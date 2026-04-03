import Foundation

import WalletCore
import SwiftProtobuf

enum SuiWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)
    case insufficientBalance

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Sui")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Sui")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Sui")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Sui")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("Sui", message: message)
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("Sui", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Sui", message: message)
        case .insufficientBalance:
            return NSLocalizedString("Insufficient SUI balance to cover amount and network fee.", comment: "")
        }
    }
}

struct SuiSendPreview: Equatable {
    let estimatedNetworkFeeSUI: Double
    let gasBudgetMist: UInt64
    let referenceGasPrice: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct SuiSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeSUI: Double
    let signedTransactionPayloadJSON: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum SuiWalletEngine {
    private static let suiCoinType = "0x2::sui::SUI"
    private static let defaultGasBudgetMist: UInt64 = 3_000_000

    private struct SuiObjectRefForSigning {
        let objectID: String
        let version: UInt64
        let objectDigest: String
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .sui,
            account: account
        )
        guard AddressValidation.isValidSuiAddress(material.address) else {
            throw SuiWalletEngineError.invalidSeedPhrase
        }
        return material.address
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> SuiSendPreview {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidSuiAddress(normalizedOwner), AddressValidation.isValidSuiAddress(normalizedDestination) else {
            throw SuiWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw SuiWalletEngineError.invalidAmount
        }

        let gasPrice = try await fetchReferenceGasPrice()
        let estimatedFee = Double(defaultGasBudgetMist) * Double(gasPrice) / 1_000_000_000.0
        let balanceSUI = try await SuiBalanceService.fetchBalance(for: normalizedOwner)
        let maxSendable = max(0, balanceSUI - estimatedFee)
        return SuiSendPreview(
            estimatedNetworkFeeSUI: estimatedFee,
            gasBudgetMist: defaultGasBudgetMist,
            referenceGasPrice: gasPrice,
            spendableBalance: maxSendable,
            feeRateDescription: "Reference gas price: \(gasPrice)",
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
    ) async throws -> SuiSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)

        guard AddressValidation.isValidSuiAddress(normalizedOwner),
              AddressValidation.isValidSuiAddress(normalizedDestination) else {
            throw SuiWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw SuiWalletEngineError.invalidAmount
        }

        let amountMist = try scaledUnsignedAmount(amount, decimals: 9)
        guard amountMist > 0 else {
            throw SuiWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(
            from: normalizedOwner,
            to: normalizedDestination,
            amount: amount
        )

        let requiredMist = amountMist + (preview.gasBudgetMist * preview.referenceGasPrice)
        let selectedCoins = try await selectCoins(address: normalizedOwner, requiredMist: requiredMist)
        guard !selectedCoins.isEmpty else {
            throw SuiWalletEngineError.insufficientBalance
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .sui,
            account: derivationAccount
        )
        guard !material.privateKeyData.isEmpty else {
            throw SuiWalletEngineError.invalidSeedPhrase
        }
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw SuiWalletEngineError.invalidAddress
        }

        let input = SuiSigningInput.with {
            $0.privateKey = material.privateKeyData
            $0.gasBudget = preview.gasBudgetMist
            $0.referenceGasPrice = preview.referenceGasPrice
            $0.paySui = SuiPaySui.with {
                $0.inputCoins = selectedCoins.map { coin in
                    SuiObjectRef.with {
                        $0.objectID = coin.objectID
                        $0.version = coin.version
                        $0.objectDigest = coin.objectDigest
                    }
                }
                $0.recipients = [normalizedDestination]
                $0.amounts = [amountMist]
            }
        }

        let output: SuiSigningOutput = AnySigner.sign(input: input, coin: .sui)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw SuiWalletEngineError.signingFailed(message)
        }

        let unsignedTx = output.unsignedTx.trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = output.signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unsignedTx.isEmpty, !signature.isEmpty else {
            throw SuiWalletEngineError.signingFailed("WalletCore returned empty transaction or signature payload.")
        }

