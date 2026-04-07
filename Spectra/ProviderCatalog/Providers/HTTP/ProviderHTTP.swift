import Foundation

enum ProviderHTTP {
    static func data(
        for request: URLRequest,
        profile: NetworkRetryProfile
    ) async throws -> (Data, URLResponse) {
        try await SpectraNetworkRouter.shared.data(for: request, profile: profile)
    }

    static func data(
        from url: URL,
        profile: NetworkRetryProfile
    ) async throws -> (Data, URLResponse) {
        try await SpectraNetworkRouter.shared.data(from: url, profile: profile)
    }

    static func sessionData(
        for request: URLRequest,
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    static func sessionData(
        from url: URL,
        session: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }

    static func sessionDataTask(
        with request: URLRequest,
        session: URLSession = .shared,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        session.dataTask(with: request, completionHandler: completionHandler)
    }

    static func sessionDataTask(
        with url: URL,
        session: URLSession = .shared,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        session.dataTask(with: url, completionHandler: completionHandler)
    }
}
