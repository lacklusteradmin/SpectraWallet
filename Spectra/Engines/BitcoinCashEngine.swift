import Foundation
import CryptoKit
import WalletCore

enum BitcoinCashWalletEngineError: LocalizedError {
    case invalidSeedPhrase
    case invalidAddress
    case signingFailed(String)
    case insufficientFunds
    case invalidUTXO
    case sourceAddressDoesNotMatchSeed
    case broadcastFailed(String)
    case policyViolation(String)

    var errorDescription: String? {
        switch self {
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Bitcoin Cash")
        case .invalidAddress:
            return CommonLocalization.invalidDestinationAddressPrompt("Bitcoin Cash")
        case .signingFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .insufficientFunds:
            return CommonLocalization.insufficientBalanceForAmountPlusNetworkFee("Bitcoin Cash")
        case .invalidUTXO:
            return CommonLocalization.invalidUTXOData("Bitcoin Cash")
        case .sourceAddressDoesNotMatchSeed:
            return CommonLocalization.sourceAddressDoesNotMatchSeed("Bitcoin Cash")
        case .broadcastFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .policyViolation(let message):
            return NSLocalizedString(message, comment: "")
        }
    }
}

enum BitcoinCashWalletEngine {
    private static let satoshisPerBCH: Double = 100_000_000
    private static let defaultFeeRateSatVb: UInt64 = 1
    private static let minimumFeeRateSatVb: UInt64 = 1
    private static let minimumFeeSatoshis: UInt64 = 1_000
    private static let dustThresholdSatoshis: UInt64 = 546
    private static let maxStandardTransactionBytes: UInt64 = 100_000
    private static let blockchairPushURL = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.blockchairPushURL
    private static let blockchairTransactionURLPrefix = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.blockchairTransactionURLPrefix
    private static let actorforthBroadcastURLPrefix = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.actorforthBroadcastURLPrefix
    private static let actorforthTransactionURLPrefix = ChainBackendRegistry.BitcoinCashRuntimeEndpoints.actorforthTransactionURLPrefix
    private static let providerReliabilityDefaultsKey = "bitcoincash.engine.provider.reliability.v1"
    private static let defaultDerivationPath = "m/44'/145'/0'/0/0"

    private enum Provider: String, CaseIterable {
        case blockchair
        case actorforth
    }

    private struct ProviderReliabilityCounter: Codable {
        var successCount: Int
        var failureCount: Int
        var lastUpdatedAt: TimeInterval
    }

    private struct ActorForthBroadcastEnvelope: Decodable {
        let status: String?
        let message: String?
        let data: String?
    }

    struct SendOptions {
        let maxInputCount: Int?
        let enableRBF: Bool
    }

    struct SendResult {
        let transactionHash: String
        let rawTransactionHex: String
        let verificationStatus: SendBroadcastVerificationStatus
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        try derivedAddress(
            for: seedPhrase,
            derivationPath: defaultDerivationPath
                .replacingOccurrences(of: "/0'/0/0", with: "/\(account)'/0/0")
        )
    }

