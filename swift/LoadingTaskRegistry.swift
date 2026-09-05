import Foundation

// Counts in-flight tasks by string ID, for the case where the same operation
// can run more than once at a time and a caller needs "is *this* one pending".
// A single "exactly one of these can run" flag is better as a Bool.
//
// Nothing calls this yet.
@MainActor
final class LoadingTaskRegistry {
    private var inflight: [String: Int] = [:]

    /// True when at least one task is registered under any ID.
    var isEmpty: Bool { inflight.isEmpty }

    /// Number of tasks currently registered under `id`. Useful when
    /// the same operation can fire concurrently (e.g. multiple
    /// per-wallet sends in flight at once).
    func count(forID id: String) -> Int { inflight[id] ?? 0 }

    /// True when one or more tasks are registered under `id`.
    func contains(_ id: String) -> Bool { count(forID: id) > 0 }

    /// Register the start of a task under `id`. Increments the count;
    /// pair with `finish(id:)`.
    func start(_ id: String) {
        inflight[id, default: 0] += 1
    }

    /// Register completion of a task under `id`. Decrements the count;
    /// removes the entry when the count reaches zero.
    func finish(_ id: String) {
        guard let current = inflight[id] else { return }
        if current <= 1 {
            inflight.removeValue(forKey: id)
        } else {
            inflight[id] = current - 1
        }
    }

    /// Convenience for the start/finish pattern around an `async` body.
    func track<T>(_ id: String, _ body: () async throws -> T) async rethrows -> T {
        start(id)
        defer { finish(id) }
        return try await body()
    }
}
