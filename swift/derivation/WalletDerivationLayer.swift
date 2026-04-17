import Foundation
nonisolated struct WalletDerivationRequestedOutputs: OptionSet, Sendable {
    let rawValue: Int
    static let address = WalletDerivationRequestedOutputs(rawValue: 1 << 0)
    static let publicKey = WalletDerivationRequestedOutputs(rawValue: 1 << 1)
    static let privateKey = WalletDerivationRequestedOutputs(rawValue: 1 << 2)
    static let all: WalletDerivationRequestedOutputs = [.address, .publicKey, .privateKey]
}
enum WalletDerivationCurve: String, Codable {
    case secp256k1
    case ed25519
}
enum WalletDerivationNetwork: String, Codable {
    case mainnet
    case testnet
    case testnet4
    case signet
}
enum WalletDerivationError: LocalizedError {
    case emptyRequestedOutputs
    case unsupportedIterationCount(Int)
    case unsupportedHMACKeyString(String)
    case invalidJSONRequest
    var errorDescription: String? {
        switch self {
        case .emptyRequestedOutputs: return "At least one derivation output must be requested."
        case .unsupportedIterationCount(let count): return "Custom iteration count \(count) is not supported by the current derivation engine."
        case .unsupportedHMACKeyString(let key): return "Custom HMAC key string '\(key)' is not supported by the current derivation engine."
        case .invalidJSONRequest: return "Invalid derivation JSON request."
        }}
}
enum WalletDerivationLayer {
    static func derive(
        seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork = .mainnet,
        derivationPath: String? = nil, requestedOutputs: WalletDerivationRequestedOutputs = .all
    ) throws -> WalletRustDerivationResponseModel {
        guard !requestedOutputs.isEmpty else { throw WalletDerivationError.emptyRequestedOutputs }
        let request = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain, network: network, seedPhrase: seedPhrase, derivationPath: derivationPath,
            passphrase: nil, iterationCount: nil, hmacKeyString: nil, requestedOutputs: requestedOutputs
        )
        return try WalletRustDerivationBridge.derive(request)
    }
    static func deriveAddress(seedPhrase: String, chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String) throws -> String {
        let result = try derive(seedPhrase: seedPhrase, chain: chain, network: network, derivationPath: derivationPath, requestedOutputs: .address)
        guard let address = result.address else { throw WalletDerivationError.emptyRequestedOutputs }
        return address
    }
    static func derive(jsonData: Data) throws -> Data {
        let payload = try JSONDecoder().decode(DerivationJSONRequestPayload.self, from: jsonData)
        try validateAdvancedOptions(iterationCount: payload.iterationCount, hmacKeyString: payload.hmacKeyString)
        let request = try WalletRustDerivationBridge.makeRequestModel(
            chain: payload.chain, network: payload.network, seedPhrase: payload.seedPhrase,
            derivationPath: payload.derivationPath, passphrase: payload.passphrase,
            iterationCount: payload.iterationCount, hmacKeyString: payload.hmacKeyString,
            requestedOutputs: WalletDerivationRequestedOutputs(jsonValues: payload.requestedOutputs)
        )
        let result = try WalletRustDerivationBridge.derive(request)
        return try JSONEncoder().encode(
            DerivationJSONResponsePayload(address: result.address, publicKeyHex: result.publicKeyHex, privateKeyHex: result.privateKeyHex)
        )
    }
    static func derive(jsonString: String) throws -> String {
        guard let jsonData = jsonString.data(using: .utf8) else { throw WalletDerivationError.invalidJSONRequest }
        let responseData = try derive(jsonData: jsonData)
        guard let responseString = String(data: responseData, encoding: .utf8) else { throw WalletDerivationError.invalidJSONRequest }
        return responseString
    }
    static func evmSeedDerivationChain(for chainName: String) -> SeedDerivationChain? {
        switch chainName {
        case "Ethereum": return .ethereum
        case "Ethereum Classic": return .ethereumClassic
        case "Arbitrum": return .arbitrum
        case "BNB Chain": return .ethereum
        case "Avalanche": return .avalanche
        case "Hyperliquid": return .hyperliquid
        default: return nil
        }}
    private static func validateAdvancedOptions(iterationCount: Int?, hmacKeyString: String?) throws {
        if let iterationCount, iterationCount != 2048 { throw WalletDerivationError.unsupportedIterationCount(iterationCount) }
        if let hmacKeyString = hmacKeyString?.trimmingCharacters(in: .whitespacesAndNewlines), !hmacKeyString.isEmpty { throw WalletDerivationError.unsupportedHMACKeyString(hmacKeyString) }
    }
}
private struct DerivationJSONRequestPayload: Codable {
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
private struct DerivationJSONResponsePayload: Codable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}
