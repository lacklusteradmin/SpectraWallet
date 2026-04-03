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

private struct BlockchainInfoMultiAddressResponse: Decodable {
    struct AddressEntry: Decodable {
        let address: String?
        let nTx: Int?
        let totalReceived: Int64?

        enum CodingKeys: String, CodingKey {
            case address
            case nTx = "n_tx"
            case totalReceived = "total_received"
        }
    }

    struct Transaction: Decodable {
        struct Input: Decodable {
            struct PrevOut: Decodable {
                let addr: String?
                let value: Int64?
            }
            let prevOut: PrevOut?

            enum CodingKeys: String, CodingKey {
                case prevOut = "prev_out"
            }
        }

        struct Output: Decodable {
            let addr: String?
            let value: Int64?
        }

        let hash: String
        let time: TimeInterval?
        let result: Int64?
        let inputs: [Input]?
        let out: [Output]?
    }

    let finalBalance: Int64?
    let txs: [Transaction]?
    let addresses: [AddressEntry]?

    enum CodingKeys: String, CodingKey {
        case finalBalance = "final_balance"
        case txs
        case addresses
    }
}

private struct BlockchairXPubResponse: Decodable {
    struct Context: Decodable {
        let code: Int?
    }

    let context: Context?
    let data: [String: BlockchairXPubData]?
}

private struct BlockchairXPubData: Decodable {
    struct AddressSummary: Decodable {
        let balance: Int64?

        enum CodingKeys: String, CodingKey {
            case balance
        }
    }

    struct AddressEntry: Decodable {
        let address: String?
    }

    let address: AddressSummary?
    let addresses: [AddressEntry]?
    let transactions: [String]?
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

    static func fetchBalance(forExtendedPublicKey xpub: String) async throws -> Double {
        do {
            let response = try await fetchXPubMultiAddress(xpub, limit: 1, offset: 0)
            let sats = max(0, response.finalBalance ?? 0)
            return Double(sats) / 100_000_000
        } catch {
            let fallback = try await fetchBlockchairXPubDashboard(xpub)
            let summary = fallback.address?.balance ?? 0
            let sats = max(0, summary)
            return Double(sats) / 100_000_000
        }
    }

    static func hasTransactionHistory(forExtendedPublicKey xpub: String) async throws -> Bool {
        do {
            let response = try await fetchXPubMultiAddress(xpub, limit: 1, offset: 0)
            return !(response.txs ?? []).isEmpty
        } catch {
            let fallback = try await fetchBlockchairXPubDashboard(xpub)
            return !(fallback.transactions ?? []).isEmpty
        }
    }

    static func fetchTransactionPage(
        forExtendedPublicKey xpub: String,
        limit: Int = 25,
        cursor: String? = nil
    ) async throws -> BitcoinHistoryPage {
        let pageSize = max(1, limit)
        let offset = max(0, Int(cursor ?? "") ?? 0)
        do {
            let response = try await fetchXPubMultiAddress(xpub, limit: pageSize, offset: offset)
            let transactions = response.txs ?? []
            let snapshots = transactions.prefix(pageSize).compactMap { transaction -> BitcoinHistorySnapshot? in
                let result = transaction.result ?? 0
                guard result != 0 else { return nil }
                let isReceive = result > 0
                let amountBTC = Double(abs(result)) / 100_000_000
                let counterparty = (isReceive ? transaction.inputs?.first?.prevOut?.addr : transaction.out?.first?.addr) ?? ""
                return BitcoinHistorySnapshot(
                    txid: transaction.hash,
                    amountBTC: amountBTC,
                    kind: isReceive ? .receive : .send,
                    status: .confirmed,
                    counterpartyAddress: counterparty,
                    blockHeight: nil,
                    createdAt: Date(timeIntervalSince1970: transaction.time ?? Date().timeIntervalSince1970)
                )
            }
            let nextCursor = transactions.count >= pageSize ? String(offset + pageSize) : nil
            return BitcoinHistoryPage(
                snapshots: Array(snapshots),
                nextCursor: nextCursor,
                sourceUsed: "blockchain.info"
            )
        } catch {
            let fallback = try await fetchBlockchairXPubDashboard(xpub, limit: pageSize, offset: offset)
            let hashes = fallback.transactions ?? []
            let snapshots = hashes.prefix(pageSize).map { hash in
                BitcoinHistorySnapshot(
                    txid: hash,
                    amountBTC: 0,
                    kind: .send,
                    status: .confirmed,
                    counterpartyAddress: "",
                    blockHeight: nil,
                    createdAt: Date()
                )
            }
            let nextCursor = hashes.count >= pageSize ? String(offset + pageSize) : nil
            return BitcoinHistoryPage(
                snapshots: Array(snapshots),
                nextCursor: nextCursor,
                sourceUsed: "blockchair"
            )
        }
    }

    static func fetchRecentTransactions(forExtendedPublicKey xpub: String, limit: Int = 25) async throws -> [BitcoinHistorySnapshot] {
        try await fetchTransactionPage(forExtendedPublicKey: xpub, limit: limit, cursor: nil).snapshots
    }

    static func fetchReceiveAddress(forExtendedPublicKey xpub: String) async throws -> String? {
        do {
            let response = try await fetchXPubMultiAddress(xpub, limit: 50, offset: 0)
            let addresses = response.addresses ?? []
            let unused = addresses.first(where: { ($0.nTx ?? 0) == 0 })?.address
            if let unused, !unused.isEmpty {
                return unused
            }
            return addresses.first?.address
        } catch {
            let fallback = try await fetchBlockchairXPubDashboard(xpub)
            return fallback.addresses?.first?.address
        }
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

    private static func fetchXPubMultiAddress(_ xpub: String, limit: Int, offset: Int) async throws -> BlockchainInfoMultiAddressResponse {
        let trimmedXPub = xpub.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = max(1, min(limit, 100))
        let boundedOffset = max(0, offset)
        guard !trimmedXPub.isEmpty,
              var components = URLComponents(string: ChainBackendRegistry.BitcoinRuntimeEndpoints.blockchainInfoMultiAddressBaseURL) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "active", value: trimmedXPub),
            URLQueryItem(name: "n", value: String(boundedLimit)),
            URLQueryItem(name: "offset", value: String(boundedOffset))
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(BlockchainInfoMultiAddressResponse.self, from: data)
    }

    private static func fetchBlockchairXPubDashboard(_ xpub: String, limit: Int = 100, offset: Int = 0) async throws -> BlockchairXPubData {
        let trimmedXPub = xpub.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = max(1, min(limit, 100))
        let boundedOffset = max(0, offset)
        guard !trimmedXPub.isEmpty,
              let encodedXPub = trimmedXPub.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(ChainBackendRegistry.BitcoinRuntimeEndpoints.blockchairXPubDashboardBaseURL)\(encodedXPub)?limit=\(boundedLimit)&offset=\(boundedOffset)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BlockchairXPubResponse.self, from: data)
        guard let key = decoded.data?.keys.first,
              let payload = decoded.data?[key] else {
            throw URLError(.cannotParseResponse)
        }
        return payload
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await ProviderHTTP.data(for: request, profile: .chainRead)
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await ProviderHTTP.data(for: request, profile: .chainRead)
    }

}
