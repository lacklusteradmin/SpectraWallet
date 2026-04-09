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
        case .economy:
            return "Economy"
        case .normal:
            return "Normal"
        case .priority:
            return "Priority"
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

enum WalletAddressInventoryRole: String, Codable {
    case primary
    case external
    case change
    case alternate
}

struct WalletAddressInventoryEntry: Equatable, Codable, Identifiable {
    let address: String
    let derivationPath: String?
    let account: UInt32?
    let branchIndex: UInt32?
    let addressIndex: UInt32?
    let role: WalletAddressInventoryRole

    var id: String {
        if let derivationPath {
            return "\(role.rawValue)|\(derivationPath.lowercased())|\(address.lowercased())"
        }
        return "\(role.rawValue)|\(address.lowercased())"
    }
}

struct WalletAddressInventory: Equatable, Codable {
    let entries: [WalletAddressInventoryEntry]
    let supportsDiscoveryScan: Bool
    let supportsChangeBranch: Bool
    let scanLimit: UInt32?

    var primaryEntry: WalletAddressInventoryEntry? {
        entries.first(where: { $0.role == .primary || $0.role == .external })
    }
}

struct Coin: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let marketDataID: String
    let coinGeckoID: String
    let chainName: String
    let tokenStandard: String
    let contractAddress: String?
    let amount: Double
    let priceUSD: Double
    let mark: String
    var color: Color
    
    // Calculates the value of this specific holding
    var valueUSD: Double {
        return amount * priceUSD
    }

    // Asset visibility must be driven by token units, not rounded fiat value.
    var hasVisibleBalance: Bool {
        amount > 0
    }
    
    var holdingKey: String {
        "\(chainName)|\(symbol)"
    }
    
    var accentMarks: [String] {
        switch symbol {
        case "BTC":
            return ["L1", "S", "P"]
        case "LTC":
            return ["L1", "S", "F"]
        case "ETH":
            return ["SC", "VM", "D"]
        case "SOL":
            return ["F", "RT", "+"]
        case "MATIC":
            return ["L2", "ZK", "G"]
        case "AVAX":
            return ["C", "X", "S"]
        case "HYPE":
            return ["L1", "DEX", "P"]
        case "ARB":
            return ["L2", "OP", "A"]
        case "BNB":
            return ["B", "DEX", "+"]
        case "DOGE":
            return ["M", "P2P", "+"]
        case "ADA":
            return ["POS", "SC", "L1"]
        case "TRX":
            return ["TVM", "NET", "+"]
        case "XMR":
            return ["PRV", "POW", "S"]
        case "SUI":
            return ["OBJ", "MOVE", "ZK"]
        case "APT":
            return ["MOVE", "ACC", "L1"]
        case "ICP":
            return ["NS", "LED", "L1"]
        case "NEAR":
            return ["SHD", "ACC", "POS"]
        default:
            return ["+", "+", "+"]
        }
    }
}

