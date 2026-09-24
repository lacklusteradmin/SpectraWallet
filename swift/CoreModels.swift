import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
/// Picker wording and iteration order for core's `FeePriority` enum.
extension FeePriority: CaseIterable {
    public static var allCases: [FeePriority] { [.economy, .normal, .priority] }
    var displayName: String {
        switch self {
        case .economy: return AppLocalization.string("Economy")
        case .normal: return AppLocalization.string("Normal")
        case .priority: return AppLocalization.string("Priority")
        }
    }
}
extension SendPreviewDetails {
    var hasVisibleContent: Bool {
        spendableBalance != nil
            || feeRateDescription != nil
            || estimatedTransactionBytes != nil
            || selectedInputCount != nil
            || usesChangeOutput != nil
            || maxSendable != nil
    }
}
/// `Coin` is the Rust-defined `AssetHolding`. Its `id` is the deployment id
/// core derives; every projection this app reads carries it.
typealias Coin = AssetHolding
extension AssetHolding: Identifiable {
    var color: Color { AssetPresentationCatalog.color(deploymentId: id) }
    var holdingKey: String { id }
    var chain: Chain? { Chain(id: chainId) }
    /// For text a person reads; identity is `chainId`.
    var chainName: String { Chain.displayName(forId: chainId) }
    var isUTXOChain: Bool { chain?.supportsDeepUTXODiscovery ?? false }
    var isEVMChain: Bool { chain?.isEVM ?? false }
    /// The chain's own asset — `ETH` on Arbitrum, not `ARB` — by deployment
    /// identity, which the catalog names for each chain.
    var isNativeCoin: Bool { chain?.entry?.nativeDeploymentId == id }
    /// Whether anything is held. Core stores amounts in canonical spelling,
    /// so zero is always `"0"`.
    var hasBalance: Bool { amount != "0" }
}
extension AssetWikiPlace {
    var chainName: String { Chain.displayName(forId: chainId) }
}
extension FundsFinderCandidate {
    var chainName: String { Chain.displayName(forId: chainId) }
}
extension DiagnosticLogInput {
    var chainName: String? { chainId.map(Chain.displayName(forId:)) }
}
extension WalletView: Identifiable {}
extension WalletView {
    /// This wallet's address on a chain. Slot resolution (including "every
    /// EVM chain shares Ethereum's") lives in the Rust registry.
    func address(on chain: Chain) -> String? {
        let slot = chain.addressSlot
        guard !slot.isEmpty else { return nil }
        return addresses[slot]
    }
    /// The network this wallet is on.
    var chain: Chain? { Chain(id: chainId) }
    /// The mainnet whose family this wallet belongs to.
    var family: Chain? { chain?.mainnetCounterpart }
    /// The family's name, for text a person reads.
    var familyName: String { family?.displayName ?? chainId }
}

typealias SeedDerivationPaths = CoreSeedDerivationPaths
extension CoreSeedDerivationPaths {
    /// Storage key for a chain. Testnets share their mainnet counterpart's
    /// slot — the derivation recipe is identical and only the address encoding
    /// differs — and the registry decides which is which.
    private static func storageKey(for chain: Chain) -> String {
        chain.seedDerivationPathKey
    }

    /// Configured derivation path for a chain, or `""` when the chain has no
    /// BIP-32 path (Monero) or is not in the catalog.
    func path(for chain: Chain) -> String {
        byChain[Self.storageKey(for: chain)] ?? ""
    }

    mutating func setPath(_ path: String, for chain: Chain) {
        let key = Self.storageKey(for: chain)
        guard !key.isEmpty else { return }
        byChain[key] = path
    }

    static var defaults: CoreSeedDerivationPaths { forPreset(.standard) }

    /// Preset paths from the Rust catalog. No fallback table: an empty map
    /// surfaces a missing catalog path rather than substituting a guessed one.
    static func forPreset(_ preset: CoreSeedDerivationPreset) -> CoreSeedDerivationPaths {
        (try? derivationPathsForPreset(preset: preset))
            ?? CoreSeedDerivationPaths(byChain: [:])
    }
}
extension TransactionStatus {
    var localizedTitle: String {
        switch self {
        case .pending: return AppLocalization.string("Pending")
        case .confirmed: return AppLocalization.string("Confirmed")
        case .failed: return AppLocalization.string("Failed")
        }
    }
}
/// Picker order and wording for core's history filter.
extension HistoryQueryFilter: CaseIterable, Identifiable {
    public static var allCases: [HistoryQueryFilter] { [.all, .send, .receive, .pending] }
    public var id: Self { self }
    var localizedTitle: String {
        switch self {
        case .all: return AppLocalization.string("All")
        case .send: return AppLocalization.string("Sends")
        case .receive: return AppLocalization.string("Receives")
        case .pending: return AppLocalization.string("Pending")
        }
    }
}
enum HistorySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    var id: String { rawValue }
    var localizedTitle: String { AppLocalization.string(rawValue) }
}
extension PriceAlertCondition {
    var displayName: String {
        switch self {
        case .above: return AppLocalization.string("Above")
        case .below: return AppLocalization.string("Below")
        }
    }
}
/// The alert rule core stores. Not a Swift copy of it — core owns the list,
/// the rule that a target must be positive, and the persistence.
typealias PriceAlertRule = PriceAlertEvaluationAlert

