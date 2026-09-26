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
    /// app never builds one; core returns them. `addresses` is keyed by chain
    /// id and stored under that chain's slot, as core stores it.
    init(
        id: UUID = UUID(),
        name: String,
        chainId: String,
        addresses: [String: String] = [:],
        bitcoinXpub: String? = nil,
        seedDerivationPreset: CoreSeedDerivationPreset = .standard,
        seedDerivationPaths: CoreSeedDerivationPaths? = nil,
        derivationOverrides: CoreWalletDerivationOverrides = CoreWalletDerivationOverrides(passphrase: nil, hmacKey: nil),
        holdings: [Coin] = [],
        includeInPortfolioTotal: Bool = true,
        signing: WalletSigning = .watchOnly
    ) {
        self.init(
            id: id.uuidString, name: name, chainId: chainId,
            addresses: Dictionary(
                addresses.compactMap { chainId, address in
                    Chain(id: chainId).map { ($0.addressSlot, address) }
                }, uniquingKeysWith: { first, _ in first }),
            bitcoinXpub: bitcoinXpub,
            seedDerivationPreset: seedDerivationPreset,
            seedDerivationPaths: seedDerivationPaths ?? .forPreset(seedDerivationPreset),
            derivationOverrides: derivationOverrides,
            holdings: holdings,
            includeInPortfolioTotal: includeInPortfolioTotal,
            signing: signing
        )
    }

    /// Set this wallet's address on a chain. Passing `nil` clears it.
    ///
    /// Spares the bridge tests rebuilding the record to change one field. The
    /// app never edits a wallet record in place — it renders what core sends
    /// and issues commands back.
    mutating func setAddress(_ address: String?, on chain: Chain) {
        let slot = chain.addressSlot
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
    func walletState() -> WalletState {
        let path = chain.map { seedDerivationPaths.path(for: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        // The wallet's own slot first: core reads the first receive address as
        // the primary one.
        let ownSlot = family?.addressSlot
        let slots = addresses.keys.sorted { ($0 == ownSlot ? 0 : 1, $0) < ($1 == ownSlot ? 0 : 1, $1) }
        return WalletState(
            id: id, name: name, signing: signing, chainId: chainId,
            includeInPortfolioTotal: includeInPortfolioTotal, xpub: bitcoinXpub,
            derivationPreset: seedDerivationPreset, derivationPath: path, derivationOverrides: derivationOverrides,
            holdings: holdings,
            addresses: slots.compactMap { slot in
                guard let owner = Chain.all.first(where: { $0.addressSlot == slot }), let address = addresses[slot] else { return nil }
                let networkPath = seedDerivationPaths.path(for: owner)
                return WalletAddress(chainId: owner.id, address: address, kind: "receive", derivationPath: networkPath.isEmpty ? nil : networkPath)
            })
    }
}

extension TransactionRecord {
    /// A record with every field a test does not name left empty. The app never
    /// builds one — core records what was sent and fetched.
    init(
        id: String, walletId: String? = nil, deploymentId: String? = nil, kind: CoreTransactionKind,
        status: TransactionStatus, walletName: String, assetDisplayName: String, symbol: String,
        chainId: String, amount: String, address: String, transactionHash: String? = nil,
        nonce: Int64? = nil, failureReason: TransactionFailure? = nil
    ) {
        self.init(
            actions: TransactionActions(recheckUnavailableReason: "Not evaluated", rebroadcastUnavailableReason: "Not evaluated"),
            deploymentId: deploymentId, id: id, walletId: walletId, kind: kind, status: status,
            walletName: walletName, assetDisplayName: assetDisplayName, symbol: symbol,
            chainId: chainId, amount: amount, address: address, transactionHash: transactionHash,
            nonce: nonce, receiptBlockNumber: nil, receiptGasUsed: nil,
            receiptEffectiveGasPriceGwei: nil, receiptNetworkFee: nil,
            feeRateDescription: nil, confirmationCount: nil, confirmedNetworkFee: nil,
            estimatedFeeRatePerKb: nil, usedChangeOutput: nil, sourceDerivationPath: nil,
            changeDerivationPath: nil, sourceAddress: nil, changeAddress: nil,
            signedTransactionPayload: nil, signedTransactionPayloadFormat: nil,
            failureReason: failureReason, transactionHistorySource: nil,
            createdAtUnix: Date().timeIntervalSince1970)
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

extension AssetHolding {
    /// A holding as core would project it. The id follows core's
    /// `deployment_id` for the EVM-style contracts these tests use.
    static func fixture(
        name: String, symbol: String, coingeckoId: String = "", chainId: String, tokenStandard: String = "Native",
        contractAddress: String? = nil, amount: String
    ) -> Coin {
        let id = contractAddress.map { "\(chainId):\(tokenStandard.lowercased()):\($0.lowercased())" } ?? "\(chainId):native"
        return AssetHolding(
            id: id, name: name, symbol: symbol, coingeckoId: coingeckoId, chainId: chainId,
            tokenStandard: tokenStandard, contractAddress: contractAddress, amount: amount)
    }
}

@MainActor
extension AppState {
    /// Wait until every command sent so far has come back and been applied.
    ///
    /// Mirrors settle a runloop hop after the assignment that sends them, which
    /// is fine for a UI and awkward for a test asserting the effect. Tests
    /// await this rather than each deriving the rule locally.
    func awaitPendingCoreStateWrites() async {
        await awaitPendingStateCommands()
        await rebuildWalletDerivedStateFromCore()
    }
}

@MainActor
extension WalletDiagnosticsState {
    func flushPendingPersistence() async { await pendingCommand?.value }
}
