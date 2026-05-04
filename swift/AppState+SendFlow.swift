import Foundation
import SwiftUI
import LocalAuthentication
import os
#if canImport(Network)
    import Network
#endif
@MainActor
extension AppState {
    private func clearAllChainSendState() {
        sendPreviewStore.bitcoinSendPreview = nil; sendPreviewStore.bitcoinCashSendPreview = nil; sendPreviewStore.bitcoinSVSendPreview = nil; sendPreviewStore.litecoinSendPreview = nil;
        sendPreviewStore.dogecoinSendPreview = nil; sendPreviewStore.ethereumSendPreview = nil; sendPreviewStore.tronSendPreview = nil; sendPreviewStore.solanaSendPreview = nil; sendPreviewStore.xrpSendPreview = nil;
        sendPreviewStore.stellarSendPreview = nil; sendPreviewStore.moneroSendPreview = nil; sendPreviewStore.cardanoSendPreview = nil; sendPreviewStore.suiSendPreview = nil; sendPreviewStore.aptosSendPreview = nil;
        sendPreviewStore.tonSendPreview = nil; sendPreviewStore.icpSendPreview = nil; sendPreviewStore.nearSendPreview = nil; sendPreviewStore.polkadotSendPreview = nil
        sendingChains = []
        preparingChains = []
        pendingSelfSendConfirmation = nil
        clearHighRiskSendConfirmation()
    }
    private func resetSendComposerFields() {
        sendAmount = ""; sendAddress = ""; sendError = nil; sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil;
        isCheckingSendDestinationBalance = false
        clearSendVerificationNotice()
        useCustomEthereumFees = false; customEthereumMaxFeeGwei = ""; customEthereumPriorityFeeGwei = ""
        sendAdvancedMode = false; sendUTXOMaxInputCount = 0; sendEnableRBF = true; sendEnableCPFP = false
        sendLitecoinChangeStrategy = .derivedChange; ethereumManualNonceEnabled = false; ethereumManualNonce = ""
        lastSentTransaction = nil
        clearAllChainSendState()
    }
    func beginSend() {
        guard let firstWallet = sendEnabledWallets.first else { return }
        sendWalletID = firstWallet.id
        sendHoldingKey = availableSendCoins(for: sendWalletID).first?.holdingKey ?? ""
        resetSendComposerFields()
        syncSendAssetSelection()
        isShowingSendSheet = true
    }
    func syncSendAssetSelection() {
        let availableHoldingKeys = availableSendCoins(for: sendWalletID).map(\.holdingKey)
        if !availableHoldingKeys.contains(sendHoldingKey) { sendHoldingKey = availableHoldingKeys.first ?? "" }
        if selectedSendCoin?.chainName != "Ethereum" {
            useCustomEthereumFees = false; customEthereumMaxFeeGwei = ""; customEthereumPriorityFeeGwei = "";
            ethereumManualNonceEnabled = false; ethereumManualNonce = ""
        }
        if selectedSendCoin?.chainName != "Litecoin" { sendLitecoinChangeStrategy = .derivedChange }
        lastSentTransaction = nil
        clearAllChainSendState()
        sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil; isCheckingSendDestinationBalance = false
    }
    func cancelSend() { isShowingSendSheet = false; resetSendComposerFields() }
    var selectedSendCoin: Coin? {
        availableSendCoins(for: sendWalletID).first(where: { $0.holdingKey == sendHoldingKey })
    }
    func sendPreviewDetails(for coin: Coin) -> SendPreviewDetails? {
        let input = SendPreviewsInput(
            bitcoin: sendPreviewStore.bitcoinSendPreview, bitcoinCash: sendPreviewStore.bitcoinCashSendPreview, bitcoinSv: sendPreviewStore.bitcoinSVSendPreview,
            litecoin: sendPreviewStore.litecoinSendPreview, dogecoin: sendPreviewStore.dogecoinSendPreview, ethereum: sendPreviewStore.ethereumSendPreview, tron: sendPreviewStore.tronSendPreview,
            solana: sendPreviewStore.solanaSendPreview, xrp: sendPreviewStore.xrpSendPreview, stellar: sendPreviewStore.stellarSendPreview, monero: sendPreviewStore.moneroSendPreview,
            cardano: sendPreviewStore.cardanoSendPreview, sui: sendPreviewStore.suiSendPreview, aptos: sendPreviewStore.aptosSendPreview, ton: sendPreviewStore.tonSendPreview, icp: sendPreviewStore.icpSendPreview,
            near: sendPreviewStore.nearSendPreview, polkadot: sendPreviewStore.polkadotSendPreview)
        guard let c = computeSendPreviewDetails(input: input, chainName: coin.chainName, coinAmount: coin.amount) else { return nil }
        return SendPreviewDetails(
            spendableBalance: c.spendableBalance, feeRateDescription: c.feeRateDescription,
            estimatedTransactionBytes: c.estimatedTransactionBytes.map(Int.init), selectedInputCount: c.selectedInputCount.map(Int.init),
            usesChangeOutput: c.usesChangeOutput, maxSendable: c.maxSendable)
    }
    var customEthereumFeeValidationError: String? {
        let code = corePlanEthereumCustomFeeValidation(
            useCustomFees: useCustomEthereumFees,
            isEthereumChain: selectedSendCoin?.chainName == "Ethereum",
            maxFeeGweiRaw: customEthereumMaxFeeGwei,
            priorityFeeGweiRaw: customEthereumPriorityFeeGwei
        )
        switch code {
        case .none: return nil
        case .invalidMaxFee: return localizedStoreString("Enter a valid Max Fee in gwei.")
        case .invalidPriorityFee: return localizedStoreString("Enter a valid Priority Fee in gwei.")
        case .maxBelowPriority: return localizedStoreString("Max Fee must be greater than or equal to Priority Fee.")
        }
    }
    func customEthereumFeeConfiguration() -> EthereumCustomFeeConfiguration? {
        guard useCustomEthereumFees else { return nil }
        guard customEthereumFeeValidationError == nil else { return nil }
        guard let maxFee = Double(customEthereumMaxFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines)),
            let priorityFee = Double(customEthereumPriorityFeeGwei.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return EthereumCustomFeeConfiguration(maxFeePerGasGwei: maxFee, maxPriorityFeePerGasGwei: priorityFee)
    }
    var customEthereumNonceValidationError: String? {
        let code = corePlanEthereumManualNonceValidation(
            manualNonceEnabled: ethereumManualNonceEnabled, nonceRaw: ethereumManualNonce
        )
        switch code {
        case .none: return nil
        case .empty: return localizedStoreString("Enter a nonce value for manual nonce mode.")
        case .notNonNegativeInteger: return localizedStoreString("Nonce must be a non-negative integer.")
        case .tooLarge: return localizedStoreString("Nonce value is too large.")
        }
    }
    func explicitEthereumNonce() -> Int? {
        guard ethereumManualNonceEnabled else { return nil }
        guard customEthereumNonceValidationError == nil else { return nil }
        return Int(ethereumManualNonce.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func selectedWalletForSend() -> ImportedWallet? { wallet(for: sendWalletID) }
    func selectedPendingEthereumSendTransaction() -> TransactionRecord? {
        guard let wallet = selectedWalletForSend() else { return nil }
        return transactions.first { record in
            record.walletID == wallet.id
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }
    }
    func pendingEthereumSendTransaction(with transactionID: UUID) -> TransactionRecord? {
        transactions.first { record in
            record.id == transactionID
                && record.chainName == "Ethereum"
                && record.kind == .send
                && record.status == .pending
                && record.transactionHash != nil
        }
    }
    func prepareEthereumReplacementContext(cancel: Bool) async {
        guard let pendingTransaction = selectedPendingEthereumSendTransaction() else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
    }
    func openEthereumReplacementComposer(for transactionID: UUID, cancel: Bool) async -> String? {
        guard let pendingTransaction = pendingEthereumSendTransaction(with: transactionID) else {
            let message = localizedStoreString("This Ethereum transaction is no longer pending, so replacement/cancel is unavailable.")
            sendError = message
            return message
        }
        guard let walletID = pendingTransaction.walletID, wallets.contains(where: { $0.id == walletID }) else {
            let message = localizedStoreString("The wallet for this pending transaction is not available.")
            sendError = message
            return message
        }
        sendWalletID = walletID
        if let ethereumHolding = availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" && $0.symbol == "ETH" })
            ?? availableSendCoins(for: sendWalletID).first(where: { $0.chainName == "Ethereum" })
        {
            sendHoldingKey = ethereumHolding.holdingKey
        }
        syncSendAssetSelection()
        selectedMainTab = .home
        await Task.yield()
        isShowingSendSheet = true
        await prepareEthereumReplacementContext(pendingTransaction: pendingTransaction, cancel: cancel)
        return sendError
    }
    func prepareEthereumReplacementContext(pendingTransaction: TransactionRecord, cancel: Bool) async {
        guard let txHash = pendingTransaction.transactionHash else {
            sendError = localizedStoreString("No pending Ethereum transaction found for this wallet.")
            return
        }
        isPreparingEthereumReplacementContext = true; defer { isPreparingEthereumReplacementContext = false }
        do {
            let nonce = try await WalletServiceBridge.shared.fetchEVMTxNonce(chainId: SpectraChainID.ethereum, txHash: txHash)
            guard let walletID = pendingTransaction.walletID, let wallet = wallets.first(where: { $0.id == walletID }) else {
                sendError = localizedStoreString("Select a wallet first."); return
            }
            sendAddress = cancel ? (wallet.ethereumAddress ?? "") : pendingTransaction.address
            sendAmount = cancel ? "0" : String(format: "%.8f", pendingTransaction.amount)
            ethereumManualNonceEnabled = true; ethereumManualNonce = String(nonce); useCustomEthereumFees = true
            let bump = coreEvmReplacementFeeBump(
                existingMaxFeeGwei: customEthereumMaxFeeGwei,
                existingPriorityFeeGwei: customEthereumPriorityFeeGwei,
                defaultMaxFeeGwei: 4.0, defaultPriorityFeeGwei: 2.0
            )
            customEthereumMaxFeeGwei = bump.maxFeeGwei
            customEthereumPriorityFeeGwei = bump.priorityFeeGwei
            sendError = localizedStoreString(
                cancel ? "Cancellation context loaded. Review fees and tap Send." : "Replacement context loaded. Review fees and tap Send.")
            await refreshSendPreview()
        } catch {
            sendError = localizedStoreFormat("Unable to prepare replacement context: %@", error.localizedDescription)
        }
    }
    func prepareEthereumSpeedUpContext() async { await prepareEthereumReplacementContext(cancel: false) }
    func prepareEthereumCancelContext() async { await prepareEthereumReplacementContext(cancel: true) }
    func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
    func mapEthereumSendError(_ error: Error) -> String {
        let message = error.localizedDescription
        switch corePlanEthereumSendErrorCode(message: message) {
        case .nonceTooLow:
            return localizedStoreString("Nonce too low. A newer transaction from this wallet is already known. Refresh and retry.")
        case .replacementUnderpriced:
            return localizedStoreString("Replacement transaction underpriced. Increase fees and retry.")
        case .alreadyKnown:
            return localizedStoreString("This transaction is already in the mempool.")
        case .insufficientFunds:
            return localizedStoreString("Insufficient ETH to cover value plus network fee.")
        case .maxFeeBelowBaseFee:
            return localizedStoreString("Max fee is below current base fee. Increase Max Fee and retry.")
        case .intrinsicGasLow:
            return localizedStoreString("Gas limit is too low for this transaction.")
        case .unknown:
            return message
        }
    }
    func evmChainContext(for chainName: String) -> EVMChainContext? {
        switch CachedCoreHelpers.evmChainContextTag(chainName: chainName, ethereumNetworkMode: ethereumNetworkMode.rawValue) {
        case "ethereum": return .ethereum
        case "ethereum_sepolia": return .ethereumSepolia
        case "ethereum_hoodi": return .ethereumHoodi
        case "ethereum_classic": return .ethereumClassic
        case "arbitrum": return .arbitrum
        case "optimism": return .optimism
        case "bnb": return .bnb
        case "avalanche": return .avalanche
        case "hyperliquid": return .hyperliquid
        case "polygon": return .polygon
        case "base": return .base
        case "linea": return .linea
        case "scroll": return .scroll
        case "blast": return .blast
        case "mantle": return .mantle
        default: return nil
        }
    }
    func isEVMChain(_ chainName: String) -> Bool { evmChainContext(for: chainName) != nil }
    func configuredEVMRPCEndpointURL(for chainName: String) -> URL? { chainName == "Ethereum" ? configuredEthereumRPCEndpointURL() : nil }
    func supportedEVMToken(for coin: Coin) -> ChainTokenRegistryEntry? {
        guard evmChainContext(for: coin.chainName) != nil else { return nil }
        if coin.chainName == "Ethereum", coin.symbol == "ETH" { return nil }
        if coin.chainName == "Ethereum Classic", coin.symbol == "ETC" { return nil }
        if coin.chainName == "Optimism", coin.symbol == "ETH" { return nil }
        if coin.chainName == "BNB Chain", coin.symbol == "BNB" { return nil }
        if coin.chainName == "Avalanche", coin.symbol == "AVAX" { return nil }
        if coin.chainName == "Hyperliquid", coin.symbol == "HYPE" { return nil }
        let chainTokens = TokenTrackingChain.forChainName(coin.chainName).map { enabledEVMTrackedTokens(for: $0) } ?? []
        if let contractAddress = coin.contractAddress {
            let normalizedContract = normalizeEVMAddress(contractAddress)
            return chainTokens.first { $0.symbol == coin.symbol && $0.contractAddress == normalizedContract }
        }
        return chainTokens.first { $0.symbol == coin.symbol }
    }
    func isValidDogecoinAddressForPolicy(_ address: String, networkMode: DogecoinNetworkMode? = nil) -> Bool {
        AddressValidation.isValid(address, kind: "dogecoin", networkMode: (networkMode ?? dogecoinNetworkMode).rawValue)
    }
    func isValidAddress(_ address: String, for chainName: String) -> Bool {
        let mode: String? = {
            switch chainName {
            case "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin":
                return bitcoinNetworkMode.rawValue
            case "Dogecoin":
                return dogecoinNetworkMode.rawValue
            default:
                return nil
            }
        }()
        return isValidSendAddress(chainName: chainName, address: address, networkMode: mode)
    }
    func normalizedAddress(_ address: String, for chainName: String) -> String {
        normalizedSendAddress(chainName: chainName, address: address)
    }
    func isENSNameCandidate(_ value: String) -> Bool {
        isEnsNameCandidate(value: value)
    }
    func resolveEVMRecipientAddress(input: String, for chainName: String) async throws -> (address: String, usedENS: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EthereumWalletEngineError.invalidAddress }
        if AddressValidation.isValid(trimmed, kind: "evm") { return (normalizeEVMAddress(trimmed), false) }
        guard chainName == "Ethereum", isENSNameCandidate(trimmed) else { throw EthereumWalletEngineError.invalidAddress }
        let cacheKey = trimmed.lowercased()
        if let cached = cachedResolvedENSAddresses[cacheKey] { return (cached, true) }
        guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmed) else {
            throw EthereumWalletEngineError.rpcFailure("Unable to resolve ENS name '\(trimmed)'.")
        }
        cachedResolvedENSAddresses[cacheKey] = resolved
        return (resolved, true)
    }
    func evmRecipientPreflightReasons(holding: Coin, chain: EVMChainContext, destinationAddress: String) async -> [String] {
        guard let chainId = SpectraChainID.id(for: holding.chainName) else { return [] }
        let recipientHasCode: Bool?
        do {
            recipientHasCode = try await WalletServiceBridge.shared.fetchEvmHasContractCode(chainId: chainId, address: destinationAddress)
        } catch { recipientHasCode = nil }
        let token = supportedEVMToken(for: holding)
        let tokenHasCode: Bool?
        if let token {
            do {
                tokenHasCode = try await WalletServiceBridge.shared.fetchEvmHasContractCode(chainId: chainId, address: token.contractAddress)
            } catch { tokenHasCode = nil }
        } else {
            tokenHasCode = nil
        }
        let warnings = corePlanEvmRecipientPreflightWarnings(
            request: EvmRecipientPreflightRequest(
                chainName: holding.chainName, holdingSymbol: holding.symbol,
                tokenSymbol: token?.symbol, recipientHasCode: recipientHasCode, tokenHasCode: tokenHasCode
            )
        )
        return warnings.compactMap { w -> String? in
            switch w.code {
            case "recipient_is_contract":
                return localizedStoreFormat(
                    "Recipient is a smart contract on %@. Confirm it can receive %@ safely.", w.chainName ?? "", w.symbol ?? "")
            case "recipient_code_unknown":
                return localizedStoreFormat(
                    "Could not verify recipient contract state on %@. Review destination carefully.", w.chainName ?? "")
            case "token_contract_missing":
                return localizedStoreFormat(
                    "Token contract %@ appears missing on %@. This may be a wrong-network token selection.",
                    w.tokenSymbol ?? "", w.chainName ?? "")
            case "token_code_unknown":
                return localizedStoreFormat(
                    "Could not verify %@ contract bytecode on %@.", w.tokenSymbol ?? "", w.chainName ?? "")
            default: return nil
            }
        }
    }
    func evaluateHighRiskSendReasons(
        wallet: ImportedWallet, holding: Coin, amount: Double, destinationAddress: String, destinationInput: String,
        usedENSResolution: Bool = false
    ) -> [String] {
        let txAddrs = Set(transactions.compactMap { $0.chainName == holding.chainName ? $0.address : nil })
        let warnings = coreEvaluateHighRiskSendReasons(
            request: HighRiskSendRequest(
                chainName: holding.chainName, symbol: holding.symbol,
                amount: amount, holdingAmount: holding.amount,
                destinationAddress: destinationAddress, destinationInput: destinationInput,
                usedEnsResolution: usedENSResolution, walletSelectedChain: wallet.selectedChain,
                addressBookEntries: addressBook.map { HighRiskChainAddress(chainName: $0.chainName, address: $0.address) },
                txAddresses: txAddrs.map { HighRiskChainAddress(chainName: holding.chainName, address: $0) }
            ))
        return warnings.compactMap { w -> String? in
            switch w.code {
            case "invalid_format": return localizedStoreFormat("The destination address format does not match %@.", w.chain ?? "")
            case "new_address": return localizedStoreString("This is a new destination address with no prior history in this wallet.")
            case "ens_resolved":
                return localizedStoreFormat(
                    "ENS name '%@' resolved to %@. Confirm this resolved address before sending.", w.name ?? "", w.address ?? "")
            case "large_send":
                let formatted = (Double(w.percent ?? 0) / 100.0).formatted(.percent.precision(.fractionLength(0)))
                return localizedStoreFormat("This send is %@ of your %@ balance.", formatted, w.symbol ?? "")
            case "non_evm_on_evm":
                return localizedStoreFormat("Destination appears to be a non-EVM address while sending on %@.", w.chain ?? "")
            case "ens_on_l2":
                return localizedStoreFormat(
                    "ENS names are Ethereum-specific. For %@, verify the resolved EVM address very carefully.", w.chain ?? "")
            case "eth_on_utxo":
                return localizedStoreFormat("Destination appears to be an Ethereum-style address while sending on %@.", w.chain ?? "")
            case "non_tron": return localizedStoreString("Destination appears to be non-Tron format while sending on Tron.")
            case "non_solana": return localizedStoreString("Destination appears to be non-Solana format while sending on Solana.")
            case "non_xrp": return localizedStoreString("Destination appears to be non-XRP format while sending on XRP Ledger.")
            case "non_monero": return localizedStoreString("Destination appears to be non-Monero format while sending on Monero.")
            case "chain_mismatch": return localizedStoreString("Wallet-chain context mismatch detected for this send.")
            default: return nil
            }
        }
    }
    func clearHighRiskSendConfirmation() { pendingHighRiskSendReasons = []; isShowingHighRiskSendConfirmation = false }
    func confirmHighRiskSendAndSubmit() async {
        bypassHighRiskSendConfirmation = true; isShowingHighRiskSendConfirmation = false; await submitSend()
    }
    func addressBookAddressValidationMessage(for address: String, chainName: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = trimmed.isEmpty
        let isValid = !isEmpty && isValidAddress(trimmed, for: chainName)
        if isEmpty {
            switch chainName {
            case "Bitcoin": return localizedStoreString("Enter a Bitcoin address valid for the selected Bitcoin network mode.")
            case "Dogecoin": return localizedStoreString("Dogecoin addresses usually start with D, A, or 9.")
            case "Ethereum": return localizedStoreString("Ethereum addresses must start with 0x and include 40 hex characters.")
            case "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Polygon", "Base",
                "Linea", "Scroll", "Blast", "Mantle":
                return localizedStoreFormat("%@ addresses use EVM format (0x + 40 hex characters).", chainName)
            case "Tron": return localizedStoreString("Tron addresses usually start with T and are Base58 encoded.")
            case "Solana": return localizedStoreString("Solana addresses are Base58 encoded and typically 32-44 characters.")
            case "Cardano": return localizedStoreString("Cardano addresses typically start with addr1 and use bech32 format.")
            case "XRP Ledger": return localizedStoreString("XRP Ledger addresses start with r and are Base58 encoded.")
            case "Stellar": return localizedStoreString("Stellar addresses start with G and are StrKey encoded.")
            case "Monero": return localizedStoreString("Monero addresses are Base58 encoded and usually start with 4 or 8.")
            case "Sui", "Aptos": return localizedStoreFormat("%@ addresses are hex and typically start with 0x.", chainName)
            case "TON": return localizedStoreString("TON addresses are usually user-friendly strings like UQ... or raw 0:<hex> addresses.")
            case "NEAR": return localizedStoreString("NEAR addresses can be named accounts or 64-character implicit account IDs.")
            case "Polkadot": return localizedStoreString("Polkadot addresses use SS58 encoding and usually start with 1.")
            default: return localizedStoreString("Enter an address for the selected chain.")
            }
        }
        if isValid {
            return localizedStoreFormat("Valid %@ address.", chainName)
        }
        switch chainName {
        case "Bitcoin": return localizedStoreString("Enter a valid Bitcoin address for the selected Bitcoin network mode.")
        case "Dogecoin": return localizedStoreString("Enter a valid Dogecoin address beginning with D, A, or 9.")
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Polygon", "Base",
            "Linea", "Scroll", "Blast", "Mantle":
            return localizedStoreFormat("Enter a valid %@ address (0x + 40 hex characters).", chainName)
        case "Tron": return localizedStoreString("Enter a valid Tron address (starts with T).")
        case "Solana": return localizedStoreString("Enter a valid Solana address (Base58 format).")
        case "Cardano": return localizedStoreString("Enter a valid Cardano address (starts with addr1).")
        case "XRP Ledger": return localizedStoreString("Enter a valid XRP address (starts with r).")
        case "Stellar": return localizedStoreString("Enter a valid Stellar address (starts with G).")
        case "Monero": return localizedStoreString("Enter a valid Monero address (starts with 4 or 8).")
        case "Sui", "Aptos": return localizedStoreFormat("Enter a valid %@ address (starts with 0x).", chainName)
        case "TON": return localizedStoreString("Enter a valid TON address.")
        case "NEAR": return localizedStoreString("Enter a valid NEAR account ID or implicit address.")
        case "Polkadot": return localizedStoreString("Enter a valid Polkadot SS58 address.")
        default: return localizedStoreFormat("Enter a valid %@ address.", chainName)
        }
    }
    func isDuplicateAddressBookAddress(_ address: String, chainName: String, excluding entryID: UUID? = nil) -> Bool {
        let normalized = normalizedAddress(address, for: chainName)
        guard !normalized.isEmpty else { return false }
        return addressBook.contains {
            $0.id != entryID && $0.chainName == chainName && $0.address.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }
    func canSaveAddressBookEntry(name: String, address: String, chainName: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && isValidAddress(address, for: chainName)
            && !isDuplicateAddressBookAddress(address, chainName: chainName)
    }
    func addAddressBookEntry(name: String, address: String, chainName: String, note: String = "") {
        guard canSaveAddressBookEntry(name: name, address: address, chainName: chainName) else { return }
        prependAddressBookEntry(
            AddressBookEntry(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), chainName: chainName,
                address: normalizedAddress(address, for: chainName), note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    func canSaveLastSentRecipientToAddressBook() -> Bool {
        guard let tx = lastSentTransaction, tx.kind == .send else { return false }
        return canSaveAddressBookEntry(name: "\(tx.symbol) Recipient", address: tx.address, chainName: tx.chainName)
    }
    func saveLastSentRecipientToAddressBook() {
        guard let tx = lastSentTransaction, tx.kind == .send else { return }
        addAddressBookEntry(name: "\(tx.symbol) Recipient", address: tx.address, chainName: tx.chainName, note: "Saved from recent send")
    }
    func renameAddressBookEntry(id: UUID, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = addressBook.firstIndex(where: { $0.id == id }) else { return }
        let e = addressBook[index]
        var next = addressBook
        next[index] = AddressBookEntry(id: e.id, name: trimmedName, chainName: e.chainName, address: e.address, note: e.note)
        setAddressBook(next)
    }
    func removeAddressBookEntry(id: UUID) { removeAddressBookEntry(byID: id) }
    private func runSyncSelfTests(
        running: ReferenceWritableKeyPath<AppState, Bool>, results: ReferenceWritableKeyPath<AppState, [ChainSelfTestResult]>,
        lastRun: ReferenceWritableKeyPath<AppState, Date?>, suite: () -> [ChainSelfTestResult], chainName: String, abbrev: String
    ) {
        guard !self[keyPath: running] else { return }
        self[keyPath: running] = true
        self[keyPath: results] = suite()
        self[keyPath: lastRun] = Date()
        self[keyPath: running] = false
        let r = self[keyPath: results]
        let failedCount = r.filter { !$0.passed }.count
        appendChainOperationalEvent(
            failedCount == 0 ? .info : .warning, chainName: chainName,
            message: failedCount == 0
                ? "\(abbrev) self-tests passed (\(r.count) checks)." : "\(abbrev) self-tests completed with \(failedCount) failure(s).")
    }
    func runBitcoinSelfTests() {
        runSyncSelfTests(
            running: \.isRunningBitcoinSelfTests, results: \.bitcoinSelfTestResults, lastRun: \.bitcoinSelfTestsLastRunAt,
            suite: { ChainSelfTests.run("Bitcoin") }, chainName: "Bitcoin", abbrev: "BTC")
    }
    func runBitcoinCashSelfTests() {
        runSyncSelfTests(
            running: \.isRunningBitcoinCashSelfTests, results: \.bitcoinCashSelfTestResults, lastRun: \.bitcoinCashSelfTestsLastRunAt,
            suite: { ChainSelfTests.run("Bitcoin Cash") }, chainName: "Bitcoin Cash", abbrev: "BCH")
    }
    func runBitcoinSVSelfTests() {
        runSyncSelfTests(
            running: \.isRunningBitcoinSVSelfTests, results: \.bitcoinSVSelfTestResults, lastRun: \.bitcoinSVSelfTestsLastRunAt,
            suite: { ChainSelfTests.run("Bitcoin SV") }, chainName: "Bitcoin SV", abbrev: "BSV")
    }
    func runLitecoinSelfTests() {
        runSyncSelfTests(
            running: \.isRunningLitecoinSelfTests, results: \.litecoinSelfTestResults, lastRun: \.litecoinSelfTestsLastRunAt,
            suite: { ChainSelfTests.run("Litecoin") }, chainName: "Litecoin", abbrev: "LTC")
    }
    func runDogecoinSelfTests() {
        runSyncSelfTests(
            running: \.isRunningDogecoinSelfTests, results: \.dogecoinSelfTestResults, lastRun: \.dogecoinSelfTestsLastRunAt,
            suite: { ChainSelfTests.run("Dogecoin") }, chainName: "Dogecoin", abbrev: "DOGE")
    }
    func runEthereumSelfTests() async {
        guard !isRunningEthereumSelfTests else { return }
        isRunningEthereumSelfTests = true; defer { isRunningEthereumSelfTests = false }
        var results = ChainSelfTests.run("Ethereum")
        let rpcURL = configuredEthereumRPCEndpointURL()?.absoluteString ?? "https://ethereum.publicnode.com"
        let rpcLabel = configuredEthereumRPCEndpointURL()?.absoluteString ?? "default RPC pool"
        results.append(contentsOf: await selfTestsRunEthereumRpc(rpcUrl: rpcURL, rpcLabel: rpcLabel))
        if let firstEthereumWallet = wallets.first(where: { $0.selectedChain == "Ethereum" }),
            let ethereumAddress = resolvedEthereumAddress(for: firstEthereumWallet)
        {
            do {
                _ = try await fetchEthereumPortfolio(for: ethereumAddress)
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe", passed: true, chainLabel: "Ethereum",
                        outcome: .custom(text: "Successfully fetched ETH/ERC-20 portfolio for \(firstEthereumWallet.name).")))
            } catch {
                results.append(
                    ChainSelfTestResult(
                        name: "ETH Portfolio Probe", passed: false, chainLabel: "Ethereum",
                        outcome: .custom(text: "Portfolio probe failed for \(firstEthereumWallet.name): \(error.localizedDescription)")))
            }
        } else {
            results.append(
                ChainSelfTestResult(
                    name: "ETH Portfolio Probe", passed: true, chainLabel: "Ethereum",
                    outcome: .custom(text: "Skipped: no imported wallet with Ethereum enabled.")))
        }
        let diagnosticsOK = ethereumDiagnosticsJSON().map { coreDiagnosticsEvmJsonShapeOk(json: $0) } ?? false
        results.append(
            ChainSelfTestResult(
                name: "ETH Diagnostics JSON Shape", passed: diagnosticsOK, chainLabel: "Ethereum",
                outcome: .custom(
                    text: diagnosticsOK
                        ? "Diagnostics JSON contains expected top-level keys."
                        : "Diagnostics JSON missing expected keys (history/endpoints).")))
        ethereumSelfTestResults = results
        ethereumSelfTestsLastRunAt = Date()
        let failedCount = results.filter { !$0.passed }.count
        appendChainOperationalEvent(
            failedCount == 0 ? .info : .warning, chainName: "Ethereum",
            message: failedCount == 0
                ? "ETH diagnostics passed (\(results.count) checks)." : "ETH diagnostics completed with \(failedCount) failure(s).")
    }
    func operationalEvents(for chainName: String) -> [ChainOperationalEvent] { chainOperationalEventsByChain[chainName] ?? [] }
    func feePriorityOption(for chainName: String) -> ChainFeePriorityOption {
        if chainName == "Bitcoin" { return mapBitcoinFeePriorityToChainOption(bitcoinFeePriority) }
        if chainName == "Dogecoin" { return mapDogecoinFeePriorityToChainOption(dogecoinFeePriority) }
        return selectedFeePriorityOptionRawByChain[chainName].flatMap(ChainFeePriorityOption.init(rawValue:)) ?? .normal
    }
    func setFeePriorityOption(_ option: ChainFeePriorityOption, for chainName: String) {
        if chainName == "Bitcoin" { bitcoinFeePriority = mapChainOptionToBitcoinFeePriority(option); return }
        if chainName == "Dogecoin" { dogecoinFeePriority = mapChainOptionToDogecoinFeePriority(option); return }
        selectedFeePriorityOptionRawByChain[chainName] = option.rawValue
    }
    func bitcoinFeePriority(for chainName: String) -> BitcoinFeePriority {
        mapChainOptionToBitcoinFeePriority(feePriorityOption(for: chainName))
    }
    func mapBitcoinFeePriorityToChainOption(_ priority: BitcoinFeePriority) -> ChainFeePriorityOption {
        ChainFeePriorityOption(rawValue: priority.rawValue) ?? .normal
    }
    func mapChainOptionToBitcoinFeePriority(_ option: ChainFeePriorityOption) -> BitcoinFeePriority {
        BitcoinFeePriority(rawValue: option.rawValue) ?? .normal
    }
    func mapDogecoinFeePriorityToChainOption(_ priority: DogecoinFeePriority) -> ChainFeePriorityOption {
        ChainFeePriorityOption(rawValue: priority.rawValue) ?? .normal
    }
    func mapChainOptionToDogecoinFeePriority(_ option: ChainFeePriorityOption) -> DogecoinFeePriority {
        DogecoinFeePriority(rawValue: option.rawValue) ?? .normal
    }
    func persistSelectedFeePriorityOptions() {
        persistCodableToSQLite(selectedFeePriorityOptionRawByChain, key: Self.selectedFeePriorityOptionsByChainDefaultsKey)
    }
    private func runUTXORescan(
        running: ReferenceWritableKeyPath<AppState, Bool>, lastRun: ReferenceWritableKeyPath<AppState, Date?>, chainName: String,
        abbrev: String, preWork: (() async -> Void)? = nil, refreshHistory: @Sendable () async -> Void, refreshPending: @Sendable () async -> Void
    ) async {
        guard !self[keyPath: running] else { return }
        self[keyPath: running] = true; defer { self[keyPath: running] = false }
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(abbrev) rescan started.")
        await preWork?()
        async let balanceTask: () = refreshBalances()
        async let historyTask: () = refreshHistory()
        async let pendingTask: () = refreshPending()
        _ = await (balanceTask, historyTask, pendingTask)
        self[keyPath: lastRun] = Date()
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(abbrev) rescan completed.")
    }
    func runDogecoinRescan() async {
        await runUTXORescan(
            running: \.isRunningDogecoinRescan, lastRun: \.dogecoinRescanLastRunAt,
            chainName: "Dogecoin", abbrev: "DOGE",
            preWork: {
                await self.refreshUTXOAddressDiscovery(chainName: "Dogecoin")
                await self.refreshUTXOReceiveReservationState(chainName: "Dogecoin")
            },
            refreshHistory: { await self.refreshDogecoinTransactions(limit: HistoryPaging.endpointBatchSize) },
            refreshPending: { await self.refreshPendingDogecoinTransactions() }
        )
    }
    func runBitcoinRescan() async {
        await runUTXORescan(
            running: \.isRunningBitcoinRescan, lastRun: \.bitcoinRescanLastRunAt, chainName: "Bitcoin", abbrev: "BTC",
            refreshHistory: { await self.refreshBitcoinTransactions(limit: HistoryPaging.endpointBatchSize) },
            refreshPending: { await self.refreshPendingBitcoinTransactions() })
    }
    func runBitcoinCashRescan() async {
        await runUTXORescan(
            running: \.isRunningBitcoinCashRescan, lastRun: \.bitcoinCashRescanLastRunAt, chainName: "Bitcoin Cash", abbrev: "BCH",
            refreshHistory: { await self.refreshBitcoinCashTransactions(limit: HistoryPaging.endpointBatchSize) },
            refreshPending: { await self.refreshPendingBitcoinCashTransactions() })
    }
    func runBitcoinSVRescan() async {
        await runUTXORescan(
            running: \.isRunningBitcoinSVRescan, lastRun: \.bitcoinSVRescanLastRunAt, chainName: "Bitcoin SV", abbrev: "BSV",
            refreshHistory: { await self.refreshBitcoinSVTransactions(limit: HistoryPaging.endpointBatchSize) },
            refreshPending: { await self.refreshPendingBitcoinSVTransactions() })
    }
    func runLitecoinRescan() async {
        await runUTXORescan(
            running: \.isRunningLitecoinRescan, lastRun: \.litecoinRescanLastRunAt, chainName: "Litecoin", abbrev: "LTC",
            refreshHistory: { await self.refreshLitecoinTransactions(limit: HistoryPaging.endpointBatchSize) },
            refreshPending: { await self.refreshPendingLitecoinTransactions() })
    }
    func runDogecoinHistoryDiagnostics() async {
        guard !isRunningDogecoinHistoryDiagnostics else { return }
        isRunningDogecoinHistoryDiagnostics = true; defer { isRunningDogecoinHistoryDiagnostics = false }
        let walletsToRefresh = wallets.compactMap { w -> (ImportedWallet, String)? in
            guard w.selectedChain == "Dogecoin", let address = resolvedDogecoinAddress(for: w) else { return nil }
            return (w, address)
        }
        guard !walletsToRefresh.isEmpty else { dogecoinHistoryDiagnosticsLastUpdatedAt = Date(); return }
        for (wallet, address) in walletsToRefresh {
            do {
                let count = try await withTimeout(seconds: 20) {
                    try await WalletServiceBridge.shared.fetchHistoryEntryCount(chainId: SpectraChainID.dogecoin, address: address)
                }
                dogecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletId: wallet.id, identifier: address, sourceUsed: "rust",
                    transactionCount: Int32(count), nextCursor: nil, error: nil)
            } catch {
                dogecoinHistoryDiagnosticsByWallet[wallet.id] = BitcoinHistoryDiagnostics(
                    walletId: wallet.id, identifier: address, sourceUsed: "none", transactionCount: 0, nextCursor: nil,
                    error: error.localizedDescription)
            }
            dogecoinHistoryDiagnosticsLastUpdatedAt = Date()
        }
    }
    func runDogecoinEndpointReachabilityDiagnostics() async {
        guard !isCheckingDogecoinEndpointHealth else { return }
        isCheckingDogecoinEndpointHealth = true; defer { isCheckingDogecoinEndpointHealth = false }
        await runSimpleEndpointReachabilityDiagnostics(
            checks: DogecoinBalanceService.diagnosticsChecks(), profile: .diagnostics,
            setResults: { [weak self] in self?.dogecoinEndpointHealthResults = $0 },
            markUpdated: { [weak self] in self?.dogecoinEndpointHealthLastUpdatedAt = Date() })
    }
    func startNetworkPathMonitorIfNeeded() {
        #if canImport(Network)
            networkPathMonitor.pathUpdateHandler = { [weak self] path in
                let reachable = path.status == .satisfied; let constrained = path.isConstrained; let expensive = path.isExpensive
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isNetworkReachable = reachable; self.isConstrainedNetwork = constrained; self.isExpensiveNetwork = expensive
                }
            }
            networkPathMonitor.start(queue: networkPathMonitorQueue)
        #endif
    }
    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if !isActive, preferences.useFaceID, preferences.useAutoLock { isAppLocked = true; appLockError = nil }
        if !isActive {
            maintenanceTask?.cancel(); maintenanceTask = nil
            // Stop the Rust balance-refresh engine so it isn't firing
            // network requests while the app is in the background.
            Task { [weak self] in await self?.restartBalanceRefreshForCurrentConfiguration() }
            return
        }
        startMaintenanceLoopIfNeeded()
        // Resume balance refresh with the current frequency preference.
        Task { [weak self] in await self?.restartBalanceRefreshForCurrentConfiguration() }
    }
    func unlockApp() async {
        guard preferences.useFaceID else { isAppLocked = false; appLockError = nil; return }
        if await authenticateForSensitiveAction(reason: "Authenticate to unlock Spectra") { isAppLocked = false; appLockError = nil }
    }
    func startMaintenanceLoopIfNeeded() {
        guard maintenanceTask == nil else { return }
        // With no wallets there's nothing to maintain — no pending tx to
        // poll, no price work, no chain history to sync. Don't even spin
        // the loop until something's worth checking.
        // `applyWalletCollectionSideEffects` re-invokes this once a wallet
        // exists. The loop also self-exits below when wallets drop to 0.
        guard !wallets.isEmpty else { return }
        maintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Self-exit when the user deletes all wallets. Lets the
                // loop terminate naturally instead of sleeping forever
                // doing nothing — matches the no-wallet startup gate.
                if self.wallets.isEmpty {
                    self.maintenanceTask = nil
                    break
                }
                await self.runScheduledMaintenanceOnce()
                // Adaptive poll: 30s only while there's pending-tx work to
                // watch; otherwise sleep a full price-refresh interval. The
                // loop used to spin every 30s regardless, waking the CPU
                // twice a minute just to ask Rust "anything to do?". For an
                // idle user that wake is pure heat and battery.
                let pollSeconds: UInt64
                if self.appIsActive {
                    if self.hasPendingTransactionMaintenanceWork {
                        pollSeconds = Self.activeMaintenancePollSeconds
                    } else {
                        pollSeconds = max(Self.activeMaintenancePollSeconds, UInt64(self.activePriceRefreshIntervalForProfile()))
                    }
                } else {
                    pollSeconds = Self.inactiveMaintenancePollSeconds
                }
                try? await Task.sleep(nanoseconds: pollSeconds * 1_000_000_000)
            }
        }
    }
    func runScheduledMaintenanceOnce(now: Date = Date()) async {
        if appIsActive { await runActiveScheduledMaintenance(now: now); return }
        let interval = backgroundMaintenanceInterval(now: now)
        guard
            WalletRefreshPlanner.shouldRunBackgroundMaintenance(
                now: now, isNetworkReachable: isNetworkReachable, lastBackgroundMaintenanceAt: lastBackgroundMaintenanceAt,
                interval: interval)
        else { return }
        lastBackgroundMaintenanceAt = now
        await performBackgroundMaintenanceTick()
    }
    func authenticateForSensitiveAction(reason: String, allowWhenAuthenticationUnavailable: Bool = false) async -> Bool {
        guard preferences.useFaceID, preferences.requireBiometricForSendActions else { return true }
        let context = LAContext(); var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            if allowWhenAuthenticationUnavailable { return true }
            let message = "Device authentication unavailable: \(authError?.localizedDescription ?? "unknown error")"
            sendError = message; appLockError = message
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                Task { @MainActor in
                    if success {
                        self.appLockError = nil
                    } else {
                        let message = error?.localizedDescription ?? "Authentication cancelled."
                        self.sendError = message; self.appLockError = message
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
    func authenticateForSeedPhraseReveal(reason: String) async -> Bool {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
    func retryUTXOTransactionStatus(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard ["Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin"].contains(transaction.chainName), transaction.kind == .send
        else { return "Status recheck is only supported for UTXO send transactions." }
        guard transaction.transactionHash != nil else { return "This transaction has no hash to recheck." }
        if transaction.chainName == "Dogecoin" {
            var tracker = statusTrackingByTransactionID[transactionID] ?? DogecoinStatusTrackingState.initial(now: Date())
            tracker.nextCheckAt = Date.distantPast; tracker.reachedFinality = false; statusTrackingByTransactionID[transactionID] = tracker
        } else {
            var tracker = statusTrackingByTransactionID[transactionID] ?? TransactionStatusTrackingState.initial(now: Date())
            tracker.nextCheckAt = Date.distantPast; statusTrackingByTransactionID[transactionID] = tracker
        }
        switch transaction.chainName {
        case "Bitcoin": await refreshPendingBitcoinTransactions()
        case "Bitcoin Cash": await refreshPendingBitcoinCashTransactions()
        case "Bitcoin SV": await refreshPendingBitcoinSVTransactions()
        case "Litecoin": await refreshPendingLitecoinTransactions()
        case "Dogecoin": await refreshPendingDogecoinTransactions()
        default: break
        }
        guard let updated = transactions.first(where: { $0.id == transactionID }) else { return "Transaction status refresh completed." }
        if updated.status != transaction.status { return "Status updated: \(updated.statusText)." }
        if updated.status == .pending { return "No confirmation yet. Spectra will keep retrying automatically." }
        if updated.status == .failed { return updated.failureReason ?? "Transaction remains failed." }
        return "Transaction is confirmed."
    }
    func rebroadcastDogecoinTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard transaction.chainName == "Dogecoin", transaction.kind == .send else {
            return "Rebroadcast is only supported for Dogecoin send transactions."
        }
        guard await authenticateForSensitiveAction(reason: "Authorize Dogecoin rebroadcast") else {
            return sendError ?? "Authentication failed."
        }
        guard let rawTransactionHex = transaction.signedTransactionPayload,
            !rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "This transaction cannot be rebroadcast because raw signed data was not saved." }
        appendChainOperationalEvent(
            .info, chainName: "Dogecoin", message: "DOGE rebroadcast requested.", transactionHash: transaction.transactionHash)
        do {
            let txidFromJSON = try await WalletServiceBridge.shared.broadcastRawExtract(
                chainId: SpectraChainID.dogecoin, payload: rawTransactionHex, resultField: "txid")
            let txHash = txidFromJSON.isEmpty ? (transaction.transactionHash ?? "") : txidFromJSON
            let result = (transactionHash: txHash, verificationStatus: SendBroadcastVerificationStatus.deferred)
            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                transactions[index] = transactions[index].withRebroadcastUpdate(status: .pending, transactionHash: result.transactionHash)
            }
            await refreshPendingDogecoinTransactions()
            switch result.verificationStatus {
            case .verified:
                appendChainOperationalEvent(
                    .info, chainName: "Dogecoin", message: "DOGE rebroadcast verified by provider.", transactionHash: result.transactionHash
                ); return "Transaction rebroadcasted and observed on network providers."
            case .deferred:
                appendChainOperationalEvent(
                    .warning, chainName: "Dogecoin", message: "DOGE rebroadcast accepted; verification deferred.",
                    transactionHash: result.transactionHash);
                return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message):
                appendChainOperationalEvent(
                    .warning, chainName: "Dogecoin", message: "DOGE rebroadcast verification warning: \(message)",
                    transactionHash: result.transactionHash);
                return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            appendChainOperationalEvent(
                .error, chainName: "Dogecoin", message: "DOGE rebroadcast failed: \(error.localizedDescription)",
                transactionHash: transaction.transactionHash);
            return error.localizedDescription
        }
    }
    func rebroadcastSignedTransaction(for transactionID: UUID) async -> String {
        guard let transaction = transactions.first(where: { $0.id == transactionID }) else { return "Transaction not found." }
        guard transaction.kind == .send else { return "Rebroadcast is only supported for send transactions." }
        guard let payload = transaction.rebroadcastPayload, let format = transaction.rebroadcastPayloadFormat else {
            return "This transaction cannot be rebroadcast because signed payload data was not saved."
        }
        guard await authenticateForSensitiveAction(reason: "Authorize transaction rebroadcast") else {
            return sendError ?? "Authentication failed."
        }
        do {
            let (transactionHash, verificationStatus) = try await rebroadcastSignedTransaction(
                transaction: transaction, payload: payload, format: format
            )
            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                transactions[index] = transactions[index].withRebroadcastUpdate(status: .pending, transactionHash: transactionHash)
            }
            if transaction.chainName == "Dogecoin" { await refreshPendingDogecoinTransactions() }
            switch verificationStatus {
            case .verified: return "Transaction rebroadcasted and observed on the network."
            case .deferred: return "Transaction rebroadcasted. Network indexers may take a moment to reflect it."
            case .failed(let message): return "Rebroadcast sent, but verification warning: \(message)"
            }
        } catch {
            return error.localizedDescription
        }
    }
    func rebroadcastSignedTransaction(transaction: TransactionRecord, payload: String, format: String) async throws -> (
        transactionHash: String, verificationStatus: SendBroadcastVerificationStatus
    ) {
        let existing = transaction.transactionHash ?? ""
        if format == "icp.signed_hex" || format == "icp.rust_json" || format == "monero.rust_json" { return (existing, .deferred) }
        if format == "evm.raw_hex" || format == "evm.rust_json" {
            guard let chainId = SpectraChainID.id(for: transaction.chainName) else {
                throw NSError(domain: "Spectra", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported EVM chain for rebroadcast."])
            }
            let txid = try await WalletServiceBridge.shared.broadcastRawExtract(
                chainId: chainId, payload: payload, resultField: "txid")
            return (txid.isEmpty ? existing : txid, .deferred)
        }
        let prepared = try coreRebroadcastPreparePayload(format: format, rawPayload: payload)
        let resultValue = try await WalletServiceBridge.shared.broadcastRawExtract(
            chainId: prepared.chainId, payload: prepared.broadcastPayload, resultField: prepared.resultField)
        return (resultValue.isEmpty ? existing : resultValue, .deferred)
    }
    func walletDerivationPath(for wallet: ImportedWallet, chain: SeedDerivationChain) -> String {
        derivationResolution(for: wallet, chain: chain).normalizedPath
    }
    func derivationAccount(for wallet: ImportedWallet, chain: SeedDerivationChain) -> UInt32 {
        derivationResolution(for: wallet, chain: chain).accountIndex
    }
    func derivationResolution(for wallet: ImportedWallet, chain: SeedDerivationChain) -> SeedDerivationResolution {
        chain.resolve(path: wallet.seedDerivationPaths.path(for: chain))
    }
    func bitcoinNetworkMode(for wallet: ImportedWallet) -> BitcoinNetworkMode { wallet.bitcoinNetworkMode }
    func dogecoinNetworkMode(for wallet: ImportedWallet) -> DogecoinNetworkMode { wallet.dogecoinNetworkMode }
    func displayNetworkName(for chainName: String) -> String {
        switch chainName {
        case "Bitcoin": return bitcoinNetworkMode.displayName
        case "Ethereum": return ethereumNetworkMode.displayName
        case "Dogecoin": return dogecoinNetworkMode.displayName
        default: return chainName
        }
    }
    func displayChainTitle(for chainName: String) -> String {
        let network = displayNetworkName(for: chainName)
        return (network == chainName || network == "Mainnet") ? chainName : "\(chainName) \(network)"
    }
    func displayNetworkName(for wallet: ImportedWallet) -> String {
        if wallet.selectedChain == "Bitcoin" { return bitcoinNetworkMode(for: wallet).displayName }
        if wallet.selectedChain == "Dogecoin" { return dogecoinNetworkMode(for: wallet).displayName }
        return displayNetworkName(for: wallet.selectedChain)
    }
    func displayChainTitle(for wallet: ImportedWallet) -> String {
        let chain = wallet.selectedChain
        let network = displayNetworkName(for: wallet)
        return (network == chain || network == "Mainnet") ? chain : "\(chain) \(network)"
    }
    func displayNetworkName(for transaction: TransactionRecord) -> String {
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"), let walletID = transaction.walletID,
            let wallet = cachedWalletByID[walletID]
        {
            return displayNetworkName(for: wallet)
        }
        return displayNetworkName(for: transaction.chainName)
    }
    func displayChainTitle(for transaction: TransactionRecord) -> String {
        if (transaction.chainName == "Bitcoin" || transaction.chainName == "Dogecoin"), let walletID = transaction.walletID,
            let wallet = cachedWalletByID[walletID]
        {
            return displayChainTitle(for: wallet)
        }
        return displayChainTitle(for: transaction.chainName)
    }
    func supportsDeepUTXODiscovery(chainName: String) -> Bool { coreSupportsDeepUtxoDiscovery(chainName: chainName) }
    func isValidUTXOAddressForPolicy(_ address: String, chainName: String) -> Bool {
        switch chainName {
        case "Bitcoin": return AddressValidation.isValid(address, kind: "bitcoin", networkMode: bitcoinNetworkMode.rawValue)
        case "Bitcoin Cash": return AddressValidation.isValid(address, kind: "bitcoinCash")
        case "Bitcoin SV": return AddressValidation.isValid(address, kind: "bitcoinSV")
        case "Litecoin": return AddressValidation.isValid(address, kind: "litecoin")
        case "Dogecoin": return AddressValidation.isValid(address, kind: "dogecoin", networkMode: dogecoinNetworkMode.rawValue)
        default: return false
        }
    }
    func utxoDiscoveryDerivationPath(for wallet: ImportedWallet, chainName: String, branch: WalletDerivationBranch, index: Int) -> String? {
        guard let derivationChain = seedDerivationChain(for: chainName) else { return nil }
        let rawPath = walletDerivationPath(for: wallet, chain: derivationChain)
        guard let segments = coreParseDerivationPath(rawPath: rawPath), segments.count >= 5 else { return nil }
        return coreDerivationPathReplacingLastTwo(
            rawPath: rawPath, branch: UInt32(branch.rawValue), index: UInt32(max(0, index)), fallback: rawPath)
    }
    func parseUTXODiscoveryIndex(path: String?, chainName: String, branch: WalletDerivationBranch) -> Int? {
        guard let path, let derivationChain = seedDerivationChain(for: chainName),
            let pathSegments = coreParseDerivationPath(rawPath: path),
            var walletSegments = coreParseDerivationPath(rawPath: derivationChain.defaultPath), pathSegments.count == walletSegments.count,
            pathSegments.count >= 5
        else { return nil }
        walletSegments[walletSegments.count - 2] = DerivationPathSegment(value: UInt32(branch.rawValue), isHardened: false)
        walletSegments[walletSegments.count - 1] = DerivationPathSegment(value: pathSegments.last?.value ?? 0, isHardened: false)
        let candidatePrefix = coreDerivationPathString(segments: Array(walletSegments.dropLast()))
        let pathPrefix = coreDerivationPathString(segments: Array(pathSegments.dropLast()))
        guard candidatePrefix == pathPrefix, pathSegments[pathSegments.count - 2].value == UInt32(branch.rawValue) else { return nil }
        return Int(pathSegments.last?.value ?? 0)
    }
    func deriveUTXOAddress(for wallet: ImportedWallet, chainName: String, branch: WalletDerivationBranch, index: Int) -> String? {
        guard let seedPhrase = storedSeedPhrase(for: wallet.id), supportsDeepUTXODiscovery(chainName: chainName),
            let derivationPath = utxoDiscoveryDerivationPath(for: wallet, chainName: chainName, branch: branch, index: index),
            let derivationChain = utxoDiscoveryDerivationChain(for: chainName),
            let address = try? deriveSeedPhraseAddress(
                seedPhrase: seedPhrase, chain: derivationChain,
                derivationPath: derivationPath
            ), isValidUTXOAddressForPolicy(address, chainName: chainName)
        else {
            return nil
        }
        return address
    }
    func hasUTXOOnChainActivity(address: String, chainName: String) async -> Bool {
        switch chainName {
        case "Bitcoin":
            if let summary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(chainId: SpectraChainID.bitcoin, address: address) {
                let confirmedSats = UInt64(summary.smallestUnit) ?? 0
                if summary.utxoCount > 0 || confirmedSats > 0 { return true }
            }
        case "Bitcoin Cash", "Bitcoin SV", "Litecoin":
            guard let chainId = SpectraChainID.id(for: chainName) else { return false }
            if let summary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(chainId: chainId, address: address),
                let sat = UInt64(summary.smallestUnit), sat > 0
            {
                return true
            }
            if (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(chainId: chainId, address: address)) == true {
                return true
            }
        case "Dogecoin":
            if let summary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(chainId: SpectraChainID.dogecoin, address: address),
                let koin = UInt64(summary.smallestUnit), koin > 0
            {
                return true
            }
            if (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(chainId: SpectraChainID.dogecoin, address: address)) == true {
                return true
            }
        default: return false
        }
        return false
    }
    func knownUTXOAddresses(for wallet: ImportedWallet, chainName: String) -> [String] {
        var ordered: [String] = []; var seen: Set<String> = []
        func appendAddress(_ candidate: String?) {
            guard let candidate else { return }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidUTXOAddressForPolicy(trimmed, chainName: chainName), seen.insert(trimmed.lowercased()).inserted else { return }
            ordered.append(trimmed)
        }
        switch chainName {
        case "Bitcoin": appendAddress(wallet.bitcoinAddress)
        case "Bitcoin Cash": appendAddress(wallet.bitcoinCashAddress)
        case "Bitcoin SV": appendAddress(wallet.bitcoinSvAddress)
        case "Litecoin": appendAddress(wallet.litecoinAddress)
        case "Dogecoin": appendAddress(wallet.dogecoinAddress)
        default: break
        }
        appendAddress(resolvedAddress(for: wallet, chainName: chainName))
        appendAddress(reservedReceiveAddress(for: wallet, chainName: chainName, reserveIfMissing: false))
        for transaction in transactions where transaction.chainName == chainName && transaction.walletID == wallet.id {
            appendAddress(transaction.sourceAddress)
            appendAddress(transaction.changeAddress)
        }
        for discoveredAddress in discoveredUTXOAddressesByChain[chainName]?[wallet.id] ?? [] { appendAddress(discoveredAddress) }
        for ownedAddress in ownedAddresses(for: wallet.id, chainName: chainName) { appendAddress(ownedAddress) }
        return ordered
    }
    func discoverUTXOAddresses(for wallet: ImportedWallet, chainName: String) async -> [String] {
        var ordered = knownUTXOAddresses(for: wallet, chainName: chainName)
        var seen = Set(ordered.map { $0.lowercased() })
        guard supportsDeepUTXODiscovery(chainName: chainName), storedSeedPhrase(for: wallet.id) != nil else { return ordered }
        let state = keypoolState(for: wallet, chainName: chainName)
        let highestOwnedExternal =
            (chainOwnedAddressMapByChain[chainName] ?? [:]).values.filter { $0.walletID == wallet.id && $0.branch == "external" }.map(
                \.index
            ).compactMap { $0 }.max() ?? 0
        let reserved = state.reservedReceiveIndex ?? 0
        let scanUpperBound = min(
            Self.utxoDiscoveryMaxIndex,
            max(state.nextExternalIndex, max(highestOwnedExternal + 1, reserved + 1)) + Self.utxoDiscoveryGapLimit
        )
        guard scanUpperBound >= 0 else { return ordered }
        for index in 0...scanUpperBound {
            guard let derivedAddress = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: index) else {
                continue
            }
            let normalized = derivedAddress.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                ordered.append(derivedAddress)
            }
            if await hasUTXOOnChainActivity(address: derivedAddress, chainName: chainName) {
                registerOwnedAddress(
                    chainName: chainName, address: derivedAddress, walletID: wallet.id,
                    derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet, chainName: chainName, branch: .external, index: index
                    ), index: index, branch: "external"
                )
            }
        }
        return ordered
    }
    func refreshUTXOAddressDiscovery(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }
        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else {
            discoveredUTXOAddressesByChain[chainName] = [:]
            return
        }
        let discovered = await withTaskGroup(of: (String, [String]).self, returning: [String: [String]].self) { group in
            for wallet in utxoWallets {
                group.addTask { [wallet] in
                    let addresses = await self.discoverUTXOAddresses(for: wallet, chainName: chainName)
                    return (wallet.id, addresses)
                }
            }
            var mapping: [String: [String]] = [:]
            for await (walletID, addresses) in group { mapping[walletID] = addresses }
            return mapping
        }
        discoveredUTXOAddressesByChain[chainName] = discovered
    }
    func refreshUTXOReceiveReservationState(chainName: String) async {
        guard supportsDeepUTXODiscovery(chainName: chainName) else { return }
        let utxoWallets = wallets.filter { $0.selectedChain == chainName }
        guard !utxoWallets.isEmpty else { return }
        for wallet in utxoWallets {
            guard storedSeedPhrase(for: wallet.id) != nil else { continue }
            _ = reserveReceiveIndex(for: wallet, chainName: chainName)
            var state = keypoolState(for: wallet, chainName: chainName)
            guard let reservedIndex = state.reservedReceiveIndex,
                let reservedAddress = deriveUTXOAddress(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                )
            else {
                continue
            }
            registerOwnedAddress(
                chainName: chainName, address: reservedAddress, walletID: wallet.id,
                derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                ), index: reservedIndex, branch: "external"
            )
            guard await hasUTXOOnChainActivity(address: reservedAddress, chainName: chainName) else { continue }
            let nextReserved = max(state.nextExternalIndex, reservedIndex + 1)
            state.reservedReceiveIndex = nextReserved; state.nextExternalIndex = max(state.nextExternalIndex, nextReserved + 1)
            storeChainKeypoolState(state, chainName: chainName, walletID: wallet.id)
            if let nextAddress = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: nextReserved) {
                registerOwnedAddress(
                    chainName: chainName, address: nextAddress, walletID: wallet.id,
                    derivationPath: utxoDiscoveryDerivationPath(
                        for: wallet, chainName: chainName, branch: .external, index: nextReserved
                    ), index: nextReserved, branch: "external"
                )
            }
        }
    }
    func seedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        CachedCoreHelpers.seedDerivationChainRaw(chainName: chainName).flatMap(SeedDerivationChain.init(rawValue:))
    }
    func walletHasAddress(for wallet: ImportedWallet, chainName: String) -> Bool {
        resolvedAddress(for: wallet, chainName: chainName) != nil
    }
    func normalizedOwnedAddressKey(chainName: String, address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    func registerOwnedAddress(
        chainName: String, address: String?, walletID: String?, derivationPath: String?, index: Int?, branch: String?
    ) {
        guard let address, let walletID else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = normalizedOwnedAddressKey(chainName: chainName, address: trimmed)
        var addresses = chainOwnedAddressMapByChain[chainName] ?? [:]
        addresses[key] = ChainOwnedAddressRecord(
            chainName: chainName, address: trimmed, walletID: walletID, derivationPath: derivationPath, index: index, branch: branch
        )
        chainOwnedAddressMapByChain[chainName] = addresses
    }
    func ownedAddresses(for walletID: String, chainName: String) -> [String] {
        (chainOwnedAddressMapByChain[chainName] ?? [:]).compactMap { key, value in
            guard value.walletID == walletID else { return nil }
            return value.address ?? key
        }
    }
    func baselineChainKeypoolState(for wallet: ImportedWallet, chainName: String) -> ChainKeypoolState {
        let supportsDeep = supportsDeepUTXODiscovery(chainName: chainName)
        var input = ChainKeypoolBaselineInput(
            supportsDeepUtxoDiscovery: supportsDeep,
            maxTransactionExternalIndex: nil,
            maxTransactionChangeIndex: nil,
            maxOwnedExternalIndex: nil,
            maxOwnedChangeIndex: nil,
            hasResolvedAddress: false
        )
        if supportsDeep {
            let chainTransactions = transactions.filter { $0.walletID == wallet.id && $0.chainName == chainName }
            let maxExternalIndex = chainTransactions.compactMap {
                parseUTXODiscoveryIndex(path: $0.sourceDerivationPath, chainName: chainName, branch: .external)
            }.max()
            let maxChangeIndex = chainTransactions.compactMap {
                parseUTXODiscoveryIndex(path: $0.changeDerivationPath, chainName: chainName, branch: .change)
            }.max()
            let ownedForWallet = (chainOwnedAddressMapByChain[chainName] ?? [:]).values.filter { $0.walletID == wallet.id }
            let maxOwnedExternalIndex = ownedForWallet.filter { $0.branch == "external" }.compactMap(\.index).max()
            let maxOwnedChangeIndex = ownedForWallet.filter { $0.branch == "change" }.compactMap(\.index).max()
            input.maxTransactionExternalIndex = maxExternalIndex.map { Int32($0) }
            input.maxTransactionChangeIndex = maxChangeIndex.map { Int32($0) }
            input.maxOwnedExternalIndex = maxOwnedExternalIndex.map { Int32($0) }
            input.maxOwnedChangeIndex = maxOwnedChangeIndex.map { Int32($0) }
        } else {
            input.hasResolvedAddress = resolvedAddress(for: wallet, chainName: chainName) != nil
        }
        return ChainKeypoolState(coreRecord: corePlanBaselineChainKeypoolState(input: input))
    }
    func keypoolState(for wallet: ImportedWallet, chainName: String) -> ChainKeypoolState {
        let baseline = baselineChainKeypoolState(for: wallet, chainName: chainName)
        let existing = (chainKeypoolByChain[chainName] ?? [:])[wallet.id]
        let merged = ChainKeypoolState(
            coreRecord: corePlanChainKeypoolState(
                baseline: baseline.coreRecord,
                existing: existing?.coreRecord
            )
        )
        storeChainKeypoolState(merged, chainName: chainName, walletID: wallet.id)
        return merged
    }
    func reserveReceiveIndex(for wallet: ImportedWallet, chainName: String) -> Int? {
        var state = keypoolState(for: wallet, chainName: chainName)
        if let reserved = state.reservedReceiveIndex { return reserved }
        let reserved = max(state.nextExternalIndex, 0)
        state.reservedReceiveIndex = reserved; state.nextExternalIndex = reserved + 1
        storeChainKeypoolState(state, chainName: chainName, walletID: wallet.id)
        return reserved
    }
    func reserveChangeIndex(for wallet: ImportedWallet, chainName: String) -> Int? {
        var state = keypoolState(for: wallet, chainName: chainName)
        let reserved = max(state.nextChangeIndex, 0); state.nextChangeIndex = reserved + 1
        storeChainKeypoolState(state, chainName: chainName, walletID: wallet.id)
        return reserved
    }
    func reservedReceiveDerivationPath(for wallet: ImportedWallet, chainName: String, index: Int?) -> String? {
        if supportsDeepUTXODiscovery(chainName: chainName) {
            guard let index else { return nil }
            return utxoDiscoveryDerivationPath(for: wallet, chainName: chainName, branch: .external, index: index)
        }
        guard seedDerivationChain(for: chainName) != nil else { return nil }
        return seedDerivationChain(for: chainName).map { walletDerivationPath(for: wallet, chain: $0) }
    }
    func reservedReceiveAddress(for wallet: ImportedWallet, chainName: String, reserveIfMissing: Bool) -> String? {
        if supportsDeepUTXODiscovery(chainName: chainName) {
            var state = keypoolState(for: wallet, chainName: chainName)
            if state.reservedReceiveIndex == nil, reserveIfMissing {
                let reserved = max(state.nextExternalIndex, 1)
                state.reservedReceiveIndex = reserved; state.nextExternalIndex = max(state.nextExternalIndex, reserved + 1)
                storeChainKeypoolState(state, chainName: chainName, walletID: wallet.id)
            }
            guard let reservedIndex = state.reservedReceiveIndex,
                let address = deriveUTXOAddress(for: wallet, chainName: chainName, branch: .external, index: reservedIndex)
            else { return resolvedAddress(for: wallet, chainName: chainName) }
            registerOwnedAddress(
                chainName: chainName, address: address, walletID: wallet.id,
                derivationPath: utxoDiscoveryDerivationPath(
                    for: wallet, chainName: chainName, branch: .external, index: reservedIndex
                ), index: reservedIndex, branch: "external"
            )
            return address
        }
        if reserveIfMissing { _ = reserveReceiveIndex(for: wallet, chainName: chainName) }
        guard let address = resolvedAddress(for: wallet, chainName: chainName) else { return nil }
        let reservedIndex = keypoolState(for: wallet, chainName: chainName).reservedReceiveIndex
        registerOwnedAddress(
            chainName: chainName, address: address, walletID: wallet.id,
            derivationPath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex), index: reservedIndex,
            branch: "external"
        )
        return address
    }
    func activateLiveReceiveAddress(_ address: String?, for wallet: ImportedWallet, chainName: String, derivationPath: String? = nil)
        -> String
    {
        guard let address else { return "" }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let reservedIndex = reserveReceiveIndex(for: wallet, chainName: chainName)
        registerOwnedAddress(
            chainName: chainName, address: trimmed, walletID: wallet.id,
            derivationPath: derivationPath ?? reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
            index: reservedIndex, branch: "external"
        )
        return trimmed
    }
    func syncChainOwnedAddressManagementState() {
        for wallet in wallets {
            for chainName in AppEndpointDirectory.diagnosticsChains.map(\.title) {
                guard let address = resolvedAddress(for: wallet, chainName: chainName) else { continue }
                let reservedIndex = reserveReceiveIndex(for: wallet, chainName: chainName)
                registerOwnedAddress(
                    chainName: chainName, address: address, walletID: wallet.id,
                    derivationPath: reservedReceiveDerivationPath(for: wallet, chainName: chainName, index: reservedIndex),
                    index: reservedIndex, branch: "external"
                )
            }
        }
    }
    private func storeChainKeypoolState(_ state: ChainKeypoolState, chainName: String, walletID: String) {
        var perWallet = chainKeypoolByChain[chainName] ?? [:]
        perWallet[walletID] = state
        chainKeypoolByChain[chainName] = perWallet
    }
    func refreshSendDestinationRiskWarning(for coin: Coin) async {
        let probeID = "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)"
        let trimmedDestination = sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        func clearProbe() { sendDestinationRiskWarning = nil; sendDestinationInfoMessage = nil; isCheckingSendDestinationBalance = false }
        guard !trimmedDestination.isEmpty else { clearProbe(); return }
        var destinationForProbe = trimmedDestination
        var ensResolutionInfo: String?
        if !isValidAddress(trimmedDestination, for: coin.chainName) {
            if (coin.chainName == "Ethereum" || coin.chainName == "Arbitrum" || coin.chainName == "Optimism"
                || coin.chainName == "BNB Chain" || coin.chainName == "Avalanche" || coin.chainName == "Hyperliquid"
                || coin.chainName == "Polygon" || coin.chainName == "Base"
                || coin.chainName == "Linea" || coin.chainName == "Scroll" || coin.chainName == "Blast" || coin.chainName == "Mantle"),
                isENSNameCandidate(trimmedDestination)
            {
                do {
                    let resolved = try await resolveEVMRecipientAddress(input: trimmedDestination, for: coin.chainName)
                    destinationForProbe = resolved.address
                    ensResolutionInfo = resolved.usedENS ? "Resolved ENS \(trimmedDestination) to \(resolved.address)." : nil
                } catch { clearProbe(); return }
            } else {
                clearProbe(); return
            }
        }
        let addressProbeKey = "\(coin.chainName)|\(coin.symbol)|\(destinationForProbe.lowercased())"
        if lastSendDestinationProbeKey == addressProbeKey {
            sendDestinationRiskWarning = lastSendDestinationProbeWarning
            if let ensResolutionInfo {
                sendDestinationInfoMessage = [lastSendDestinationProbeInfoMessage, ensResolutionInfo].compactMap { $0 }.joined(
                    separator: " ")
            } else {
                sendDestinationInfoMessage = lastSendDestinationProbeInfoMessage
            }
            isCheckingSendDestinationBalance = false
            return
        }
        isCheckingSendDestinationBalance = true
        defer { isCheckingSendDestinationBalance = false }
        do {
            let warning: String?
            let infoMessage: String?
            switch coin.chainName {
            case "Bitcoin":
                let btcSummary = try await WalletServiceBridge.shared.fetchNativeBalanceSummary(
                    chainId: SpectraChainID.bitcoin, address: destinationForProbe)
                let btcBalance = UInt64(btcSummary.smallestUnit) ?? 0
                let m = chainRiskProbeMessages(
                    chainName: "Bitcoin", balanceLabel: "balance", balanceNonPositive: btcBalance <= 0, hasHistory: btcSummary.utxoCount > 0)
                warning = m.warning; infoMessage = m.info
            case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Polygon", "Base",
            "Linea", "Scroll", "Blast", "Mantle":
                guard let chainId = SpectraChainID.id(for: coin.chainName) else {
                    warning = nil
                    infoMessage = nil
                    break
                }
                let normalizedAddress = try validateEVMAddress(destinationForProbe)
                let probe = try await WalletServiceBridge.shared.fetchEvmAddressProbe(
                    chainId: chainId, address: normalizedAddress
                )
                let hasHistory = probe.nonce > 0
                if coin.symbol == "ETH" || coin.symbol == "BNB" || coin.symbol == "AVAX" || coin.symbol == "ARB" || coin.symbol == "OP" {
                    let m = chainRiskProbeMessages(
                        chainName: coin.chainName, balanceLabel: "\(coin.symbol) balance",
                        balanceNonPositive: probe.balanceEth <= 0,
                        hasHistory: hasHistory)
                    warning = m.warning; infoMessage = m.info
                } else if let token = supportedEVMToken(for: coin) {
                    let tokenBalances = try await WalletServiceBridge.shared.fetchEVMTokenBalancesBatch(
                        chainId: chainId, address: normalizedAddress,
                        tokens: [TokenDescriptor(contract: token.contractAddress, symbol: token.symbol, decimals: UInt8(token.decimals), name: nil)])
                    let tokenBalance = Decimal(string: tokenBalances.first?.balanceDisplay ?? "0") ?? .zero
                    warning =
                        (tokenBalance <= .zero && !hasHistory)
                        ? "Warning: this address has zero \(coin.symbol) balance and no transaction history on \(coin.chainName). Double-check recipient details."
                        : nil
                    infoMessage =
                        (tokenBalance <= .zero && hasHistory)
                        ? "Note: this address has transaction history but currently zero \(coin.symbol) balance on \(coin.chainName)." : nil
                } else {
                    warning = nil; infoMessage = nil
                }
            case "Tron":
                if coin.symbol == "TRX" || coin.symbol == "USDT" {
                    let tronSummary = try await WalletServiceBridge.shared.fetchNativeBalanceSummary(
                        chainId: SpectraChainID.tron, address: destinationForProbe)
                    let tronSun = UInt64(tronSummary.smallestUnit) ?? 0
                    let hasHistory =
                        (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(
                            chainId: SpectraChainID.tron, address: destinationForProbe)) ?? false
                    let balance: Double
                    if coin.symbol == "TRX" {
                        balance = Double(tronSun) / 1e6
                    } else {
                        let usdtResults = try await WalletServiceBridge.shared.fetchTokenBalances(
                            chainId: SpectraChainID.tron, address: destinationForProbe,
                            tokens: [TokenDescriptor(contract: TronBalanceService.usdtTronContract, symbol: "USDT", decimals: 6, name: nil)])
                        balance = usdtResults.first.flatMap { Double($0.balanceDisplay) } ?? 0
                    }
                    let label = "\(coin.symbol) balance"
                    warning =
                        (balance <= 0 && !hasHistory)
                        ? "Warning: this Tron address has zero \(coin.symbol) balance and no transaction history. Double-check recipient details."
                        : nil
                    infoMessage =
                        (balance <= 0 && hasHistory) ? "Note: this Tron address has transaction history but currently zero \(label)." : nil
                } else {
                    warning = nil; infoMessage = nil
                }
            case "Litecoin", "Dogecoin", "Solana", "XRP Ledger", "Monero", "Sui", "Aptos":
                if let cfg = coreSimpleChainRiskProbeConfig(chainName: coin.chainName, symbol: coin.symbol),
                    let chainId = SpectraChainID.id(for: coin.chainName)
                {
                    (warning, infoMessage) = await fetchChainRiskWarning(
                        chainId: chainId, address: destinationForProbe,
                        chainName: cfg.displayChainName, balanceLabel: cfg.balanceLabel)
                } else {
                    warning = nil; infoMessage = nil
                }
            case "NEAR":
                let nearBalance: Double
                if let nearSummary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(
                    chainId: SpectraChainID.near, address: destinationForProbe)
                {
                    nearBalance = Double(nearSummary.amountDisplay) ?? 0
                } else {
                    nearBalance = 0
                }
                let nearHasHistory =
                    (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(
                        chainId: SpectraChainID.near, address: destinationForProbe)) ?? false
                let m = chainRiskProbeMessages(
                    chainName: "NEAR", balanceLabel: "NEAR balance", balanceNonPositive: nearBalance <= 0, hasHistory: nearHasHistory)
                warning = m.warning; infoMessage = m.info
            default:
                warning = nil
                infoMessage = nil
            }
            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = warning
            sendDestinationInfoMessage = [infoMessage, ensResolutionInfo]
                .compactMap { $0 }.joined(separator: " ")
            lastSendDestinationProbeKey = addressProbeKey
            lastSendDestinationProbeWarning = warning
            lastSendDestinationProbeInfoMessage = sendDestinationInfoMessage
        } catch {
            guard probeID == "\(sendWalletID)|\(sendHoldingKey)|\(sendAddress)" else { return }
            sendDestinationRiskWarning = nil
            sendDestinationInfoMessage = nil
        }
    }
    func userFacingTronSendError(_ error: Error, symbol: String) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("timed out") {
            return localizedStoreString("Tron network request timed out. Please try again.")
        }
        if lower.contains("not connected") || lower.contains("offline") {
            return localizedStoreString("No network connection. Check your internet and retry.")
        }
        return message
    }
    func recordTronSendDiagnosticError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tronLastSendErrorDetails = trimmed
        tronLastSendErrorAt = Date()
    }
    private func fetchChainRiskWarning(
        chainId: UInt32, address: String, chainName: String, balanceLabel: String
    ) async -> (warning: String?, info: String?) {
        guard let summary = try? await WalletServiceBridge.shared.fetchNativeBalanceSummary(chainId: chainId, address: address) else {
            return (nil, nil)
        }
        let balance = Double(summary.amountDisplay) ?? 0
        let hasHistory = (try? await WalletServiceBridge.shared.fetchHistoryHasActivity(chainId: chainId, address: address)) ?? false
        let m = chainRiskProbeMessages(
            chainName: chainName, balanceLabel: balanceLabel, balanceNonPositive: balance <= 0, hasHistory: hasHistory)
        return (m.warning, m.info)
    }
    /// Validate that the wallet has sufficient balance for amount + fee.
    /// Returns nil on success, or a user-facing error message on failure.
    func validateSendBalance(
        amount: Double, networkFee: Double, holdingBalance: Double,
        isNativeAsset: Bool, symbol: String,
        nativeSymbol: String?, nativeBalance: Double?,
        feeDecimals: Int, chainLabel: String?
    ) -> String? {
        if isNativeAsset {
            let total = amount + networkFee
            if total > holdingBalance {
                return localizedStoreFormat(
                    "Insufficient %@ for amount plus network fee (needs ~%.\(feeDecimals)f %@).",
                    symbol, total, symbol
                )
            }
        } else {
            if amount > holdingBalance {
                return localizedStoreFormat("Insufficient %@ balance for this transfer.", symbol)
            }
            if let nativeSym = nativeSymbol, let nativeBal = nativeBalance, networkFee > nativeBal {
                if let chain = chainLabel {
                    return localizedStoreFormat(
                        "Insufficient %@ to cover %@ network fee (~%.\(feeDecimals)f %@).",
                        nativeSym, chain, networkFee, nativeSym
                    )
                }
                return localizedStoreFormat(
                    "Insufficient %@ to cover the network fee (~%.\(feeDecimals)f %@).",
                    nativeSym, networkFee, nativeSym
                )
            }
        }
        return nil
    }
    func chainRiskProbeMessages(chainName: String, balanceLabel: String, balanceNonPositive: Bool, hasHistory: Bool) -> (
        warning: String?, info: String?
    ) {
        let warning: String? =
            (balanceNonPositive && !hasHistory)
            ? localizedStoreFormat(
                "Warning: this %@ address has zero balance and no transaction history. Double-check recipient details.", chainName)
            : nil
        let info: String? =
            (balanceNonPositive && hasHistory)
            ? localizedStoreFormat("Note: this %@ address has transaction history but currently zero %@.", chainName, balanceLabel)
            : nil
        return (warning, info)
    }
}
