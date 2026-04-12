import Foundation

// MARK: - Frozen chain ID table (mirrors service.rs — do not reorder)

enum SpectraChainID {
    static let bitcoin:          UInt32 = 0
    static let ethereum:         UInt32 = 1
    static let solana:           UInt32 = 2
    static let dogecoin:         UInt32 = 3
    static let xrp:              UInt32 = 4
    static let litecoin:         UInt32 = 5
    static let bitcoinCash:      UInt32 = 6
    static let tron:             UInt32 = 7
    static let stellar:          UInt32 = 8
    static let cardano:          UInt32 = 9
    static let polkadot:         UInt32 = 10
    static let arbitrum:         UInt32 = 11
    static let optimism:         UInt32 = 12
    static let avalanche:        UInt32 = 13
    static let sui:              UInt32 = 14
    static let aptos:            UInt32 = 15
    static let ton:              UInt32 = 16
    static let near:             UInt32 = 17
    static let icp:              UInt32 = 18
    static let monero:           UInt32 = 19
    static let base:             UInt32 = 20
    static let ethereumClassic:  UInt32 = 21
    static let bitcoinSv:        UInt32 = 22
    static let bsc:              UInt32 = 23
    static let hyperliquid:      UInt32 = 24

    // Logical offsets for secondary endpoint bundles (mirrors service.rs)
    static let subscaOffset:  UInt32 = 100   // Polkadot Subscan
    static let icOffset:      UInt32 = 100   // ICP Rosetta
    static let explorerOffset: UInt32 = 200  // Etherscan-compatible explorers

    static func id(for chainName: String) -> UInt32? {
        chainNameTable[chainName]
    }

    private static let chainNameTable: [String: UInt32] = [
        "Bitcoin":            bitcoin,
        "Ethereum":           ethereum,
        "Solana":             solana,
        "Dogecoin":           dogecoin,
        "XRP Ledger":         xrp,
        "Litecoin":           litecoin,
        "Bitcoin Cash":       bitcoinCash,
        "Tron":               tron,
        "Stellar":            stellar,
        "Cardano":            cardano,
        "Polkadot":           polkadot,
        "Arbitrum":           arbitrum,
        "Optimism":           optimism,
        "Avalanche":          avalanche,
        "Sui":                sui,
        "Aptos":              aptos,
        "TON":                ton,
        "NEAR":               near,
        "Internet Computer":  icp,
        "Monero":             monero,
        "Base":               base,
        "Ethereum Classic":   ethereumClassic,
        "Bitcoin SV":         bitcoinSv,
        "BNB Chain":          bsc,
        "Hyperliquid":        hyperliquid,
    ]
}

// MARK: - Wire model (matches ChainEndpoints in service.rs)

private struct ChainEndpointsPayload: Encodable {
    let chainId: UInt32
    let endpoints: [String]
    let apiKey: String?

    enum CodingKeys: String, CodingKey {
        case chainId   = "chain_id"
        case endpoints
        case apiKey    = "api_key"
    }
}

// MARK: - WalletServiceBridge

