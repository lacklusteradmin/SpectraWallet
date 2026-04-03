import Foundation
import WalletCore

enum CardanoWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Cardano")
        case .invalidAmount:
            return CommonLocalization.invalidAmount("Cardano")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Cardano")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("Cardano", message: message)
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("Cardano", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Cardano", message: message)
        }
    }
}

struct CardanoSendPreview: Equatable {
    let estimatedNetworkFeeADA: Double
    let ttlSlot: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct CardanoSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeADA: Double
    let signedTransactionCBORHex: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum CardanoWalletEngine {
    private static let endpointReliabilityNamespace = "cardano.koios"
    private static let estimatedTransferBytes = 320

    private struct RPCAddressUTXO {
        let txHash: String
        let txIndex: UInt64
        let amountLovelace: UInt64
    }

    private struct TipResult {
        let absSlot: UInt64
    }

    private struct EpochFeeParameters {
        let minFeeA: UInt64
        let minFeeB: UInt64
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        try derivedAddress(
            for: seedPhrase,
            derivationPath: "m/1852'/1815'/\(account)'/0/0"
        )
    }

    static func derivedAddress(for seedPhrase: String, derivationPath: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .cardano,
            derivationPath: derivationPath
        )
        guard AddressValidation.isValidCardanoAddress(material.address) else {
            throw CardanoWalletEngineError.invalidSeedPhrase
        }
        return material.address
    }

    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> CardanoSendPreview {
        guard AddressValidation.isValidCardanoAddress(ownerAddress),
              AddressValidation.isValidCardanoAddress(destinationAddress) else {
            throw CardanoWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let tip = try await fetchTip()
        let balanceADA = try await CardanoBalanceService.fetchBalance(for: ownerAddress)
        let estimatedNetworkFeeADA = try await fetchEstimatedNetworkFeeADA()
        let maxSendable = max(0, balanceADA - estimatedNetworkFeeADA)
        return CardanoSendPreview(
            estimatedNetworkFeeADA: estimatedNetworkFeeADA,
            ttlSlot: tip.absSlot + 7_200,
            spendableBalance: maxSendable,
            feeRateDescription: "Live protocol parameters",
            estimatedTransactionBytes: estimatedTransferBytes,
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
        derivationPath: String = "m/1852'/1815'/0'/0/0",
        providerIDs: Set<String>? = nil
    ) async throws -> CardanoSendResult {
        guard AddressValidation.isValidCardanoAddress(ownerAddress),
              AddressValidation.isValidCardanoAddress(destinationAddress) else {
            throw CardanoWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .cardano,
            derivationPath: derivationPath
        )
        guard !material.privateKeyData.isEmpty else {
            throw CardanoWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw CardanoWalletEngineError.invalidAddress
        }

        let amountLovelace = try scaledSignedAmount(amount, decimals: 6)
        guard amountLovelace > 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let utxos = try await fetchAddressUTXOs(address: ownerAddress)
        guard !utxos.isEmpty else {
            throw CardanoWalletEngineError.networkError("No spendable UTXOs found for this Cardano address.")
        }

        let tip = try await fetchTip()
        let ttl = tip.absSlot + 7_200

        var input = CardanoSigningInput()
        input.privateKey = [material.privateKeyData]
        input.ttl = ttl

        var transfer = CardanoTransfer()
        transfer.toAddress = destinationAddress
        transfer.changeAddress = ownerAddress
        transfer.amount = UInt64(amountLovelace)
        input.transferMessage = transfer

        input.utxos = utxos.compactMap { item in
            guard let txHashData = Data(hexString: item.txHash) else { return nil }
            var outPoint = CardanoOutPoint()
            outPoint.txHash = txHashData
            outPoint.outputIndex = item.txIndex

            var txInput = CardanoTxInput()
            txInput.outPoint = outPoint
            txInput.address = ownerAddress
            txInput.amount = item.amountLovelace
            return txInput
        }

        if input.utxos.isEmpty {
            throw CardanoWalletEngineError.networkError("Unable to parse Cardano UTXOs for signing.")
        }

        let output: CardanoSigningOutput = AnySigner.sign(input: input, coin: .cardano)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned \(output.error.rawValue)." : output.errorMessage
            throw CardanoWalletEngineError.signingFailed(message)
        }
        guard !output.encoded.isEmpty else {
            throw CardanoWalletEngineError.signingFailed("WalletCore returned empty transaction payload.")
        }

        let txHashData = output.txID
        let txHashHex = txHashData.hexEncodedString()
        guard !txHashHex.isEmpty else {
            throw CardanoWalletEngineError.signingFailed("Missing transaction hash from signing output.")
        }

        try await submitTransactionCBOR(
            cbor: output.encoded,
            fallbackTransactionHash: txHashHex,
            providerIDs: providerIDs
        )

        let estimatedNetworkFeeADA = try await fetchEstimatedNetworkFeeADA()

        return CardanoSendResult(
            transactionHash: txHashHex,
            estimatedNetworkFeeADA: estimatedNetworkFeeADA,
            signedTransactionCBORHex: output.encoded.hexEncodedString(),
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: ownerAddress, transactionHash: txHashHex)
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionCBORHex: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> CardanoSendResult {
        let normalized = signedTransactionCBORHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cbor = Data(hexEncoded: normalized), !cbor.isEmpty else {
            throw CardanoWalletEngineError.signingFailed("Invalid signed Cardano transaction payload.")
        }
        guard let fallbackTransactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fallbackTransactionHash.isEmpty else {
            throw CardanoWalletEngineError.signingFailed("Missing prior Cardano transaction hash for rebroadcast recovery.")
        }
        try await submitTransactionCBOR(cbor: cbor, fallbackTransactionHash: fallbackTransactionHash, providerIDs: providerIDs)
        return CardanoSendResult(
            transactionHash: fallbackTransactionHash,
            estimatedNetworkFeeADA: 0,
            signedTransactionCBORHex: normalized,
            verificationStatus: await CardanoBalanceService.verifyTransactionIfAvailable(fallbackTransactionHash)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        await CardanoBalanceService.verifyTransactionIfAvailable(transactionHash)
    }

    private static func fetchTip() async throws -> TipResult {
        var lastError: Error?
        for endpoint in orderedKoiosBaseURLs() {
            let url = endpoint.appendingPathComponent("tip")
            var request = URLRequest(url: url)
            request.timeoutInterval = 20

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await ProviderHTTP.sessionData(for: request)
            } catch {
                lastError = CardanoWalletEngineError.networkError(error.localizedDescription)
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                continue
            }
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = CardanoWalletEngineError.networkError("HTTP \(code)")
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                continue
            }

            guard let rows = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
                  let first = rows.first else {
                lastError = CardanoWalletEngineError.networkError("Invalid /tip response payload.")
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                continue
            }

            if let absSlot = first["abs_slot"] as? UInt64 {
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                return TipResult(absSlot: absSlot)
            }
            if let absSlotInt = first["abs_slot"] as? Int {
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                return TipResult(absSlot: UInt64(max(0, absSlotInt)))
            }
            if let absSlotString = first["abs_slot"] as? String,
               let absSlot = UInt64(absSlotString) {
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                return TipResult(absSlot: absSlot)
            }

            lastError = CardanoWalletEngineError.networkError("Missing abs_slot in /tip response.")
            ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
        }
        throw lastError ?? CardanoWalletEngineError.networkError("Missing abs_slot in /tip response.")
    }

    private static func fetchEstimatedNetworkFeeADA() async throws -> Double {
        let parameters = try await fetchEpochFeeParameters()
        let estimatedFeeLovelace = parameters.minFeeB + (parameters.minFeeA * UInt64(estimatedTransferBytes))
        return Double(estimatedFeeLovelace) / 1_000_000.0
    }

    private static func fetchEpochFeeParameters() async throws -> EpochFeeParameters {
        var lastError: Error?
        for endpoint in orderedKoiosBaseURLs() {
            guard var components = URLComponents(url: endpoint.appendingPathComponent("epoch_params"), resolvingAgainstBaseURL: false) else {
                continue
            }
            components.queryItems = [
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "order", value: "epoch_no.desc")
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20

            do {
                let (data, response) = try await ProviderHTTP.sessionData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw CardanoWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                guard let rows = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
                      let row = rows.first,
                      let minFeeA = unsignedIntegerValue(row["min_fee_a"]),
                      let minFeeB = unsignedIntegerValue(row["min_fee_b"]) else {
                    throw CardanoWalletEngineError.networkError("Missing Cardano epoch fee parameters.")
                }
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                return EpochFeeParameters(minFeeA: minFeeA, minFeeB: minFeeB)
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
            }
        }
        throw lastError ?? CardanoWalletEngineError.networkError("Missing Cardano epoch fee parameters.")
    }

    private static func unsignedIntegerValue(_ raw: Any?) -> UInt64? {
        switch raw {
        case let number as NSNumber:
            return number.uint64Value
        case let string as String:
            return UInt64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func fetchAddressUTXOs(address: String) async throws -> [RPCAddressUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw CardanoWalletEngineError.networkError("Invalid Cardano UTXO endpoint URL.")
        }
        var lastError: Error?
        for endpoint in orderedKoiosBaseURLs() {
            guard let url = URL(string: "\(endpoint.absoluteString)/address_utxos?_address=eq.\(encodedAddress)") else {
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await ProviderHTTP.sessionData(for: request)
            } catch {
                lastError = CardanoWalletEngineError.networkError(error.localizedDescription)
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                continue
            }
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = CardanoWalletEngineError.networkError("HTTP \(code)")
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                continue
            }

            guard let rows = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                lastError = CardanoWalletEngineError.networkError("Invalid Cardano UTXO response payload.")
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                continue
            }

            let utxos: [RPCAddressUTXO] = rows.compactMap { row in
                guard let txHash = row["tx_hash"] as? String,
                      !txHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                let txIndex: UInt64 = {
                    if let value = row["tx_index"] as? UInt64 { return value }
                    if let value = row["tx_index"] as? Int { return UInt64(max(0, value)) }
                    if let value = row["tx_index"] as? String, let parsed = UInt64(value) { return parsed }
                    return 0
                }()

                let lovelace: UInt64? = {
                    if let value = row["value"] as? UInt64 { return value }
                    if let value = row["value"] as? Int { return UInt64(max(0, value)) }
                    if let value = row["value"] as? String { return UInt64(value) }
                    return nil
                }()

                guard let amount = lovelace, amount > 0 else { return nil }
                return RPCAddressUTXO(txHash: txHash, txIndex: txIndex, amountLovelace: amount)
            }
            ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
            return utxos
        }
        throw lastError ?? CardanoWalletEngineError.networkError("Invalid Cardano UTXO response payload.")
    }

