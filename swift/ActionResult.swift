import Foundation

/// Surface for failable Button actions that need to report status to the user.
///
/// SwiftUI `Button(action: { try? doFailableThing() })` swallows failures
/// silently — a reader of the view can't tell which buttons can fail and
/// the user gets no feedback. This type holds the most-recent outcome of
/// a single named action so the view can bind a banner / inline error /
/// success toast against it.
///
/// Adoption: views that wrap a fail-prone store call replace
///     Button(action) { Task { await store.foo() } }
/// with
///     Button(action) {
///         actionResult.run { try await store.foo() }
///     }
/// and render `actionResult.banner` somewhere visible.
@MainActor
@Observable
final class ActionResult {
    /// Last outcome observed, or `.idle` if no action has run yet.
    private(set) var state: State = .idle

    enum State: Equatable {
        case idle
        case inFlight
        case success(message: String?)
        case failure(message: String)
    }

    /// Wrap a failable async action. Sets `.inFlight` for the duration,
    /// then `.success` or `.failure` based on whether `body` threw.
    func run(
        successMessage: String? = nil,
        _ body: () async throws -> Void
    ) async {
        state = .inFlight
        do {
            try await body()
            state = .success(message: successMessage)
        } catch {
            state = .failure(message: String(describing: error))
        }
    }

    /// Reset to `.idle`. Call when the user dismisses the banner or
    /// navigates away.
    func clear() { state = .idle }

    /// User-visible string for the current state, or `nil` when idle /
    /// in-flight (callers usually want a separate spinner for the latter).
    var banner: String? {
        switch state {
        case .idle, .inFlight: return nil
        case .success(let message): return message
        case .failure(let message): return message
        }
    }

    var isInFlight: Bool {
        if case .inFlight = state { return true }
        return false
    }
}
