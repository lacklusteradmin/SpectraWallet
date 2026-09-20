import Foundation
import LocalAuthentication

@MainActor
extension AppState {
    func unlockApp() async {
        guard preferences.useFaceId else { isAppLocked = false; appLockError = nil; return }
        if await authenticateForSensitiveAction(reason: AppLocalization.string("Authenticate to unlock Spectra")) { isAppLocked = false; appLockError = nil }
    }
    func authenticateForSensitiveAction(reason: String, allowWhenAuthenticationUnavailable: Bool = false) async -> Bool {
        guard preferences.useFaceId, preferences.requireBiometricForSendActions else { return true }
        let context = LAContext(); var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            if allowWhenAuthenticationUnavailable { return true }
            let message = AppLocalization.format(
                "Device authentication unavailable: %@",
                authError?.localizedDescription ?? AppLocalization.string("unknown error"))
            sendError = message; appLockError = message
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
                // `resume` sits outside the optional chain on purpose: the
                // continuation must be resumed exactly once even if the store
                // is gone by the time the prompt returns, and a `guard let
                // self else { return }` here would leak it instead.
                Task { @MainActor [weak self] in
                    if success {
                        self?.appLockError = nil
                    } else {
                        let message = error?.localizedDescription ?? AppLocalization.string("Authentication cancelled.")
                        self?.sendError = message
                        self?.appLockError = message
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }
    func authenticateForSeedPhraseReveal(reason: String) async -> Bool {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
