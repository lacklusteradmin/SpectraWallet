import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
/// `FeePriority` is core's enum. Which values exist, how they are stored, and
/// that anything else reads as `normal` are core's rules; this adds the wording
/// and the iteration order a picker needs.
///
/// Was a second enum declared here, with its own raw strings, while core's
/// setting held a free string — so "which priorities exist" had two answers and
/// the typed one was the app's.
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
struct SendPreviewDetails: Equatable {
    let spendableBalance: Double?
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double?
    var hasVisibleContent: Bool {
        spendableBalance != nil
            || feeRateDescription != nil
            || estimatedTransactionBytes != nil
            || selectedInputCount != nil
            || usesChangeOutput != nil
            || maxSendable != nil
    }
}
/// `Coin` is the Rust-defined `AssetHolding`. Chain identity is the
/// `(chainName, tokenStandard, contractAddress)` triple — use the
/// core `holdingIdentity` helper rather than parsing strings ad-hoc.
typealias Coin = AssetHolding
extension AssetHolding: Identifiable {
    /// The list key, from what identifies the holding. Was a stored field each
    /// producer filled its own way — one of them with a fresh `UUID`, which
    /// makes SwiftUI treat every row as new on each rebuild.
    public var id: String { holdingIdentity(holding: self) }
    var color: Color { Coin.displayColor(for: symbol) }
    static func makeCustom(
        name: String, symbol: String, coinGeckoId: String, chainName: String, tokenStandard: String,
        contractAddress: String?, amount: Double, priceUsd: Double
    ) -> Coin {
        AssetHolding(
            name: name, symbol: symbol, coinGeckoId: coinGeckoId, chainName: chainName,
            tokenStandard: tokenStandard, contractAddress: contractAddress, amount: amount, priceUsd: priceUsd)
    }
    var holdingKey: String { id }
    var chain: Chain? { Chain(displayName: chainName) }
    var isUTXOChain: Bool { chain?.supportsDeepUTXODiscovery ?? false }
    var isEVMChain: Bool { chain?.isEVM ?? false }
    /// A holding is the chain's own asset when its symbol is the one fees are
    /// paid in — `ETH` on Arbitrum, not `ARB`.
    var isNativeCoin: Bool {
        tokenStandard == "Native" && (contractAddress?.isEmpty ?? true)
    }
}
extension WalletView: Identifiable {}
extension WalletView {
    /// This wallet's address for a chain, by display name. Slot resolution
    /// (including "every EVM chain shares Ethereum's") lives in the Rust
    /// registry, so this never needs to know which chains exist.
    func address(forChainNamed chainName: String) -> String? {
        let slot = Chain(displayName: chainName)?.addressSlot ?? ""
        guard !slot.isEmpty else { return nil }
        return addresses[slot]
    }
}

