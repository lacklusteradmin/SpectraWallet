import Foundation

struct LitecoinAddressResponse: Decodable {
    let chainStats: LitecoinAddressStats
    let mempoolStats: LitecoinAddressStats

    enum CodingKeys: String, CodingKey {
        case chainStats = "chain_stats"
        case mempoolStats = "mempool_stats"
    }
}

struct LitecoinAddressStats: Decodable {
    let fundedTXOSum: Int64
    let spentTXOSum: Int64
    let txCount: Int

    enum CodingKeys: String, CodingKey {
        case fundedTXOSum = "funded_txo_sum"
        case spentTXOSum = "spent_txo_sum"
        case txCount = "tx_count"
    }
}

struct LitecoinTransactionStatus: Decodable {
    let confirmed: Bool
    let blockHeight: Int?

    enum CodingKeys: String, CodingKey {
        case confirmed
        case blockHeight = "block_height"
    }
}

struct LitecoinAddressTransaction: Decodable {
    struct VIN: Decodable {
        struct Prevout: Decodable {
            let scriptpubkeyAddress: String?
            let value: Int64

            enum CodingKeys: String, CodingKey {
                case scriptpubkeyAddress = "scriptpubkey_address"
                case value
            }
        }

        let prevout: Prevout?
    }

    struct VOUT: Decodable {
        let scriptpubkeyAddress: String?
        let value: Int64

        enum CodingKeys: String, CodingKey {
            case scriptpubkeyAddress = "scriptpubkey_address"
            case value
        }
    }

    struct Status: Decodable {
        let confirmed: Bool
        let blockHeight: Int?
        let blockTime: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
            case blockTime = "block_time"
        }
    }

    let txid: String
    let vin: [VIN]
    let vout: [VOUT]
    let status: Status
}

struct LitecoinHistorySnapshot: Equatable {
    let txid: String
    let amountLTC: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}

struct LitecoinHistoryPage {
    let snapshots: [LitecoinHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

enum LitecoinBalanceService {
    private static let litecoinspaceBaseURL = ChainBackendRegistry.LitecoinRuntimeEndpoints.litecoinspaceBaseURL
    private static let blockcypherBaseURL = BlockCypherProvider.Network.litecoinMainnet.baseURL
    private static let sochainBaseURL = ChainBackendRegistry.LitecoinRuntimeEndpoints.sochainBaseURL
    private static let iso8601Formatter = ISO8601DateFormatter()

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

    private enum ProviderOperation {
        case balance
        case historyExists
        case status
        case historyPage
    }

    private struct SoChainEnvelope<Payload: Decodable>: Decodable {
        let status: String?
        let data: Payload?
    }

    private struct SoChainBalancePayload: Decodable {
        let confirmedBalance: String?
        let confirmed_balance: String?
    }

    private struct SoChainAddressTXPayload: Decodable {
        struct Transaction: Decodable {
            let txid: String?
        }
        let txs: [Transaction]?
    }

    private struct SoChainTransactionPayload: Decodable {
        let confirmations: Int?
        let blockNo: Int?

        enum CodingKeys: String, CodingKey {
            case confirmations
            case blockNo = "block_no"
        }
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw URLError(.badURL)
        }
        return try await runWithProviderFallback(providerOperation: .balance, candidates: [.litecoinspace, .blockcypher, .sochain]) { provider in
            switch provider {
            case .litecoinspace:
                return try await fetchBalanceViaLitecoinspace(trimmedAddress)
            case .blockcypher:
                return try await fetchBalanceViaBlockcypher(trimmedAddress)
            case .sochain:
                return try await fetchBalanceViaSochain(trimmedAddress)
            }
        }
    }

    static func hasTransactionHistory(for address: String) async throws -> Bool {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw URLError(.badURL)
        }
        return try await runWithProviderFallback(providerOperation: .historyExists, candidates: [.litecoinspace, .blockcypher, .sochain]) { provider in
            switch provider {
            case .litecoinspace:
                return try await hasHistoryViaLitecoinspace(trimmedAddress)
            case .blockcypher:
                return try await hasHistoryViaBlockcypher(trimmedAddress)
            case .sochain:
                return try await hasHistoryViaSochain(trimmedAddress)
            }
        }
    }