struct ImportedWallet: Identifiable {
    let id: UUID
    let name: String
    let bitcoinNetworkMode: BitcoinNetworkMode
    let dogecoinNetworkMode: DogecoinNetworkMode
    let bitcoinAddress: String?
    let bitcoinXPub: String?
    let bitcoinCashAddress: String?
    let bitcoinSVAddress: String?
    let litecoinAddress: String?
    let dogecoinAddress: String?
    let ethereumAddress: String?
    let tronAddress: String?
    let solanaAddress: String?
    let stellarAddress: String?
    let xrpAddress: String?
    let moneroAddress: String?
    let cardanoAddress: String?
    let suiAddress: String?
    let aptosAddress: String?
    let tonAddress: String?
    let icpAddress: String?
    let nearAddress: String?
    let polkadotAddress: String?
    let seedDerivationPreset: SeedDerivationPreset
    let seedDerivationPaths: SeedDerivationPaths
    let selectedChain: String
    let holdings: [Coin]
    let includeInPortfolioTotal: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        bitcoinNetworkMode: BitcoinNetworkMode = .mainnet,
        dogecoinNetworkMode: DogecoinNetworkMode = .mainnet,
        bitcoinAddress: String? = nil,
        bitcoinXPub: String? = nil,
        bitcoinCashAddress: String? = nil,
        bitcoinSVAddress: String? = nil,
        litecoinAddress: String? = nil,
        dogecoinAddress: String? = nil,
        ethereumAddress: String? = nil,
        tronAddress: String? = nil,
        solanaAddress: String? = nil,
        stellarAddress: String? = nil,
        xrpAddress: String? = nil,
        moneroAddress: String? = nil,
        cardanoAddress: String? = nil,
        suiAddress: String? = nil,
        aptosAddress: String? = nil,
        tonAddress: String? = nil,
        icpAddress: String? = nil,
        nearAddress: String? = nil,
        polkadotAddress: String? = nil,
        seedDerivationPreset: SeedDerivationPreset = .standard,
        seedDerivationPaths: SeedDerivationPaths = .defaults,
        selectedChain: String,
        holdings: [Coin],
        includeInPortfolioTotal: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bitcoinNetworkMode = bitcoinNetworkMode
        self.dogecoinNetworkMode = dogecoinNetworkMode
        self.bitcoinAddress = bitcoinAddress
        self.bitcoinXPub = bitcoinXPub
        self.bitcoinCashAddress = bitcoinCashAddress
        self.bitcoinSVAddress = bitcoinSVAddress
        self.litecoinAddress = litecoinAddress
        self.dogecoinAddress = dogecoinAddress
        self.ethereumAddress = ethereumAddress
        self.tronAddress = tronAddress
        self.solanaAddress = solanaAddress
        self.stellarAddress = stellarAddress
        self.xrpAddress = xrpAddress
        self.moneroAddress = moneroAddress
        self.cardanoAddress = cardanoAddress
        self.suiAddress = suiAddress
        self.aptosAddress = aptosAddress
        self.tonAddress = tonAddress
        self.icpAddress = icpAddress
        self.nearAddress = nearAddress
        self.polkadotAddress = polkadotAddress
        self.seedDerivationPreset = seedDerivationPreset
        self.seedDerivationPaths = seedDerivationPaths
        self.selectedChain = selectedChain
        self.holdings = holdings
        self.includeInPortfolioTotal = includeInPortfolioTotal
    }

    var totalBalance: Double {
        holdings.reduce(0) { $0 + $1.valueUSD }
    }
}

enum SeedDerivationPreset: String, CaseIterable, Codable, Identifiable {
    case standard
    case account1
    case account2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .account1:
            return "Account 1"
        case .account2:
            return "Account 2"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            return "Use account 0 default paths."
        case .account1:
            return "Use account 1 paths for all supported chains."
        case .account2:
            return "Use account 2 paths for all supported chains."
        }
    }

    var accountIndex: UInt32 {
        switch self {
        case .standard:
            return 0
        case .account1:
            return 1
        case .account2:
            return 2
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

    var defaultPath: String {
        WalletDerivationPresetCatalog.defaultPreset(for: self).derivationPath
    }

    var presetOptions: [SeedDerivationPathPreset] {
        WalletDerivationPresetCatalog.mainnetUIPresets(for: self)
    }
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
            let resolution = try WalletRustAppCoreBridge.resolve(chain: self, path: rawPath)
            return SeedDerivationResolution(
                chain: resolution.chain,
                normalizedPath: resolution.normalizedPath,
                accountIndex: resolution.accountIndex,
                flavor: resolution.flavor
            )
        } catch {
            fatalError("Rust derivation path resolution failed for \(rawValue): \(error.localizedDescription)")
        }
    }
}

struct SeedDerivationPaths: Equatable {
    var isCustomEnabled: Bool
    var bitcoin: String
    var bitcoinCash: String
    var bitcoinSV: String
    var litecoin: String
    var dogecoin: String
    var ethereum: String
    var ethereumClassic: String
    var arbitrum: String
    var optimism: String
    var avalanche: String
    var hyperliquid: String
    var tron: String
    var solana: String
    var stellar: String
    var xrp: String
    var cardano: String
    var sui: String
    var aptos: String
    var ton: String
    var internetComputer: String
    var near: String
    var polkadot: String

