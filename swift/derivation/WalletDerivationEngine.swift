import Foundation
struct WalletDerivationRequestedOutputs: OptionSet, Sendable {
    let rawValue: Int
    nonisolated(unsafe) static let address = WalletDerivationRequestedOutputs(rawValue: 1 << 0)
    nonisolated(unsafe) static let publicKey = WalletDerivationRequestedOutputs(rawValue: 1 << 1)
    nonisolated(unsafe) static let privateKey = WalletDerivationRequestedOutputs(rawValue: 1 << 2)
    nonisolated(unsafe) static let all: WalletDerivationRequestedOutputs = [.address, .publicKey, .privateKey]
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
private struct WalletDerivationQuery {
    let chain: SeedDerivationChain
    let network: WalletDerivationNetwork
    let derivationPath: String?
    let curve: WalletDerivationCurve
    let passphrase: String?
    let iterationCount: Int?
    let hmacKeyString: String?
    let requestedOutputs: WalletDerivationRequestedOutputs
    init(
        chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String?, curve: WalletDerivationCurve, passphrase: String? = nil, iterationCount: Int? = nil, hmacKeyString: String? = nil, requestedOutputs: WalletDerivationRequestedOutputs = .all
    ) {
        self.chain = chain
        self.network = network
        self.derivationPath = derivationPath
        self.curve = curve
        self.passphrase = passphrase
        self.iterationCount = iterationCount
        self.hmacKeyString = hmacKeyString
        self.requestedOutputs = requestedOutputs
    }
    init(request: WalletDerivationRequest) {
        self.init(
            chain: request.chain, network: request.network, derivationPath: request.derivationPath, curve: request.curve, passphrase: request.passphrase, iterationCount: request.iterationCount, hmacKeyString: request.hmacKeyString, requestedOutputs: request.requestedOutputs
        )
    }
}
struct WalletDerivationResult {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}
struct WalletDerivationRequest {
    let chain: SeedDerivationChain
    let network: WalletDerivationNetwork
    let derivationPath: String?
    let curve: WalletDerivationCurve
    let passphrase: String?
    let iterationCount: Int?
    let hmacKeyString: String?
    let requestedOutputs: WalletDerivationRequestedOutputs
    init(
        chain: SeedDerivationChain, network: WalletDerivationNetwork, derivationPath: String?, curve: WalletDerivationCurve, passphrase: String? = nil, iterationCount: Int? = nil, hmacKeyString: String? = nil, requestedOutputs: WalletDerivationRequestedOutputs = .all
    ) {
        self.chain = chain
        self.network = network
        self.derivationPath = derivationPath
        self.curve = curve
        self.passphrase = passphrase
        self.iterationCount = iterationCount
        self.hmacKeyString = hmacKeyString
        self.requestedOutputs = requestedOutputs
    }
}
private struct WalletDerivationJSONRequestPayload: Codable {
    let chain: SeedDerivationChain
    let network: WalletDerivationNetwork
    let seedPhrase: String
    let derivationPath: String?
    let curve: WalletDerivationCurve
    let passphrase: String?
    let iterationCount: Int?
    let hmacKeyString: String?
    let requestedOutputs: [String]
    var query: WalletDerivationQuery {
        WalletDerivationQuery(
            chain: chain, network: network, derivationPath: derivationPath, curve: curve, passphrase: passphrase, iterationCount: iterationCount, hmacKeyString: hmacKeyString, requestedOutputs: WalletDerivationRequestedOutputs(jsonValues: requestedOutputs)
        )
    }
}
private struct WalletDerivationJSONResponsePayload: Codable {
    let address: String?
    let publicKeyHex: String?
    let privateKeyHex: String?
}
enum WalletDerivationEngineError: LocalizedError {
    case emptyRequestedOutputs
    case unsupportedNetwork(chain: SeedDerivationChain, network: WalletDerivationNetwork)
    case unsupportedAddressCurve(chain: SeedDerivationChain, expected: WalletDerivationCurve, provided: WalletDerivationCurve)
    case unsupportedIterationCount(Int)
    case unsupportedHMACKeyString(String)
    case unsupportedBitcoinPurpose(String)
    case invalidJSONRequest
    var errorDescription: String? {
        switch self {
        case .emptyRequestedOutputs: return "At least one derivation output must be requested."
        case .unsupportedNetwork(let chain, let network): return "\(network.rawValue) is not supported for \(chain.rawValue)."
        case .unsupportedAddressCurve(let chain, let expected, let provided): return "\(chain.rawValue) addresses require \(expected.rawValue), not \(provided.rawValue)."
        case .unsupportedIterationCount(let count): return "Custom iteration count \(count) is not supported by the current derivation engine."
        case .unsupportedHMACKeyString(let key): return "Custom HMAC key string '\(key)' is not supported by the current derivation engine."
        case .unsupportedBitcoinPurpose(let path): return "Unsupported Bitcoin derivation purpose for path \(path)."
        case .invalidJSONRequest: return "Invalid derivation JSON request."
        }}
}
enum WalletDerivationEngine {
    static func derive(seedPhrase: String, request: WalletDerivationRequest) throws -> WalletDerivationResult {
        let query = WalletDerivationQuery(request: request)
        return try derive(seedPhrase: seedPhrase, query: query)
    }
    static func derive(jsonData: Data) throws -> Data {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(WalletDerivationJSONRequestPayload.self, from: jsonData)
        let result = try derive(seedPhrase: payload.seedPhrase, query: payload.query)
        return try JSONEncoder().encode(
            WalletDerivationJSONResponsePayload(
                address: result.address, publicKeyHex: result.publicKeyHex, privateKeyHex: result.privateKeyHex
            )
        )
    }
    static func derive(jsonString: String) throws -> String {
        guard let jsonData = jsonString.data(using: .utf8) else { throw WalletDerivationEngineError.invalidJSONRequest }
        let responseData = try derive(jsonData: jsonData)
        guard let responseString = String(data: responseData, encoding: .utf8) else { throw WalletDerivationEngineError.invalidJSONRequest }
        return responseString
    }
    private static func derive(seedPhrase: String, query: WalletDerivationQuery) throws -> WalletDerivationResult {
        guard !query.requestedOutputs.isEmpty else { throw WalletDerivationEngineError.emptyRequestedOutputs }
        try validateAdvancedOptions(query)
        return try deriveViaRust(seedPhrase: seedPhrase, query: query)
    }
    private static func deriveViaRust(seedPhrase: String, query: WalletDerivationQuery) throws -> WalletDerivationResult {
        let request = try WalletRustDerivationBridge.makeRequestModel(
            chain: query.chain, network: query.network, seedPhrase: seedPhrase, derivationPath: query.derivationPath, passphrase: query.passphrase, iterationCount: query.iterationCount, hmacKeyString: query.hmacKeyString, requestedOutputs: query.requestedOutputs
        )
        let response = try WalletRustDerivationBridge.derive(request)
        return WalletDerivationResult(
            address: response.address, publicKeyHex: response.publicKeyHex, privateKeyHex: response.privateKeyHex
        )
    }
    static func curve(for chain: SeedDerivationChain) -> WalletDerivationCurve {
        switch chain {
        case .bitcoin, .bitcoinCash, .bitcoinSV, .litecoin, .dogecoin, .ethereum, .ethereumClassic, .arbitrum, .optimism, .avalanche, .hyperliquid, .tron, .xrp: return .secp256k1
        case .solana, .stellar, .cardano, .sui, .aptos, .ton, .internetComputer, .near, .polkadot: return .ed25519
        }}
    private static func validateAdvancedOptions(_ query: WalletDerivationQuery) throws {
        if let iterationCount = query.iterationCount, iterationCount != 2048 { throw WalletDerivationEngineError.unsupportedIterationCount(iterationCount) }
        if let hmacKeyString = query.hmacKeyString? .trimmingCharacters(in: .whitespacesAndNewlines), !hmacKeyString.isEmpty { throw WalletDerivationEngineError.unsupportedHMACKeyString(hmacKeyString) }}
}
