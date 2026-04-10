import Foundation

enum NearBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcError(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("NEAR")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("NEAR")
        case .rpcError(let message):
            return CommonLocalization.rpcError("NEAR", message: message)
        case .httpError(let code):
            let format = AppLocalization.string("The NEAR provider returned HTTP %d.")
            return String(format: format, locale: AppLocalization.locale, code)
        }
    }
}

struct NearHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct NearHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct NearTokenBalanceSnapshot: Equatable {
    let contractAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}

enum NearBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }

    static func endpointCatalog() -> [String] {
        NearProvider.endpointCatalog()
    }

    static func rpcEndpointCatalog() -> [String] {
        NearProvider.rpcEndpoints
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        NearProvider.diagnosticsChecks()
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidNearAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw NearBalanceServiceError.invalidAddress
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "spectra-near-balance",
            "method": "query",
            "params": [
                "request_type": "view_account",
                "finality": "final",
                "account_id": normalized
            ]
        ]

        var lastError: Error?
        for endpoint in NearProvider.rpcEndpoints {
            do {
                let result: NearProvider.ViewAccountResult = try await postRPC(payload: payload, endpoint: endpoint)
                guard let yoctoText = result.amount,
                      let yocto = Decimal(string: yoctoText) else {
                    throw NearBalanceServiceError.invalidResponse
                }
                return decimalToDouble(yocto / Decimal(string: "1000000000000000000000000")!)
            } catch {
                if isMissingAccountError(error) {
                    return 0
                }
                lastError = error
            }
        }

        throw lastError ?? NearBalanceServiceError.invalidResponse
    }

    static func fetchTrackedTokenBalances(
        for address: String,
        trackedTokenMetadataByContract: [String: KnownTokenMetadata]
    ) async throws -> [NearTokenBalanceSnapshot] {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw NearBalanceServiceError.invalidAddress
        }

        let trackedByContract = Dictionary(
            uniqueKeysWithValues: trackedTokenMetadataByContract.map { (normalizedAddress($0.key), $0.value) }
        )
        guard !trackedByContract.isEmpty else { return [] }

        var snapshots: [NearTokenBalanceSnapshot] = []
        for contractAddress in trackedByContract.keys.sorted() {
            guard let metadata = trackedByContract[contractAddress] else { continue }
            do {
                let rawBalanceText = try await callFunctionString(
                    contractAddress: contractAddress,
                    methodName: "ft_balance_of",
                    arguments: ["account_id": normalized]
                )
                guard let rawBalance = Decimal(string: rawBalanceText),
                      rawBalance > 0 else {
                    continue
                }

                let divisor = decimalPowerOfTen(min(max(metadata.decimals, 0), 30))
                let balance = decimalToDouble(rawBalance / divisor)
                guard balance.isFinite, balance > 0 else { continue }

                snapshots.append(
                    NearTokenBalanceSnapshot(
                        contractAddress: contractAddress,
                        symbol: metadata.symbol,
                        name: metadata.name,
                        tokenStandard: metadata.tokenStandard,
                        decimals: metadata.decimals,
                        balance: balance,
                        marketDataID: metadata.marketDataID,
                        coinGeckoID: metadata.coinGeckoID
                    )
                )
            } catch {
                continue
            }
        }

        return snapshots
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 80) async -> (snapshots: [NearHistorySnapshot], diagnostics: NearHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                NearHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: NearBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let boundedLimit = max(1, min(limit, 100))
        var lastError: String?
        for endpoint in NearProvider.historyEndpoints {
            do {
                let snapshots = try await fetchHistory(address: normalized, endpoint: endpoint, limit: boundedLimit)
                return (
                    snapshots,
                    NearHistoryDiagnostics(
                        address: normalized,
                        sourceUsed: endpoint,
                        transactionCount: snapshots.count,
                        error: nil
                    )
                )
            } catch {
                lastError = error.localizedDescription
            }
        }

        return (
            [],
            NearHistoryDiagnostics(
                address: normalized,
                sourceUsed: NearProvider.historyEndpoints.first ?? "none",
                transactionCount: 0,
                error: lastError ?? NearBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func callFunctionString(
        contractAddress: String,
        methodName: String,
        arguments: [String: String]
    ) async throws -> String {
        let argumentsData = try JSONSerialization.data(withJSONObject: arguments, options: [])
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "spectra-near-call-function",
            "method": "query",
            "params": [
                "request_type": "call_function",
                "finality": "final",
                "account_id": contractAddress,
                "method_name": methodName,
                "args_base64": argumentsData.base64EncodedString()
            ]
        ]

        var lastError: Error?
        for endpoint in NearProvider.rpcEndpoints {
            do {
                let result: NearProvider.CallFunctionResult = try await postRPC(payload: payload, endpoint: endpoint)
                guard let bytes = result.result else {
                    throw NearBalanceServiceError.invalidResponse
                }
                let data = Data(bytes)
                if let decoded = try? JSONDecoder().decode(String.self, from: data) {
                    return decoded
                }
                if let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\""))) {
                    return text
                }
                throw NearBalanceServiceError.invalidResponse
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NearBalanceServiceError.invalidResponse
    }

    private static func postRPC<ResultType: Decodable>(payload: [String: Any], endpoint: String) async throws -> ResultType {
        guard let url = URL(string: endpoint) else {
            throw NearBalanceServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
        guard let http = response as? HTTPURLResponse else {
            throw NearBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw NearBalanceServiceError.httpError(http.statusCode)
        }

        let envelope = try JSONDecoder().decode(NearProvider.RPCEnvelope<ResultType>.self, from: data)
        if let error = envelope.error {
            let message = error.message ?? error.cause?.info ?? error.name ?? "Unknown NEAR RPC error"
            throw NearBalanceServiceError.rpcError(message)
        }
        guard let result = envelope.result else {
            throw NearBalanceServiceError.invalidResponse
        }
        return result
    }

    private static func isMissingAccountError(_ error: Error) -> Bool {
        guard case NearBalanceServiceError.rpcError(let message) = error else {
            return false
        }
        let normalized = message.lowercased()
        return normalized.contains("unknown_account")
            || normalized.contains("unknown account")
            || normalized.contains("does not exist")
    }

    private static func fetchHistory(address: String, endpoint: String, limit: Int) async throws -> [NearHistorySnapshot] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(endpoint)/account/\(encodedAddress)/txns?page=1&per_page=\(limit)&order=desc") else {
            throw NearBalanceServiceError.invalidResponse
        }

        let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
        guard let http = response as? HTTPURLResponse else {
            throw NearBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw NearBalanceServiceError.httpError(http.statusCode)
        }

        return try parseHistoryResponse(data, ownerAddress: address)
    }

    static func parseHistoryResponse(_ data: Data, ownerAddress: String) throws -> [NearHistorySnapshot] {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let rows = historyRows(from: jsonObject)
        return rows.compactMap { snapshot(from: $0, ownerAddress: ownerAddress) }
    }

    private static func historyRows(from jsonObject: Any) -> [[String: Any]] {
        if let rows = jsonObject as? [[String: Any]] {
            return rows
        }
        guard let dictionary = jsonObject as? [String: Any] else {
            return []
        }
        if let rows = dictionary["txns"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["transactions"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["data"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["result"] as? [[String: Any]] {
            return rows
        }
        return []
    }

    private static func snapshot(from row: [String: Any], ownerAddress: String) -> NearHistorySnapshot? {
        guard let hash = stringValue(in: row, keys: ["transaction_hash", "hash", "receipt_id"]),
              !hash.isEmpty else {
            return nil
        }

        let owner = normalizedAddress(ownerAddress)
        let signer = normalizedAddress(
            stringValue(in: row, keys: ["signer_account_id", "predecessor_account_id", "signer_id", "signer"]) ?? ""
        )
        let receiver = normalizedAddress(
            stringValue(in: row, keys: ["receiver_account_id", "receiver_id", "receiver"]) ?? ""
        )

        let kind: TransactionKind
        let counterparty: String
        if signer == owner {
            kind = .send
            counterparty = receiver
        } else if receiver == owner {
            kind = .receive
            counterparty = signer
        } else if !signer.isEmpty {
            kind = .receive
            counterparty = signer
        } else {
            kind = .send
            counterparty = receiver
        }

        let depositYocto = depositText(in: row).flatMap { Decimal(string: $0) } ?? 0
        let amount = decimalToDouble(depositYocto / Decimal(string: "1000000000000000000000000")!)
        let createdAt = timestampDate(in: row) ?? Date()

        return NearHistorySnapshot(
            transactionHash: hash,
            kind: kind,
            amount: amount,
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: .confirmed
        )
    }

    private static func depositText(in row: [String: Any]) -> String? {
        if let direct = stringValue(in: row, keys: ["deposit", "amount"]), !direct.isEmpty {
            return direct
        }

        if let actionsAggregate = row["actions_agg"] as? [String: Any],
           let aggregateDeposit = stringValue(in: actionsAggregate, keys: ["deposit", "total_deposit", "amount"]),
           !aggregateDeposit.isEmpty {
            return aggregateDeposit
        }

        if let actions = row["actions"] as? [[String: Any]] {
            for action in actions {
                if let deposit = stringValue(in: action, keys: ["deposit", "amount"]), !deposit.isEmpty {
                    return deposit
                }
                if let args = action["args"] as? [String: Any],
                   let nestedDeposit = stringValue(in: args, keys: ["deposit", "amount"]),
                   !nestedDeposit.isEmpty {
                    return nestedDeposit
                }
            }
        }

        return nil
    }

    private static func timestampDate(in row: [String: Any]) -> Date? {
        if let timestamp = numericTimestamp(in: row, keys: ["block_timestamp", "timestamp", "included_in_block_timestamp"]) {
            return normalizedDate(fromTimestamp: timestamp)
        }

        for nestedKey in ["block", "receipt_block", "included_in_block", "receipt"] {
            if let nested = row[nestedKey] as? [String: Any],
               let timestamp = numericTimestamp(in: nested, keys: ["block_timestamp", "timestamp"]) {
                return normalizedDate(fromTimestamp: timestamp)
            }
        }

        return nil
    }

    private static func normalizedDate(fromTimestamp timestamp: Double) -> Date? {
        guard timestamp > 0 else { return nil }
        if timestamp >= 1_000_000_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000_000_000.0)
        }
        if timestamp >= 1_000_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000.0)
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func numericTimestamp(in row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = row[key] as? NSNumber {
                return number.doubleValue
            }
            if let string = row[key] as? String, let parsed = Double(string) {
                return parsed
            }
        }
        return nil
    }

    private static func stringValue(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = row[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            if let number = row[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(Decimal(1)) { partialResult, _ in
            partialResult * 10
        }
    }
}