    static func derivedAddress(for seedPhrase: String, derivationPath: String) throws -> String {
        let normalized = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let words = BitcoinWalletEngine.normalizedMnemonicWords(from: normalized)
        guard !words.isEmpty else { throw BitcoinCashWalletEngineError.invalidSeedPhrase }
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalized,
            coin: .bitcoinCash,
            derivationPath: derivationPath
        )
        return material.address
    }

    static func estimateSendPreview(
        sourceAddress: String,
        maxInputCount: Int? = nil
    ) async throws -> BitcoinSendPreview {
        let fetched = try await BitcoinCashBalanceService.fetchUTXOs(for: sourceAddress)
        let utxos = limitedUTXOs(from: fetched, maxInputCount: maxInputCount)
        let totalInputSatoshis = utxos.reduce(UInt64(0)) { $0 + $1.value }
        let estimatedBytes = UInt64(10 + (148 * max(1, utxos.count)) + 68)
        let estimatedFee = max(minimumFeeSatoshis, UInt64(Double(estimatedBytes) * Double(defaultFeeRateSatVb)))
        let spendable = totalInputSatoshis > estimatedFee ? totalInputSatoshis - estimatedFee : 0
        guard spendable > 0 else {
            throw BitcoinCashWalletEngineError.insufficientFunds
        }
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: defaultFeeRateSatVb,
            estimatedNetworkFeeBTC: Double(estimatedFee) / satoshisPerBCH,
            feeRateDescription: "\(defaultFeeRateSatVb) sat/vB",
            spendableBalance: Double(spendable) / satoshisPerBCH,
            estimatedTransactionBytes: Int(estimatedBytes),
            selectedInputCount: utxos.count,
            usesChangeOutput: nil,
            maxSendable: Double(spendable) / satoshisPerBCH
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        sourceAddress: String,
        to destinationAddress: String,
        amountBCH: Double,
        options: SendOptions? = nil,
        derivationPath: String = "m/44'/145'/0'/0/0",
        providerIDs: Set<String>? = nil
    ) async throws -> SendResult {
        let effectiveOptions = options ?? SendOptions(maxInputCount: nil, enableRBF: false)
        guard AddressValidation.isValidBitcoinCashAddress(destinationAddress) else {
            throw BitcoinCashWalletEngineError.invalidAddress
        }

        let normalizedSeed = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let normalizedDerivationPath = DerivationPathParser.normalize(
            derivationPath,
            fallback: defaultDerivationPath
        )
        let sourceMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .bitcoinCash,
            derivationPath: normalizedDerivationPath
        )
        let normalizedSourceAddress = sourceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceMaterial.address.caseInsensitiveCompare(normalizedSourceAddress) == .orderedSame else {
            throw BitcoinCashWalletEngineError.sourceAddressDoesNotMatchSeed
        }
        let changePath = changeDerivationPath(for: normalizedDerivationPath)
        let changeMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .bitcoinCash,
            derivationPath: changePath
        )

        let amountSatoshis = UInt64((amountBCH * satoshisPerBCH).rounded())
        guard amountSatoshis > 0 else {
            throw BitcoinCashWalletEngineError.invalidUTXO
        }

        let fetchedUTXOs = try await BitcoinCashBalanceService.fetchUTXOs(for: sourceAddress)
        guard !fetchedUTXOs.isEmpty else {
            throw BitcoinCashWalletEngineError.insufficientFunds
        }

        let selectedUTXOs = try selectUTXOs(
            from: fetchedUTXOs,
            sendAmountSatoshis: amountSatoshis,
            feeRateSatVb: defaultFeeRateSatVb,
            maxInputCount: effectiveOptions.maxInputCount
        )
        try validatePolicyRules(
            sendAmountSatoshis: amountSatoshis,
            selectedUTXOs: selectedUTXOs,
            feeRateSatVb: defaultFeeRateSatVb
        )

        let sourceScript = try sourceScript(for: sourceAddress)

        var signingInput = BitcoinSigningInput()
        signingInput.hashType = 0x41
        signingInput.amount = Int64(amountSatoshis)
        signingInput.byteFee = Int64(defaultFeeRateSatVb)
        signingInput.toAddress = destinationAddress
        signingInput.changeAddress = changeMaterial.address
        signingInput.coinType = CoinType.bitcoinCash.rawValue
        signingInput.privateKey = [sourceMaterial.privateKeyData]
        signingInput.utxo = try selectedUTXOs.map {
            try walletCoreUnspentTransaction(
                from: $0,
                sourceScript: sourceScript,
                sequence: effectiveOptions.enableRBF ? 0xFFFFFFFD : UInt32.max
            )
        }

        let output: BitcoinSigningOutput = AnySigner.sign(input: signingInput, coin: .bitcoinCash)
        if !output.errorMessage.isEmpty || output.encoded.isEmpty {
            let message = output.errorMessage.isEmpty ? "Failed to sign Bitcoin Cash transaction." : output.errorMessage
            throw BitcoinCashWalletEngineError.signingFailed(message)
        }

        let rawHex = output.encoded.map { String(format: "%02x", $0) }.joined()
        let txid = try await broadcast(
            rawTransactionHex: rawHex,
            fallbackTransactionHash: computeTransactionHash(fromRawHex: rawHex),
            providerIDs: providerIDs
        )
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid, providerIDs: providerIDs)
        return SendResult(
            transactionHash: txid,
            rawTransactionHex: rawHex,
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> SendResult {
        let normalizedRawHex = rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawData = Data(hexEncoded: normalizedRawHex), !rawData.isEmpty else {
            throw BitcoinCashWalletEngineError.signingFailed("Invalid signed Bitcoin Cash transaction payload.")
        }
        guard UInt64(rawData.count) <= maxStandardTransactionBytes else {
            throw BitcoinCashWalletEngineError.policyViolation("Bitcoin Cash transaction is too large for standard relay policy.")
        }
        let fallbackTransactionHash = (expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : computeTransactionHash(fromRawHex: normalizedRawHex)
        let txid = try await broadcast(
            rawTransactionHex: normalizedRawHex,
            fallbackTransactionHash: fallbackTransactionHash,
            providerIDs: providerIDs
        )
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid, providerIDs: providerIDs)
        return SendResult(
            transactionHash: txid,
            rawTransactionHex: normalizedRawHex,
            verificationStatus: verificationStatus
        )
    }

    private static func limitedUTXOs(from utxos: [BitcoinCashUTXO], maxInputCount: Int?) -> [BitcoinCashUTXO] {
        guard let maxInputCount, maxInputCount > 0 else { return utxos }
        return Array(utxos.sorted(by: { $0.value > $1.value }).prefix(maxInputCount))
    }

    private static func walletCoreUnspentTransaction(
        from utxo: BitcoinCashUTXO,
        sourceScript: Data,
        sequence: UInt32
    ) throws -> BitcoinUnspentTransaction {
        guard let txHashData = Data(hexEncoded: utxo.txid), txHashData.count == 32 else {
            throw BitcoinCashWalletEngineError.invalidUTXO
        }

        var outPoint = BitcoinOutPoint()
        outPoint.hash = Data(txHashData.reversed())
        outPoint.index = UInt32(utxo.vout)
        outPoint.sequence = sequence

        var unspent = BitcoinUnspentTransaction()
        unspent.amount = Int64(utxo.value)
        unspent.script = sourceScript
        unspent.outPoint = outPoint
        return unspent
    }

    private static func selectUTXOs(
        from utxos: [BitcoinCashUTXO],
        sendAmountSatoshis: UInt64,
        feeRateSatVb: UInt64,
        maxInputCount: Int?
    ) throws -> [BitcoinCashUTXO] {
        let sorted = utxos.sorted(by: { $0.value > $1.value })
        let cap = maxInputCount.map { max(1, $0) } ?? sorted.count
        var selected: [BitcoinCashUTXO] = []
        var runningTotal: UInt64 = 0

        for utxo in sorted {
            if selected.count >= cap { break }
            selected.append(utxo)
            runningTotal += utxo.value
            let estimatedBytes = UInt64(10 + (148 * selected.count) + 68)
            let estimatedFee = max(minimumFeeSatoshis, UInt64(Double(estimatedBytes) * Double(feeRateSatVb)))
            if runningTotal >= sendAmountSatoshis + estimatedFee {
                return selected
            }
        }

        throw BitcoinCashWalletEngineError.insufficientFunds
    }

    private static func validatePolicyRules(
        sendAmountSatoshis: UInt64,
        selectedUTXOs: [BitcoinCashUTXO],
        feeRateSatVb: UInt64
    ) throws {
        guard sendAmountSatoshis >= dustThresholdSatoshis else {
            throw BitcoinCashWalletEngineError.policyViolation("Amount is below Bitcoin Cash dust threshold.")
        }
        guard feeRateSatVb >= minimumFeeRateSatVb else {
            throw BitcoinCashWalletEngineError.policyViolation("Bitcoin Cash fee rate is below standard relay policy.")
        }
        let estimatedBytes = UInt64(10 + (148 * max(1, selectedUTXOs.count)) + 68)
        guard estimatedBytes <= maxStandardTransactionBytes else {
            throw BitcoinCashWalletEngineError.policyViolation("Bitcoin Cash transaction is too large for standard relay policy.")
        }
        let totalInput = selectedUTXOs.reduce(UInt64(0)) { $0 + $1.value }
        let estimatedFee = max(minimumFeeSatoshis, UInt64(Double(estimatedBytes) * Double(feeRateSatVb)))
        guard totalInput >= sendAmountSatoshis + estimatedFee else {
            throw BitcoinCashWalletEngineError.insufficientFunds
        }
        let change = totalInput - sendAmountSatoshis - estimatedFee
        if change > 0, change < dustThresholdSatoshis {
            throw BitcoinCashWalletEngineError.policyViolation("Calculated Bitcoin Cash change is below dust threshold.")
        }
    }

    private static func sourceScript(for address: String) throws -> Data {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = BitcoinScript.lockScriptForAddress(address: trimmed, coin: .bitcoinCash)
        guard !script.data.isEmpty else {
            throw BitcoinCashWalletEngineError.invalidAddress
        }
        return script.data
    }

    private static func broadcast(
        rawTransactionHex: String,
        fallbackTransactionHash: String,
        providerIDs: Set<String>? = nil
    ) async throws -> String {
        try await runWithFallback(candidates: orderedProviders(candidates: filteredProviders(providerIDs: providerIDs))) { provider in
            switch provider {
            case .blockchair:
                return try await broadcastViaBlockchair(
                    rawTransactionHex: rawTransactionHex,
                    fallbackTransactionHash: fallbackTransactionHash
                )
            case .actorforth:
                return try await broadcastViaActorForth(
                    rawTransactionHex: rawTransactionHex,
                    fallbackTransactionHash: fallbackTransactionHash
                )
            }
        }
    }

    private static func computeTransactionHash(fromRawHex rawHex: String) -> String {
        guard let rawData = Data(hexEncoded: rawHex) else { return "" }
        let firstHash = SHA256.hash(data: rawData)
        let secondHash = SHA256.hash(data: Data(firstHash))
        return Data(secondHash).reversed().map { String(format: "%02x", $0) }.joined()
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        txid: String,
        providerIDs: Set<String>? = nil
    ) async -> SendBroadcastVerificationStatus {
        let attempts = 3
        var lastError: Error?

        for attempt in 0 ..< attempts {
            do {
                if try await verifyPresenceOnlyIfAvailable(txid: txid, providerIDs: providerIDs) {
                    return .verified
                }
            } catch {
                lastError = error
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func verifyPresenceOnlyIfAvailable(
        txid: String,
        providerIDs: Set<String>? = nil
    ) async throws -> Bool {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }

        var sawNotFound = false
        var lastError: Error?

        for provider in orderedProviders(candidates: filteredProviders()) {
            do {
            let url: URL
            switch provider {
            case .blockchair:
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let resolved = URL(string: "\(blockchairTransactionURLPrefix)\(encoded)") else {
                    throw URLError(.badURL)
                }
                url = resolved
            case .actorforth:
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let resolved = URL(string: "\(actorforthTransactionURLPrefix)\(encoded)") else {
                    throw URLError(.badURL)
                }
                url = resolved
            }

            let (_, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainRead)
            guard let http = response as? HTTPURLResponse else {
                throw BitcoinCashWalletEngineError.broadcastFailed("Invalid Bitcoin Cash verification response.")
            }
            if (200 ..< 300).contains(http.statusCode) {
                return true
            }
            if http.statusCode == 404 {
                sawNotFound = true
                continue
            }
            throw BitcoinCashWalletEngineError.broadcastFailed("Bitcoin Cash verification failed with status \(http.statusCode).")
            } catch {
                lastError = error
            }
        }

        if sawNotFound {
            return false
        }
        if let lastError {
            throw lastError
        }
        return false
    }

    private static func broadcastViaBlockchair(
        rawTransactionHex: String,
        fallbackTransactionHash: String
    ) async throws -> String {
        guard let url = URL(string: blockchairPushURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = "data=\(rawTransactionHex)".data(using: .utf8)

        let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainWrite)

        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            let message = "Bitcoin Cash broadcast failed. \(responseBody)".trimmingCharacters(in: .whitespacesAndNewlines)
            if classifySendBroadcastFailure(message) == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                return fallbackTransactionHash
            }
            throw BitcoinCashWalletEngineError.broadcastFailed(message)
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataValue = jsonObject["data"] as? [String: Any],
           let transactionHash = dataValue["transaction_hash"] as? String,
           !transactionHash.isEmpty {
            return transactionHash
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataValue = jsonObject["data"] as? String,
           !dataValue.isEmpty {
            return dataValue
        }

        throw BitcoinCashWalletEngineError.broadcastFailed("Bitcoin Cash broadcast returned an empty transaction hash.")
    }

    private static func broadcastViaActorForth(
        rawTransactionHex: String,
        fallbackTransactionHash: String
    ) async throws -> String {
        guard let encoded = rawTransactionHex.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(actorforthBroadcastURLPrefix)\(encoded)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await SpectraNetworkRouter.shared.data(from: url, profile: .chainWrite)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            let message = "Bitcoin Cash broadcast failed. \(responseBody)".trimmingCharacters(in: .whitespacesAndNewlines)
            if classifySendBroadcastFailure(message) == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                return fallbackTransactionHash
            }
            throw BitcoinCashWalletEngineError.broadcastFailed(message)
        }

        if let envelope = try? JSONDecoder().decode(ActorForthBroadcastEnvelope.self, from: data),
           let txid = envelope.data?.trimmingCharacters(in: .whitespacesAndNewlines),
           !txid.isEmpty {
            return txid
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }

        if !fallbackTransactionHash.isEmpty {
            return fallbackTransactionHash
        }
        throw BitcoinCashWalletEngineError.broadcastFailed("Bitcoin Cash broadcast returned an empty transaction hash.")
    }

    private static func runWithFallback<T>(
        candidates: [Provider],
        operation: @escaping (Provider) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for provider in candidates {
            do {
                let value = try await operation(provider)
                recordProviderAttempt(provider: provider, success: true)
                return value
            } catch {
                lastError = error
                recordProviderAttempt(provider: provider, success: false)
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw lastError ?? BitcoinCashWalletEngineError.broadcastFailed("All Bitcoin Cash providers failed.")
    }

    private static func orderedProviders(candidates: [Provider]) -> [Provider] {
        let counters = loadProviderReliabilityCounters()
        return candidates.sorted { lhs, rhs in
            let leftScore = providerScore(counters[lhs.rawValue])
            let rightScore = providerScore(counters[rhs.rawValue])
            if leftScore == rightScore {
                return lhs.rawValue < rhs.rawValue
            }
            return leftScore > rightScore
        }
    }

    private static func filteredProviders(providerIDs: Set<String>? = nil) -> [Provider] {
        guard let providerIDs, !providerIDs.isEmpty else {
            return Provider.allCases
        }
        let normalized = Set(providerIDs.map { $0.lowercased() })
        let providers = Provider.allCases.filter { normalized.contains($0.rawValue) }
        return providers.isEmpty ? Provider.allCases : providers
    }

    private static func providerScore(_ counter: ProviderReliabilityCounter?) -> Double {
        guard let counter else { return 0.5 }
        let attempts = max(1, counter.successCount + counter.failureCount)
        return Double(counter.successCount) / Double(attempts)
    }

    private static func loadProviderReliabilityCounters() -> [String: ProviderReliabilityCounter] {
        guard let data = UserDefaults.standard.data(forKey: providerReliabilityDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: ProviderReliabilityCounter].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveProviderReliabilityCounters(_ counters: [String: ProviderReliabilityCounter]) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: providerReliabilityDefaultsKey)
    }

    private static func recordProviderAttempt(provider: Provider, success: Bool) {
        var counters = loadProviderReliabilityCounters()
        var counter = counters[provider.rawValue] ?? ProviderReliabilityCounter(successCount: 0, failureCount: 0, lastUpdatedAt: 0)
        if success {
            counter.successCount += 1
        } else {
            counter.failureCount += 1
        }
        counter.lastUpdatedAt = Date().timeIntervalSince1970
        counters[provider.rawValue] = counter
        saveProviderReliabilityCounters(counters)
    }

    private static func changeDerivationPath(for sourceDerivationPath: String) -> String {
        switch sourceDerivationPath {
        case "m/0":
            return "m/1"
        default:
            return DerivationPathParser.replacingLastTwoSegments(
                in: sourceDerivationPath,
                branch: UInt32(WalletDerivationBranch.change.rawValue),
                index: 0,
                fallback: "m/44'/145'/0'/1/0"
            )
        }
    }
}
