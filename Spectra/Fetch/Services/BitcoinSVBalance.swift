import Foundation

struct BitcoinSVHistorySnapshot: Equatable {
    let txid: String
    let amountBSV: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}

struct BitcoinSVHistoryPage {
    let snapshots: [BitcoinSVHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

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
    private static let satoshisPerBSV: Double = 100_000_000

    static func endpointCatalog() -> [String] {
        BitcoinSVProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        BitcoinSVProvider.diagnosticsChecks()
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let trimmed = try normalizedAddress(address)
        return try await BitcoinSVProvider.runWithFallback(candidates: BitcoinSVProvider.ProviderID.allCases) { provider in
            switch provider {
            case .whatsonchain:
                let balance: BitcoinSVProvider.WhatsOnChainBalanceResponse = try await fetchWhatsOnChainDecodable(path: "/address/\(trimmed)/balance")
                let confirmed = max(0, balance.confirmed ?? 0)
                let unconfirmed = max(0, balance.unconfirmed ?? 0)
                return Double(confirmed + unconfirmed) / satoshisPerBSV
            case .blockchair:
                let dashboard = try await fetchBlockchairAddressDashboard(for: trimmed, limit: 1, offset: 0)
                let balance = max(0, dashboard.address.balance ?? 0)
                return Double(balance) / satoshisPerBSV
            }
        }
    }

    static func hasTransactionHistory(for address: String) async throws -> Bool {
        let trimmed = try normalizedAddress(address)
        return try await BitcoinSVProvider.runWithFallback(candidates: BitcoinSVProvider.ProviderID.allCases) { provider in
            switch provider {
            case .whatsonchain:
                let confirmed: [BitcoinSVProvider.WhatsOnChainHistoryEntry] = try await fetchWhatsOnChainDecodable(path: "/address/\(trimmed)/confirmed/history")
                if !confirmed.isEmpty {
                    return true
                }
                let unconfirmed: [BitcoinSVProvider.WhatsOnChainHistoryEntry] = try await fetchWhatsOnChainDecodable(path: "/address/\(trimmed)/unconfirmed/history")
                return !unconfirmed.isEmpty
            case .blockchair:
                let dashboard = try await fetchBlockchairAddressDashboard(for: trimmed, limit: 1, offset: 0)
                return !(dashboard.transactions.isEmpty) || (dashboard.address.transactionCount ?? 0) > 0
            }
        }
    }

    static func fetchUTXOs(for address: String) async throws -> [BitcoinSVUTXO] {
        let trimmed = try normalizedAddress(address)
        let whatsonchainUTXOs = try? await fetchWhatsOnChainUTXOs(for: trimmed)
        let blockchairUTXOs = try? await fetchBlockchairUTXOs(for: trimmed)

        switch (whatsonchainUTXOs, blockchairUTXOs) {
        case let (.some(whatsonchain), .some(blockchair)):
            return try mergeConsistentUTXOs(
                whatsonchainUTXOs: whatsonchain,
                blockchairUTXOs: blockchair
            )
        case let (.some(whatsonchain), .none):
            return whatsonchain
        case let (.none, .some(blockchair)):
            return blockchair
        case (.none, .none):
            throw URLError(.cannotLoadFromNetwork)
        }
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

    static func fetchTransactionPage(
        for address: String,
        limit: Int,
        cursor: String? = nil
    ) async throws -> BitcoinSVHistoryPage {
        let trimmed = try normalizedAddress(address)
        let normalizedLimit = max(1, limit)
        let ownAddresses = ownAddressVariants(for: trimmed)

        let unconfirmedEntries: [BitcoinSVProvider.WhatsOnChainHistoryEntry]
        let confirmedEntries: [BitcoinSVProvider.WhatsOnChainHistoryEntry]
        let nextCursor: String?

        if let cursor, !cursor.isEmpty {
            let token = cursor.replacingOccurrences(of: "confirmed:", with: "")
            confirmedEntries = try await fetchHistoryPage(
                path: "/address/\(trimmed)/confirmed/history",
                limit: normalizedLimit,
                cursor: token.isEmpty ? nil : token
            )
            unconfirmedEntries = []
            nextCursor = confirmedEntries.count == normalizedLimit
                ? "confirmed:\(tokenForLastHistoryEntry(confirmedEntries.last))"
                : nil
        } else {
            unconfirmedEntries = try await fetchHistoryPage(
                path: "/address/\(trimmed)/unconfirmed/history",
                limit: normalizedLimit,
                cursor: nil
            )
            let remainingLimit = max(0, normalizedLimit - unconfirmedEntries.count)
            if remainingLimit > 0 {
                confirmedEntries = try await fetchHistoryPage(
                    path: "/address/\(trimmed)/confirmed/history",
                    limit: remainingLimit,
                    cursor: nil
                )
            } else {
                confirmedEntries = []
            }
            nextCursor = confirmedEntries.count == remainingLimit && remainingLimit > 0
                ? "confirmed:\(tokenForLastHistoryEntry(confirmedEntries.last))"
                : nil
        }

        let txids = Array(Set((unconfirmedEntries + confirmedEntries).map(\.txHash)))
        var snapshots: [BitcoinSVHistorySnapshot] = []
        for txid in txids {
            let transaction = try await fetchWhatsOnChainTransactionDetails(txid: txid)
            snapshots.append(snapshot(for: transaction, ownAddresses: ownAddresses))
        }

        return BitcoinSVHistoryPage(
            snapshots: snapshots.sorted { $0.createdAt > $1.createdAt },
            nextCursor: nextCursor,
            sourceUsed: "whatsonchain"
        )
    }

    private static func fetchHistoryPage(
        path: String,
        limit: Int,
        cursor: String?
    ) async throws -> [BitcoinSVProvider.WhatsOnChainHistoryEntry] {
        var queryItems = [URLQueryItem(name: "limit", value: String(max(1, limit)))]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "start", value: cursor))
        }
        return try await fetchWhatsOnChainDecodable(path: path, queryItems: queryItems)
    }

    private static func fetchWhatsOnChainTransactionDetails(txid: String) async throws -> BitcoinSVProvider.WhatsOnChainTransaction {
        try await fetchWhatsOnChainDecodable(path: "/tx/hash/\(txid)")
    }

    private static func fetchBlockchairAddressDashboard(
        for address: String,
        limit: Int,
        offset: Int
    ) async throws -> BitcoinSVProvider.AddressDashboard {
        guard let url = BitcoinSVProvider.blockchairAddressDashboardURL(address: address, limit: limit, offset: offset) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BitcoinSVProvider.BlockchairAddressResponse.self, from: data)
        if let dashboard = decoded.data[address] {
            return dashboard
        }
        if let dashboard = decoded.data.values.first {
            return dashboard
        }
        throw URLError(.cannotParseResponse)
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

    private static func fetchWhatsOnChainUTXOs(for address: String) async throws -> [BitcoinSVUTXO] {
        let utxos: [BitcoinSVProvider.WhatsOnChainUnspentEntry] = try await fetchWhatsOnChainDecodable(path: "/address/\(address)/confirmed/unspent")
        return sanitizeUTXOs(utxos.map {
            BitcoinSVUTXO(txid: $0.txHash, vout: $0.outputIndex, value: $0.value)
        })
    }

    private static func fetchBlockchairUTXOs(for address: String) async throws -> [BitcoinSVUTXO] {
        let dashboard = try await fetchBlockchairAddressDashboard(for: address, limit: 100, offset: 0)
        return sanitizeUTXOs((dashboard.utxo ?? []).map {
            BitcoinSVUTXO(txid: $0.transactionHash, vout: $0.index, value: $0.value)
        })
    }

    private static func snapshot(
        for transaction: BitcoinSVProvider.WhatsOnChainTransaction,
        ownAddresses: Set<String>
    ) -> BitcoinSVHistorySnapshot {
        let outgoingValue = transaction.vin.reduce(0.0) { partialResult, input in
            guard let address = input.address?.lowercased(), ownAddresses.contains(address) else {
                return partialResult
            }
            return partialResult + max(0, input.value ?? 0)
        }
        let incomingOutputs = transaction.vout.filter { output in
            let outputAddresses = resolvedAddresses(for: output)
            return outputAddresses.contains { ownAddresses.contains($0.lowercased()) }
        }
        let incomingValue = incomingOutputs.reduce(0.0) { $0 + max(0, $1.value ?? 0) }
        let netAmount = incomingValue - outgoingValue
        let isReceive = netAmount >= 0

        let counterparty = if isReceive {
            transaction.vin.compactMap(\.address).first ?? "Unknown"
        } else {
            transaction.vout.first { output in
                let outputAddresses = resolvedAddresses(for: output)
                return outputAddresses.contains { !ownAddresses.contains($0.lowercased()) }
            }
            .flatMap { resolvedAddresses(for: $0).first } ?? "Unknown"
        }

        let timestamp = transaction.blocktime ?? transaction.time
        let createdAt = timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date()
        let confirmations = max(0, transaction.confirmations ?? 0)

        return BitcoinSVHistorySnapshot(
            txid: transaction.txid,
            amountBSV: abs(netAmount),
            kind: isReceive ? .receive : .send,
            status: confirmations > 0 || transaction.blockheight != nil ? .confirmed : .pending,
            counterpartyAddress: counterparty,
            blockHeight: transaction.blockheight,
            createdAt: createdAt
        )
    }

    private static func resolvedAddresses(for output: BitcoinSVProvider.WhatsOnChainTransaction.Output) -> [String] {
        if let addresses = output.scriptPubKey?.addresses, !addresses.isEmpty {
            return addresses
        }
        if let address = output.scriptPubKey?.address, !address.isEmpty {
            return [address]
        }
        return []
    }

    private static func tokenForLastHistoryEntry(_ entry: BitcoinSVProvider.WhatsOnChainHistoryEntry?) -> String {
        guard let entry else { return "" }
        let height = entry.height.map(String.init) ?? ""
        return height.isEmpty ? entry.txHash : "\(height):\(entry.txHash)"
    }

    private static func normalizedAddress(_ address: String) throws -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return encoded
    }

    private static func ownAddressVariants(for address: String) -> Set<String> {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return [trimmed, lowered]
    }

    nonisolated private static func sanitizeUTXOs(_ utxos: [BitcoinSVUTXO]) -> [BitcoinSVUTXO] {
        var deduplicated: [String: BitcoinSVUTXO] = [:]
        for utxo in utxos where !utxo.txid.isEmpty && utxo.vout >= 0 && utxo.value > 0 {
            let key = outpointKey(hash: utxo.txid, index: utxo.vout)
            if let existing = deduplicated[key] {
                guard existing.value == utxo.value else {
                    continue
                }
            }
            deduplicated[key] = utxo
        }
        return deduplicated.values.sorted {
            if $0.value == $1.value {
                return outpointKey(hash: $0.txid, index: $0.vout) < outpointKey(hash: $1.txid, index: $1.vout)
            }
            return $0.value > $1.value
        }
    }

    nonisolated private static func mergeConsistentUTXOs(
        whatsonchainUTXOs: [BitcoinSVUTXO],
        blockchairUTXOs: [BitcoinSVUTXO]
    ) throws -> [BitcoinSVUTXO] {
        guard !whatsonchainUTXOs.isEmpty else { return blockchairUTXOs }
        guard !blockchairUTXOs.isEmpty else { return whatsonchainUTXOs }

        let whatsonchainByOutpoint = Dictionary(uniqueKeysWithValues: whatsonchainUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })
        let blockchairByOutpoint = Dictionary(uniqueKeysWithValues: blockchairUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })
        let overlappingKeys = Set(whatsonchainByOutpoint.keys).intersection(blockchairByOutpoint.keys)

        guard !overlappingKeys.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        for key in overlappingKeys {
            guard whatsonchainByOutpoint[key]?.value == blockchairByOutpoint[key]?.value else {
                throw URLError(.cannotParseResponse)
            }
        }

        var merged = whatsonchainByOutpoint
        for (key, utxo) in blockchairByOutpoint where merged.index(forKey: key) == nil {
            merged[key] = utxo
        }
        return merged.values.sorted {
            if $0.value == $1.value {
                return outpointKey(hash: $0.txid, index: $0.vout) < outpointKey(hash: $1.txid, index: $1.vout)
            }
            return $0.value > $1.value
        }
    }

    nonisolated private static func outpointKey(hash: String, index: Int) -> String {
        "\(hash.lowercased()):\(index)"
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
