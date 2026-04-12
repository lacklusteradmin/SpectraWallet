import Foundation

enum WalletFetchLayer {
    static func loadMoreOnChainHistory(for walletIDs: Set<UUID>, using store: WalletStore) async {
        guard store.canLoadMoreOnChainHistory(for: walletIDs) else { return }
        store.isLoadingMoreOnChainHistory = true
        defer { store.isLoadingMoreOnChainHistory = false }

        let eligibleWalletIDs = Set(walletIDs.filter(store.canLoadMoreHistory(for:)))

        if store.hasBitcoinWallets {
            await store.refreshBitcoinTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasBitcoinCashWallets {
            await store.refreshBitcoinCashTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasBitcoinSVWallets {
            await store.refreshBitcoinSVTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasLitecoinWallets {
            await store.refreshLitecoinTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasDogecoinWallets {
            await store.refreshDogecoinTransactions(limit: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasEthereumWallets {
            await store.refreshEVMTokenTransactions(chainName: "Ethereum", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasArbitrumWallets {
            await store.refreshEVMTokenTransactions(chainName: "Arbitrum", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasOptimismWallets {
            await store.refreshEVMTokenTransactions(chainName: "Optimism", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasBNBWallets {
            await store.refreshEVMTokenTransactions(chainName: "BNB Chain", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.hasAvalancheWallets {
            await store.refreshEVMTokenTransactions(chainName: "Avalanche", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: false)
        }
        if store.wallets.contains(where: { $0.selectedChain == "Hyperliquid" && store.resolvedEVMAddress(for: $0, chainName: "Hyperliquid") != nil }) {
            await store.refreshEVMTokenTransactions(chainName: "Hyperliquid", maxResults: WalletStore.HistoryPaging.endpointBatchSize, loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
        if store.wallets.contains(where: { $0.selectedChain == "Tron" && store.resolvedTronAddress(for: $0) != nil }) {
            await store.refreshTronTransactions(loadMore: true, targetWalletIDs: eligibleWalletIDs)
        }
    }

    static func refreshWalletBalance(_ walletID: UUID, using store: WalletStore) async {
        await store.withBalanceRefreshWindow {
            guard let wallet = store.wallets.first(where: { $0.id == walletID }) else { return }
            guard let refreshPlan = store.plannedWalletBalanceRefresh(for: wallet),
                  let serviceKind = refreshPlan.serviceKind else { return }

            let updatedHoldings: [Coin]?
            let bridge = WalletServiceBridge.shared

            switch serviceKind {
            case "bitcoinBulk":
                await store.refreshBitcoinBalances()
                return

            case "utxoSingleAddress":
                switch wallet.selectedChain {
                case "Bitcoin Cash":
                    guard let address = store.resolvedBitcoinCashAddress(for: wallet) else { return }
                    guard let balance = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.bitcoinCash, address: address),
                          let sat = RustBalanceDecoder.uint64Field("balance_sat", from: balance) else { return }
                    updatedHoldings = store.applyBitcoinCashBalance(Double(sat) / 1e8, to: wallet.holdings)
                case "Bitcoin SV":
                    guard let address = store.resolvedBitcoinSVAddress(for: wallet) else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.bitcoinSv, address: address),
                          let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json) else { return }
                    updatedHoldings = store.applyBitcoinSVBalance(Double(sat) / 1e8, to: wallet.holdings)
                case "Litecoin":
                    guard let address = store.resolvedLitecoinAddress(for: wallet) else { return }
                    guard let balance = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.litecoin, address: address),
                          let sat = RustBalanceDecoder.uint64Field("balance_sat", from: balance) else { return }
                    updatedHoldings = store.applyLitecoinBalance(Double(sat) / 1e8, to: wallet.holdings)
                default:
                    return
                }

            case "dogecoinBulk":
                await store.refreshDogecoinBalances()
                return

            case "evmPortfolio":
                switch wallet.selectedChain {
                case "Ethereum":
                    guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Ethereum") else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.ethereum, address: address),
                          let native = RustBalanceDecoder.evmNativeBalance(from: json) else { return }
                    updatedHoldings = store.applyEthereumBalances(
                        nativeBalance: native,
                        tokenBalances: [],
                        to: wallet.holdings
                    )
                case "Ethereum Classic":
                    guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Ethereum Classic") else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.ethereumClassic, address: address),
                          let native = RustBalanceDecoder.evmNativeBalance(from: json) else { return }
                    updatedHoldings = store.applyETCBalances(nativeBalance: native, to: wallet.holdings)
                case "Arbitrum":
                    guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Arbitrum") else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.arbitrum, address: address),
                          let native = RustBalanceDecoder.evmNativeBalance(from: json) else { return }
                    updatedHoldings = store.applyArbitrumBalances(
                        nativeBalance: native,
                        tokenBalances: [],
                        to: wallet.holdings
                    )
                case "Optimism":
                    guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Optimism") else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.optimism, address: address),
                          let native = RustBalanceDecoder.evmNativeBalance(from: json) else { return }
                    updatedHoldings = store.applyOptimismBalances(
                        nativeBalance: native,
                        tokenBalances: [],
                        to: wallet.holdings
                    )
                case "BNB Chain":
                    // BNB Chain is not in the Rust WalletService chain list — keep Swift path.
                    guard let address = store.resolvedEVMAddress(for: wallet, chainName: "BNB Chain") else { return }
                    guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "BNB Chain") else { return }
                    updatedHoldings = store.applyBNBBalances(
                        nativeBalance: portfolio.nativeBalance,
                        tokenBalances: portfolio.tokenBalances,
                        to: wallet.holdings
                    )
                case "Avalanche":
                    guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Avalanche") else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.avalanche, address: address),
                          let native = RustBalanceDecoder.evmNativeBalance(from: json) else { return }
                    updatedHoldings = store.applyAvalancheBalances(
                        nativeBalance: native,
                        tokenBalances: [],
                        to: wallet.holdings
                    )
                case "Hyperliquid":
                    // Hyperliquid is not in the Rust chain list — keep Swift path.
                    guard let address = store.resolvedEVMAddress(for: wallet, chainName: "Hyperliquid") else { return }
                    guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "Hyperliquid") else { return }
                    updatedHoldings = store.applyHyperliquidBalances(
                        nativeBalance: portfolio.nativeBalance,
                        tokenBalances: portfolio.tokenBalances,
                        to: wallet.holdings
                    )
                default:
                    return
                }

            case "tronPortfolio":
                guard let address = store.resolvedTronAddress(for: wallet) else { return }
                guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.tron, address: address),
                      let sun = RustBalanceDecoder.uint64Field("sun", from: json) else { return }
                let nativeTrx = Double(sun) / 1e6
                let tronTrackedTokens = store.enabledTronTrackedTokens()
                let tronTuples = tronTrackedTokens.map { t in (contract: t.contractAddress, symbol: t.symbol, decimals: t.decimals) }
                var tronTokenBalances: [TronTokenBalanceSnapshot] = []
                if !tronTuples.isEmpty,
                   let tokenJSON = try? await bridge.fetchTokenBalancesJSON(chainId: SpectraChainID.tron, address: address, tokens: tronTuples),
                   let tokenData = tokenJSON.data(using: .utf8),
                   let tokenArr = try? JSONSerialization.jsonObject(with: tokenData) as? [[String: Any]] {
                    tronTokenBalances = tokenArr.compactMap { obj in
                        guard let contract = obj["contract"] as? String,
                              let symbol = obj["symbol"] as? String,
                              let displayStr = obj["balance_display"] as? String,
                              let balance = Double(displayStr) else { return nil }
                        return TronTokenBalanceSnapshot(symbol: symbol, contractAddress: contract, balance: balance)
                    }
                }
                let resolvedTrx = store.resolvedTronNativeBalance(fetchedNativeBalance: nativeTrx, tokenBalances: tronTokenBalances, wallet: wallet)
                updatedHoldings = store.applyTronBalances(
                    nativeBalance: resolvedTrx,
                    tokenBalances: tronTokenBalances,
                    to: wallet.holdings
                )

            case "solanaPortfolio":
                guard let address = store.resolvedSolanaAddress(for: wallet) else { return }
                guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.solana, address: address),
                      let lamports = RustBalanceDecoder.uint64Field("lamports", from: json) else { return }
                let nativeSol = Double(lamports) / 1e9
                let solTrackedTokens = store.enabledSolanaTrackedTokens()
                let solTuples = solTrackedTokens.map { mint, meta in (contract: mint, symbol: meta.symbol, decimals: meta.decimals) }
                var splTokenBalances: [SolanaSPLTokenBalanceSnapshot] = []
                if !solTuples.isEmpty,
                   let tokenJSON = try? await bridge.fetchTokenBalancesJSON(chainId: SpectraChainID.solana, address: address, tokens: solTuples),
                   let tokenData = tokenJSON.data(using: .utf8),
                   let tokenArr = try? JSONSerialization.jsonObject(with: tokenData) as? [[String: Any]] {
                    splTokenBalances = tokenArr.compactMap { obj -> SolanaSPLTokenBalanceSnapshot? in
                        guard let mint = obj["contract"] as? String,
                              let displayStr = obj["balance_display"] as? String,
                              let balance = Double(displayStr),
                              balance > 0 else { return nil }
                        let meta = solTrackedTokens[mint]
                        return SolanaSPLTokenBalanceSnapshot(
                            mintAddress: mint,
                            sourceTokenAccountAddress: "",
                            symbol: meta?.symbol ?? (obj["symbol"] as? String ?? ""),
                            name: meta?.name ?? "",
                            tokenStandard: "SPL",
                            decimals: meta?.decimals ?? (obj["decimals"] as? Int ?? 0),
                            balance: balance,
                            marketDataID: meta?.marketDataID ?? "",
                            coinGeckoID: meta?.coinGeckoID ?? ""
                        )
                    }
                }
                updatedHoldings = store.applySolanaPortfolio(
                    nativeBalance: nativeSol,
                    tokenBalances: splTokenBalances,
                    to: wallet.holdings
                )

            case "singleBalance":
                switch wallet.selectedChain {
                case "Cardano":
                    guard let address = store.resolvedCardanoAddress(for: wallet) else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.cardano, address: address),
                          let lovelace = RustBalanceDecoder.uint64Field("lovelace", from: json) else { return }
                    updatedHoldings = store.applyCardanoBalance(Double(lovelace) / 1e6, to: wallet.holdings)
                case "XRP Ledger":
                    guard let address = store.resolvedXRPAddress(for: wallet) else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.xrp, address: address),
                          let drops = RustBalanceDecoder.uint64Field("drops", from: json) else { return }
                    updatedHoldings = store.applyXRPBalance(Double(drops) / 1e6, to: wallet.holdings)
                case "Stellar":
                    guard let address = store.resolvedStellarAddress(for: wallet) else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.stellar, address: address),
                          let stroops = RustBalanceDecoder.int64Field("stroops", from: json) else { return }
                    updatedHoldings = store.applyStellarBalance(Double(stroops) / 1e7, to: wallet.holdings)
                case "Monero":
                    guard let address = store.resolvedMoneroAddress(for: wallet) else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.monero, address: address),
                          let piconeros = RustBalanceDecoder.uint64Field("piconeros", from: json) else { return }
                    updatedHoldings = store.applyMoneroBalance(Double(piconeros) / 1e12, to: wallet.holdings)
                case "Internet Computer":
                    guard let address = store.resolvedICPAddress(for: wallet) else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.icp, address: address),
                          let e8s = RustBalanceDecoder.uint64Field("e8s", from: json) else { return }
                    updatedHoldings = store.applyICPBalance(Double(e8s) / 1e8, to: wallet.holdings)
                case "Polkadot":
                    guard let address = store.resolvedPolkadotAddress(for: wallet) else { return }
                    guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.polkadot, address: address),
                          let planck = RustBalanceDecoder.uint128StringField("planck", from: json) else { return }
                    updatedHoldings = store.applyPolkadotBalance(planck / 1e10, to: wallet.holdings)
                default:
                    return
                }

            case "suiPortfolio":
                guard let address = store.resolvedSuiAddress(for: wallet) else { return }
                guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.sui, address: address),
                      let mist = RustBalanceDecoder.uint64Field("mist", from: json) else { return }
                updatedHoldings = store.applySuiBalances(
                    nativeBalance: Double(mist) / 1e9,
                    tokenBalances: [],
                    to: wallet.holdings
                )

            case "aptosPortfolio":
                guard let address = store.resolvedAptosAddress(for: wallet) else { return }
                guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.aptos, address: address),
                      let octas = RustBalanceDecoder.uint64Field("octas", from: json) else { return }
                updatedHoldings = store.applyAptosBalances(
                    nativeBalance: Double(octas) / 1e8,
                    tokenBalances: [],
                    to: wallet.holdings
                )

            case "tonPortfolio":
                guard let address = store.resolvedTONAddress(for: wallet) else { return }
                guard let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.ton, address: address),
                      let nanotons = RustBalanceDecoder.uint64Field("nanotons", from: json) else { return }
                updatedHoldings = store.applyTONBalances(
                    nativeBalance: Double(nanotons) / 1e9,
                    tokenBalances: [],
                    to: wallet.holdings
                )

            case "nearPortfolio":
                guard let address = store.resolvedNearAddress(for: wallet) else { return }
                let nativeBalance: Double?
                if let json = try? await bridge.fetchBalanceJSON(chainId: SpectraChainID.near, address: address),
                   let near = RustBalanceDecoder.yoctoNearToDouble(from: json) {
                    nativeBalance = near
                } else {
                    nativeBalance = nil
                }
                updatedHoldings = store.applyNearBalances(
                    nativeBalance: nativeBalance,
                    tokenBalances: nil,
                    to: wallet.holdings
                )

            default:
                return
            }

            guard let updatedHoldings,
                  let index = store.wallets.firstIndex(where: { $0.id == walletID }) else { return }
            store.wallets[index] = store.walletByReplacingHoldings(store.wallets[index], with: updatedHoldings)
            store.applyWalletCollectionSideEffects()
        }
    }
}

