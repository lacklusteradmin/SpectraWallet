import Foundation
import CryptoKit
import WalletCore

enum LitecoinWalletEngineError: LocalizedError {
    case invalidSeedPhrase
    case invalidAddress
    case signingFailed
    case insufficientFunds
    case networkFailure(String)
    case invalidUTXO
    case sourceAddressDoesNotMatchSeed
    case policyViolation(String)

    var errorDescription: String? {
        switch self {
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Litecoin")
        case .invalidAddress:
            return CommonLocalization.invalidDestinationAddressPrompt("Litecoin")
        case .signingFailed:
            return CommonLocalization.signingTransactionFailed("Litecoin")
        case .insufficientFunds:
            return CommonLocalization.insufficientBalanceForAmountPlusNetworkFee("Litecoin")
        case let .networkFailure(message):
            return NSLocalizedString(message, comment: "")
        case .invalidUTXO:
            return CommonLocalization.invalidUTXOData("Litecoin")
        case .sourceAddressDoesNotMatchSeed:
            return CommonLocalization.sourceAddressDoesNotMatchSeed("Litecoin")
        case .policyViolation(let message):
            return NSLocalizedString(message, comment: "")
        }
    }
}

private struct LitecoinUTXO: Decodable {
    let txid: String
    let vout: Int
    let value: UInt64
}

enum LitecoinWalletEngine {
    private static let litecoinspaceBaseURL = ChainBackendRegistry.LitecoinRuntimeEndpoints.litecoinspaceBaseURL
    private static let litoshiPerLTC: Double = 100_000_000
    private static let minimumFeeRateSatVb: UInt64 = 1
    private static let minimumFeeLitoshi: UInt64 = 1_000
    private static let dustThresholdLitoshi: UInt64 = 1_000
    private static let maxStandardTransactionBytes: UInt64 = 100_000
    private static let feePolicy = UTXOSatVBytePolicy(
        chainName: "Litecoin",
        baseUnitsPerCoin: litoshiPerLTC,
        dustThreshold: dustThresholdLitoshi,
        minimumRelayFeeRate: minimumFeeRateSatVb,
        minimumAbsoluteFee: minimumFeeLitoshi,
        maxStandardTransactionBytes: maxStandardTransactionBytes
    )
    private static let providerReliabilityDefaultsKey = "litecoin.engine.provider.reliability.v1"
    private static let utxoCacheTTLSeconds: TimeInterval = 60
    private static let utxoCacheLock = NSLock()
    private static var utxoCacheByAddress: [String: CachedUTXOSet] = [:]

    private enum Provider: String, CaseIterable {
        case litecoinspace
        case blockcypher
    }

    private struct ProviderReliabilityCounter: Codable {
        var successCount: Int
        var failureCount: Int
        var lastUpdatedAt: TimeInterval
    }

    private struct CachedUTXOSet {
        let utxos: [LitecoinUTXO]
        let updatedAt: Date
    }

