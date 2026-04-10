import Foundation
import CryptoKit
import WalletCore

enum NearWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case accessKeyUnavailable
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("NEAR")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("NEAR")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("NEAR")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("NEAR")
        case .accessKeyUnavailable:
            return AppLocalization.string("No full-access NEAR key was found for this account.")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("NEAR", message: message)
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("NEAR", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("NEAR", message: message)
        }
    }
}

struct NearSendPreview: Equatable {
    let estimatedNetworkFeeNEAR: Double
    let gasPriceYoctoNear: String
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct NearSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeNEAR: Double
    let signedTransactionBase64: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum NearWalletEngine {
    private static let yoctoMultiplier = Decimal(string: "1000000000000000000000000")!
    private static let defaultGasPriceYocto = Decimal(string: "100000000")!
    private static let estimatedTransferGasUnits = Decimal(string: "450000000000")!
    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private struct NearTransaction {
        let signerID: String
        let publicKey: Data
        let nonce: UInt64
        let receiverID: String
        let blockHash: Data
        let depositYocto: String
    }

    private struct BroadcastOutcome {
        let transactionHash: String
        let isCommitted: Bool
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        do {
            return try SeedPhraseAddressDerivation.address(
                for: seedPhrase,
                coin: .near,
                derivationPath: "m/44'/397'/\(account)'",
                normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() },
                validator: AddressValidation.isValidNearAddress
            )
        } catch {
            throw NearWalletEngineError.invalidSeedPhrase
        }
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> NearSendPreview {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidNearAddress(normalizedOwner),
              AddressValidation.isValidNearAddress(normalizedDestination) else {
            throw NearWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw NearWalletEngineError.invalidAmount
        }

        let gasPriceYocto = try await fetchGasPriceYocto()
        let estimatedFeeYocto = gasPriceYocto * estimatedTransferGasUnits
        let estimatedFeeNEAR = decimalToDouble(estimatedFeeYocto / yoctoMultiplier)
        let balanceNEAR = try await NearBalanceService.fetchBalance(for: normalizedOwner)
        let maxSendable = max(0, balanceNEAR - estimatedFeeNEAR)
        return NearSendPreview(
            estimatedNetworkFeeNEAR: estimatedFeeNEAR,
            gasPriceYoctoNear: NSDecimalNumber(decimal: gasPriceYocto).stringValue,
            spendableBalance: maxSendable,
            feeRateDescription: NSDecimalNumber(decimal: gasPriceYocto).stringValue,
            estimatedTransactionBytes: nil,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: maxSendable
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationAccount: UInt32 = 0,
        providerIDs: Set<String>? = nil
    ) async throws -> NearSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidNearAddress(normalizedOwner),
              AddressValidation.isValidNearAddress(normalizedDestination) else {
            throw NearWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw NearWalletEngineError.invalidAmount
        }

        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: seedPhrase,
            coin: .near,
            derivationPath: "m/44'/397'/\(derivationAccount)'"
        )
        guard !material.privateKeyData.isEmpty else {
            throw NearWalletEngineError.invalidSeedPhrase
        }
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw NearWalletEngineError.invalidAddress
        }

        let privateKey = try privateKey(from: material.privateKeyData)
        let publicKey = privateKey.getPublicKeyEd25519().data
        let publicKeyString = "ed25519:\(base58Encode(publicKey))"
        let accessKey = try await fetchAccessKey(accountID: normalizedOwner, publicKey: publicKeyString)
        let blockHash = try base58Decode(accessKey.blockHash)
        guard blockHash.count == 32 else {
            throw NearWalletEngineError.invalidResponse
        }

        let depositYocto = try scaledWholeNumberString(amount, decimals: 24)
        let transaction = NearTransaction(
            signerID: normalizedOwner,
            publicKey: publicKey,
            nonce: accessKey.nonce + 1,
            receiverID: normalizedDestination,
            blockHash: blockHash,
            depositYocto: depositYocto
        )
        let serializedTransaction = try serialize(transaction: transaction)
        let digest = Data(SHA256.hash(data: serializedTransaction))
        guard let signature = privateKey.sign(digest: digest, curve: .ed25519) else {
            throw NearWalletEngineError.signingFailed("WalletCore returned an empty Ed25519 signature.")
        }