/// Thread-safe actor that owns the Rust WalletService instance.
/// All async chain operations go through this actor.
actor WalletServiceBridge {

    static let shared = WalletServiceBridge()

    // Lazily initialised on first use.
    private var _service: WalletService?

    // MARK: Service access

    private func service() throws -> WalletService {
        if let existing = _service { return existing }
        let endpointsJSON = Self.buildEndpointsJSON()
        let svc = try WalletService(endpointsJson: endpointsJSON)
        _service = svc
        return svc
    }

    /// Call after the user changes endpoint preferences so the Rust layer
    /// picks up the new URLs without an app restart.
    func refreshEndpoints() async throws {
        let json = Self.buildEndpointsJSON()
        try await service().updateEndpoints(endpointsJson: json)
    }

    // MARK: Balance

    /// Returns the raw JSON string from Rust (chain-specific balance struct).
    func fetchBalanceJSON(chainId: UInt32, address: String) async throws -> String {
        try await service().fetchBalance(chainId: chainId, address: address)
    }

    func fetchBalanceJSON(chainName: String, address: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await fetchBalanceJSON(chainId: chainId, address: address)
    }

    // MARK: History

    func fetchHistoryJSON(chainId: UInt32, address: String) async throws -> String {
        try await service().fetchHistory(chainId: chainId, address: address)
    }

    func fetchHistoryJSON(chainName: String, address: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await fetchHistoryJSON(chainId: chainId, address: address)
    }

    /// Fetch one page of EVM transaction history (native + ERC-20 token transfers).
    ///
    /// `tokens` is the list of tracked tokens for this chain. Pass `[]` to skip token transfers.
    /// Returns JSON: `{"native": [...], "tokens": [...]}`.
    func fetchEVMHistoryPageJSON(
        chainId: UInt32,
        address: String,
        tokens: [(contract: String, symbol: String, name: String, decimals: Int)],
        page: Int,
        pageSize: Int
    ) async throws -> String {
        let tokenArray: [[String: Any]] = tokens.map { t in
            ["contract": t.contract, "symbol": t.symbol, "name": t.name, "decimals": t.decimals]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: tokenArray),
              let tokensJson = String(data: data, encoding: .utf8) else {
            return try await service().fetchEvmHistoryPage(
                chainId: chainId,
                address: address,
                tokensJson: "[]",
                page: UInt32(max(1, page)),
                pageSize: UInt32(max(1, pageSize))
            )
        }
        return try await service().fetchEvmHistoryPage(
            chainId: chainId,
            address: address,
            tokensJson: tokensJson,
            page: UInt32(max(1, page)),
            pageSize: UInt32(max(1, pageSize))
        )
    }

    // MARK: Sign & Send

    /// `paramsJson` is a chain-specific JSON object (see service.rs for field names).
    func signAndSend(chainId: UInt32, paramsJson: String) async throws -> String {
        try await service().signAndSend(chainId: chainId, paramsJson: paramsJson)
    }

    func signAndSend(chainName: String, paramsJson: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }

    // MARK: EVM token balances (batch)

    /// Fetch balances for multiple ERC-20 tokens in one call.
    ///
    /// `tokens` is an array of `(contract, symbol, decimals)` tuples.
    /// Returns decoded `EthereumTokenBalanceSnapshot` values.
    func fetchEVMTokenBalancesBatch(
        chainId: UInt32,
        address: String,
        tokens: [(contract: String, symbol: String, decimals: Int)]
    ) async throws -> [EthereumTokenBalanceSnapshot] {
        guard !tokens.isEmpty else { return [] }
        let tokenArray = tokens.map { t in
            ["contract": t.contract, "symbol": t.symbol, "decimals": t.decimals] as [String: Any]
        }
        guard let tokensData = try? JSONSerialization.data(withJSONObject: tokenArray),
              let tokensJSON = String(data: tokensData, encoding: .utf8) else { return [] }
        let resultJSON = try await service().fetchEvmTokenBalancesBatch(
            chainId: chainId, address: address, tokensJson: tokensJSON)
        guard let data = resultJSON.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { obj in
            guard let contract = obj["contract_address"] as? String,
                  let symbol = obj["symbol"] as? String,
                  let rawStr = obj["balance_raw"] as? String,
                  let rawInt = Decimal(string: rawStr),
                  let decimals = obj["decimals"] as? Int else { return nil }
            let divisor = pow(Decimal(10), decimals)
            let balance = rawInt / divisor
            return EthereumTokenBalanceSnapshot(
                contractAddress: contract,
                symbol: symbol,
                balance: balance,
                decimals: decimals
            )
        }
    }

    // MARK: Token balances (TRC-20 / SPL batch)

    /// Fetch balances for a list of tokens in one call.
    ///
    /// `tokens` is an array of `(contract, symbol, decimals)` tuples where
    /// `contract` is the token contract address (or mint address for Solana).
    ///
    /// Returns the raw JSON array from Rust. Each element has:
    ///   `contract`, `symbol`, `decimals`, `balance_raw`, `balance_display`.
    func fetchTokenBalancesJSON(
        chainId: UInt32,
        address: String,
        tokens: [(contract: String, symbol: String, decimals: Int)]
    ) async throws -> String {
        guard !tokens.isEmpty else { return "[]" }
        let tokenArray = tokens.map { t in
            ["contract": t.contract, "symbol": t.symbol, "decimals": t.decimals] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: tokenArray),
              let tokensJSON = String(data: data, encoding: .utf8) else { return "[]" }
        return try await service().fetchTokenBalances(
            chainId: chainId, address: address, tokensJson: tokensJSON)
    }

    // MARK: Bitcoin HD — seed → xpub

    /// Derive the account-level xpub from a BIP39 mnemonic phrase.
    ///
    /// `accountPath` is the hardened account path, e.g. `"m/84'/0'/0'"` (native SegWit).
    /// `passphrase` is the optional BIP39 passphrase — pass `""` for none.
    /// Returns the canonical `xpub…` string (mainnet, account level only).
    func deriveBitcoinAccountXpub(
        mnemonicPhrase: String,
        passphrase: String = "",
        accountPath: String
    ) throws -> String {
        let json = try service().deriveBitcoinAccountXpub(
            mnemonicPhrase: mnemonicPhrase,
            passphrase: passphrase,
            accountPath: accountPath
        )
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let xpub = obj["xpub"] as? String else {
            throw NSError(domain: "BitcoinXpub", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to derive xpub from seed"])
        }
        return xpub
    }

    // MARK: ENS resolution

    /// Resolve an ENS name to an Ethereum address via the ENS Ideas API.
    /// Returns the resolved address string, or `nil` if unregistered / invalid.
    /// Throws on network failure.
    func resolveENSName(_ name: String) async throws -> String? {
        let json = try await service().resolveEnsName(name: name)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = obj["address"] as? String,
              !address.isEmpty else { return nil }
        return address
    }

    // MARK: EVM utilities

    /// Fetch the bytecode at `address` on `chainId` (eth_getCode).
    /// Returns `{"code": "0x…"}`. "0x" / "0x0" means the address is an EOA.
    func fetchEVMCodeJSON(chainId: UInt32, address: String) async throws -> String {
        try await service().fetchEvmCode(chainId: chainId, address: address)
    }

    /// Fetch the nonce of a submitted tx by hash on `chainId`.
    /// Returns `{"nonce": <integer>}`. Used for replacement-tx flows.
    func fetchEVMTxNonce(chainId: UInt32, txHash: String) async throws -> Int {
        let json = try await service().fetchEvmTxNonce(chainId: chainId, txHash: txHash)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nonce = obj["nonce"] as? Int else { return 0 }
        return nonce
    }

    /// Fetch the transaction receipt for `txHash` on `chainId`.
    /// Returns raw JSON string (`EvmReceipt`) when the tx has been mined,
    /// or `"null"` when still pending. Returns `nil` if the bridge throws.
    func fetchEVMReceiptJSON(chainId: UInt32, txHash: String) async throws -> String? {
        let raw = try await service().fetchEvmReceipt(chainId: chainId, txHash: txHash)
        return raw == "null" ? nil : raw
    }

    /// Fetch a send preview bundle for an EVM chain.
    ///
    /// `valueWei` is the ETH/token value in wei as a decimal string.
    /// `dataHex` is the calldata hex string (use `"0x"` for native transfers).
    /// Returns raw JSON matching `EthereumSendPreview`.
    func fetchEVMSendPreviewJSON(
        chainId: UInt32,
        from: String,
        to: String,
        valueWei: String,
        dataHex: String
    ) async throws -> String {
        try await service().fetchEvmSendPreview(
            chainId: chainId,
            from: from,
            to: to,
            valueWei: valueWei,
            dataHex: dataHex
        )
    }

    /// Fetch a send-preview bundle for Tron (TRX or TRC-20).
    ///
    /// `contractAddress` should be empty for native TRX sends.
    /// Returns raw JSON matching `TronSendPreview`.
    func fetchTronSendPreviewJSON(
        address: String,
        symbol: String,
        contractAddress: String
    ) async throws -> String {
        try await service().fetchTronSendPreview(
            address: address,
            symbol: symbol,
            contractAddress: contractAddress
        )
    }

    // MARK: UTXO fee preview

    /// Compute a max-send fee preview for a UTXO chain (BTC=0, LTC=5, BCH=6, BSV=22).
    ///
    /// `feeRateSvb = 0` lets Rust fetch a live rate from Blockbook (falls back to 1).
    /// Returns JSON: `{ fee_rate_svb, estimated_fee_sat, estimated_tx_bytes,
    /// selected_input_count, uses_change_output, spendable_balance_sat, max_sendable_sat }`.
    func fetchUTXOFeePreviewJSON(chainId: UInt32, address: String, feeRateSvb: UInt64) async throws -> String {
        try await service().fetchUtxoFeePreview(chainId: chainId, address: address, feeRateSvb: feeRateSvb)
    }

    // MARK: BIP39 mnemonic utilities

    /// Generate a new BIP-39 mnemonic with the given word count (12/15/18/21/24).
    /// Falls back to 12 words for any unsupported count.
    /// Pure computation — no network I/O, no async needed.
    func rustGenerateMnemonic(wordCount: Int) -> String {
        generateMnemonic(wordCount: UInt32(wordCount))
    }

    /// Validate a BIP-39 mnemonic phrase (checksum + word list).
    /// Returns `true` if the phrase is a valid English BIP-39 mnemonic.
    func rustValidateMnemonic(_ phrase: String) -> Bool {
        validateMnemonic(phrase: phrase)
    }

    /// Return the full BIP-39 English word list as a newline-delimited string
    /// (2048 words, one per line).
    func rustBip39Wordlist() -> [String] {
        bip39EnglishWordlist().split(separator: "\n").map(String.init)
    }

    // MARK: Rebroadcast

    /// Rebroadcast a previously signed transaction. `payload` is chain-specific:
    ///   UTXO chains (BTC/LTC/BCH/BSV/DOGE): raw hex string
    ///   Solana: base64-encoded signed transaction
    ///   Tron: signed transaction JSON
    ///   EVM: raw hex string
    /// Returns raw JSON from Rust (chain-specific send result struct).
    func broadcastRaw(chainId: UInt32, payload: String) async throws -> String {
        try await service().broadcastRaw(chainId: chainId, payload: payload)
    }

    // MARK: Token balance / transfer (ERC-20 / SPL / NEP-141 / TRC-20)

    /// Fetch a token balance for the given chain. `paramsJson` is chain-specific
    /// (for EVM: `{"contract": "0x…", "holder": "0x…"}`). Returns the raw JSON
    /// emitted by Rust — the Swift call site decodes it into a typed struct.
    func fetchTokenBalanceJSON(chainId: UInt32, paramsJson: String) async throws -> String {
        try await service().fetchTokenBalance(chainId: chainId, paramsJson: paramsJson)
    }

    /// Sign and broadcast a token transfer (ERC-20, SPL, etc.).
    func signAndSendToken(chainId: UInt32, paramsJson: String) async throws -> String {
        try await service().signAndSendToken(chainId: chainId, paramsJson: paramsJson)
    }

    // MARK: Fee estimate

    func fetchFeeEstimateJSON(chainId: UInt32) async throws -> String {
        try await service().fetchFeeEstimate(chainId: chainId)
    }

    func fetchFeeEstimateJSON(chainName: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await fetchFeeEstimateJSON(chainId: chainId)
    }

    // MARK: Bitcoin HD (xpub / ypub / zpub)

    /// Derive a contiguous range of BIP32 child addresses from an
    /// account-level extended public key. `change` is 0 for receive and 1
    /// for change. Returns the raw JSON array emitted by Rust
    /// (`[{index, change, address}]`).
    func deriveBitcoinHdAddressesJSON(
        xpub: String,
        change: UInt32,
        startIndex: UInt32,
        count: UInt32
    ) async throws -> String {
        try await service().deriveBitcoinHdAddresses(
            xpub: xpub,
            change: change,
            startIndex: startIndex,
            count: count
        )
    }

    /// Scan an xpub's receive + change legs via Esplora and return the raw
    /// aggregated-balance JSON (`HdXpubBalance`).
    func fetchBitcoinXpubBalanceJSON(
        xpub: String,
        receiveCount: UInt32 = 20,
        changeCount: UInt32 = 20
    ) async throws -> String {
        try await service().fetchBitcoinXpubBalance(
            xpub: xpub,
            receiveCount: receiveCount,
            changeCount: changeCount
        )
    }

    /// Find the first unused address on the given leg (0 = receive, 1 =
    /// change) within the supplied gap limit. Returns the raw JSON (which
    /// may be `"null"` if the window is exhausted).
    func fetchBitcoinNextUnusedAddressJSON(
        xpub: String,
        change: UInt32 = 0,
        gapLimit: UInt32 = 20
    ) async throws -> String {
        try await service().fetchBitcoinNextUnusedAddress(
            xpub: xpub,
            change: change,
            gapLimit: gapLimit
        )
    }

    // MARK: Prices / fiat rates

    /// One coin the caller wants priced. Matches
    /// `core::price::PriceRequestCoin` — field names encode as camelCase to
    /// line up with the Rust serde attribute.
    struct PriceRequestCoinInput: Encodable {
        let holdingKey: String
        let symbol: String
        let coinGeckoId: String
    }

    /// Fetch USD spot prices for `coins` from `provider`. Returns a
    /// dictionary keyed by `holdingKey`. `provider` accepts the Swift
    /// `PricingProvider.rawValue` strings ("CoinGecko", "Binance Public API",
    /// "Coinbase Exchange API", "CoinPaprika", "CoinLore"). `apiKey` is
    /// consulted only by CoinGecko.
    func fetchPricesViaRust(
        provider: String,
        coins: [PriceRequestCoinInput],
        apiKey: String
    ) async throws -> [String: Double] {
        let coinsJson = try String(
            data: JSONEncoder().encode(coins),
            encoding: .utf8
        ) ?? "[]"
        let raw = try await service().fetchPrices(
            provider: provider,
            coinsJson: coinsJson,
            apiKey: apiKey
        )
        guard let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    /// Fetch USD-relative fiat rates from `provider`. `currencies` are ISO
    /// codes. The returned map always includes `"USD": 1.0`. Accepted
    /// providers match the Swift `FiatRateProvider.rawValue` strings.
    func fetchFiatRatesViaRust(
        provider: String,
        currencies: [String]
    ) async throws -> [String: Double] {
        let json = try String(
            data: JSONEncoder().encode(currencies),
            encoding: .utf8
        ) ?? "[]"
        let raw = try await service().fetchFiatRates(
            provider: provider,
            currenciesJson: json
        )
        guard let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }
}

// MARK: - Derivation + send pipeline

extension WalletServiceBridge {

    /// Derive the signing key for `chain` from `seedPhrase` + `derivationPath`,
    /// then call `sign_and_send` on the Rust WalletService.
    ///
    /// `paramsBuilder` receives the derived `privateKeyHex` (and optional
    /// `publicKeyHex`) and must return the chain-specific params JSON string.
    func signAndSendWithDerivation(
        chainId: UInt32,
        seedPhrase: String,
        chain: SeedDerivationChain,
        derivationPath: String,
        paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String?) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain,
            network: .mainnet,
            seedPhrase: seedPhrase,
            derivationPath: derivationPath,
            passphrase: nil,
            iterationCount: nil,
            hmacKeyString: nil,
            requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex else {
            throw WalletServiceBridgeError.serviceInit("derivation did not return private key for chain \(chainId)")
        }
        let paramsJson = paramsBuilder(privKeyHex, derived.publicKeyHex)
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }

    /// Same as `signAndSendWithDerivation`, but routes through
    /// `sign_and_send_token` on the Rust side (for ERC-20 / SPL / TRC-20 /
    /// NEP-141 / Stellar assets). `paramsBuilder` receives the derived
    /// `privateKeyHex` and optional `publicKeyHex` and must produce the
    /// token-specific params JSON.
    func signAndSendTokenWithDerivation(
        chainId: UInt32,
        seedPhrase: String,
        chain: SeedDerivationChain,
        derivationPath: String,
        paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String?) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain,
            network: .mainnet,
            seedPhrase: seedPhrase,
            derivationPath: derivationPath,
            passphrase: nil,
            iterationCount: nil,
            hmacKeyString: nil,
            requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex else {
            throw WalletServiceBridgeError.serviceInit("token derivation did not return private key for chain \(chainId)")
        }
        let paramsJson = paramsBuilder(privKeyHex, derived.publicKeyHex)
        return try await signAndSendToken(chainId: chainId, paramsJson: paramsJson)
    }

    /// Convenience overload that also derives and passes the public key.
    func signAndSendWithDerivationAndPubKey(
        chainId: UInt32,
        seedPhrase: String,
        chain: SeedDerivationChain,
        derivationPath: String,
        paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain,
            network: .mainnet,
            seedPhrase: seedPhrase,
            derivationPath: derivationPath,
            passphrase: nil,
            iterationCount: nil,
            hmacKeyString: nil,
            requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex,
              let pubKeyHex  = derived.publicKeyHex else {
            throw WalletServiceBridgeError.serviceInit("derivation did not return key material for chain \(chainId)")
        }
        let paramsJson = paramsBuilder(privKeyHex, pubKeyHex)
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }
}

