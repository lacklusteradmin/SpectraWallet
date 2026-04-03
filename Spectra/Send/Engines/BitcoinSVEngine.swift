import Foundation
import CryptoKit
import WalletCore

enum BitcoinSVWalletEngineError: LocalizedError {
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
            return CommonLocalization.invalidSeedPhrase("Bitcoin SV")
        case .invalidAddress:
            return CommonLocalization.invalidDestinationAddressPrompt("Bitcoin SV")
        case .signingFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .insufficientFunds:
            return CommonLocalization.insufficientBalanceForAmountPlusNetworkFee("Bitcoin SV")
        case .invalidUTXO:
            return CommonLocalization.invalidUTXOData("Bitcoin SV")
        case .sourceAddressDoesNotMatchSeed:
            return CommonLocalization.sourceAddressDoesNotMatchSeed("Bitcoin SV")
        case .broadcastFailed(let message):
            return NSLocalizedString(message, comment: "")
        case .policyViolation(let message):
            return NSLocalizedString(message, comment: "")
        }
    }
}

enum BitcoinSVWalletEngine {
    private static let satoshisPerBSV: Double = 100_000_000
    private static let minimumFeeRateSatVb: UInt64 = 1
    private static let minimumFeeSatoshis: UInt64 = 1_000
    private static let dustThresholdSatoshis: UInt64 = 546
    private static let maxStandardTransactionBytes: UInt64 = 100_000
    private static let feePolicy = UTXOSatVBytePolicy(
        chainName: "Bitcoin SV",
        baseUnitsPerCoin: satoshisPerBSV,
        dustThreshold: dustThresholdSatoshis,
        minimumRelayFeeRate: minimumFeeRateSatVb,
        minimumAbsoluteFee: minimumFeeSatoshis,
        maxStandardTransactionBytes: maxStandardTransactionBytes
    )
    private static let whatsonchainBroadcastURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainBroadcastURL
    private static let whatsonchainTransactionURLPrefix = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainTransactionURLPrefix
    private static let blockchairPushURL = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.blockchairPushURL
    private static let blockchairTransactionURLPrefix = ChainBackendRegistry.BitcoinSVRuntimeEndpoints.blockchairTransactionURLPrefix
    private static let providerReliabilityDefaultsKey = "bitcoinsv.engine.provider.reliability.v1"
    private static let defaultDerivationPath = "m/44'/236'/0'/0/0"

    private enum Provider: String, CaseIterable {
        case whatsonchain
        case blockchair
    }

    private struct ProviderReliabilityCounter: Codable {
        var successCount: Int
        var failureCount: Int
        var lastUpdatedAt: TimeInterval
    }

    private struct BlockchairStatsResponse: Decodable {
        let data: StatsPayload?
    }

    private struct StatsPayload: Decodable {
        let suggestedTransactionFeePerByteSat: Double?