// MARK: - JSON field extractors for Rust balance responses

enum RustBalanceDecoder {

    static func uint64Field(_ key: String, from json: String) -> UInt64? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let v = obj[key] as? UInt64 { return v }
        if let v = obj[key] as? Int    { return UInt64(v) }
        if let v = obj[key] as? Double { return UInt64(v) }
        return nil
    }

    static func int64Field(_ key: String, from json: String) -> Int64? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let v = obj[key] as? Int64  { return v }
        if let v = obj[key] as? Int    { return Int64(v) }
        if let v = obj[key] as? Double { return Int64(v) }
        return nil
    }

    /// `planck` is a u128 serialised as a JSON number; parse via Double for reasonable balances.
    static func uint128StringField(_ key: String, from json: String) -> Double? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let v = obj[key] as? Double { return v }
        if let v = obj[key] as? Int    { return Double(v) }
        if let s = obj[key] as? String { return Double(s) }
        return nil
    }

    /// EVM balance comes as a decimal string in wei; divide by 1e18 for display.
    static func evmNativeBalance(from json: String) -> Double? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wei = obj["balance_wei"] as? String,
              let d = Double(wei) else { return nil }
        return d / 1e18
    }

    /// NEAR yoctoNEAR is a large integer string; divide by 1e24.
    static func yoctoNearToDouble(from json: String) -> Double? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let yocto = obj["yocto_near"] as? String,
              let d = Double(yocto) else { return nil }
        return d / 1e24
    }
}

