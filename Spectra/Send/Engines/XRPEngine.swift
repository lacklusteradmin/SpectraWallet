import Foundation
import WalletCore
import SwiftProtobuf

enum XRPWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("XRP")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("XRP")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("XRP")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("XRP", message: message)
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("XRP", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("XRP", message: message)
        }
    }
}

struct XRPSendPreview: Equatable {
    let estimatedNetworkFeeXRP: Double
    let feeDrops: Int64
    let sequence: Int64
    let lastLedgerSequence: Int64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct XRPSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeXRP: Double
    let signedTransactionBlobHex: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum XRPWalletEngine {
    private static let minimumFeeDrops: Int64 = 10

    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> XRPSendPreview {
        guard AddressValidation.isValidXRPAddress(ownerAddress),
              AddressValidation.isValidXRPAddress(destinationAddress) else {
            throw XRPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let feeDrops = try await fetchFeeDrops()
        let accountInfo = try await fetchAccountInfo(address: ownerAddress)
        let sequence = accountInfo.accountData?.sequence ?? 0
        let currentLedger = accountInfo.ledgerCurrentIndex ?? 0
        let lastLedgerSequence = currentLedger > 0 ? currentLedger + 20 : 0
        let estimatedNetworkFeeXRP = Double(feeDrops) / 1_000_000.0
        let balanceXRP = try await XRPBalanceService.fetchBalance(for: ownerAddress)
        let maxSendable = max(0, balanceXRP - estimatedNetworkFeeXRP)

        return XRPSendPreview(
            estimatedNetworkFeeXRP: estimatedNetworkFeeXRP,
            feeDrops: feeDrops,
            sequence: sequence,
            lastLedgerSequence: lastLedgerSequence,
            spendableBalance: maxSendable,
            feeRateDescription: "\(feeDrops) drops",
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
    ) async throws -> XRPSendResult {
        guard AddressValidation.isValidXRPAddress(ownerAddress),
              AddressValidation.isValidXRPAddress(destinationAddress) else {
            throw XRPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let amountDrops = Int64((amount * 1_000_000.0).rounded(.towardZero))
        guard amountDrops > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .xrp,
            account: derivationAccount
        )
        guard !material.privateKeyData.isEmpty else {
            throw XRPWalletEngineError.invalidSeedPhrase
        }

        let operation = RippleOperationPayment.with {
            $0.destination = destinationAddress
            $0.amount = amountDrops
        }
        let sequence = UInt32(clamping: preview.sequence)
        let lastLedgerSequence = UInt32(clamping: preview.lastLedgerSequence)
        let input = RippleSigningInput.with {
            $0.fee = preview.feeDrops
            $0.sequence = sequence
            if lastLedgerSequence > 0 {
                $0.lastLedgerSequence = lastLedgerSequence
            }
            $0.account = ownerAddress
            $0.privateKey = material.privateKeyData
            $0.opPayment = operation
        }
        let output: RippleSigningOutput = AnySigner.sign(input: input, coin: .xrp)
        let txBlobHex = output.encoded.hexString
        guard !txBlobHex.isEmpty else {
            throw XRPWalletEngineError.signingFailed("WalletCore produced an empty transaction payload.")
        }

        let submit = try await submitTransaction(txBlobHex: txBlobHex, providerIDs: providerIDs)
        let resultCode = submit.engineResult ?? ""
        let txHash = submit.txJSON?.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard resultCode.hasPrefix("tes") || isAlreadyBroadcastSubmit(resultCode: resultCode, message: submit.engineResultMessage) else {
            let message = submit.engineResultMessage ?? "Engine result \(resultCode)"
            throw XRPWalletEngineError.broadcastFailed(message)
        }
        guard !txHash.isEmpty else {
            throw XRPWalletEngineError.broadcastFailed("Missing transaction hash from XRP submit response.")
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(transactionHash: txHash)

        return XRPSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeXRP: preview.estimatedNetworkFeeXRP,
            signedTransactionBlobHex: txBlobHex,
            verificationStatus: verificationStatus
        )
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .xrp)
        guard AddressValidation.isValidXRPAddress(material.address) else {
            throw XRPWalletEngineError.invalidAddress
        }
        return material.address
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        providerIDs: Set<String>? = nil
    ) async throws -> XRPSendResult {
        guard AddressValidation.isValidXRPAddress(ownerAddress),
              AddressValidation.isValidXRPAddress(destinationAddress) else {
            throw XRPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let amountDrops = Int64((amount * 1_000_000.0).rounded(.towardZero))
        guard amountDrops > 0 else {
            throw XRPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .xrp)
        guard !material.privateKeyData.isEmpty else {
            throw XRPWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw XRPWalletEngineError.invalidAddress
        }

        let operation = RippleOperationPayment.with {
            $0.destination = destinationAddress
            $0.amount = amountDrops
        }
        let sequence = UInt32(clamping: preview.sequence)
        let lastLedgerSequence = UInt32(clamping: preview.lastLedgerSequence)
        let input = RippleSigningInput.with {
            $0.fee = preview.feeDrops
            $0.sequence = sequence
            if lastLedgerSequence > 0 {
                $0.lastLedgerSequence = lastLedgerSequence
            }
            $0.account = ownerAddress
            $0.privateKey = material.privateKeyData
            $0.opPayment = operation
        }
        let output: RippleSigningOutput = AnySigner.sign(input: input, coin: .xrp)
        let txBlobHex = output.encoded.hexString
        guard !txBlobHex.isEmpty else {
            throw XRPWalletEngineError.signingFailed("WalletCore produced an empty transaction payload.")
        }

        let submit = try await submitTransaction(txBlobHex: txBlobHex, providerIDs: providerIDs)
        let resultCode = submit.engineResult ?? ""
        let txHash = submit.txJSON?.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard resultCode.hasPrefix("tes") || isAlreadyBroadcastSubmit(resultCode: resultCode, message: submit.engineResultMessage) else {
            let message = submit.engineResultMessage ?? "Engine result \(resultCode)"
            throw XRPWalletEngineError.broadcastFailed(message)
        }
        guard !txHash.isEmpty else {
            throw XRPWalletEngineError.broadcastFailed("Missing transaction hash from XRP submit response.")
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(transactionHash: txHash)

        return XRPSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeXRP: preview.estimatedNetworkFeeXRP,
            signedTransactionBlobHex: txBlobHex,
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionBlobHex: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> XRPSendResult {
        let normalizedBlob = signedTransactionBlobHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let blob = Data(hexEncoded: normalizedBlob), !blob.isEmpty else {
            throw XRPWalletEngineError.signingFailed("Invalid signed XRP transaction payload.")
        }
        let submit = try await submitTransaction(txBlobHex: normalizedBlob, providerIDs: providerIDs)
        let returnedHash = submit.txJSON?.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : returnedHash
        return XRPSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeXRP: 0,
            signedTransactionBlobHex: normalizedBlob,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(transactionHash: transactionHash)
        )
    }

    private struct TransactionLookupResult: Decodable {
        let validated: Bool?
        let hash: String?
        let meta: TransactionMeta?

        struct TransactionMeta: Decodable {
            let transactionResult: String?

            enum CodingKeys: String, CodingKey {
                case transactionResult = "TransactionResult"
            }
        }
    }

    private static func verifyBroadcastedTransactionIfAvailable(transactionHash: String) async -> SendBroadcastVerificationStatus {
        let attempts = 3
        var lastError: Error?

        for attempt in 0 ..< attempts {
            do {
                if let lookup = try await fetchTransactionLookup(transactionHash: transactionHash) {
                    if let transactionResult = lookup.meta?.transactionResult,
                       !transactionResult.hasPrefix("tes") {
                        return .failed("Ledger reported result \(transactionResult).")
                    }
                    if lookup.validated == true || lookup.hash?.caseInsensitiveCompare(transactionHash) == .orderedSame {
                        return .verified
                    }
                }
            } catch {
                lastError = error
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func fetchTransactionLookup(transactionHash: String) async throws -> TransactionLookupResult? {
        let payload: [String: Any] = [
            "method": "tx",
            "params": [[
                "transaction": transactionHash
            ]]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        var lastError: Error?

        for endpoint in orderedRPCEndpoints() {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            do {
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw XRPWalletEngineError.networkError("HTTP \(code)")
                }

                let decoded = try JSONDecoder().decode(XRPProvider.RPCEnvelope<TransactionLookupResult>.self, from: data)
                if let result = decoded.result {
                    ChainEndpointReliability.recordAttempt(namespace: XRPProvider.endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                    return result
                }
                let message = decoded.errorMessage ?? decoded.error ?? ""
                if message.localizedCaseInsensitiveContains("notfound") || message.localizedCaseInsensitiveContains("txnnotfound") {
                    ChainEndpointReliability.recordAttempt(namespace: XRPProvider.endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                    return nil
                }
                throw XRPWalletEngineError.networkError(message.isEmpty ? "Unknown XRP RPC error." : message)
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: XRPProvider.endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
            }
        }

        throw XRPWalletEngineError.networkError(lastError?.localizedDescription ?? "Unknown XRP RPC error.")
    }

    private static func fetchFeeDrops() async throws -> Int64 {
        let payload: [String: Any] = [
            "method": "fee",
            "params": [[:]]
        ]
        let result: XRPProvider.FeeResult = try await postRPC(payload: payload)
        let feeString = result.drops?.openLedgerFee ?? result.drops?.minimumFee ?? "12"
        guard let fee = Int64(feeString), fee > 0 else {
            throw XRPWalletEngineError.networkError("Invalid fee response from XRP network.")
        }
        return max(minimumFeeDrops, fee)
    }

    private static func fetchAccountInfo(address: String) async throws -> XRPProvider.AccountInfoResult {
        let payload: [String: Any] = [
            "method": "account_info",
            "params": [[
                "account": address,
                "ledger_index": "current",
                "strict": true
            ]]
        ]
        let result: XRPProvider.AccountInfoResult = try await postRPC(payload: payload)
        return result
    }

    private static func submitTransaction(txBlobHex: String, providerIDs: Set<String>? = nil) async throws -> XRPProvider.SubmitResult {
        let payload: [String: Any] = [
            "method": "submit",
            "params": [[
                "tx_blob": txBlobHex
            ]]
        ]
        let result: XRPProvider.SubmitResult = try await postRPC(payload: payload, providerIDs: providerIDs)
        return result
    }

    private static func isAlreadyBroadcastSubmit(resultCode: String, message: String?) -> Bool {
        let normalizedCode = resultCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedCode == "tefalready" {
            return true
        }
        return classifySendBroadcastFailure(message ?? resultCode) == .alreadyBroadcast
    }

    private static func postRPC<ResultType: Decodable>(payload: [String: Any], providerIDs: Set<String>? = nil) async throws -> ResultType {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        var lastError: Error?

        for endpoint in orderedRPCEndpoints(providerIDs: providerIDs) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            do {
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainWrite)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw XRPWalletEngineError.networkError("HTTP \(code)")
                }

                let decoded = try JSONDecoder().decode(XRPProvider.RPCEnvelope<ResultType>.self, from: data)
                if let result = decoded.result {
                    ChainEndpointReliability.recordAttempt(namespace: XRPProvider.endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                    return result
                }
                let message = decoded.errorMessage ?? decoded.error ?? "Unknown XRP RPC error."
                throw XRPWalletEngineError.networkError(message)
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: XRPProvider.endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
            }
        }

        throw XRPWalletEngineError.networkError(lastError?.localizedDescription ?? "Unknown XRP RPC error.")
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .xrp,
            account: account
        )
        guard AddressValidation.isValidXRPAddress(material.address) else {
            throw XRPWalletEngineError.invalidSeedPhrase
        }
        return material.address
    }

    private static func orderedRPCEndpoints(providerIDs: Set<String>? = nil) -> [URL] {
        let ordered = ChainEndpointReliability.orderedEndpoints(
            namespace: XRPProvider.endpointReliabilityNamespace,
            candidates: filteredRPCEndpoints(providerIDs: providerIDs)
        )
        return ordered.compactMap(URL.init(string:))
    }

    private static func filteredRPCEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        let candidates = XRPProvider.xrpJSONRPCEndpoints.map(\.absoluteString)
        guard let providerIDs, !providerIDs.isEmpty else { return candidates }
        return candidates.filter { endpoint in
            switch endpoint {
            case "https://s1.ripple.com:51234/":
                return providerIDs.contains("ripple-s1")
            case "https://s2.ripple.com:51234/":
                return providerIDs.contains("ripple-s2")
            case "https://xrplcluster.com/":
                return providerIDs.contains("xrplcluster")
            default:
                return false
            }
        }
    }
}
