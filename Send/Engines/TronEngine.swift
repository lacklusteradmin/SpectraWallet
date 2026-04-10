import Foundation
import CryptoKit
import WalletCore

enum TronWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case unsupportedTokenContract
    case createTransactionFailed(String)
    case signFailed(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Tron")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Tron")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Tron")
        case .unsupportedTokenContract:
            return AppLocalization.string("Only official USDT (TRC-20) on Tron is supported.")
        case .createTransactionFailed(let message):
            return AppLocalization.string(message)
        case .signFailed(let message):
            return AppLocalization.string(message)
        case .broadcastFailed(let message):
            return AppLocalization.string(message)
        }
    }
}

struct TronSendPreview: Equatable {
    let estimatedNetworkFeeTRX: Double
    let feeLimitSun: Int64
    let simulationUsed: Bool
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct TronSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeTRX: Double
    let signedTransactionJSON: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum TronWalletEngine {
    private static let tronGridBaseURLs = ChainBackendRegistry.TronRuntimeEndpoints.tronGridBroadcastBaseURLs
    private static let endpointReliabilityNamespace = "tron.trongrid"
    private static let usdtDecimals: Int64 = 6

    private static func isSupportedUSDTContract(_ contractAddress: String) -> Bool {
        contractAddress.caseInsensitiveCompare(TronBalanceService.usdtTronContract) == .orderedSame
    }
    private static let estimatedTRXTransferBytes: Int64 = 300

    private struct TronFeeParameters {
        let energyFeeSun: Int64
        let transactionFeeSun: Int64
    }

    private static func estimatedTRC20FeeTRX(energyUsed: Int64, parameters: TronFeeParameters) -> Double {
        let energyFeeTRX = Double(energyUsed * parameters.energyFeeSun) / 1_000_000.0
        let bandwidthFeeTRX = Double(parameters.transactionFeeSun * estimatedTRXTransferBytes) / 1_000_000.0
        return max(bandwidthFeeTRX, energyFeeTRX + bandwidthFeeTRX)
    }

    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        symbol: String,
        amount: Double,
        contractAddress: String?
    ) async throws -> TronSendPreview {
        guard AddressValidation.isValidTronAddress(ownerAddress),
              AddressValidation.isValidTronAddress(destinationAddress) else {
            throw TronWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        if symbol == "TRX" {
            let balances = try await TronBalanceService.fetchBalances(for: ownerAddress)
            let estimatedTRXFee = try await fetchEstimatedTRXTransferFee(ownerAddress: ownerAddress)
            let maxSendable = max(0, balances.trxBalance - estimatedTRXFee)
            return TronSendPreview(
                estimatedNetworkFeeTRX: estimatedTRXFee,
                feeLimitSun: 0,
                simulationUsed: true,
                spendableBalance: maxSendable,
                feeRateDescription: "Live bandwidth estimate",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: maxSendable
            )
        }

        guard symbol == "USDT", let contractAddress else {
            throw TronWalletEngineError.invalidAmount
        }
        guard isSupportedUSDTContract(contractAddress) else {
            throw TronWalletEngineError.unsupportedTokenContract
        }

        let amountRaw = try scaledSignedAmount(amount, decimals: Int(usdtDecimals))
        guard amountRaw > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let parameter = try makeTRC20TransferParameter(to: destinationAddress, amountRaw: amountRaw)
        let simulation = try await simulateTRC20Transfer(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter
        )
        guard let energyUsed = simulation.energyUsed else {
            throw TronWalletEngineError.createTransactionFailed("Tron token fee simulation did not return energy usage.")
        }
        let feeParameters = try await fetchTronFeeParameters()

        let balances = try await TronBalanceService.fetchBalances(for: ownerAddress)
        let tokenBalance = balances.tokenBalances.first(where: { $0.symbol == symbol })?.balance ?? 0
        return TronSendPreview(
            estimatedNetworkFeeTRX: estimatedTRC20FeeTRX(energyUsed: energyUsed, parameters: feeParameters),
            feeLimitSun: simulation.feeLimitSun,
            simulationUsed: true,
            spendableBalance: tokenBalance,
            feeRateDescription: "\(energyUsed) energy",
            estimatedTransactionBytes: nil,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: tokenBalance
        )
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        do {
            return try SeedPhraseAddressDerivation.tronAddress(forPrivateKey: privateKeyHex)
        } catch {
            throw TronWalletEngineError.invalidAddress
        }
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        symbol: String,
        amount: Double,
        contractAddress: String?,
        derivationAccount: UInt32 = 0,
        providerIDs: Set<String>? = nil
    ) async throws -> TronSendResult {
        guard AddressValidation.isValidTronAddress(ownerAddress),
              AddressValidation.isValidTronAddress(destinationAddress) else {
            throw TronWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: seedPhrase,
            coin: .tron,
            account: derivationAccount
        )
        guard !material.privateKeyData.isEmpty else {
            throw TronWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw TronWalletEngineError.invalidAddress
        }

        if symbol == "TRX" {
            let amountSun = try scaledSignedAmount(amount, decimals: 6)
            guard amountSun > 0 else {
                throw TronWalletEngineError.invalidAmount
            }
            let unsignedTx = try await createTRXTransferTransaction(
                ownerAddress: ownerAddress,
                destinationAddress: destinationAddress,
                amountSun: amountSun
            )
            let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
            let txid = try await broadcastSignedTransaction(signedTransaction, providerIDs: providerIDs)
            let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid, providerIDs: providerIDs)
            let estimatedTRXFee = try await fetchEstimatedTRXTransferFee(ownerAddress: ownerAddress)
            return TronSendResult(
                transactionHash: txid,
                estimatedNetworkFeeTRX: estimatedTRXFee,
                signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
                verificationStatus: verificationStatus
            )
        }

        guard symbol == "USDT", let contractAddress else {
            throw TronWalletEngineError.invalidAmount
        }
        guard isSupportedUSDTContract(contractAddress) else {
            throw TronWalletEngineError.unsupportedTokenContract
        }

        let amountRaw = try scaledSignedAmount(amount, decimals: Int(usdtDecimals))
        guard amountRaw > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let parameter = try makeTRC20TransferParameter(to: destinationAddress, amountRaw: amountRaw)
        let simulation = try await simulateTRC20Transfer(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter
        )
        guard let energyUsed = simulation.energyUsed else {
            throw TronWalletEngineError.createTransactionFailed("Tron token fee simulation did not return energy usage.")
        }
        let feeParameters = try await fetchTronFeeParameters()

        let unsignedTx = try await createTRC20TransferTransaction(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter,
            feeLimitSun: simulation.feeLimitSun
        )
        let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
        let txid = try await broadcastSignedTransaction(signedTransaction, providerIDs: providerIDs)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid, providerIDs: providerIDs)

