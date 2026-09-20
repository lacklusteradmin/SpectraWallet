import Foundation

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }
}

/// Device-local preferences stored synchronously in `UserDefaults`.
/// Appearance and balance privacy must be available before the first frame.
private enum PlatformDefaults {
    static let hideBalances = "settings.platform.hideBalances"
    static let appearanceMode = "settings.appearanceMode"
    static let useFaceID = "settings.platform.useFaceID"
    static let useAutoLock = "settings.platform.useAutoLock"
    static let requireBiometricForSendActions = "settings.platform.requireBiometricForSendActions"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
    static func set(_ value: Bool, _ key: String) { UserDefaults.standard.set(value, forKey: key) }
}

/// The five preferences this platform keeps for itself, split out of
/// `AppState` so that views which only read them are not invalidated whenever
/// wallets, balances or transactions change.
///
/// The settings core owns lived here too, mirrored, with a handler to commit
/// them; they are `AppState.appSettings` now.
@MainActor
@Observable
final class AppUserPreferences {
    // ── UI ──────────────────────────────────────────────────────────────
    var hideBalances: Bool = PlatformDefaults.bool(PlatformDefaults.hideBalances, default: false) {
        didSet { if hideBalances != oldValue { PlatformDefaults.set(hideBalances, PlatformDefaults.hideBalances) } }
    }
    var appearanceMode: AppearanceMode = {
        if let raw = UserDefaults.standard.string(forKey: PlatformDefaults.appearanceMode),
           let saved = AppearanceMode(rawValue: raw) { return saved }
        return .dark
    }() {
        didSet {
            guard appearanceMode != oldValue else { return }
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: PlatformDefaults.appearanceMode)
        }
    }

    // ── Security ────────────────────────────────────────────────────────
    var useFaceID: Bool = PlatformDefaults.bool(PlatformDefaults.useFaceID, default: true) {
        didSet {
            guard useFaceID != oldValue else { return }
            PlatformDefaults.set(useFaceID, PlatformDefaults.useFaceID)
            if !useFaceID { useFaceIDDisabledHandler?() }
        }
    }
    var useAutoLock: Bool = PlatformDefaults.bool(PlatformDefaults.useAutoLock, default: false) {
        didSet { if useAutoLock != oldValue { PlatformDefaults.set(useAutoLock, PlatformDefaults.useAutoLock) } }
    }
    var requireBiometricForSendActions: Bool = PlatformDefaults.bool(
        PlatformDefaults.requireBiometricForSendActions, default: true)
    {
        didSet {
            guard requireBiometricForSendActions != oldValue else { return }
            PlatformDefaults.set(requireBiometricForSendActions, PlatformDefaults.requireBiometricForSendActions)
        }
    }

    /// Wired by `AppState` in its init. Kept out of `@Observable` tracking so
    /// assigning the closure does not invalidate views.
    @ObservationIgnored var useFaceIDDisabledHandler: (() -> Void)?

    nonisolated init() {}

    /// Reset to factory defaults. Each value writes itself back to
    /// `UserDefaults` as it changes.
    func resetToDefaults() {
        hideBalances = false
        appearanceMode = .dark
        useFaceID = true
        useAutoLock = false
        requireBiometricForSendActions = true
    }
}
