import Foundation

// MARK: - Frozen chain ID table (mirrors service.rs — do not reorder)

enum SpectraChainID {
    static let bitcoin:          UInt32 = 0
    static let ethereum:         UInt32 = 1
    static let solana:           UInt32 = 2
    static let dogecoin:         UInt32 = 3
    static let xrp:              UInt32 = 4
    static let litecoin:         UInt32 = 5
    static let bitcoinCash:      UInt32 = 6
    static let tron:             UInt32 = 7
    static let stellar:          UInt32 = 8
    static let cardano:          UInt32 = 9
    static let polkadot:         UInt32 = 10
    static let arbitrum:         UInt32 = 11
    static let optimism:         UInt32 = 12
    static let avalanche:        UInt32 = 13
    static let sui:              UInt32 = 14
    static let aptos:            UInt32 = 15
    static let ton:              UInt32 = 16
    static let near:             UInt32 = 17
    static let icp:              UInt32 = 18
    static let monero:           UInt32 = 19
    static let base:             UInt32 = 20
    static let ethereumClassic:  UInt32 = 21

    // Logical offsets for secondary endpoint bundles (mirrors service.rs)
    static let subscaOffset:  UInt32 = 100   // Polkadot Subscan
    static let icOffset:      UInt32 = 100   // ICP Rosetta
    static let explorerOffset: UInt32 = 200  // Etherscan-compatible explorers

    static func id(for chainName: String) -> UInt32? {
        chainNameTable[chainName]
    }

    private static let chainNameTable: [String: UInt32] = [
        "Bitcoin":            bitcoin,
        "Ethereum":           ethereum,
        "Solana":             solana,
        "Dogecoin":           dogecoin,
        "XRP Ledger":         xrp,
        "Litecoin":           litecoin,
        "Bitcoin Cash":       bitcoinCash,
        "Tron":               tron,
        "Stellar":            stellar,
        "Cardano":            cardano,
        "Polkadot":           polkadot,
        "Arbitrum":           arbitrum,
        "Optimism":           optimism,
        "Avalanche":          avalanche,
        "Sui":                sui,
        "Aptos":              aptos,
        "TON":                ton,
        "NEAR":               near,
        "Internet Computer":  icp,
        "Monero":             monero,
        "Base":               base,
        "Ethereum Classic":   ethereumClassic,
    ]
}

// MARK: - Wire model (matches ChainEndpoints in service.rs)

private struct ChainEndpointsPayload: Encodable {
    let chainId: UInt32
    let endpoints: [String]
    let apiKey: String?

    enum CodingKeys: String, CodingKey {
        case chainId   = "chain_id"
        case endpoints
        case apiKey    = "api_key"
    }
}

// MARK: - WalletServiceBridge

/// Thread-safe actor that owns the Rust WalletService instance.
/// All async chain operations go through this actor.
actor WalletServiceBridge {

    static let shared = WalletServiceBridge()

    // Lazily initialised on first use.
    private var _service: WalletService?

    // MARK: Service access

    private func service() throws -> WalletService {
        if let existing = _service { return existing }
        let endpointsJSON = Self.buildEndpointsJSON()
        let svc = try WalletService(endpointsJson: endpointsJSON)
        _service = svc
        return svc
    }

    /// Call after the user changes endpoint preferences so the Rust layer
    /// picks up the new URLs without an app restart.
    func refreshEndpoints() async throws {
        let json = Self.buildEndpointsJSON()
        try await service().updateEndpoints(endpointsJson: json)
    }

    // MARK: Balance

    /// Returns the raw JSON string from Rust (chain-specific balance struct).
    func fetchBalanceJSON(chainId: UInt32, address: String) async throws -> String {
        try await service().fetchBalance(chainId: chainId, address: address)
    }

    func fetchBalanceJSON(chainName: String, address: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await fetchBalanceJSON(chainId: chainId, address: address)
    }

    // MARK: History

    func fetchHistoryJSON(chainId: UInt32, address: String) async throws -> String {
        try await service().fetchHistory(chainId: chainId, address: address)
    }

    func fetchHistoryJSON(chainName: String, address: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await fetchHistoryJSON(chainId: chainId, address: address)
    }

    // MARK: Sign & Send

    /// `paramsJson` is a chain-specific JSON object (see service.rs for field names).
    func signAndSend(chainId: UInt32, paramsJson: String) async throws -> String {
        try await service().signAndSend(chainId: chainId, paramsJson: paramsJson)
    }

    func signAndSend(chainName: String, paramsJson: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }

    // MARK: Fee estimate

    func fetchFeeEstimateJSON(chainId: UInt32) async throws -> String {
        try await service().fetchFeeEstimate(chainId: chainId)
    }

    func fetchFeeEstimateJSON(chainName: String) async throws -> String {
        guard let chainId = SpectraChainID.id(for: chainName) else {
            throw WalletServiceBridgeError.unsupportedChain(chainName)
        }
        return try await fetchFeeEstimateJSON(chainId: chainId)
    }
}