// MARK: - WalletStore helpers (unchanged from original)

private extension WalletStore {
    func plannedWalletBalanceRefresh(
        for wallet: ImportedWallet
    ) -> WalletRustWalletBalanceRefreshPlan? {
        let request = WalletRustWalletBalanceRefreshRequest(
            selectedChain: wallet.selectedChain,
            hasSeedPhrase: storedSeedPhrase(for: wallet.id) != nil,
            hasExtendedPublicKey: !(wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            availableAddressKinds: availableAddressKinds(for: wallet)
        )
        return try? WalletRustAppCoreBridge.planWalletBalanceRefresh(request)
    }

    func availableAddressKinds(for wallet: ImportedWallet) -> [String] {
        var kinds: [String] = []
        if !(wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            kinds.append("bitcoin")
        }
        if resolvedBitcoinCashAddress(for: wallet) != nil {
            kinds.append("bitcoinCash")
        }
        if resolvedBitcoinSVAddress(for: wallet) != nil {
            kinds.append("bitcoinSV")
        }
        if resolvedLitecoinAddress(for: wallet) != nil {
            kinds.append("litecoin")
        }
        if !knownDogecoinAddresses(for: wallet).isEmpty {
            kinds.append("dogecoin")
        }
        if resolvedEVMAddress(for: wallet, chainName: wallet.selectedChain) != nil {
            kinds.append("evm")
        }
        if resolvedTronAddress(for: wallet) != nil {
            kinds.append("tron")
        }
        if resolvedSolanaAddress(for: wallet) != nil {
            kinds.append("solana")
        }
        if resolvedCardanoAddress(for: wallet) != nil {
            kinds.append("cardano")
        }
        if resolvedXRPAddress(for: wallet) != nil {
            kinds.append("xrp")
        }
        if resolvedStellarAddress(for: wallet) != nil {
            kinds.append("stellar")
        }
        if resolvedMoneroAddress(for: wallet) != nil {
            kinds.append("monero")
        }
        if resolvedSuiAddress(for: wallet) != nil {
            kinds.append("sui")
        }
        if resolvedAptosAddress(for: wallet) != nil {
            kinds.append("aptos")
        }
        if resolvedTONAddress(for: wallet) != nil {
            kinds.append("ton")
        }
        if resolvedICPAddress(for: wallet) != nil {
            kinds.append("icp")
        }
        if resolvedNearAddress(for: wallet) != nil {
            kinds.append("near")
        }
        if resolvedPolkadotAddress(for: wallet) != nil {
            kinds.append("polkadot")
        }
        return kinds
    }
}
