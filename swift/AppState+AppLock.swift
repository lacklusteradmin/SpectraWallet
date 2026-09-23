import Foundation
import LocalAuthentication

enum DeviceAuthenticationAction {
    case unlock, send, deleteWallet, resetData

    func requiresAuthentication(useFaceId: Bool, authenticateSends: Bool) -> Bool {
        switch self {
        case .send: return useFaceId && authenticateSends
        case .unlock, .deleteWallet, .resetData: return useFaceId
        }
    }
}

@MainActor
extension AppState {
    func unlockApp() async {
        guard preferences.useFaceId else { isAppLocked = false; appLockError = nil; return }
        if await authenticateForSensitiveAction(.unlock, reason: AppLocalization.string("Authenticate to unlock Spectra")) { isAppLocked = false; appLockError = nil }
    }
    func authenticateForSensitiveAction(_ action: DeviceAuthenticationAction, reason: String) async -> Bool {
        let sendSessionId = sendFlow.session.id
        guard action.requiresAuthentication(useFaceId: preferences.useFaceId,
            authenticateSends: preferences.requireBiometricForSendActions) else { return true }
        let context = LAContext(); var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            let message = AppLocalization.format(
                "Device authentication unavailable: %@",
                authError?.localizedDescription ?? AppLocalization.string("unknown error"))
            sendFlow.error = message; appLockError = message
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
                // `resume` sits outside the optional chain on purpose: the
                // continuation must be resumed exactly once even if the store
                // is gone by the time the prompt returns, and a `guard let
                // self else { return }` here would leak it instead.
                Task { @MainActor [weak self] in
                    if case .send = action, self?.sendFlow.session.id != sendSessionId {
                        continuation.resume(returning: false)
                        return
                    }
                    if success {
                        self?.appLockError = nil
                    } else {
                        let message = error?.localizedDescription ?? AppLocalization.string("Authentication cancelled.")
                        self?.sendFlow.error = message
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
