import Foundation
import SwiftProtobuf
import WalletCore

enum AptosWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case insufficientBalance
    case networkError(String)
    case signingFailed(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Aptos")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Aptos")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Aptos")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Aptos")
        case .insufficientBalance:
            return NSLocalizedString("Insufficient APT balance to cover amount and network fee.", comment: "")
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("Aptos", message: message)
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("Aptos", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Aptos", message: message)
        }
    }
}

struct AptosSendPreview: Equatable {
    let estimatedNetworkFeeAPT: Double
    let maxGasAmount: UInt64
    let gasUnitPriceOctas: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct AptosSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeAPT: Double
    let signedTransactionJSON: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum AptosWalletEngine {
    private static let chainID: UInt64 = 1
    private static let defaultMaxGasAmount: UInt64 = 2_000
    private static let expirationWindowSeconds: UInt64 = 600
    private static let endpointReliabilityNamespace = "aptos.rpc"

    private struct GasEstimate: Decodable {
        let gasEstimate: String?

        enum CodingKeys: String, CodingKey {
            case gasEstimate = "gas_estimate"
        }
    }

    private struct AccountSnapshot: Decodable {
        let sequenceNumber: String?

        enum CodingKeys: String, CodingKey {
            case sequenceNumber = "sequence_number"
        }
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .aptos,
            derivationPath: "m/44'/637'/\(account)'/0'/0'"
        )
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidAptosAddress(normalized) else {
            throw AptosWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .aptos)
        let normalized = normalizeAddress(material.address)
        guard AddressValidation.isValidAptosAddress(normalized) else {
            throw AptosWalletEngineError.invalidAddress
        }
        return normalized
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> AptosSendPreview {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidAptosAddress(normalizedOwner),
              AddressValidation.isValidAptosAddress(normalizedDestination) else {
            throw AptosWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw AptosWalletEngineError.invalidAmount
        }

        let gasUnitPrice = try await fetchGasUnitPrice()
        let estimatedFee = Double(defaultMaxGasAmount * gasUnitPrice) / 100_000_000.0
        let balanceAPT = try await AptosBalanceService.fetchBalance(for: normalizedOwner)
        let maxSendable = max(0, balanceAPT - estimatedFee)
        return AptosSendPreview(
            estimatedNetworkFeeAPT: estimatedFee,
            maxGasAmount: defaultMaxGasAmount,
            gasUnitPriceOctas: gasUnitPrice,
            spendableBalance: maxSendable,
            feeRateDescription: "\(gasUnitPrice) octas/unit",
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
    ) async throws -> AptosSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidAptosAddress(normalizedOwner),
              AddressValidation.isValidAptosAddress(normalizedDestination) else {
            throw AptosWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw AptosWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: normalizedOwner, to: normalizedDestination, amount: amount)
        let amountOctas = try scaledUnsignedAmount(amount, decimals: 8)
        let balanceAPT = try await AptosBalanceService.fetchBalance(for: normalizedOwner)
        guard balanceAPT + 0.00000001 >= amount + preview.estimatedNetworkFeeAPT else {
            throw AptosWalletEngineError.insufficientBalance
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .aptos,
            derivationPath: "m/44'/637'/\(derivationAccount)'/0'/0'"
        )
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw AptosWalletEngineError.invalidAddress
        }

        let sequenceNumber = try await fetchSequenceNumber(for: normalizedOwner)
        let expiration = UInt64(Date().timeIntervalSince1970) + expirationWindowSeconds

        let input = AptosSigningInput.with {
            $0.privateKey = material.privateKeyData
            $0.sender = normalizedOwner
            $0.sequenceNumber = Int64(sequenceNumber)
            $0.maxGasAmount = preview.maxGasAmount
            $0.gasUnitPrice = preview.gasUnitPriceOctas
            $0.expirationTimestampSecs = expiration
            $0.chainID = UInt32(chainID)
            $0.transfer = AptosTransferMessage.with {
                $0.to = normalizedDestination
                $0.amount = amountOctas
            }
        }

        let output: AptosSigningOutput = AnySigner.sign(input: input, coin: .aptos)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw AptosWalletEngineError.signingFailed(message)
        }
        guard !output.json.isEmpty else {
            throw AptosWalletEngineError.signingFailed("WalletCore returned empty Aptos transaction JSON.")
        }