/// `id` is an opaque core-assigned string, not a platform-minted `UUID`.
extension PriceAlertRule: Identifiable {}

extension PriceAlertRule {
    var chainName: String { Chain.displayName(forId: chainId) }
    var titleText: String { String(format: CommonLocalizationContent.current.assetOnChainFormat, assetDisplayName, chainName) }
    var statusText: String {
        if !isEnabled { return AppLocalization.string("Paused") }
        return hasTriggered ? AppLocalization.string("Triggered") : AppLocalization.string("Watching")
    }
}
// `AddressBookEntry` is the Rust record — core owns saved recipients, including
// the rules about which ones are acceptable. Only display helpers live here.
extension AddressBookEntry: Identifiable {
    var chainName: String { Chain.displayName(forId: chainId) }
    var subtitleText: String {
        guard !note.isEmpty else { return chainName }
        return String(format: CommonLocalizationContent.current.addressBookSubtitleFormat, chainName, note)
    }
}
/// A stored transaction, as core keeps it.
typealias TransactionRecord = CorePersistedTransactionRecord

extension CorePersistedTransactionRecord: Identifiable {}

extension TransactionRecord {
    /// History with no deployment identity draws its letter.
    var artworkName: String { AssetPresentationCatalog.artwork(deploymentId: deploymentId) }
    var chain: Chain? { Chain(id: chainId) }
    var chainName: String { Chain.displayName(forId: chainId) }
    /// When it was recorded. Core stores Unix seconds.
    var createdDate: Date { Date(timeIntervalSince1970: createdAtUnix) }
    var titleText: String {
        let copy = CommonLocalizationContent.current
        switch kind {
        case .send: return String(format: copy.transactionSentTitleFormat, symbol)
        case .receive: return String(format: copy.transactionReceivedTitleFormat, symbol)
        }
    }
    /// Name the network and wallet, prefixing the asset name for token transfers.
    var subtitleText: String {
        let copy = CommonLocalizationContent.current
        let asset =
            assetDisplayName.caseInsensitiveCompare(chainName) == .orderedSame
            ? assetDisplayName : String(format: copy.assetOnChainFormat, assetDisplayName, chainName)
        return String(format: copy.transactionSubtitleFormat, asset, walletName)
    }
    var statusText: String { status.localizedTitle }
    var badgeMark: String {
        switch kind {
        case .send: return "OUT"
        case .receive: return "IN"
        }
    }
    var badgeColor: Color {
        switch kind {
        case .send: return .red
        case .receive: return .green
        }
    }
    var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .confirmed: return .mint
        case .failed: return .red
        }
    }
    var receiptBlockNumberText: String? {
        guard let receiptBlockNumber else { return nil }
        return String(receiptBlockNumber)
    }
    var storedConfirmationCountText: String? {
        guard let confirmationCount else { return nil }
        return AppLocalization.format("%lld confirmations", confirmationCount)
    }
    var storedUsedChangeOutputText: String? {
        guard let usedChangeOutput else { return nil }
        return AppLocalization.string(usedChangeOutput ? "Yes" : "No")
    }
    /// The signed payload as stored, whatever its encoding; the format row
    /// beside it says which.
    var rawTransactionText: String? {
        let trimmed = signedTransactionPayload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
    var rawTransactionFormatText: String? {
        guard let signedTransactionPayloadFormat else { return nil }
        let trimmed = signedTransactionPayloadFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    var fullTimestampText: String { createdDate.formatted(date: .abbreviated, time: .standard) }
    var transactionExplorerURL: URL? {
        guard let transactionHash, !transactionHash.isEmpty else { return nil }
        return AppEndpointDirectory.transactionExplorerURL(for: chainId, transactionHash: transactionHash)
    }
    var transactionExplorerLabel: String? {
        guard transactionHash != nil else { return nil }
        return AppEndpointDirectory.transactionExplorerLabel(for: chainId)
    }
    /// The failure reason to show, localized. Core stores the reason; the
    /// words are made here so they follow the reader's language.
    var localizedFailureReason: String? {
        guard let failureReason else { return nil }
        switch failureReason {
        case .stuckAfterRetries:
            return AppLocalization.format(
                "%@ transaction appears stuck and could not be confirmed after extended retries.",
                chainName)
        case .submissionOutcomeUnknown:
            return AppLocalization.string("Submission outcome unknown; check network status before sending again.")
        case .rebroadcastOutcomeUnknown:
            return AppLocalization.string("Rebroadcast outcome unknown; check network status before retrying.")
        case .reported(let message):
            return message
        }
    }
}

extension WalletView {
    var networkTitle: String { Chain.displayName(forId: chainId) }
}
