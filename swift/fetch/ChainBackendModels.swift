import Foundation
typealias ChainIntegrationState = AppCoreChainIntegrationState
struct ChainBackendRecord {
    let chainName: String
    let supportedSymbols: [String]
    let integrationState: ChainIntegrationState
    let supportsSeedImport: Bool
    let supportsBalanceRefresh: Bool
    let supportsReceiveAddress: Bool
    let supportsSend: Bool
}
enum AppChainID: String, CaseIterable, Identifiable, Decodable {
    case bitcoin
    case bitcoinCash
    case bitcoinSV
    case litecoin
    case dogecoin
    case ethereum
    case ethereumClassic
    case arbitrum
    case optimism
    case bnb
    case avalanche
    case hyperliquid
    case polygon
    case base
    case linea
    case scroll
    case blast
    case mantle
    case tron
    case solana
    case cardano
    case xrp
    case stellar
    case monero
    case sui
    case aptos
    case ton
    case icp
    case near
    case polkadot
    var id: String { rawValue }
}
struct AppChainDescriptor: Identifiable, Decodable {
    let id: AppChainID
    let chainName: String
    let shortLabel: String
    let nativeSymbol: String
    let searchKeywords: [String]
    let supportsDiagnostics: Bool
    let supportsEndpointCatalog: Bool
    let isEVM: Bool
    var title: String {
        String(
            format: AppLocalization.string("%@ Diagnostics"), locale: AppLocalization.locale, chainName
        )
    }
}
struct ChainBroadcastProviderOption: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
}
