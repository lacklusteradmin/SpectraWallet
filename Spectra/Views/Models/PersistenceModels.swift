import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PersistedCoin: Codable {
    let name: String
    let symbol: String
    let marketDataID: String
    let coinGeckoID: String
    let chainName: String
    let tokenStandard: String
    let contractAddress: String?
    let amount: Double
    let priceUSD: Double
}

struct PersistedWallet: Codable {
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
    let holdings: [PersistedCoin]
    let includeInPortfolioTotal: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bitcoinNetworkMode
        case dogecoinNetworkMode
        case bitcoinAddress
        case bitcoinXPub
        case bitcoinCashAddress
        case bitcoinSVAddress
        case litecoinAddress
        case dogecoinAddress
        case ethereumAddress
        case tronAddress
        case solanaAddress
        case stellarAddress
        case xrpAddress
        case moneroAddress
        case cardanoAddress
        case suiAddress
        case aptosAddress
        case tonAddress
        case icpAddress
        case nearAddress
        case polkadotAddress
        case seedDerivationPreset
        case seedDerivationPaths
        case selectedChain
        case holdings
        case includeInPortfolioTotal
    }

    init(
        id: UUID,
        name: String,
        bitcoinNetworkMode: BitcoinNetworkMode = .mainnet,
        dogecoinNetworkMode: DogecoinNetworkMode = .mainnet,
        bitcoinAddress: String?,
        bitcoinXPub: String?,
        bitcoinCashAddress: String?,
        bitcoinSVAddress: String?,
        litecoinAddress: String?,
        dogecoinAddress: String?,
        ethereumAddress: String?,
        tronAddress: String?,
        solanaAddress: String?,
        stellarAddress: String?,
        xrpAddress: String?,
        moneroAddress: String?,
        cardanoAddress: String?,
        suiAddress: String?,
        aptosAddress: String?,
        tonAddress: String?,
        icpAddress: String?,
        nearAddress: String?,
        polkadotAddress: String?,
        seedDerivationPreset: SeedDerivationPreset,
        seedDerivationPaths: SeedDerivationPaths,
        selectedChain: String,
        holdings: [PersistedCoin],
        includeInPortfolioTotal: Bool
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bitcoinNetworkMode = try container.decodeIfPresent(BitcoinNetworkMode.self, forKey: .bitcoinNetworkMode) ?? .mainnet
        dogecoinNetworkMode = try container.decodeIfPresent(DogecoinNetworkMode.self, forKey: .dogecoinNetworkMode) ?? .mainnet
        bitcoinAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinAddress)
        bitcoinXPub = try container.decodeIfPresent(String.self, forKey: .bitcoinXPub)
        bitcoinCashAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinCashAddress)
        bitcoinSVAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinSVAddress)
        litecoinAddress = try container.decodeIfPresent(String.self, forKey: .litecoinAddress)
        dogecoinAddress = try container.decodeIfPresent(String.self, forKey: .dogecoinAddress)
        ethereumAddress = try container.decodeIfPresent(String.self, forKey: .ethereumAddress)
        tronAddress = try container.decodeIfPresent(String.self, forKey: .tronAddress)
        solanaAddress = try container.decodeIfPresent(String.self, forKey: .solanaAddress)
        stellarAddress = try container.decodeIfPresent(String.self, forKey: .stellarAddress)
        xrpAddress = try container.decodeIfPresent(String.self, forKey: .xrpAddress)
        moneroAddress = try container.decodeIfPresent(String.self, forKey: .moneroAddress)
        cardanoAddress = try container.decodeIfPresent(String.self, forKey: .cardanoAddress)
        suiAddress = try container.decodeIfPresent(String.self, forKey: .suiAddress)
        aptosAddress = try container.decodeIfPresent(String.self, forKey: .aptosAddress)
        tonAddress = try container.decodeIfPresent(String.self, forKey: .tonAddress)
        icpAddress = try container.decodeIfPresent(String.self, forKey: .icpAddress)
        nearAddress = try container.decodeIfPresent(String.self, forKey: .nearAddress)
        polkadotAddress = try container.decodeIfPresent(String.self, forKey: .polkadotAddress)
        seedDerivationPreset = try container.decode(SeedDerivationPreset.self, forKey: .seedDerivationPreset)
        seedDerivationPaths = try container.decode(SeedDerivationPaths.self, forKey: .seedDerivationPaths)
        selectedChain = try container.decode(String.self, forKey: .selectedChain)
        holdings = try container.decode([PersistedCoin].self, forKey: .holdings)
        includeInPortfolioTotal = try container.decode(Bool.self, forKey: .includeInPortfolioTotal)
    }
}

struct PersistedWalletStore: Codable {
    let version: Int
    let wallets: [PersistedWallet]
    
    static let currentVersion = 5
}

struct PersistedPriceAlertRule: Codable {
    let id: UUID
    let holdingKey: String
    let assetName: String
    let symbol: String
    let chainName: String
    let targetPrice: Double
    let condition: PriceAlertCondition
    let isEnabled: Bool
    let hasTriggered: Bool
}

