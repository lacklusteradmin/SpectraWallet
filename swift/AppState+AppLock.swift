import Foundation
import LocalAuthentication

enum DeviceAuthenticationAction {
    case unlock, send, deleteWallet, resetData, revealSeedPhrase

    func requiresAuthentication(useFaceId: Bool, authenticateSends: Bool) -> Bool {
        switch self {
        case .send: return useFaceId && authenticateSends
        case .unlock, .deleteWallet, .resetData: return useFaceId
        // Showing signing material is never unprotected, whatever the preferences say.
        case .revealSeedPhrase: return true
        }
    }
}

@MainActor
extension AppState {
    func unlockApp() async {
        let failure = await authenticate(.unlock, reason: AppLocalization.string("Authenticate to unlock Spectra"))
        appLockError = failure
        if failure == nil { isAppLocked = false }
    }

    /// `nil` when the action may proceed; otherwise why it may not. The caller
    /// shows the reason in its own flow — an unlock failure is not a send error.
    func authenticate(_ action: DeviceAuthenticationAction, reason: String) async -> String? {
        guard action.requiresAuthentication(useFaceId: preferences.useFaceId,
            authenticateSends: preferences.requireBiometricForSendActions) else { return nil }
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            return AppLocalization.format(
                "Device authentication unavailable: %@",
                authError?.localizedDescription ?? AppLocalization.string("unknown error"))
        }
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