// MARK: - Typed convenience helpers

extension WalletServiceBridge {

    // These decode the JSON returned by Rust into typed Swift values.
    // Add more as the UI needs them.

    func fetchSolanaBalance(address: String) async throws -> SolanaBalanceResponse {
        let json = try await fetchBalanceJSON(chainId: SpectraChainID.solana, address: address)
        return try JSONDecoder().decode(SolanaBalanceResponse.self, from: Data(json.utf8))
    }

    func fetchNearBalance(address: String) async throws -> NearBalanceResponse {
        let json = try await fetchBalanceJSON(chainId: SpectraChainID.near, address: address)
        return try JSONDecoder().decode(NearBalanceResponse.self, from: Data(json.utf8))
    }

    /// Fetch an ERC-20 balance for `holder` on `chainId` (any EVM chain).
    func fetchErc20Balance(
        chainId: UInt32,
        contract: String,
        holder: String
    ) async throws -> Erc20BalanceResponse {
        let payload = """
        {"contract":"\(contract)","holder":"\(holder)"}
        """
        let json = try await fetchTokenBalanceJSON(chainId: chainId, paramsJson: payload)
        return try JSONDecoder().decode(Erc20BalanceResponse.self, from: Data(json.utf8))
    }

    /// Derive the signing key for the given EVM chain, then broadcast an ERC-20
    /// `transfer(to, amount_raw)`. `amountRaw` must already be scaled by the
    /// token's decimals.
    func signAndSendErc20WithDerivation(
        chainId: UInt32,
        seedPhrase: String,
        derivationPath: String,
        from: String,
        contract: String,
        to: String,
        amountRaw: String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: .ethereum,
            network: .mainnet,
            seedPhrase: seedPhrase,
            derivationPath: derivationPath,
            passphrase: nil,
            iterationCount: nil,
            hmacKeyString: nil,
            requestedOutputs: [.address, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex else {
            throw WalletServiceBridgeError.serviceInit("erc20: derivation missing private key")
        }
        let payload = """
        {"from":"\(from)","contract":"\(contract)","to":"\(to)","amount_raw":"\(amountRaw)","private_key_hex":"\(privKeyHex)"}
        """
        return try await signAndSendToken(chainId: chainId, paramsJson: payload)
    }

    // MARK: SQLite state persistence

    /// Load a JSON state blob stored in the Rust-managed SQLite database.
    /// Returns `"{}"` if no value has been saved yet for `key`.
    func loadState(key: String) async throws -> String {
        try await service().loadState(dbPath: sqliteDbPath(), key: key)
    }

    /// Persist a JSON state blob in the Rust-managed SQLite database.
    func saveState(key: String, stateJSON: String) async throws {
        try await service().saveState(dbPath: sqliteDbPath(), key: key, stateJson: stateJSON)
    }

    // MARK: - Token catalog

    /// Return the built-in token catalog for a chain as a JSON array string.
    /// Pass `chainId: UInt32.max` to get all chains.
    func listBuiltinTokensJSON(chainId: UInt32) async throws -> String {
        try await service().listBuiltinTokens(chainId: chainId)
    }

    // MARK: - UTXO tx status

    /// Fetch the confirmation status of a UTXO transaction.
    /// Returns JSON `{"txid","confirmed","block_height","block_time"}`.
    /// Supported chain IDs: 0 (BTC), 3 (DOGE), 5 (LTC), 6 (BCH), 22 (BSV).
    func fetchUTXOTxStatusJSON(chainId: UInt32, txid: String) async throws -> String {
        try await service().fetchUtxoTxStatus(chainId: chainId, txid: txid)
    }

    private func sqliteDbPath() -> String {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?.path ?? NSTemporaryDirectory()
        return "\(docs)/spectra_state.db"
    }
}

// MARK: - Response types (mirror Rust structs)

struct SolanaBalanceResponse: Decodable {
    let lamports: UInt64
    let solDisplay: String
    enum CodingKeys: String, CodingKey {
        case lamports
        case solDisplay = "sol_display"
    }
}

struct NearBalanceResponse: Decodable {
    let yoctoNear: String
    let nearDisplay: String
    enum CodingKeys: String, CodingKey {
        case yoctoNear  = "yocto_near"
        case nearDisplay = "near_display"
    }
}

struct Erc20BalanceResponse: Decodable {
    let contract: String
    let holder: String
    let balanceRaw: String
    let balanceDisplay: String
    let decimals: UInt8
    let symbol: String