struct PersistedPriceAlertStore: Codable {
    let version: Int
    let alerts: [PersistedPriceAlertRule]
    
    static let currentVersion = 1
}

struct PersistedAddressBookEntry: Codable {
    let id: UUID
    let name: String
    let chainName: String
    let address: String
    let note: String
}

struct PersistedAddressBookStore: Codable {
    let version: Int
    let entries: [PersistedAddressBookEntry]

    static let currentVersion = 1
}

struct PersistedTransactionRecord: Codable, Equatable {
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
    
    enum CodingKeys: String, CodingKey {
        case id
        case walletID
        case kind
        case status
        case walletName
        case assetName
        case symbol
        case chainName
        case amount
        case address
        case transactionHash
        case ethereumNonce
        case receiptBlockNumber
        case receiptGasUsed
        case receiptEffectiveGasPriceGwei
        case receiptNetworkFeeETH
        case feePriorityRaw
        case feeRateDescription
        case confirmationCount
        case dogecoinConfirmedNetworkFeeDOGE
        case dogecoinConfirmations
        case dogecoinFeePriorityRaw
        case dogecoinEstimatedFeeRateDOGEPerKB
        case usedChangeOutput
        case dogecoinUsedChangeOutput
        case sourceDerivationPath
        case changeDerivationPath
        case sourceAddress
        case changeAddress
        case dogecoinRawTransactionHex
        case signedTransactionPayload
        case signedTransactionPayloadFormat
        case failureReason
        case transactionHistorySource
        case createdAt
    }
    
