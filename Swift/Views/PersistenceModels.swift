import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
struct PersistedCoin: Codable {
    let name: String
    let symbol: String
    let marketDataId: String
    let coinGeckoId: String
    let chainName: String
    let tokenStandard: String
    let contractAddress: String?
    let amount: Double
    let priceUsd: Double
}
struct PersistedWallet: Codable {
    let id: String
    let name: String
    let bitcoinNetworkMode: BitcoinNetworkMode
    let dogecoinNetworkMode: DogecoinNetworkMode
    let bitcoinAddress: String?
    let bitcoinXpub: String?
    let bitcoinCashAddress: String?
    let bitcoinSvAddress: String?
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
        case bitcoinXpub
        case bitcoinCashAddress
        case bitcoinSvAddress
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
        id: String, name: String, bitcoinNetworkMode: BitcoinNetworkMode = .mainnet, dogecoinNetworkMode: DogecoinNetworkMode = .mainnet, bitcoinAddress: String?, bitcoinXpub: String?, bitcoinCashAddress: String?, bitcoinSvAddress: String?, litecoinAddress: String?, dogecoinAddress: String?, ethereumAddress: String?, tronAddress: String?, solanaAddress: String?, stellarAddress: String?, xrpAddress: String?, moneroAddress: String?, cardanoAddress: String?, suiAddress: String?, aptosAddress: String?, tonAddress: String?, icpAddress: String?, nearAddress: String?, polkadotAddress: String?, seedDerivationPreset: SeedDerivationPreset, seedDerivationPaths: SeedDerivationPaths, selectedChain: String, holdings: [PersistedCoin], includeInPortfolioTotal: Bool
    ) {
        self.id = id
        self.name = name
        self.bitcoinNetworkMode = bitcoinNetworkMode
        self.dogecoinNetworkMode = dogecoinNetworkMode
        self.bitcoinAddress = bitcoinAddress
        self.bitcoinXpub = bitcoinXpub
        self.bitcoinCashAddress = bitcoinCashAddress
        self.bitcoinSvAddress = bitcoinSvAddress
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
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bitcoinNetworkMode = try container.decodeIfPresent(BitcoinNetworkMode.self, forKey: .bitcoinNetworkMode) ?? .mainnet
        dogecoinNetworkMode = try container.decodeIfPresent(DogecoinNetworkMode.self, forKey: .dogecoinNetworkMode) ?? .mainnet
        bitcoinAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinAddress)
        bitcoinXpub = try container.decodeIfPresent(String.self, forKey: .bitcoinXpub)
        bitcoinCashAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinCashAddress)
        bitcoinSvAddress = try container.decodeIfPresent(String.self, forKey: .bitcoinSvAddress)
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
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SeedDerivationPathsCodingKeys.self)
        self = SeedDerivationPaths.defaults
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
    public func encode(to encoder: Encoder) throws {
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