    static let defaults = loadRustDefaultPreset()

    func path(for chain: SeedDerivationChain) -> String {
        switch chain {
        case .bitcoin:
            return bitcoin
        case .bitcoinCash:
            return bitcoinCash
        case .bitcoinSV:
            return bitcoinSV
        case .litecoin:
            return litecoin
        case .dogecoin:
            return dogecoin
        case .ethereum:
            return ethereum
        case .ethereumClassic:
            return ethereumClassic
        case .arbitrum:
            return arbitrum
        case .optimism:
            return optimism
        case .avalanche:
            return avalanche
        case .hyperliquid:
            return hyperliquid
        case .tron:
            return tron
        case .solana:
            return solana
        case .stellar:
            return stellar
        case .xrp:
            return xrp
        case .cardano:
            return cardano
        case .sui:
            return sui
        case .aptos:
            return aptos
        case .ton:
            return ton
        case .internetComputer:
            return internetComputer
        case .near:
            return near
        case .polkadot:
            return polkadot
        }
    }

    mutating func setPath(_ path: String, for chain: SeedDerivationChain) {
        switch chain {
        case .bitcoin:
            bitcoin = path
        case .bitcoinCash:
            bitcoinCash = path
        case .bitcoinSV:
            bitcoinSV = path
        case .litecoin:
            litecoin = path
        case .dogecoin:
            dogecoin = path
        case .ethereum:
            ethereum = path
        case .ethereumClassic:
            ethereumClassic = path
        case .arbitrum:
            arbitrum = path
        case .optimism:
            optimism = path
        case .avalanche:
            avalanche = path
        case .hyperliquid:
            hyperliquid = path
        case .tron:
            tron = path
        case .solana:
            solana = path
        case .stellar:
            stellar = path
        case .xrp:
            xrp = path
        case .cardano:
            cardano = path
        case .sui:
            sui = path
        case .aptos:
            aptos = path
        case .ton:
            ton = path
        case .internetComputer:
            internetComputer = path
        case .near:
            near = path
        case .polkadot:
            polkadot = path
        }
    }

    static func migrated(from preset: SeedDerivationPreset?) -> SeedDerivationPaths {
        do {
            return try WalletRustAppCoreBridge.derivationPaths(for: preset)
        } catch {
            fatalError("Rust derivation preset paths failed to load: \(error.localizedDescription)")
        }
    }

    static func applyingPreset(_ preset: SeedDerivationPreset, keepCustomEnabled: Bool = false) -> SeedDerivationPaths {
        var paths = migrated(from: preset)
        paths.isCustomEnabled = keepCustomEnabled
        return paths
    }

    private static func loadRustDefaultPreset() -> SeedDerivationPaths {
        do {
            return try WalletRustAppCoreBridge.derivationPaths(for: nil)
        } catch {
            fatalError("Rust default derivation paths failed to load: \(error.localizedDescription)")
        }
    }
}

enum TransactionKind: String, Codable {
    case send
    case receive
}

enum TransactionStatus: String, Codable {
    case pending
    case confirmed
    case failed

    var localizedTitle: String {
        switch self {
        case .pending:
            return String(localized: "Pending")
        case .confirmed:
            return String(localized: "Confirmed")
        case .failed:
            return String(localized: "Failed")
        }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case sends = "Sends"
    case receives = "Receives"
    case pending = "Pending"
    
    var id: String { rawValue }

    var localizedTitle: String {
        String(localized: LocalizedStringResource(stringLiteral: rawValue))
    }
}

enum HistorySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    
    var id: String { rawValue }

    var localizedTitle: String {
        String(localized: LocalizedStringResource(stringLiteral: rawValue))
    }
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

enum PriceAlertCondition: String, CaseIterable, Codable, Identifiable {
    case above = "Above"
    case below = "Below"
    
    var id: String { rawValue }

    var displayName: String {
        NSLocalizedString(rawValue, comment: "")
    }
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
        id: UUID = UUID(),
        holdingKey: String,
        assetName: String,
        symbol: String,
        chainName: String,
        targetPrice: Double,
        condition: PriceAlertCondition,
        isEnabled: Bool = true,
        hasTriggered: Bool = false
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
    
