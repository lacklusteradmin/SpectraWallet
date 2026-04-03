import Foundation

struct BitcoinCashHistorySnapshot: Equatable {
    let txid: String
    let amountBCH: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}

struct BitcoinCashHistoryPage {
    let snapshots: [BitcoinCashHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}

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
    private static let blockchairTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    private static let satoshisPerBCH: Double = 100_000_000

    static func endpointCatalog() -> [String] {
        BitcoinCashProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        BitcoinCashProvider.diagnosticsChecks()
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await BitcoinCashProvider.runWithFallback(candidates: BitcoinCashProvider.ProviderID.allCases) { provider in
            switch provider {
            case .blockchair:
                let dashboard = try await fetchBlockchairAddressDashboard(for: trimmed, limit: 1, offset: 0)
                let balance = max(0, dashboard.address.balance ?? 0)
                return Double(balance) / satoshisPerBCH
            case .actorforth:
                let details = try await fetchActorForthAddressDetails(for: trimmed)
                let balance = max(0, details.balanceSat ?? 0)
                return Double(balance) / satoshisPerBCH
            }
        }
    }

    static func hasTransactionHistory(for address: String) async throws -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        return try await BitcoinCashProvider.runWithFallback(candidates: BitcoinCashProvider.ProviderID.allCases) { provider in
            switch provider {
            case .blockchair:
                let dashboard = try await fetchBlockchairAddressDashboard(for: trimmed, limit: 1, offset: 0)
                return !(dashboard.transactions.isEmpty) || (dashboard.address.transactionCount ?? 0) > 0
            case .actorforth:
                let details = try await fetchActorForthAddressDetails(for: trimmed)
                return !(details.transactions ?? []).isEmpty || (details.txApperances ?? 0) > 0
            }
        }
    }

    static func fetchUTXOs(for address: String) async throws -> [BitcoinCashUTXO] {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.badURL)
        }
        let blockchairUTXOs = try? await fetchBlockchairUTXOs(for: trimmed)
        let actorforthUTXOs = try? await fetchActorForthResolvedUTXOs(for: trimmed)

        switch (blockchairUTXOs, actorforthUTXOs) {
        case let (.some(blockchair), .some(actorforth)):
            return try mergeConsistentUTXOs(
                blockchairUTXOs: blockchair,
                actorforthUTXOs: actorforth
            )
        case let (.some(blockchair), .none):
            return blockchair
        case let (.none, .some(actorforth)):
            return actorforth
        case (.none, .none):
            throw URLError(.cannotLoadFromNetwork)
        }
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

    static func fetchTransactionPage(
        for address: String,
        limit: Int,
        cursor: String? = nil
    ) async throws -> BitcoinCashHistoryPage {
        let offset = Int(cursor ?? "0") ?? 0
        let dashboard = try await fetchBlockchairAddressDashboard(for: address, limit: limit, offset: offset)
        let ownAddresses = ownAddressVariants(for: address)
        let txids = Array(dashboard.transactions.prefix(limit))
        var snapshots: [BitcoinCashHistorySnapshot] = []

        for txid in txids {
            let transaction = try await fetchBlockchairTransactionDetails(txid: txid)
            let snapshot = snapshot(for: transaction, ownAddresses: ownAddresses)
            snapshots.append(snapshot)
        }

        let nextOffset = offset + txids.count
        let hasMore = (dashboard.address.transactionCount ?? 0) > nextOffset
        return BitcoinCashHistoryPage(
            snapshots: snapshots.sorted { $0.createdAt > $1.createdAt },
            nextCursor: hasMore ? String(nextOffset) : nil,
            sourceUsed: "blockchair"
        )
    }

    private static func fetchBlockchairAddressDashboard(
        for address: String,
        limit: Int,
        offset: Int
    ) async throws -> BitcoinCashProvider.AddressDashboard {
        guard let url = BitcoinCashProvider.blockchairAddressDashboardURL(address: address, limit: limit, offset: offset) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BitcoinCashProvider.BlockchairAddressResponse.self, from: data)
        if let dashboard = decoded.data[address] {
            return dashboard
        }
        if let dashboard = decoded.data.values.first {
            return dashboard
        }
        throw URLError(.cannotParseResponse)
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

    private static func fetchActorForthAddressDetails(for address: String) async throws -> BitcoinCashProvider.ActorForthAddressDetails {
        guard let url = BitcoinCashProvider.actorForthAddressDetailsURL(address: address) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(BitcoinCashProvider.ActorForthEnvelope<BitcoinCashProvider.ActorForthAddressDetails>.self, from: data)
        guard let payload = envelope.data else {
            throw URLError(.cannotParseResponse)
        }
        return payload
    }

    private static func fetchActorForthUTXOs(for address: String) async throws -> BitcoinCashProvider.ActorForthUTXOPayload {
        guard let url = BitcoinCashProvider.actorForthUTXOsURL(address: address) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(BitcoinCashProvider.ActorForthEnvelope<BitcoinCashProvider.ActorForthUTXOPayload>.self, from: data)
        guard let payload = envelope.data else {
            throw URLError(.cannotParseResponse)
        }
        return payload
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

    private static func fetchBlockchairUTXOs(for address: String) async throws -> [BitcoinCashUTXO] {
        let dashboard = try await fetchBlockchairAddressDashboard(for: address, limit: 100, offset: 0)
        return sanitizeUTXOs((dashboard.utxo ?? []).map {
            BitcoinCashUTXO(txid: $0.transactionHash, vout: $0.index, value: $0.value)
        })
    }

    private static func fetchActorForthResolvedUTXOs(for address: String) async throws -> [BitcoinCashUTXO] {
        let payload = try await fetchActorForthUTXOs(for: address)
        return sanitizeUTXOs((payload.utxos ?? []).compactMap { entry in
            guard let txid = entry.txid,
                  let vout = entry.vout,
                  let satoshis = entry.satoshis else {
                return nil
            }
            return BitcoinCashUTXO(txid: txid, vout: vout, value: satoshis)
        })
    }

    nonisolated private static func sanitizeUTXOs(_ utxos: [BitcoinCashUTXO]) -> [BitcoinCashUTXO] {
        var deduplicated: [String: BitcoinCashUTXO] = [:]
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
        blockchairUTXOs: [BitcoinCashUTXO],
        actorforthUTXOs: [BitcoinCashUTXO]
    ) throws -> [BitcoinCashUTXO] {
        guard !blockchairUTXOs.isEmpty else { return actorforthUTXOs }
        guard !actorforthUTXOs.isEmpty else { return blockchairUTXOs }

        let blockchairByOutpoint = Dictionary(uniqueKeysWithValues: blockchairUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })
        let actorforthByOutpoint = Dictionary(uniqueKeysWithValues: actorforthUTXOs.map { (outpointKey(hash: $0.txid, index: $0.vout), $0) })
        let overlappingKeys = Set(blockchairByOutpoint.keys).intersection(actorforthByOutpoint.keys)

        guard !overlappingKeys.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        for key in overlappingKeys {
            guard blockchairByOutpoint[key]?.value == actorforthByOutpoint[key]?.value else {
                throw URLError(.cannotParseResponse)
            }
        }

        var merged = blockchairByOutpoint
        for (key, utxo) in actorforthByOutpoint where merged.index(forKey: key) == nil {
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

    private static func snapshot(
        for transaction: BitcoinCashProvider.TransactionDashboard,
        ownAddresses: Set<String>
    ) -> BitcoinCashHistorySnapshot {
        let outgoingValue = transaction.inputs.reduce(Int64(0)) { partialResult, input in
            guard let recipient = input.recipient?.lowercased(), ownAddresses.contains(recipient) else {
                return partialResult
            }
            return partialResult + max(0, input.value ?? 0)
        }
        let incomingOutputs = transaction.outputs.filter { output in
            guard let recipient = output.recipient?.lowercased() else { return false }
            return ownAddresses.contains(recipient)
        }
        let incomingValue = incomingOutputs.reduce(Int64(0)) { $0 + max(0, $1.value ?? 0) }
        let amount = max(0, incomingValue - outgoingValue)
        let isReceive = incomingValue >= outgoingValue

        let counterparty = if isReceive {
            transaction.inputs.compactMap(\.recipient).first ?? "Unknown"
        } else {
            transaction.outputs.first { output in
                guard let recipient = output.recipient?.lowercased() else { return false }
                return !ownAddresses.contains(recipient)
            }?.recipient ?? "Unknown"
        }

        let createdAt = parseDate(transaction.transaction.time) ?? Date()
        return BitcoinCashHistorySnapshot(
            txid: transaction.transaction.hash,
            amountBCH: Double(abs(amount)) / satoshisPerBCH,
            kind: isReceive ? .receive : .send,
            status: transaction.transaction.blockID == nil ? .pending : .confirmed,
            counterpartyAddress: counterparty,
            blockHeight: transaction.transaction.blockID,
            createdAt: createdAt
        )
    }

    private static func ownAddressVariants(for address: String) -> Set<String> {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var variants: Set<String> = [trimmed]
        if trimmed.hasPrefix("bitcoincash:") {
            variants.insert(String(trimmed.dropFirst("bitcoincash:".count)))
        } else {
            variants.insert("bitcoincash:\(trimmed)")
        }
        return variants
    }

    private static func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue else { return nil }
        return blockchairTimestampFormatter.date(from: rawValue)
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(from: url, profile: .chainRead)
    }
}
