import Foundation

enum DogecoinNetworkMode: String, CaseIterable, Codable, Identifiable {
    case mainnet
    case testnet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainnet: return "Mainnet"
        case .testnet: return "Testnet"
        }
    }
}

struct DogecoinTransactionStatus {
    let confirmed: Bool
    let blockHeight: Int?
    let networkFeeDOGE: Double?
    let confirmations: Int?
}

enum DogecoinBalanceService {
    typealias NetworkMode = DogecoinNetworkMode

    struct AddressTransactionSnapshot {
        let hash: String
        let kind: TransactionKind
        let status: TransactionStatus
        let amount: Double
        let counterpartyAddress: String
        let createdAt: Date
        let blockNumber: Int?
    }

    static func isValidDogecoinAddress(_ address: String, networkMode: NetworkMode = .mainnet) -> Bool {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (25 ... 40).contains(trimmedAddress.count) else {
            return false
        }

        guard let decoded = UTXOAddressCodec.base58CheckDecode(trimmedAddress), decoded.count == 21 else {
            return false
        }

        guard let version = decoded.first else { return false }
        switch networkMode {
        case .mainnet:
            return version == 0x1e || version == 0x16
        case .testnet:
            return version == 0x71 || version == 0xc4
        }
    }

    static func fetchTransactionStatus(txid: String, networkMode: NetworkMode = .mainnet) async throws -> DogecoinTransactionStatus {
        try await fetchTransactionStatusViaBlockcypher(txid: txid, networkMode: networkMode)
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.dogecoinChainName)
    }

    static func endpointCatalogByNetwork() -> [(title: String, endpoints: [String])] {
        AppEndpointDirectory.groupedSettingsEntries(for: ChainBackendRegistry.dogecoinChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.dogecoinChainName)
    }

    private static func blockcypherURL(path: String, networkMode: NetworkMode) -> URL? {
        switch networkMode {
        case .mainnet:
            return BlockCypherProvider.url(path: path, network: .dogecoinMainnet)
        case .testnet:
            return BlockCypherProvider.url(path: path, network: .dogecoinTestnet)
        }
    }

    private static func fetchTransactionStatusViaBlockcypher(
        txid: String,
        networkMode: NetworkMode
    ) async throws -> DogecoinTransactionStatus {
        let trimmedTXID = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTXID.isEmpty,
              let encodedTXID = trimmedTXID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/txs/\(encodedTXID)", networkMode: networkMode) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(BlockCypherProvider.TransactionDetailResponse.self, from: data)
        let confirmed = (payload.confirmations ?? 0) > 0 || payload.blockHeight != nil
        let inputTotalKoinu = (payload.inputs ?? []).reduce(Int64(0)) { partialResult, input in
            partialResult + max(0, input.outputValue ?? input.value ?? 0)
        }
        let outputTotalKoinu = (payload.outputs ?? []).reduce(Int64(0)) { partialResult, output in
            partialResult + max(0, output.value ?? 0)
        }
        let feeDOGE = Double(max(0, inputTotalKoinu - outputTotalKoinu)) / 100_000_000

        return DogecoinTransactionStatus(
            confirmed: confirmed,
            blockHeight: payload.blockHeight,
            networkFeeDOGE: feeDOGE,
            confirmations: payload.confirmations
        )
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(from: url, profile: .chainRead)
    }
}
