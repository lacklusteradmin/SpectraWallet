import Foundation

// MARK: - LoadingTaskRegistry
//
// Replaces the proliferation of `is…ing` Bools (`isImportingWallet`,
// `isPreparingEthereumSend`, `isResolvingReceiveAddress`, …) for the
// case where the same operation can fire concurrently or where callers
// need to check "is *this specific* operation pending."
//
// Each registered task is keyed by a string ID. A reader trying to
// answer "is the app busy with X?" calls `registry.contains("X")`.
// "Is the app busy with anything?" is `!registry.isEmpty`. State
// transitions go through `start`/`finish` so flipping a bool twice in
// a row becomes detectable (the registry records cardinality).
//
// Adoption is incremental — singleton "exactly one of these can run"
// flags are fine staying as Bools; the registry is for cases where
// "one of N concurrent" is the actual semantic. Audit pass:
//   * `isImportingWallet` → singleton, keep as Bool
//   * `isPreparingEthereumSend` → could fire per-wallet, candidate
//   * `isResolvingReceiveAddress` → singleton (one receive flow at a
//     time), keep as Bool
//   * `isRefreshingChainBalances` → singleton, keep as Bool
//   * `isRefreshingLivePrices` → singleton, keep as Bool
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