    var titleText: String {
        String(format: CommonLocalizationContent.current.priceAlertTitleFormat, assetName, chainName)
    }
    
    var conditionText: String {
        "\(condition.rawValue) $\(String(format: "%.2f", targetPrice))"
    }
    
    var statusText: String {
        if !isEnabled {
            return NSLocalizedString("Paused", comment: "")
        }
        return hasTriggered
            ? NSLocalizedString("Triggered", comment: "")
            : NSLocalizedString("Watching", comment: "")
    }
}

struct DonationDestination: Identifiable {
    let id = UUID()
    let title: String
    let address: String
    let mark: String
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
        id: UUID = UUID(),
        name: String,
        chainName: String,
        address: String,
        note: String = ""
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

struct TransactionRecord: Identifiable {
    let id: UUID
    let walletID: UUID?
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
    let receiptNetworkFeeETH: Double?
    let feePriorityRaw: String?
    let feeRateDescription: String?
    let confirmationCount: Int?
    let dogecoinConfirmedNetworkFeeDOGE: Double?
    let dogecoinConfirmations: Int?
    let dogecoinFeePriorityRaw: String?
    let dogecoinEstimatedFeeRateDOGEPerKB: Double?
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
        id: UUID = UUID(),
        walletID: UUID? = nil,
        kind: TransactionKind,
        status: TransactionStatus,
        walletName: String,
        assetName: String,
        symbol: String,
        chainName: String,
        amount: Double,
        address: String,
        transactionHash: String? = nil,
        ethereumNonce: Int? = nil,
        receiptBlockNumber: Int? = nil,
        receiptGasUsed: String? = nil,
        receiptEffectiveGasPriceGwei: Double? = nil,
        receiptNetworkFeeETH: Double? = nil,
        feePriorityRaw: String? = nil,
        feeRateDescription: String? = nil,
        confirmationCount: Int? = nil,
        dogecoinConfirmedNetworkFeeDOGE: Double? = nil,
        dogecoinConfirmations: Int? = nil,
        dogecoinFeePriorityRaw: String? = nil,
        dogecoinEstimatedFeeRateDOGEPerKB: Double? = nil,
        usedChangeOutput: Bool? = nil,
        dogecoinUsedChangeOutput: Bool? = nil,
        sourceDerivationPath: String? = nil,
        changeDerivationPath: String? = nil,
        sourceAddress: String? = nil,
        changeAddress: String? = nil,
        dogecoinRawTransactionHex: String? = nil,
        signedTransactionPayload: String? = nil,
        signedTransactionPayloadFormat: String? = nil,
        failureReason: String? = nil,
        transactionHistorySource: String? = nil,
        createdAt: Date = Date()
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
        self.receiptNetworkFeeETH = receiptNetworkFeeETH
        self.feePriorityRaw = feePriorityRaw
        self.feeRateDescription = feeRateDescription
        self.confirmationCount = confirmationCount
        self.dogecoinConfirmedNetworkFeeDOGE = dogecoinConfirmedNetworkFeeDOGE
        self.dogecoinConfirmations = dogecoinConfirmations
        self.dogecoinFeePriorityRaw = dogecoinFeePriorityRaw
        self.dogecoinEstimatedFeeRateDOGEPerKB = dogecoinEstimatedFeeRateDOGEPerKB
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

    var assetIdentifier: String? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let nativeDescriptor = Coin.nativeChainIconDescriptor(symbol: symbol, chainName: chainName) {
            return nativeDescriptor.assetIdentifier
        }

        guard let chainSlug = transactionIconChainSlug else { return nil }
        guard !normalizedSymbol.isEmpty else { return nil }
        return "token:\(chainSlug):\(normalizedSymbol)"
    }

