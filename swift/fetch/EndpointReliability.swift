import Foundation
enum ChainEndpointReliability {
    private static func defaultsKey(for namespace: String) -> String { "chain.endpoint.reliability.\(namespace).v1" }
    static func orderedEndpoints(namespace: String, candidates: [String]) -> [String] {
        MainActor.assumeIsolated {
            let counters = loadCounters(namespace: namespace)
            return coreOrderEndpointsByReliability(request: EndpointOrderingRequest(
                candidates: candidates, counters: counters
            ))
        }}
    static func recordAttempt(namespace: String, endpoint: String, success: Bool) {
        MainActor.assumeIsolated {
            let counters = coreRecordEndpointAttempt(request: EndpointAttemptRequest(
                counters: loadCounters(namespace: namespace), endpoint: endpoint, success: success, observedAt: Int64(Date().timeIntervalSince1970)
            ))
            saveCounters(counters, namespace: namespace)
        }}
    private static func loadCounters(namespace: String) -> [String: ReliabilityCounter] {
        let key = defaultsKey(for: namespace)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: CodableReliabilityCounter].self, from: data) else { return [:] }
        return decoded.mapValues { ReliabilityCounter(successCount: $0.successCount, failureCount: $0.failureCount, lastUpdatedAt: $0.lastUpdatedAt) }
    }
    private static func saveCounters(_ counters: [String: ReliabilityCounter], namespace: String) {
        let key = defaultsKey(for: namespace)
        let codable = counters.mapValues { CodableReliabilityCounter(successCount: $0.successCount, failureCount: $0.failureCount, lastUpdatedAt: $0.lastUpdatedAt) }
        guard let data = try? JSONEncoder().encode(codable) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
private struct CodableReliabilityCounter: Codable {
    let successCount: UInt32
    let failureCount: UInt32
    let lastUpdatedAt: Int64
}