    enum CodingKeys: String, CodingKey {
        case contract
        case holder
        case balanceRaw = "balance_raw"
        case balanceDisplay = "balance_display"
        case decimals
        case symbol
    }
}

// MARK: - Error

enum WalletServiceBridgeError: LocalizedError {
    case unsupportedChain(String)
    case serviceInit(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let name):
            return "WalletServiceBridge: chain '\(name)' has no Rust chain ID mapping."
        case .serviceInit(let msg):
            return "WalletServiceBridge: failed to initialise WalletService — \(msg)"
        }
    }
}

// MARK: - Endpoint catalog builder

private extension WalletServiceBridge {

    /// Assembles the JSON array of ChainEndpoints that Rust WalletService expects.
    /// Reads from the existing WalletRustEndpointCatalogBridge so endpoint
    /// preferences configured elsewhere in the app are respected.
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

        // Subscan secondary endpoints for Polkadot (chain_id 110).
        payloads += explorerPayloads(
            chainId: SpectraChainID.polkadot + SpectraChainID.subscaOffset,
            chainName: "Polkadot"
        )

        // ICP Rosetta secondary endpoints (chain_id 118).
        payloads += explorerPayloads(
            chainId: SpectraChainID.icp + SpectraChainID.icOffset,
            chainName: "Internet Computer"
        )

