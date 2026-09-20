// Conversions from the Swift view models back into the core records, used by
// the bridge tests to seed state through the same commands the app issues.
//
// They live in the test target because nothing in the app converts in this
// direction: the app renders core's records, and core builds its own. Swift has
// no `#[cfg(test)]`, so the target boundary is the gate.
import Foundation

@testable import Spectra

extension WalletView {
    /// A wallet record with every field a test does not name defaulted. The
    /// app never builds one; core returns them.
    init(
        id: UUID = UUID(),
        name: String,
        selectedChainId: String? = nil,
        addresses: [String: String] = [:],
        bitcoinXpub: String? = nil,
        seedDerivationPreset: CoreSeedDerivationPreset = .standard,
        seedDerivationPaths: CoreSeedDerivationPaths? = nil,
        derivationOverrides: CoreWalletDerivationOverrides = CoreWalletDerivationOverrides(passphrase: nil, hmacKey: nil),
        selectedChain: String,
        holdings: [Coin] = [],
        includeInPortfolioTotal: Bool = true
    ) {
        self.init(
            id: id.uuidString, name: name,
            chainId: selectedChainId ?? Chain(displayName: selectedChain)?.id ?? "",
            addresses: Dictionary(
                addresses.compactMap { chainName, address in
                    Chain(displayName: chainName).map { ($0.addressSlot, address) }
                }, uniquingKeysWith: { first, _ in first }),
            bitcoinXpub: bitcoinXpub,
            seedDerivationPreset: seedDerivationPreset,
            seedDerivationPaths: seedDerivationPaths ?? .forPreset(seedDerivationPreset),
            derivationOverrides: derivationOverrides,
            selectedChain: selectedChain, holdings: holdings,
            includeInPortfolioTotal: includeInPortfolioTotal
        )
    }

    /// Set this wallet's address for a chain. Passing `nil` clears it.
    ///
    /// Spares the bridge tests rebuilding a 27-field record to change one
    /// field. The app never edits a wallet record in place — it renders what
    /// core sends and issues commands back.
    mutating func setAddress(_ address: String?, forChainNamed chainName: String) {
        let slot = Chain(displayName: chainName)?.addressSlot ?? ""
        guard !slot.isEmpty else { return }
        if let address, !address.isEmpty {
            addresses[slot] = address
        } else {
            addresses.removeValue(forKey: slot)
        }
    }

    /// The authoritative model this view model was rendered from, the same
    /// mapping as core's `WalletView::to_wallet_state`, for seeding a test
    /// through the command the app issues.
    ///
    /// `isWatchOnly` is a Keychain fact the record cannot carry, so the caller
    /// supplies it — see `WalletState` in `core/src/store/state.rs`.
    func walletState(isWatchOnly: Bool) -> WalletState {
        let chain = Chain(displayName: selectedChain)
        let path = Chain(id: chainId).map { seedDerivationPaths.path(for: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        // The wallet's own slot first: core reads the first receive address as
        // the primary one.
        let ownSlot = chain?.addressSlot
        let slots = addresses.keys.sorted { ($0 == ownSlot ? 0 : 1, $0) < ($1 == ownSlot ? 0 : 1, $1) }
        return WalletState(
            id: id, name: name, isWatchOnly: isWatchOnly, chainName: selectedChain,
            includeInPortfolioTotal: includeInPortfolioTotal, chainId: chainId, xpub: bitcoinXpub,
            derivationPreset: seedDerivationPreset, derivationPath: path, derivationOverrides: derivationOverrides,
            holdings: holdings,
            addresses: slots.compactMap { slot in
                guard let owner = Chain.all.first(where: { $0.addressSlot == slot }), let address = addresses[slot] else { return nil }
                let networkPath = seedDerivationPaths.path(for: owner)
                return WalletAddress(chainName: owner.displayName, address: address, kind: "receive", derivationPath: networkPath.isEmpty ? nil : networkPath)
            })
    }
}

extension TransactionRecord {
    /// A record with every field a test does not name left empty. The app never
    /// builds one — core records what was sent and fetched.
    init(
        id: String, walletId: String? = nil, deploymentId: String? = nil, kind: TransactionKind,
        status: TransactionStatus, walletName: String, assetDisplayName: String, symbol: String,
        chainName: String, amount: Double, address: String, transactionHash: String? = nil,
        nonce: Int64? = nil, failureReason: String? = nil
    ) {
        self.init(
            deploymentId: deploymentId, id: id, walletId: walletId, kind: kind, status: status,
            walletName: walletName, assetDisplayName: assetDisplayName, symbol: symbol,
            chainName: chainName, amount: amount, address: address, transactionHash: transactionHash,
            nonce: nonce, receiptBlockNumber: nil, receiptGasUsed: nil,
            receiptEffectiveGasPriceGwei: nil, receiptNetworkFee: nil, feePriorityRaw: nil,
            feeRateDescription: nil, confirmationCount: nil, confirmedNetworkFee: nil,
            estimatedFeeRatePerKb: nil, usedChangeOutput: nil, sourceDerivationPath: nil,
            changeDerivationPath: nil, sourceAddress: nil, changeAddress: nil,
            signedTransactionPayload: nil, signedTransactionPayloadFormat: nil,
            failureReason: failureReason, transactionHistorySource: nil,
            createdAt: Date().timeIntervalSinceReferenceDate)
    }
}

extension WalletImportDraft {
    /// Populate the seed phrase the way the UI does — the per-word entry grid
    /// *and* the joined string. Validation reads `seedPhraseEntries`, so
    /// setting `seedPhrase` alone leaves the draft looking incomplete.
    func setSeedPhraseForTesting(_ phrase: String) {
        let words = phrase.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        selectedSeedPhraseWordCount = words.count
        seedPhraseEntries = words
        seedPhrase = words.joined(separator: " ")
    }
}
