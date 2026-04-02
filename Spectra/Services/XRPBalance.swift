import Foundation

enum XRPBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("XRP")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("XRP")
        case .httpError(let code):
            let format = NSLocalizedString("The XRP provider returned HTTP %d.", comment: "")
            return String(format: format, locale: .current, code)
        case .rpcError(let message):
            return CommonLocalization.rpcError("XRP", message: message)
        }
    }
}

struct XRPHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct XRPHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum XRPBalanceService {
    private static let xrpScanAccountBases = ChainBackendRegistry.XRPRuntimeEndpoints.accountHistoryBases
    private static let rippleEpochOffset: TimeInterval = 946_684_800
    private enum Provider: String, CaseIterable {
        case xrpscan
        case xrplCluster
        case rippleS1
        case rippleS2

        var rpcEndpoint: URL {
            switch self {
            case .xrpscan, .rippleS1:
                return ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs[0]
            case .xrplCluster:
                return ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs[2]
            case .rippleS2:
                return ChainBackendRegistry.XRPRuntimeEndpoints.rpcURLs[1]
            }
        }
    }

    static func endpointCatalog() -> [String] {
        var endpoints = xrpScanAccountBases
        for provider in Provider.allCases {
            let endpoint = provider.rpcEndpoint.absoluteString
            if !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
        }
        return endpoints
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        endpointCatalog().map { base in
            (endpoint: base, probeURL: base)
        }
    }

    private struct XRPAccountResponse: Decodable {
        let xrpBalance: String?

        enum CodingKeys: String, CodingKey {
            case xrpBalance = "xrpBalance"
        }
    }

    private struct XRPTransactionRow: Decodable {
        let hash: String?
        let transactionType: String?
        let destination: String?
        let account: String?
        let deliveredAmount: XRPDeliveredAmount?
        let date: String?
        let validated: Bool?

        enum CodingKeys: String, CodingKey {
            case hash
            case transactionType = "TransactionType"
            case destination = "Destination"
            case account = "Account"
            case deliveredAmount = "delivered_amount"
            case date
            case validated
        }
    }

    private struct XRPTransactionEnvelope: Decodable {
        let transactions: [XRPTransactionRow]?
        let data: [XRPTransactionRow]?
        let rows: [XRPTransactionRow]?
    }

    private struct XRPLRPCErrorResponse: Decodable {
        let error: String?
        let error_message: String?
    }