        let digest: String
        do {
            digest = try await executeTransactionBlock(
                txBytesBase64: unsignedTx,
                signatureBase64: signature,
                providerIDs: providerIDs
            )
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredDigest = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: normalizedOwner,
                      destinationAddress: normalizedDestination,
                      amount: amount
                  ) else {
                throw error
            }
            digest = recoveredDigest
        }
        return SuiSendResult(
            transactionHash: digest,
            estimatedNetworkFeeSUI: preview.estimatedNetworkFeeSUI,
            signedTransactionPayloadJSON: "{\"txBytesBase64\":\"\(unsignedTx)\",\"signatureBase64\":\"\(signature)\"}",
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(
                ownerAddress: normalizedOwner,
                transactionHash: digest
            )
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionPayloadJSON: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> SuiSendResult {
        let payloadData = Data(signedTransactionPayloadJSON.utf8)
        guard let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: String],
              let txBytesBase64 = payload["txBytesBase64"],
              let signatureBase64 = payload["signatureBase64"],
              Data(base64Encoded: txBytesBase64) != nil,
              Data(base64Encoded: signatureBase64) != nil else {
            throw SuiWalletEngineError.invalidResponse
        }
        let digest = try await executeTransactionBlock(
            txBytesBase64: txBytesBase64,
            signatureBase64: signatureBase64,
            providerIDs: providerIDs
        )
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : digest
        return SuiSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeSUI: 0,
            signedTransactionPayloadJSON: signedTransactionPayloadJSON,
            verificationStatus: await verifyBroadcastedTransactionByHashIfAvailable(transactionHash: transactionHash)
        )
    }

    private static func selectCoins(address: String, requiredMist: UInt64) async throws -> [SuiObjectRefForSigning] {
        var cursor: String?
        var selected: [SuiObjectRefForSigning] = []
        var accumulated: UInt64 = 0

        while true {
            let page = try await fetchCoins(address: address, cursor: cursor)
            let entries = (page.data ?? []).compactMap { coin -> (SuiObjectRefForSigning, UInt64)? in
                guard let objectID = coin.coinObjectID,
                      let versionText = coin.version,
                      let version = UInt64(versionText),
                      let digest = coin.digest,
                      let balanceText = coin.balance,
                      let balance = UInt64(balanceText),
                      balance > 0 else {
                    return nil
                }

                return (
                    SuiObjectRefForSigning(
                        objectID: objectID,
                        version: version,
                        objectDigest: digest
                    ),
                    balance
                )
            }
            .sorted { $0.1 > $1.1 }

            for entry in entries {
                selected.append(entry.0)
                accumulated += entry.1
                if accumulated >= requiredMist {
                    return selected
                }
            }

            guard page.hasNextPage == true else { break }
            cursor = page.nextCursor
        }

        if accumulated >= requiredMist {
            return selected
        }
        throw SuiWalletEngineError.insufficientBalance
    }

    private static func fetchCoins(address: String, cursor: String?) async throws -> SuiProvider.CoinPage {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "suix_getCoins",
            "params": [address, suiCoinType, cursor as Any, 100]
        ]
        return try await postRPC(payload: payload, profile: .chainRead)
    }

    private static func fetchReferenceGasPrice() async throws -> UInt64 {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "suix_getReferenceGasPrice",
            "params": []
        ]
        let result: SuiProvider.ReferenceGasPriceResult = try await postRPC(payload: payload, profile: .chainRead)
        guard let value = result.value, let parsed = UInt64(value), parsed > 0 else {
            throw SuiWalletEngineError.invalidResponse
        }
        return parsed
    }

    private static func executeTransactionBlock(
        txBytesBase64: String,
        signatureBase64: String,
        providerIDs: Set<String>? = nil
    ) async throws -> String {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sui_executeTransactionBlock",
            "params": [
                txBytesBase64,
                [signatureBase64],
                ["showEffects": true],
                "WaitForLocalExecution"
            ]
        ]

        var lastError: Error?
        for attempt in 0 ..< 2 {
            do {
                let result: SuiProvider.ExecuteResult = try await postRPC(payload: payload, profile: .chainWrite, providerIDs: providerIDs)
                let status = result.effects?.status?.status?.lowercased()
                if let status, status != "success" {
                    let message = result.effects?.status?.error ?? "Sui execute reported status: \(status)."
                    throw SuiWalletEngineError.broadcastFailed(message)
                }

                guard let digest = result.digest?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !digest.isEmpty else {
                    throw SuiWalletEngineError.broadcastFailed("Missing transaction digest from Sui execute response.")
                }
                return digest
            } catch {
                lastError = error
                if attempt < 1, classifySendBroadcastFailure(error.localizedDescription) == .retryable {
                    continue
                }
                break
            }
        }
        throw lastError ?? SuiWalletEngineError.broadcastFailed("Sui transaction execution failed.")
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        await verifyBroadcastedTransactionByHashIfAvailable(transactionHash: transactionHash)
    }

    private static func recoverRecentTransactionHashIfAvailable(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async -> String? {
        let result = await SuiBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        return result.snapshots.first {
            $0.kind == .send
                && abs($0.amount - amount) < 0.000000001
                && $0.counterpartyAddress.lowercased() == destinationAddress.lowercased()
        }?.transactionHash
    }

    private static func verifyBroadcastedTransactionByHashIfAvailable(
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else { return .deferred }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sui_getTransactionBlock",
            "params": [normalizedHash, ["showEffects": true]]
        ]
        do {
            let _: SuiProvider.ExecuteResult = try await postRPC(payload: payload, profile: .chainRead)
            return .verified
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func postRPC<ResultType: Decodable>(
        payload: [String: Any],
        profile: NetworkRetryProfile,
        providerIDs: Set<String>? = nil
    ) async throws -> ResultType {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        var lastError: Error?

        for endpoint in SuiProvider.orderedRPCEndpoints(providerIDs: providerIDs) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            do {
                let (data, response): (Data, URLResponse) = try await ProviderHTTP.data(for: request, profile: profile)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw SuiWalletEngineError.networkError("HTTP \(code)")
                }

                let decoded = try JSONDecoder().decode(SuiProvider.RPCEnvelope<ResultType>.self, from: data)
                if let result = decoded.result {
                    ChainEndpointReliability.recordAttempt(namespace: SuiProvider.endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: true)
                    return result
                }

                let message = decoded.error?.message ?? "Unknown Sui RPC error"
                throw SuiWalletEngineError.networkError(message)
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: SuiProvider.endpointReliabilityNamespace, endpoint: endpoint.absoluteString, success: false)
            }
        }

        throw lastError ?? SuiWalletEngineError.networkError("Unknown Sui RPC error")
    }

    private static func normalizeAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw SuiWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let amountDecimal = NSDecimalNumber(value: amount)
        let scaled = amountDecimal.multiplying(by: base)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        if rounded == NSDecimalNumber.notANumber || rounded.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw SuiWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard rounded.compare(maxValue) != .orderedDescending else {
            throw SuiWalletEngineError.invalidAmount
        }
        let value = rounded.uint64Value
        guard value > 0 else {
            throw SuiWalletEngineError.invalidAmount
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
