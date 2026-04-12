import Foundation

struct BitcoinHistorySnapshot: Equatable {
    let txid: String
    let amountBTC: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}

struct BitcoinHistoryPage {
    let snapshots: [BitcoinHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}


enum BitcoinBalanceService {
    static func fetchBalance(for address: String, networkMode: BitcoinNetworkMode = .mainnet) async throws -> Double {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty,
              let encodedAddress = trimmedAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return try await EsploraProvider.runWithFallback(baseURLs: EsploraProvider.runtimeBaseURLs(for: networkMode)) { baseURL in
            guard let url = EsploraProvider.url(baseURL: baseURL, path: "/address/\(encodedAddress)") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await fetchData(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(EsploraProvider.AddressResponse.self, from: data)
            let funded = decoded.chainStats.fundedTXOSum + decoded.mempoolStats.fundedTXOSum
            let spent = decoded.chainStats.spentTXOSum + decoded.mempoolStats.spentTXOSum
            let satoshis = max(0, funded - spent)
            return Double(satoshis) / 100_000_000
        }
    }

    static func fetchTransactionStatus(txid: String, networkMode: BitcoinNetworkMode = .mainnet) async throws -> EsploraProvider.TransactionStatus {
        let trimmedTXID = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTXID.isEmpty,
              let encodedTXID = trimmedTXID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return try await EsploraProvider.runWithFallback(baseURLs: EsploraProvider.runtimeBaseURLs(for: networkMode)) { baseURL in
            guard let url = EsploraProvider.url(baseURL: baseURL, path: "/tx/\(encodedTXID)/status") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await fetchData(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(EsploraProvider.TransactionStatus.self, from: data)
        }
    }

    static func hasTransactionHistory(for address: String, networkMode: BitcoinNetworkMode = .mainnet) async throws -> Bool {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty,
              let encodedAddress = trimmedAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return try await EsploraProvider.runWithFallback(baseURLs: EsploraProvider.runtimeBaseURLs(for: networkMode)) { baseURL in
            guard let url = EsploraProvider.url(baseURL: baseURL, path: "/address/\(encodedAddress)") else {
                throw URLError(.badURL)
            }

            let (data, response) = try await fetchData(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(EsploraProvider.AddressResponse.self, from: data)
            return decoded.chainStats.txCount > 0 || decoded.mempoolStats.txCount > 0
        }
    }

    static func fetchTransactionPage(
        for address: String,
        networkMode: BitcoinNetworkMode = .mainnet,
        limit: Int = 25,
        cursor: String? = nil
    ) async throws -> BitcoinHistoryPage {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty,
              let encodedAddress = trimmedAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        let endpointPath: String
        if let cursor, !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            endpointPath = "/address/\(encodedAddress)/txs/chain/\(encodedCursor)"
        } else {
            endpointPath = "/address/\(encodedAddress)/txs"
        }
        let baseURLs = EsploraProvider.runtimeBaseURLs(for: networkMode)
        return try await EsploraProvider.runWithFallback(baseURLs: baseURLs) { baseURL in
            guard let url = EsploraProvider.url(baseURL: baseURL, path: endpointPath) else {
                throw URLError(.badURL)
            }

            let (data, response) = try await fetchData(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode([EsploraProvider.AddressTransaction].self, from: data)
            let pageSize = max(1, limit)
            let snapshots = mapAddressTransactions(decoded, normalizedAddress: trimmedAddress.lowercased(), fallbackAddress: trimmedAddress)
            let nextCursor = decoded.count >= pageSize ? decoded.prefix(pageSize).last?.txid : nil
            return BitcoinHistoryPage(
                snapshots: Array(snapshots.prefix(pageSize)),
                nextCursor: nextCursor,
                sourceUsed: URL(string: baseURL)?.host ?? "esplora"
            )
        }
    }

    static func fetchRecentTransactions(
        for address: String,
        networkMode: BitcoinNetworkMode = .mainnet,
        limit: Int = 25
    ) async throws -> [BitcoinHistorySnapshot] {
        try await fetchTransactionPage(for: address, networkMode: networkMode, limit: limit, cursor: nil).snapshots
    }


    private static func mapAddressTransactions(
        _ transactions: [EsploraProvider.AddressTransaction],
        normalizedAddress: String,
        fallbackAddress: String
    ) -> [BitcoinHistorySnapshot] {
        transactions.compactMap { transaction in
            var incomingSats: Int64 = 0
            var outgoingSats: Int64 = 0
            var firstIncomingAddress: String?
            var firstOutgoingAddress: String?

            for input in transaction.vin {
                guard let prevout = input.prevout,
                      let source = prevout.scriptpubkeyAddress else { continue }
                if source.lowercased() == normalizedAddress {
                    outgoingSats += prevout.value
                } else if firstOutgoingAddress == nil {
                    firstOutgoingAddress = source
                }
            }

            for output in transaction.vout {
                guard let destination = output.scriptpubkeyAddress else { continue }
                if destination.lowercased() == normalizedAddress {
                    incomingSats += output.value
                } else if firstIncomingAddress == nil {
                    firstIncomingAddress = destination
                }
            }

            let delta = incomingSats - outgoingSats
            guard delta != 0 else { return nil }
            let isReceive = delta > 0
            let amountBTC = Double(abs(delta)) / 100_000_000
            let counterparty = isReceive ? (firstOutgoingAddress ?? fallbackAddress) : (firstIncomingAddress ?? fallbackAddress)
            let createdAt: Date
            if let timestamp = transaction.status.blockTime {
                createdAt = Date(timeIntervalSince1970: timestamp)
            } else {
                createdAt = Date()
            }

            return BitcoinHistorySnapshot(
                txid: transaction.txid,
                amountBTC: amountBTC,
                kind: isReceive ? .receive : .send,
                status: transaction.status.confirmed ? .confirmed : .pending,
                counterpartyAddress: counterparty,
                blockHeight: transaction.status.blockHeight,
                createdAt: createdAt
            )
        }
    }


    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await ProviderHTTP.data(for: request, profile: .chainRead)
    }

}
