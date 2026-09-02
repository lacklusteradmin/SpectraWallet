import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
enum ChainFeePriorityOption: String, CaseIterable, Codable, Identifiable {
    case economy
    case normal
    case priority
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .economy: return "Economy"
        case .normal: return "Normal"
        case .priority: return "Priority"
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
/// existing `assetIdentityKey` / `Coin.normalizedIconIdentifier` helpers
/// rather than parsing the strings ad-hoc.
typealias Coin = AssetHolding
extension AssetHolding: Identifiable {
    /// The list key, from what identifies the holding. Was a stored field each
    /// producer filled its own way — one of them with a fresh `UUID`, which
    /// makes SwiftUI treat every row as new on each rebuild.
    public var id: String { holdingIdentity(holding: self) }
    var color: Color { Coin.displayColor(for: symbol) }
    var valueUSD: Double { amount * priceUsd }
    static func makeCustom(
        name: String, symbol: String, coinGeckoId: String, chainName: String, tokenStandard: String,
        contractAddress: String?, amount: Double, priceUsd: Double
    ) -> Coin {
        AssetHolding(
            name: name, symbol: symbol, coinGeckoId: coinGeckoId, chainName: chainName,
            tokenStandard: tokenStandard, contractAddress: contractAddress, amount: amount, priceUsd: priceUsd)
    }
    var hasVisibleBalance: Bool { amount > 0 }
    var holdingKey: String { "\(chainName)|\(symbol)" }
    var accentMarks: [String] {
        switch symbol {
        case "BTC": return ["L1", "S", "P"]
        case "LTC": return ["L1", "S", "F"]
        case "ETH": return ["SC", "VM", "D"]
        case "SOL": return ["F", "RT", "+"]
        case "MATIC": return ["L2", "ZK", "G"]
        case "AVAX": return ["C", "X", "S"]
        case "HYPE": return ["L1", "DEX", "P"]
        case "ARB": return ["L2", "OP", "A"]
        case "BNB": return ["B", "DEX", "+"]
        case "DOGE": return ["M", "P2P", "+"]
        case "ADA": return ["POS", "SC", "L1"]
        case "TRX": return ["TVM", "NET", "+"]
        case "XMR": return ["PRV", "POW", "S"]
        case "SUI": return ["OBJ", "MOVE", "ZK"]
        case "APT": return ["MOVE", "ACC", "L1"]
        case "ICP": return ["NS", "LED", "L1"]
        case "NEAR": return ["SHD", "ACC", "POS"]
        default: return ["+", "+", "+"]
        }
    }
    var chain: Chain? { Chain(displayName: chainName) }
    var isUTXOChain: Bool { chain?.supportsDeepUTXODiscovery ?? false }
    var isEVMChain: Bool { chain?.isEVM ?? false }
    /// A holding is the chain's own asset when its symbol is the one fees are
    /// paid in — `ETH` on Arbitrum, not `ARB`.
    var isNativeCoin: Bool {
        guard let chain else { return false }
        return symbol == chain.gasTokenSymbol
    }
}
typealias ImportedWallet = CoreImportedWallet
extension CoreImportedWallet: Identifiable {}
extension CoreImportedWallet {
    var totalBalance: Double { holdings.reduce(0) { $0 + $1.valueUSD } }

    /// This wallet's address for a chain, by display name. Slot resolution
    /// (including "every EVM chain shares Ethereum's") lives in the Rust
    /// registry, so this never needs to know which chains exist.
    func address(forChainNamed chainName: String) -> String? {
        let slot = Chain(displayName: chainName)?.addressSlot ?? ""
        guard !slot.isEmpty else { return nil }
        return addresses[slot]
    }

    /// The address for the wallet's own chain.
    var primaryAddress: String? { address(forChainNamed: selectedChain) }

    /// Set this wallet's address for a chain. Passing `nil` clears it.
    ///
    /// Replaces the "rebuild the whole record to change one field" pattern the
    /// 27-field version forced on every caller.
    mutating func setAddress(_ address: String?, forChainNamed chainName: String) {
        let slot = Chain(displayName: chainName)?.addressSlot ?? ""
        guard !slot.isEmpty else { return }
        if let address, !address.isEmpty {
            addresses[slot] = address
        } else {
            addresses.removeValue(forKey: slot)
        }
    }


