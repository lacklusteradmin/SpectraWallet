import Foundation

struct LitecoinTransactionStatus: Decodable {
    let confirmed: Bool
    let blockHeight: Int?

    enum CodingKeys: String, CodingKey {
        case confirmed
        case blockHeight = "block_height"
    }
}

enum LitecoinBalanceService {
    private static let litecoinspaceBaseURL = ChainBackendRegistry.LitecoinRuntimeEndpoints.litecoinspaceBaseURL
    private static let blockcypherBaseURL = BlockCypherProvider.Network.litecoinMainnet.baseURL
    private static let sochainBaseURL = ChainBackendRegistry.LitecoinRuntimeEndpoints.sochainBaseURL

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.litecoinChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.litecoinChainName)
    }

    private enum Provider: String {
        case litecoinspace
        case blockcypher
        case sochain
    }

    private struct SoChainEnvelope<Payload: Decodable>: Decodable {
        let status: String?
        let data: Payload?
    }

    private struct SoChainTransactionPayload: Decodable {
        let confirmations: Int?
        let blockNo: Int?

        enum CodingKeys: String, CodingKey {
            case confirmations
            case blockNo = "block_no"
        }
    }

    static func fetchTransactionStatus(txid: String) async throws -> LitecoinTransactionStatus {
        let trimmedTXID = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTXID.isEmpty else {
            throw URLError(.badURL)
        }
        return try await runWithProviderFallback(candidates: [.litecoinspace, .blockcypher, .sochain]) { provider in
            switch provider {
            case .litecoinspace:
                return try await fetchStatusViaLitecoinspace(trimmedTXID)
            case .blockcypher:
                return try await fetchStatusViaBlockcypher(trimmedTXID)
            case .sochain:
                return try await fetchStatusViaSochain(trimmedTXID)
            }
        }
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(from: url, profile: .litecoinRead)
    }

    private static func fetchStatusViaLitecoinspace(_ txid: String) async throws -> LitecoinTransactionStatus {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(litecoinspaceBaseURL)/tx/\(encodedTXID)/status") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(LitecoinTransactionStatus.self, from: data)
    }

    private static func fetchStatusViaBlockcypher(_ txid: String) async throws -> LitecoinTransactionStatus {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockcypherBaseURL)/txs/\(encodedTXID)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(BlockCypherProvider.TransactionStatusResponse.self, from: data)
        return LitecoinTransactionStatus(
            confirmed: (decoded.confirmations ?? 0) > 0,
            blockHeight: decoded.blockHeight
        )
    }

    private static func fetchStatusViaSochain(_ txid: String) async throws -> LitecoinTransactionStatus {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(sochainBaseURL)/get_tx/LTC/\(encodedTXID)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SoChainEnvelope<SoChainTransactionPayload>.self, from: data)
        let confirmations = decoded.data?.confirmations ?? 0
        return LitecoinTransactionStatus(
            confirmed: confirmations > 0,
            blockHeight: decoded.data?.blockNo
        )
    }

    private static func runWithProviderFallback<T>(
        candidates: [Provider],
        operation: @escaping (Provider) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for provider in candidates {
            do {
                return try await operation(provider)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }
}
