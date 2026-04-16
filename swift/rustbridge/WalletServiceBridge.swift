import Foundation
enum SpectraChainID: Sendable {
    nonisolated static let bitcoin:          UInt32 = 0
    nonisolated static let ethereum:         UInt32 = 1
    nonisolated static let solana:           UInt32 = 2
    nonisolated static let dogecoin:         UInt32 = 3
    nonisolated static let xrp:              UInt32 = 4
    nonisolated static let litecoin:         UInt32 = 5
    nonisolated static let bitcoinCash:      UInt32 = 6
    nonisolated static let tron:             UInt32 = 7
    nonisolated static let stellar:          UInt32 = 8
    nonisolated static let cardano:          UInt32 = 9
    nonisolated static let polkadot:         UInt32 = 10
    nonisolated static let arbitrum:         UInt32 = 11
    nonisolated static let optimism:         UInt32 = 12
    nonisolated static let avalanche:        UInt32 = 13
    nonisolated static let sui:              UInt32 = 14
    nonisolated static let aptos:            UInt32 = 15
    nonisolated static let ton:              UInt32 = 16
    nonisolated static let near:             UInt32 = 17
    nonisolated static let icp:              UInt32 = 18
    nonisolated static let monero:           UInt32 = 19
    nonisolated static let base:             UInt32 = 20
    nonisolated static let ethereumClassic:  UInt32 = 21
    nonisolated static let bitcoinSv:        UInt32 = 22
    nonisolated static let bsc:              UInt32 = 23
    nonisolated static let hyperliquid:      UInt32 = 24
    nonisolated static let subscaOffset:   UInt32 = 100  // Polkadot Subscan
    nonisolated static let icOffset:       UInt32 = 100  // ICP Rosetta
    nonisolated static let tonV3Offset:    UInt32 = 100  // TON TonCenter v3 API
    nonisolated static let explorerOffset: UInt32 = 200  // Etherscan-compatible explorers
    nonisolated static func id(for chainName: String) -> UInt32? { chainNameTable[chainName] }
    nonisolated private static let chainNameTable: [String: UInt32] = [
        "Bitcoin":            bitcoin, "Ethereum":           ethereum, "Solana":             solana, "Dogecoin":           dogecoin, "XRP Ledger":         xrp, "Litecoin":           litecoin, "Bitcoin Cash":       bitcoinCash, "Tron":               tron, "Stellar":            stellar, "Cardano":            cardano, "Polkadot":           polkadot, "Arbitrum":           arbitrum, "Optimism":           optimism, "Avalanche":          avalanche, "Sui":                sui, "Aptos":              aptos, "TON":                ton, "NEAR":               near, "Internet Computer":  icp, "Monero":             monero, "Base":               base, "Ethereum Classic":   ethereumClassic, "Bitcoin SV":         bitcoinSv, "BNB Chain":          bsc, "Hyperliquid":        hyperliquid, ]
}
private struct ChainEndpointsPayload: Encodable, Sendable {
    let chainId: UInt32
    let endpoints: [String]
    let apiKey: String?
    enum CodingKeys: String, CodingKey {
        case chainId   = "chain_id"
        case endpoints
        case apiKey    = "api_key"
    }
}
actor WalletServiceBridge {
    static let shared = WalletServiceBridge()
    private var _service: WalletService?
    nonisolated(unsafe) private static var _syncService: WalletService?
    private var _balanceRefreshEngine: BalanceRefreshEngine?
    private func service() throws -> WalletService {
        if let existing = _service { return existing }
        let endpointsJSON = Self.buildEndpointsJSON()
        let svc = try WalletService(endpointsJson: endpointsJSON)
        _service = svc
        WalletServiceBridge._syncService = svc
        return svc
    }
    func refreshEndpoints() async throws {
        let json = Self.buildEndpointsJSON()
        try await service().updateEndpoints(endpointsJson: json)
    }
    func fetchBalanceJSON(chainId: UInt32, address: String) async throws -> String { try await service().fetchBalance(chainId: chainId, address: address) }
    func fetchHistoryJSON(chainId: UInt32, address: String) async throws -> String { try await service().fetchHistory(chainId: chainId, address: address) }
    func fetchEVMHistoryPageJSON(
        chainId: UInt32, address: String, tokens: [(contract: String, symbol: String, name: String, decimals: Int)], page: Int, pageSize: Int
    ) async throws -> String {
        let tokenArray: [[String: Any]] = tokens.map { t in ["contract": t.contract, "symbol": t.symbol, "name": t.name, "decimals": t.decimals] }
        guard let data = try? JSONSerialization.data(withJSONObject: tokenArray), let tokensJson = String(data: data, encoding: .utf8) else {
            return try await service().fetchEvmHistoryPage(
                chainId: chainId, address: address, tokensJson: "[]", page: UInt32(max(1, page)), pageSize: UInt32(max(1, pageSize))
            )
        }
        return try await service().fetchEvmHistoryPage(
            chainId: chainId, address: address, tokensJson: tokensJson, page: UInt32(max(1, page)), pageSize: UInt32(max(1, pageSize))
        )
    }
    func signAndSend(chainId: UInt32, paramsJson: String) async throws -> String { try await service().signAndSend(chainId: chainId, paramsJson: paramsJson) }
    func fetchEVMTokenBalancesBatch(
        chainId: UInt32, address: String, tokens: [(contract: String, symbol: String, decimals: Int)]
    ) async throws -> [EthereumTokenBalanceSnapshot] {
        guard !tokens.isEmpty else { return [] }
        let tokenArray = tokens.map { t in ["contract": t.contract, "symbol": t.symbol, "decimals": t.decimals] as [String: Any] }
        guard let tokensData = try? JSONSerialization.data(withJSONObject: tokenArray), let tokensJSON = String(data: tokensData, encoding: .utf8) else { return [] }
        let resultJSON = try await service().fetchEvmTokenBalancesBatch(
            chainId: chainId, address: address, tokensJson: tokensJSON)
        guard let data = resultJSON.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { obj in
            guard let contract = obj["contract_address"] as? String, let symbol = obj["symbol"] as? String, let rawStr = obj["balance_raw"] as? String, let rawInt = Decimal(string: rawStr), let decimals = obj["decimals"] as? Int else { return nil }
            let divisor = pow(Decimal(10), decimals)
            let balance = rawInt / divisor
            return EthereumTokenBalanceSnapshot(contractAddress: contract, symbol: symbol, balance: balance, decimals: decimals)
        }}
    func fetchTokenBalancesJSON(
        chainId: UInt32, address: String, tokens: [(contract: String, symbol: String, decimals: Int)]
    ) async throws -> String {
        guard !tokens.isEmpty else { return "[]" }
        let tokenArray = tokens.map { t in ["contract": t.contract, "symbol": t.symbol, "decimals": t.decimals] as [String: Any] }
        guard let data = try? JSONSerialization.data(withJSONObject: tokenArray), let tokensJSON = String(data: data, encoding: .utf8) else { return "[]" }
        return try await service().fetchTokenBalances(
            chainId: chainId, address: address, tokensJson: tokensJSON)
    }
    func deriveBitcoinAccountXpub(mnemonicPhrase: String, passphrase: String = "", accountPath: String) throws -> String {
        let json = try service().deriveBitcoinAccountXpub(mnemonicPhrase: mnemonicPhrase, passphrase: passphrase, accountPath: accountPath)
        guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let xpub = obj["xpub"] as? String else { throw NSError(domain: "BitcoinXpub", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to derive xpub from seed"]) }
        return xpub
    }
    func resolveENSName(_ name: String) async throws -> String? {
        let json = try await service().resolveEnsName(name: name)
        guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let address = obj["address"] as? String, !address.isEmpty else { return nil }
        return address
    }
    func fetchEVMCodeJSON(chainId: UInt32, address: String) async throws -> String { try await service().fetchEvmCode(chainId: chainId, address: address) }
    func fetchEVMTxNonce(chainId: UInt32, txHash: String) async throws -> Int {
        let json = try await service().fetchEvmTxNonce(chainId: chainId, txHash: txHash)
        guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let nonce = obj["nonce"] as? Int else { return 0 }
        return nonce
    }
    func fetchEVMReceiptJSON(chainId: UInt32, txHash: String) async throws -> String? {
        let raw = try await service().fetchEvmReceipt(chainId: chainId, txHash: txHash)
        return raw == "null" ? nil : raw
    }
    func fetchEVMSendPreviewJSON(chainId: UInt32, from: String, to: String, valueWei: String, dataHex: String) async throws -> String { try await service().fetchEvmSendPreview(chainId: chainId, from: from, to: to, valueWei: valueWei, dataHex: dataHex) }
    func fetchTronSendPreviewJSON(address: String, symbol: String, contractAddress: String) async throws -> String { try await service().fetchTronSendPreview(address: address, symbol: symbol, contractAddress: contractAddress) }
    func fetchUTXOFeePreviewJSON(chainId: UInt32, address: String, feeRateSvb: UInt64) async throws -> String { try await service().fetchUtxoFeePreview(chainId: chainId, address: address, feeRateSvb: feeRateSvb) }
    func fetchSimpleChainSendPreviewJSON(chainId: UInt32, address: String) async throws -> String { try await service().fetchSimpleChainSendPreview(chainId: chainId, address: address) }
    nonisolated func rustGenerateMnemonic(wordCount: Int) -> String { generateMnemonic(wordCount: UInt32(wordCount)) }
    nonisolated func rustValidateMnemonic(_ phrase: String) -> Bool { validateMnemonic(phrase: phrase) }
    nonisolated func rustBip39Wordlist() -> [String] { bip39EnglishWordlist().split(separator: "\n").map(String.init) }
    func broadcastRaw(chainId: UInt32, payload: String) async throws -> String { try await service().broadcastRaw(chainId: chainId, payload: payload) }
    func fetchTokenBalanceJSON(chainId: UInt32, paramsJson: String) async throws -> String { try await service().fetchTokenBalance(chainId: chainId, paramsJson: paramsJson) }
    func signAndSendToken(chainId: UInt32, paramsJson: String) async throws -> String { try await service().signAndSendToken(chainId: chainId, paramsJson: paramsJson) }
    func fetchFeeEstimateJSON(chainId: UInt32) async throws -> String { try await service().fetchFeeEstimate(chainId: chainId) }
    func deriveBitcoinHdAddressesJSON(xpub: String, change: UInt32, startIndex: UInt32, count: UInt32) async throws -> String { try await service().deriveBitcoinHdAddresses(xpub: xpub, change: change, startIndex: startIndex, count: count) }
    func fetchBitcoinXpubBalanceJSON(xpub: String, receiveCount: UInt32 = 20, changeCount: UInt32 = 20) async throws -> String { try await service().fetchBitcoinXpubBalance(xpub: xpub, receiveCount: receiveCount, changeCount: changeCount) }
    func fetchBitcoinNextUnusedAddressJSON(xpub: String, change: UInt32 = 0, gapLimit: UInt32 = 20) async throws -> String { try await service().fetchBitcoinNextUnusedAddress(xpub: xpub, change: change, gapLimit: gapLimit) }
    struct PriceRequestCoinInput: Encodable {
        let holdingKey: String
        let symbol: String
        let coinGeckoId: String
    }
    func fetchPricesViaRust(provider: String, coins: [PriceRequestCoinInput], apiKey: String) async throws -> [String: Double] {
        let coinsJson = try String(
            data: JSONEncoder().encode(coins), encoding: .utf8
        ) ?? "[]"
        let raw = try await service().fetchPrices(provider: provider, coinsJson: coinsJson, apiKey: apiKey)
        guard let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }
    func fetchFiatRatesViaRust(provider: String, currencies: [String]) async throws -> [String: Double] {
        let json = try String(
            data: JSONEncoder().encode(currencies), encoding: .utf8
        ) ?? "[]"
        let raw = try await service().fetchFiatRates(provider: provider, currenciesJson: json)
        guard let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }
    func cachedBalanceJSON(chainId: UInt32, address: String) throws -> String? { try service().cachedBalance(chainId: chainId, address: address) }
    func storeBalanceCache(chainId: UInt32, address: String, json: String) throws { try service().cacheBalance(chainId: chainId, address: address, balanceJson: json) }
    func invalidateBalanceCache(chainId: UInt32, address: String) throws { try service().invalidateCachedBalance(chainId: chainId, address: address) }
    func fetchBalanceCachedJSON(chainId: UInt32, address: String) async throws -> String { try await service().fetchBalanceCached(chainId: chainId, address: address) }
    func registerSecretStore(_ store: SecretStore) throws { try service().setSecretStore(store: store) }
    func makeSendStateMachine() -> SendStateMachine { SendStateMachine() }
}
extension WalletServiceBridge {
    func signAndSendWithDerivation(
        chainId: UInt32, seedPhrase: String, chain: SeedDerivationChain, derivationPath: String, paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String?) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain, network: .mainnet, seedPhrase: seedPhrase, derivationPath: derivationPath, passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex else { throw WalletServiceBridgeError.serviceInit("derivation did not return private key for chain \(chainId)") }
        let paramsJson = paramsBuilder(privKeyHex, derived.publicKeyHex)
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }
    func signAndSendTokenWithDerivation(
        chainId: UInt32, seedPhrase: String, chain: SeedDerivationChain, derivationPath: String, paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String?) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain, network: .mainnet, seedPhrase: seedPhrase, derivationPath: derivationPath, passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex else { throw WalletServiceBridgeError.serviceInit("token derivation did not return private key for chain \(chainId)") }
        let paramsJson = paramsBuilder(privKeyHex, derived.publicKeyHex)
        return try await signAndSendToken(chainId: chainId, paramsJson: paramsJson)
    }
    func signAndSendWithDerivationAndPubKey(
        chainId: UInt32, seedPhrase: String, chain: SeedDerivationChain, derivationPath: String, paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain, network: .mainnet, seedPhrase: seedPhrase, derivationPath: derivationPath, passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex, let pubKeyHex  = derived.publicKeyHex else { throw WalletServiceBridgeError.serviceInit("derivation did not return key material for chain \(chainId)") }
        let paramsJson = paramsBuilder(privKeyHex, pubKeyHex)
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }
}
extension WalletServiceBridge {
    func fetchSolanaBalance(address: String) async throws -> SolanaBalanceResponse {
        let json = try await fetchBalanceJSON(chainId: SpectraChainID.solana, address: address)
        return try JSONDecoder().decode(SolanaBalanceResponse.self, from: Data(json.utf8))
    }
    func fetchNearBalance(address: String) async throws -> NearBalanceResponse {
        let json = try await fetchBalanceJSON(chainId: SpectraChainID.near, address: address)
        return try JSONDecoder().decode(NearBalanceResponse.self, from: Data(json.utf8))
    }
    func fetchErc20Balance(chainId: UInt32, contract: String, holder: String) async throws -> Erc20BalanceResponse {
        let payload = """
        {"contract":"\(contract)","holder":"\(holder)"}
        """
        let json = try await fetchTokenBalanceJSON(chainId: chainId, paramsJson: payload)
        return try JSONDecoder().decode(Erc20BalanceResponse.self, from: Data(json.utf8))
    }
    func signAndSendErc20WithDerivation(chainId: UInt32, seedPhrase: String, derivationPath: String, from: String, contract: String, to: String, amountRaw: String) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: .ethereum, network: .mainnet, seedPhrase: seedPhrase, derivationPath: derivationPath, passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: [.address, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex else { throw WalletServiceBridgeError.serviceInit("erc20: derivation missing private key") }
        let payload = sendPayload(.str("from", from), .str("contract", contract), .str("to", to), .str("amount_raw", amountRaw), .str("private_key_hex", privKeyHex))
        return try await signAndSendToken(chainId: chainId, paramsJson: payload)
    }
    func loadState(key: String) async throws -> String { try await service().loadState(dbPath: sqliteDbPath(), key: key) }
    func saveState(key: String, stateJSON: String) async throws { try await service().saveState(dbPath: sqliteDbPath(), key: key, stateJson: stateJSON) }
    func initWalletState(walletsJson: String) async throws { try await service().initWalletState(walletsJson: walletsJson) }
    func listWalletsJSON() async throws -> String { try await service().listWalletsJson() }
    @discardableResult
    func upsertWalletJSON(_ walletJson: String) async throws -> String { try await service().upsertWalletJson(walletJson: walletJson) }
    @discardableResult
    func removeWalletJSON(walletId: String) async throws -> String { try await service().removeWalletJson(walletId: walletId) }
    func updateNativeBalance(walletId: String, chainId: UInt32, balanceJson: String) async throws -> String? { try await service().updateNativeBalance(walletId: walletId, chainId: chainId, balanceJson: balanceJson) }
    func setNativeBalance(walletId: String, chainId: UInt32, amount: Double) async throws -> String? { try await service().setNativeBalance(walletId: walletId, chainId: chainId, amount: amount) }
    /// Upsert a batch of asset holdings into a wallet in Rust state.
    /// `holdingsJson` is a JSON array matching the AssetHolding schema
    /// (camelCase: name, symbol, marketDataId, coinGeckoId, chainName,
    /// tokenStandard, contractAddress?, amount, priceUsd).
    /// Returns the updated WalletSummary JSON, or nil if wallet not found.
    @discardableResult
    func upsertAssetHoldings(walletId: String, holdingsJson: String) async throws -> String? {
        try await service().upsertAssetHoldings(walletId: walletId, holdingsJson: holdingsJson)
    }
    /// Fetches history for `address` on `chainId`, normalizes the raw chain-specific
    /// JSON into a standard `ChainHistoryEntry` array, and returns JSON.
    /// Covers: BTC, LTC, BCH, BSV, DOGE, XRP, XLM, ADA, DOT, SOL, TRX,
    /// SUI, APT, TON, NEAR, ICP, XMR. EVM uses fetchEVMHistoryPageJSON instead.
    func fetchNormalizedHistoryJSON(chainId: UInt32, address: String) async throws -> String {
        try await service().fetchNormalizedHistoryJson(chainId: chainId, address: address)
    }
    func saveWalletSnapshot(json: String) {
        Task {
            try? await service().saveWalletSnapshot(dbPath: sqliteDbPath(), snapshotJson: json)
        }}
    func loadWalletSnapshot() async throws -> String { try await service().loadWalletSnapshot(dbPath: sqliteDbPath()) }
    func saveAppSettings(json: String) {
        Task {
            try? await service().saveAppSettings(dbPath: sqliteDbPath(), settingsJson: json)
        }}
    func loadAppSettings() async throws -> String { try await service().loadAppSettings(dbPath: sqliteDbPath()) }
    func saveKeypoolState(walletId: String, chainName: String, stateJSON: String) {
        Task {
            try? await service().saveKeypoolState(
                dbPath: sqliteDbPath(), walletId: walletId, chainName: chainName, stateJson: stateJSON
            )
        }}
    func loadKeypoolState(walletId: String, chainName: String) async throws -> String? {
        try await service().loadKeypoolState(
            dbPath: sqliteDbPath(), walletId: walletId, chainName: chainName
        )
    }
    func loadAllKeypoolState() async throws -> String { try await service().loadAllKeypoolState(dbPath: sqliteDbPath()) }
    func deleteKeypoolForWallet(walletId: String) {
        Task {
            try? await service().deleteKeypoolForWallet(dbPath: sqliteDbPath(), walletId: walletId)
        }}
    func deleteKeypoolForChain(chainName: String) {
        Task {
            try? await service().deleteKeypoolForChain(dbPath: sqliteDbPath(), chainName: chainName)
        }}
    func saveOwnedAddress(recordJSON: String) {
        Task {
            try? await service().saveOwnedAddress(dbPath: sqliteDbPath(), recordJson: recordJSON)
        }}
    func loadAllOwnedAddresses() async throws -> String { try await service().loadAllOwnedAddresses(dbPath: sqliteDbPath()) }
    func deleteOwnedAddressesForWallet(walletId: String) {
        Task {
            try? await service().deleteOwnedAddressesForWallet(
                dbPath: sqliteDbPath(), walletId: walletId
            )
        }}
    func deleteOwnedAddressesForChain(chainName: String) {
        Task {
            try? await service().deleteOwnedAddressesForChain(
                dbPath: sqliteDbPath(), chainName: chainName
            )
        }}
    func deleteWalletRelationalData(walletId: String) {
        Task {
            try? await service().deleteWalletRelationalData(
                dbPath: sqliteDbPath(), walletId: walletId
            )
        }}
    // ── Transaction history persistence (Rust SQLite) ──────────────────────────
    func upsertHistoryRecords(recordsJSON: String) {
        Task { try? await service().upsertHistoryRecords(dbPath: sqliteDbPath(), recordsJson: recordsJSON) }}
    func fetchAllHistoryRecords() async throws -> String { try await service().fetchAllHistoryRecords(dbPath: sqliteDbPath()) }
    func deleteHistoryRecords(idsJSON: String) {
        Task { try? await service().deleteHistoryRecords(dbPath: sqliteDbPath(), idsJson: idsJSON) }}
    func replaceAllHistoryRecords(recordsJSON: String) {
        Task { try? await service().replaceAllHistoryRecords(dbPath: sqliteDbPath(), recordsJson: recordsJSON) }}
    func deleteHistoryRecordsForWallet(walletId: String) {
        Task { try? await service().deleteHistoryRecordsForWallet(dbPath: sqliteDbPath(), walletId: walletId) }}
    func clearAllHistoryRecords() {
        Task { try? await service().clearAllHistoryRecords(dbPath: sqliteDbPath()) }}
    func cachedHistoryJSON(chainId: UInt32, address: String) throws -> String? { try service().cachedHistory(chainId: chainId, address: address) }
    func storeHistoryCache(chainId: UInt32, address: String, json: String) throws { try service().cacheHistory(chainId: chainId, address: address, historyJson: json) }
    func invalidateHistoryCache(chainId: UInt32, address: String) throws { try service().invalidateCachedHistory(chainId: chainId, address: address) }
    func fetchHistoryCachedJSON(chainId: UInt32, address: String) async throws -> String { try await service().fetchHistoryCached(chainId: chainId, address: address) }
    nonisolated func historyNextCursor(chainId: UInt32, walletId: String) -> String? { WalletServiceBridge._syncService?.historyNextCursor(chainId: chainId, walletId: walletId) }
    nonisolated func historyNextPage(chainId: UInt32, walletId: String) -> UInt32 { WalletServiceBridge._syncService?.historyNextPage(chainId: chainId, walletId: walletId) ?? 0 }
    nonisolated func isHistoryExhausted(chainId: UInt32, walletId: String) -> Bool { WalletServiceBridge._syncService?.isHistoryExhausted(chainId: chainId, walletId: walletId) ?? false }
    nonisolated func advanceHistoryCursor(chainId: UInt32, walletId: String, nextCursor: String?) { WalletServiceBridge._syncService?.advanceHistoryCursor(chainId: chainId, walletId: walletId, nextCursor: nextCursor) }
    nonisolated func advanceHistoryPage(chainId: UInt32, walletId: String, isLast: Bool) { WalletServiceBridge._syncService?.advanceHistoryPage(chainId: chainId, walletId: walletId, isLast: isLast) }
    nonisolated func setHistoryPage(chainId: UInt32, walletId: String, page: UInt32) { WalletServiceBridge._syncService?.setHistoryPage(chainId: chainId, walletId: walletId, page: page) }
    nonisolated func setHistoryExhausted(chainId: UInt32, walletId: String, exhausted: Bool) { WalletServiceBridge._syncService?.setHistoryExhausted(chainId: chainId, walletId: walletId, exhausted: exhausted) }
    nonisolated func resetHistory(chainId: UInt32, walletId: String) { WalletServiceBridge._syncService?.resetHistory(chainId: chainId, walletId: walletId) }
    nonisolated func resetHistoryForWallet(walletId: String) { WalletServiceBridge._syncService?.resetHistoryForWallet(walletId: walletId) }
    nonisolated func resetHistoryForChain(chainId: UInt32) { WalletServiceBridge._syncService?.resetHistoryForChain(chainId: chainId) }
    nonisolated func resetAllHistory() { WalletServiceBridge._syncService?.resetAllHistory() }
    func fetchUTXOTxStatusJSON(chainId: UInt32, txid: String) async throws -> String { try await service().fetchUtxoTxStatus(chainId: chainId, txid: txid) }
    private func sqliteDbPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
        return "\(docs)/spectra_state.db"
    }
}
struct SolanaBalanceResponse: Sendable {
    let lamports: UInt64
    let solDisplay: String
}
extension SolanaBalanceResponse: Decodable {
    private enum CodingKeys: String, CodingKey { case lamports; case solDisplay = "sol_display" }
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lamports = try c.decode(UInt64.self, forKey: .lamports)
        solDisplay = try c.decode(String.self, forKey: .solDisplay)
    }
}
struct NearBalanceResponse: Sendable {
    let yoctoNear: String
    let nearDisplay: String
}
extension NearBalanceResponse: Decodable {
    private enum CodingKeys: String, CodingKey { case yoctoNear = "yocto_near"; case nearDisplay = "near_display" }
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yoctoNear = try c.decode(String.self, forKey: .yoctoNear)
        nearDisplay = try c.decode(String.self, forKey: .nearDisplay)
    }
}
struct Erc20BalanceResponse: Sendable {
    let contract: String
    let holder: String
    let balanceRaw: String
    let balanceDisplay: String
    let decimals: UInt8
    let symbol: String
}
extension Erc20BalanceResponse: Decodable {
    private enum CodingKeys: String, CodingKey { case contract; case holder; case balanceRaw = "balance_raw"; case balanceDisplay = "balance_display"; case decimals; case symbol }
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contract = try c.decode(String.self, forKey: .contract)
        holder = try c.decode(String.self, forKey: .holder)
        balanceRaw = try c.decode(String.self, forKey: .balanceRaw)
        balanceDisplay = try c.decode(String.self, forKey: .balanceDisplay)
        decimals = try c.decode(UInt8.self, forKey: .decimals)
        symbol = try c.decode(String.self, forKey: .symbol)
    }
}
enum WalletServiceBridgeError: LocalizedError {
    case unsupportedChain(String)
    case serviceInit(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let name): return "WalletServiceBridge: chain '\(name)' has no Rust chain ID mapping."
        case .serviceInit(let msg): return "WalletServiceBridge: failed to initialise WalletService — \(msg)"
        }}
}
private extension WalletServiceBridge {
    static func buildEndpointsJSON() -> String {
        var payloads: [ChainEndpointsPayload] = []
        payloads += rpcPayloads(chainId: SpectraChainID.bitcoin,         chainName: "Bitcoin")
        payloads += evmPayloads(chainId: SpectraChainID.ethereum,        chainName: "Ethereum")
        payloads += rpcPayloads(chainId: SpectraChainID.solana,          chainName: "Solana")
        payloads += rpcPayloads(chainId: SpectraChainID.dogecoin,        chainName: "Dogecoin")
        payloads += rpcPayloads(chainId: SpectraChainID.xrp,             chainName: "XRP Ledger")
        payloads += rpcPayloads(chainId: SpectraChainID.litecoin,        chainName: "Litecoin")
        payloads += rpcPayloads(chainId: SpectraChainID.bitcoinCash,     chainName: "Bitcoin Cash")
        payloads += rpcPayloads(chainId: SpectraChainID.tron,            chainName: "Tron")
        payloads += rpcPayloads(chainId: SpectraChainID.stellar,         chainName: "Stellar")
        payloads += rpcPayloads(chainId: SpectraChainID.cardano,         chainName: "Cardano")
        payloads += rpcPayloads(chainId: SpectraChainID.polkadot,        chainName: "Polkadot")
        payloads += evmPayloads(chainId: SpectraChainID.arbitrum,        chainName: "Arbitrum")
        payloads += evmPayloads(chainId: SpectraChainID.optimism,        chainName: "Optimism")
        payloads += evmPayloads(chainId: SpectraChainID.avalanche,       chainName: "Avalanche")
        payloads += rpcPayloads(chainId: SpectraChainID.sui,             chainName: "Sui")
        payloads += rpcPayloads(chainId: SpectraChainID.aptos,           chainName: "Aptos")
        payloads += rpcPayloads(chainId: SpectraChainID.ton,             chainName: "TON")
        payloads += rpcPayloads(chainId: SpectraChainID.near,            chainName: "NEAR")
        payloads += rpcPayloads(chainId: SpectraChainID.icp,             chainName: "Internet Computer")
        payloads += rpcPayloads(chainId: SpectraChainID.monero,          chainName: "Monero")
        payloads += evmPayloads(chainId: SpectraChainID.base,            chainName: "Base")
        payloads += evmPayloads(chainId: SpectraChainID.ethereumClassic, chainName: "Ethereum Classic")
        payloads += rpcPayloads(chainId: SpectraChainID.bitcoinSv,       chainName: "Bitcoin SV")
        payloads += evmPayloads(chainId: SpectraChainID.bsc,             chainName: "BNB Chain")
        payloads += evmPayloads(chainId: SpectraChainID.hyperliquid,     chainName: "Hyperliquid")
        payloads += explorerPayloads(chainId: SpectraChainID.polkadot + SpectraChainID.subscaOffset, chainName: "Polkadot")
        payloads += explorerPayloads(chainId: SpectraChainID.icp + SpectraChainID.icOffset, chainName: "Internet Computer")
        let tonV3URLs = ChainBackendRegistry.TONRuntimeEndpoints.apiV3BaseURLs
        if !tonV3URLs.isEmpty { payloads.append(ChainEndpointsPayload(chainId: SpectraChainID.ton + SpectraChainID.tonV3Offset, endpoints: tonV3URLs, apiKey: nil)) }
        let explorerChains: [(UInt32, String)] = [
            (SpectraChainID.ethereum,        "Ethereum"), (SpectraChainID.tron,            "Tron"), (SpectraChainID.arbitrum,        "Arbitrum"), (SpectraChainID.optimism,        "Optimism"), (SpectraChainID.avalanche,       "Avalanche"), (SpectraChainID.near,            "NEAR"), (SpectraChainID.base,            "Base"), (SpectraChainID.ethereumClassic, "Ethereum Classic"), (SpectraChainID.bsc,             "BNB Chain"), ]
        for (primaryId, chainName) in explorerChains { payloads += explorerPayloads(chainId: SpectraChainID.explorerOffset + primaryId, chainName: chainName) }
        guard
            let data = try? JSONEncoder().encode(payloads), let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }
    static func rpcPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (
            try? WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName, roles: [.rpc, .balance, .backend], settingsVisibleOnly: false
            )
        )?.map(\.endpoint) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
    static func evmPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.evmRPCEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
    static func explorerPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.explorerSupplementalEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
}
extension WalletServiceBridge {
    private func balanceRefreshEngine() throws -> BalanceRefreshEngine {
        if let engine = _balanceRefreshEngine { return engine }
        let engine = BalanceRefreshEngine(walletService: try service())
        _balanceRefreshEngine = engine
        return engine
    }
    func setBalanceObserver(_ observer: BalanceObserver) throws { try balanceRefreshEngine().setObserver(observer: observer) }
    func setRefreshEntries(_ entriesJson: String) throws { try balanceRefreshEngine().setEntries(entriesJson: entriesJson) }
    func startBalanceRefresh(intervalSecs: UInt64) async throws { try await balanceRefreshEngine().start(intervalSecs: intervalSecs) }
    func stopBalanceRefresh() throws { try balanceRefreshEngine().stop() }
    func triggerImmediateBalanceRefresh() async throws { try await balanceRefreshEngine().triggerImmediate() }
}
