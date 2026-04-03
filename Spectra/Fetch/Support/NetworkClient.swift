import Foundation

enum NetworkRetryProfile {
    case chainRead
    case chainWrite
    case diagnostics
    case litecoinRead
    case litecoinWrite
    case litecoinDiagnostics

    var policy: NetworkRetryPolicy {
        switch self {
        case .chainRead:
            return NetworkRetryPolicy(maxAttempts: 3, initialDelay: 0.35, multiplier: 2.0, maxDelay: 2.0)
        case .chainWrite:
            return NetworkRetryPolicy(maxAttempts: 2, initialDelay: 0.25, multiplier: 2.0, maxDelay: 1.0)
        case .diagnostics:
            return NetworkRetryPolicy(maxAttempts: 2, initialDelay: 0.2, multiplier: 2.0, maxDelay: 0.8)
        case .litecoinRead:
            // Litecoin endpoints are commonly rate-limited; use gentler retries.
            return NetworkRetryPolicy(maxAttempts: 4, initialDelay: 0.55, multiplier: 2.0, maxDelay: 4.0)
        case .litecoinWrite:
            return NetworkRetryPolicy(maxAttempts: 3, initialDelay: 0.45, multiplier: 2.0, maxDelay: 3.0)
        case .litecoinDiagnostics:
            return NetworkRetryPolicy(maxAttempts: 3, initialDelay: 0.35, multiplier: 2.0, maxDelay: 2.5)
        }
    }
}

struct NetworkRetryPolicy {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let multiplier: Double
    let maxDelay: TimeInterval
}

enum NetworkResilience {
    static func data(
        for request: URLRequest,
        profile: NetworkRetryProfile,
        session: URLSession = .shared,
        retryStatusCodes: Set<Int> = Set([429] + Array(500 ... 599))
    ) async throws -> (Data, URLResponse) {
        let policy = profile.policy
        var delay = policy.initialDelay
        var lastError: Error?

        for attempt in 1 ... max(1, policy.maxAttempts) {
            do {
                let (data, response) = try await ProviderHTTP.sessionData(for: request, session: session)
                if let http = response as? HTTPURLResponse,
                   retryStatusCodes.contains(http.statusCode),
                   attempt < policy.maxAttempts {
                    try await sleepWithJitter(base: delay)
                    delay = min(policy.maxDelay, delay * policy.multiplier)
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                guard shouldRetry(error: error), attempt < policy.maxAttempts else {
                    throw error
                }
                try await sleepWithJitter(base: delay)
                delay = min(policy.maxDelay, delay * policy.multiplier)
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    static func data(
        from url: URL,
        profile: NetworkRetryProfile,
        session: URLSession = .shared,
        retryStatusCodes: Set<Int> = Set([429] + Array(500 ... 599))
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await data(
            for: request,
            profile: profile,
            session: session,
            retryStatusCodes: retryStatusCodes
        )
    }

    private static func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private static func sleepWithJitter(base: TimeInterval) async throws {
        let jitter = Double.random(in: 0 ... 0.15)
        let total = max(0.05, base + jitter)
        try await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
    }
}

protocol SpectraNetworkClient {
    func data(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse)
}

extension SpectraNetworkClient {
    func data(from url: URL, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await data(for: request, profile: profile)
    }
}

struct LiveSpectraNetworkClient: SpectraNetworkClient {
    nonisolated init() {}

    func data(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        try await NetworkResilience.data(for: request, profile: profile)
    }
}

actor SpectraNetworkRouter {
    static let shared = SpectraNetworkRouter()

    private var client: any SpectraNetworkClient

    init() {
        self.client = LiveSpectraNetworkClient()
    }

    func install(client: any SpectraNetworkClient) {
        self.client = client
    }

    func resetToDefault() {
        client = LiveSpectraNetworkClient()
    }

    func data(for request: URLRequest, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        try await client.data(for: request, profile: profile)
    }

    func data(from url: URL, profile: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        try await client.data(from: url, profile: profile)
    }
}

actor TestSpectraNetworkClient: SpectraNetworkClient {
    struct RequestKey: Hashable {
        let method: String
        let url: String
    }

    enum Event {
        case response(statusCode: Int, headers: [String: String], body: Data)
        case failure(URLError.Code)
    }

    private var queues: [RequestKey: [Event]] = [:]

    func enqueueResponse(
        method: String = "GET",
        url: String,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        body: Data
    ) {
        let key = RequestKey(method: method.uppercased(), url: url)
        queues[key, default: []].append(.response(statusCode: statusCode, headers: headers, body: body))
    }

    func enqueueJSONResponse(
        method: String = "GET",
        url: String,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        object: Any
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        var mergedHeaders = headers
        if mergedHeaders["Content-Type"] == nil {
            mergedHeaders["Content-Type"] = "application/json"
        }
        enqueueResponse(
            method: method,
            url: url,
            statusCode: statusCode,
            headers: mergedHeaders,
            body: data
        )
    }

    func enqueueFailure(method: String = "GET", url: String, code: URLError.Code) {
        let key = RequestKey(method: method.uppercased(), url: url)
        queues[key, default: []].append(.failure(code))
    }

    func data(for request: URLRequest, profile _: NetworkRetryProfile) async throws -> (Data, URLResponse) {
        let method = (request.httpMethod ?? "GET").uppercased()
        let urlString = request.url?.absoluteString ?? ""
        let key = RequestKey(method: method, url: urlString)
        guard var events = queues[key], !events.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        let event = events.removeFirst()
        queues[key] = events.isEmpty ? nil : events

        switch event {
        case let .failure(code):
            throw URLError(code)
        case let .response(statusCode, headers, body):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers) else {
                throw URLError(.badServerResponse)
            }
            return (body, response)
        }
    }
}