        return TronSendResult(
            transactionHash: txid,
            estimatedNetworkFeeTRX: estimatedTRC20FeeTRX(energyUsed: energyUsed, parameters: feeParameters),
            signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
            verificationStatus: verificationStatus
        )
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        symbol: String,
        amount: Double,
        contractAddress: String?,
        providerIDs: Set<String>? = nil
    ) async throws -> TronSendResult {
        guard AddressValidation.isValidTronAddress(ownerAddress),
              AddressValidation.isValidTronAddress(destinationAddress) else {
            throw TronWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let material = try SeedPhraseSigningMaterial.material(privateKeyHex: privateKeyHex, coin: .tron)
        guard !material.privateKeyData.isEmpty else {
            throw TronWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw TronWalletEngineError.invalidAddress
        }

        if symbol == "TRX" {
            let amountSun = try scaledSignedAmount(amount, decimals: 6)
            guard amountSun > 0 else {
                throw TronWalletEngineError.invalidAmount
            }
            let unsignedTx = try await createTRXTransferTransaction(
                ownerAddress: ownerAddress,
                destinationAddress: destinationAddress,
                amountSun: amountSun
            )
            let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
            let txid = try await broadcastSignedTransaction(signedTransaction, providerIDs: providerIDs)
            let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid, providerIDs: providerIDs)
            let estimatedTRXFee = try await fetchEstimatedTRXTransferFee(ownerAddress: ownerAddress)
            return TronSendResult(
                transactionHash: txid,
                estimatedNetworkFeeTRX: estimatedTRXFee,
                signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
                verificationStatus: verificationStatus
            )
        }

        guard symbol == "USDT", let contractAddress else {
            throw TronWalletEngineError.invalidAmount
        }
        guard isSupportedUSDTContract(contractAddress) else {
            throw TronWalletEngineError.unsupportedTokenContract
        }

        let amountRaw = try scaledSignedAmount(amount, decimals: Int(usdtDecimals))
        guard amountRaw > 0 else {
            throw TronWalletEngineError.invalidAmount
        }

        let parameter = try makeTRC20TransferParameter(to: destinationAddress, amountRaw: amountRaw)
        let simulation = try await simulateTRC20Transfer(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter
        )
        guard let energyUsed = simulation.energyUsed else {
            throw TronWalletEngineError.createTransactionFailed("Tron token fee simulation did not return energy usage.")
        }
        let feeParameters = try await fetchTronFeeParameters()

        let unsignedTx = try await createTRC20TransferTransaction(
            ownerAddress: ownerAddress,
            contractAddress: contractAddress,
            parameter: parameter,
            feeLimitSun: simulation.feeLimitSun
        )
        let signedTransaction = try signRawTransaction(unsignedTx, privateKey: material.privateKeyData)
        let txid = try await broadcastSignedTransaction(signedTransaction, providerIDs: providerIDs)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid, providerIDs: providerIDs)

        return TronSendResult(
            transactionHash: txid,
            estimatedNetworkFeeTRX: estimatedTRC20FeeTRX(energyUsed: energyUsed, parameters: feeParameters),
            signedTransactionJSON: encodedSignedTransactionJSON(signedTransaction),
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionJSON: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> TronSendResult {
        guard let data = signedTransactionJSON.data(using: .utf8),
              let signedTransaction = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TronWalletEngineError.broadcastFailed("Invalid signed Tron transaction payload.")
        }
        let txid = try await broadcastSignedTransaction(signedTransaction, providerIDs: providerIDs)
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : txid
        return TronSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeTRX: 0,
            signedTransactionJSON: signedTransactionJSON,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(txid: transactionHash, providerIDs: providerIDs)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        txid: String,
        providerIDs: Set<String>? = nil
    ) async -> SendBroadcastVerificationStatus {
        let attempts = 3
        var lastError: Error?

        for attempt in 0 ..< attempts {
            do {
                if try await transactionExists(txid: txid, providerIDs: providerIDs) {
                    return .verified
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

    private static func transactionExists(
        txid: String,
        providerIDs: Set<String>? = nil
    ) async throws -> Bool {
        var lastError: Error?
        for baseURL in orderedBroadcastBaseURLs() {
            guard let url = URL(string: baseURL + "/walletsolidity/gettransactioninfobyid") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["value": txid], options: [])

            do {
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw TronWalletEngineError.broadcastFailed("Tron verification failed with HTTP \(code).")
                }

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw TronWalletEngineError.broadcastFailed("Invalid Tron verification payload.")
                }

                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: true)
                if object.isEmpty {
                    return false
                }
                if let id = object["id"] as? String, !id.isEmpty {
                    return true
                }
                if let receipt = object["receipt"] as? [String: Any], !receipt.isEmpty {
                    return true
                }
                return false
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: false)
            }
        }
        throw lastError ?? TronWalletEngineError.broadcastFailed("Invalid Tron verification payload.")
    }

    private struct TRC20SimulationResult {
        let energyUsed: Int64?
        let feeLimitSun: Int64
    }

    private static func createTRXTransferTransaction(
        ownerAddress: String,
        destinationAddress: String,
        amountSun: Int64
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "owner_address": ownerAddress,
            "to_address": destinationAddress,
            "amount": amountSun,
            "visible": true
        ]
        return try await postJSON(
            path: "/wallet/createtransaction",
            payload: payload,
            profile: .chainWrite,
            expectedKey: "txID",
            errorPrefix: "Tron create transaction failed"
        )
    }

    private static func createTRC20TransferTransaction(
        ownerAddress: String,
        contractAddress: String,
        parameter: String,
        feeLimitSun: Int64
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "owner_address": ownerAddress,
            "contract_address": contractAddress,
            "function_selector": "transfer(address,uint256)",
            "parameter": parameter,
            "fee_limit": feeLimitSun,
            "call_value": 0,
            "visible": true
        ]

        let response = try await postJSON(
            path: "/wallet/triggersmartcontract",
            payload: payload,
            profile: .chainWrite,
            expectedKey: "result",
            errorPrefix: "Tron trigger smart contract failed"
        )

        if let result = response["result"] as? [String: Any],
           let ok = result["result"] as? Bool,
           !ok {
            let message = (result["message"] as? String) ?? "unknown trigger error"
            throw TronWalletEngineError.createTransactionFailed("Tron trigger smart contract failed: \(message)")
        }

        guard let transaction = response["transaction"] as? [String: Any],
              transaction["txID"] as? String != nil else {
            throw TronWalletEngineError.createTransactionFailed("Tron trigger smart contract did not return a transaction payload.")
        }
        return transaction
    }

    private static func simulateTRC20Transfer(
        ownerAddress: String,
        contractAddress: String,
        parameter: String
    ) async throws -> TRC20SimulationResult {
        let payload: [String: Any] = [
            "owner_address": ownerAddress,
            "contract_address": contractAddress,
            "function_selector": "transfer(address,uint256)",
            "parameter": parameter,
            "visible": true
        ]

        let response = try await postJSON(
            path: "/wallet/triggerconstantcontract",
            payload: payload,
            profile: .chainRead,
            expectedKey: "result",
            errorPrefix: "Tron transfer simulation failed"
        )

        if let energyUsed = (response["energy_used"] as? NSNumber)?.int64Value {
            let feeParameters = try await fetchTronFeeParameters()
            let estimatedEnergyFeeSun = energyUsed * feeParameters.energyFeeSun
            let bandwidthHeadroomSun = feeParameters.transactionFeeSun * estimatedTRXTransferBytes
            let feeLimitSun = max(estimatedEnergyFeeSun + bandwidthHeadroomSun, estimatedEnergyFeeSun + 2_000_000)
            return TRC20SimulationResult(energyUsed: energyUsed, feeLimitSun: feeLimitSun)
        }

        if let energyFee = (response["energy_fee"] as? NSNumber)?.int64Value {
            return TRC20SimulationResult(energyUsed: nil, feeLimitSun: energyFee + 2_000_000)
        }

        throw TronWalletEngineError.createTransactionFailed("Tron token fee simulation did not return fee data.")
    }

    private static func signRawTransaction(_ transaction: [String: Any], privateKey: Data) throws -> [String: Any] {
        guard let txID = transaction["txID"] as? String, !txID.isEmpty else {
            throw TronWalletEngineError.signFailed("Unsigned Tron transaction is missing txID.")
        }

        var input = TronSigningInput()
        input.privateKey = privateKey
        input.txID = txID
        let output: TronSigningOutput = AnySigner.sign(input: input, coin: .tron)

        if output.error.rawValue != 0 {
            let message = output.errorMessage.isEmpty ? "WalletCore Tron signer returned error code \(output.error.rawValue)." : output.errorMessage
            throw TronWalletEngineError.signFailed(message)
        }
        guard !output.signature.isEmpty else {
            throw TronWalletEngineError.signFailed("WalletCore Tron signer returned an empty signature.")
        }

        var signed = transaction
        signed["signature"] = [output.signature.hexEncodedString()]
        return signed
    }

    private static func broadcastSignedTransaction(
        _ signedTransaction: [String: Any],
        providerIDs: Set<String>? = nil
    ) async throws -> String {
        let response = try await postJSON(
            path: "/wallet/broadcasttransaction",
            payload: signedTransaction,
            profile: .chainWrite,
            expectedKey: "result",
            errorPrefix: "Tron broadcast failed"
        )

        if let success = response["result"] as? Bool, success {
            if let txid = response["txid"] as? String, !txid.isEmpty {
                return txid
            }
            if let txid = signedTransaction["txID"] as? String, !txid.isEmpty {
                return txid
            }
            throw TronWalletEngineError.broadcastFailed("Tron broadcast succeeded but no transaction hash was returned.")
        }

        if let providerMessage = bestProviderMessage(from: response), !providerMessage.isEmpty {
            if classifySendBroadcastFailure(providerMessage) == .alreadyBroadcast {
                if let txid = response["txid"] as? String, !txid.isEmpty {
                    return txid
                }
                if let txid = signedTransaction["txID"] as? String, !txid.isEmpty {
                    return txid
                }
            }
            throw TronWalletEngineError.broadcastFailed("Tron broadcast failed: \(providerMessage)")
        }
        throw TronWalletEngineError.broadcastFailed("Tron broadcast failed with unknown provider response.")
    }

    private static func postJSON(
        path: String,
        payload: [String: Any],
        profile: NetworkRetryProfile,
        expectedKey: String,
        errorPrefix: String
    ) async throws -> [String: Any] {
        var lastError: Error?
        for baseURL in orderedBroadcastBaseURLs() {
            guard let url = URL(string: baseURL + path) else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

            do {
                let (data, response) = try await ProviderHTTP.data(for: request, profile: profile)

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): invalid JSON payload.")
                }

                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if let providerMessage = bestProviderMessage(from: object), !providerMessage.isEmpty {
                        throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): HTTP \(statusCode) (\(providerMessage))")
                    }
                    throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): HTTP \(statusCode)")
                }

                if object[expectedKey] == nil {
                    if let providerMessage = bestProviderMessage(from: object), !providerMessage.isEmpty {
                        throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): \(providerMessage)")
                    }
                    throw TronWalletEngineError.createTransactionFailed("\(errorPrefix): missing expected field \(expectedKey).")
                }
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: true)
                return object
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: baseURL, success: false)
            }
        }
        throw lastError ?? TronWalletEngineError.createTransactionFailed("\(errorPrefix): all providers failed.")
    }

    private static func fetchEstimatedTRXTransferFee(ownerAddress: String) async throws -> Double {
        let resource = try await postJSON(
            path: "/wallet/getaccountresource",
            payload: ["address": ownerAddress, "visible": true],
            profile: .chainRead,
            expectedKey: "freeNetLimit",
            errorPrefix: "Failed to fetch Tron account resources"
        )
        let parameters = try await postJSON(
            path: "/wallet/getchainparameters",
            payload: ["visible": true],
            profile: .chainRead,
            expectedKey: "chainParameter",
            errorPrefix: "Failed to fetch Tron chain parameters"
        )

        let freeNetLimit = int64Value(resource["freeNetLimit"]) ?? 0
        let freeNetUsed = int64Value(resource["freeNetUsed"]) ?? 0
        let netLimit = int64Value(resource["NetLimit"]) ?? 0
        let netUsed = int64Value(resource["NetUsed"]) ?? 0
        let availableBandwidth = max(0, (freeNetLimit - freeNetUsed) + (netLimit - netUsed))
        let billableBytes = max(0, estimatedTRXTransferBytes - availableBandwidth)
        guard let sunPerByte = chainParameterValue(
            parameters["chainParameter"],
            names: ["getTransactionFee"]
        ) else {
            throw TronWalletEngineError.createTransactionFailed("Tron chain parameters did not include transaction fee pricing.")
        }
        return (Double(billableBytes) * Double(sunPerByte)) / 1_000_000.0
    }

    private static func fetchTronFeeParameters() async throws -> TronFeeParameters {
        let parameters = try await postJSON(
            path: "/wallet/getchainparameters",
            payload: ["visible": true],
            profile: .chainRead,
            expectedKey: "chainParameter",
            errorPrefix: "Failed to fetch Tron chain parameters"
        )
        guard let energyFeeSun = chainParameterValue(parameters["chainParameter"], names: ["getEnergyFee"]),
              let transactionFeeSun = chainParameterValue(parameters["chainParameter"], names: ["getTransactionFee"]) else {
            throw TronWalletEngineError.createTransactionFailed("Tron chain parameters did not include fee pricing.")
        }
        return TronFeeParameters(energyFeeSun: energyFeeSun, transactionFeeSun: transactionFeeSun)
    }

    private static func chainParameterValue(_ raw: Any?, names: Set<String>) -> Int64? {
        guard let rows = raw as? [[String: Any]] else { return nil }
        for row in rows {
            guard let key = row["key"] as? String,
                  names.contains(key),
                  let value = int64Value(row["value"]) else {
                continue
            }
            return value
        }
        return nil
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        switch raw {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func orderedBroadcastBaseURLs(providerIDs: Set<String>? = nil) -> [String] {
        ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: filteredBroadcastBaseURLs(providerIDs: providerIDs)
        )
    }

    private static func filteredBroadcastBaseURLs(providerIDs: Set<String>? = nil) -> [String] {
        guard let providerIDs, !providerIDs.isEmpty else {
            return tronGridBaseURLs
        }
        let normalized = Set(providerIDs.map { $0.lowercased() })
        let filtered = tronGridBaseURLs.filter { baseURL in
            if baseURL.contains("api.trongrid.io") {
                return normalized.contains("trongrid-io")
            }
            if baseURL.contains("api.trongrid.pro") {
                return normalized.contains("trongrid-pro")
            }
            if baseURL.contains("api.trongrid.network") {
                return normalized.contains("trongrid-network")
            }
            return false
        }
        return filtered.isEmpty ? tronGridBaseURLs : filtered
    }

    private static func bestProviderMessage(from object: [String: Any]) -> String? {
        if let message = normalizedProviderMessage(object["message"]) {
            return message
        }
        if let error = normalizedProviderMessage(object["Error"]) {
            return error
        }
        if let code = normalizedProviderMessage(object["code"]) {
            return code
        }
        if let result = object["result"] as? [String: Any] {
            if let message = normalizedProviderMessage(result["message"]) {
                return message
            }
            if let code = normalizedProviderMessage(result["code"]) {
                return code
            }
        }
        return nil
    }

    private static func normalizedProviderMessage(_ value: Any?) -> String? {
        guard let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let decoded = decodeHexASCIIIfNeeded(trimmed), !decoded.isEmpty {
                return decoded
            }
            return trimmed
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        if JSONSerialization.isValidJSONObject(["v": value]),
           let encoded = try? JSONSerialization.data(withJSONObject: ["v": value], options: []),
           let json = String(data: encoded, encoding: .utf8) {
            return json
        }

        return nil
    }

    private static func encodedSignedTransactionJSON(_ signedTransaction: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(signedTransaction),
              let data = try? JSONSerialization.data(withJSONObject: signedTransaction, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    private static func decodeHexASCIIIfNeeded(_ string: String) -> String? {
        let candidate = string.hasPrefix("0x") ? String(string.dropFirst(2)) : string
        guard candidate.count >= 2, candidate.count % 2 == 0,
              candidate.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }

        var bytes = Data()
        bytes.reserveCapacity(candidate.count / 2)
        var index = candidate.startIndex
        while index < candidate.endIndex {
            let next = candidate.index(index, offsetBy: 2)
            guard let byte = UInt8(candidate[index ..< next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }

        guard let decoded = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !decoded.isEmpty,
              decoded.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 && $0.value != 127 }) else {
            return nil
        }
        return decoded
    }

    private static func makeTRC20TransferParameter(to destinationAddress: String, amountRaw: Int64) throws -> String {
        guard let tronAddressPayload = UTXOAddressCodec.base58CheckDecode(destinationAddress), tronAddressPayload.count == 21 else {
            throw TronWalletEngineError.invalidAddress
        }
        let evmAddress = tronAddressPayload.dropFirst()
        guard evmAddress.count == 20 else {
            throw TronWalletEngineError.invalidAddress
        }
        let addressSlot = Data(repeating: 0, count: 12) + evmAddress

        var amountBytes = withUnsafeBytes(of: amountRaw.bigEndian, Array.init)
        while amountBytes.first == 0, amountBytes.count > 1 {
            amountBytes.removeFirst()
        }
        if amountBytes.count > 32 {
            throw TronWalletEngineError.invalidAmount
        }
        let amountSlot = Data(repeating: 0, count: 32 - amountBytes.count) + Data(amountBytes)

        return (addressSlot + amountSlot).hexEncodedString()
    }

    private static func scaledSignedAmount(_ amount: Double, decimals: Int) throws -> Int64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw TronWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        guard rounded != NSDecimalNumber.notANumber,
              rounded.compare(NSDecimalNumber.zero) == .orderedDescending else {
            throw TronWalletEngineError.invalidAmount
        }

        let maxValue = NSDecimalNumber(value: Int64.max)
        guard rounded.compare(maxValue) != .orderedDescending else {
            throw TronWalletEngineError.invalidAmount
        }

        let value = rounded.int64Value
        guard value > 0 else {
            throw TronWalletEngineError.invalidAmount
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
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
