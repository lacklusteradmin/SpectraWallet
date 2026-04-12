import Foundation

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

    static func configuredBackendAPIKey() -> String? {
        let value = UserDefaults.standard.string(forKey: MoneroProvider.backendAPIKeyDefaultsKey) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
