/// Holds an operation at a suspension point until the test releases it, so the
/// test can act while the operation is still in flight.
@MainActor
final class SuspensionGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []

    /// Called by the operation under test; returns what `resume` passes.
    func wait() async -> Value {
        await withCheckedContinuation {
            continuation = $0
            for arrival in arrivals { arrival.resume() }
            arrivals.removeAll()
        }
    }

    /// Returns once the operation is held in `wait()`.
    func reached() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { arrivals.append($0) }
    }

    func resume(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

extension SuspensionGate where Value == Void {
    func resume() { resume(()) }
}
