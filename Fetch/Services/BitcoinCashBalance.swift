import Foundation

struct BitcoinCashTransactionStatus: Equatable {
    let confirmed: Bool
    let blockHeight: Int?
}

struct BitcoinCashUTXO: Equatable {
    let txid: String
    let vout: Int
    let value: UInt64
}

enum BitcoinCashBalanceService {
    static func endpointCatalog() -> [String] {
        BitcoinCashProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        BitcoinCashProvider.diagnosticsChecks()
    }

    static func fetchTransactionStatus(txid: String) async throws -> BitcoinCashTransactionStatus {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await BitcoinCashProvider.runWithFallback(candidates: BitcoinCashProvider.ProviderID.allCases) { provider in
            switch provider {
            case .blockchair:
                let transaction = try await fetchBlockchairTransactionDetails(txid: trimmed)
                return BitcoinCashTransactionStatus(
                    confirmed: transaction.transaction.blockID != nil,
                    blockHeight: transaction.transaction.blockID
                )
            case .actorforth:
                let transaction = try await fetchActorForthTransactionDetails(txid: trimmed)
                let confirmations = max(0, transaction.confirmations ?? 0)
                return BitcoinCashTransactionStatus(
                    confirmed: confirmations > 0 || transaction.blockheight != nil,
                    blockHeight: transaction.blockheight
                )
            }
        }
    }

    private static func fetchBlockchairTransactionDetails(txid: String) async throws -> BitcoinCashProvider.TransactionDashboard {
        guard let url = BitcoinCashProvider.blockchairTransactionURL(txid: txid) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BitcoinCashProvider.BlockchairTransactionResponse.self, from: data)
        if let transaction = decoded.data[txid] {
            return transaction
        }
        if let transaction = decoded.data.values.first {
            return transaction
        }
        throw URLError(.cannotParseResponse)
    }

    private static func fetchActorForthTransactionDetails(txid: String) async throws -> BitcoinCashProvider.ActorForthTransactionPayload {
        guard let url = BitcoinCashProvider.actorForthTransactionURL(txid: txid) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(BitcoinCashProvider.ActorForthEnvelope<BitcoinCashProvider.ActorForthTransactionPayload>.self, from: data)
        guard let payload = envelope.data else {
            throw URLError(.cannotParseResponse)
        }
        return payload
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(from: url, profile: .chainRead)
    }
}
