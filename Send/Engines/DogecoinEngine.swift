import Foundation
import CryptoKit
import WalletCore

enum DogecoinNetworkMode: String, CaseIterable, Codable, Identifiable {
    case mainnet
    case testnet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        }
    }
}

struct DogecoinWalletEngine {
    static let derivationScanLimit = 200
    static let maxStandardTransactionBytes = 100_000
    static let minRelayFeePerKB: Double = 0.01
    static let dustThresholdDOGE: Double = 0.01
    static let koinuPerDOGE: Double = 100_000_000
    static let feePolicy = UTXOKilobyteFeePolicy(
        baseUnitsPerCoin: koinuPerDOGE,
        dustThreshold: UInt64((dustThresholdDOGE * koinuPerDOGE).rounded()),
        minimumRelayFeePerKB: minRelayFeePerKB
    )
    static let networkTimeoutSeconds: TimeInterval = 12
    static let networkRetryCount = 2
    static let utxoCacheTTLSeconds: TimeInterval = 180
    static let utxoCacheLock = NSLock()
    static var utxoCacheByAddress: [String: CachedUTXOSet] = [:]

    struct SigningKeyMaterial {
        let address: String
        let privateKeyData: Data
        let signingDerivationPath: String
        let changeAddress: String
        let changeDerivationPath: String
    }

    typealias DogecoinSpendPlan = UTXOSpendPlan<DogecoinUTXO>

    struct DogecoinWalletCoreSigningRequest {
        let keyMaterial: SigningKeyMaterial
        let utxos: [DogecoinUTXO]
        let destinationAddress: String
        let amountDOGE: Double
        let changeAddress: String
        let feeRateDOGEPerKB: Double
    }

    struct DogecoinWalletCoreSigningResult {
        let encodedTransaction: Data
        let transactionHash: String
    }

    enum FeePriority: String, CaseIterable, Equatable {
        case economy
        case normal
        case priority
    }

    struct DogecoinSendPreview: Equatable {
        let spendableBalanceDOGE: Double
        let requestedAmountDOGE: Double
        let estimatedNetworkFeeDOGE: Double
        let estimatedFeeRateDOGEPerKB: Double
        let estimatedTransactionBytes: Int
        let selectedInputCount: Int
        let usesChangeOutput: Bool
        let feePriority: FeePriority
        let maxSendableDOGE: Double
        let spendableBalance: Double
        let feeRateDescription: String?
        let maxSendable: Double
    }

    enum PostBroadcastVerificationStatus: Equatable {
        case verified
        case deferred
        case failed(String)
    }

    struct DogecoinSendResult: Equatable {
        let transactionHash: String
        let verificationStatus: PostBroadcastVerificationStatus
        let derivationMetadata: DerivationMetadata
        let rawTransactionHex: String
    }

    struct DogecoinRebroadcastResult: Equatable {
        let transactionHash: String
        let verificationStatus: PostBroadcastVerificationStatus
    }

    struct DerivationMetadata: Equatable {
        let sourceAddress: String
        let sourceDerivationPath: String
        let changeAddress: String
        let changeDerivationPath: String
    }

    struct DogecoinUTXO: Decodable {
        let transactionHash: String
        let index: Int
        let value: UInt64

        enum CodingKeys: String, CodingKey {
            case transactionHash = "transaction_hash"
            case index
            case value
        }
    }

    struct CachedUTXOSet {
        let utxos: [DogecoinUTXO]
        let updatedAt: Date
    }

    static func resetUTXOCache() {
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress.removeAll()
    }

    static func networkMode(for wallet: ImportedWallet) -> DogecoinNetworkMode {
        wallet.dogecoinNetworkMode
    }