// MARK: - Derivation + send pipeline

extension WalletServiceBridge {

    /// Derive the signing key for `chain` from `seedPhrase` + `derivationPath`,
    /// then call `sign_and_send` on the Rust WalletService.
    ///
    /// `paramsBuilder` receives the derived `privateKeyHex` (and optional
    /// `publicKeyHex`) and must return the chain-specific params JSON string.
    func signAndSendWithDerivation(
        chainId: UInt32,
        seedPhrase: String,
        chain: SeedDerivationChain,
        derivationPath: String,
        paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String?) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain,
            network: .mainnet,
            seedPhrase: seedPhrase,
            derivationPath: derivationPath,
            passphrase: nil,
            iterationCount: nil,
            hmacKeyString: nil,
            requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex else {
            throw WalletServiceBridgeError.serviceInit("derivation did not return private key for chain \(chainId)")
        }
        let paramsJson = paramsBuilder(privKeyHex, derived.publicKeyHex)
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }

    /// Convenience overload that also derives and passes the public key.
    func signAndSendWithDerivationAndPubKey(
        chainId: UInt32,
        seedPhrase: String,
        chain: SeedDerivationChain,
        derivationPath: String,
        paramsBuilder: (_ privateKeyHex: String, _ publicKeyHex: String) -> String
    ) async throws -> String {
        let requestModel = try WalletRustDerivationBridge.makeRequestModel(
            chain: chain,
            network: .mainnet,
            seedPhrase: seedPhrase,
            derivationPath: derivationPath,
            passphrase: nil,
            iterationCount: nil,
            hmacKeyString: nil,
            requestedOutputs: [.address, .publicKey, .privateKey]
        )
        let derived = try WalletRustDerivationBridge.derive(requestModel)
        guard let privKeyHex = derived.privateKeyHex,
              let pubKeyHex  = derived.publicKeyHex else {
            throw WalletServiceBridgeError.serviceInit("derivation did not return key material for chain \(chainId)")
        }
        let paramsJson = paramsBuilder(privKeyHex, pubKeyHex)
        return try await signAndSend(chainId: chainId, paramsJson: paramsJson)
    }
}

// MARK: - Typed convenience helpers

extension WalletServiceBridge {

    // These decode the JSON returned by Rust into typed Swift values.
    // Add more as the UI needs them.

    func fetchSolanaBalance(address: String) async throws -> SolanaBalanceResponse {
        let json = try await fetchBalanceJSON(chainId: SpectraChainID.solana, address: address)
        return try JSONDecoder().decode(SolanaBalanceResponse.self, from: Data(json.utf8))
    }

    func fetchNearBalance(address: String) async throws -> NearBalanceResponse {
        let json = try await fetchBalanceJSON(chainId: SpectraChainID.near, address: address)
        return try JSONDecoder().decode(NearBalanceResponse.self, from: Data(json.utf8))
    }
}

// MARK: - Response types (mirror Rust structs)

struct SolanaBalanceResponse: Decodable {
    let lamports: UInt64
    let solDisplay: String
    enum CodingKeys: String, CodingKey {
        case lamports
        case solDisplay = "sol_display"
    }
}

struct NearBalanceResponse: Decodable {
    let yoctoNear: String
    let nearDisplay: String
    enum CodingKeys: String, CodingKey {
        case yoctoNear  = "yocto_near"
        case nearDisplay = "near_display"
    }
}

// MARK: - Error

enum WalletServiceBridgeError: LocalizedError {
    case unsupportedChain(String)
    case serviceInit(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let name):
            return "WalletServiceBridge: chain '\(name)' has no Rust chain ID mapping."
        case .serviceInit(let msg):
            return "WalletServiceBridge: failed to initialise WalletService — \(msg)"
        }
    }
}

// MARK: - Endpoint catalog builder

private extension WalletServiceBridge {