    private var transactionIconChainSlug: String? {
        switch chainName {
        case "Ethereum":
            return "ethereum"
        case "Arbitrum":
            return "arbitrum"
        case "BNB Chain":
            return "bnb-chain"
        case "Avalanche":
            return "avalanche"
        case "Tron":
            return "tron"
        case "Solana":
            return "solana"
        default:
            return nil
        }
    }
}

enum SendBroadcastVerificationStatus: Equatable {
    case verified
    case deferred
    case failed(String)
}

enum SendBroadcastFailureDisposition: Equatable {
    case alreadyBroadcast
    case retryable
    case terminal
}

func classifySendBroadcastFailure(_ rawMessage: String) -> SendBroadcastFailureDisposition {
    let normalized = rawMessage
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    guard !normalized.isEmpty else {
        return .terminal
    }

    let alreadyBroadcastPatterns = [
        "already known",
        "already exists",
        "already imported",
        "already in mempool",
        "txn-already-known",
        "known transaction",
        "duplicate transaction",
        "duplicate tx",
        "tx already exists",
        "transaction already exists",
        "transaction already imported",
        "already have transaction",
        "already submitted",
        "already processed",
        "already confirmed",
        "tefalready"
    ]
    if alreadyBroadcastPatterns.contains(where: { normalized.contains($0) }) {
        return .alreadyBroadcast
    }

    let retryablePatterns = [
        "timeout",
        "timed out",
        "temporary",
        "temporarily unavailable",
        "service unavailable",
        "try again",
        "too many requests",
        "rate limit",
        "429",
        "500",
        "502",
        "503",
        "504",
        "connection reset",
        "network connection was lost",
        "cannot connect",
        "could not connect",
        "connection refused",
        "broken pipe",
        "econnreset",
        "econnrefused",
        "gateway timeout",
        "internal error",
        "internal server error",
        "bad gateway",
        "transport error"
    ]
    if retryablePatterns.contains(where: { normalized.contains($0) }) {
        return .retryable
    }

    return .terminal
}

extension ImportedWallet {
    @MainActor init(snapshot: PersistedWallet) {
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            bitcoinNetworkMode: snapshot.bitcoinNetworkMode,
            dogecoinNetworkMode: snapshot.dogecoinNetworkMode,
            bitcoinAddress: snapshot.bitcoinAddress,
            bitcoinXPub: snapshot.bitcoinXPub,
            bitcoinCashAddress: snapshot.bitcoinCashAddress,
            bitcoinSVAddress: snapshot.bitcoinSVAddress,
            litecoinAddress: snapshot.litecoinAddress,
            dogecoinAddress: snapshot.dogecoinAddress,
            ethereumAddress: snapshot.ethereumAddress,
            tronAddress: snapshot.tronAddress,
            solanaAddress: snapshot.solanaAddress,
            stellarAddress: snapshot.stellarAddress,
            xrpAddress: snapshot.xrpAddress,
            moneroAddress: snapshot.moneroAddress,
            cardanoAddress: snapshot.cardanoAddress,
            suiAddress: snapshot.suiAddress,
            aptosAddress: snapshot.aptosAddress,
            tonAddress: snapshot.tonAddress,
            icpAddress: snapshot.icpAddress,
            nearAddress: snapshot.nearAddress,
            polkadotAddress: snapshot.polkadotAddress,
            seedDerivationPreset: snapshot.seedDerivationPreset,
            seedDerivationPaths: snapshot.seedDerivationPaths,
            selectedChain: snapshot.selectedChain,
            holdings: snapshot.holdings.map(Coin.init(snapshot:)),
            includeInPortfolioTotal: snapshot.includeInPortfolioTotal
        )
    }

    var persistedSnapshot: PersistedWallet {
        PersistedWallet(
            id: id,
            name: name,
            bitcoinNetworkMode: bitcoinNetworkMode,
            dogecoinNetworkMode: dogecoinNetworkMode,
            bitcoinAddress: bitcoinAddress,
            bitcoinXPub: bitcoinXPub,
            bitcoinCashAddress: bitcoinCashAddress,
            bitcoinSVAddress: bitcoinSVAddress,
            litecoinAddress: litecoinAddress,
            dogecoinAddress: dogecoinAddress,
            ethereumAddress: ethereumAddress,
            tronAddress: tronAddress,
            solanaAddress: solanaAddress,
            stellarAddress: stellarAddress,
            xrpAddress: xrpAddress,
            moneroAddress: moneroAddress,
            cardanoAddress: cardanoAddress,
            suiAddress: suiAddress,
            aptosAddress: aptosAddress,
            tonAddress: tonAddress,
            icpAddress: icpAddress,
            nearAddress: nearAddress,
            polkadotAddress: polkadotAddress,
            seedDerivationPreset: seedDerivationPreset,
            seedDerivationPaths: seedDerivationPaths,
            selectedChain: selectedChain,
            holdings: holdings.map(\.persistedSnapshot),
            includeInPortfolioTotal: includeInPortfolioTotal
        )
    }
}