    @discardableResult
    static func sendInBackground(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        to recipientAddress: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        changeIndex: Int? = nil,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) async throws -> DogecoinSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try send(
                        from: importedWallet,
                        seedPhrase: seedPhrase,
                        to: recipientAddress,
                        amountDOGE: amountDOGE,
                        feePriority: feePriority,
                        changeIndex: changeIndex,
                        maxInputCount: maxInputCount,
                        derivationAccount: derivationAccount
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func rebroadcastSignedTransactionInBackground(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil,
        networkMode: DogecoinNetworkMode = .mainnet
    ) async throws -> DogecoinRebroadcastResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try rebroadcastSignedTransaction(
                        rawTransactionHex: rawTransactionHex,
                        expectedTransactionHash: expectedTransactionHash,
                        networkMode: networkMode
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func derivedAddress(for seedPhrase: String, account: Int = 0) throws -> String {
        try derivedAddress(for: seedPhrase, networkMode: .mainnet, account: account)
    }

    static func derivedAddress(
        for seedPhrase: String,
        networkMode: DogecoinNetworkMode,
        account: Int = 0
    ) throws -> String {
        try SeedPhraseAddressDerivation.dogecoinAddress(
            seedPhrase: seedPhrase,
            networkMode: networkMode,
            isChange: false,
            index: 0,
            account: account
        )
    }

    static func derivedAddress(for seedPhrase: String, isChange: Bool, index: Int, account: Int = 0) throws -> String {
        try derivedAddress(
            for: seedPhrase,
            networkMode: .mainnet,
            isChange: isChange,
            index: index,
            account: account
        )
    }

    static func derivedAddress(
        for seedPhrase: String,
        networkMode: DogecoinNetworkMode,
        isChange: Bool,
        index: Int,
        account: Int = 0
    ) throws -> String {
        try SeedPhraseAddressDerivation.dogecoinAddress(
            seedPhrase: seedPhrase,
            networkMode: networkMode,
            isChange: isChange,
            index: index,
            account: account
        )
    }

    static func fetchSendPreview(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) throws -> DogecoinSendPreview {
        guard amountDOGE > 0 else {
            throw DogecoinWalletEngineError.invalidAmount
        }

        let keyMaterial = try deriveSigningKeyMaterial(
            seedPhrase: seedPhrase,
            expectedAddress: importedWallet.dogecoinAddress,
            networkMode: networkMode(for: importedWallet),
            derivationAccount: derivationAccount
        )
        let spendableUTXOs = try fetchSpendableUTXOs(for: keyMaterial.address, networkMode: networkMode(for: importedWallet))
        guard !spendableUTXOs.isEmpty else {
            throw DogecoinWalletEngineError.noSpendableUTXOs
        }

        let feeRateDOGEPerKB = try resolveNetworkFeeRateDOGEPerKB(
            feePriority: feePriority,
            networkMode: networkMode(for: importedWallet)
        )
        let spendPlan = try buildSpendPlan(
            from: spendableUTXOs,
            amountDOGE: amountDOGE,
            feeRateDOGEPerKB: feeRateDOGEPerKB,
            maxInputCount: maxInputCount
        )
        let spendableBalanceDOGE = Double(spendableUTXOs.reduce(0) { $0 + $1.value }) / koinuPerDOGE
        let preview = try rustPreviewPlan(from: spendableUTXOs, feeRateDOGEPerKB: feeRateDOGEPerKB)
        let maxSendableDOGE = Double(preview.spendableValue) / koinuPerDOGE

        return DogecoinSendPreview(
            spendableBalanceDOGE: spendableBalanceDOGE,
            requestedAmountDOGE: amountDOGE,
            estimatedNetworkFeeDOGE: Double(spendPlan.fee) / koinuPerDOGE,
            estimatedFeeRateDOGEPerKB: feeRateDOGEPerKB,
            estimatedTransactionBytes: spendPlan.estimatedTransactionBytes,
            selectedInputCount: spendPlan.utxos.count,
            usesChangeOutput: spendPlan.usesChangeOutput,
            feePriority: feePriority,
            maxSendableDOGE: maxSendableDOGE,
            spendableBalance: spendableBalanceDOGE,
            feeRateDescription: String(format: "%.4f DOGE/KB", feeRateDOGEPerKB),
            maxSendable: maxSendableDOGE
        )
    }

    static func fetchSendPreviewInBackground(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) async throws -> DogecoinSendPreview {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let preview = try fetchSendPreview(
                        from: importedWallet,
                        seedPhrase: seedPhrase,
                        amountDOGE: amountDOGE,
                        feePriority: feePriority,
                        maxInputCount: maxInputCount,
                        derivationAccount: derivationAccount
                    )
                    continuation.resume(returning: preview)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @discardableResult
    static func send(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        to recipientAddress: String,
        amountDOGE: Double,
        feePriority: FeePriority = .normal,
        changeIndex: Int? = nil,
        maxInputCount: Int? = nil,
        derivationAccount: UInt32 = 0
    ) throws -> DogecoinSendResult {
        let networkMode = networkMode(for: importedWallet)
        guard AddressValidation.isValidDogecoinAddress(recipientAddress, networkMode: networkMode) else {
            throw DogecoinWalletEngineError.invalidRecipientAddress
        }
        guard amountDOGE > 0 else {
            throw DogecoinWalletEngineError.invalidAmount
        }

        let keyMaterial = try deriveSigningKeyMaterial(
            seedPhrase: seedPhrase,
            expectedAddress: importedWallet.dogecoinAddress,
            networkMode: networkMode,
            derivationAccount: derivationAccount
        )

        let spendableUTXOs = try fetchSpendableUTXOs(for: keyMaterial.address, networkMode: networkMode)
        guard !spendableUTXOs.isEmpty else {
            throw DogecoinWalletEngineError.noSpendableUTXOs
        }

        let feeRateDOGEPerKB = try resolveNetworkFeeRateDOGEPerKB(
            feePriority: feePriority,
            networkMode: networkMode
        )
            let spendPlan = try buildSpendPlan(
                from: spendableUTXOs,
                amountDOGE: amountDOGE,
                feeRateDOGEPerKB: feeRateDOGEPerKB,
                maxInputCount: maxInputCount
            )
            guard spendPlan.estimatedTransactionBytes <= maxStandardTransactionBytes else {
                throw DogecoinWalletEngineError.transactionTooLarge
            }

            let resolvedChangeAddress = try resolveChangeAddress(
                seedPhrase: seedPhrase,
                keyMaterial: keyMaterial,
                networkMode: networkMode,
                changeIndex: changeIndex,
                derivationAccount: derivationAccount
            )
            let signingResult = try walletCoreSignTransaction(
                keyMaterial: keyMaterial,
                utxos: spendPlan.utxos,
                destinationAddress: recipientAddress,
                amountDOGE: amountDOGE,
                changeAddress: resolvedChangeAddress.address,
                feeRateDOGEPerKB: feeRateDOGEPerKB
            )
            let rawHex = signingResult.encodedTransaction.map { String(format: "%02x", $0) }.joined()
            guard !rawHex.isEmpty else {
                throw DogecoinWalletEngineError.transactionSignFailed
            }
            let rawByteCount = rawHex.count / 2
            guard rawByteCount <= maxStandardTransactionBytes else {
            throw DogecoinWalletEngineError.transactionTooLarge
        }

            try broadcastRawTransaction(rawHex, networkMode: networkMode)
            let txid = signingResult.transactionHash.isEmpty ? computeTXID(fromRawHex: rawHex) : signingResult.transactionHash
            let verificationStatus = verifyBroadcastedTransactionIfAvailable(txid: txid, networkMode: networkMode)
        return DogecoinSendResult(
            transactionHash: txid,
            verificationStatus: verificationStatus,
            derivationMetadata: DerivationMetadata(
                sourceAddress: keyMaterial.address,
                sourceDerivationPath: keyMaterial.signingDerivationPath,
                changeAddress: resolvedChangeAddress.address,
                changeDerivationPath: resolvedChangeAddress.derivationPath
            ),
            rawTransactionHex: rawHex
        )
    }

    static func rebroadcastSignedTransaction(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil,
        networkMode: DogecoinNetworkMode = .mainnet
    ) throws -> DogecoinRebroadcastResult {
        let trimmedRawHex = rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRawHex.isEmpty, let rawData = Data(hexEncoded: trimmedRawHex) else {
            throw DogecoinWalletEngineError.broadcastFailed("Signed transaction hex is missing or invalid.")
        }
        guard rawData.count <= maxStandardTransactionBytes else {
            throw DogecoinWalletEngineError.transactionTooLarge
        }

        let computedTXID = computeTXID(fromRawHex: trimmedRawHex)
        guard !computedTXID.isEmpty else {
            throw DogecoinWalletEngineError.broadcastFailed("Unable to compute txid from signed transaction.")
        }
        if let expectedTransactionHash {
            let expected = expectedTransactionHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard expected.isEmpty || expected == computedTXID.lowercased() else {
                throw DogecoinWalletEngineError.broadcastFailed("Signed transaction does not match the recorded txid.")
            }
        }

        try broadcastRawTransaction(trimmedRawHex, networkMode: networkMode)
        let verificationStatus = verifyPresenceOnlyIfAvailable(txid: computedTXID, networkMode: networkMode)
        return DogecoinRebroadcastResult(
            transactionHash: computedTXID,
            verificationStatus: verificationStatus
        )
    }

}

extension DogecoinWalletEngine {
    static func resolveChangeAddress(
        seedPhrase: String,
        keyMaterial: SigningKeyMaterial,
        networkMode: DogecoinNetworkMode,
        changeIndex: Int?,
        derivationAccount: UInt32
    ) throws -> (address: String, derivationPath: String) {
        guard let changeIndex else {
            return (keyMaterial.changeAddress, keyMaterial.changeDerivationPath)
        }

        let address = try derivedAddress(
            for: seedPhrase,
            networkMode: networkMode,
            isChange: true,
            index: changeIndex,
            account: Int(derivationAccount)
        )
        return (
            address,
            WalletDerivationPath.dogecoin(
                account: derivationAccount,
                branch: .change,
                index: UInt32(changeIndex)
            )
        )
    }

    static func deriveSigningKeyMaterial(
        seedPhrase: String,
        expectedAddress: String?,
        networkMode: DogecoinNetworkMode,
        derivationAccount: UInt32
    ) throws -> SigningKeyMaterial {
        try deriveSigningKeyMaterialWithWalletCore(
            seedPhrase: seedPhrase,
            expectedAddress: expectedAddress,
            networkMode: networkMode,
            derivationAccount: derivationAccount
        )
    }

    static func deriveSigningKeyMaterialWithWalletCore(
        seedPhrase: String,
        expectedAddress: String?,
        networkMode: DogecoinNetworkMode,
        derivationAccount: UInt32
    ) throws -> SigningKeyMaterial {
        let normalizedSeedPhrase = SeedPhraseSafety.normalizedPhrase(from: seedPhrase)
        let normalizedExpectedAddress: String?
        if let expectedAddress {
            normalizedExpectedAddress = expectedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            normalizedExpectedAddress = nil
        }
        let mnemonicWords = SeedPhraseSafety.normalizedWords(from: normalizedSeedPhrase)
        guard !mnemonicWords.isEmpty else {
            throw DogecoinWalletEngineError.invalidSeedPhrase
        }
        for index in 0 ..< derivationScanLimit {
            let signingMaterial = try SeedPhraseSigningMaterial.material(
                seedPhrase: normalizedSeedPhrase,
                coin: .dogecoin,
                account: derivationAccount,
                branch: .external,
                index: UInt32(index)
            )
            let signingAddress = try nativeDerivedAddress(
                privateKeyData: signingMaterial.privateKeyData,
                networkMode: networkMode
            )
            if let normalizedExpectedAddress, normalizedExpectedAddress != signingAddress {
                continue
            }

            let changeMaterial = try SeedPhraseSigningMaterial.material(
                seedPhrase: normalizedSeedPhrase,
                coin: .dogecoin,
                account: derivationAccount,
                branch: .change,
                index: UInt32(index)
            )
            let changeAddress = try nativeDerivedAddress(
                privateKeyData: changeMaterial.privateKeyData,
                networkMode: networkMode
            )
            return SigningKeyMaterial(
                address: signingAddress,
                privateKeyData: signingMaterial.privateKeyData,
                signingDerivationPath: signingMaterial.derivationPath,
                changeAddress: changeAddress,
                changeDerivationPath: changeMaterial.derivationPath
            )
        }
        throw DogecoinWalletEngineError.walletAddressNotDerivedFromSeed
    }

    static func walletCoreDerivedAddress(
        seedPhrase: String,
        networkMode: DogecoinNetworkMode,
        isChange: Bool,
        index: Int,
        account: Int
    ) throws -> String {
        guard index >= 0 else {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
        let normalizedSeedPhrase = SeedPhraseSafety.normalizedPhrase(from: seedPhrase)
        let mnemonicWords = SeedPhraseSafety.normalizedWords(from: normalizedSeedPhrase)
        guard !mnemonicWords.isEmpty else {
            throw DogecoinWalletEngineError.invalidSeedPhrase
        }
        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: normalizedSeedPhrase,
            coin: .dogecoin,
            account: UInt32(max(0, account)),
            branch: isChange ? .change : .external,
            index: UInt32(index)
        )
        guard !material.address.isEmpty else {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
        return try nativeDerivedAddress(
            privateKeyData: material.privateKeyData,
            networkMode: networkMode
        )
    }
}

extension DogecoinWalletEngine {
    private static let mainnetP2PKHVersion: UInt8 = 0x1e
    private static let testnetP2PKHVersion: UInt8 = 0x71
    private static let mainnetP2SHVersion: UInt8 = 0x16
    private static let testnetP2SHVersion: UInt8 = 0xc4

    static func standardScriptPubKey(for address: String) -> Data? {
        UTXOAddressCodec.legacyScriptPubKey(
            for: address,
            p2pkhVersions: [mainnetP2PKHVersion, testnetP2PKHVersion],
            p2shVersions: [mainnetP2SHVersion, testnetP2SHVersion]
        )
    }

    static func nativeDerivedAddress(
        privateKeyData: Data,
        networkMode: DogecoinNetworkMode
    ) throws -> String {
        do {
            return try UTXOAddressCodec.legacyP2PKHAddress(
                privateKeyData: privateKeyData,
                version: p2pkhVersion(for: networkMode)
            )
        } catch {
            throw DogecoinWalletEngineError.keyDerivationFailed
        }
    }

    static func p2pkhVersion(for networkMode: DogecoinNetworkMode) -> UInt8 {
        switch networkMode {
        case .mainnet:
            return mainnetP2PKHVersion
        case .testnet:
            return testnetP2PKHVersion
        }
    }

    static func computeTXID(fromRawHex rawHex: String) -> String {
        guard let rawData = Data(hexEncoded: rawHex) else {
            return ""
        }
        let firstHash = SHA256.hash(data: rawData)
        let secondHash = SHA256.hash(data: Data(firstHash))
        return Data(secondHash.reversed()).map { String(format: "%02x", $0) }.joined()
    }
}

extension DogecoinWalletEngine {
    static func fetchSpendableUTXOs(for address: String, networkMode: DogecoinNetworkMode) throws -> [DogecoinUTXO] {
        do {
            let utxos = sanitizeUTXOs(try fetchBlockCypherUTXOs(for: address, networkMode: networkMode))
            if !utxos.isEmpty {
                cacheUTXOs(utxos, for: address)
                return utxos
            }
            return cachedUTXOs(for: address) ?? []
        } catch {
            if let cached = cachedUTXOs(for: address) {
                return cached
            }
            throw DogecoinWalletEngineError.networkFailure(error.localizedDescription)
        }
    }

    static func sanitizeUTXOs(_ utxos: [DogecoinUTXO]) -> [DogecoinUTXO] {
        var deduped: [String: DogecoinUTXO] = [:]
        for utxo in utxos where utxo.value > 0 {
            let key = outpointKey(hash: utxo.transactionHash, index: utxo.index)
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
            if lhs.transactionHash != rhs.transactionHash {
                return lhs.transactionHash < rhs.transactionHash
            }
            return lhs.index < rhs.index
        }
    }

    static func outpointKey(hash: String, index: Int) -> String {
        "\(hash.lowercased()):\(index)"
    }

    static func blockcypherURL(path: String, networkMode: DogecoinNetworkMode) -> URL? {
        switch networkMode {
        case .mainnet:
            return BlockCypherProvider.url(path: path, network: .dogecoinMainnet)
        case .testnet:
            return BlockCypherProvider.url(path: path, network: .dogecoinTestnet)
        }
    }

    static func normalizedAddressCacheKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func cacheUTXOs(_ utxos: [DogecoinUTXO], for address: String) {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress[key] = CachedUTXOSet(utxos: utxos, updatedAt: Date())
    }

    static func cachedUTXOs(for address: String) -> [DogecoinUTXO]? {
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

    static func fetchBlockCypherUTXOs(for address: String, networkMode: DogecoinNetworkMode) throws -> [DogecoinUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let baseURL = blockcypherURL(path: "/addrs/\(encodedAddress)", networkMode: networkMode),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "unspentOnly", value: "true"),
            URLQueryItem(name: "includeScript", value: "true"),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components.url else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherProvider.AddressRefsResponse.self, from: data)
        let confirmed = payload.txrefs ?? []
        let pending = payload.unconfirmedTxrefs ?? []
        return (confirmed + pending).compactMap {
            guard let txOutputIndex = $0.txOutputIndex, let value = $0.value else { return nil }
            return DogecoinUTXO(transactionHash: $0.txHash, index: txOutputIndex, value: value)
        }
    }

    static func resolveNetworkFeeRateDOGEPerKB(
        feePriority: FeePriority,
        networkMode: DogecoinNetworkMode
    ) throws -> Double {
        let candidates = try fetchBlockCypherFeeRateCandidatesDOGEPerKB(networkMode: networkMode)
        let baseRate = candidates.sorted()[candidates.count / 2]
        let boundedRate = max(minRelayFeePerKB, min(baseRate, 10))
        return adjustedFeeRateDOGEPerKB(baseRate: boundedRate, feePriority: feePriority)
    }

    static func adjustedFeeRateDOGEPerKB(baseRate: Double, feePriority: FeePriority) -> Double {
        feePolicy.adjustedFeeRatePerKB(
            baseRate: baseRate,
            multiplier: UTXOFeePriorityMultiplierPolicy.multiplier(for: feePriority),
            maxRate: 25
        )
    }

    static func fetchBlockCypherFeeRateCandidatesDOGEPerKB(networkMode: DogecoinNetworkMode) throws -> [Double] {
        guard let url = blockcypherURL(path: "", networkMode: networkMode) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin network fee endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherProvider.NetworkFeesResponse.self, from: data)
        let candidates = [payload.lowFeePerKB, payload.mediumFeePerKB, payload.highFeePerKB]
            .compactMap { $0 }
            .map { $0 / koinuPerDOGE }
            .filter { $0 > 0 }

        guard !candidates.isEmpty else {
            throw DogecoinWalletEngineError.networkFailure("Fee-rate data was missing from BlockCypher.")
        }
        return candidates
    }

    static func performSynchronousRequest(
        _ request: URLRequest,
        timeout: TimeInterval = networkTimeoutSeconds,
        retries: Int = networkRetryCount
    ) throws -> Data {
        do {
            return try UTXOEngineSupport.performSynchronousRequest(
                request,
                timeout: timeout,
                retries: retries
            )
        } catch {
            throw DogecoinWalletEngineError.networkFailure(error.localizedDescription)
        }
    }
}

extension DogecoinWalletEngine {
    static func walletCoreSignTransaction(
        keyMaterial: SigningKeyMaterial,
        utxos: [DogecoinUTXO],
        destinationAddress: String,
        amountDOGE: Double,
        changeAddress: String,
        feeRateDOGEPerKB: Double
    ) throws -> DogecoinWalletCoreSigningResult {
        let request = DogecoinWalletCoreSigningRequest(
            keyMaterial: keyMaterial,
            utxos: utxos,
            destinationAddress: destinationAddress,
            amountDOGE: amountDOGE,
            changeAddress: changeAddress,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let signingInput = try buildWalletCoreSigningInput(from: request)
        return try signWithWalletCore(input: signingInput)
    }

    static func buildWalletCoreSigningInput(
        from request: DogecoinWalletCoreSigningRequest
    ) throws -> BitcoinSigningInput {
        guard let sourceScript = standardScriptPubKey(for: request.keyMaterial.address) else {
            throw DogecoinWalletEngineError.transactionBuildFailed("Unable to derive source script for selected UTXOs.")
        }
        let amountKoinu = UInt64((request.amountDOGE * koinuPerDOGE).rounded())
        let feePerByteKoinu = max(1, Int64(((request.feeRateDOGEPerKB * koinuPerDOGE) / 1_000).rounded(.up)))

        var signingInput = BitcoinSigningInput()
        signingInput.hashType = 0x01
        signingInput.amount = Int64(amountKoinu)
        signingInput.byteFee = feePerByteKoinu
        signingInput.toAddress = request.destinationAddress
        signingInput.changeAddress = request.changeAddress
        signingInput.coinType = CoinType.dogecoin.rawValue
        signingInput.privateKey = [request.keyMaterial.privateKeyData]
        signingInput.utxo = try request.utxos.map { try walletCoreUnspentTransaction(from: $0, sourceScript: sourceScript) }
        return signingInput
    }

    static func walletCoreUnspentTransaction(
        from utxo: DogecoinUTXO,
        sourceScript: Data
    ) throws -> BitcoinUnspentTransaction {
        guard let txHashData = Data(hexEncoded: utxo.transactionHash), txHashData.count == 32 else {
            throw DogecoinWalletEngineError.transactionBuildFailed("One or more UTXOs had invalid txid encoding.")
        }
        var outPoint = BitcoinOutPoint()
        outPoint.hash = Data(txHashData.reversed())
        outPoint.index = UInt32(utxo.index)
        outPoint.sequence = UInt32.max

        var unspent = BitcoinUnspentTransaction()
        unspent.amount = Int64(utxo.value)
        unspent.script = sourceScript
        unspent.outPoint = outPoint
        return unspent
    }

    static func signWithWalletCore(input: BitcoinSigningInput) throws -> DogecoinWalletCoreSigningResult {
        let output: BitcoinSigningOutput = AnySigner.sign(input: input, coin: .dogecoin)
        if !output.errorMessage.isEmpty || output.encoded.isEmpty {
            throw DogecoinWalletEngineError.transactionSignFailed
        }
        return DogecoinWalletCoreSigningResult(
            encodedTransaction: output.encoded,
            transactionHash: output.transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func buildSpendPlan(
        from utxos: [DogecoinUTXO],
        amountDOGE: Double,
        feeRateDOGEPerKB: Double,
        maxInputCount: Int?
    ) throws -> DogecoinSpendPlan {
        let targetKoinu = UInt64((amountDOGE * koinuPerDOGE).rounded())
        let rustPlan: WalletRustUTXOSpendPlan
        do {
            rustPlan = try WalletRustAppCoreBridge.planUTXOSpend(
                WalletRustUTXOSpendPlanRequest(
                    inputs: utxos.enumerated().map { index, utxo in
                        WalletRustUTXOEntry(index: index, value: utxo.value)
                    },
                    targetValue: targetKoinu,
                    feeRate: feeRateDOGEPerKB,
                    feePolicy: rustFeePolicy(),
                    maxInputCount: maxInputCount
                )
            )
        } catch {
            throw mapRustUTXOPlannerError(error)
        }

        return UTXOSpendPlan(
            utxos: rustPlan.selectedIndices.map { utxos[$0] },
            totalInputValue: rustPlan.totalInputValue,
            fee: rustPlan.fee,
            change: rustPlan.change,
            usesChangeOutput: rustPlan.usesChangeOutput,
            estimatedTransactionBytes: rustPlan.estimatedTransactionBytes
        )
    }

    static func rustPreviewPlan(
        from utxos: [DogecoinUTXO],
        feeRateDOGEPerKB: Double
    ) throws -> WalletRustUTXOPreviewPlan {
        do {
            return try WalletRustAppCoreBridge.planUTXOPreview(
                WalletRustUTXOPreviewRequest(
                    inputs: utxos.enumerated().map { index, utxo in
                        WalletRustUTXOEntry(index: index, value: utxo.value)
                    },
                    feeRate: feeRateDOGEPerKB,
                    feePolicy: rustFeePolicy()
                )
            )
        } catch {
            throw mapRustUTXOPlannerError(error)
        }
    }

    static func rustFeePolicy() -> WalletRustUTXOFeePolicy {
        WalletRustUTXOFeePolicy(
            chainName: "Dogecoin",
            feeModel: "kilobyte",
            dustThreshold: feePolicy.dustThreshold,
            minimumRelayFeeRate: nil,
            minimumAbsoluteFee: nil,
            minimumRelayFeePerKB: minRelayFeePerKB,
            baseUnitsPerCoin: koinuPerDOGE,
            maxStandardTransactionBytes: UInt64(maxStandardTransactionBytes),
            inputBytes: 148,
            outputBytes: 34,
            overheadBytes: 10
        )
    }

    static func mapRustUTXOPlannerError(_ error: Error) -> DogecoinWalletEngineError {
        switch error.localizedDescription {
        case "utxo.insufficientFunds":
            return .insufficientFunds
        case "utxo.amountBelowDustThreshold":
            return .amountBelowDustThreshold
        case "utxo.feeBelowRelayPolicy":
            return .transactionBuildFailed("Dogecoin fee rate is below standard relay policy.")
        case "utxo.transactionTooLarge":
            return .transactionTooLarge
        case "utxo.changeBelowDustThreshold":
            return .changeBelowDustThreshold
        default:
            return .transactionBuildFailed(error.localizedDescription)
        }
    }

    static func broadcastRawTransaction(
        _ rawHex: String,
        networkMode: DogecoinNetworkMode
    ) throws {
        let maxAttempts = 2
        for attempt in 0 ..< maxAttempts {
            do {
                try broadcastRawTransactionViaBlockCypher(rawHex, networkMode: networkMode)
                return
            } catch {
                let errorDescription = error.localizedDescription
                if isAlreadyBroadcastedError(errorDescription) {
                    return
                }

                let shouldRetry = attempt < maxAttempts - 1 && isRetryableBroadcastError(errorDescription)
                if shouldRetry {
                    usleep(UInt32(250_000 * (attempt + 1)))
                    continue
                }

                throw DogecoinWalletEngineError.broadcastFailed(errorDescription)
            }
        }
        throw DogecoinWalletEngineError.broadcastFailed("BlockCypher did not accept the transaction.")
    }

    static func broadcastRawTransactionViaBlockCypher(
        _ rawHex: String,
        networkMode: DogecoinNetworkMode
    ) throws {
        guard let url = blockcypherURL(path: "/txs/push", networkMode: networkMode) else {
            throw DogecoinWalletEngineError.broadcastFailed("Invalid BlockCypher broadcast endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["tx": rawHex], options: [])

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: 0
        )
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorMessage = object["error"] as? String, !errorMessage.isEmpty {
                throw DogecoinWalletEngineError.broadcastFailed(errorMessage)
            }
            if let errors = object["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["error"] as? String,
               !message.isEmpty {
                throw DogecoinWalletEngineError.broadcastFailed(message)
            }
        }
    }

    static func isAlreadyBroadcastedError(_ message: String) -> Bool {
        if classifySendBroadcastFailure(message) == .alreadyBroadcast {
            return true
        }
        let normalized = message.lowercased()
        return normalized.contains("already in blockchain")
            || normalized.contains("already in block chain")
            || normalized.contains("txn-already")
            || normalized.contains("already spent")
    }

    static func isRetryableBroadcastError(_ message: String) -> Bool {
        if classifySendBroadcastFailure(message) == .retryable {
            return true
        }
        return message.lowercased().contains("network")
    }

    static func verifyBroadcastedTransactionIfAvailable(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) -> PostBroadcastVerificationStatus {
        let maxAttempts = 3
        for attempt in 0 ..< maxAttempts {
            let status = verifyPresenceOnlyIfAvailable(txid: txid, networkMode: networkMode)
            if status == .verified {
                return .verified
            }
            if attempt < maxAttempts - 1 {
                usleep(UInt32(350_000 * (attempt + 1)))
            }
        }
        return .deferred
    }

    static func verifyPresenceOnlyIfAvailable(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) -> PostBroadcastVerificationStatus {
        if (try? fetchBlockCypherTransactionHash(txid: txid, networkMode: networkMode)) != nil { return .verified }
        return .deferred
    }

    static func fetchBlockCypherTransactionHash(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) throws -> String? {
        guard let payload = try fetchBlockCypherTransaction(txid: txid, networkMode: networkMode),
              let txHash = payload.hash,
              !txHash.isEmpty else {
            return nil
        }
        return txHash
    }

    static func fetchBlockCypherTransaction(
        txid: String,
        networkMode: DogecoinNetworkMode
    ) throws -> BlockCypherProvider.TransactionHashResponse? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/txs/\(encodedTXID)", networkMode: networkMode) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher Dogecoin transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(request, timeout: networkTimeoutSeconds, retries: 0)

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = object["error"] as? String,
           !errorMessage.isEmpty {
            if errorMessage.lowercased().contains("not found") {
                return nil
            }
            throw DogecoinWalletEngineError.networkFailure("BlockCypher transaction lookup failed: \(errorMessage)")
        }

        return try JSONDecoder().decode(BlockCypherProvider.TransactionHashResponse.self, from: data)
    }
}

enum DogecoinWalletEngineError: LocalizedError {
    case invalidRecipientAddress
    case invalidAmount
    case invalidSeedPhrase
    case walletAddressNotDerivedFromSeed
    case keyDerivationFailed
    case noSpendableUTXOs
    case insufficientFunds
    case transactionBuildFailed(String)
    case transactionSignFailed
    case amountBelowDustThreshold
    case changeBelowDustThreshold
    case transactionTooLarge
    case networkFailure(String)
    case broadcastFailed(String)
    case preBroadcastValidationFailed(String)
    case postBroadcastVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRecipientAddress:
            return CommonLocalization.invalidDestinationAddressPrompt("Dogecoin")
        case .invalidAmount:
            return CommonLocalization.invalidAssetAmountPrompt("DOGE")
        case .invalidSeedPhrase:
            return AppLocalization.string("Unable to derive Dogecoin keys from this seed phrase.")
        case .walletAddressNotDerivedFromSeed:
            return AppLocalization.string("The imported Dogecoin address does not match the provided seed phrase.")
        case .keyDerivationFailed:
            return AppLocalization.string("Failed to derive the Dogecoin private key for signing.")
        case .noSpendableUTXOs:
            return AppLocalization.string("No spendable Dogecoin UTXOs were found for this wallet.")
        case .insufficientFunds:
            return CommonLocalization.insufficientBalanceForAmountPlusNetworkFee("DOGE")
        case .transactionBuildFailed(let message):
            return AppLocalization.string(message)
        case .transactionSignFailed:
            return CommonLocalization.signingTransactionFailed("Dogecoin")
        case .amountBelowDustThreshold:
            return AppLocalization.string("Amount is below Dogecoin dust threshold.")
        case .changeBelowDustThreshold:
            return AppLocalization.string("Calculated change is below dust threshold. Increase amount or consolidate UTXOs.")
        case .transactionTooLarge:
            return AppLocalization.string("Dogecoin transaction is too large for standard relay policy.")
        case .networkFailure(let message):
            return CommonLocalization.networkError("Dogecoin", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Dogecoin", message: message)
        case .preBroadcastValidationFailed(let message):
            let format = AppLocalization.string("Dogecoin pre-broadcast validation failed: %@")
            return String(format: format, locale: AppLocalization.locale, AppLocalization.string(message))
        case .postBroadcastVerificationFailed(let message):
            let format = AppLocalization.string("Dogecoin post-broadcast verification failed: %@")
            return String(format: format, locale: AppLocalization.locale, AppLocalization.string(message))
        }
    }
}
