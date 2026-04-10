import Foundation
import CryptoKit

enum TronBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Tron")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Tron")
        case .httpError(let status):
            let format = AppLocalization.string("The Tron provider returned HTTP %d.")
            return String(format: format, locale: AppLocalization.locale, status)
        }
    }
}

struct TronTokenBalanceSnapshot: Equatable {
    let symbol: String
    let contractAddress: String?
    let balance: Double
}

struct TronHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let symbol: String
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct TronHistoryDiagnostics: Equatable {
    let address: String
    let tronScanTxCount: Int
    let tronScanTRC20Count: Int
    let sourceUsed: String
    let error: String?
}

enum TronBalanceService {
    static let usdtTronContract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    static let usddTronContract = "TXDk8mbtRbXeYuMNS83CfKPaYYT8XWv9Hz"
    static let usd1TronContract = "TPFqcBAaaUMCSVRCqPaQ9QnzKhmuoLR6Rc"
    static let bttTronContract = "TAFjULxiVgT4qWk6UZwjqwZXTSaGaqnVp4"

    struct TrackedTRC20Token: Equatable {
        let symbol: String
        let contractAddress: String
        let decimals: Int
    }

    static let defaultTrackedTRC20Tokens: [TrackedTRC20Token] = [
        TrackedTRC20Token(symbol: "USDT", contractAddress: usdtTronContract, decimals: 6),
        TrackedTRC20Token(symbol: "USDD", contractAddress: usddTronContract, decimals: 18),
        TrackedTRC20Token(symbol: "USD1", contractAddress: usd1TronContract, decimals: 18),
        TrackedTRC20Token(symbol: "BTT", contractAddress: bttTronContract, decimals: 18),
    ]

    private static let tronScanAddressInfoBases = ChainBackendRegistry.TronRuntimeEndpoints.tronScanAddressInfoBases
    private static let tronGridAccountsBases = ChainBackendRegistry.TronRuntimeEndpoints.tronGridAccountsBases
    private static let tronGridRPCBases = ChainBackendRegistry.TronRuntimeEndpoints.tronGridBroadcastBaseURLs

    static func endpointCatalog() -> [String] {
        AppEndpointDirectory.settingsEndpoints(for: ChainBackendRegistry.tronChainName)
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AppEndpointDirectory.diagnosticsChecks(for: ChainBackendRegistry.tronChainName)
    }

    private struct TronGridTRC20HistoryResponse: Decodable {
        let data: [TronGridTRC20HistoryItem]?
    }

    private struct TronGridTRC20HistoryItem: Decodable {
        let transaction_id: String?
        let from: String?
        let to: String?
        let value: String?
        let block_timestamp: Int64?
        let token_info: TronGridTokenInfo?
    }

    private struct TronGridTokenInfo: Decodable {
        let address: String?
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTokenAmount(_ raw: String?, decimals: Int) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let decimal = Decimal(string: trimmed) else {
            return nil
        }
        // Some Tron providers return already-normalized decimal balances
        // ("3.25" TRX) while others return smallest-unit integers ("3250000").
        if trimmed.contains(".") || trimmed.lowercased().contains("e") {
            let value = NSDecimalNumber(decimal: decimal).doubleValue
            guard value.isFinite, value >= 0 else { return nil }
            return value
        }
        let divisor = pow(10, Double(min(max(decimals, 0), 18)))
        let value = NSDecimalNumber(decimal: decimal).doubleValue / divisor
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func normalizedInt64(_ raw: Any?) -> Int64? {
        switch raw {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int64(trimmed) {
                return value
            }
            if let decimal = Decimal(string: trimmed) {
                let value = NSDecimalNumber(decimal: decimal).doubleValue
                guard value.isFinite, value >= 0 else { return nil }
                return Int64(value.rounded())
            }
            return nil
        default:
            return nil
        }
    }

    private static func tronScanTopLevelBalanceSun(from object: [String: Any]) -> Int64 {
        if let direct = normalizedInt64(object["balance"]) {
            return direct
        }
        if let dataObject = object["data"] as? [String: Any],
           let nested = normalizedInt64(dataObject["balance"]) {
            return nested
        }
        if let dataRows = object["data"] as? [[String: Any]],
           let first = dataRows.first,
           let nested = normalizedInt64(first["balance"]) {
            return nested
        }
        return 0
    }

