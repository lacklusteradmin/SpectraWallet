import Foundation

private struct WalletDerivationLayerJSONRequest: Codable {
    let chain: SeedDerivationChain
    let network: WalletDerivationNetwork
    let seedPhrase: String
    let derivationPath: String?
    let curve: WalletDerivationCurve
    let passphrase: String?
    let iterationCount: Int?
    let hmacKeyString: String?
    let requestedOutputs: [String]
}

private struct WalletDerivationLayerJSONResponse: Codable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}

enum WalletDerivationLayer {
    static func derive(
        seedPhrase: String,
        request: WalletDerivationRequest
    ) throws -> WalletDerivationResult {
        try WalletDerivationEngine.derive(seedPhrase: seedPhrase, request: request)
    }

    static func derive(
        jsonData: Data
    ) throws -> Data {
        try WalletDerivationEngine.derive(jsonData: jsonData)
    }

    static func derive(
        jsonString: String
    ) throws -> String {
        try WalletDerivationEngine.derive(jsonString: jsonString)
    }

    static func deriveAddress(
        seedPhrase: String,
        chain: SeedDerivationChain,
        network: WalletDerivationNetwork,
        derivationPath: String
    ) throws -> String {
        let requestData = try JSONEncoder().encode(
            WalletDerivationLayerJSONRequest(
                chain: chain,
                network: network,
                seedPhrase: seedPhrase,
                derivationPath: derivationPath,
                curve: WalletDerivationEngine.curve(for: chain),
                passphrase: nil,
                iterationCount: nil,
                hmacKeyString: nil,
                requestedOutputs: ["address"]
            )
        )
        let responseData = try derive(jsonData: requestData)
        let result = try JSONDecoder().decode(WalletDerivationLayerJSONResponse.self, from: responseData)
        guard let address = result.address else {
            throw WalletDerivationEngineError.emptyRequestedOutputs
        }
        return address
    }

    static func evmSeedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        switch chainName {
        case "Ethereum":
            return .ethereum
        case "Ethereum Classic":
            return .ethereumClassic
        case "Arbitrum":
            return .arbitrum
        case "BNB Chain":
            return .ethereum
        case "Avalanche":
            return .avalanche
        case "Hyperliquid":
            return .hyperliquid
        default:
            return nil
        }
    }
}