    private enum XRPDeliveredAmount: Decodable {
        case string(String)
        case object([String: String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            if let value = try? container.decode([String: String].self) {
                self = .object(value)
                return
            }
            throw DecodingError.typeMismatch(
                XRPDeliveredAmount.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported delivered_amount format")
            )
        }
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidXRPAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            throw XRPBalanceServiceError.invalidAddress
        }
        return try await runWithProviderFallback(candidates: Provider.allCases) { provider in
            do {
                switch provider {
                case .xrpscan:
                    return try await fetchBalanceViaXRPSCAN(address: normalized)
                case .xrplCluster, .rippleS1, .rippleS2:
                    return try await fetchBalanceViaXRPLRPC(address: normalized, endpoint: provider.rpcEndpoint)
                }
            } catch {
                if isMissingAccountError(error) {
                    return 0
                }
                throw error
            }
        }
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 50) async -> (snapshots: [XRPHistorySnapshot], diagnostics: XRPHistoryDiagnostics) {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            return (
                [],
                XRPHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: XRPBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let boundedLimit = max(1, min(limit, 100))
        var lastError: String?
        for provider in Provider.allCases {
            do {
                let snapshots: [XRPHistorySnapshot]
                switch provider {
                case .xrpscan:
                    snapshots = try await fetchHistoryViaXRPSCAN(address: normalized, limit: boundedLimit)
                case .xrplCluster, .rippleS1, .rippleS2:
                    snapshots = try await fetchHistoryViaXRPLRPC(address: normalized, limit: boundedLimit, endpoint: provider.rpcEndpoint)
                }

                return (
                    snapshots,
                    XRPHistoryDiagnostics(
                        address: normalized,
                        sourceUsed: provider.rawValue,
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
            XRPHistoryDiagnostics(
                address: normalized,
                sourceUsed: "none",
                transactionCount: 0,
                error: lastError ?? XRPBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
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

    private static func fetchBalanceViaXRPSCAN(address: String) async throws -> Double {
        var lastError: Error?
        for base in xrpScanAccountBases {
            guard let url = URL(string: "\(base)/\(address)") else { continue }
            do {
                let (data, response) = try await fetchData(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw XRPBalanceServiceError.invalidResponse
                }
                if http.statusCode == 404 {
                    return 0
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw XRPBalanceServiceError.httpError(http.statusCode)
                }

                let decoded = try JSONDecoder().decode(XRPAccountResponse.self, from: data)
                guard let balanceString = decoded.xrpBalance,
                      let balance = Double(balanceString),
                      balance.isFinite,
                      balance >= 0 else {
                    throw XRPBalanceServiceError.invalidResponse
                }
                return balance
            } catch {
                lastError = error
            }
        }
        throw lastError ?? XRPBalanceServiceError.invalidResponse
    }

    private static func fetchBalanceViaXRPLRPC(address: String, endpoint: URL) async throws -> Double {
        let payload: [String: Any] = [
            "method": "account_info",
            "params": [[
                "account": address,
                "ledger_index": "validated",
                "strict": true
            ]]
        ]
        let result = try await postXRPLRPC(payload: payload, endpoint: endpoint)
        guard let accountData = result["account_data"] as? [String: Any],
              let dropsText = accountData["Balance"] as? String,
              let drops = Double(dropsText),
              drops.isFinite,
              drops >= 0 else {
            throw XRPBalanceServiceError.invalidResponse
        }
        return drops / 1_000_000.0
    }

    private static func fetchHistoryViaXRPSCAN(address: String, limit: Int) async throws -> [XRPHistorySnapshot] {
        var lastError: Error?
        for base in xrpScanAccountBases {
            guard let url = URL(string: "\(base)/\(address)/transactions") else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw XRPBalanceServiceError.httpError(code)
                }

                let rows = try parseXRPSCANHistoryRows(data)
                let trimmed = Array(rows.prefix(limit))
                return trimmed.compactMap { row in
                    guard let hash = row.hash, !hash.isEmpty else { return nil }

                    let destination = row.destination?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let source = row.account?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let kind: TransactionKind = (destination?.caseInsensitiveCompare(address) == .orderedSame) ? .receive : .send
                    let counterparty = kind == .receive ? (source ?? "") : (destination ?? "")

                    let amount: Double = {
                        switch row.deliveredAmount {
                        case .string(let value):
                            if let drops = Double(value), drops.isFinite {
                                return max(0, drops / 1_000_000.0)
                            }
                            return 0
                        case .object(let payload):
                            if let value = payload["value"], let decimal = Double(value), decimal.isFinite {
                                return max(0, decimal)
                            }
                            return 0
                        case .none:
                            return 0
                        }
                    }()

                    let createdAt: Date = {
                        if let dateString = row.date,
                           let timestamp = TimeInterval(dateString) {
                            return Date(timeIntervalSince1970: timestamp)
                        }
                        return Date()
                    }()

                    let status: TransactionStatus = (row.validated ?? true) ? .confirmed : .pending
                    return XRPHistorySnapshot(
                        transactionHash: hash,
                        kind: kind,
                        amount: amount,
                        counterpartyAddress: counterparty,
                        createdAt: createdAt,
                        status: status
                    )
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? XRPBalanceServiceError.invalidResponse
    }

    private static func parseXRPSCANHistoryRows(_ data: Data) throws -> [XRPTransactionRow] {
        if let rows = try? JSONDecoder().decode([XRPTransactionRow].self, from: data) {
            return rows
        }
        let envelope = try JSONDecoder().decode(XRPTransactionEnvelope.self, from: data)
        return envelope.transactions ?? envelope.data ?? envelope.rows ?? []
    }

    private static func fetchHistoryViaXRPLRPC(address: String, limit: Int, endpoint: URL) async throws -> [XRPHistorySnapshot] {
        let payload: [String: Any] = [
            "method": "account_tx",
            "params": [[
                "account": address,
                "ledger_index_min": -1,
                "ledger_index_max": -1,
                "limit": limit,
                "binary": false,
                "forward": false
            ]]
        ]
        let result = try await postXRPLRPC(payload: payload, endpoint: endpoint)
        guard let rows = result["transactions"] as? [[String: Any]] else {
            throw XRPBalanceServiceError.invalidResponse
        }

        return rows.compactMap { row in
            guard let tx = row["tx"] as? [String: Any],
                  let hash = tx["hash"] as? String,
                  !hash.isEmpty else {
                return nil
            }
            let type = (tx["TransactionType"] as? String ?? "").lowercased()
            guard type == "payment" else { return nil }

            let from = (tx["Account"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let to = (tx["Destination"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: TransactionKind = to.caseInsensitiveCompare(address) == .orderedSame ? .receive : .send
            let counterparty = kind == .receive ? from : to

            let amount = parseXRPLAmount(tx["Amount"])
            let dateValue = TimeInterval(tx["date"] as? Int ?? 0)
            let createdAt = dateValue > 0 ? Date(timeIntervalSince1970: rippleEpochOffset + dateValue) : Date()

            let status: TransactionStatus = {
                guard let meta = row["meta"] as? [String: Any] else { return .pending }
                let resultCode = (meta["TransactionResult"] as? String ?? "").uppercased()
                if resultCode.isEmpty { return .pending }
                return resultCode == "TESSUCCESS" ? .confirmed : .failed
            }()

            return XRPHistorySnapshot(
                transactionHash: hash,
                kind: kind,
                amount: amount,
                counterpartyAddress: counterparty,
                createdAt: createdAt,
                status: status
            )
        }
    }

    private static func parseXRPLAmount(_ value: Any?) -> Double {
        if let text = value as? String, let drops = Double(text), drops.isFinite {
            return max(0, drops / 1_000_000.0)
        }
        if let object = value as? [String: Any],
           let amountText = object["value"] as? String,
           let decimal = Double(amountText),
           decimal.isFinite {
            return max(0, decimal)
        }
        return 0
    }

    private static func postXRPLRPC(payload: [String: Any], endpoint: URL) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await fetchData(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw XRPBalanceServiceError.httpError(code)
        }

        if let errorResponse = try? JSONDecoder().decode(XRPLRPCErrorResponse.self, from: data),
           errorResponse.error != nil || errorResponse.error_message != nil {
            throw XRPBalanceServiceError.rpcError(
                errorResponse.error_message ?? errorResponse.error ?? "Unknown XRPL RPC error"
            )
        }

        guard let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw XRPBalanceServiceError.invalidResponse
        }
        return result
    }

    private static func isMissingAccountError(_ error: Error) -> Bool {
        switch error {
        case XRPBalanceServiceError.httpError(let code):
            return code == 404
        case XRPBalanceServiceError.rpcError(let message):
            let normalized = message.lowercased()
            return normalized.contains("actnotfound")
                || normalized.contains("account not found")
                || normalized.contains("does not exist")
        default:
            return false
        }
    }
}