extension TransactionRecord {
    @MainActor init(snapshot: PersistedTransactionRecord) {
        self.init(
            id: snapshot.id,
            walletID: snapshot.walletID,
            kind: snapshot.kind,
            status: snapshot.status,
            walletName: snapshot.walletName,
            assetName: snapshot.assetName,
            symbol: snapshot.symbol,
            chainName: snapshot.chainName,
            amount: snapshot.amount,
            address: snapshot.address,
            transactionHash: snapshot.transactionHash,
            ethereumNonce: snapshot.ethereumNonce,
            receiptBlockNumber: snapshot.receiptBlockNumber,
            receiptGasUsed: snapshot.receiptGasUsed,
            receiptEffectiveGasPriceGwei: snapshot.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: snapshot.receiptNetworkFeeETH,
            feePriorityRaw: snapshot.feePriorityRaw,
            feeRateDescription: snapshot.feeRateDescription,
            confirmationCount: snapshot.confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: snapshot.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: snapshot.dogecoinConfirmations,
            dogecoinFeePriorityRaw: snapshot.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: snapshot.dogecoinEstimatedFeeRateDOGEPerKB,
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
            createdAt: snapshot.createdAt
        )
    }
    
    var persistedSnapshot: PersistedTransactionRecord {
        PersistedTransactionRecord(
            id: id,
            walletID: walletID,
            kind: kind,
            status: status,
            walletName: walletName,
            assetName: assetName,
            symbol: symbol,
            chainName: chainName,
            amount: amount,
            address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce,
            receiptBlockNumber: receiptBlockNumber,
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: receiptNetworkFeeETH,
            feePriorityRaw: feePriorityRaw,
            feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: dogecoinConfirmations,
            dogecoinFeePriorityRaw: dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: dogecoinEstimatedFeeRateDOGEPerKB,
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
            createdAt: createdAt
        )
    }
    
    var titleText: String {
        let copy = CommonLocalizationContent.current
        switch kind {
        case .send:
            return String(format: copy.transactionSentTitleFormat, symbol)
        case .receive:
            return String(format: copy.transactionReceivedTitleFormat, symbol)
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
        case "esplora":
            return "Esplora"
        case "litecoinspace":
            return "LitecoinSpace"
        case "blockchain.info":
            return "Blockchain.info"
        case "blockchair":
            return "Blockchair"
        case "dogecoin.providers":
            return "DOGE Providers"
        case "rpc":
            return "RPC"
        default:
            return trimmed
        }
    }

    var statusText: String {
        status.localizedTitle
    }
    
    var badgeMark: String {
        switch kind {
        case .send:
            return "OUT"
        case .receive:
            return "IN"
        }
    }
    
    var badgeColor: Color {
        switch kind {
        case .send:
            return .red
        case .receive:
            return .green
        }
    }
    
    var statusColor: Color {
        switch status {
        case .pending:
            return .orange
        case .confirmed:
            return .mint
        case .failed:
            return .red
        }
    }
    
    var amountText: String? {
        guard amount > 0 else { return nil }
        return String(format: "%.4f %@", amount, symbol)
    }

    var addressPreviewText: String {
        address
    }

    var receiptBlockNumberText: String? {
        guard let receiptBlockNumber else { return nil }
        return String(receiptBlockNumber)
    }

    var receiptEffectiveGasPriceText: String? {
        guard let receiptEffectiveGasPriceGwei else { return nil }
        return String(format: "%.3f gwei", receiptEffectiveGasPriceGwei)
    }

