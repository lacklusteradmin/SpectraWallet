import Foundation

enum MoneroBalanceServiceError: LocalizedError {
    case invalidAddress
    case backendNotConfigured
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Monero")
        case .backendNotConfigured:
            return NSLocalizedString("Monero backend is not configured.", comment: "")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Monero")
        case .httpError(let status):
            let format = NSLocalizedString("The Monero backend returned HTTP %d.", comment: "")
            return String(format: format, locale: .current, status)
        }
    }
}

struct MoneroHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct MoneroHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum MoneroBalanceService {
    typealias TrustedBackend = MoneroProvider.TrustedBackend
    static let backendBaseURLDefaultsKey = MoneroProvider.backendBaseURLDefaultsKey
    static let backendAPIKeyDefaultsKey = MoneroProvider.backendAPIKeyDefaultsKey
    static let defaultBackendID = MoneroProvider.defaultBackendID
    static let defaultPublicBackend = MoneroProvider.defaultPublicBackend
    static let trustedBackends = MoneroProvider.trustedBackends

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidMoneroAddress(address)
    }

    static func configuredBackendBaseURL() -> URL? {
        if let value = UserDefaults.standard.string(forKey: MoneroProvider.backendBaseURLDefaultsKey) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return url
            }
        }
        return URL(string: MoneroProvider.defaultPublicBackend.baseURL)
    }

    static func candidateBackendBaseURLs() -> [URL] {
        var urls: [URL] = []
        if let primary = configuredBackendBaseURL() {
            urls.append(primary)
        }
        for backend in MoneroProvider.trustedBackends {
            guard let url = URL(string: backend.baseURL) else { continue }
            if !urls.contains(url) {
                urls.append(url)
            }
        }
        return Array(urls.prefix(3))
    }

    private static func shouldFallback(for statusCode: Int) -> Bool {
        [404, 405, 429, 500, 501, 502, 503, 504].contains(statusCode)
    }

    static func configuredBackendAPIKey() -> String? {
        let value = UserDefaults.standard.string(forKey: MoneroProvider.backendAPIKeyDefaultsKey) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            throw MoneroBalanceServiceError.invalidAddress
        }
        let candidates = candidateBackendBaseURLs()
        guard !candidates.isEmpty else {
            throw MoneroBalanceServiceError.backendNotConfigured
        }
        var lastError: Error = MoneroBalanceServiceError.invalidResponse
        for (index, baseURL) in candidates.enumerated() {
            var components = URLComponents(url: baseURL.appendingPathComponent("v1/monero/balance"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "address", value: normalized)]
            guard let url = components?.url else {
                continue
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            if let apiKey = configuredBackendAPIKey() {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            do {
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = MoneroBalanceServiceError.invalidResponse
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    lastError = MoneroBalanceServiceError.httpError(http.statusCode)
                    if index < candidates.count - 1, shouldFallback(for: http.statusCode) {
                        continue
                    }
                    throw lastError
                }
                let decoded = try JSONDecoder().decode(MoneroProvider.BalanceResponse.self, from: data)
                guard decoded.balanceXMR.isFinite, decoded.balanceXMR >= 0 else {
                    lastError = MoneroBalanceServiceError.invalidResponse
                    continue
                }
                return decoded.balanceXMR
            } catch {
                lastError = error
                if index < candidates.count - 1 {
                    continue
                }
            }
        }
        throw lastError
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 80) async -> (snapshots: [MoneroHistorySnapshot], diagnostics: MoneroHistoryDiagnostics) {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            return (
                [],
                MoneroHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: MoneroBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }
        let candidates = candidateBackendBaseURLs()
        guard !candidates.isEmpty else {
            return (
                [],
                MoneroHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "backend",
                    transactionCount: 0,
                    error: MoneroBalanceServiceError.backendNotConfigured.localizedDescription
                )
            )
        }

        var lastErrorMessage: String = MoneroBalanceServiceError.invalidResponse.localizedDescription
        for (index, baseURL) in candidates.enumerated() {
            var components = URLComponents(url: baseURL.appendingPathComponent("v1/monero/history"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "address", value: normalized),
                URLQueryItem(name: "limit", value: String(max(1, min(limit, 300))))
            ]
            guard let url = components?.url else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                if let apiKey = configuredBackendAPIKey() {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await fetchData(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastErrorMessage = MoneroBalanceServiceError.invalidResponse.localizedDescription
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    lastErrorMessage = "HTTP \(http.statusCode)"
                    if index < candidates.count - 1, shouldFallback(for: http.statusCode) {
                        continue
                    }
                    return (
                        [],
                        MoneroHistoryDiagnostics(address: normalized, sourceUsed: baseURL.host ?? "backend", transactionCount: 0, error: lastErrorMessage)
                    )
                }
                let decoded = try JSONDecoder().decode(MoneroProvider.HistoryResponse.self, from: data)
                let snapshots: [MoneroHistorySnapshot] = decoded.transactions.compactMap { item in
                    let txid = item.txid.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !txid.isEmpty else { return nil }
                    let kind: TransactionKind = item.direction.lowercased() == "in" ? .receive : .send
                    let status: TransactionStatus
                    switch (item.status ?? "").lowercased() {
                    case "pending", "pool":
                        status = .pending
                    case "failed":
                        status = .failed
                    default:
                        status = .confirmed
                    }
                    let amount = max(0, item.amountXMR)
                    return MoneroHistorySnapshot(
                        transactionHash: txid,
                        kind: kind,
                        amount: amount,
                        counterpartyAddress: item.counterpartyAddress ?? "",
                        createdAt: Date(timeIntervalSince1970: max(0, item.timestamp)),
                        status: status
                    )
                }
                return (
                    snapshots,
                    MoneroHistoryDiagnostics(address: normalized, sourceUsed: baseURL.host ?? "backend", transactionCount: snapshots.count, error: nil)
                )
            } catch {
                lastErrorMessage = error.localizedDescription
                if index < candidates.count - 1 {
                    continue
                }
            }
        }
        return (
            [],
            MoneroHistoryDiagnostics(address: normalized, sourceUsed: "backend", transactionCount: 0, error: lastErrorMessage)
        )
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await ProviderHTTP.data(for: request, profile: .chainRead)
    }
}
