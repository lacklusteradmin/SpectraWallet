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

/// Where the five platform preferences live.
///
/// Four were a JSON blob core stored for the app through a generic
/// `save_state` export, loaded after launch; the fifth, appearance, was here
/// because it must be known before the first frame. Hidden balances had the
/// same need and not the same store: until the blob arrived the dashboard
/// showed what the user had hidden. None of the five is a domain fact — a CLI
/// has no Face ID and no dashboard — so core had no reason to hold them, and
/// `UserDefaults` answers synchronously.
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

/// User-facing UI / security preferences, split out of `AppState` so that
/// views which only read preferences (Settings, lock-screen UI, the
/// hide-balances dashboard mirror, etc.) don't get invalidated whenever
/// unrelated AppState properties (wallets, balances, transactions) change.
///
/// Apple's native pattern: split a god-object `@Observable` model along
/// coherent domains so each view observes only the sub-model it needs.
///
/// Five are this platform's and persist in `UserDefaults` as they change; the
/// rest mirror core settings and commit through `persistHandler`.
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
    var useStrictRPCOnly: Bool = false { didSet { guard useStrictRPCOnly != oldValue else { return }; persistHandler?() } }
    var requireBiometricForSendActions: Bool = PlatformDefaults.bool(
        PlatformDefaults.requireBiometricForSendActions, default: true)
    {
        didSet {
            guard requireBiometricForSendActions != oldValue else { return }
            PlatformDefaults.set(requireBiometricForSendActions, PlatformDefaults.requireBiometricForSendActions)
        }
    }

    // ── Notifications ───────────────────────────────────────────────────
    var usePriceAlerts: Bool = true { didSet { guard usePriceAlerts != oldValue else { return }; persistHandler?() } }
    var useTransactionStatusNotifications: Bool = true {
        didSet {
            guard useTransactionStatusNotifications != oldValue else { return }
            persistHandler?()
            if useTransactionStatusNotifications { notificationPermissionRequestHandler?() }
        }
    }
    var useLargeMovementNotifications: Bool = true {
        didSet {
            guard useLargeMovementNotifications != oldValue else { return }
            persistHandler?()
            if useLargeMovementNotifications { notificationPermissionRequestHandler?() }
        }
    }

    // ── Refresh cadence + alert thresholds ──────────────────────────────
    // No clamps here. The bounds are `apply_app_setting`'s, which is where the
    // value is stored — this side re-clamping would be a second copy of a rule
    // about someone else's state, and the copy that used to live here was the
    // only one.
    var automaticRefreshFrequencyMinutes: Int = 5 {
        didSet {
            guard automaticRefreshFrequencyMinutes != oldValue else { return }
            persistHandler?()
        }
    }
    var largeMovementAlertPercentThreshold: Double = 10.0 {
        didSet {
            guard largeMovementAlertPercentThreshold != oldValue else { return }
            persistHandler?()
        }
    }
    var largeMovementAlertUSDThreshold: Double = 50.0 {
        didSet {
            guard largeMovementAlertUSDThreshold != oldValue else { return }
            persistHandler?()
        }
    }

    // ── Side-effect hooks, wired by `AppState` in its init. Kept out of
    // `@Observable` tracking so closure assignment doesn't cause spurious
    // view invalidations.
    /// Commit the settings core owns.
    @ObservationIgnored var persistHandler: (() -> Void)?
    @ObservationIgnored var useFaceIDDisabledHandler: (() -> Void)?
    @ObservationIgnored var notificationPermissionRequestHandler: (() -> Void)?

    nonisolated init() {}

    /// Reset to factory defaults. Called from `StoreLifecycleReset.reset()`.
    /// The five platform values write themselves back as they change; the core
    /// settings are reset by core, so the commit handler is held off.
    func resetToDefaults() {
        let previousPersist = persistHandler
        persistHandler = nil
        defer { persistHandler = previousPersist }
        // Only the five this platform owns. The other seven on this class —
        // strict RPC, the three notification toggles, the refresh cadence and
        // the two large-movement thresholds — are core settings mirrored here,
        // and `StateCommand::ResetAppSettings` puts them back; restating their
        // defaults made this file a second copy of `AppSettings::default()`.
        hideBalances = false
        appearanceMode = .dark
        useFaceID = true
        useAutoLock = false
        requireBiometricForSendActions = true
    }
}
