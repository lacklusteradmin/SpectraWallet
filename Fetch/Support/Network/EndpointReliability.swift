import Foundation

private struct RustEndpointReliabilityCounter: Codable {
    let successCount: UInt32
    let failureCount: UInt32
    let lastUpdatedAt: Int64
}

private struct RustEndpointOrderingPayload: Encodable {
    let candidates: [String]
    let counters: [String: RustEndpointReliabilityCounter]
}

private struct RustEndpointAttemptPayload: Encodable {
    let counters: [String: RustEndpointReliabilityCounter]
    let endpoint: String
    let success: Bool
    let observedAt: Int64
}

enum ChainEndpointReliability {
    private static func defaultsKey(for namespace: String) -> String {
        "chain.endpoint.reliability.\(namespace).v1"
    }

    static func orderedEndpoints(namespace: String, candidates: [String]) -> [String] {
        MainActor.assumeIsolated {
            let counters = loadCounters(namespace: namespace)
            let payload = RustEndpointOrderingPayload(candidates: candidates, counters: counters)
            guard
                let json = try? encodeJSONString(payload),
                let responseJSON = try? coreOrderEndpointsByReliabilityJson(requestJson: json),
                let data = responseJSON.data(using: .utf8),
                let ordered = try? JSONDecoder().decode([String].self, from: data)
            else {
                return candidates
            }
            return ordered
        }
    }

    static func recordAttempt(namespace: String, endpoint: String, success: Bool) {
        MainActor.assumeIsolated {
            let payload = RustEndpointAttemptPayload(
                counters: loadCounters(namespace: namespace),
                endpoint: endpoint,
                success: success,
                observedAt: Int64(Date().timeIntervalSince1970)
            )

            guard
                let json = try? encodeJSONString(payload),
                let responseJSON = try? coreRecordEndpointAttemptJson(requestJson: json),
                let data = responseJSON.data(using: .utf8),
                let counters = try? JSONDecoder().decode([String: RustEndpointReliabilityCounter].self, from: data)
            else {
                return
            }

            saveCounters(counters, namespace: namespace)
        }
    }

    private static func loadCounters(namespace: String) -> [String: RustEndpointReliabilityCounter] {
        let key = defaultsKey(for: namespace)
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: RustEndpointReliabilityCounter].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func saveCounters(_ counters: [String: RustEndpointReliabilityCounter], namespace: String) {
        let key = defaultsKey(for: namespace)
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return json
    }
}