    /// Assembles the JSON array of ChainEndpoints that Rust WalletService expects.
    /// Reads from the existing WalletRustEndpointCatalogBridge so endpoint
    /// preferences configured elsewhere in the app are respected.
    static func buildEndpointsJSON() -> String {
        var payloads: [ChainEndpointsPayload] = []

        payloads += rpcPayloads(chainId: SpectraChainID.bitcoin,         chainName: "Bitcoin")
        payloads += evmPayloads(chainId: SpectraChainID.ethereum,        chainName: "Ethereum")
        payloads += rpcPayloads(chainId: SpectraChainID.solana,          chainName: "Solana")
        payloads += rpcPayloads(chainId: SpectraChainID.dogecoin,        chainName: "Dogecoin")
        payloads += rpcPayloads(chainId: SpectraChainID.xrp,             chainName: "XRP Ledger")
        payloads += rpcPayloads(chainId: SpectraChainID.litecoin,        chainName: "Litecoin")
        payloads += rpcPayloads(chainId: SpectraChainID.bitcoinCash,     chainName: "Bitcoin Cash")
        payloads += rpcPayloads(chainId: SpectraChainID.tron,            chainName: "Tron")
        payloads += rpcPayloads(chainId: SpectraChainID.stellar,         chainName: "Stellar")
        payloads += rpcPayloads(chainId: SpectraChainID.cardano,         chainName: "Cardano")
        payloads += rpcPayloads(chainId: SpectraChainID.polkadot,        chainName: "Polkadot")
        payloads += evmPayloads(chainId: SpectraChainID.arbitrum,        chainName: "Arbitrum")
        payloads += evmPayloads(chainId: SpectraChainID.optimism,        chainName: "Optimism")
        payloads += evmPayloads(chainId: SpectraChainID.avalanche,       chainName: "Avalanche")
        payloads += rpcPayloads(chainId: SpectraChainID.sui,             chainName: "Sui")
        payloads += rpcPayloads(chainId: SpectraChainID.aptos,           chainName: "Aptos")
        payloads += rpcPayloads(chainId: SpectraChainID.ton,             chainName: "TON")
        payloads += rpcPayloads(chainId: SpectraChainID.near,            chainName: "NEAR")
        payloads += rpcPayloads(chainId: SpectraChainID.icp,             chainName: "Internet Computer")
        payloads += rpcPayloads(chainId: SpectraChainID.monero,          chainName: "Monero")
        payloads += evmPayloads(chainId: SpectraChainID.base,            chainName: "Base")
        payloads += evmPayloads(chainId: SpectraChainID.ethereumClassic, chainName: "Ethereum Classic")

        // Subscan secondary endpoints for Polkadot (chain_id 110).
        payloads += explorerPayloads(
            chainId: SpectraChainID.polkadot + SpectraChainID.subscaOffset,
            chainName: "Polkadot"
        )

        // ICP Rosetta secondary endpoints (chain_id 118).
        payloads += explorerPayloads(
            chainId: SpectraChainID.icp + SpectraChainID.icOffset,
            chainName: "Internet Computer"
        )

        // Explorer/indexer endpoints (chain_id = 200 + primary chain_id).
        let explorerChains: [(UInt32, String)] = [
            (SpectraChainID.ethereum,        "Ethereum"),
            (SpectraChainID.tron,            "Tron"),
            (SpectraChainID.arbitrum,        "Arbitrum"),
            (SpectraChainID.optimism,        "Optimism"),
            (SpectraChainID.avalanche,       "Avalanche"),
            (SpectraChainID.near,            "NEAR"),
            (SpectraChainID.base,            "Base"),
            (SpectraChainID.ethereumClassic, "Ethereum Classic"),
        ]
        for (primaryId, chainName) in explorerChains {
            payloads += explorerPayloads(
                chainId: SpectraChainID.explorerOffset + primaryId,
                chainName: chainName
            )
        }

        guard
            let data = try? JSONEncoder().encode(payloads),
            let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    // MARK: Endpoint helpers

    /// Fetches RPC/balance endpoint records for a chain and wraps them
    /// in a ChainEndpointsPayload. Falls back to an empty array on error.
    static func rpcPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (
            try? WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName,
                roles: [.rpc, .balance, .backend],
                settingsVisibleOnly: false
            )
        )?.map(\.endpoint) ?? []

        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }

    /// Uses the dedicated EVM RPC helper (returns only RPC URLs, no explorer).
    static func evmPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.evmRPCEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }

    /// Fetches explorer / indexer supplemental endpoints for a chain.
    static func explorerPayloads(chainId: UInt32, chainName: String) -> [ChainEndpointsPayload] {
        let endpoints = (try? WalletRustEndpointCatalogBridge.explorerSupplementalEndpoints(for: chainName)) ?? []
        guard !endpoints.isEmpty else { return [] }
        return [ChainEndpointsPayload(chainId: chainId, endpoints: endpoints, apiKey: nil)]
    }
}