    // MARK: The five chains read by name
    //
    // Twenty-four of these existed, "so the ~150 existing
    // `wallet.<chain>Address` call sites keep working" — and this document
    // declined to remove them on that trade, because rewriting 150 readable
    // reads into `address(forChainNamed:)` improves a metric and not the code.
    //
    // What changed is that most of those call sites were not reads. They were
    // switches *picking between* the shims by chain name — in the receive view,
    // the receive flow, `knownUTXOAddresses`, `knownOwnedAddresses`, the wallet
    // detail row and the address-resolution descriptor table — and every one of
    // them is `address(forChainNamed:)` with the name it already had. Those are
    // gone, and with them nineteen shims that had no reader left.
    //
    // These five remain because something genuinely reads them for that chain:
    // Bitcoin falls back to its account xpub, Dogecoin has a watch address,
    // Ethereum backs the EVM family, and Cardano and Monero prefer a stored
    // address to a derived one.
    var bitcoinAddress: String? { address(forChainNamed: "Bitcoin") }
    var dogecoinAddress: String? { address(forChainNamed: "Dogecoin") }
    var ethereumAddress: String? { address(forChainNamed: "Ethereum") }
    var moneroAddress: String? { address(forChainNamed: "Monero") }
    var cardanoAddress: String? { address(forChainNamed: "Cardano") }

    /// The authoritative model this view model was rendered from.
    ///
    /// `isWatchOnly` is a Keychain fact the record cannot carry, so the caller
    /// supplies it — see `WalletSummary` in `core/src/store/state.rs`.
    func summary(isWatchOnly: Bool) -> WalletSummary {
        coreWalletSummary(wallet: self, isWatchOnly: isWatchOnly)
    }