/// Watch-only entries keyed by storage slot, the shape core's import reads.
///
/// Slots come from the registry via `Chain.addressSlot`, so the UI never
/// hardcodes a key. Chains that share a slot — the EVM family — have their
/// lists concatenated rather than overwriting each other; a chain the registry
/// does not know is dropped.
func addressSlotMap(_ byChainName: [String: [String]]) -> [String: [String]] {
    var bySlot: [String: [String]] = [:]
    for (chainName, addresses) in byChainName where !addresses.isEmpty {
        guard let slot = Chain(displayName: chainName)?.addressSlot, !slot.isEmpty else { continue }
        bySlot[slot, default: []].append(contentsOf: addresses)
    }
    return bySlot
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

    /// A preset's paths, straight from the Rust chain catalog.
    ///
    /// There is deliberately no hardcoded Swift fallback table. The one that
    /// used to live here restated all 44 paths from `chains.toml` and would
    /// have drifted silently; an empty map instead surfaces a broken catalog
    /// as a visibly missing path rather than a plausible wrong one.
    static func forPreset(_ preset: CoreSeedDerivationPreset) -> CoreSeedDerivationPaths {
        (try? appCoreDerivationPathsForPreset(preset: preset))
            ?? CoreSeedDerivationPaths(isCustomEnabled: false, byChain: [:])
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
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case sends = "Sends"
    case receives = "Receives"
    case pending = "Pending"
    var id: String { rawValue }
    var localizedTitle: String { AppLocalization.string(rawValue) }
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
    init(
        holdingKey: String, assetDisplayName: String, symbol: String, chainName: String, targetPrice: Double,
        condition: PriceAlertCondition
    ) {
        self.init(
            id: UUID().uuidString, holdingKey: holdingKey, assetDisplayName: assetDisplayName, symbol: symbol,
            chainName: chainName, targetPrice: targetPrice, condition: condition, isEnabled: true,
            hasTriggered: false
        )
    }
    var titleText: String { String(format: CommonLocalizationContent.current.assetOnChainFormat, assetDisplayName, chainName) }
    var statusText: String {
        if !isEnabled { return AppLocalization.string("Paused") }
        return hasTriggered ? AppLocalization.string("Triggered") : AppLocalization.string("Watching")
    }
}
// `AddressBookEntry` is the Rust record — core owns saved recipients, including
// the rules about which ones are acceptable. Only display helpers live here.
extension AddressBookEntry: Identifiable {
    var subtitleText: String {
        guard !note.isEmpty else { return chainName }
        return String(format: CommonLocalizationContent.current.addressBookSubtitleFormat, chainName, note)
    }
}
/// A stored transaction, as core keeps it.
///
/// A typealias, like `Coin`. This was a 35-field Swift struct copying core's
/// record field by field, with an initializer that copied it again and
/// integer widths converted on the way; three chain-named fields came across
/// with it.
typealias TransactionRecord = CorePersistedTransactionRecord

extension CorePersistedTransactionRecord: Identifiable {}

extension TransactionRecord {
    /// History with no deployment identity draws its letter.
    var artworkName: String { coreDeploymentArtworkName(deploymentId: deploymentId) }
    /// When it was recorded. Core stores Swift reference seconds.
    var createdDate: Date { Date(timeIntervalSinceReferenceDate: createdAt) }
    var titleText: String {
        let copy = CommonLocalizationContent.current
        switch kind {
        case .send: return String(format: copy.transactionSentTitleFormat, symbol)
        case .receive: return String(format: copy.transactionReceivedTitleFormat, symbol)
        }
    }
    /// "Solana • Main Wallet", or "USD Coin on Solana • Main Wallet" when the
    /// asset is not the network's own. The chain was always named, so every
    /// native asset read "Solana on Solana" — its display name is its chain's
    /// — and the line wrapped, costing a third row of type to say one word
    /// twice.
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
    var storedFeePriorityText: String? {
        if let feePriorityRaw {
            let trimmed = feePriorityRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.capitalized }
        }
        return nil
    }
    var storedConfirmationCountText: String? {
        if let confirmationCount { return "\(confirmationCount) conf" }
        return nil
    }
    var storedUsedChangeOutputText: String? {
        if let usedChangeOutput { return usedChangeOutput ? "Yes" : "No" }
        return nil
    }
    var rawTransactionHexText: String? {
        guard let signedTransactionPayload, let signedTransactionPayloadFormat else { return nil }
        guard signedTransactionPayloadFormat.lowercased().contains("hex") else { return nil }
        let trimmed = signedTransactionPayload.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return AppEndpointDirectory.transactionExplorerURL(for: chainName, transactionHash: transactionHash)
    }
    var transactionExplorerLabel: String? {
        guard transactionHash != nil else { return nil }
        return AppEndpointDirectory.transactionExplorerLabel(for: chainName)
    }
    var rebroadcastPayload: String? {
        if let signedTransactionPayload {
            let trimmed = signedTransactionPayload.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
    var rebroadcastPayloadFormat: String? {
        if let signedTransactionPayloadFormat {
            let trimmed = signedTransactionPayloadFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
    var supportsSignedRebroadcast: Bool { kind == .send && rebroadcastPayload != nil && rebroadcastPayloadFormat != nil }

    /// The failure reason to show, localized.
    ///
    /// Core stores a code. A localized sentence written into the database
    /// keeps its language when the user changes theirs, so the text is made
    /// here and the record keeps the code.
    var localizedFailureReason: String? {
        guard let failureReason else { return nil }
        switch failureReason {
        case "stuckAfterRetries":
            return AppLocalization.format(
                "%@ transaction appears stuck and could not be confirmed after extended retries.",
                chainName)
        default:
            return failureReason
        }
    }

    /// Whether this transaction's status can be rechecked against the chain.
    ///
    /// The rule is `Chain::pending_status_poll`: the chain is polled
    /// UTXO-style, and either it does not require a send or this is one.
    /// Litecoin is `require_send_kind: false` because its explorer confirms
    /// receives on its own cadence.
    var supportsStatusRecheck: Bool {
        guard transactionHash != nil,
            let chain = Chain(displayName: chainName),
            case .utxo(_, let requireSendKind) = chain.pendingStatusPoll
        else { return false }
        return !requireSendKind || kind == .send
    }
}