    var receiptNetworkFeeText: String? {
        guard let receiptNetworkFeeETH else { return nil }
        return String(format: "%.8f ETH", receiptNetworkFeeETH)
    }

    var storedFeePriorityText: String? {
        if let feePriorityRaw {
            let trimmed = feePriorityRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.capitalized
            }
        }

        if let dogecoinFeePriorityRaw {
            let trimmed = dogecoinFeePriorityRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.capitalized
            }
        }

        return nil
    }

    var storedFeeRateText: String? {
        if let feeRateDescription {
            let trimmed = feeRateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let dogecoinEstimatedFeeRateDOGEPerKB {
            return String(format: "%.4f DOGE/KB", dogecoinEstimatedFeeRateDOGEPerKB)
        }

        return nil
    }

    var storedConfirmationCountText: String? {
        if let confirmationCount {
            return "\(confirmationCount) conf"
        }

        if let dogecoinConfirmations {
            return "\(dogecoinConfirmations) conf"
        }

        return nil
    }

    var storedUsedChangeOutputText: String? {
        if let usedChangeOutput {
            return usedChangeOutput ? "Yes" : "No"
        }

        if let dogecoinUsedChangeOutput {
            return dogecoinUsedChangeOutput ? "Yes" : "No"
        }

        return nil
    }

    var rawTransactionHexText: String? {
        if let dogecoinRawTransactionHex {
            let trimmed = dogecoinRawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        guard let signedTransactionPayload,
              let signedTransactionPayloadFormat else { return nil }
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

        if let storedFeePriorityText {
            parts.append("Fee \(storedFeePriorityText)")
        }

        if let storedFeeRateText {
            parts.append(storedFeeRateText)
        }

        if let storedConfirmationCountText {
            parts.append(storedConfirmationCountText)
        }

        if let usedChangeOutput = usedChangeOutput ?? dogecoinUsedChangeOutput, kind == .send {
            parts.append(usedChangeOutput ? "change output" : "no change output")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var dogecoinConfirmationsText: String? {
        guard chainName == "Dogecoin",
              let dogecoinConfirmations else { return nil }
        return "\(dogecoinConfirmations) conf"
    }
    
    var fullTimestampText: String {
        createdAt.formatted(date: .abbreviated, time: .standard)
    }

    var transactionExplorerURL: URL? {
        guard let transactionHash, !transactionHash.isEmpty else { return nil }
        return ChainBackendRegistry.ExplorerRegistry.transactionURL(for: chainName, transactionHash: transactionHash)
    }

    var transactionExplorerLabel: String? {
        guard transactionHash != nil else { return nil }
        return ChainBackendRegistry.ExplorerRegistry.transactionLabel(for: chainName)
    }

    var rebroadcastPayload: String? {
        if let signedTransactionPayload {
            let trimmed = signedTransactionPayload.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let dogecoinRawTransactionHex {
            let trimmed = dogecoinRawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    var rebroadcastPayloadFormat: String? {
        if let signedTransactionPayloadFormat {
            let trimmed = signedTransactionPayloadFormat.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let dogecoinRawTransactionHex,
           !dogecoinRawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "dogecoin.raw_hex"
        }

        return nil
    }

    var supportsSignedRebroadcast: Bool {
        kind == .send && rebroadcastPayload != nil && rebroadcastPayloadFormat != nil
    }
}

extension PriceAlertRule {
    init(snapshot: PersistedPriceAlertRule) {
        self.init(
            id: snapshot.id,
            holdingKey: snapshot.holdingKey,
            assetName: snapshot.assetName,
            symbol: snapshot.symbol,
            chainName: snapshot.chainName,
            targetPrice: snapshot.targetPrice,
            condition: snapshot.condition,
            isEnabled: snapshot.isEnabled,
            hasTriggered: snapshot.hasTriggered
        )
    }
    
    var persistedSnapshot: PersistedPriceAlertRule {
        PersistedPriceAlertRule(
            id: id,
            holdingKey: holdingKey,
            assetName: assetName,
            symbol: symbol,
            chainName: chainName,
            targetPrice: targetPrice,
            condition: condition,
            isEnabled: isEnabled,
            hasTriggered: hasTriggered
        )
    }
}
