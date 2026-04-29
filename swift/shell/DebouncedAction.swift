import Foundation

/// Coalesces rapid `fire(_:)` calls into a single delayed execution.
///
/// Replaces the hand-rolled pattern that recurred across `AppState`:
///
/// ```swift
/// task?.cancel()
/// task = Task { @MainActor [weak self] in
///     try? await Task.sleep(nanoseconds: N)
///     guard !Task.isCancelled, let self else { return }
///     self.doWork()
/// }
/// ```
///
/// Each call to `fire` cancels any in-flight delay and starts a new one.
/// The interval is fixed at construction so reading the call site shows
/// the action *and* its debounce window in one place. `cancel()` discards
/// the pending action without firing it.
nonisolated final class DebouncedAction: @unchecked Sendable {
    /// Debounce window for the most recently fired closure. Captured at
    /// init so the configured interval is visible alongside the field
    /// declaration ("wallets debounce 30ms; live prices 200ms; …").
    let intervalNanoseconds: UInt64
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(intervalMilliseconds: UInt64) {
        self.intervalNanoseconds = intervalMilliseconds * 1_000_000
    }

    /// Schedule `work` to run after the configured interval. If `fire` is
    /// called again before that interval elapses, the previous schedule is
    /// cancelled and a fresh one starts.
    @MainActor
    func fire(_ work: @escaping @MainActor () -> Void) {
        lock.lock()
        task?.cancel()
        let interval = intervalNanoseconds
        let next = Task { @MainActor in
            try? await Task.sleep(nanoseconds: interval)
            guard !Task.isCancelled else { return }
            work()
        }
        task = next
        lock.unlock()
    }

    /// Drop the pending action without running it. Safe to call from
    /// `deinit` (non-isolated) — only touches the underlying Task handle,
    /// not main-actor state.
    func cancel() {
        lock.lock()
        task?.cancel()
        task = nil
        lock.unlock()
    }
}