        enum CodingKeys: String, CodingKey {
            case suggestedTransactionFeePerByteSat = "suggested_transaction_fee_per_byte_sat"
        }
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
        guard !words.isEmpty else { throw BitcoinSVWalletEngineError.invalidSeedPhrase }
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalized,
            coin: .bitcoinSV,
            derivationPath: derivationPath
        )
        return material.address
    }

    static func estimateSendPreview(
        sourceAddress: String,
        maxInputCount: Int? = nil
    ) async throws -> BitcoinSendPreview {
        let fetched = try await BitcoinSVBalanceService.fetchUTXOs(for: sourceAddress)
        let utxos = limitedUTXOs(from: fetched, maxInputCount: maxInputCount)
        let totalInputSatoshis = utxos.reduce(UInt64(0)) { $0 + $1.value }
        let feeRateSatVb = try await fetchLiveFeeRateSatVb()
        let preview = feePolicy.preview(
            for: totalInputSatoshis,
            inputCount: utxos.count,
            feeRate: feeRateSatVb
        )
        let spendable = preview.spendable
        guard spendable > 0 else {
            throw BitcoinSVWalletEngineError.insufficientFunds
        }
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: feeRateSatVb,
            estimatedNetworkFeeBTC: Double(preview.estimatedFee) / satoshisPerBSV,
            feeRateDescription: "\(feeRateSatVb) sat/vB",
            spendableBalance: Double(spendable) / satoshisPerBSV,
            estimatedTransactionBytes: preview.estimatedBytes,
            selectedInputCount: utxos.count,
            usesChangeOutput: nil,
            maxSendable: Double(spendable) / satoshisPerBSV
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        sourceAddress: String,
        to destinationAddress: String,
        amountBSV: Double,
        options: SendOptions? = nil,
        derivationPath: String = "m/44'/236'/0'/0/0",
        providerIDs: Set<String>? = nil
    ) async throws -> SendResult {
        let effectiveOptions = options ?? SendOptions(maxInputCount: nil, enableRBF: false)
        guard AddressValidation.isValidBitcoinSVAddress(destinationAddress) else {
            throw BitcoinSVWalletEngineError.invalidAddress
        }

        let normalizedSeed = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let normalizedDerivationPath = DerivationPathParser.normalize(
            derivationPath,
            fallback: defaultDerivationPath
        )
        let sourceMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .bitcoinSV,
            derivationPath: normalizedDerivationPath
        )
        let normalizedSourceAddress = sourceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceMaterial.address.caseInsensitiveCompare(normalizedSourceAddress) == .orderedSame else {
            throw BitcoinSVWalletEngineError.sourceAddressDoesNotMatchSeed
        }
        let changePath = changeDerivationPath(for: normalizedDerivationPath)
        let changeMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .bitcoinSV,
            derivationPath: changePath
        )

        let amountSatoshis = UInt64((amountBSV * satoshisPerBSV).rounded())
        guard amountSatoshis > 0 else {
            throw BitcoinSVWalletEngineError.invalidUTXO
        }

        let fetchedUTXOs = try await BitcoinSVBalanceService.fetchUTXOs(for: sourceAddress)
        guard !fetchedUTXOs.isEmpty else {
            throw BitcoinSVWalletEngineError.insufficientFunds
        }

        let feeRateSatVb = try await fetchLiveFeeRateSatVb()

        let spendPlan = try selectSpendPlan(
            from: fetchedUTXOs,
            sendAmountSatoshis: amountSatoshis,
            feeRateSatVb: feeRateSatVb,
            maxInputCount: effectiveOptions.maxInputCount
        )
        try validatePolicyRules(
            sendAmountSatoshis: amountSatoshis,
            spendPlan: spendPlan,
            feeRateSatVb: feeRateSatVb
        )

        let sourceScript = try sourceScript(for: sourceAddress)

        var signingInput = BitcoinSigningInput()
        signingInput.hashType = 0x41
        signingInput.amount = Int64(amountSatoshis)
        signingInput.byteFee = Int64(feeRateSatVb)
        signingInput.toAddress = destinationAddress
        signingInput.changeAddress = changeMaterial.address
        signingInput.coinType = CoinType.bitcoin.rawValue
        signingInput.privateKey = [sourceMaterial.privateKeyData]
        signingInput.utxo = try spendPlan.utxos.map {
            try walletCoreUnspentTransaction(
                from: $0,
                sourceScript: sourceScript,
                sequence: effectiveOptions.enableRBF ? 0xFFFFFFFD : UInt32.max
            )
        }

        let output: BitcoinSigningOutput = AnySigner.sign(input: signingInput, coin: .bitcoin)
        if !output.errorMessage.isEmpty || output.encoded.isEmpty {
            let message = output.errorMessage.isEmpty ? "Failed to sign Bitcoin SV transaction." : output.errorMessage
            throw BitcoinSVWalletEngineError.signingFailed(message)
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
            throw BitcoinSVWalletEngineError.signingFailed("Invalid signed Bitcoin SV transaction payload.")
        }
        guard UInt64(rawData.count) <= maxStandardTransactionBytes else {
            throw BitcoinSVWalletEngineError.policyViolation("Bitcoin SV transaction is too large for standard relay policy.")
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

    private static func limitedUTXOs(from utxos: [BitcoinSVUTXO], maxInputCount: Int?) -> [BitcoinSVUTXO] {
        guard let maxInputCount, maxInputCount > 0 else { return utxos }
        return Array(utxos.sorted(by: { $0.value > $1.value }).prefix(maxInputCount))
    }

    private static func walletCoreUnspentTransaction(
        from utxo: BitcoinSVUTXO,
        sourceScript: Data,
        sequence: UInt32
    ) throws -> BitcoinUnspentTransaction {
        guard let txHashData = Data(hexEncoded: utxo.txid), txHashData.count == 32 else {
            throw BitcoinSVWalletEngineError.invalidUTXO
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

    private static func selectSpendPlan(
        from utxos: [BitcoinSVUTXO],
        sendAmountSatoshis: UInt64,
        feeRateSatVb: UInt64,
        maxInputCount: Int?
    ) throws -> UTXOSpendPlan<BitcoinSVUTXO> {
        guard let plan = UTXOSpendPlanner.buildPlan(
            from: utxos,
            targetValue: sendAmountSatoshis,
            dustThreshold: dustThresholdSatoshis,
            maxInputCount: maxInputCount,
            sortBy: { $0.value > $1.value },
            value: \.value,
            feeForLayout: { inputCount, outputCount in
                feePolicy.estimatedFee(
                    inputCount: inputCount,
                    outputCount: outputCount,
                    feeRate: feeRateSatVb
                )
            }
        ) else {
            throw BitcoinSVWalletEngineError.insufficientFunds
        }
        return plan
    }

    private static func validatePolicyRules(
        sendAmountSatoshis: UInt64,
        spendPlan: UTXOSpendPlan<BitcoinSVUTXO>,
        feeRateSatVb: UInt64
    ) throws {
        try feePolicy.validatePlan(
            sendAmount: sendAmountSatoshis,
            spendPlan: spendPlan,
            feeRate: feeRateSatVb,
            error: { BitcoinSVWalletEngineError.policyViolation($0) },
            insufficientFunds: BitcoinSVWalletEngineError.insufficientFunds
        )
    }

    private static func sourceScript(for address: String) throws -> Data {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = BitcoinScript.lockScriptForAddress(address: trimmed, coin: .bitcoin)
        guard !script.data.isEmpty else {
            throw BitcoinSVWalletEngineError.invalidAddress
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
            case .whatsonchain:
                return try await broadcastViaWhatsOnChain(
                    rawTransactionHex: rawTransactionHex,
                    fallbackTransactionHash: fallbackTransactionHash
                )
            case .blockchair:
                return try await broadcastViaBlockchair(
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
            case .whatsonchain:
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let resolved = URL(string: "\(whatsonchainTransactionURLPrefix)\(encoded)") else {
                    throw URLError(.badURL)
                }
                url = resolved
            case .blockchair:
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let resolved = URL(string: "\(blockchairTransactionURLPrefix)\(encoded)") else {
                    throw URLError(.badURL)
                }
                url = resolved
            }

            let (_, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
            guard let http = response as? HTTPURLResponse else {
                throw BitcoinSVWalletEngineError.broadcastFailed("Invalid Bitcoin SV verification response.")
            }
            if (200 ..< 300).contains(http.statusCode) {
                return true
            }
            if http.statusCode == 404 {
                sawNotFound = true
                continue
            }
            throw BitcoinSVWalletEngineError.broadcastFailed("Bitcoin SV verification failed with status \(http.statusCode).")
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

    private static func broadcastViaWhatsOnChain(
        rawTransactionHex: String,
        fallbackTransactionHash: String
    ) async throws -> String {
        guard let url = URL(string: whatsonchainBroadcastURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawTransactionHex.data(using: .utf8)

        let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainWrite)

        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            let message = "Bitcoin SV broadcast failed. \(responseBody)".trimmingCharacters(in: .whitespacesAndNewlines)
            if classifySendBroadcastFailure(message) == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                return fallbackTransactionHash
            }
            throw BitcoinSVWalletEngineError.broadcastFailed(message)
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        throw BitcoinSVWalletEngineError.broadcastFailed("Bitcoin SV broadcast returned an empty transaction hash.")
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

        let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainWrite)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            let message = "Bitcoin SV broadcast failed. \(responseBody)".trimmingCharacters(in: .whitespacesAndNewlines)
            if classifySendBroadcastFailure(message) == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                return fallbackTransactionHash
            }
            throw BitcoinSVWalletEngineError.broadcastFailed(message)
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

        throw BitcoinSVWalletEngineError.broadcastFailed("Bitcoin SV broadcast returned an empty transaction hash.")
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
        throw lastError ?? BitcoinSVWalletEngineError.broadcastFailed("All Bitcoin SV providers failed.")
    }

    private static func fetchLiveFeeRateSatVb() async throws -> UInt64 {
        try await runWithFallback(candidates: orderedProviders(candidates: [.whatsonchain, .blockchair])) { provider in
            switch provider {
            case .whatsonchain:
                return try await fetchWhatsOnChainFeeRateSatVb()
            case .blockchair:
                return try await fetchBlockchairFeeRateSatVb()
            }
        }
    }

    private static func fetchWhatsOnChainFeeRateSatVb() async throws -> UInt64 {
        guard let url = URL(string: ChainBackendRegistry.BitcoinSVRuntimeEndpoints.whatsonchainChainInfoURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BitcoinSVWalletEngineError.broadcastFailed("Failed to fetch Bitcoin SV chain info.")
        }
        let json = try JSONSerialization.jsonObject(with: data)
        guard let candidate = numericValue(in: json, matching: ["relayfee", "relay_fee", "miningfee", "mining_fee", "feerate", "fee_rate"]) else {
            throw BitcoinSVWalletEngineError.broadcastFailed("Bitcoin SV fee-rate data was missing from WhatsOnChain.")
        }
        return try normalizeFeeRateSatVb(candidate, keyHint: "relayfee")
    }

    private static func fetchBlockchairFeeRateSatVb() async throws -> UInt64 {
        guard let url = URL(string: "\(ChainBackendRegistry.BitcoinSVRuntimeEndpoints.blockchairBaseURL)/stats") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BitcoinSVWalletEngineError.broadcastFailed("Failed to fetch Bitcoin SV fee estimates.")
        }
        if let decoded = try? JSONDecoder().decode(BlockchairStatsResponse.self, from: data),
           let value = decoded.data?.suggestedTransactionFeePerByteSat,
           value.isFinite, value > 0 {
            return max(minimumFeeRateSatVb, UInt64(ceil(value)))
        }
        throw BitcoinSVWalletEngineError.broadcastFailed("Bitcoin SV fee-rate data was missing from Blockchair.")
    }

    private static func numericValue(in object: Any, matching keys: Set<String>) -> Double? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let normalizedKey = key.lowercased()
                if keys.contains(normalizedKey) {
                    if let number = value as? NSNumber {
                        return number.doubleValue
                    }
                    if let string = value as? String, let number = Double(string) {
                        return number
                    }
                }
                if let nested = numericValue(in: value, matching: keys) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = numericValue(in: item, matching: keys) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func normalizeFeeRateSatVb(_ value: Double, keyHint: String) throws -> UInt64 {
        guard value.isFinite, value > 0 else {
            throw BitcoinSVWalletEngineError.broadcastFailed("Bitcoin SV fee-rate data was invalid.")
        }
        let normalizedKey = keyHint.lowercased()
        let satPerVb: Double
        if normalizedKey.contains("relay") || normalizedKey.contains("mining") || normalizedKey.contains("fee") {
            satPerVb = value < 1 ? (value * satoshisPerBSV / 1_000.0) : value
        } else {
            satPerVb = value
        }
        guard satPerVb.isFinite, satPerVb > 0 else {
            throw BitcoinSVWalletEngineError.broadcastFailed("Bitcoin SV fee-rate data was invalid.")
        }
        return max(minimumFeeRateSatVb, UInt64(ceil(satPerVb)))
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

    private static func changeDerivationPath(for path: String) -> String {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return path }
        var updated = components.map(String.init)
        if updated.count >= 2 {
            updated[updated.count - 2] = "1"
        }
        return updated.joined(separator: "/")
    }
}
