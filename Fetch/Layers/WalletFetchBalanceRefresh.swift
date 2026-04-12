import Foundation

extension WalletFetchLayer {
    private typealias EVMBalanceRefreshTarget = (index: Int, wallet: ImportedWallet, address: String)
    private typealias EVMBalanceRefreshPortfolio = (nativeBalance: Double, tokenBalances: [EthereumTokenBalanceSnapshot])

    static func refreshBitcoinBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet)? in
            guard wallet.selectedChain == "Bitcoin" else {
                return nil
            }
            let hasStoredSeedPhrase = store.storedSeedPhrase(for: wallet.id) != nil
            let hasBitcoinAddress = !(wallet.bitcoinAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasExtendedPublicKey = !(wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            guard hasStoredSeedPhrase || hasBitcoinAddress || hasExtendedPublicKey else {
                return nil
            }
            return (index, wallet)
        }

        guard !walletsToRefresh.isEmpty else { return }

        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, wallet) in
            let walletID = wallet.id
            let bitcoinAddress = wallet.bitcoinAddress
            let bitcoinXPub = wallet.bitcoinXPub
            let storedSeedPhrase = store.storedSeedPhrase(for: walletID)

            // Priority 1 — HD xpub path via Rust (preferred for accuracy).
            let effectiveXpub: String?
            if let xp = bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines), !xp.isEmpty {
                effectiveXpub = xp
            } else if let seed = storedSeedPhrase,
                      let derived = try? await WalletServiceBridge.shared.deriveBitcoinAccountXpub(
                          mnemonicPhrase: seed, passphrase: "", accountPath: "m/84'/0'/0'") {
                effectiveXpub = derived
            } else {
                effectiveXpub = nil
            }
            if let xp = effectiveXpub,
               let balJSON = try? await WalletServiceBridge.shared.fetchBitcoinXpubBalanceJSON(xpub: xp),
               let data = balJSON.data(using: .utf8),
               let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let confirmedSats = obj["confirmed_sats"] as? UInt64 {
                return (index, Double(confirmedSats) / 100_000_000)
            }

            // Fallback — single-address balance via Blockstream/Mempool.
            if let bitcoinAddress,
               !bitcoinAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let fallbackBalance = try? await BitcoinBalanceService.fetchBalance(for: bitcoinAddress, networkMode: wallet.bitcoinNetworkMode) {
                return (index, fallbackBalance)
            }

            return (index, nil)
        }

        var effectiveBalances = resolvedBalances
        for (index, wallet) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Bitcoin", symbol: "BTC") {
                effectiveBalances[index] = fallback
            }
        }

        var updatedWalletHoldings: [(index: Int, holdings: [Coin])] = []
        for (index, balance) in effectiveBalances {
            let wallet = walletSnapshot[index]
            let updatedHoldings = store.applyBitcoinBalance(balance, to: wallet.holdings)
            updatedWalletHoldings.append((index: index, holdings: updatedHoldings))
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Bitcoin", wallet: store.walletByReplacingHoldings(wallet, with: updatedHoldings), holdings: updatedHoldings)
#endif
        }

        store.applyIndexedWalletHoldingUpdates(updatedWalletHoldings, to: walletSnapshot)

        if resolvedBalances.count == walletsToRefresh.count {
            store.markChainHealthy("Bitcoin")
        } else if !resolvedBalances.isEmpty {
            store.noteChainSuccessfulSync("Bitcoin")
            store.markChainDegraded("Bitcoin", detail: "Bitcoin providers are partially reachable. Showing the latest available balances.")
        } else if !walletsToRefresh.isEmpty {
            store.markChainDegraded("Bitcoin", detail: "Bitcoin providers are unavailable. Using cached balances and history.")
        }
    }

    static func refreshBitcoinCashBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Bitcoin Cash",
                  let bitcoinCashAddress = store.resolvedBitcoinCashAddress(for: wallet) else {
                return nil
            }
            return (index, wallet, bitcoinCashAddress)
        }

        guard !walletsToRefresh.isEmpty else { return }

        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, bitcoinCashAddress) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.bitcoinCash, address: bitcoinCashAddress),
               let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json) {
                balance = Double(sat) / 1e8
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Bitcoin Cash", symbol: "BCH") {
                effectiveBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        var updatedWalletHoldings: [(index: Int, holdings: [Coin])] = []
        for (index, balance) in effectiveBalances {
            let wallet = walletSnapshot[index]
            let updatedHoldings = store.applyBitcoinCashBalance(balance, to: wallet.holdings)
            updatedWalletHoldings.append((index: index, holdings: updatedHoldings))
        }

        store.applyIndexedWalletHoldingUpdates(updatedWalletHoldings, to: walletSnapshot)
        updateBalanceRefreshHealth(chainName: "Bitcoin Cash", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshBitcoinSVBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Bitcoin SV",
                  let bitcoinSVAddress = store.resolvedBitcoinSVAddress(for: wallet) else {
                return nil
            }
            return (index, wallet, bitcoinSVAddress)
        }

        guard !walletsToRefresh.isEmpty else { return }

        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, bitcoinSVAddress) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.bitcoinSv, address: bitcoinSVAddress),
               let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json) {
                balance = Double(sat) / 1e8
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var updatedWalletHoldings: [(index: Int, holdings: [Coin])] = []
        for (index, balance) in resolvedBalances {
            let wallet = walletSnapshot[index]
            let updatedHoldings = store.applyBitcoinSVBalance(balance, to: wallet.holdings)
            updatedWalletHoldings.append((index: index, holdings: updatedHoldings))
        }

        store.applyIndexedWalletHoldingUpdates(updatedWalletHoldings, to: walletSnapshot)
        updateBalanceRefreshHealth(chainName: "Bitcoin SV", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: false, using: store)
    }

    static func refreshLitecoinBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Litecoin",
                  let litecoinAddress = store.resolvedLitecoinAddress(for: wallet) else {
                return nil
            }
            return (index, wallet, litecoinAddress)
        }

        guard !walletsToRefresh.isEmpty else { return }

        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, litecoinAddress) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.litecoin, address: litecoinAddress),
               let sat = RustBalanceDecoder.uint64Field("balance_sat", from: json) {
                balance = Double(sat) / 1e8
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Litecoin", symbol: "LTC") {
                effectiveBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        var updatedWalletHoldings: [(index: Int, holdings: [Coin])] = []
        for (index, balance) in effectiveBalances {
            let wallet = walletSnapshot[index]
            let updatedHoldings = store.applyLitecoinBalance(balance, to: wallet.holdings)
            updatedWalletHoldings.append((index: index, holdings: updatedHoldings))
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Litecoin", wallet: store.walletByReplacingHoldings(wallet, with: updatedHoldings), holdings: updatedHoldings)
#endif
        }

        store.applyIndexedWalletHoldingUpdates(updatedWalletHoldings, to: walletSnapshot)
        updateBalanceRefreshHealth(chainName: "Litecoin", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshDogecoinBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = store.plannedDogecoinRefreshTargets(walletSnapshot: walletSnapshot) ??
            walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, [String])? in
                guard wallet.selectedChain == "Dogecoin",
                      !store.knownDogecoinAddresses(for: wallet).isEmpty else {
                    return nil
                }
                return (index, wallet, store.knownDogecoinAddresses(for: wallet))
            }

        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, dogecoinAddresses) in
            var didResolve = false
            var totalBalance: Double = 0
            for dogecoinAddress in dogecoinAddresses {
                if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.dogecoin, address: dogecoinAddress),
                   let koin = RustBalanceDecoder.uint64Field("balance_koin", from: json) {
                    totalBalance += Double(koin) / 1e8
                    didResolve = true
                }
            }
            return (index, didResolve ? totalBalance : nil)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let ledgerBalance = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Dogecoin", symbol: "DOGE") {
                effectiveBalances[index] = ledgerBalance
                if ledgerBalance > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, balance) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyDogecoinBalance(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Dogecoin", wallet: updatedWallets[index], holdings: updatedHoldings)
#endif
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Dogecoin", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshTronBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Tron",
                  let tronAddress = store.resolvedTronAddress(for: wallet) else {
                return nil
            }
            return (index, wallet, tronAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let trackedTronTokens = store.enabledTronTrackedTokens()
        let tronTokenTuples = trackedTronTokens.map { t in
            (contract: t.contractAddress, symbol: t.symbol, decimals: t.decimals)
        }
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, tronAddress) in
            guard let nativeJSON = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.tron, address: tronAddress),
                  let sun = RustBalanceDecoder.uint64Field("sun", from: nativeJSON) else {
                return (index, nil as (Double, [TronTokenBalanceSnapshot])?)
            }
            let trxBalance = Double(sun) / 1e6
            var tokenBalances: [TronTokenBalanceSnapshot] = []
            if !tronTokenTuples.isEmpty,
               let tokenJSON = try? await WalletServiceBridge.shared.fetchTokenBalancesJSON(chainId: SpectraChainID.tron, address: tronAddress, tokens: tronTokenTuples),
               let tokenData = tokenJSON.data(using: .utf8),
               let tokenArr = try? JSONSerialization.jsonObject(with: tokenData) as? [[String: Any]] {
                tokenBalances = tokenArr.compactMap { obj in
                    guard let contract = obj["contract"] as? String,
                          let symbol = obj["symbol"] as? String,
                          let displayStr = obj["balance_display"] as? String,
                          let balance = Double(displayStr) else { return nil }
                    return TronTokenBalanceSnapshot(symbol: symbol, contractAddress: contract, balance: balance)
                }
            }
            return (index, (trxBalance, tokenBalances))
        }

        var fallbackNativeBalances: [Int: Double] = [:]
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where resolvedBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Tron", symbol: "TRX") {
                fallbackNativeBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, balances) in resolvedBalances {
            let wallet = updatedWallets[index]
            let nativeBalance = store.resolvedTronNativeBalance(
                fetchedNativeBalance: balances.0,
                tokenBalances: balances.1,
                wallet: wallet
            )
            let updatedHoldings = store.applyTronBalances(
                nativeBalance: nativeBalance,
                tokenBalances: balances.1,
                to: wallet.holdings
            )
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Tron", wallet: updatedWallets[index], holdings: updatedHoldings)
#endif
        }

        for (index, balance) in fallbackNativeBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyTronNativeBalanceOnly(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !resolvedBalances.isEmpty || !fallbackNativeBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Tron", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshSolanaBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Solana",
                  let solanaAddress = store.resolvedSolanaAddress(for: wallet) else { return nil }
            return (index, wallet, solanaAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let trackedSolanaTokens = store.enabledSolanaTrackedTokens()
        let solanaTokenTuples = trackedSolanaTokens.map { mint, meta in
            (contract: mint, symbol: meta.symbol, decimals: meta.decimals)
        }
        let resolvedPortfolios = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            guard let nativeJSON = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.solana, address: address),
                  let lamports = RustBalanceDecoder.uint64Field("lamports", from: nativeJSON) else {
                return (index, nil as SolanaPortfolioSnapshot?)
            }
            let nativeBalance = Double(lamports) / 1e9
            var tokenBalances: [SolanaSPLTokenBalanceSnapshot] = []
            if !solanaTokenTuples.isEmpty,
               let tokenJSON = try? await WalletServiceBridge.shared.fetchTokenBalancesJSON(chainId: SpectraChainID.solana, address: address, tokens: solanaTokenTuples),
               let tokenData = tokenJSON.data(using: .utf8),
               let tokenArr = try? JSONSerialization.jsonObject(with: tokenData) as? [[String: Any]] {
                tokenBalances = tokenArr.compactMap { obj -> SolanaSPLTokenBalanceSnapshot? in
                    guard let mint = obj["contract"] as? String,
                          let displayStr = obj["balance_display"] as? String,
                          let balance = Double(displayStr),
                          balance > 0 else { return nil }
                    let meta = trackedSolanaTokens[mint]
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
            return (index, SolanaPortfolioSnapshot(nativeBalance: nativeBalance, tokenBalances: tokenBalances))
        }

        var fallbackNativeBalances: [Int: Double] = [:]
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where resolvedPortfolios[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Solana", symbol: "SOL") {
                fallbackNativeBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, portfolio) in resolvedPortfolios {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applySolanaPortfolio(
                nativeBalance: portfolio.nativeBalance,
                tokenBalances: portfolio.tokenBalances,
                to: wallet.holdings
            )
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Solana", wallet: updatedWallets[index], holdings: updatedHoldings)
#endif
        }

        for (index, balance) in fallbackNativeBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applySolanaNativeBalanceOnly(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !resolvedPortfolios.isEmpty || !fallbackNativeBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Solana", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedPortfolios.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshCardanoBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Cardano",
                  let cardanoAddress = store.resolvedCardanoAddress(for: wallet) else { return nil }
            return (index, wallet, cardanoAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.cardano, address: address),
               let lovelace = RustBalanceDecoder.uint64Field("lovelace", from: json) {
                balance = Double(lovelace) / 1_000_000
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Cardano", symbol: "ADA") {
                effectiveBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, balance) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyCardanoBalance(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Cardano", wallet: updatedWallets[index], holdings: updatedHoldings)
#endif
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Cardano", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshXRPBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "XRP Ledger",
                  let xrpAddress = store.resolvedXRPAddress(for: wallet) else { return nil }
            return (index, wallet, xrpAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.xrp, address: address),
               let drops = RustBalanceDecoder.uint64Field("drops", from: json) {
                balance = Double(drops) / 1_000_000
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "XRP Ledger", symbol: "XRP") {
                effectiveBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, balance) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyXRPBalance(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "XRP Ledger", wallet: updatedWallets[index], holdings: updatedHoldings)
#endif
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "XRP Ledger", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshStellarBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Stellar",
                  let stellarAddress = store.resolvedStellarAddress(for: wallet) else { return nil }
            return (index, wallet, stellarAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.stellar, address: address),
               let stroops = RustBalanceDecoder.int64Field("stroops", from: json) {
                balance = Double(stroops) / 10_000_000
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Stellar", symbol: "XLM") {
                effectiveBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, balance) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyStellarBalance(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Stellar", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshMoneroBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Monero",
                  let moneroAddress = store.resolvedMoneroAddress(for: wallet) else { return nil }
            return (index, wallet, moneroAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.monero, address: address),
               let piconeros = RustBalanceDecoder.uint64Field("piconeros", from: json) {
                balance = Double(piconeros) / 1_000_000_000_000
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Monero", symbol: "XMR") {
                effectiveBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, balance) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyMoneroBalance(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Monero", wallet: updatedWallets[index], holdings: updatedHoldings)
#endif
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Monero", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshSuiBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let trackedTokens = store.enabledSuiTrackedTokens()
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Sui",
                  let suiAddress = store.resolvedSuiAddress(for: wallet) else { return nil }
            return (index, wallet, suiAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedPortfolios = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let portfolio: SuiPortfolioSnapshot?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.sui, address: address),
               let mist = RustBalanceDecoder.uint64Field("mist", from: json) {
                portfolio = SuiPortfolioSnapshot(nativeBalance: Double(mist) / 1_000_000_000, tokenBalances: [])
            } else {
                portfolio = nil
            }
            return (index, portfolio)
        }

        var effectivePortfolios = resolvedPortfolios
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectivePortfolios[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Sui", symbol: "SUI") {
                effectivePortfolios[index] = SuiPortfolioSnapshot(nativeBalance: fallback, tokenBalances: [])
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, portfolio) in effectivePortfolios {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applySuiBalances(
                nativeBalance: portfolio.nativeBalance,
                tokenBalances: portfolio.tokenBalances,
                to: wallet.holdings
            )
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            store.logBalanceTelemetry(source: "network", chainName: "Sui", wallet: updatedWallets[index], holdings: updatedHoldings)
#endif
        }

        if !effectivePortfolios.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Sui", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedPortfolios.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshAptosBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Aptos",
                  let aptosAddress = store.resolvedAptosAddress(for: wallet) else { return nil }
            return (index, wallet, aptosAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let trackedTokens = store.enabledAptosTrackedTokens()
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let portfolio: AptosPortfolioSnapshot?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.aptos, address: address),
               let octas = RustBalanceDecoder.uint64Field("octas", from: json) {
                portfolio = AptosPortfolioSnapshot(nativeBalance: Double(octas) / 100_000_000, tokenBalances: [])
            } else {
                portfolio = nil
            }
            return (index, portfolio)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Aptos", symbol: "APT") {
                effectiveBalances[index] = AptosPortfolioSnapshot(nativeBalance: fallback, tokenBalances: [])
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, portfolio) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyAptosBalances(
                nativeBalance: portfolio.nativeBalance,
                tokenBalances: portfolio.tokenBalances,
                to: wallet.holdings
            )
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Aptos", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshTONBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let trackedTokens = store.enabledTONTrackedTokens()
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "TON",
                  let address = store.resolvedTONAddress(for: wallet) else { return nil }
            return (index, wallet, address)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances: [Int: TONPortfolioSnapshot] = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let portfolio: TONPortfolioSnapshot?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.ton, address: address),
               let nanotons = RustBalanceDecoder.uint64Field("nanotons", from: json) {
                portfolio = TONPortfolioSnapshot(nativeBalance: Double(nanotons) / 1_000_000_000, tokenBalances: [])
            } else {
                portfolio = nil
            }
            return (index, portfolio)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "TON", symbol: "TON") {
                effectiveBalances[index] = TONPortfolioSnapshot(nativeBalance: fallback, tokenBalances: [])
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, portfolio) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyTONBalances(
                nativeBalance: portfolio.nativeBalance,
                tokenBalances: portfolio.tokenBalances,
                to: wallet.holdings
            )
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "TON", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshICPBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Internet Computer",
                  let address = store.resolvedICPAddress(for: wallet) else { return nil }
            return (index, wallet, address)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.icp, address: address),
               let e8s = RustBalanceDecoder.uint64Field("e8s", from: json) {
                balance = Double(e8s) / 100_000_000
            } else {
                balance = nil
            }
            return (index, balance)
        }

        for (index, balance) in resolvedBalances {
            let wallet = updatedWallets[index]
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: store.applyICPBalance(balance, to: wallet.holdings))
        }

        if !resolvedBalances.isEmpty {
            store.wallets = updatedWallets
            store.markChainHealthy("Internet Computer")
        } else {
            store.markChainDegraded("Internet Computer", detail: "Internet Computer providers are unavailable. Using cached balances and history.")
        }
    }

    static func refreshNearBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let trackedTokens = store.enabledNearTrackedTokens()
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "NEAR",
                  let nearAddress = store.resolvedNearAddress(for: wallet) else { return nil }
            return (index, wallet, nearAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances: [Int: (Double?, [NearTokenBalanceSnapshot]?)] = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            // Native NEAR balance via Rust.
            var nativeBalance: Double? = nil
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.near, address: address),
               let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let yoctoStr = obj["yocto_near"] as? String,
               let yocto = Double(yoctoStr) {
                nativeBalance = yocto / 1e24
            }

            // NEP-141 token balances via Rust fetch_token_balances.
            var tokenBalances: [NearTokenBalanceSnapshot]? = nil
            if !trackedTokens.isEmpty {
                let tokenTuples = trackedTokens.map { (contract, meta) in
                    (contract: contract, symbol: meta.symbol, decimals: meta.decimals)
                }
                if let resultJson = try? await WalletServiceBridge.shared.fetchTokenBalancesJSON(
                       chainId: SpectraChainID.near, address: address, tokens: tokenTuples),
                   let resultData = resultJson.data(using: .utf8),
                   let results = try? JSONSerialization.jsonObject(with: resultData) as? [[String: Any]] {
                    tokenBalances = results.compactMap { obj -> NearTokenBalanceSnapshot? in
                        guard let contract = obj["contract"] as? String,
                              let rawStr = obj["balance_raw"] as? String,
                              let decimals = obj["decimals"] as? Int,
                              let meta = trackedTokens[contract],
                              let rawDouble = Double(rawStr) else { return nil }
                        let balance = rawDouble / pow(10, Double(decimals))
                        return NearTokenBalanceSnapshot(
                            contractAddress: contract,
                            symbol: meta.symbol,
                            name: meta.name,
                            tokenStandard: meta.tokenStandard,
                            decimals: decimals,
                            balance: balance,
                            marketDataID: meta.marketDataID,
                            coinGeckoID: meta.coinGeckoID
                        )
                    }
                }
            }

            guard nativeBalance != nil || tokenBalances != nil else {
                return (index, nil)
            }
            return (index, (nativeBalance, tokenBalances))
        }

        var effectiveNativeBalances = resolvedBalances.mapValues(\.0)
        let resolvedTokenBalances = resolvedBalances.mapValues(\.1)
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveNativeBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "NEAR", symbol: "NEAR") {
                effectiveNativeBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, _, _) in walletsToRefresh {
            guard effectiveNativeBalances[index] != nil || resolvedTokenBalances[index] != nil else { continue }
            let wallet = updatedWallets[index]
            let nativeBalance = effectiveNativeBalances[index] ?? nil
            let tokenBalances = resolvedTokenBalances[index] ?? nil
            let updatedHoldings = store.applyNearBalances(
                nativeBalance: nativeBalance,
                tokenBalances: tokenBalances,
                to: wallet.holdings
            )
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !resolvedBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "NEAR", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshPolkadotBalances(using store: WalletStore) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh = walletSnapshot.enumerated().compactMap { index, wallet -> (Int, ImportedWallet, String)? in
            guard wallet.selectedChain == "Polkadot",
                  let polkadotAddress = store.resolvedPolkadotAddress(for: wallet) else { return nil }
            return (index, wallet, polkadotAddress)
        }
        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let resolvedBalances = await store.collectLimitedConcurrentIndexedResults(from: walletsToRefresh) { (index, _, address) in
            let balance: Double?
            if let json = try? await WalletServiceBridge.shared.fetchBalanceJSON(chainId: SpectraChainID.polkadot, address: address),
               let planck = RustBalanceDecoder.uint128StringField("planck", from: json) {
                balance = planck / 10_000_000_000
            } else {
                balance = nil
            }
            return (index, balance)
        }

        var effectiveBalances = resolvedBalances
        var usedLedgerFallback = false
        for (index, wallet, _) in walletsToRefresh where effectiveBalances[index] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: wallet.id, chainName: "Polkadot", symbol: "DOT") {
                effectiveBalances[index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for (index, balance) in effectiveBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = store.applyPolkadotBalance(balance, to: wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !effectiveBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(chainName: "Polkadot", attemptedWalletCount: walletsToRefresh.count, resolvedWalletCount: resolvedBalances.count, usedLedgerFallback: usedLedgerFallback, using: store)
    }

    static func refreshEthereumBalances(using store: WalletStore) async {
        await refreshEVMBalances(
            chainName: "Ethereum",
            nativeSymbol: "ETH",
            fetchPortfolio: { address in
                try? await store.withTimeout(seconds: 25, operation: {
                    try await store.fetchEthereumPortfolio(for: address)
                })
            },
            applyPortfolio: { portfolio, holdings in
                store.applyEthereumBalances(
                    nativeBalance: portfolio.nativeBalance,
                    tokenBalances: portfolio.tokenBalances,
                    to: holdings
                )
            },
            applyFallback: { balance, holdings in
                store.applyEthereumNativeBalanceOnly(balance, to: holdings)
            },
            shouldLogTelemetry: true,
            using: store
        )
    }

    static func refreshBNBBalances(using store: WalletStore) async {
        await refreshEVMBalances(
            chainName: "BNB Chain",
            nativeSymbol: "BNB",
            fetchPortfolio: { address in
                try? await store.fetchEVMNativePortfolio(for: address, chainName: "BNB Chain")
            },
            applyPortfolio: { portfolio, holdings in
                store.applyBNBBalances(nativeBalance: portfolio.nativeBalance, tokenBalances: portfolio.tokenBalances, to: holdings)
            },
            applyFallback: { balance, holdings in
                store.applyBNBNativeBalanceOnly(balance, to: holdings)
            },
            shouldLogTelemetry: true,
            using: store
        )
    }

    static func refreshArbitrumBalances(using store: WalletStore) async {
        await refreshEVMBalances(
            chainName: "Arbitrum",
            nativeSymbol: "ETH",
            fetchPortfolio: { address in
                try? await store.fetchEVMNativePortfolio(for: address, chainName: "Arbitrum")
            },
            applyPortfolio: { portfolio, holdings in
                store.applyArbitrumBalances(nativeBalance: portfolio.nativeBalance, tokenBalances: portfolio.tokenBalances, to: holdings)
            },
            applyFallback: { balance, holdings in
                store.applyArbitrumNativeBalanceOnly(balance, to: holdings)
            },
            shouldLogTelemetry: true,
            using: store
        )
    }

    static func refreshOptimismBalances(using store: WalletStore) async {
        await refreshEVMBalances(
            chainName: "Optimism",
            nativeSymbol: "ETH",
            fetchPortfolio: { address in
                try? await store.fetchEVMNativePortfolio(for: address, chainName: "Optimism")
            },
            applyPortfolio: { portfolio, holdings in
                store.applyOptimismBalances(nativeBalance: portfolio.nativeBalance, tokenBalances: portfolio.tokenBalances, to: holdings)
            },
            applyFallback: { balance, holdings in
                store.applyOptimismNativeBalanceOnly(balance, to: holdings)
            },
            shouldLogTelemetry: true,
            using: store
        )
    }

    static func refreshETCBalances(using store: WalletStore) async {
        await refreshEVMBalances(
            chainName: "Ethereum Classic",
            nativeSymbol: "ETC",
            fetchPortfolio: { address in
                guard let portfolio = try? await store.fetchEVMNativePortfolio(for: address, chainName: "Ethereum Classic") else {
                    return nil
                }
                return (portfolio.nativeBalance, [])
            },
            applyPortfolio: { portfolio, holdings in
                store.applyETCBalances(nativeBalance: portfolio.nativeBalance, to: holdings)
            },
            applyFallback: { balance, holdings in
                store.applyETCNativeBalanceOnly(balance, to: holdings)
            },
            shouldLogTelemetry: false,
            using: store
        )
    }

    static func refreshAvalancheBalances(using store: WalletStore) async {
        await refreshEVMBalances(
            chainName: "Avalanche",
            nativeSymbol: "AVAX",
            fetchPortfolio: { address in
                try? await store.fetchEVMNativePortfolio(for: address, chainName: "Avalanche")
            },
            applyPortfolio: { portfolio, holdings in
                store.applyAvalancheBalances(nativeBalance: portfolio.nativeBalance, tokenBalances: portfolio.tokenBalances, to: holdings)
            },
            applyFallback: { balance, holdings in
                store.applyAvalancheNativeBalanceOnly(balance, to: holdings)
            },
            shouldLogTelemetry: false,
            using: store
        )
    }

    static func refreshHyperliquidBalances(using store: WalletStore) async {
        await refreshEVMBalances(
            chainName: "Hyperliquid",
            nativeSymbol: "HYPE",
            fetchPortfolio: { address in
                try? await store.fetchEVMNativePortfolio(for: address, chainName: "Hyperliquid")
            },
            applyPortfolio: { portfolio, holdings in
                store.applyHyperliquidBalances(nativeBalance: portfolio.nativeBalance, tokenBalances: portfolio.tokenBalances, to: holdings)
            },
            applyFallback: { balance, holdings in
                store.applyHyperliquidNativeBalanceOnly(balance, to: holdings)
            },
            shouldLogTelemetry: false,
            using: store
        )
    }

    private static func refreshEVMBalances(
        chainName: String,
        nativeSymbol: String,
        fetchPortfolio: @escaping (String) async -> EVMBalanceRefreshPortfolio?,
        applyPortfolio: @escaping (EVMBalanceRefreshPortfolio, [Coin]) -> [Coin],
        applyFallback: @escaping (Double, [Coin]) -> [Coin],
        shouldLogTelemetry: Bool,
        using store: WalletStore
    ) async {
        guard store.allowsBalanceNetworkRefresh else { return }
        let walletSnapshot = store.wallets
        let walletsToRefresh: [EVMBalanceRefreshTarget] = store
            .plannedEVMBalanceRefreshTargets(for: chainName, walletSnapshot: walletSnapshot)
            ?? walletSnapshot.enumerated().compactMap { index, wallet in
                guard wallet.selectedChain == chainName,
                      let evmAddress = store.resolvedEVMAddress(for: wallet, chainName: chainName) else {
                    return nil
                }
                return (index, wallet, evmAddress)
            }

        guard !walletsToRefresh.isEmpty else { return }

        var updatedWallets = walletSnapshot
        let plannedGroups = store.plannedEVMRefreshGroups(
            for: chainName,
            walletSnapshot: walletSnapshot,
            groupByNormalizedAddress: true
        )
        let targetsByAddress = if let plannedGroups {
            Dictionary(uniqueKeysWithValues: plannedGroups.map { ($0.normalizedAddress, $0.address) })
        } else {
            Dictionary(grouping: walletsToRefresh) { target in
                normalizeEVMAddress(target.address)
            }
            .compactMapValues { $0.first?.address }
        }
        var resolvedPortfoliosByAddress: [String: EVMBalanceRefreshPortfolio] = [:]
        await withTaskGroup(of: (String, EVMBalanceRefreshPortfolio?).self) { group in
            for (normalizedAddress, address) in targetsByAddress {
                group.addTask {
                    (normalizedAddress, await fetchPortfolio(address))
                }
            }

            while let (normalizedAddress, portfolio) = await group.next() {
                if let portfolio {
                    resolvedPortfoliosByAddress[normalizedAddress] = portfolio
                }
            }
        }

        var fallbackNativeBalances: [Int: Double] = [:]
        var usedLedgerFallback = false
        for target in walletsToRefresh where resolvedPortfoliosByAddress[normalizeEVMAddress(target.address)] == nil {
            if let fallback = store.ledgerDerivedNativeBalanceIfAvailable(for: target.wallet.id, chainName: chainName, symbol: nativeSymbol) {
                fallbackNativeBalances[target.index] = fallback
                if fallback > 0 {
                    usedLedgerFallback = true
                }
            }
        }

        for target in walletsToRefresh {
            guard let portfolio = resolvedPortfoliosByAddress[normalizeEVMAddress(target.address)] else {
                continue
            }
            let wallet = updatedWallets[target.index]
            let updatedHoldings = applyPortfolio(portfolio, wallet.holdings)
            updatedWallets[target.index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
#if DEBUG
            if shouldLogTelemetry {
                store.logBalanceTelemetry(source: "network", chainName: chainName, wallet: updatedWallets[target.index], holdings: updatedHoldings)
            }
#endif
        }

        for (index, balance) in fallbackNativeBalances {
            let wallet = updatedWallets[index]
            let updatedHoldings = applyFallback(balance, wallet.holdings)
            updatedWallets[index] = store.walletByReplacingHoldings(wallet, with: updatedHoldings)
        }

        if !resolvedPortfoliosByAddress.isEmpty || !fallbackNativeBalances.isEmpty {
            store.wallets = updatedWallets
        }

        updateBalanceRefreshHealth(
            chainName: chainName,
            attemptedWalletCount: walletsToRefresh.count,
            resolvedWalletCount: walletsToRefresh.filter {
                resolvedPortfoliosByAddress[normalizeEVMAddress($0.address)] != nil
            }.count,
            usedLedgerFallback: usedLedgerFallback,
            using: store
        )
    }

    private static func updateBalanceRefreshHealth(
        chainName: String,
        attemptedWalletCount: Int,
        resolvedWalletCount: Int,
        usedLedgerFallback: Bool,
        using store: WalletStore
    ) {
        _ = usedLedgerFallback
        guard let plan = try? WalletRustAppCoreBridge.planBalanceRefreshHealth(
            WalletRustBalanceRefreshHealthRequest(
                chainName: chainName,
                attemptedWalletCount: attemptedWalletCount,
                resolvedWalletCount: resolvedWalletCount
            )
        ) else {
            if attemptedWalletCount > 0 && resolvedWalletCount == attemptedWalletCount {
                store.markChainHealthy(chainName)
            } else if attemptedWalletCount > 0 && resolvedWalletCount > 0 {
                store.noteChainSuccessfulSync(chainName)
                store.markChainDegraded(chainName, detail: "\(chainName) providers are partially reachable. Showing the latest available balances.")
            } else if attemptedWalletCount > 0 {
                store.markChainDegraded(chainName, detail: "\(chainName) providers are unavailable. Using cached balances and history.")
            }
            return
        }

        if plan.shouldNoteSuccessfulSync {
            store.noteChainSuccessfulSync(chainName)
        }
        if plan.shouldMarkHealthy {
            store.markChainHealthy(chainName)
        } else if let degradedDetail = plan.degradedDetail {
            store.markChainDegraded(chainName, detail: degradedDetail)
        }
    }
}

private extension WalletStore {
    func plannedEVMBalanceRefreshTargets(
        for chainName: String,
        walletSnapshot: [ImportedWallet]
    ) -> [(index: Int, wallet: ImportedWallet, address: String)]? {
        let request = WalletRustEVMRefreshTargetsRequest(
            chainName: chainName,
            wallets: walletSnapshot.enumerated().map { index, wallet in
                WalletRustEVMRefreshWalletInput(
                    index: index,
                    walletID: wallet.id.uuidString,
                    selectedChain: wallet.selectedChain,
                    address: resolvedEVMAddress(for: wallet, chainName: chainName)
                )
            },
            allowedWalletIDs: nil,
            groupByNormalizedAddress: true
        )

        guard let plan = try? WalletRustAppCoreBridge.planEVMRefreshTargets(request) else {
            return nil
        }

        return plan.walletTargets.compactMap { target in
            guard walletSnapshot.indices.contains(target.index) else { return nil }
            let wallet = walletSnapshot[target.index]
            guard wallet.id.uuidString == target.walletID else { return nil }
            return (target.index, wallet, target.address)
        }
    }

    func plannedEVMRefreshGroups(
        for chainName: String,
        walletSnapshot: [ImportedWallet],
        groupByNormalizedAddress: Bool
    ) -> [WalletRustEVMGroupedTarget]? {
        let request = WalletRustEVMRefreshTargetsRequest(
            chainName: chainName,
            wallets: walletSnapshot.enumerated().map { index, wallet in
                WalletRustEVMRefreshWalletInput(
                    index: index,
                    walletID: wallet.id.uuidString,
                    selectedChain: wallet.selectedChain,
                    address: resolvedEVMAddress(for: wallet, chainName: chainName)
                )
            },
            allowedWalletIDs: nil,
            groupByNormalizedAddress: groupByNormalizedAddress
        )

        return try? WalletRustAppCoreBridge.planEVMRefreshTargets(request).groupedTargets
    }

    func plannedDogecoinRefreshTargets(
        walletSnapshot: [ImportedWallet]
    ) -> [(index: Int, wallet: ImportedWallet, addresses: [String])]? {
        let request = WalletRustDogecoinRefreshTargetsRequest(
            wallets: walletSnapshot.enumerated().map { index, wallet in
                WalletRustDogecoinRefreshWalletInput(
                    index: index,
                    walletID: wallet.id.uuidString,
                    selectedChain: wallet.selectedChain,
                    addresses: knownDogecoinAddresses(for: wallet)
                )
            },
            allowedWalletIDs: nil
        )

        guard let targets = try? WalletRustAppCoreBridge.planDogecoinRefreshTargets(request) else {
            return nil
        }

        return targets.compactMap { target in
            guard walletSnapshot.indices.contains(target.index) else { return nil }
            let wallet = walletSnapshot[target.index]
            guard wallet.id.uuidString == target.walletID else { return nil }
            return (target.index, wallet, target.addresses)
        }
    }
}
