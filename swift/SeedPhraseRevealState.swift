import Foundation

/// Transient secret presentation. A dismissed or hidden screen cannot adopt a late reveal.
@MainActor
@Observable
final class SeedPhraseRevealState {
    var isShowingPasswordPrompt = false
    var isShowingPhraseSheet = false
    var passwordInput = ""
    private(set) var phrase = ""
    var errorMessage: String?
    private(set) var isRevealing = false
    @ObservationIgnored private var requestId = UUID() // Binds results and cleanup to one reveal.
    @ObservationIgnored private var isVisible = false // Rejects tasks queued before the screen disappeared.
    @ObservationIgnored private var isSceneActive = true // Completion reads live lifecycle state.

    func activate(sceneIsActive: Bool = true) {
        isVisible = true
        isSceneActive = sceneIsActive
    }

    func deactivate() {
        isVisible = false
        invalidate()
    }

    func setSceneIsActive(_ active: Bool) {
        isSceneActive = active
        if !active { clearPresentation() }
    }

    func clearPresentation() {
        isShowingPasswordPrompt = false
        isShowingPhraseSheet = false
        passwordInput = ""
        phrase = ""
        errorMessage = nil
    }

    func invalidate() {
        requestId = UUID()
        isRevealing = false
        clearPresentation()
    }

    func clearPhrase() { phrase = "" }

    /// `nil` means the request no longer belongs to a visible screen.
    func reveal(canPresent: @MainActor () -> Bool,
                operation: @MainActor () async throws -> String) async -> Bool? {
        guard isVisible, isSceneActive, !isRevealing, canPresent(), !Task.isCancelled else { return nil }
        let request = requestId
        isRevealing = true
        defer { if requestId == request { isRevealing = false } }
        do {
            let revealed = try await operation()
            guard requestId == request, isVisible, isSceneActive, !Task.isCancelled, canPresent() else { return nil }
            phrase = revealed
            passwordInput = ""
            errorMessage = nil
            isShowingPhraseSheet = true
            return true
        } catch {
            guard requestId == request, isVisible, isSceneActive, !Task.isCancelled, canPresent() else { return nil }
            errorMessage = userErrorMessage(error)
            return false
        }
    }
}
