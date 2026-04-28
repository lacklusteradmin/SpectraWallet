import Foundation

/// Centralized registry for long-lived background tasks owned by an
/// `AppState`-shaped object.
///
/// Replaces the wall of `task?.cancel()` calls in `AppState.deinit` with
/// a single `cancelAll()`. Each task is registered under a name so the
/// reader can grep "what runs in this AppState" by reading the registry,
/// instead of scanning ~15 scattered `Task<Void, Never>?` properties.
///
/// The registry is non-isolated and uses an internal lock so callers can
/// register from any actor and `cancelAll` from a non-isolated `deinit`.
final class ManagedTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Register `task` under `name`, cancelling any previous task that
    /// shared the name. Re-registering the same name is the canonical way
    /// to replace an in-flight handler with a fresh one.
    func register(name: String, _ task: Task<Void, Never>) {
        lock.lock()
        tasks[name]?.cancel()
        tasks[name] = task
        lock.unlock()
    }

    /// Drop the named task without cancelling it (e.g. on natural completion).
    func clear(name: String) {
        lock.lock()
        tasks.removeValue(forKey: name)
        lock.unlock()
    }

    /// Cancel one named task. No-op if the name isn't registered.
    func cancel(name: String) {
        lock.lock()
        tasks[name]?.cancel()
        tasks.removeValue(forKey: name)
        lock.unlock()
    }

    /// Cancel every registered task. Safe to call from `deinit`.
    func cancelAll() {
        lock.lock()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        lock.unlock()
    }
}