    private static func normalizedString(_ raw: Any?) -> String? {
        switch raw {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func tronScanTokenRows(from object: [String: Any]) -> [[String: Any]] {
        if let rows = object["tokens"] as? [[String: Any]] {
            return rows
        }
        if let rows = object["withPriceTokens"] as? [[String: Any]] {
            return rows
        }
        if let rows = object["tokenBalances"] as? [[String: Any]] {
            return rows
        }
        if let data = object["data"] as? [String: Any] {
            if let rows = data["tokens"] as? [[String: Any]] {
                return rows
            }
            if let rows = data["withPriceTokens"] as? [[String: Any]] {
                return rows
            }
            if let rows = data["tokenBalances"] as? [[String: Any]] {
                return rows
            }
        }
        return []
    }

    private static func tronScanRowContractAddress(_ row: [String: Any]) -> String? {
        normalizedString(row["tokenId"])
            ?? normalizedString(row["token_id"])
            ?? normalizedString(row["contract_address"])
            ?? normalizedString(row["contractAddress"])
    }

    private static func tronScanRowSymbol(_ row: [String: Any]) -> String? {
        normalizedString(row["tokenAbbr"])
            ?? normalizedString(row["token_abbr"])
            ?? normalizedString(row["abbr"])
            ?? normalizedString(row["symbol"])
    }

    private static func tronScanRowName(_ row: [String: Any]) -> String? {
        normalizedString(row["tokenName"])
            ?? normalizedString(row["token_name"])
            ?? normalizedString(row["name"])
    }

    private static func tronScanRowDecimals(_ row: [String: Any]) -> Int {
        if let value = normalizedInt64(row["tokenDecimal"]) {
            return Int(value)
        }
        if let value = normalizedInt64(row["token_decimal"]) {
            return Int(value)
        }
        if let value = normalizedInt64(row["decimals"]) {
            return Int(value)
        }
        return 6
    }

    private static func tronScanRowBalanceString(_ row: [String: Any]) -> String? {
        normalizedString(row["balance"])
            ?? normalizedString(row["amount"])
            ?? normalizedString(row["quantity"])
            ?? normalizedString(row["balanceStr"])
            ?? normalizedString(row["value"])
    }

    private static func tronScanNativeBalanceFallback(from rows: [[String: Any]]) -> Double? {
        guard let nativeRow = rows.first(where: { row in
            if tronScanRowContractAddress(row) == "_" { return true }
            if tronScanRowSymbol(row)?.lowercased() == "trx" { return true }
            if tronScanRowName(row)?.lowercased() == "trx" { return true }
            return false
        }) else {
            return nil
        }
        return normalizedTokenAmount(
            tronScanRowBalanceString(nativeRow),
            decimals: tronScanRowDecimals(nativeRow)
        )
    }

    private static func tronScanTrackedTokenBalances(
        from rows: [[String: Any]],
        trackedTokens: [TrackedTRC20Token]
    ) -> [TronTokenBalanceSnapshot] {
        let tokenLookup = Dictionary(uniqueKeysWithValues: trackedTokens.map { ($0.contractAddress.lowercased(), $0) })
        var balancesByContract: [String: TronTokenBalanceSnapshot] = [:]

        for row in rows {
            guard let contract = tronScanRowContractAddress(row)?.lowercased(),
                  let tracked = tokenLookup[contract] else {
                continue
            }
            let balance = normalizedTokenAmount(
                tronScanRowBalanceString(row),
                decimals: tracked.decimals
            ) ?? 0
            let snapshot = TronTokenBalanceSnapshot(
                symbol: tracked.symbol,
                contractAddress: tracked.contractAddress,
                balance: balance
            )
            if let existing = balancesByContract[tracked.contractAddress], existing.balance > snapshot.balance {
                continue
            }
            balancesByContract[tracked.contractAddress] = snapshot
        }

        return trackedTokens.compactMap { tracked in
            balancesByContract[tracked.contractAddress]
        }
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidTronAddress(address)
    }

    static func fetchBalances(for address: String) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        try await fetchBalances(for: address, trackedTokens: defaultTrackedTRC20Tokens)
    }

    static func fetchBalances(
        for address: String,
        trackedTokens: [TrackedTRC20Token]
    ) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw TronBalanceServiceError.invalidAddress
        }