        let digest: String
        do {
            digest = try await submitTransaction(jsonPayload: output.json, providerIDs: providerIDs)
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: normalizedOwner,
                      destinationAddress: normalizedDestination,
                      amount: amount
                  ) else {
                throw error
            }
            digest = recoveredHash
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(transactionHash: digest)
        return AptosSendResult(
            transactionHash: digest,
            estimatedNetworkFeeAPT: preview.estimatedNetworkFeeAPT,
            signedTransactionJSON: output.json,
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionJSON: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> AptosSendResult {
        let digest = try await submitTransaction(jsonPayload: signedTransactionJSON, providerIDs: providerIDs)
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : digest
        return AptosSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeAPT: 0,
            signedTransactionJSON: signedTransactionJSON,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(transactionHash: transactionHash)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(transactionHash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else { return .deferred }

        var lastError: Error?
        for attempt in 0 ..< 3 {
            for endpoint in AptosBalanceService.endpointCatalog() {
                do {
                    guard let url = URL(string: endpoint)?.appendingPathComponent("transactions/by_hash/\(normalizedHash)") else {
                        continue
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    let result: AptosProvider.TransactionLookupResponse = try await get(request)
                    if result.success == false {
                        return .failed(result.vmStatus ?? "Aptos transaction execution failed.")
                    }
                    if result.hash?.caseInsensitiveCompare(normalizedHash) == .orderedSame || result.success == true {
                        return .verified
                    }
                } catch let error as AptosWalletEngineError {
                    if case .networkError(let message) = error, message.contains("HTTP 404") {
                        continue
                    }
                    lastError = error
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

    private static func fetchGasUnitPrice() async throws -> UInt64 {
        var lastError: Error?
        for endpoint in orderedRPCEndpoints() {
            do {
                var request = URLRequest(url: endpoint.appendingPathComponent("estimate_gas_price"))
                request.httpMethod = "GET"
                let result: GasEstimate = try await get(request)
                guard let value = result.gasEstimate, let parsed = UInt64(value), parsed > 0 else {
                    throw AptosWalletEngineError.invalidResponse
                }
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                return parsed
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
            }
        }
        throw lastError ?? AptosWalletEngineError.invalidResponse
    }

    private static func fetchSequenceNumber(for address: String) async throws -> UInt64 {
        var lastError: Error?
        for endpoint in orderedRPCEndpoints() {
            do {
                var request = URLRequest(url: endpoint.appendingPathComponent("accounts/\(address)"))
                request.httpMethod = "GET"
                let result: AccountSnapshot = try await get(request)
                guard let value = result.sequenceNumber, let parsed = UInt64(value) else {
                    throw AptosWalletEngineError.invalidResponse
                }
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                return parsed
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
            }
        }
        throw lastError ?? AptosWalletEngineError.invalidResponse
    }

    private static func submitTransaction(jsonPayload: String, providerIDs: Set<String>? = nil) async throws -> String {
        guard let data = jsonPayload.data(using: .utf8) else {
            throw AptosWalletEngineError.signingFailed("WalletCore returned non-UTF8 Aptos transaction JSON.")
        }
        var lastError: Error?
        for endpoint in orderedRPCEndpoints(providerIDs: providerIDs) {
            for attempt in 0 ..< 2 {
                do {
                    var request = URLRequest(url: endpoint.appendingPathComponent("transactions"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 20
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = data

                    let result: AptosProvider.SubmitResponse = try await send(request)
                    guard let hash = result.hash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty else {
                        throw AptosWalletEngineError.broadcastFailed("Missing Aptos transaction hash from submit response.")
                    }
                    ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                    return hash
                } catch {
                    lastError = error
                    ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                    if attempt < 1, classifySendBroadcastFailure(error.localizedDescription) == .retryable {
                        continue
                    }
                    break
                }
            }
        }
        throw lastError ?? AptosWalletEngineError.broadcastFailed("Aptos transaction submission failed.")
    }

    private static func orderedRPCEndpoints(providerIDs: Set<String>? = nil) -> [URL] {
        let ordered = ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: filteredRPCEndpoints(providerIDs: providerIDs)
        )
        return ordered.compactMap(URL.init(string:))
    }

    private static func filteredRPCEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        let candidates = AptosBalanceService.endpointCatalog()
        guard let providerIDs, !providerIDs.isEmpty else { return candidates }
        return candidates.filter { endpoint in
            switch endpoint {
            case "https://api.mainnet.aptoslabs.com/v1":
                return providerIDs.contains("aptoslabs-api")
            case "https://aptos-mainnet.public.blastapi.io/v1":
                return providerIDs.contains("blastapi-aptos")
            case "https://mainnet.aptoslabs.com/v1":
                return providerIDs.contains("aptoslabs-mainnet")
            default:
                return false
            }
        }
    }

    private static func recoverRecentTransactionHashIfAvailable(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async -> String? {
        let result = await AptosBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        return result.snapshots.first {
            $0.kind == .send
                && abs($0.amount - amount) < 0.00000001
                && normalizeAddress($0.counterpartyAddress) == normalizeAddress(destinationAddress)
        }?.transactionHash
    }

    private static func get<ResultType: Decodable>(_ request: URLRequest) async throws -> ResultType {
        do {
            let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw AptosWalletEngineError.networkError("HTTP \(code)")
            }
            return try JSONDecoder().decode(ResultType.self, from: data)
        } catch let error as AptosWalletEngineError {
            throw error
        } catch {
            throw AptosWalletEngineError.networkError(error.localizedDescription)
        }
    }

    private static func send<ResultType: Decodable>(_ request: URLRequest) async throws -> ResultType {
        do {
            let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainWrite)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw AptosWalletEngineError.broadcastFailed("HTTP \(code)")
            }
            return try JSONDecoder().decode(ResultType.self, from: data)
        } catch let error as AptosWalletEngineError {
            throw error
        } catch {
            throw AptosWalletEngineError.broadcastFailed(error.localizedDescription)
        }
    }

    private static func normalizeAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("0x") ? trimmed : "0x\(trimmed)"
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw AptosWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base).rounding(accordingToBehavior: nil)
        if scaled == NSDecimalNumber.notANumber || scaled.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw AptosWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard scaled.compare(maxValue) != .orderedDescending else {
            throw AptosWalletEngineError.invalidAmount
        }
        let value = scaled.uint64Value
        guard value > 0 else {
            throw AptosWalletEngineError.invalidAmount
        }
        return value
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var result = Decimal(1)
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }
}
