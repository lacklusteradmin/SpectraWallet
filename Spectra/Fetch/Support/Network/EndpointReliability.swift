import Foundation

enum ChainEndpointReliability {
    private struct Counter: Codable {
        var successCount: Int
        var failureCount: Int
        var lastUpdatedAt: TimeInterval
    }

    private static func defaultsKey(for namespace: String) -> String {
        "chain.endpoint.reliability.\(namespace).v1"
    }

    static func orderedEndpoints(namespace: String, candidates: [String]) -> [String] {
        let counters = loadCounters(namespace: namespace)
        return candidates.sorted { lhs, rhs in
            let leftScore = score(counters[lhs])
            let rightScore = score(counters[rhs])
            if leftScore == rightScore {
                return lhs < rhs
            }
            return leftScore > rightScore
        }
    }

    static func recordAttempt(namespace: String, endpoint: String, success: Bool) {
        var counters = loadCounters(namespace: namespace)
        var counter = counters[endpoint] ?? Counter(successCount: 0, failureCount: 0, lastUpdatedAt: 0)
        if success {
            counter.successCount += 1
        } else {
            counter.failureCount += 1
        }
        counter.lastUpdatedAt = Date().timeIntervalSince1970
        counters[endpoint] = counter
        saveCounters(counters, namespace: namespace)
    }

    private static func score(_ counter: Counter?) -> Double {
        guard let counter else { return 0.5 }
        let attempts = max(1, counter.successCount + counter.failureCount)
        return Double(counter.successCount) / Double(attempts)
    }

    private static func loadCounters(namespace: String) -> [String: Counter] {
        let key = defaultsKey(for: namespace)
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Counter].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveCounters(_ counters: [String: Counter], namespace: String) {
        let key = defaultsKey(for: namespace)
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