    enum ChangeStrategy: String, CaseIterable, Identifiable {
        case derivedChange
        case reuseSourceAddress

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .derivedChange:
                return "Derived change address"
            case .reuseSourceAddress:
                return "Reuse source address"
            }
        }
    }

    struct SendOptions {
        let maxInputCount: Int?
        let changeStrategy: ChangeStrategy
        let enableRBF: Bool
    }

    struct LitecoinSendResult: Equatable {
        let transactionHash: String
        let rawTransactionHex: String
        let verificationStatus: SendBroadcastVerificationStatus
    }

    static func derivedAddress(for seedPhrase: String, account: UInt32 = 0) throws -> String {
        try derivedAddress(
            for: seedPhrase,
            derivationPath: "m/44'/2'/\(account)'/0/0"
        )
    }

    static func derivedAddress(for seedPhrase: String, derivationPath: String) throws -> String {
        let normalized = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let words = BitcoinWalletEngine.normalizedMnemonicWords(from: normalized)
        guard !words.isEmpty else { throw LitecoinWalletEngineError.invalidSeedPhrase }
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalized,
            coin: .litecoin,
            derivationPath: derivationPath
        )
        return material.address
    }

    static func estimateSendPreview(
        seedPhrase: String,
        sourceAddress: String,
        feePriority: BitcoinFeePriority,
        maxInputCount: Int? = nil
    ) async throws -> BitcoinSendPreview {
        let fetched = try await fetchUTXOs(for: sourceAddress)
        let utxos: [LitecoinUTXO]
        if let maxInputCount, maxInputCount > 0 {
            utxos = Array(fetched.sorted(by: { $0.value > $1.value }).prefix(maxInputCount))
        } else {
            utxos = fetched
        }
        let totalInputLitoshi = utxos.reduce(UInt64(0)) { $0 + $1.value }
        let rate = try await fetchFeeRate(priority: feePriority)
        let preview = feePolicy.preview(
            for: totalInputLitoshi,
            inputCount: utxos.count,
            feeRate: rate
        )
        let spendable = preview.spendable
        if spendable == 0 {
            throw LitecoinWalletEngineError.insufficientFunds
        }
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: rate,
            estimatedNetworkFeeBTC: Double(preview.estimatedFee) / litoshiPerLTC,
            feeRateDescription: "\(rate) sat/vB",
            spendableBalance: Double(spendable) / litoshiPerLTC,
            estimatedTransactionBytes: preview.estimatedBytes,
            selectedInputCount: utxos.count,
            usesChangeOutput: nil,
            maxSendable: Double(spendable) / litoshiPerLTC
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        sourceAddress: String,
        to destinationAddress: String,
        amountLTC: Double,
        feePriority: BitcoinFeePriority,
        options: SendOptions? = nil,
        derivationPath: String = "m/44'/2'/0'/0/0",
        providerIDs: Set<String>? = nil
    ) async throws -> LitecoinSendResult {
        let effectiveOptions = options ?? SendOptions(
            maxInputCount: nil,
            changeStrategy: .derivedChange,
            enableRBF: false
        )
        guard AddressValidation.isValidLitecoinAddress(destinationAddress) else {
            throw LitecoinWalletEngineError.invalidAddress
        }

        let normalizedSeed = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
        let keyMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .litecoin,
            derivationPath: derivationPath
        )
        let normalizedSourceAddress = sourceAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyMaterial.address == normalizedSourceAddress else {
            throw LitecoinWalletEngineError.sourceAddressDoesNotMatchSeed
        }
        let changePath = DerivationPathParser.replacingLastTwoSegments(
            in: derivationPath,
            branch: UInt32(WalletDerivationBranch.change.rawValue),
            index: 0,
            fallback: "m/44'/2'/0'/1/0"
        )
        let changeMaterial = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: normalizedSeed,
            coin: .litecoin,
            derivationPath: changePath
        )

        let amountLitoshi = UInt64((amountLTC * litoshiPerLTC).rounded())
        guard amountLitoshi > 0 else {
            throw LitecoinWalletEngineError.invalidUTXO
        }

        let utxos = try await fetchUTXOs(for: sourceAddress)
        guard !utxos.isEmpty else {
            throw LitecoinWalletEngineError.insufficientFunds
        }

        let feeRate = try await fetchFeeRate(priority: feePriority)
        guard let sourceScript = scriptPubKey(for: sourceAddress) else {
            throw LitecoinWalletEngineError.invalidAddress
        }
        let spendPlan = try selectSpendPlan(
            from: utxos,
            sendAmountLitoshi: amountLitoshi,
            feeRateSatVb: feeRate,
            maxInputCount: effectiveOptions.maxInputCount
        )
        try validatePolicyRules(
            sendAmount: amountLitoshi,
            spendPlan: spendPlan,
            feeRateSatVb: feeRate
        )
        let changeAddress: String
        switch effectiveOptions.changeStrategy {
        case .derivedChange:
            changeAddress = changeMaterial.address
        case .reuseSourceAddress:
            changeAddress = sourceAddress
        }

        var signingInput = BitcoinSigningInput()
        signingInput.hashType = 0x01
        signingInput.amount = Int64(amountLitoshi)
        signingInput.byteFee = Int64(feeRate)
        signingInput.toAddress = destinationAddress
        signingInput.changeAddress = changeAddress
        signingInput.coinType = CoinType.litecoin.rawValue
        signingInput.privateKey = [keyMaterial.privateKeyData]
        signingInput.utxo = try spendPlan.utxos.map {
            try walletCoreUnspentTransaction(
                from: $0,
                sourceScript: sourceScript,
                sequence: effectiveOptions.enableRBF ? 0xFFFFFFFD : UInt32.max
            )
        }

        let output: BitcoinSigningOutput = AnySigner.sign(input: signingInput, coin: .litecoin)
        if !output.errorMessage.isEmpty || output.encoded.isEmpty {
            throw LitecoinWalletEngineError.signingFailed
        }
        let rawHex = output.encoded.map { String(format: "%02x", $0) }.joined()
        let txid = try await broadcast(
            rawTransactionHex: rawHex,
            fallbackTransactionHash: computeTransactionHash(fromRawHex: rawHex),
            providerIDs: providerIDs
        )
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(txid: txid, providerIDs: providerIDs)
        return LitecoinSendResult(
            transactionHash: txid,
            rawTransactionHex: rawHex,
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> LitecoinSendResult {
        let normalizedRawHex = rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawData = Data(hexEncoded: normalizedRawHex), !rawData.isEmpty else {
            throw LitecoinWalletEngineError.signingFailed
        }
        guard UInt64(rawData.count) <= maxStandardTransactionBytes else {
            throw LitecoinWalletEngineError.policyViolation("Litecoin transaction is too large for standard relay policy.")
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
        return LitecoinSendResult(
            transactionHash: txid,
            rawTransactionHex: normalizedRawHex,
            verificationStatus: verificationStatus
        )
    }

    private static func fetchUTXOs(for address: String) async throws -> [LitecoinUTXO] {
        var providerErrors: [String] = []
        var providerResults: [Provider: [LitecoinUTXO]] = [:]
        let ordered = orderedProviders(candidates: [.litecoinspace, .blockcypher])

        for provider in ordered {
            do {
                let utxos: [LitecoinUTXO]
                switch provider {
                case .litecoinspace:
                    utxos = try await fetchUTXOsViaLitecoinspace(for: address)
                case .blockcypher:
                    utxos = try await fetchUTXOsViaBlockcypher(for: address)
                }
                recordProviderAttempt(provider: provider, success: true)
                providerResults[provider] = sanitizeUTXOs(utxos)
            } catch {
                recordProviderAttempt(provider: provider, success: false)
                providerErrors.append("\(provider.rawValue): \(error.localizedDescription)")
            }
        }

        if providerResults.isEmpty {
            if let cached = cachedUTXOs(for: address) {
                return cached
            }
            throw LitecoinWalletEngineError.networkFailure("All Litecoin UTXO providers failed (\(providerErrors.joined(separator: " | "))).")
        }

        let merged: [LitecoinUTXO]
        if let litecoinspaceUTXOs = providerResults[.litecoinspace],
           let blockcypherUTXOs = providerResults[.blockcypher] {
            merged = try mergeConsistentUTXOs(
                litecoinspaceUTXOs: litecoinspaceUTXOs,
                blockcypherUTXOs: blockcypherUTXOs
            )
        } else {
            merged = providerResults.values.first ?? []
        }

        if !merged.isEmpty {
            cacheUTXOs(merged, for: address)
            return merged
        }

        if let cached = cachedUTXOs(for: address) {
            return cached
        }

        return []
    }

    private static func fetchUTXOsViaLitecoinspace(for address: String) async throws -> [LitecoinUTXO] {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(litecoinspaceBaseURL)/address/\(encoded)/utxo") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.data(from: url, profile: .litecoinRead)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw LitecoinWalletEngineError.networkFailure("Failed to fetch Litecoin UTXOs.")
        }
        return try JSONDecoder().decode([LitecoinUTXO].self, from: data)
    }

    private static func fetchUTXOsViaBlockcypher(for address: String) async throws -> [LitecoinUTXO] {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = BlockCypherProvider.url(
                path: "/addrs/\(encoded)?unspentOnly=true&includeScript=true",
                network: .litecoinMainnet
              ) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.data(from: url, profile: .litecoinRead)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw LitecoinWalletEngineError.networkFailure("Failed to fetch Litecoin UTXOs.")
        }
        let decoded = try JSONDecoder().decode(BlockCypherProvider.AddressRefsResponse.self, from: data)
        let refs = (decoded.txrefs ?? []) + (decoded.unconfirmedTxrefs ?? [])
        return refs.compactMap {
            guard let txOutputIndex = $0.txOutputIndex, let value = $0.value else { return nil }
            return LitecoinUTXO(txid: $0.txHash, vout: txOutputIndex, value: value)
        }
    }

    private static func sanitizeUTXOs(_ utxos: [LitecoinUTXO]) -> [LitecoinUTXO] {
        var deduped: [String: LitecoinUTXO] = [:]
        for utxo in utxos where utxo.value > 0 {
            let key = outpointKey(hash: utxo.txid, index: utxo.vout)
            if let existing = deduped[key] {
                deduped[key] = existing.value >= utxo.value ? existing : utxo
            } else {
                deduped[key] = utxo
            }
        }

        return deduped.values.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            if lhs.txid != rhs.txid {
                return lhs.txid < rhs.txid
            }
            return lhs.vout < rhs.vout
        }
    }

    private static func mergeConsistentUTXOs(
        litecoinspaceUTXOs: [LitecoinUTXO],
        blockcypherUTXOs: [LitecoinUTXO]
    ) throws -> [LitecoinUTXO] {
        let litecoinspaceMap = Dictionary(uniqueKeysWithValues: litecoinspaceUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })
        let blockcypherMap = Dictionary(uniqueKeysWithValues: blockcypherUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })

        let litecoinspaceKeys = Set(litecoinspaceMap.keys)
        let blockcypherKeys = Set(blockcypherMap.keys)
        let overlap = litecoinspaceKeys.intersection(blockcypherKeys)

        for key in overlap {
            guard let lhs = litecoinspaceMap[key], let rhs = blockcypherMap[key] else { continue }
            if lhs.value != rhs.value {
                throw LitecoinWalletEngineError.networkFailure("Litecoin UTXO providers returned conflicting values for the same outpoint.")
            }
        }

        if !litecoinspaceKeys.isEmpty, !blockcypherKeys.isEmpty, overlap.isEmpty {
            throw LitecoinWalletEngineError.networkFailure("Litecoin UTXO providers disagree on the spendable set.")
        }

        let merged = Array(litecoinspaceMap.values) + blockcypherMap.compactMap { key, value in
            litecoinspaceMap[key] == nil ? value : nil
        }
        return sanitizeUTXOs(merged)
    }

    private static func outpointKey(hash: String, index: Int) -> String {
        "\(hash.lowercased()):\(index)"
    }

    private static func normalizedAddressCacheKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func cacheUTXOs(_ utxos: [LitecoinUTXO], for address: String) {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress[key] = CachedUTXOSet(utxos: utxos, updatedAt: Date())
    }

    private static func cachedUTXOs(for address: String) -> [LitecoinUTXO]? {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        guard let cached = utxoCacheByAddress[key] else { return nil }
        guard Date().timeIntervalSince(cached.updatedAt) <= utxoCacheTTLSeconds else {
            utxoCacheByAddress[key] = nil
            return nil
        }
        return cached.utxos
    }

    private static func fetchFeeRate(priority: BitcoinFeePriority) async throws -> UInt64 {
        try await runWithFallback(candidates: orderedProviders(candidates: [.litecoinspace, .blockcypher])) { provider in
            switch provider {
            case .litecoinspace:
                return try await fetchFeeRateViaLitecoinspace(priority: priority)
            case .blockcypher:
                return try await fetchFeeRateViaBlockcypher(priority: priority)
            }
        }
    }

    private static func fetchFeeRateViaLitecoinspace(priority: BitcoinFeePriority) async throws -> UInt64 {
        guard let url = URL(string: "\(litecoinspaceBaseURL)/fee-estimates") else { throw URLError(.badURL) }
        let (data, response) = try await ProviderHTTP.data(from: url, profile: .litecoinRead)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw LitecoinWalletEngineError.networkFailure("Failed to fetch Litecoin fee estimates.")
        }
        let estimates = try JSONDecoder().decode([String: Double].self, from: data)
        let picked: Double
        switch priority {
        case .economy:
            picked = estimates["6"] ?? estimates["10"] ?? 5
        case .normal:
            picked = estimates["3"] ?? estimates["6"] ?? 8
        case .priority:
            picked = estimates["1"] ?? estimates["2"] ?? 12
        }
        return max(1, UInt64(ceil(picked)))
    }

    private static func fetchFeeRateViaBlockcypher(priority: BitcoinFeePriority) async throws -> UInt64 {
        guard let url = BlockCypherProvider.url(path: "", network: .litecoinMainnet) else { throw URLError(.badURL) }
        let (data, response) = try await ProviderHTTP.data(from: url, profile: .litecoinRead)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw LitecoinWalletEngineError.networkFailure("Failed to fetch Litecoin fee estimates.")
        }
        let decoded = try JSONDecoder().decode(BlockCypherProvider.NetworkFeesResponse.self, from: data)
        let feePerKB: Double
        switch priority {
        case .economy:
            feePerKB = decoded.lowFeePerKB ?? decoded.mediumFeePerKB ?? 5_000
        case .normal:
            feePerKB = decoded.mediumFeePerKB ?? decoded.lowFeePerKB ?? 8_000
        case .priority:
            feePerKB = decoded.highFeePerKB ?? decoded.mediumFeePerKB ?? 12_000
        }
        return max(1, UInt64(ceil(feePerKB / 1_000.0)))
    }

    private static func broadcast(
        rawTransactionHex: String,
        fallbackTransactionHash: String,
        providerIDs: Set<String>? = nil
    ) async throws -> String {
        try await runWithFallback(candidates: orderedProviders(candidates: filteredProviders(providerIDs: providerIDs))) { provider in
            switch provider {
            case .litecoinspace:
                return try await broadcastViaLitecoinspace(
                    rawTransactionHex: rawTransactionHex,
                    fallbackTransactionHash: fallbackTransactionHash
                )
            case .blockcypher:
                return try await broadcastViaBlockcypher(
                    rawTransactionHex: rawTransactionHex,
                    fallbackTransactionHash: fallbackTransactionHash
                )
            }
        }
    }

    private static func broadcastViaLitecoinspace(rawTransactionHex: String, fallbackTransactionHash: String) async throws -> String {
        guard let url = URL(string: "\(litecoinspaceBaseURL)/tx") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawTransactionHex.data(using: .utf8)
        let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinWrite)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown broadcast failure."
            if classifySendBroadcastFailure(message) == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                return fallbackTransactionHash
            }
            throw LitecoinWalletEngineError.networkFailure("Litecoin broadcast failed: \(message)")
        }
        let txid = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if txid.isEmpty {
            throw LitecoinWalletEngineError.networkFailure("Litecoin broadcast succeeded but no txid returned.")
        }
        return txid
    }

    private static func broadcastViaBlockcypher(rawTransactionHex: String, fallbackTransactionHash: String) async throws -> String {
        guard let url = BlockCypherProvider.url(path: "/txs/push", network: .litecoinMainnet) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["tx": rawTransactionHex], options: [])
        let (data, response) = try await ProviderHTTP.data(for: request, profile: .litecoinWrite)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown broadcast failure."
            if classifySendBroadcastFailure(message) == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                return fallbackTransactionHash
            }
            throw LitecoinWalletEngineError.networkFailure("Litecoin broadcast failed: \(message)")
        }
        if let decoded = try? JSONDecoder().decode(BlockCypherProvider.BroadcastResponse.self, from: data),
           let txid = decoded.tx?.hash,
           !txid.isEmpty {
            return txid
        }
        throw LitecoinWalletEngineError.networkFailure("Litecoin broadcast succeeded but no txid returned.")
    }

    private static func computeTransactionHash(fromRawHex rawHex: String) -> String {
        guard let rawData = Data(hexEncoded: rawHex) else { return "" }
        let firstHash = SHA256.hash(data: rawData)
        let secondHash = SHA256.hash(data: Data(firstHash))
        return Data(secondHash).reversed().map { String(format: "%02x", $0) }.joined()
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
                // Space provider failovers to avoid immediate repeat hits on throttled endpoints.
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw lastError ?? LitecoinWalletEngineError.networkFailure("All Litecoin providers failed.")
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
            return [.litecoinspace, .blockcypher]
        }
        let normalized = Set(providerIDs.map { $0.lowercased() })
        let providers = [Provider.litecoinspace, .blockcypher].filter { normalized.contains($0.rawValue) }
        return providers.isEmpty ? [.litecoinspace, .blockcypher] : providers
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
        guard !trimmed.isEmpty else { return false }

        var sawNotFound = false
        var lastError: Error?

        for provider in orderedProviders(candidates: filteredProviders()) {
            do {
            switch provider {
            case .litecoinspace:
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: "\(litecoinspaceBaseURL)/tx/\(encoded)") else {
                    throw URLError(.badURL)
                }
                let (_, response) = try await ProviderHTTP.data(from: url, profile: .litecoinRead)
                guard let http = response as? HTTPURLResponse else {
                    throw LitecoinWalletEngineError.networkFailure("Invalid Litecoin verification response.")
                }
                if (200 ..< 300).contains(http.statusCode) {
                    return true
                }
                if http.statusCode == 404 {
                    sawNotFound = true
                    continue
                }
                throw LitecoinWalletEngineError.networkFailure("Litecoin verification failed with status \(http.statusCode).")
            case .blockcypher:
                guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = BlockCypherProvider.url(path: "/txs/\(encoded)", network: .litecoinMainnet) else {
                    throw URLError(.badURL)
                }
                let (_, response) = try await ProviderHTTP.data(from: url, profile: .litecoinRead)
                guard let http = response as? HTTPURLResponse else {
                    throw LitecoinWalletEngineError.networkFailure("Invalid Litecoin verification response.")
                }
                if (200 ..< 300).contains(http.statusCode) {
                    return true
                }
                if http.statusCode == 404 {
                    sawNotFound = true
                    continue
                }
                throw LitecoinWalletEngineError.networkFailure("Litecoin verification failed with status \(http.statusCode).")
            }
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

    private static func walletCoreUnspentTransaction(
        from utxo: LitecoinUTXO,
        sourceScript: Data,
        sequence: UInt32
    ) throws -> BitcoinUnspentTransaction {
        guard let txHashData = Data(hexEncoded: utxo.txid), txHashData.count == 32 else {
            throw LitecoinWalletEngineError.invalidUTXO
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
        from utxos: [LitecoinUTXO],
        sendAmountLitoshi: UInt64,
        feeRateSatVb: UInt64,
        maxInputCount: Int?
    ) throws -> UTXOSpendPlan<LitecoinUTXO> {
        guard let plan = UTXOSpendPlanner.buildPlan(
            from: utxos,
            targetValue: sendAmountLitoshi,
            dustThreshold: dustThresholdLitoshi,
            maxInputCount: maxInputCount,
            sortBy: { $0.value > $1.value },
            value: \.value,
            feeForLayout: { inputCount, outputCount in
                feePolicy.estimatedFee(
                    estimatedBytes: UTXOSpendPlanner.estimateTransactionBytes(
                        inputCount: inputCount,
                        outputCount: outputCount
                    ),
                    feeRate: feeRateSatVb
                )
            }
        ) else {
            throw LitecoinWalletEngineError.insufficientFunds
        }
        return plan
    }

    private static func validatePolicyRules(
        sendAmount: UInt64,
        spendPlan: UTXOSpendPlan<LitecoinUTXO>,
        feeRateSatVb: UInt64
    ) throws {
        try feePolicy.validatePlan(
            sendAmount: sendAmount,
            spendPlan: spendPlan,
            feeRate: feeRateSatVb,
            error: { LitecoinWalletEngineError.policyViolation($0) },
            insufficientFunds: LitecoinWalletEngineError.insufficientFunds
        )
    }

    private static func scriptPubKey(for address: String) -> Data? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let script = UTXOAddressCodec.legacyScriptPubKey(
            for: trimmed,
            p2pkhVersions: [0x30, 0x6f],
            p2shVersions: [0x32, 0x3a, 0xc4]
        ) {
            return script
        }

        if let program = decodeBech32WitnessProgram(address: trimmed) {
            let versionByte = program.version == 0 ? UInt8(0x00) : UInt8(0x50 + program.version)
            return Data([versionByte, UInt8(program.program.count)]) + program.program
        }

        return nil
    }

    private static func decodeBech32WitnessProgram(address: String) -> (version: UInt8, program: Data)? {
        let lower = address.lowercased()
        guard lower.hasPrefix("ltc1") || lower.hasPrefix("tltc1") else { return nil }
        guard let separatorIndex = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[..<separatorIndex])
        guard hrp == "ltc" || hrp == "tltc" else { return nil }
        let dataPart = String(lower[lower.index(after: separatorIndex)...])
        guard dataPart.count >= 6 else { return nil }
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        var charsetMap: [Character: Int] = [:]
        for (i, c) in charset.enumerated() {
            charsetMap[c] = i
        }
        let values: [UInt8] = dataPart.compactMap { ch in
            guard let v = charsetMap[ch] else { return nil }
            return UInt8(v)
        }
        guard values.count == dataPart.count else { return nil }
        guard verifyBech32Checksum(hrp: hrp, data: values) else { return nil }
        let payload = Array(values.dropLast(6))
        guard let version = payload.first, version <= 16 else { return nil }
        let program5Bit = Array(payload.dropFirst())
        guard let program = convertBits(program5Bit, fromBits: 5, toBits: 8, pad: false),
              !program.isEmpty, program.count >= 2, program.count <= 40 else {
            return nil
        }
        if version == 0 && !(program.count == 20 || program.count == 32) {
            return nil
        }
        return (version, Data(program))
    }

    private static func verifyBech32Checksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = hrp.utf8.map { UInt8($0) }
        let high = bytes.map { $0 >> 5 }
        let low = bytes.map { $0 & 0x1f }
        return high + [0] + low
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for value in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(value)
            for i in 0 ..< 5 where ((top >> i) & 1) != 0 {
                chk ^= generators[i]
            }
        }
        return chk
    }

    private static func convertBits(_ data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        for value in data {
            let v = Int(value)
            if (v >> fromBits) != 0 { return nil }
            acc = (acc << fromBits) | v
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        return result
    }

}
