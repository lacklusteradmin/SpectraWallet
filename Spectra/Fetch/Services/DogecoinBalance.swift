import Foundation

struct DogecoinTransactionStatus {
    let confirmed: Bool
    let blockHeight: Int?
    let networkFeeDOGE: Double?
    let confirmations: Int?
}

enum DogecoinBalanceService {
    typealias NetworkMode = DogecoinNetworkMode

    private static let iso8601Formatter = ISO8601DateFormatter()

    struct AddressTransactionSnapshot {
        let hash: String
        let kind: TransactionKind
        let status: TransactionStatus
        let amount: Double
        let counterpartyAddress: String
        let createdAt: Date
        let blockNumber: Int?
    }

    struct DogecoinHistoryPage {
        let snapshots: [AddressTransactionSnapshot]
        let nextCursor: String?
        let sourceUsed: String
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

    static func fetchBalance(for address: String, networkMode: NetworkMode = .mainnet) async throws -> Double {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDogecoinAddress(trimmedAddress, networkMode: networkMode) else {
            throw URLError(.badURL)
        }

        return try await fetchBalanceViaBlockcypher(for: trimmedAddress, networkMode: networkMode)
    }

    private static func fetchBalanceViaBlockcypher(for address: String, networkMode: NetworkMode) async throws -> Double {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/addrs/\(encodedAddress)/balance", networkMode: networkMode) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await fetchData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(BlockCypherProvider.AddressBalanceResponse.self, from: data)
        let balanceKoinu = max(0, payload.finalBalance ?? payload.balance ?? 0)
        return Double(balanceKoinu) / 100_000_000
    }

    static func fetchRecentTransactions(
        for address: String,
        limit: Int = 15,
        networkMode: NetworkMode = .mainnet
    ) async throws -> [AddressTransactionSnapshot] {
        try await fetchTransactionPage(for: address, limit: limit, cursor: nil, networkMode: networkMode).snapshots
    }

    static func fetchTransactionPage(
        for address: String,
        limit: Int = 15,
        cursor: String? = nil,
        networkMode: NetworkMode = .mainnet
    ) async throws -> DogecoinHistoryPage {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDogecoinAddress(trimmedAddress, networkMode: networkMode) else {
            throw URLError(.badURL)
        }

        let clampedLimit = max(1, min(limit, 200))
        let offset = max(0, Int(cursor ?? "") ?? 0)
        let reconciled = try await fetchRecentTransactionsViaBlockcypher(
            for: trimmedAddress,
            limit: clampedLimit,
            networkMode: networkMode
        ).sorted { $0.createdAt > $1.createdAt }
        if offset >= reconciled.count {
            return DogecoinHistoryPage(snapshots: [], nextCursor: nil, sourceUsed: "dogecoin.blockcypher")
        }
        let paged = Array(reconciled.dropFirst(offset).prefix(clampedLimit))
        let nextCursor = (offset + clampedLimit) < reconciled.count ? String(offset + clampedLimit) : nil
        return DogecoinHistoryPage(snapshots: paged, nextCursor: nextCursor, sourceUsed: "dogecoin.blockcypher")
    }

    private static func fetchRecentTransactionsViaBlockcypher(
        for address: String,
        limit: Int,
        networkMode: NetworkMode
    ) async throws -> [AddressTransactionSnapshot] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let addressURL = blockcypherURL(path: "/addrs/\(encodedAddress)?limit=\(limit)&unspentOnly=false&includeScript=false", networkMode: networkMode) else {
            throw URLError(.badURL)
        }

        let (addressData, addressResponse) = try await fetchData(from: addressURL)
        guard let addressHTTPResponse = addressResponse as? HTTPURLResponse, (200 ..< 300).contains(addressHTTPResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let addressPayload = try JSONDecoder().decode(BlockCypherProvider.AddressRefsResponse.self, from: addressData)
        let allRefs = (addressPayload.txrefs ?? []) + (addressPayload.unconfirmedTxrefs ?? [])
        let hashes = Array(Set(allRefs.map(\.txHash))).prefix(limit)
        guard !hashes.isEmpty else { return [] }

        var snapshots: [AddressTransactionSnapshot] = []
        for hash in hashes {
            guard let encodedHash = hash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let txURL = blockcypherURL(path: "/txs/\(encodedHash)", networkMode: networkMode) else {
                continue
            }

            do {
                let (txData, txResponse) = try await fetchData(from: txURL)
                guard let txHTTPResponse = txResponse as? HTTPURLResponse, (200 ..< 300).contains(txHTTPResponse.statusCode) else {
                    continue
                }
                let payload = try JSONDecoder().decode(BlockCypherProvider.TransactionDetailResponse.self, from: txData)
                guard let txHash = payload.hash else { continue }
                let snapshot = mapTransactionSnapshot(
                    txHash: txHash,
                    timestamp: parseBlockcypherTimestamp(payload.received),
                    blockHeight: payload.blockHeight,
                    confirmations: payload.confirmations,
                    inputTransfers: (payload.inputs ?? []).map { (recipient: $0.addresses?.first, value: $0.outputValue ?? $0.value) },
                    outputTransfers: (payload.outputs ?? []).map { (recipient: $0.addresses?.first, value: $0.value) },
                    walletAddress: address.lowercased(),
                    defaultCounterparty: address
                )
                if let snapshot {
                    snapshots.append(snapshot)
                }
            } catch {
                continue
            }
        }

        return snapshots
    }

    private static func mapTransactionSnapshot(
        txHash: String,
        timestamp: Date?,
        blockHeight: Int?,
        confirmations: Int?,
        inputTransfers: [(recipient: String?, value: Int64?)],
        outputTransfers: [(recipient: String?, value: Int64?)],
        walletAddress: String,
        defaultCounterparty: String
    ) -> AddressTransactionSnapshot? {
        let incomingValue = outputTransfers.reduce(Int64(0)) { partialResult, output in
            guard output.recipient?.lowercased() == walletAddress else { return partialResult }
            return partialResult + max(0, output.value ?? 0)
        }

        let outgoingValue = inputTransfers.reduce(Int64(0)) { partialResult, input in
            guard input.recipient?.lowercased() == walletAddress else { return partialResult }
            return partialResult + max(0, input.value ?? 0)
        }

        let netValue = incomingValue - outgoingValue
        guard netValue != 0 else { return nil }

        let kind: TransactionKind = netValue > 0 ? .receive : .send
        let amount = Double(abs(netValue)) / 100_000_000

        let counterparty: String
        if kind == .receive {
            counterparty = inputTransfers.first(where: { $0.recipient?.lowercased() != walletAddress })?.recipient ?? defaultCounterparty
        } else {
            counterparty = outputTransfers.first(where: { $0.recipient?.lowercased() != walletAddress })?.recipient ?? defaultCounterparty
        }

        let isPending: Bool
        if let confirmations {
            isPending = confirmations <= 0
        } else {
            isPending = blockHeight == nil
        }

        return AddressTransactionSnapshot(
            hash: txHash,
            kind: kind,
            status: isPending ? .pending : .confirmed,
            amount: amount,
            counterpartyAddress: counterparty,
            createdAt: timestamp ?? Date.distantPast,
            blockNumber: blockHeight
        )
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

    private static func parseBlockcypherTimestamp(_ timestamp: String?) -> Date? {
        guard let timestamp else { return nil }
        return iso8601Formatter.date(from: timestamp)
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(from: url, profile: .chainRead)
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(for: request, profile: .chainRead)
    }
}
