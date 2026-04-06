import Foundation

enum WalletSendCapability: String, CaseIterable {
    case signing
    case planning
    case broadcast
    case feeEstimation
}

enum WalletSendLayer {
    static func capabilities(for chainName: String) -> Set<WalletSendCapability> {
        var capabilities: Set<WalletSendCapability> = [.broadcast]

        switch chainName {
        case "Bitcoin", "Bitcoin Cash", "Bitcoin SV", "Litecoin", "Dogecoin":
            capabilities.formUnion([.signing, .planning, .feeEstimation])
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid":
            capabilities.formUnion([.signing, .planning, .feeEstimation])
        case "Tron", "Solana", "Cardano", "XRP Ledger", "Stellar", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot":
            capabilities.formUnion([.signing, .feeEstimation])
        case "Monero":
            capabilities.formUnion([.signing, .planning])
        default:
            break
        }

        return capabilities
    }

    static func broadcastEndpoints(for chainName: String) -> [AppEndpointRecord] {
        ChainProviderCatalog.broadcastEndpoints(for: chainName)
    }

    static func supportsSending(on chainName: String) -> Bool {
        !broadcastEndpoints(for: chainName).isEmpty || capabilities(for: chainName).contains(.signing)
    }
}
