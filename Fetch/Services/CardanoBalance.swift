import Foundation

enum CardanoBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Cardano")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Cardano")
        case .httpError(let code):
            let format = AppLocalization.string("The Cardano provider returned HTTP %d.")
            return String(format: format, locale: AppLocalization.locale, code)
        }
    }
}

struct CardanoHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct CardanoHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum CardanoBalanceService {
    nonisolated(unsafe) private static let iso8601Formatter = ISO8601DateFormatter()

    private enum Provider: String, CaseIterable {
        case koiosV1
        case koiosXray
        case koiosHappyStaking
    }

    private static func baseURL(for provider: Provider) -> String {
        switch provider {
        case .koiosV1:
            return ChainBackendRegistry.CardanoRuntimeEndpoints.koiosBaseURLs[0]
        case .koiosXray:
            return ChainBackendRegistry.CardanoRuntimeEndpoints.koiosBaseURLs[1]
        case .koiosHappyStaking:
            return ChainBackendRegistry.CardanoRuntimeEndpoints.koiosBaseURLs[2]
        }
    }

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.cardanoChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.cardanoChainName)
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidCardanoAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            throw CardanoBalanceServiceError.invalidAddress
        }
        return try await runWithProviderFallback(candidates: Provider.allCases) { provider in
            let rows = try await fetchAddressInfoRows(for: normalized, baseURL: baseURL(for: provider))
            guard let first = rows.first else { return 0 }

            if let stakeAddress = resolvedStakeAddress(from: first, fallbackAddress: normalized),
               let accountLovelace = try await fetchAccountBalance(for: stakeAddress, baseURL: baseURL(for: provider)) {
                return max(0, accountLovelace / 1_000_000.0)
            }

            let lovelaceValue = parseLovelaceValue(first["balance"])
            guard let lovelace = lovelaceValue, lovelace.isFinite else {
                throw CardanoBalanceServiceError.invalidResponse
            }

            return max(0, lovelace / 1_000_000.0)
        }
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 80) async -> (snapshots: [CardanoHistorySnapshot], diagnostics: CardanoHistoryDiagnostics) {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            return (
                [],
                CardanoHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: CardanoBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let providers = Provider.allCases
        var lastError = CardanoBalanceServiceError.invalidResponse.localizedDescription
        for provider in providers {
            do {
                let base = baseURL(for: provider)
                let boundedLimit = max(1, min(limit, 200))
                var historyRows = try await fetchAddressTransactionRows(
                    for: normalized,
                    baseURL: base,
                    limit: boundedLimit
                )

                if historyRows.isEmpty,
                   let addressRows = try? await fetchAddressInfoRows(for: normalized, baseURL: base),
                   let first = addressRows.first,
                   let stakeAddress = resolvedStakeAddress(from: first, fallbackAddress: normalized),
                   let accountRows = try? await fetchAccountTransactionRows(
                       for: stakeAddress,
                       baseURL: base,
                       limit: boundedLimit
                   ),
                   !accountRows.isEmpty {
                    historyRows = accountRows
                }

                let historyHashes = historyRows.compactMap(parseTransactionHash(from:))
                let detailsByHash = try await fetchTransactionDetailsByHash(
                    hashes: historyHashes,
                    baseURL: base
                )
                let snapshots: [CardanoHistorySnapshot] = historyRows.reduce(into: []) { partialResult, row in
                    guard let hash = parseTransactionHash(from: row),
                          !hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return
                    }

                    let detail = detailsByHash[hash.lowercased()]
                    let blockTime = parseTransactionTimestamp(from: detail ?? row) ?? parseTransactionTimestamp(from: row) ?? 0
                    let createdAt = blockTime > 0 ? Date(timeIntervalSince1970: blockTime) : Date()
                    let resolved = resolveHistorySnapshot(
                        hash: hash,
                        primaryAddress: normalized,
                        detail: detail,
                        createdAt: createdAt
                    )

                    partialResult.append(
                        CardanoHistorySnapshot(
                            transactionHash: hash,
                            kind: resolved.kind,
                            amount: resolved.amount,
                            counterpartyAddress: resolved.counterpartyAddress,
                            createdAt: resolved.createdAt,
                            status: .confirmed
                        )
                    )
                }

                return (
                    snapshots,
                    CardanoHistoryDiagnostics(
                        address: normalized,
                        sourceUsed: provider.rawValue,
                        transactionCount: snapshots.count,
                        error: nil
                    )
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        return (
            [],
            CardanoHistoryDiagnostics(
                address: normalized,
                sourceUsed: "none",
                transactionCount: 0,
                error: lastError
            )
        )
    }

    static func verifyTransactionIfAvailable(_ transactionHash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHash.isEmpty else {
            return .deferred
        }

        var lastError: String?
        for provider in Provider.allCases {
            do {
                let detailsByHash = try await fetchTransactionDetailsByHash(
                    hashes: [normalizedHash],
                    baseURL: baseURL(for: provider)
                )
                if detailsByHash[normalizedHash] != nil {
                    return .verified
                }
            } catch {
                lastError = error.localizedDescription
            }
        }

        if let lastError {
            return .failed(lastError)
        }
        return .deferred
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(for: request, profile: .chainRead)
    }

    private static func fetchAddressInfoRows(for normalizedAddress: String, baseURL: String) async throws -> [[String: Any]] {
        guard let postURL = URL(string: "\(baseURL)/address_info") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var postRequest = URLRequest(url: postURL)
        postRequest.httpMethod = "POST"
        postRequest.timeoutInterval = 20
        postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postRequest.httpBody = try JSONSerialization.data(withJSONObject: ["_addresses": [normalizedAddress]], options: [])

        let (postData, postResponse) = try await fetchData(for: postRequest)
        guard let postHTTP = postResponse as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(postHTTP.statusCode) else {
            throw CardanoBalanceServiceError.httpError(postHTTP.statusCode)
        }
        if let postRows = try JSONSerialization.jsonObject(with: postData, options: []) as? [[String: Any]],
           !postRows.isEmpty {
            return postRows
        }

        guard let encodedAddress = normalizedAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let getURL = URL(string: "\(baseURL)/address_info?_address=eq.\(encodedAddress)") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var getRequest = URLRequest(url: getURL)
        getRequest.timeoutInterval = 20
        let (getData, getResponse) = try await fetchData(for: getRequest)
        guard let getHTTP = getResponse as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(getHTTP.statusCode) else {
            throw CardanoBalanceServiceError.httpError(getHTTP.statusCode)
        }
        guard let getRows = try JSONSerialization.jsonObject(with: getData, options: []) as? [[String: Any]] else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        return getRows
    }

    private static func fetchAccountBalance(for stakeAddress: String, baseURL: String) async throws -> Double? {
        guard let postURL = URL(string: "\(baseURL)/account_info") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var postRequest = URLRequest(url: postURL)
        postRequest.httpMethod = "POST"
        postRequest.timeoutInterval = 20
        postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postRequest.httpBody = try JSONSerialization.data(withJSONObject: ["_stake_addresses": [stakeAddress]], options: [])

        let (postData, postResponse) = try await fetchData(for: postRequest)
        guard let postHTTP = postResponse as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(postHTTP.statusCode) else {
            throw CardanoBalanceServiceError.httpError(postHTTP.statusCode)
        }
        if let postRows = try JSONSerialization.jsonObject(with: postData, options: []) as? [[String: Any]],
           let first = postRows.first {
            return parseAccountBalance(first)
        }

        guard let encodedStakeAddress = stakeAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let getURL = URL(string: "\(baseURL)/account_info?_stake_address=eq.\(encodedStakeAddress)") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var getRequest = URLRequest(url: getURL)
        getRequest.timeoutInterval = 20
        let (getData, getResponse) = try await fetchData(for: getRequest)
        guard let getHTTP = getResponse as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(getHTTP.statusCode) else {
            throw CardanoBalanceServiceError.httpError(getHTTP.statusCode)
        }
        guard let getRows = try JSONSerialization.jsonObject(with: getData, options: []) as? [[String: Any]],
              let first = getRows.first else {
            return nil
        }
        return parseAccountBalance(first)
    }

    private static func fetchAccountTransactionRows(for stakeAddress: String, baseURL: String, limit: Int) async throws -> [[String: Any]] {
        guard let encodedStakeAddress = stakeAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let getURL = URL(string: "\(baseURL)/account_txs?_stake_address=\(encodedStakeAddress)") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var getRequest = URLRequest(url: getURL)
        getRequest.timeoutInterval = 20
        let (getData, getResponse) = try await fetchData(for: getRequest)
        guard let getHTTP = getResponse as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(getHTTP.statusCode) else {
            throw CardanoBalanceServiceError.httpError(getHTTP.statusCode)
        }
        guard let getRows = try JSONSerialization.jsonObject(with: getData, options: []) as? [[String: Any]] else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        return limitedSortedTransactionRows(getRows, limit: limit)
    }

    private static func fetchAddressTransactionRows(for normalizedAddress: String, baseURL: String, limit: Int) async throws -> [[String: Any]] {
        guard let postURL = URL(string: "\(baseURL)/address_txs") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var postRequest = URLRequest(url: postURL)
        postRequest.httpMethod = "POST"
        postRequest.timeoutInterval = 20
        postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postRequest.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "_addresses": [normalizedAddress]
            ],
            options: []
        )

        let (postData, postResponse) = try await fetchData(for: postRequest)
        guard let postHTTP = postResponse as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(postHTTP.statusCode) else {
            throw CardanoBalanceServiceError.httpError(postHTTP.statusCode)
        }
        if let postRows = try JSONSerialization.jsonObject(with: postData, options: []) as? [[String: Any]] {
            return limitedSortedTransactionRows(postRows, limit: limit)
        }

        guard let encodedAddress = normalizedAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let getURL = URL(string: "\(baseURL)/address_txs?_address=\(encodedAddress)") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var getRequest = URLRequest(url: getURL)
        getRequest.timeoutInterval = 20
        let (getData, getResponse) = try await fetchData(for: getRequest)
        guard let getHTTP = getResponse as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(getHTTP.statusCode) else {
            throw CardanoBalanceServiceError.httpError(getHTTP.statusCode)
        }
        guard let getRows = try JSONSerialization.jsonObject(with: getData, options: []) as? [[String: Any]] else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        return limitedSortedTransactionRows(getRows, limit: limit)
    }

    private static func fetchTransactionDetailsByHash(hashes: [String], baseURL: String) async throws -> [String: [String: Any]] {
        let uniqueHashes = Array(Set(hashes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !uniqueHashes.isEmpty else { return [:] }
        guard let postURL = URL(string: "\(baseURL)/tx_info") else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        var postRequest = URLRequest(url: postURL)
        postRequest.httpMethod = "POST"
        postRequest.timeoutInterval = 20
        postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postRequest.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "_tx_hashes": uniqueHashes,
                "_inputs": true
            ],
            options: []
        )

        let (data, response) = try await fetchData(for: postRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CardanoBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw CardanoBalanceServiceError.httpError(http.statusCode)
        }
        guard let rows = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            throw CardanoBalanceServiceError.invalidResponse
        }

        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let hash = parseTransactionHash(from: row)?.lowercased() else { return nil }
            return (hash, row)
        })
    }

    private static func parseAccountBalance(_ row: [String: Any]) -> Double? {
        parseLovelaceValue(row["total_balance"])
            ?? parseLovelaceValue(row["controlled_total_stake"])
            ?? parseLovelaceValue(row["balance"])
    }

    nonisolated private static func parseTransactionHash(from row: [String: Any]) -> String? {
        let keys = ["tx_hash", "hash"]
        for key in keys {
            if let value = row[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated private static func parseTransactionTimestamp(from row: [String: Any]) -> TimeInterval? {
        let candidates: [Any?] = [
            row["block_time"],
            row["tx_timestamp"],
            row["time"]
        ]

        for candidate in candidates {
            if let interval = parseTimeInterval(candidate) {
                return interval
            }
        }

        return nil
    }

    nonisolated private static func resolveHistorySnapshot(
        hash: String,
        primaryAddress: String,
        detail: [String: Any]?,
        createdAt: Date
    ) -> (kind: TransactionKind, amount: Double, counterpartyAddress: String, createdAt: Date) {
        guard let detail else {
            return (.receive, 0, "", createdAt)
        }

        let normalizedAddress = primaryAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let inputs = (detail["inputs"] as? [[String: Any]]) ?? []
        let outputs = (detail["outputs"] as? [[String: Any]]) ?? []

        let ownInputTotal = inputs.reduce(0.0) { running, row in
            running + (isCardanoHistoryAddressMatch(row, normalizedAddress: normalizedAddress) ? (parseLovelaceValue(row["value"]) ?? 0) : 0)
        }
        let ownOutputTotal = outputs.reduce(0.0) { running, row in
            running + (isCardanoHistoryAddressMatch(row, normalizedAddress: normalizedAddress) ? (parseLovelaceValue(row["value"]) ?? 0) : 0)
        }
        let externalOutputs = outputs.filter { !isCardanoHistoryAddressMatch($0, normalizedAddress: normalizedAddress) }
        let externalOutputTotal = externalOutputs.reduce(0.0) { $0 + (parseLovelaceValue($1["value"]) ?? 0) }
        let externalInputs = inputs.filter { !isCardanoHistoryAddressMatch($0, normalizedAddress: normalizedAddress) }

        if ownInputTotal > 0, externalOutputTotal > 0 {
            return (
                .send,
                max(0, externalOutputTotal / 1_000_000.0),
                externalOutputs.compactMap(cardanoHistoryAddressString(from:)).first ?? "",
                createdAt
            )
        }

        if ownOutputTotal > 0 {
            return (
                .receive,
                max(0, ownOutputTotal / 1_000_000.0),
                externalInputs.compactMap(cardanoHistoryAddressString(from:)).first ?? "",
                createdAt
            )
        }

        if ownInputTotal > 0 {
            let fee = parseLovelaceValue(detail["fee"]) ?? 0
            return (
                .send,
                max(0, (ownInputTotal - ownOutputTotal - fee) / 1_000_000.0),
                externalOutputs.compactMap(cardanoHistoryAddressString(from:)).first ?? "",
                createdAt
            )
        }

        return (.receive, 0, "", createdAt)
    }

    nonisolated private static func isCardanoHistoryAddressMatch(_ row: [String: Any], normalizedAddress: String) -> Bool {
        cardanoHistoryAddressString(from: row)?.lowercased() == normalizedAddress
    }

    nonisolated private static func cardanoHistoryAddressString(from row: [String: Any]) -> String? {
        if let paymentAddress = row["payment_addr"] as? [String: Any],
           let bech32 = paymentAddress["bech32"] as? String,
           !bech32.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bech32
        }
        if let address = row["address"] as? String,
           !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return address
        }
        return nil
    }

    nonisolated private static func limitedSortedTransactionRows(_ rows: [[String: Any]], limit: Int) -> [[String: Any]] {
        let sorted = rows.sorted { lhs, rhs in
            let lhsHeight = parseTimeInterval(lhs["block_height"]) ?? 0
            let rhsHeight = parseTimeInterval(rhs["block_height"]) ?? 0
            if lhsHeight != rhsHeight {
                return lhsHeight > rhsHeight
            }

            let lhsTime = parseTransactionTimestamp(from: lhs) ?? 0
            let rhsTime = parseTransactionTimestamp(from: rhs) ?? 0
            return lhsTime > rhsTime
        }

        return Array(sorted.prefix(max(1, limit)))
    }

    nonisolated private static func parseTimeInterval(_ raw: Any?) -> TimeInterval? {
        if let interval = raw as? TimeInterval {
            return interval
        }
        if let intValue = raw as? Int {
            return TimeInterval(intValue)
        }
        if let int64Value = raw as? Int64 {
            return TimeInterval(int64Value)
        }
        if let number = raw as? NSNumber {
            return number.doubleValue
        }
        if let text = raw as? String {
            if let interval = TimeInterval(text) {
                return interval
            }
            if let date = iso8601Formatter.date(from: text) {
                return date.timeIntervalSince1970
            }
        }
        return nil
    }

    private static func resolvedStakeAddress(from row: [String: Any], fallbackAddress: String) -> String? {
        if let stakeAddress = row["stake_address"] as? String,
           !stakeAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stakeAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return extractStakeAddress(from: fallbackAddress)
    }

    private static func extractStakeAddress(from paymentAddress: String) -> String? {
        let lower = paymentAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("addr1") || lower.hasPrefix("addr_test1") else { return nil }
        guard let decoded = decodeBech32Payload(address: lower), decoded.count >= 57 else { return nil }

        let header = decoded[0]
        let addressType = header >> 4
        let networkID = header & 0x0f
        guard addressType <= 3 else { return nil }

        let stakeKeyHash = decoded.subdata(in: 29 ..< 57)
        let rewardHeader: UInt8 = 0xe0 | networkID
        let rewardData = Data([rewardHeader]) + stakeKeyHash
        let hrp = networkID == 0 ? "stake_test" : "stake"
        return encodeBech32(hrp: hrp, payload: rewardData)
    }

    nonisolated private static func parseLovelaceValue(_ raw: Any?) -> Double? {
        if let text = raw as? String {
            return Double(text)
        }
        if let number = raw as? NSNumber {
            return number.doubleValue
        }
        if let intValue = raw as? Int {
            return Double(intValue)
        }
        if let int64Value = raw as? Int64 {
            return Double(int64Value)
        }
        if let uint64Value = raw as? UInt64 {
            return Double(uint64Value)
        }
        return nil
    }

    private static func decodeBech32Payload(address: String) -> Data? {
        guard let separatorIndex = address.lastIndex(of: "1") else { return nil }
        let hrp = String(address[..<separatorIndex])
        let dataPart = String(address[address.index(after: separatorIndex)...])
        guard !hrp.isEmpty, dataPart.count >= 6 else { return nil }

        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        var charsetMap: [Character: Int] = [:]
        for (index, character) in charset.enumerated() {
            charsetMap[character] = index
        }

        let values: [UInt8] = dataPart.compactMap { character in
            guard let value = charsetMap[character] else { return nil }
            return UInt8(value)
        }
        guard values.count == dataPart.count else { return nil }
        guard verifyBech32Checksum(hrp: hrp, data: values) else { return nil }

        let payload5Bit = Array(values.dropLast(6))
        guard let payload = convertBits(payload5Bit, fromBits: 5, toBits: 8, pad: false) else { return nil }
        return Data(payload)
    }

    private static func encodeBech32(hrp: String, payload: Data) -> String? {
        guard let converted = convertBits(Array(payload), fromBits: 8, toBits: 5, pad: true) else { return nil }
        let checksum = bech32Checksum(hrp: hrp, data: converted)
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let encodedData = (converted + checksum).map { charset[Int($0)] }
        return hrp + "1" + String(encodedData)
    }

    private static func verifyBech32Checksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    private static func bech32Checksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let mod = polymod(values) ^ 1
        return (0 ..< 6).map { index in
            UInt8((mod >> (5 * (5 - index))) & 31)
        }
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = hrp.utf8.map { UInt8($0) }
        let high = bytes.map { $0 >> 5 }
        let low = bytes.map { $0 & 0x1f }
        return high + [0] + low
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var check: UInt32 = 1
        for value in values {
            let top = check >> 25
            check = ((check & 0x1ffffff) << 5) ^ UInt32(value)
            for index in 0 ..< 5 where ((top >> index) & 1) != 0 {
                check ^= generators[index]
            }
        }
        return check
    }

    private static func convertBits(_ data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var result: [UInt8] = []
        let maxValue = (1 << toBits) - 1
        for value in data {
            let intValue = Int(value)
            if (intValue >> fromBits) != 0 { return nil }
            accumulator = (accumulator << fromBits) | intValue
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }
        if pad {
            if bits > 0 {
                result.append(UInt8((accumulator << (toBits - bits)) & maxValue))
            }
        } else if bits >= fromBits || ((accumulator << (toBits - bits)) & maxValue) != 0 {
            return nil
        }
        return result
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