    static func fetchTransactionStatus(txid: String) async throws -> LitecoinTransactionStatus {
        let trimmedTXID = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTXID.isEmpty else {
            throw URLError(.badURL)
        }
        return try await runWithProviderFallback(providerOperation: .status, candidates: [.litecoinspace, .blockcypher, .sochain]) { provider in
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

    static func fetchTransactionPage(
        for address: String,
        limit: Int = 25,
        cursor: String? = nil
    ) async throws -> LitecoinHistoryPage {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw URLError(.badURL)
        }
        let pageSize = max(1, limit)
        let rawCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredProvider: Provider?
        let providerCursor: String?
        if let rawCursor, rawCursor.hasPrefix("bc:") {
            preferredProvider = .blockcypher
            providerCursor = String(rawCursor.dropFirst(3))
        } else if let rawCursor, rawCursor.hasPrefix("ls:") {
            preferredProvider = .litecoinspace
            providerCursor = String(rawCursor.dropFirst(3))
        } else {
            preferredProvider = nil
            providerCursor = rawCursor
        }

        let orderedProviders: [Provider] = {
            guard let preferredProvider else {
                return [.litecoinspace, .blockcypher]
            }
            return [preferredProvider] + [.litecoinspace, .blockcypher].filter { $0 != preferredProvider }
        }()

        return try await runWithProviderFallback(providerOperation: .historyPage, candidates: orderedProviders) { provider in
            switch provider {
            case .litecoinspace:
                return try await fetchTransactionPageViaLitecoinspace(
                    address: trimmedAddress,
                    limit: pageSize,
                    cursor: preferredProvider == .blockcypher ? nil : providerCursor
                )
            case .blockcypher:
                return try await fetchTransactionPageViaBlockcypher(
                    address: trimmedAddress,
                    limit: pageSize,
                    cursor: preferredProvider == .litecoinspace ? nil : providerCursor
                )
            case .sochain:
                throw URLError(.cannotLoadFromNetwork)
            }
        }
    }

    private static func mapAddressTransactions(
        _ transactions: [LitecoinAddressTransaction],
        normalizedAddress: String,
        fallbackAddress: String
    ) -> [LitecoinHistorySnapshot] {
        transactions.compactMap { transaction in
            var incomingLitoshis: Int64 = 0
            var outgoingLitoshis: Int64 = 0
            var firstIncomingAddress: String?
            var firstOutgoingAddress: String?

            for input in transaction.vin {
                guard let prevout = input.prevout,
                      let source = prevout.scriptpubkeyAddress else { continue }
                if source.lowercased() == normalizedAddress {
                    outgoingLitoshis += prevout.value
                } else if firstOutgoingAddress == nil {
                    firstOutgoingAddress = source
                }
            }

            for output in transaction.vout {
                guard let destination = output.scriptpubkeyAddress else { continue }
                if destination.lowercased() == normalizedAddress {
                    incomingLitoshis += output.value
                } else if firstIncomingAddress == nil {
                    firstIncomingAddress = destination
                }
            }

            let delta = incomingLitoshis - outgoingLitoshis
            guard delta != 0 else { return nil }
            let isReceive = delta > 0
            let amountLTC = Double(abs(delta)) / 100_000_000
            let counterparty = isReceive ? (firstOutgoingAddress ?? fallbackAddress) : (firstIncomingAddress ?? fallbackAddress)
            let createdAt: Date
            if let timestamp = transaction.status.blockTime {
                createdAt = Date(timeIntervalSince1970: timestamp)
            } else {
                createdAt = Date()
            }

            return LitecoinHistorySnapshot(
                txid: transaction.txid,
                amountLTC: amountLTC,
                kind: isReceive ? .receive : .send,
                status: transaction.status.confirmed ? .confirmed : .pending,
                counterpartyAddress: counterparty,
                blockHeight: transaction.status.blockHeight,
                createdAt: createdAt
            )
        }
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(from: url, profile: .litecoinRead)
    }

    private static func fetchBalanceViaLitecoinspace(_ address: String) async throws -> Double {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(litecoinspaceBaseURL)/address/\(encodedAddress)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(LitecoinAddressResponse.self, from: data)
        let funded = decoded.chainStats.fundedTXOSum + decoded.mempoolStats.fundedTXOSum
        let spent = decoded.chainStats.spentTXOSum + decoded.mempoolStats.spentTXOSum
        let litoshis = max(0, funded - spent)
        return Double(litoshis) / 100_000_000
    }

    private static func fetchBalanceViaBlockcypher(_ address: String) async throws -> Double {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockcypherBaseURL)/addrs/\(encodedAddress)/balance") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(BlockCypherProvider.AddressStatsResponse.self, from: data)
        let litoshis = max(0, decoded.finalBalance ?? decoded.balance ?? 0)
        return Double(litoshis) / 100_000_000
    }