        do {
            return try await fetchBalancesFromTronScan(for: normalized, trackedTokens: trackedTokens)
        } catch {
            return try await fetchBalancesFromTronGrid(for: normalized, trackedTokens: trackedTokens)
        }
    }

    private static func fetchBalancesFromTronScan(
        for address: String,
        trackedTokens: [TrackedTRC20Token]
    ) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        var lastError: Error = TronBalanceServiceError.invalidResponse
        for base in tronScanAddressInfoBases {
            var components = URLComponents(string: base)
            components?.queryItems = [URLQueryItem(name: "address", value: address)]
            guard let url = components?.url else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    lastError = TronBalanceServiceError.httpError(http.statusCode)
                    continue
                }

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                let trxSun = tronScanTopLevelBalanceSun(from: object)
                let topLevelTRXBalance = Double(trxSun) / 1_000_000.0
                let tokenRows = tronScanTokenRows(from: object)
                let tokenFallbackTRXBalance = tronScanNativeBalanceFallback(from: tokenRows)
                let trxBalance = topLevelTRXBalance > 0
                    ? topLevelTRXBalance
                    : (tokenFallbackTRXBalance ?? topLevelTRXBalance)

                let tokenBalances = tronScanTrackedTokenBalances(from: tokenRows, trackedTokens: trackedTokens)