    private static func submitTransactionCBOR(
        cbor: Data,
        fallbackTransactionHash: String,
        providerIDs: Set<String>? = nil
    ) async throws {
        let attempts = 2
        var lastError: Error?

        for endpoint in orderedKoiosBaseURLs(providerIDs: providerIDs) {
            let url = endpoint.appendingPathComponent("submittx")
            for _ in 0 ..< attempts {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 20
                request.setValue("application/cbor", forHTTPHeaderField: "Content-Type")
                request.httpBody = cbor

                let (data, response): (Data, URLResponse)
                do {
                    (data, response) = try await ProviderHTTP.sessionData(for: request)
                } catch {
                    let disposition = classifySendBroadcastFailure(error.localizedDescription)
                    if disposition == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                        ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                        return
                    }
                    lastError = CardanoWalletEngineError.broadcastFailed(error.localizedDescription)
                    ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                    if disposition != .retryable {
                        break
                    }
                    continue
                }

                guard let http = response as? HTTPURLResponse else {
                    lastError = CardanoWalletEngineError.broadcastFailed("Missing HTTP response from Cardano submit endpoint.")
                    ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                    break
                }

                guard (200 ... 299).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    let message = "HTTP \(http.statusCode) \(body)"
                    let disposition = classifySendBroadcastFailure(message)
                    if disposition == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                        ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                        return
                    }
                    lastError = CardanoWalletEngineError.broadcastFailed(message)
                    ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
                    if disposition != .retryable {
                        break
                    }
                    continue
                }

                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                return
            }
        }

        throw lastError ?? CardanoWalletEngineError.broadcastFailed("Cardano submit failed.")
    }

    private static func orderedKoiosBaseURLs(providerIDs: Set<String>? = nil) -> [URL] {
        let ordered = ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: filteredKoiosBaseURLs(providerIDs: providerIDs)
        )
        return ordered.compactMap(URL.init(string:))
    }

    private static func filteredKoiosBaseURLs(providerIDs: Set<String>? = nil) -> [String] {
        let candidates = ChainBackendRegistry.CardanoRuntimeEndpoints.koiosBaseURLs
        guard let providerIDs, !providerIDs.isEmpty else { return candidates }
        return candidates.filter { endpoint in
            switch endpoint {
            case "https://api.koios.rest/api/v1":
                return providerIDs.contains("koios")
            case "https://graph.xray.app/output/services/koios/mainnet/api/v1":
                return providerIDs.contains("xray-koios")
            case "https://koios.happystaking.io:8453/api/v1":
                return providerIDs.contains("happystaking-koios")
            default:
                return false
            }
        }
    }

    private static func scaledSignedAmount(_ amount: Double, decimals: Int) throws -> Int64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        guard rounded != NSDecimalNumber.notANumber,
              rounded.compare(NSDecimalNumber.zero) == .orderedDescending else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let maxValue = NSDecimalNumber(value: Int64.max)
        guard rounded.compare(maxValue) != .orderedDescending else {
            throw CardanoWalletEngineError.invalidAmount
        }

        let value = rounded.int64Value
        guard value > 0 else {
            throw CardanoWalletEngineError.invalidAmount
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

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }

    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