        let signedTransaction = try serializeSignedTransaction(transaction: transaction, signature: signature)
        let broadcastOutcome: BroadcastOutcome
        do {
            broadcastOutcome = try await broadcastSignedTransaction(signedTransaction, providerIDs: providerIDs)
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: normalizedOwner,
                      destinationAddress: normalizedDestination,
                      amount: amount
                  ) else {
                throw error
            }
            broadcastOutcome = BroadcastOutcome(transactionHash: recoveredHash, isCommitted: false)
        }
        let preview = try await estimateSendPreview(
            from: normalizedOwner,
            to: normalizedDestination,
            amount: amount
        )
        return NearSendResult(
            transactionHash: broadcastOutcome.transactionHash,
            estimatedNetworkFeeNEAR: preview.estimatedNetworkFeeNEAR,
            signedTransactionBase64: signedTransaction.base64EncodedString(),
            verificationStatus: broadcastOutcome.isCommitted
                ? .verified
                : await verifyBroadcastedTransactionIfAvailable(
                    ownerAddress: normalizedOwner,
                    transactionHash: broadcastOutcome.transactionHash
                )
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionBase64: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> NearSendResult {
        let normalizedPayload = signedTransactionBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPayload.isEmpty,
              let signedTransaction = Data(base64Encoded: normalizedPayload),
              !signedTransaction.isEmpty else {
            throw NearWalletEngineError.invalidResponse
        }
        let broadcastOutcome = try await broadcastSignedTransaction(signedTransaction, providerIDs: providerIDs)
        let recoveredHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : broadcastOutcome.transactionHash
        return NearSendResult(
            transactionHash: recoveredHash,
            estimatedNetworkFeeNEAR: 0,
            signedTransactionBase64: normalizedPayload,
            verificationStatus: broadcastOutcome.isCommitted ? .verified : .deferred
        )
    }

    private static func fetchAccessKey(accountID: String, publicKey: String) async throws -> NearProvider.AccessKeyResult {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "spectra-near-access-key",
            "method": "query",
            "params": [
                "request_type": "view_access_key",
                "finality": "final",
                "account_id": accountID,
                "public_key": publicKey
            ]
        ]

        var lastError: Error?
        for endpoint in NearProvider.orderedRPCEndpoints() {
            do {
                let result: NearProvider.AccessKeyResult = try await postRPC(payload: payload, endpoint: endpoint)
                ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                return result
            } catch let error as NearWalletEngineError {
                if case .broadcastFailed(let message) = error,
                   message.localizedCaseInsensitiveContains("does not exist") {
                    throw NearWalletEngineError.accessKeyUnavailable
                }
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
            }
        }
        throw lastError ?? NearWalletEngineError.accessKeyUnavailable
    }

    private static func fetchGasPriceYocto() async throws -> Decimal {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "spectra-near-gas-price",
            "method": "gas_price",
            "params": [NSNull()]
        ]

        for endpoint in NearProvider.orderedRPCEndpoints() {
            do {
                let result: NearProvider.GasPriceResult = try await postRPC(payload: payload, endpoint: endpoint)
                if let decimal = Decimal(string: result.gasPrice) {
                    ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                    return decimal
                }
            } catch {
                ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
                continue
            }
        }
        return defaultGasPriceYocto
    }

    private static func broadcastSignedTransaction(_ payload: Data, providerIDs: Set<String>? = nil) async throws -> BroadcastOutcome {
        let encodedTransaction = payload.base64EncodedString()
        let fallbackHash = signedTransactionHash(payload)
        let requestPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "spectra-near-broadcast",
            "method": "broadcast_tx_commit",
            "params": [encodedTransaction]
        ]

        var lastError: Error?
        for endpoint in NearProvider.orderedRPCEndpoints(providerIDs: providerIDs) {
            guard let url = URL(string: endpoint) else { continue }
            for attempt in 0 ..< 2 {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 30
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestPayload, options: [])

                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainWrite)
                    guard let http = response as? HTTPURLResponse else {
                        throw NearWalletEngineError.invalidResponse
                    }
                    guard (200 ... 299).contains(http.statusCode) else {
                        throw NearWalletEngineError.networkError("NEAR RPC returned HTTP \(http.statusCode).")
                    }

                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw NearWalletEngineError.invalidResponse
                    }
                    if let error = root["error"] as? [String: Any] {
                        let message = (error["message"] as? String)
                            ?? ((error["cause"] as? [String: Any])?["info"] as? String)
                            ?? "Unknown NEAR RPC error."
                        let failure = NearWalletEngineError.broadcastFailed(message)
                        if classifySendBroadcastFailure(message) == .alreadyBroadcast {
                            return BroadcastOutcome(transactionHash: fallbackHash, isCommitted: false)
                        }
                        throw failure
                    }
                    guard let result = root["result"] as? [String: Any] else {
                        throw NearWalletEngineError.invalidResponse
                    }
                    if let status = result["status"] as? [String: Any],
                       let failure = status["Failure"] {
                        let message = String(describing: failure)
                        if classifySendBroadcastFailure(message) == .alreadyBroadcast {
                            return BroadcastOutcome(transactionHash: fallbackHash, isCommitted: false)
                        }
                        throw NearWalletEngineError.broadcastFailed(message)
                    }
                    if let transaction = result["transaction"] as? [String: Any],
                       let hash = transaction["hash"] as? String,
                       !hash.isEmpty {
                        ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                        return BroadcastOutcome(transactionHash: hash, isCommitted: true)
                    }
                    if let outcome = result["transaction_outcome"] as? [String: Any],
                       let id = outcome["id"] as? String,
                       !id.isEmpty {
                        ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                        return BroadcastOutcome(transactionHash: id, isCommitted: true)
                    }
                    throw NearWalletEngineError.invalidResponse
                } catch {
                    lastError = error
                    ChainEndpointReliability.recordAttempt(namespace: NearProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
                    if attempt < 1, classifySendBroadcastFailure(error.localizedDescription) == .retryable {
                        continue
                    }
                    break
                }
            }
        }
        throw lastError ?? NearWalletEngineError.broadcastFailed("All NEAR broadcast endpoints failed.")
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHash.isEmpty else { return .deferred }
        var lastError: Error?

        for attempt in 0 ..< 3 {
            for endpoint in NearProvider.orderedRPCEndpoints() {
                do {
                    var request = URLRequest(url: URL(string: endpoint)!)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 20
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(
                        withJSONObject: [
                            "jsonrpc": "2.0",
                            "id": "spectra-near-verify",
                            "method": "tx",
                            "params": [normalizedHash, ownerAddress]
                        ],
                        options: []
                    )

                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                        throw NearWalletEngineError.networkError("NEAR RPC returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1).")
                    }
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw NearWalletEngineError.invalidResponse
                    }
                    if let error = root["error"] as? [String: Any] {
                        let message = (error["message"] as? String)
                            ?? ((error["cause"] as? [String: Any])?["info"] as? String)
                            ?? "Unknown NEAR RPC error."
                        if message.uppercased().contains("UNKNOWN_TRANSACTION") || message.uppercased().contains("UNKNOWN_TX") {
                            continue
                        }
                        throw NearWalletEngineError.broadcastFailed(message)
                    }
                    if let result = root["result"] as? [String: Any] {
                        if let transaction = result["transaction"] as? [String: Any],
                           let hash = transaction["hash"] as? String,
                           hash.caseInsensitiveCompare(normalizedHash) == .orderedSame {
                            return .verified
                        }
                        if let outcome = result["transaction_outcome"] as? [String: Any],
                           let id = outcome["id"] as? String,
                           id.caseInsensitiveCompare(normalizedHash) == .orderedSame {
                            return .verified
                        }
                    }
                } catch {
                    lastError = error
                }
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func recoverRecentTransactionHashIfAvailable(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async -> String? {
        let result = await NearBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        return result.snapshots.first {
            $0.kind == .send
                && abs($0.amount - amount) < 0.000000000001
                && $0.counterpartyAddress.lowercased() == destinationAddress.lowercased()
        }?.transactionHash
    }

    private static func signedTransactionHash(_ payload: Data) -> String {
        let digest = Data(SHA256.hash(data: payload))
        return base58Encode(digest)
    }

    private static func postRPC<ResultType: Decodable>(payload: [String: Any], endpoint: String) async throws -> ResultType {
        guard let url = URL(string: endpoint) else {
            throw NearWalletEngineError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
        guard let http = response as? HTTPURLResponse else {
            throw NearWalletEngineError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw NearWalletEngineError.networkError("NEAR RPC returned HTTP \(http.statusCode).")
        }

        let envelope = try JSONDecoder().decode(NearProvider.RPCEnvelope<ResultType>.self, from: data)
        if let error = envelope.error {
            let message = error.message ?? error.cause?.info ?? error.name ?? "Unknown NEAR RPC error"
            throw NearWalletEngineError.broadcastFailed(message)
        }
        guard let result = envelope.result else {
            throw NearWalletEngineError.invalidResponse
        }
        return result
    }

    private static func serialize(transaction: NearTransaction) throws -> Data {
        var data = Data()
        data.appendBorshString(transaction.signerID)
        data.append(UInt8(0))
        data.append(transaction.publicKey)
        data.appendLittleEndian(transaction.nonce)
        data.appendBorshString(transaction.receiverID)
        data.append(transaction.blockHash)
        data.appendLittleEndian(UInt32(1))
        data.append(UInt8(3))
        data.append(try encodeUInt128LE(decimalString: transaction.depositYocto))
        return data
    }

    private static func serializeSignedTransaction(transaction: NearTransaction, signature: Data) throws -> Data {
        guard signature.count == 64 else {
            throw NearWalletEngineError.signingFailed("Unexpected Ed25519 signature length.")
        }
        var data = try serialize(transaction: transaction)
        data.append(UInt8(0))
        data.append(signature)
        return data
    }

    private static func privateKey(from data: Data) throws -> PrivateKey {
        guard let key = PrivateKey(data: data) else {
            throw NearWalletEngineError.invalidSeedPhrase
        }
        return key
    }

    private static func scaledWholeNumberString(_ amount: Double, decimals: Int) throws -> String {
        guard amount > 0 else {
            throw NearWalletEngineError.invalidAmount
        }
        var decimalAmount = Decimal(amount)
        var multiplier = Decimal(1)
        for _ in 0 ..< decimals {
            multiplier *= 10
        }
        decimalAmount *= multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimalAmount, 0, .plain)
        let numberString = NSDecimalNumber(decimal: rounded).stringValue
        guard numberString != "nan", !numberString.hasPrefix("-") else {
            throw NearWalletEngineError.invalidAmount
        }
        return numberString
    }

    private static func encodeUInt128LE(decimalString: String) throws -> Data {
        let trimmed = decimalString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(\.isNumber) else {
            throw NearWalletEngineError.invalidAmount
        }
        if trimmed == "0" {
            return Data(repeating: 0, count: 16)
        }

        var digits = trimmed.compactMap { $0.wholeNumberValue }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        while !digits.isEmpty {
            var quotient: [Int] = []
            quotient.reserveCapacity(digits.count)
            var remainder = 0
            for digit in digits {
                let accumulator = remainder * 10 + digit
                let q = accumulator / 256
                remainder = accumulator % 256
                if !quotient.isEmpty || q != 0 {
                    quotient.append(q)
                }
            }
            bytes.append(UInt8(remainder))
            digits = quotient
        }
        guard bytes.count <= 16 else {
            throw NearWalletEngineError.invalidAmount
        }
        return Data(bytes + Array(repeating: 0, count: 16 - bytes.count))
    }

    private static func normalizeAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static func base58Encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var digits = [Int](repeating: 0, count: 1)
        for byte in data {
            var carry = Int(byte)
            for index in digits.indices {
                let value = digits[index] * 256 + carry
                digits[index] = value % 58
                carry = value / 58
            }
            while carry > 0 {
                digits.append(carry % 58)
                carry /= 58
            }
        }
        var result = String(repeating: "1", count: data.prefix(while: { $0 == 0 }).count)
        for digit in digits.reversed() {
            result.append(base58Alphabet[digit])
        }
        return result
    }

    private static func base58Decode(_ string: String) throws -> Data {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NearWalletEngineError.invalidResponse
        }

        let alphabetMap = Dictionary(uniqueKeysWithValues: base58Alphabet.enumerated().map { ($0.element, $0.offset) })
        var bytes = [UInt8](repeating: 0, count: 1)
        for character in trimmed {
            guard let value = alphabetMap[character] else {
                throw NearWalletEngineError.invalidResponse
            }
            var carry = value
            for index in bytes.indices {
                let accumulator = Int(bytes[index]) * 58 + carry
                bytes[index] = UInt8(accumulator & 0xff)
                carry = accumulator >> 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }

        let leadingZeros = trimmed.prefix(while: { $0 == "1" }).count
        let decoded = Data(repeating: 0, count: leadingZeros) + Data(bytes.reversed())
        return decoded
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendBorshString(_ string: String) {
        let utf8Data = Data(string.utf8)
        appendLittleEndian(UInt32(utf8Data.count))
        append(utf8Data)
    }
}