                return (trxBalance, tokenBalances)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private static func fetchBalancesFromTronGrid(
        for address: String,
        trackedTokens: [TrackedTRC20Token]
    ) async throws -> (trxBalance: Double, tokenBalances: [TronTokenBalanceSnapshot]) {
        var lastError: Error = TronBalanceServiceError.invalidResponse
        for base in tronGridAccountsBases {
            guard let url = URL(string: "\(base)/\(address)") else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["data"] as? [[String: Any]] else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                if rows.isEmpty {
                    let tokenBalances = trackedTokens.map { token in
                        TronTokenBalanceSnapshot(
                            symbol: token.symbol,
                            contractAddress: token.contractAddress,
                            balance: 0
                        )
                    }
                    return (0, tokenBalances)
                }

                guard let account = rows.first else {
                    lastError = TronBalanceServiceError.invalidResponse
                    continue
                }

                let trxSun = normalizedInt64(account["balance"]) ?? 0
                let trxBalance = Double(trxSun) / 1_000_000.0

                var balancesByContract: [String: Double] = [:]
                let tokenLookup = Dictionary(uniqueKeysWithValues: trackedTokens.map { ($0.contractAddress.lowercased(), $0) })
                if let trc20Rows = account["trc20"] as? [[String: String]] {
                    for row in trc20Rows {
                        for (contract, rawAmount) in row {
                            let normalizedContract = contract.lowercased()
                            guard let tracked = tokenLookup[normalizedContract] else { continue }
                            let balance = normalizedTokenAmount(rawAmount, decimals: tracked.decimals) ?? 0
                            balancesByContract[tracked.contractAddress] = balance
                        }
                    }
                }

                let tokenBalances: [TronTokenBalanceSnapshot] = trackedTokens.map { token in
                    TronTokenBalanceSnapshot(
                        symbol: token.symbol,
                        contractAddress: token.contractAddress,
                        balance: balancesByContract[token.contractAddress] ?? 0
                    )
                }

                return (trxBalance, tokenBalances)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 50) async -> (snapshots: [TronHistorySnapshot], diagnostics: TronHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                TronHistoryDiagnostics(
                    address: normalized,
                    tronScanTxCount: 0,
                    tronScanTRC20Count: 0,
                    sourceUsed: "none",
                    error: TronBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let txResult = await fetchNativeTransfers(address: normalized, limit: limit)
        let trc20Result = await fetchUSDTTRC20Transfers(address: normalized, limit: limit)
        let merged = dedupeAndSort(native: txResult, usdt: trc20Result)
        let errorMessage = [txResult.error, trc20Result.error].compactMap { $0 }.joined(separator: " | ")

        return (
            merged,
            TronHistoryDiagnostics(
                address: normalized,
                tronScanTxCount: txResult.items.count,
                tronScanTRC20Count: trc20Result.items.count,
                sourceUsed: "trongrid",
                error: errorMessage.isEmpty ? nil : errorMessage
            )
        )
    }

    private static func fetchNativeTransfers(address: String, limit: Int) async -> (items: [TronHistorySnapshot], error: String?) {
        for base in tronGridAccountsBases {
            guard let url = URL(string: "\(base)/\(address)/transactions?limit=\(max(1, min(limit, 200)))&only_confirmed=false&order_by=block_timestamp,desc&visible=true") else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    continue
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["data"] as? [[String: Any]] else {
                    continue
                }
                let ownerAddress = normalizedAddress(address)
                let snapshots = rows.compactMap { row in
                    nativeHistorySnapshot(from: row, ownerAddress: ownerAddress)
                }
                return (snapshots, nil)
            } catch {
                continue
            }
        }
        return ([], TronBalanceServiceError.invalidResponse.localizedDescription)
    }

    private static func nativeHistorySnapshot(from row: [String: Any], ownerAddress: String) -> TronHistorySnapshot? {
        let hash = (row["txID"] as? String) ?? (row["txid"] as? String) ?? (row["transaction_id"] as? String)
        guard let hash, !hash.isEmpty else { return nil }

        let rawData = row["raw_data"] as? [String: Any]
        let contracts = rawData?["contract"] as? [[String: Any]]
        let contract = contracts?.first
        let contractType = (contract?["type"] as? String) ?? (row["type"] as? String)
        let nativeContractTypes: Set<String> = ["TransferContract", "TransferAssetContract"]
        guard let contractType, nativeContractTypes.contains(contractType) else { return nil }

        let parameter = contract?["parameter"] as? [String: Any]
        let value = parameter?["value"] as? [String: Any]

        let from = preferredTronAddress(primary: row["from"], fallback: value?["owner_address"])
        let to = preferredTronAddress(primary: row["to"], fallback: value?["to_address"])
        guard let from, let to = to else { return nil }

        let amountSun = normalizedInt64(value?["amount"])
            ?? normalizedInt64(value?["quant"])
            ?? normalizedInt64(value?["call_value"])
            ?? normalizedInt64(row["amount"])
            ?? normalizedInt64(row["value"])
            ?? normalizedInt64(row["quant"])
            ?? 0
        let amount = Double(amountSun) / 1_000_000.0
        guard amount > 0 else { return nil }

        let timestampMS = normalizedInt64(row["block_timestamp"])
            ?? normalizedInt64(row["timestamp"])
            ?? 0
        let createdAt = Date(timeIntervalSince1970: Double(timestampMS) / 1_000.0)

        let ownerKeys = tronAddressComparisonKeys(ownerAddress)
        let fromKeys = tronAddressComparisonKeys(from)
        let toKeys = tronAddressComparisonKeys(to)
        let kind: TransactionKind
        let counterparty: String
        if !toKeys.isDisjoint(with: ownerKeys) {
            kind = .receive
            counterparty = from
        } else if !fromKeys.isDisjoint(with: ownerKeys) {
            kind = .send
            counterparty = to
        } else {
            kind = .receive
            counterparty = from
        }

        let contractRet = (row["ret"] as? [[String: Any]])?.first?["contractRet"] as? String
        let status: TransactionStatus = (contractRet == nil || contractRet == "SUCCESS") ? .confirmed : .failed

        return TronHistorySnapshot(
            transactionHash: hash,
            kind: kind,
            amount: amount,
            symbol: "TRX",
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: status
        )
    }

    private static func fetchUSDTTRC20Transfers(address: String, limit: Int) async -> (items: [TronHistorySnapshot], error: String?) {
        for base in tronGridAccountsBases {
            guard let url = URL(string: "\(base)/\(address)/transactions/trc20?limit=\(max(1, min(limit, 200)))&contract_address=\(usdtTronContract)&only_confirmed=false&order_by=block_timestamp,desc") else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    continue
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = object["data"] as? [[String: Any]] else {
                    continue
                }
                let ownerAddress = normalizedAddress(address)
                let snapshots = rows.compactMap { row in
                    trc20HistorySnapshot(from: row, ownerAddress: ownerAddress)
                }
                return (snapshots, nil)
            } catch {
                continue
            }
        }
        return ([], TronBalanceServiceError.invalidResponse.localizedDescription)
    }