    private static func fetchBalanceViaSochain(_ address: String) async throws -> Double {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(sochainBaseURL)/get_address_balance/LTC/\(encodedAddress)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SoChainEnvelope<SoChainBalancePayload>.self, from: data)
        let text = decoded.data?.confirmedBalance ?? decoded.data?.confirmed_balance ?? "0"
        guard let balance = Double(text), balance.isFinite else {
            throw URLError(.cannotParseResponse)
        }
        return max(0, balance)
    }

    private static func hasHistoryViaLitecoinspace(_ address: String) async throws -> Bool {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(litecoinspaceBaseURL)/address/\(encodedAddress)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(LitecoinAddressResponse.self, from: data)
        return decoded.chainStats.txCount > 0 || decoded.mempoolStats.txCount > 0
    }

    private static func hasHistoryViaBlockcypher(_ address: String) async throws -> Bool {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockcypherBaseURL)/addrs/\(encodedAddress)?limit=1") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(BlockCypherProvider.AddressStatsResponse.self, from: data)
        return (decoded.finalNTx ?? decoded.nTx ?? 0) > 0
    }

    private static func hasHistoryViaSochain(_ address: String) async throws -> Bool {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(sochainBaseURL)/get_tx_received/LTC/\(encodedAddress)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SoChainEnvelope<SoChainAddressTXPayload>.self, from: data)
        return !(decoded.data?.txs ?? []).isEmpty
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

    private static func fetchTransactionPageViaLitecoinspace(
        address: String,
        limit: Int,
        cursor: String?
    ) async throws -> LitecoinHistoryPage {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        let endpointPath: String
        if let cursor, !cursor.isEmpty,
           let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            endpointPath = "/address/\(encodedAddress)/txs/chain/\(encodedCursor)"
        } else {
            endpointPath = "/address/\(encodedAddress)/txs"
        }
        guard let url = URL(string: "\(litecoinspaceBaseURL)\(endpointPath)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode([LitecoinAddressTransaction].self, from: data)
        let snapshots = mapAddressTransactions(decoded, normalizedAddress: address.lowercased(), fallbackAddress: address)
        let nextCursor = decoded.count >= limit ? decoded.prefix(limit).last.map { "ls:\($0.txid)" } : nil
        return LitecoinHistoryPage(
            snapshots: Array(snapshots.prefix(limit)),
            nextCursor: nextCursor,
            sourceUsed: Provider.litecoinspace.rawValue
        )
    }

    private static func fetchTransactionPageViaBlockcypher(
        address: String,
        limit: Int,
        cursor: String?
    ) async throws -> LitecoinHistoryPage {
        let offset = max(0, Int(cursor ?? "") ?? 0)
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(blockcypherBaseURL)/addrs/\(encodedAddress)/full?limit=\(limit)&txstart=\(offset)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(BlockCypherProvider.AddressTransactionsResponse.self, from: data)
        let transactions = decoded.txs ?? []
        let snapshots = mapBlockCypherTransactions(transactions, normalizedAddress: address.lowercased(), fallbackAddress: address)
        let nextCursor = transactions.count >= limit ? "bc:\(offset + limit)" : nil
        return LitecoinHistoryPage(
            snapshots: Array(snapshots.prefix(limit)),
            nextCursor: nextCursor,
            sourceUsed: Provider.blockcypher.rawValue
        )
    }

    private static func mapBlockCypherTransactions(
        _ transactions: [BlockCypherProvider.TransactionDetailResponse],
        normalizedAddress: String,
        fallbackAddress: String
    ) -> [LitecoinHistorySnapshot] {
        transactions.compactMap { transaction in
            var incomingLitoshis: Int64 = 0
            var outgoingLitoshis: Int64 = 0
            var firstIncomingAddress: String?
            var firstOutgoingAddress: String?

            for input in transaction.inputs ?? [] {
                let source = input.addresses?.first
                let value = input.outputValue ?? input.value ?? 0
                if source?.lowercased() == normalizedAddress {
                    outgoingLitoshis += value
                } else if let source, firstOutgoingAddress == nil {
                    firstOutgoingAddress = source
                }
            }

            for output in transaction.outputs ?? [] {
                guard let destination = output.addresses?.first else { continue }
                let value = output.value ?? 0
                if destination.lowercased() == normalizedAddress {
                    incomingLitoshis += value
                } else if firstIncomingAddress == nil {
                    firstIncomingAddress = destination
                }
            }

            let delta = incomingLitoshis - outgoingLitoshis
            guard delta != 0, let txid = transaction.hash else { return nil }
            let isReceive = delta > 0
            let amountLTC = Double(abs(delta)) / 100_000_000
            let counterparty = isReceive ? (firstOutgoingAddress ?? fallbackAddress) : (firstIncomingAddress ?? fallbackAddress)

            let createdAt: Date
            if let received = transaction.received,
               let parsed = iso8601Formatter.date(from: received) {
                createdAt = parsed
            } else {
                createdAt = Date()
            }

            let status: TransactionStatus = (transaction.confirmations ?? 0) > 0 ? .confirmed : .pending
            return LitecoinHistorySnapshot(
                txid: txid,
                amountLTC: amountLTC,
                kind: isReceive ? .receive : .send,
                status: status,
                counterpartyAddress: counterparty,
                blockHeight: transaction.blockHeight,
                createdAt: createdAt
            )
        }
    }

    private static func runWithProviderFallback<T>(
        providerOperation: ProviderOperation,
        candidates: [Provider],
        operation: @escaping (Provider) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for provider in candidates {
            do {
                return try await operation(provider)
            } catch {
                lastError = error
                // Small spacing between provider attempts reduces burst retries on shared rate limits.
                switch providerOperation {
                case .balance, .historyExists, .status, .historyPage:
                    try? await Task.sleep(nanoseconds: 180_000_000)
                }
            }
        }
        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }
}
