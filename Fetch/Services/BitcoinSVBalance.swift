import Foundation

struct BitcoinSVTransactionStatus: Equatable {
    let confirmed: Bool
    let blockHeight: Int?
}

struct BitcoinSVUTXO: Equatable {
    let txid: String
    let vout: Int
    let value: UInt64
}

enum BitcoinSVBalanceService {
    static func endpointCatalog() -> [String] {
        BitcoinSVProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        BitcoinSVProvider.diagnosticsChecks()
    }

    static func fetchTransactionStatus(txid: String) async throws -> BitcoinSVTransactionStatus {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await BitcoinSVProvider.runWithFallback(candidates: BitcoinSVProvider.ProviderID.allCases) { provider in
            switch provider {
            case .whatsonchain:
                let transaction = try await fetchWhatsOnChainTransactionDetails(txid: trimmed)
                let confirmations = max(0, transaction.confirmations ?? 0)
                return BitcoinSVTransactionStatus(
                    confirmed: confirmations > 0 || transaction.blockheight != nil,
                    blockHeight: transaction.blockheight
                )
            case .blockchair:
                let transaction = try await fetchBlockchairTransactionDetails(txid: trimmed)
                return BitcoinSVTransactionStatus(
                    confirmed: transaction.transaction.blockID != nil,
                    blockHeight: transaction.transaction.blockID
                )
            }
        }
    }

    private static func fetchWhatsOnChainTransactionDetails(txid: String) async throws -> BitcoinSVProvider.WhatsOnChainTransaction {
        try await fetchWhatsOnChainDecodable(path: "/tx/hash/\(txid)")
    }

    private static func fetchBlockchairTransactionDetails(txid: String) async throws -> BitcoinSVProvider.TransactionDashboard {
        guard let url = BitcoinSVProvider.blockchairTransactionURL(txid: txid) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BitcoinSVProvider.BlockchairTransactionResponse.self, from: data)
        if let transaction = decoded.data[txid] {
            return transaction
        }
        if let transaction = decoded.data.values.first {
            return transaction
        }
        throw URLError(.cannotParseResponse)
    }

    private static func fetchWhatsOnChainDecodable<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard var components = URLComponents(string: BitcoinSVProvider.whatsonchainBaseURL + path) else {
            throw URLError(.badURL)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await ProviderHTTP.data(for: request, profile: .chainRead)
    }
}
