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
typealias Coin = CoreCoin
extension CoreCoin: Identifiable {
    var color: Color { Coin.displayColor(for: symbol) }
    nonisolated var valueUSD: Double { amount * priceUsd }
    static func makeCustom(
        name: String, symbol: String, coinGeckoId: String, chainName: String, tokenStandard: String,
        contractAddress: String?, amount: Double, priceUsd: Double
    ) -> Coin {
        CoreCoin(
            id: UUID().uuidString, name: name, symbol: symbol, coinGeckoId: coinGeckoId, chainName: chainName,
            tokenStandard: tokenStandard, contractAddress: contractAddress, amount: amount, priceUsd: priceUsd)
    }
    var hasVisibleBalance: Bool { amount > 0 }
    nonisolated var holdingKey: String { "\(chainName)|\(symbol)" }
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
    var chainID: AppChainID? { AppEndpointDirectory.appChain(for: chainName)?.id }
    var isUTXOChain: Bool {
        switch chainID {
        case .bitcoin, .bitcoinCash, .bitcoinSV, .litecoin, .dogecoin: return true
        default: return false
        }
    }
    var isEVMChain: Bool { AppEndpointDirectory.appChain(for: chainName)?.isEVM ?? false }
    var isNativeCoin: Bool {
        guard let descriptor = AppEndpointDirectory.appChain(for: chainName) else { return false }
        return symbol == descriptor.nativeSymbol
    }
}
typealias ImportedWallet = CoreImportedWallet
extension CoreImportedWallet: Identifiable {}
extension CoreImportedWallet {
    nonisolated var totalBalance: Double { holdings.reduce(0) { $0 + $1.valueUSD } }
    var walletSummary: WalletSummary {
        let chain = selectedChain
        let networkMode: String? = {
            switch chain {
            case "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin":
                return bitcoinNetworkMode.rawValue
            case "Dogecoin":
                return dogecoinNetworkMode.rawValue
            default:
                return nil
            }
        }()
        let derivationPath: String? = {
            guard let sdChain = SeedDerivationChain(rawValue: chain) else { return nil }
            return seedDerivationPaths.path(for: sdChain)
        }()
        return WalletSummary(
            id: id, name: name, isWatchOnly: false, chainName: chain, includeInPortfolioTotal: includeInPortfolioTotal,
            networkMode: networkMode, xpub: bitcoinXpub, derivationPreset: seedDerivationPreset.rawValue, derivationPath: derivationPath,
            holdings: holdings.map { coin in
                AssetHolding(
                    name: coin.name, symbol: coin.symbol, coinGeckoId: coin.coinGeckoId,
                    chainName: coin.chainName, tokenStandard: coin.tokenStandard, contractAddress: coin.contractAddress,
                    amount: coin.amount, priceUsd: coin.priceUsd)
            }, addresses: []
        )
    }
}
typealias SeedDerivationPreset = CoreSeedDerivationPreset
nonisolated extension CoreSeedDerivationPreset: RawRepresentable, CaseIterable, Codable, Identifiable {
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
enum SeedDerivationChain: String, CaseIterable, Codable, Identifiable {
    case bitcoin = "Bitcoin"
    case bitcoinCash = "Bitcoin Cash"
    case bitcoinSV = "Bitcoin SV"
    case litecoin = "Litecoin"
    case dogecoin = "Dogecoin"
    case ethereum = "Ethereum"
    case ethereumClassic = "Ethereum Classic"
    case arbitrum = "Arbitrum"
    case optimism = "Optimism"
    case avalanche = "Avalanche"
    case hyperliquid = "Hyperliquid"
    case tron = "Tron"
    case solana = "Solana"
    case stellar = "Stellar"
    case xrp = "XRP Ledger"
    case cardano = "Cardano"
    case sui = "Sui"
    case aptos = "Aptos"
    case ton = "TON"
    case internetComputer = "Internet Computer"
    case near = "NEAR"
    case polkadot = "Polkadot"
    var id: String { rawValue }
    var defaultPath: String { WalletDerivationPresetCatalog.defaultPreset(for: self).derivationPath }
    var presetOptions: [SeedDerivationPathPreset] { WalletDerivationPresetCatalog.mainnetUIPresets(for: self) }
}
struct SeedDerivationPathPreset: Identifiable, Equatable {
    let title: String
    let detail: String
    let path: String
    var id: String { "\(title)|\(path)" }
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
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: SeedDerivationFlavor
}
extension SeedDerivationChain {
    func resolve(path rawPath: String) -> SeedDerivationResolution {
        do {
            let raw = try appCoreResolveDerivationPath(chain: rawValue, derivationPath: rawPath)
            return SeedDerivationResolution(
                chain: SeedDerivationChain(rawValue: raw.chain) ?? self,
                normalizedPath: raw.normalizedPath,
                accountIndex: raw.accountIndex,
                flavor: SeedDerivationFlavor(rawValue: raw.flavor) ?? .standard
            )
        } catch {
            fatalError("Rust derivation path resolution failed for \(rawValue): \(error.localizedDescription)")
        }
    }
}
typealias SeedDerivationPaths = CoreSeedDerivationPaths
extension CoreSeedDerivationPaths {
    // Compat forwarder: legacy property name preserved for call sites pre-rename.
    var bitcoinSV: String {
        get { bitcoinSv }
        set { bitcoinSv = newValue }
    }
    static var defaults: CoreSeedDerivationPaths { loadRustDefaultPreset() }
    init(
        isCustomEnabled: Bool, bitcoin: String, bitcoinCash: String, bitcoinSV: String, litecoin: String, dogecoin: String,
        ethereum: String, ethereumClassic: String, arbitrum: String, optimism: String, avalanche: String, hyperliquid: String, tron: String,
        solana: String, stellar: String, xrp: String, cardano: String, sui: String, aptos: String, ton: String, internetComputer: String,
        near: String, polkadot: String
    ) {
        self.init(
            isCustomEnabled: isCustomEnabled, bitcoin: bitcoin, bitcoinCash: bitcoinCash, bitcoinSv: bitcoinSV, litecoin: litecoin,
            dogecoin: dogecoin, ethereum: ethereum, ethereumClassic: ethereumClassic, arbitrum: arbitrum, optimism: optimism,
            avalanche: avalanche, hyperliquid: hyperliquid, tron: tron, solana: solana, stellar: stellar, xrp: xrp, cardano: cardano,
            sui: sui, aptos: aptos, ton: ton, internetComputer: internetComputer, near: near, polkadot: polkadot)
    }
    func path(for chain: SeedDerivationChain) -> String {
        switch chain {
        case .bitcoin: return bitcoin
        case .bitcoinCash: return bitcoinCash
        case .bitcoinSV: return bitcoinSv
        case .litecoin: return litecoin
        case .dogecoin: return dogecoin
        case .ethereum: return ethereum
        case .ethereumClassic: return ethereumClassic
        case .arbitrum: return arbitrum
        case .optimism: return optimism
        case .avalanche: return avalanche
        case .hyperliquid: return hyperliquid
        case .tron: return tron
        case .solana: return solana
        case .stellar: return stellar
        case .xrp: return xrp
        case .cardano: return cardano
        case .sui: return sui
        case .aptos: return aptos
        case .ton: return ton
        case .internetComputer: return internetComputer
        case .near: return near
        case .polkadot: return polkadot
        }
    }
    mutating func setPath(_ path: String, for chain: SeedDerivationChain) {
        switch chain {
        case .bitcoin: bitcoin = path
        case .bitcoinCash: bitcoinCash = path
        case .bitcoinSV: bitcoinSv = path
        case .litecoin: litecoin = path
        case .dogecoin: dogecoin = path
        case .ethereum: ethereum = path
        case .ethereumClassic: ethereumClassic = path
        case .arbitrum: arbitrum = path
        case .optimism: optimism = path
        case .avalanche: avalanche = path
        case .hyperliquid: hyperliquid = path
        case .tron: tron = path
        case .solana: solana = path
        case .stellar: stellar = path
        case .xrp: xrp = path
        case .cardano: cardano = path
        case .sui: sui = path
        case .aptos: aptos = path
        case .ton: ton = path
        case .internetComputer: internetComputer = path
        case .near: near = path
        case .polkadot: polkadot = path
        }
    }
    static func migrated(from preset: SeedDerivationPreset?) -> CoreSeedDerivationPaths {
        do {
            return try appCoreDerivationPathsForPreset(accountIndex: preset?.accountIndex ?? 0)
        } catch {
            return fallbackPaths(for: preset)
        }
    }
    static func applyingPreset(_ preset: SeedDerivationPreset, keepCustomEnabled: Bool = false) -> CoreSeedDerivationPaths {
        var paths = migrated(from: preset)
        paths.isCustomEnabled = keepCustomEnabled
        return paths
    }
    private static func loadRustDefaultPreset() -> CoreSeedDerivationPaths {
        do {
            return try appCoreDerivationPathsForPreset(accountIndex: 0)
        } catch {
            return fallbackPaths(for: nil)
        }
    }
    private static func fallbackPaths(for preset: SeedDerivationPreset?) -> CoreSeedDerivationPaths {
        let accountIndex = preset?.accountIndex ?? 0
        return CoreSeedDerivationPaths(
            isCustomEnabled: false, bitcoin: "m/84'/0'/\(accountIndex)'/0/0", bitcoinCash: "m/44'/145'/\(accountIndex)'/0/0",
            bitcoinSv: "m/44'/236'/\(accountIndex)'/0/0", litecoin: "m/44'/2'/\(accountIndex)'/0/0",
            dogecoin: "m/44'/3'/\(accountIndex)'/0/0", ethereum: "m/44'/60'/\(accountIndex)'/0/0",
            ethereumClassic: "m/44'/61'/\(accountIndex)'/0/0", arbitrum: "m/44'/60'/\(accountIndex)'/0/0",
            optimism: "m/44'/60'/\(accountIndex)'/0/0", avalanche: "m/44'/60'/\(accountIndex)'/0/0",
            hyperliquid: "m/44'/60'/\(accountIndex)'/0/0", tron: "m/44'/195'/\(accountIndex)'/0/0",
            solana: "m/44'/501'/\(accountIndex)'/0'", stellar: "m/44'/148'/\(accountIndex)'", xrp: "m/44'/144'/\(accountIndex)'/0/0",
            cardano: "m/1852'/1815'/\(accountIndex)'/0/0", sui: "m/44'/784'/\(accountIndex)'/0'/0'",
            aptos: "m/44'/637'/\(accountIndex)'/0'/0'", ton: "m/44'/607'/\(accountIndex)'/0/0",
            internetComputer: "m/44'/223'/\(accountIndex)'/0/0", near: "m/44'/397'/\(accountIndex)'",
            polkadot: "m/44'/354'/\(accountIndex)'"
        )
    }
    func toDictionary() -> [String: String] {
        var d: [String: String] = [:]
        for chain in SeedDerivationChain.allCases { d[chain.rawValue] = path(for: chain) }
        return d
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
struct HistorySection: Identifiable {
    let title: String
    let transactions: [TransactionRecord]
    var id: String { title }
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
struct PriceAlertRule: Identifiable {
    let id: UUID
    let holdingKey: String
    let assetName: String
    let symbol: String
    let chainName: String
    let targetPrice: Double
    let condition: PriceAlertCondition
    var isEnabled: Bool
    var hasTriggered: Bool
    init(
        id: UUID = UUID(), holdingKey: String, assetName: String, symbol: String, chainName: String, targetPrice: Double,
        condition: PriceAlertCondition, isEnabled: Bool = true, hasTriggered: Bool = false
    ) {
        self.id = id
        self.holdingKey = holdingKey
        self.assetName = assetName
        self.symbol = symbol
        self.chainName = chainName
        self.targetPrice = targetPrice
        self.condition = condition
        self.isEnabled = isEnabled
        self.hasTriggered = hasTriggered
    }
    var titleText: String { String(format: CommonLocalizationContent.current.priceAlertTitleFormat, assetName, chainName) }
    var conditionText: String { "\(condition.rawValue) $\(String(format: "%.2f", targetPrice))" }
    var statusText: String {
        if !isEnabled { return AppLocalization.string("Paused") }
        return hasTriggered ? AppLocalization.string("Triggered") : AppLocalization.string("Watching")
    }
}
struct DonationDestination: Identifiable {
    let id = UUID()
    let title: String
    let address: String
    let assetIdentifier: String?
    let color: Color
}
struct AddressBookEntry: Identifiable {
    let id: UUID
    let name: String
    let chainName: String
    let address: String
    let note: String
    init(
        id: UUID = UUID(), name: String, chainName: String, address: String, note: String = ""
    ) {
        self.id = id
        self.name = name
        self.chainName = chainName
        self.address = address
        self.note = note
    }
    var subtitleText: String {
        guard !note.isEmpty else { return chainName }
        return String(format: CommonLocalizationContent.current.addressBookSubtitleFormat, chainName, note)
    }
}
nonisolated struct TransactionRecord: Identifiable, Equatable, Sendable {
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
    let dogecoinConfirmations: Int?
    let dogecoinFeePriorityRaw: String?
    let dogecoinEstimatedFeeRateDogePerKb: Double?
    let usedChangeOutput: Bool?
    let dogecoinUsedChangeOutput: Bool?
    let sourceDerivationPath: String?
    let changeDerivationPath: String?
    let sourceAddress: String?
    let changeAddress: String?
    let dogecoinRawTransactionHex: String?
    let signedTransactionPayload: String?
    let signedTransactionPayloadFormat: String?
    let failureReason: String?
    let transactionHistorySource: String?
    let createdAt: Date
    init(
        id: UUID = UUID(), walletID: String? = nil, kind: TransactionKind, status: TransactionStatus, walletName: String, assetName: String,
        symbol: String, chainName: String, amount: Double, address: String, transactionHash: String? = nil, ethereumNonce: Int? = nil,
        receiptBlockNumber: Int? = nil, receiptGasUsed: String? = nil, receiptEffectiveGasPriceGwei: Double? = nil,
        receiptNetworkFeeEth: Double? = nil, feePriorityRaw: String? = nil, feeRateDescription: String? = nil,
        confirmationCount: Int? = nil, dogecoinConfirmedNetworkFeeDoge: Double? = nil, dogecoinConfirmations: Int? = nil,
        dogecoinFeePriorityRaw: String? = nil, dogecoinEstimatedFeeRateDogePerKb: Double? = nil, usedChangeOutput: Bool? = nil,
        dogecoinUsedChangeOutput: Bool? = nil, sourceDerivationPath: String? = nil, changeDerivationPath: String? = nil,
        sourceAddress: String? = nil, changeAddress: String? = nil, dogecoinRawTransactionHex: String? = nil,
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
        self.dogecoinConfirmations = dogecoinConfirmations
        self.dogecoinFeePriorityRaw = dogecoinFeePriorityRaw
        self.dogecoinEstimatedFeeRateDogePerKb = dogecoinEstimatedFeeRateDogePerKb
        self.usedChangeOutput = usedChangeOutput
        self.dogecoinUsedChangeOutput = dogecoinUsedChangeOutput
        self.sourceDerivationPath = sourceDerivationPath
        self.changeDerivationPath = changeDerivationPath
        self.sourceAddress = sourceAddress
        self.changeAddress = changeAddress
        self.dogecoinRawTransactionHex = dogecoinRawTransactionHex
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
    nonisolated private var transactionIconChainSlug: String? {
        switch chainName {
        case "Ethereum": return "ethereum"
        case "Arbitrum": return "arbitrum"
        case "BNB Chain": return "bnb-chain"
        case "Avalanche": return "avalanche"
        case "Tron": return "tron"
        case "Solana": return "solana"
        default: return nil
        }
    }
}
enum SendBroadcastVerificationStatus: Equatable {
    case verified
    case deferred
    case failed(String)
}

extension ImportedWallet {
    @MainActor init(snapshot: PersistedWallet) {
        self.init(
            id: snapshot.id, name: snapshot.name, bitcoinNetworkMode: snapshot.bitcoinNetworkMode,
            dogecoinNetworkMode: snapshot.dogecoinNetworkMode, bitcoinAddress: snapshot.bitcoinAddress, bitcoinXpub: snapshot.bitcoinXpub,
            bitcoinCashAddress: snapshot.bitcoinCashAddress, bitcoinSvAddress: snapshot.bitcoinSvAddress,
            litecoinAddress: snapshot.litecoinAddress, dogecoinAddress: snapshot.dogecoinAddress, ethereumAddress: snapshot.ethereumAddress,
            tronAddress: snapshot.tronAddress, solanaAddress: snapshot.solanaAddress, stellarAddress: snapshot.stellarAddress,
            xrpAddress: snapshot.xrpAddress, moneroAddress: snapshot.moneroAddress, cardanoAddress: snapshot.cardanoAddress,
            suiAddress: snapshot.suiAddress, aptosAddress: snapshot.aptosAddress, tonAddress: snapshot.tonAddress,
            icpAddress: snapshot.icpAddress, nearAddress: snapshot.nearAddress, polkadotAddress: snapshot.polkadotAddress,
            seedDerivationPreset: snapshot.seedDerivationPreset, seedDerivationPaths: snapshot.seedDerivationPaths,
            derivationOverrides: snapshot.derivationOverrides,
            selectedChain: snapshot.selectedChain, holdings: snapshot.holdings.map(Coin.init(snapshot:)),
            includeInPortfolioTotal: snapshot.includeInPortfolioTotal
        )
    }
    var persistedSnapshot: PersistedWallet {
        PersistedWallet(
            id: id, name: name, bitcoinNetworkMode: bitcoinNetworkMode, dogecoinNetworkMode: dogecoinNetworkMode,
            bitcoinAddress: bitcoinAddress, bitcoinXpub: bitcoinXpub, bitcoinCashAddress: bitcoinCashAddress,
            bitcoinSvAddress: bitcoinSvAddress, litecoinAddress: litecoinAddress, dogecoinAddress: dogecoinAddress,
            ethereumAddress: ethereumAddress, tronAddress: tronAddress, solanaAddress: solanaAddress, stellarAddress: stellarAddress,
            xrpAddress: xrpAddress, moneroAddress: moneroAddress, cardanoAddress: cardanoAddress, suiAddress: suiAddress,
            aptosAddress: aptosAddress, tonAddress: tonAddress, icpAddress: icpAddress, nearAddress: nearAddress,
            polkadotAddress: polkadotAddress, seedDerivationPreset: seedDerivationPreset, seedDerivationPaths: seedDerivationPaths,
            derivationOverrides: derivationOverrides,
            selectedChain: selectedChain, holdings: holdings.map(\.persistedSnapshot), includeInPortfolioTotal: includeInPortfolioTotal
        )
    }
}
extension TransactionRecord {
    func withRebroadcastUpdate(status: TransactionStatus, transactionHash: String?, failureReason: String? = nil) -> TransactionRecord {
        TransactionRecord(
            id: id, walletID: walletID, kind: kind, status: status, walletName: walletName, assetName: assetName, symbol: symbol,
            chainName: chainName, amount: amount, address: address, transactionHash: transactionHash, ethereumNonce: ethereumNonce,
            receiptBlockNumber: receiptBlockNumber, receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: receiptNetworkFeeEth,
            feePriorityRaw: feePriorityRaw, feeRateDescription: feeRateDescription, confirmationCount: confirmationCount,
            dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge, dogecoinConfirmations: dogecoinConfirmations,
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw, dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: usedChangeOutput, dogecoinUsedChangeOutput: dogecoinUsedChangeOutput,
            sourceDerivationPath: sourceDerivationPath, changeDerivationPath: changeDerivationPath, sourceAddress: sourceAddress,
            changeAddress: changeAddress, dogecoinRawTransactionHex: dogecoinRawTransactionHex,
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
            dogecoinConfirmations: snapshot.dogecoinConfirmations.map { Int($0) },
            dogecoinFeePriorityRaw: snapshot.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: snapshot.dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: snapshot.usedChangeOutput,
            dogecoinUsedChangeOutput: snapshot.dogecoinUsedChangeOutput,
            sourceDerivationPath: snapshot.sourceDerivationPath,
            changeDerivationPath: snapshot.changeDerivationPath,
            sourceAddress: snapshot.sourceAddress,
            changeAddress: snapshot.changeAddress,
            dogecoinRawTransactionHex: snapshot.dogecoinRawTransactionHex,
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
            dogecoinConfirmations: dogecoinConfirmations.map { Int64($0) },
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: usedChangeOutput,
            dogecoinUsedChangeOutput: dogecoinUsedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            dogecoinRawTransactionHex: dogecoinRawTransactionHex,
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
        if let dogecoinFeePriorityRaw {
            let trimmed = dogecoinFeePriorityRaw.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let dogecoinConfirmations { return "\(dogecoinConfirmations) conf" }
        return nil
    }
    var storedUsedChangeOutputText: String? {
        if let usedChangeOutput { return usedChangeOutput ? "Yes" : "No" }
        if let dogecoinUsedChangeOutput { return dogecoinUsedChangeOutput ? "Yes" : "No" }
        return nil
    }
    var rawTransactionHexText: String? {
        if let dogecoinRawTransactionHex {
            let trimmed = dogecoinRawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
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
        if let usedChangeOutput = usedChangeOutput ?? dogecoinUsedChangeOutput, kind == .send {
            parts.append(usedChangeOutput ? "change output" : "no change output")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    var dogecoinConfirmationsText: String? {
        guard chainName == "Dogecoin", let dogecoinConfirmations else { return nil }
        return "\(dogecoinConfirmations) conf"
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
        if let dogecoinRawTransactionHex {
            let trimmed = dogecoinRawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
    var rebroadcastPayloadFormat: String? {
        if let signedTransactionPayloadFormat {
            let trimmed = signedTransactionPayloadFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let dogecoinRawTransactionHex, !dogecoinRawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "dogecoin.raw_hex"
        }
        return nil
    }
    var supportsSignedRebroadcast: Bool { kind == .send && rebroadcastPayload != nil && rebroadcastPayloadFormat != nil }
}
extension PriceAlertRule {
    init?(snapshot: CorePersistedPriceAlertRule) {
        guard let resolvedID = UUID(uuidString: snapshot.id) else { return nil }
        self.init(
            id: resolvedID, holdingKey: snapshot.holdingKey, assetName: snapshot.assetName, symbol: snapshot.symbol,
            chainName: snapshot.chainName, targetPrice: snapshot.targetPrice, condition: snapshot.condition, isEnabled: snapshot.isEnabled,
            hasTriggered: snapshot.hasTriggered
        )
    }
    var persistedSnapshot: CorePersistedPriceAlertRule {
        CorePersistedPriceAlertRule(
            id: id.uuidString, holdingKey: holdingKey, assetName: assetName, symbol: symbol, chainName: chainName, targetPrice: targetPrice,
            condition: condition, isEnabled: isEnabled, hasTriggered: hasTriggered
        )
    }
}
extension AddressBookEntry {
    init?(snapshot: CorePersistedAddressBookEntry) {
        guard let resolvedID = UUID(uuidString: snapshot.id) else { return nil }
        self.init(
            id: resolvedID, name: snapshot.name, chainName: snapshot.chainName, address: snapshot.address, note: snapshot.note
        )
    }
    var persistedSnapshot: CorePersistedAddressBookEntry {
        CorePersistedAddressBookEntry(
            id: id.uuidString, name: name, chainName: chainName, address: address, note: note
        )
    }
}