    /// Convenience initializer that defaults every field a caller doesn't set.
    ///
    /// `CoreImportedWallet` is a UniFFI record, so its generated memberwise
    /// init has no defaults.
    init(
        id: UUID = UUID(),
        name: String,
        networkChainID: String? = nil,
        addresses: [String: String?] = [:],
        bitcoinXpub: String? = nil,
        seedDerivationPreset: CoreSeedDerivationPreset = .standard,
        seedDerivationPaths: CoreSeedDerivationPaths? = nil,
        derivationOverrides: CoreWalletDerivationOverrides = .empty,
        selectedChain: String,
        holdings: [Coin] = [],
        includeInPortfolioTotal: Bool = true
    ) {
        self.init(
            id: id.uuidString, name: name, networkChainId: networkChainID,
            addresses: addressSlotMap(addresses),
            bitcoinXpub: bitcoinXpub,
            seedDerivationPreset: seedDerivationPreset,
            seedDerivationPaths: seedDerivationPaths ?? .applyingPreset(seedDerivationPreset),
            derivationOverrides: derivationOverrides,
            selectedChain: selectedChain, holdings: holdings,
            includeInPortfolioTotal: includeInPortfolioTotal
        )
    }

}

extension CoreWalletDerivationOverrides {
    /// All-nil overrides — "use the chain's defaults".
    static var empty: CoreWalletDerivationOverrides {
        CoreWalletDerivationOverrides(
            passphrase: nil, mnemonicWordlist: nil, iterationCount: nil, saltPrefix: nil, hmacKey: nil,
            curve: nil, derivationAlgorithm: nil, addressAlgorithm: nil, publicKeyFormat: nil, scriptType: nil
        )
    }
}

// MARK: - Wallet import address slots
//
// `WalletImportAddresses` and `WalletImportWatchOnlyEntries` are keyed by
// storage slot rather than carrying one field per chain. Slots come from the
// Rust registry via `Chain.addressSlot`, so the UI never hardcodes a key and
// never has to know that every EVM chain shares Ethereum's slot.

/// The storage slot a chain's address is kept under, or nil if the registry
/// does not know the chain.
private func addressSlot(forChainNamed chainName: String) -> String? {
    let slot = Chain(displayName: chainName)?.addressSlot ?? ""
    return slot.isEmpty ? nil : slot
}

/// Fold a chain-display-name → address table into the slot-keyed storage,
/// dropping empty values and chains the registry does not know.
func addressSlotMap(_ byChainName: [String: String?]) -> [String: String] {
    var bySlot: [String: String] = [:]
    for (chainName, address) in byChainName {
        guard let address, !address.isEmpty, let slot = addressSlot(forChainNamed: chainName) else {
            continue
        }
        bySlot[slot] = address
    }
    return bySlot
}

/// The list-valued variant. Chains that share a slot — the EVM family — have
/// their lists concatenated rather than overwriting each other, which is the
/// one thing that keeps this from being the same function.
func addressSlotMap(_ byChainName: [String: [String]]) -> [String: [String]] {
    var bySlot: [String: [String]] = [:]
    for (chainName, addresses) in byChainName where !addresses.isEmpty {
        guard let slot = addressSlot(forChainNamed: chainName) else { continue }
        bySlot[slot, default: []].append(contentsOf: addresses)
    }
    return bySlot
}

extension WalletImportAddresses {
    /// The address stored for a chain, by display name.
    func address(for chainName: String) -> String? {
        addressSlot(forChainNamed: chainName).flatMap { bySlot[$0] }
    }
}

extension WalletImportWatchOnlyEntries {
    /// Addresses entered for a chain, by display name.
    func addresses(for chainName: String) -> [String] {
        addressSlot(forChainNamed: chainName).flatMap { bySlot[$0] } ?? []
    }
}
typealias SeedDerivationPreset = CoreSeedDerivationPreset
extension CoreSeedDerivationPreset: RawRepresentable, CaseIterable, Codable, Identifiable {
    public typealias RawValue = String
    public init?(rawValue: String) {
        switch rawValue {
        case "standard": self = .standard
        case "account1": self = .account1
        case "account2": self = .account2
        default: return nil
        }
    }
    public var rawValue: String {
        switch self {
        case .standard: return "standard"
        case .account1: return "account1"
        case .account2: return "account2"
        }
    }
    public static let allCases: [CoreSeedDerivationPreset] = [.standard, .account1, .account2]
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let v = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid SeedDerivationPreset: \(raw)")
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .account1: return "Account 1"
        case .account2: return "Account 2"
        }
    }
    public var detail: String {
        switch self {
        case .standard: return "Use account 0 default paths."
        case .account1: return "Use account 1 paths for all supported chains."
        case .account2: return "Use account 2 paths for all supported chains."
        }
    }
    public var accountIndex: UInt32 {
        switch self {
        case .standard: return 0
        case .account1: return 1
        case .account2: return 2
        }
    }
}
enum SeedDerivationFlavor: String, Equatable {
    case standard
    case legacy
    case nestedSegWit
    case nativeSegWit
    case taproot
    case electrumLegacy
}
struct SeedDerivationResolution: Equatable {
    let chain: Chain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: SeedDerivationFlavor
}
extension Chain {
    func resolve(path rawPath: String) -> SeedDerivationResolution {
        do {
            let raw = try appCoreResolveDerivationPath(
                chain: displayName, derivationPath: rawPath)
            return SeedDerivationResolution(
                chain: Chain(displayName: raw.chain) ?? self,
                normalizedPath: raw.normalizedPath,
                accountIndex: raw.accountIndex,
                flavor: SeedDerivationFlavor(rawValue: raw.flavor) ?? .standard
            )
        } catch {
            fatalError(
                "Rust derivation path resolution failed for \(displayName): "
                    + error.localizedDescription)
        }
    }
}
typealias SeedDerivationPaths = CoreSeedDerivationPaths
extension CoreSeedDerivationPaths {
    /// Storage key for a chain. Testnets share their mainnet counterpart's
    /// slot — the derivation recipe is identical and only the address encoding
    /// differs — and the registry decides which is which.
    private static func storageKey(for chain: Chain) -> String {
        CachedCoreHelpers.seedDerivationPathKey(chainName: chain.displayName)
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

    static var defaults: CoreSeedDerivationPaths { migrated(from: nil) }

    /// Defaults for a preset's account index, straight from the Rust chain
    /// catalog.
    ///
    /// There is deliberately no hardcoded Swift fallback table. The one that
    /// used to live here restated all 44 paths from `chains.toml` and would
    /// have drifted silently; an empty map instead surfaces a broken catalog
    /// as a visibly missing path rather than a plausible wrong one.
    static func migrated(from preset: SeedDerivationPreset?) -> CoreSeedDerivationPaths {
        (try? appCoreDerivationPathsForPreset(accountIndex: preset?.accountIndex ?? 0))
            ?? CoreSeedDerivationPaths(isCustomEnabled: false, byChain: [:])
    }

    static func applyingPreset(_ preset: SeedDerivationPreset, keepCustomEnabled: Bool = false) -> CoreSeedDerivationPaths {
        var paths = migrated(from: preset)
        paths.isCustomEnabled = keepCustomEnabled
        return paths
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
struct NormalizedHistoryEntry: Identifiable {
    let id: String
    let transactionID: UUID
    let dedupeKey: String
    let createdAt: Date
    let kind: TransactionKind
    let status: TransactionStatus
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let address: String
    let transactionHash: String?
    let sourceTag: String
    let providerCount: Int
    let searchIndex: String
}
extension PriceAlertCondition {
    var displayName: String { AppLocalization.string(rawValue) }
}
/// The alert rule core stores. Not a Swift copy of it — core owns the list,
/// the rule that a target must be positive, and the persistence.
typealias PriceAlertRule = PriceAlertEvaluationAlert

/// `id` is an opaque core-assigned string, not a platform-minted `UUID`.
extension PriceAlertRule: Identifiable {}

extension PriceAlertRule {
    init(
        holdingKey: String, assetName: String, symbol: String, chainName: String, targetPrice: Double,
        condition: PriceAlertCondition
    ) {
        self.init(
            id: UUID().uuidString, holdingKey: holdingKey, assetName: assetName, symbol: symbol,
            chainName: chainName, targetPrice: targetPrice, condition: condition, isEnabled: true,
            hasTriggered: false
        )
    }
    var titleText: String { String(format: CommonLocalizationContent.current.priceAlertTitleFormat, assetName, chainName) }
    var conditionText: String { "\(condition.rawValue) $\(String(format: "%.2f", targetPrice))" }
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
struct TransactionRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let walletID: String?
    let kind: TransactionKind
    let status: TransactionStatus
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let amount: Double
    let address: String
    let transactionHash: String?
    let ethereumNonce: Int?
    let receiptBlockNumber: Int?
    let receiptGasUsed: String?
    let receiptEffectiveGasPriceGwei: Double?
    let receiptNetworkFeeEth: Double?
    let feePriorityRaw: String?
    let feeRateDescription: String?
    let confirmationCount: Int?
    let dogecoinConfirmedNetworkFeeDoge: Double?
    let dogecoinEstimatedFeeRateDogePerKb: Double?
    let usedChangeOutput: Bool?
    let sourceDerivationPath: String?
    let changeDerivationPath: String?
    let sourceAddress: String?
    let changeAddress: String?
    let signedTransactionPayload: String?
    let signedTransactionPayloadFormat: String?
    let failureReason: String?
    let transactionHistorySource: String?
    let createdAt: Date
    nonisolated init(
        id: UUID = UUID(), walletID: String? = nil, kind: TransactionKind, status: TransactionStatus, walletName: String, assetName: String,
        symbol: String, chainName: String, amount: Double, address: String, transactionHash: String? = nil, ethereumNonce: Int? = nil,
        receiptBlockNumber: Int? = nil, receiptGasUsed: String? = nil, receiptEffectiveGasPriceGwei: Double? = nil,
        receiptNetworkFeeEth: Double? = nil, feePriorityRaw: String? = nil, feeRateDescription: String? = nil,
        confirmationCount: Int? = nil, dogecoinConfirmedNetworkFeeDoge: Double? = nil,
        dogecoinEstimatedFeeRateDogePerKb: Double? = nil, usedChangeOutput: Bool? = nil,
        sourceDerivationPath: String? = nil, changeDerivationPath: String? = nil,
        sourceAddress: String? = nil, changeAddress: String? = nil,
        signedTransactionPayload: String? = nil, signedTransactionPayloadFormat: String? = nil, failureReason: String? = nil,
        transactionHistorySource: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.walletID = walletID
        self.kind = kind
        self.status = status
        self.walletName = walletName
        self.assetName = assetName
        self.symbol = symbol
        self.chainName = chainName
        self.amount = amount
        self.address = address
        self.transactionHash = transactionHash
        self.ethereumNonce = ethereumNonce
        self.receiptBlockNumber = receiptBlockNumber
        self.receiptGasUsed = receiptGasUsed
        self.receiptEffectiveGasPriceGwei = receiptEffectiveGasPriceGwei
        self.receiptNetworkFeeEth = receiptNetworkFeeEth
        self.feePriorityRaw = feePriorityRaw
        self.feeRateDescription = feeRateDescription
        self.confirmationCount = confirmationCount
        self.dogecoinConfirmedNetworkFeeDoge = dogecoinConfirmedNetworkFeeDoge
        self.dogecoinEstimatedFeeRateDogePerKb = dogecoinEstimatedFeeRateDogePerKb
        self.usedChangeOutput = usedChangeOutput
        self.sourceDerivationPath = sourceDerivationPath
        self.changeDerivationPath = changeDerivationPath
        self.sourceAddress = sourceAddress
        self.changeAddress = changeAddress
        self.signedTransactionPayload = signedTransactionPayload
        self.signedTransactionPayloadFormat = signedTransactionPayloadFormat
        self.failureReason = failureReason
        self.transactionHistorySource = transactionHistorySource
        self.createdAt = createdAt
    }
    @MainActor var assetIdentifier: String? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let nativeDescriptor = Coin.nativeChainIconDescriptor(symbol: symbol, chainName: chainName) {
            return nativeDescriptor.assetIdentifier
        }
        guard let chainSlug = transactionIconChainSlug else { return nil }
        guard !normalizedSymbol.isEmpty else { return nil }
        return "token:\(chainSlug):\(normalizedSymbol)"
    }
    /// The chain part of a token's icon identifier, for chains that host
    /// tokens.
    ///
    /// Six chains were named here out of the eighteen `tokenHostingChain`
    /// knows, so a token on Polygon, Base, Sui, TON or NEAR produced no
    /// identifier and got no icon lookup at all. The slug is not parsed —
    /// `entry(matchingAssetIdentifier:)` matches the symbol fragment — so the
    /// registry id serves, and BNB Chain's `"bnb-chain"` was never read as
    /// anything but text.
    private var transactionIconChainSlug: String? {
        guard let chain = Chain(displayName: chainName), chain.tokenHostingChain != nil else {
            return nil
        }
        return chain.id
    }
}
enum SendBroadcastVerificationStatus: Equatable {
    case verified
    case deferred
    case failed(String)
}

extension TransactionRecord {
    func withRebroadcastUpdate(status: TransactionStatus, transactionHash: String?, failureReason: String? = nil) -> TransactionRecord {
        TransactionRecord(
            id: id, walletID: walletID, kind: kind, status: status, walletName: walletName, assetName: assetName, symbol: symbol,
            chainName: chainName, amount: amount, address: address, transactionHash: transactionHash, ethereumNonce: ethereumNonce,
            receiptBlockNumber: receiptBlockNumber, receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: receiptNetworkFeeEth,
            feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription, confirmationCount: confirmationCount,
            dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge,
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: usedChangeOutput,
            sourceDerivationPath: sourceDerivationPath, changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            signedTransactionPayload: signedTransactionPayload, signedTransactionPayloadFormat: signedTransactionPayloadFormat,
            failureReason: failureReason, transactionHistorySource: transactionHistorySource, createdAt: createdAt)
    }
    @MainActor init?(snapshot: CorePersistedTransactionRecord) {
        guard let resolvedID = UUID(uuidString: snapshot.id) else { return nil }
        let resolvedKind = snapshot.kind
        let resolvedStatus = snapshot.status ?? (resolvedKind == .receive ? .pending : .confirmed)
        self.init(
            id: resolvedID,
            walletID: snapshot.walletId,
            kind: resolvedKind,
            status: resolvedStatus,
            walletName: snapshot.walletName,
            assetName: snapshot.assetName,
            symbol: snapshot.symbol,
            chainName: snapshot.chainName,
            amount: snapshot.amount,
            address: snapshot.address,
            transactionHash: snapshot.transactionHash,
            ethereumNonce: snapshot.ethereumNonce.map { Int($0) },
            receiptBlockNumber: snapshot.receiptBlockNumber.map { Int($0) },
            receiptGasUsed: snapshot.receiptGasUsed,
            receiptEffectiveGasPriceGwei: snapshot.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeEth: snapshot.receiptNetworkFeeEth,
            feePriorityRaw: snapshot.feePriorityRaw,
            feeRateDescription: snapshot.feeRateDescription,
            confirmationCount: snapshot.confirmationCount.map { Int($0) },
            dogecoinConfirmedNetworkFeeDoge: snapshot.dogecoinConfirmedNetworkFeeDoge,
            dogecoinEstimatedFeeRateDogePerKb: snapshot.dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: snapshot.usedChangeOutput,
            sourceDerivationPath: snapshot.sourceDerivationPath,
            changeDerivationPath: snapshot.changeDerivationPath,
            sourceAddress: snapshot.sourceAddress,
            changeAddress: snapshot.changeAddress,
            signedTransactionPayload: snapshot.signedTransactionPayload,
            signedTransactionPayloadFormat: snapshot.signedTransactionPayloadFormat,
            failureReason: snapshot.failureReason,
            transactionHistorySource: snapshot.transactionHistorySource,
            createdAt: Date(timeIntervalSinceReferenceDate: snapshot.createdAt)
        )
    }
    var persistedSnapshot: CorePersistedTransactionRecord {
        CorePersistedTransactionRecord(
            id: id.uuidString,
            walletId: walletID,
            kind: kind,
            status: status,
            walletName: walletName,
            assetName: assetName,
            symbol: symbol,
            chainName: chainName,
            amount: amount,
            address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce.map { Int64($0) },
            receiptBlockNumber: receiptBlockNumber.map { Int64($0) },
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeEth: receiptNetworkFeeEth,
            feePriorityRaw: feePriorityRaw,
            feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount.map { Int64($0) },
            dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge,
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: usedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transactionHistorySource,
            createdAt: createdAt.timeIntervalSinceReferenceDate
        )
    }
    var titleText: String {
        let copy = CommonLocalizationContent.current
        switch kind {
        case .send: return String(format: copy.transactionSentTitleFormat, symbol)
        case .receive: return String(format: copy.transactionReceivedTitleFormat, symbol)
        }
    }
    var subtitleText: String {
        String(format: CommonLocalizationContent.current.transactionSubtitleFormat, assetName, chainName, walletName)
    }
    var historySourceText: String? {
        guard let transactionHistorySource else { return nil }
        let trimmed = transactionHistorySource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "esplora": return "Esplora"
        case "litecoinspace": return "LitecoinSpace"
        case "blockchain.info": return "Blockchain.info"
        case "blockchair": return "Blockchair"
        case "dogecoin.providers": return "DOGE Providers"
        case "rpc": return "RPC"
        default: return trimmed
        }
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
    var amountText: String? {
        guard amount > 0 else { return nil }
        return String(format: "%.4f %@", amount, symbol)
    }
    var addressPreviewText: String { address }
    var receiptBlockNumberText: String? {
        guard let receiptBlockNumber else { return nil }
        return String(receiptBlockNumber)
    }
    var receiptEffectiveGasPriceText: String? {
        guard let receiptEffectiveGasPriceGwei else { return nil }
        return String(format: "%.3f gwei", receiptEffectiveGasPriceGwei)
    }
    var receiptNetworkFeeText: String? {
        guard let receiptNetworkFeeEth else { return nil }
        return String(format: "%.8f ETH", receiptNetworkFeeEth)
    }
    var storedFeePriorityText: String? {
        if let feePriorityRaw {
            let trimmed = feePriorityRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.capitalized }
        }
        return nil
    }
    var storedFeeRateText: String? {
        if let feeRateDescription {
            let trimmed = feeRateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let dogecoinEstimatedFeeRateDogePerKb { return String(format: "%.4f DOGE/KB", dogecoinEstimatedFeeRateDogePerKb) }
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
    var historyMetadataText: String? {
        var parts: [String] = []
        if let storedFeePriorityText { parts.append("Fee \(storedFeePriorityText)") }
        if let storedFeeRateText { parts.append(storedFeeRateText) }
        if let storedConfirmationCountText { parts.append(storedConfirmationCountText) }
        if let usedChangeOutput, kind == .send {
            parts.append(usedChangeOutput ? "change output" : "no change output")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    var dogecoinConfirmationsText: String? {
        guard chainName == "Dogecoin", let confirmationCount else { return nil }
        return "\(confirmationCount) conf"
    }
    var fullTimestampText: String { createdAt.formatted(date: .abbreviated, time: .standard) }
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

    /// Whether this transaction's status can be rechecked against the chain.
    ///
    /// The rule is `Chain::pending_status_poll`: the chain is polled
    /// UTXO-style, and either it does not require a send or this is one.
    /// Litecoin is `require_send_kind: false` because its explorer confirms
    /// receives on its own cadence.
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

    var supportsStatusRecheck: Bool {
        guard transactionHash != nil,
            let chain = Chain(displayName: chainName),
            case .utxo(_, let requireSendKind) = chain.pendingStatusPoll
        else { return false }
        return !requireSendKind || kind == .send
    }
}
