import Foundation

enum StellarBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Stellar")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Stellar")
        case .httpError(let code):
            let format = AppLocalization.string("The Stellar provider returned HTTP %d.")
            return String(format: format, locale: AppLocalization.locale, code)
        }
    }
}

struct StellarHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct StellarHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum StellarBalanceService {
    private static let stroopDivisor = Decimal(string: "10000000")!
    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let endpointReliabilityNamespace = "stellar.horizon"

    static func endpointCatalog() -> [String] {
        StellarProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        StellarProvider.diagnosticsChecks()
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidStellarAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw StellarBalanceServiceError.invalidAddress
        }

        var lastError: Error?
        for endpoint in StellarProvider.horizonEndpoints {
            do {
                let account = try await fetchAccount(address: normalized, endpoint: endpoint)
                guard let nativeBalance = account.balances.first(where: { $0.assetType == "native" }),
                      let balance = Decimal(string: nativeBalance.balance ?? "") else {
                    throw StellarBalanceServiceError.invalidResponse
                }
                return decimalToDouble(balance)
            } catch {
                if isMissingAccountError(error) {
                    return 0
                }
                lastError = error
            }
        }
        throw lastError ?? StellarBalanceServiceError.invalidResponse
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 80) async -> (snapshots: [StellarHistorySnapshot], diagnostics: StellarHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                StellarHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: StellarBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let boundedLimit = max(1, min(limit, 80))
        var lastError: String?
        for endpoint in StellarProvider.horizonEndpoints {
            do {
                let snapshots = try await fetchPayments(address: normalized, endpoint: endpoint, limit: boundedLimit)
                return (
                    snapshots,
                    StellarHistoryDiagnostics(
                        address: normalized,
                        sourceUsed: endpoint,
                        transactionCount: snapshots.count,
                        error: nil
                    )
                )
            } catch {
                if isMissingAccountError(error) {
                    return (
                        [],
                        StellarHistoryDiagnostics(
                            address: normalized,
                            sourceUsed: endpoint,
                            transactionCount: 0,
                            error: nil
                        )
                    )
                }
                lastError = error.localizedDescription
            }
        }

        return (
            [],
            StellarHistoryDiagnostics(
                address: normalized,
                sourceUsed: StellarProvider.horizonEndpoints.first ?? "none",
                transactionCount: 0,
                error: lastError ?? StellarBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    static func fetchSequence(for address: String) async throws -> Int64 {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw StellarBalanceServiceError.invalidAddress
        }

        var lastError: Error?
        for endpoint in StellarProvider.horizonEndpoints {
            do {
                let account = try await fetchAccount(address: normalized, endpoint: endpoint)
                guard let sequenceText = account.sequence,
                      let sequence = Int64(sequenceText) else {
                    throw StellarBalanceServiceError.invalidResponse
                }
                return sequence
            } catch {
                lastError = error
            }
        }

        throw lastError ?? StellarBalanceServiceError.invalidResponse
    }

    static func fetchBaseFeeStroops() async throws -> Int64 {
        var lastError: Error?
        for endpoint in StellarProvider.horizonEndpoints {
            guard let url = URL(string: "\(endpoint)/fee_stats") else { continue }
            do {
                let (data, response) = try await fetchData(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw StellarBalanceServiceError.invalidResponse
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw StellarBalanceServiceError.httpError(http.statusCode)
                }
                let stats = try JSONDecoder().decode(StellarProvider.FeeStatsResponse.self, from: data)
                if let feeText = stats.lastLedgerBaseFee ?? stats.feeCharged?.p50,
                   let fee = Int64(feeText),
                   fee > 0 {
                    return fee
                }
                throw StellarBalanceServiceError.invalidResponse
            } catch {
                lastError = error
            }
        }
        throw lastError ?? StellarBalanceServiceError.invalidResponse
    }

    static func submitTransaction(xdrEnvelope: String, providerIDs: Set<String>? = nil) async throws -> String {
        let trimmedEnvelope = xdrEnvelope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEnvelope.isEmpty else {
            throw StellarBalanceServiceError.invalidResponse
        }

        var lastError: Error?
        for endpoint in orderedHorizonEndpoints(providerIDs: providerIDs) {
            guard let url = URL(string: "\(endpoint)/transactions") else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 20
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let encodedEnvelope = trimmedEnvelope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedEnvelope
                request.httpBody = "tx=\(encodedEnvelope)".data(using: .utf8)
                let (data, response) = try await fetchData(for: request, profile: .chainWrite)
                guard let http = response as? HTTPURLResponse else {
                    throw StellarBalanceServiceError.invalidResponse
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    if let envelope = try? JSONDecoder().decode(StellarProvider.SubmitTransactionResponse.self, from: data),
                       let hash = envelope.hash?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !hash.isEmpty,
                       classifySendBroadcastFailure(String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)") == .alreadyBroadcast {
                        ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint, success: true)
                        return hash
                    }
                    throw StellarBalanceServiceError.httpError(http.statusCode)
                }
                let envelope = try JSONDecoder().decode(StellarProvider.SubmitTransactionResponse.self, from: data)
                guard let hash = envelope.hash?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !hash.isEmpty else {
                    throw StellarBalanceServiceError.invalidResponse
                }
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint, success: true)
                return hash
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: endpointReliabilityNamespace, endpoint: endpoint, success: false)
            }
        }
        throw lastError ?? StellarBalanceServiceError.invalidResponse
    }

    private static func orderedHorizonEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        ChainEndpointReliability.orderedEndpoints(
            namespace: endpointReliabilityNamespace,
            candidates: filteredHorizonEndpoints(providerIDs: providerIDs)
        )
    }

    private static func filteredHorizonEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        guard let providerIDs, !providerIDs.isEmpty else { return StellarProvider.horizonEndpoints }
        return StellarProvider.horizonEndpoints.filter { endpoint in
            switch endpoint {
            case "https://horizon.stellar.org":
                return providerIDs.contains("stellar-horizon")
            case "https://horizon.stellar.lobstr.co":
                return providerIDs.contains("lobstr-horizon")
            default:
                return false
            }
        }
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await ProviderHTTP.data(for: request, profile: .chainRead)
    }

    private static func fetchData(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await ProviderHTTP.data(for: request, profile: profile)
    }

    private static func fetchAccount(address: String, endpoint: String) async throws -> StellarProvider.AccountResponse {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(endpoint)/accounts/\(encoded)") else {
            throw StellarBalanceServiceError.invalidResponse
        }
        let (data, response) = try await fetchData(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw StellarBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw StellarBalanceServiceError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(StellarProvider.AccountResponse.self, from: data)
    }

    private static func fetchPayments(address: String, endpoint: String, limit: Int) async throws -> [StellarHistorySnapshot] {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(endpoint)/accounts/\(encoded)/payments?order=desc&limit=\(limit)&include_failed=false") else {
            throw StellarBalanceServiceError.invalidResponse
        }
        let (data, response) = try await fetchData(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw StellarBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw StellarBalanceServiceError.httpError(http.statusCode)
        }
        let records = try parsePaymentRecords(data)
        return records.compactMap { record in
            switch record.type {
            case "payment":
                guard record.assetType == "native",
                      let hash = record.transactionHash,
                      let amountText = record.amount,
                      let amount = Double(amountText),
                      let createdAtText = record.createdAt,
                      let createdAt = iso8601Formatter.date(from: createdAtText) else {
                    return nil
                }
                let from = normalizedAddress(record.from ?? "")
                let to = normalizedAddress(record.to ?? "")
                if to == address {
                    return StellarHistorySnapshot(
                        transactionHash: hash,
                        kind: .receive,
                        amount: amount,
                        counterpartyAddress: from,
                        createdAt: createdAt,
                        status: .confirmed
                    )
                }
                if from == address {
                    return StellarHistorySnapshot(
                        transactionHash: hash,
                        kind: .send,
                        amount: amount,
                        counterpartyAddress: to,
                        createdAt: createdAt,
                        status: .confirmed
                    )
                }
                return nil
            case "create_account":
                guard let hash = record.transactionHash,
                      let amountText = record.amount,
                      let amount = Double(amountText),
                      let createdAtText = record.createdAt,
                      let createdAt = iso8601Formatter.date(from: createdAtText) else {
                    return nil
                }
                let funder = normalizedAddress(record.account ?? "")
                let to = normalizedAddress(record.to ?? "")
                if to == address {
                    return StellarHistorySnapshot(
                        transactionHash: hash,
                        kind: .receive,
                        amount: amount,
                        counterpartyAddress: funder,
                        createdAt: createdAt,
                        status: .confirmed
                    )
                }
                if funder == address {
                    return StellarHistorySnapshot(
                        transactionHash: hash,
                        kind: .send,
                        amount: amount,
                        counterpartyAddress: to,
                        createdAt: createdAt,
                        status: .confirmed
                    )
                }
                return nil
            default:
                return nil
            }
        }
    }

    private static func parsePaymentRecords(_ data: Data) throws -> [StellarProvider.PaymentRecord] {
        if let envelope = try? JSONDecoder().decode(StellarProvider.PaymentsEnvelope.self, from: data) {
            return envelope.embedded.records
        }
        if let envelope = try? JSONDecoder().decode(StellarProvider.PaymentsEnvelopeVariant.self, from: data) {
            return envelope.records ?? envelope.data ?? []
        }
        if let rows = try? JSONDecoder().decode([StellarProvider.PaymentRecord].self, from: data) {
            return rows
        }
        throw StellarBalanceServiceError.invalidResponse
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static func isMissingAccountError(_ error: Error) -> Bool {
        guard case StellarBalanceServiceError.httpError(let code) = error else {
            return false
        }
        return code == 404
    }

    static func stroops(fromXLM amount: Double) throws -> Int64 {
        guard amount > 0 else {
            throw StellarBalanceServiceError.invalidResponse
        }
        let amountText = String(format: "%.7f", amount)
        guard let xlm = Decimal(string: amountText) else {
            throw StellarBalanceServiceError.invalidResponse
        }
        let stroopsDecimal = xlm * stroopDivisor
        let rounded = NSDecimalNumber(decimal: stroopsDecimal).rounding(accordingToBehavior: nil)
        guard let integer = Int64(exactly: rounded) else {
            throw StellarBalanceServiceError.invalidResponse
        }
        return integer
    }
}