    init(
        id: UUID,
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
        createdAt: Date
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
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(TransactionKind.self, forKey: .kind)
        
        id = try container.decode(UUID.self, forKey: .id)
        walletID = try container.decodeIfPresent(UUID.self, forKey: .walletID)
        self.kind = kind
        status = try container.decodeIfPresent(TransactionStatus.self, forKey: .status)
            ?? (kind == .receive ? .pending : .confirmed)
        walletName = try container.decode(String.self, forKey: .walletName)
        assetName = try container.decode(String.self, forKey: .assetName)
        symbol = try container.decode(String.self, forKey: .symbol)
        chainName = try container.decode(String.self, forKey: .chainName)
        amount = try container.decode(Double.self, forKey: .amount)
        address = try container.decode(String.self, forKey: .address)
        transactionHash = try container.decodeIfPresent(String.self, forKey: .transactionHash)
        ethereumNonce = try container.decodeIfPresent(Int.self, forKey: .ethereumNonce)
        receiptBlockNumber = try container.decodeIfPresent(Int.self, forKey: .receiptBlockNumber)
        receiptGasUsed = try container.decodeIfPresent(String.self, forKey: .receiptGasUsed)
        receiptEffectiveGasPriceGwei = try container.decodeIfPresent(Double.self, forKey: .receiptEffectiveGasPriceGwei)
        receiptNetworkFeeETH = try container.decodeIfPresent(Double.self, forKey: .receiptNetworkFeeETH)
        feePriorityRaw = try container.decodeIfPresent(String.self, forKey: .feePriorityRaw)
        feeRateDescription = try container.decodeIfPresent(String.self, forKey: .feeRateDescription)
        confirmationCount = try container.decodeIfPresent(Int.self, forKey: .confirmationCount)
        dogecoinConfirmedNetworkFeeDOGE = try container.decodeIfPresent(Double.self, forKey: .dogecoinConfirmedNetworkFeeDOGE)
        dogecoinConfirmations = try container.decodeIfPresent(Int.self, forKey: .dogecoinConfirmations)
        dogecoinFeePriorityRaw = try container.decodeIfPresent(String.self, forKey: .dogecoinFeePriorityRaw)
        dogecoinEstimatedFeeRateDOGEPerKB = try container.decodeIfPresent(Double.self, forKey: .dogecoinEstimatedFeeRateDOGEPerKB)
        usedChangeOutput = try container.decodeIfPresent(Bool.self, forKey: .usedChangeOutput)
        dogecoinUsedChangeOutput = try container.decodeIfPresent(Bool.self, forKey: .dogecoinUsedChangeOutput)
        sourceDerivationPath = try container.decodeIfPresent(String.self, forKey: .sourceDerivationPath)
        changeDerivationPath = try container.decodeIfPresent(String.self, forKey: .changeDerivationPath)
        sourceAddress = try container.decodeIfPresent(String.self, forKey: .sourceAddress)
        changeAddress = try container.decodeIfPresent(String.self, forKey: .changeAddress)
        dogecoinRawTransactionHex = try container.decodeIfPresent(String.self, forKey: .dogecoinRawTransactionHex)
        signedTransactionPayload = try container.decodeIfPresent(String.self, forKey: .signedTransactionPayload)
        signedTransactionPayloadFormat = try container.decodeIfPresent(String.self, forKey: .signedTransactionPayloadFormat)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        transactionHistorySource = try container.decodeIfPresent(String.self, forKey: .transactionHistorySource)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

private enum SeedDerivationPathsCodingKeys: String, CodingKey {
    case isCustomEnabled
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case dogecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case avalanche
    case hyperliquid
    case tron
    case solana
    case stellar
    case xrp
    case cardano
    case sui
    case aptos
    case ton
    case internetComputer
    case near
    case polkadot
}

extension SeedDerivationPaths: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SeedDerivationPathsCodingKeys.self)
        isCustomEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCustomEnabled) ?? false
        bitcoin = try container.decodeIfPresent(String.self, forKey: .bitcoin) ?? SeedDerivationChain.bitcoin.defaultPath
        bitcoinCash = try container.decodeIfPresent(String.self, forKey: .bitcoinCash) ?? SeedDerivationChain.bitcoinCash.defaultPath
        bitcoinSV = try container.decodeIfPresent(String.self, forKey: .bitcoinSV) ?? SeedDerivationChain.bitcoinSV.defaultPath
        litecoin = try container.decodeIfPresent(String.self, forKey: .litecoin) ?? SeedDerivationChain.litecoin.defaultPath
        dogecoin = try container.decodeIfPresent(String.self, forKey: .dogecoin) ?? SeedDerivationChain.dogecoin.defaultPath
        ethereum = try container.decodeIfPresent(String.self, forKey: .ethereum) ?? SeedDerivationChain.ethereum.defaultPath
        ethereumClassic = try container.decodeIfPresent(String.self, forKey: .ethereumClassic) ?? SeedDerivationChain.ethereumClassic.defaultPath
        arbitrum = try container.decodeIfPresent(String.self, forKey: .arbitrum) ?? SeedDerivationChain.arbitrum.defaultPath
        optimism = try container.decodeIfPresent(String.self, forKey: .optimism) ?? SeedDerivationChain.optimism.defaultPath
        avalanche = try container.decodeIfPresent(String.self, forKey: .avalanche) ?? SeedDerivationChain.avalanche.defaultPath
        hyperliquid = try container.decodeIfPresent(String.self, forKey: .hyperliquid) ?? SeedDerivationChain.hyperliquid.defaultPath
        tron = try container.decodeIfPresent(String.self, forKey: .tron) ?? SeedDerivationChain.tron.defaultPath
        solana = try container.decodeIfPresent(String.self, forKey: .solana) ?? SeedDerivationChain.solana.defaultPath
        stellar = try container.decodeIfPresent(String.self, forKey: .stellar) ?? SeedDerivationChain.stellar.defaultPath
        xrp = try container.decodeIfPresent(String.self, forKey: .xrp) ?? SeedDerivationChain.xrp.defaultPath
        cardano = try container.decodeIfPresent(String.self, forKey: .cardano) ?? SeedDerivationChain.cardano.defaultPath
        sui = try container.decodeIfPresent(String.self, forKey: .sui) ?? SeedDerivationChain.sui.defaultPath
        aptos = try container.decodeIfPresent(String.self, forKey: .aptos) ?? SeedDerivationChain.aptos.defaultPath
        ton = try container.decodeIfPresent(String.self, forKey: .ton) ?? SeedDerivationChain.ton.defaultPath
        internetComputer = try container.decodeIfPresent(String.self, forKey: .internetComputer) ?? SeedDerivationChain.internetComputer.defaultPath
        near = try container.decodeIfPresent(String.self, forKey: .near) ?? SeedDerivationChain.near.defaultPath
        polkadot = try container.decodeIfPresent(String.self, forKey: .polkadot) ?? SeedDerivationChain.polkadot.defaultPath
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SeedDerivationPathsCodingKeys.self)
        try container.encode(isCustomEnabled, forKey: .isCustomEnabled)
        try container.encode(bitcoin, forKey: .bitcoin)
        try container.encode(bitcoinCash, forKey: .bitcoinCash)
        try container.encode(bitcoinSV, forKey: .bitcoinSV)
        try container.encode(litecoin, forKey: .litecoin)
        try container.encode(dogecoin, forKey: .dogecoin)
        try container.encode(ethereum, forKey: .ethereum)
        try container.encode(ethereumClassic, forKey: .ethereumClassic)
        try container.encode(arbitrum, forKey: .arbitrum)
        try container.encode(optimism, forKey: .optimism)
        try container.encode(avalanche, forKey: .avalanche)
        try container.encode(hyperliquid, forKey: .hyperliquid)
        try container.encode(tron, forKey: .tron)
        try container.encode(solana, forKey: .solana)
        try container.encode(stellar, forKey: .stellar)
        try container.encode(xrp, forKey: .xrp)
        try container.encode(cardano, forKey: .cardano)
        try container.encode(sui, forKey: .sui)
        try container.encode(aptos, forKey: .aptos)
        try container.encode(ton, forKey: .ton)
        try container.encode(internetComputer, forKey: .internetComputer)
        try container.encode(near, forKey: .near)
        try container.encode(polkadot, forKey: .polkadot)
    }
}