    private static func trc20HistorySnapshot(from row: [String: Any], ownerAddress: String) -> TronHistorySnapshot? {
        let hash = (row["transaction_id"] as? String) ?? (row["txID"] as? String)
        guard let hash, !hash.isEmpty else { return nil }

        let tokenInfo = row["token_info"] as? [String: Any]
        let contract = (tokenInfo?["address"] as? String) ?? (row["contract_address"] as? String)
        guard contract?.lowercased() == usdtTronContract.lowercased() else { return nil }

        let from = (row["from"] as? String) ?? ""
        let to = (row["to"] as? String) ?? ""
        guard !from.isEmpty, !to.isEmpty else { return nil }

        let decimals = normalizedInt64(tokenInfo?["decimals"]).map(Int.init) ?? 6
        let rawValue = normalizedString(row["value"]) ?? normalizedString(row["amount"])
        let amount = normalizedTokenAmount(rawValue, decimals: decimals) ?? 0
        guard amount > 0 else { return nil }

        let timestampMS = normalizedInt64(row["block_timestamp"])
            ?? normalizedInt64(row["timestamp"])
            ?? 0
        let createdAt = Date(timeIntervalSince1970: Double(timestampMS) / 1_000.0)

        let ownerKeys = tronAddressComparisonKeys(ownerAddress)
        let fromKeys = tronAddressComparisonKeys(from)
        let toKeys = tronAddressComparisonKeys(to)
        let kind: TransactionKind
        let counterparty: String
        if !toKeys.isDisjoint(with: ownerKeys) {
            kind = .receive
            counterparty = from
        } else if !fromKeys.isDisjoint(with: ownerKeys) {
            kind = .send
            counterparty = to
        } else {
            kind = .receive
            counterparty = from
        }

        return TronHistorySnapshot(
            transactionHash: hash,
            kind: kind,
            amount: amount,
            symbol: "USDT",
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: .confirmed
        )
    }

    private static func dedupeAndSort(native: (items: [TronHistorySnapshot], error: String?), usdt: (items: [TronHistorySnapshot], error: String?)) -> [TronHistorySnapshot] {
        var ordered: [TronHistorySnapshot] = []
        var seen: Set<String> = []

        for item in native.items + usdt.items {
            if seen.insert(item.transactionHash).inserted {
                ordered.append(item)
            }
        }

        return ordered.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.transactionHash > rhs.transactionHash
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await ProviderHTTP.sessionData(for: request)
    }

    private static func preferredTronAddress(primary: Any?, fallback: Any?) -> String? {
        if let primaryAddress = normalizedString(primary), AddressValidation.isValidTronAddress(primaryAddress) {
            return primaryAddress
        }
        if let fallbackAddress = normalizedString(fallback), AddressValidation.isValidTronAddress(fallbackAddress) {
            return fallbackAddress
        }
        return normalizedString(primary) ?? normalizedString(fallback)
    }

    private static func tronAddressComparisonKeys(_ address: String) -> Set<String> {
        let trimmed = normalizedAddress(address)
        guard !trimmed.isEmpty else { return [] }

        var keys: Set<String> = [trimmed.lowercased()]
        if let hexAddress = normalizedTronHexAddress(trimmed) {
            keys.insert(hexAddress)
        }
        if AddressValidation.isValidTronAddress(trimmed),
           let payload = UTXOAddressCodec.base58CheckDecode(trimmed),
           payload.count == 21 {
            keys.insert(payload.map { String(format: "%02x", $0) }.joined())
        }
        return keys
    }

    private static func normalizedTronHexAddress(_ address: String) -> String? {
        let trimmed = normalizedAddress(address)
        let stripped = trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X")
            ? String(trimmed.dropFirst(2))
            : trimmed
        guard stripped.count == 42,
              stripped.allSatisfy({ $0.isHexDigit }),
              stripped.lowercased().hasPrefix("41") else {
            return nil
        }
        return stripped.lowercased()
    }
}