        // Explorer/indexer endpoints (chain_id = 200 + primary chain_id).
        let explorerChains: [(UInt32, String)] = [
            (SpectraChainID.ethereum,        "Ethereum"),
            (SpectraChainID.tron,            "Tron"),
            (SpectraChainID.arbitrum,        "Arbitrum"),
            (SpectraChainID.optimism,        "Optimism"),
            (SpectraChainID.avalanche,       "Avalanche"),
            (SpectraChainID.near,            "NEAR"),
            (SpectraChainID.base,            "Base"),
            (SpectraChainID.ethereumClassic, "Ethereum Classic"),
            (SpectraChainID.bsc,             "BNB Chain"),
        ]
        for (primaryId, chainName) in explorerChains {
            payloads += explorerPayloads(
                chainId: SpectraChainID.explorerOffset + primaryId,
                chainName: chainName
            )
        }

        guard
            let data = try? JSONEncoder().encode(payloads),
            let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    // MARK: Endpoint helpers

    /// Fetches RPC/balance endpoint records for a chain and wraps them
    /// in a ChainEndpointsPayload. Falls back to an empty array on error.
    static func rpcPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (
            try? WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName,
                roles: [.rpc, .balance, .backend],
                settingsVisibleOnly: false
            )
        )?.map(\.endpoint) ?? []

        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }

    /// Uses the dedicated EVM RPC helper (returns only RPC URLs, no explorer).
    static func evmPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.evmRPCEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }

    /// Fetches explorer / indexer supplemental endpoints for a chain.
    static func explorerPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.explorerSupplementalEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
}
