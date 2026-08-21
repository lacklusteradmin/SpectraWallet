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

/// User-facing UI / security preferences, split out of `AppState` so that
/// views which only read preferences (Settings, lock-screen UI, the
/// hide-balances dashboard mirror, etc.) don't get invalidated whenever
/// unrelated AppState properties (wallets, balances, transactions) change.
///
/// Apple's native pattern: split a god-object `@Observable` model along
/// coherent domains so each view observes only the sub-model it needs.
///
/// Writes are persisted through the owning `AppState` via `persistHandler`,
/// which keeps the single-blob SQLite schema intact — only the in-memory
/// observation graph is split.
@MainActor
@Observable
final class AppUserPreferences {
    // ── UI ──────────────────────────────────────────────────────────────
    var hideBalances: Bool = false { didSet { guard hideBalances != oldValue else { return }; platformPersistHandler?() } }
    var appearanceMode: AppearanceMode = {
        if let raw = UserDefaults.standard.string(forKey: "settings.appearanceMode"),
           let saved = AppearanceMode(rawValue: raw) { return saved }
        return .dark
    }() {
        didSet {
            guard appearanceMode != oldValue else { return }
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "settings.appearanceMode")
        }
    }

    // ── Security ────────────────────────────────────────────────────────
    var useFaceID: Bool = true {
        didSet {
            guard useFaceID != oldValue else { return }
            platformPersistHandler?()
            if !useFaceID { useFaceIDDisabledHandler?() }
        }
    }
    var useAutoLock: Bool = false { didSet { guard useAutoLock != oldValue else { return }; platformPersistHandler?() } }
    var useStrictRPCOnly: Bool = false { didSet { guard useStrictRPCOnly != oldValue else { return }; persistHandler?() } }
    var requireBiometricForSendActions: Bool = true {
        didSet { guard requireBiometricForSendActions != oldValue else { return }; platformPersistHandler?() }
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
            refreshFrequencyChangedHandler?()
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
    /// Persist the four this platform keeps.
    @ObservationIgnored var platformPersistHandler: (() -> Void)?
    @ObservationIgnored var useFaceIDDisabledHandler: (() -> Void)?
    @ObservationIgnored var notificationPermissionRequestHandler: (() -> Void)?
    @ObservationIgnored var refreshFrequencyChangedHandler: (() -> Void)?

    nonisolated init() {}

    /// The four this platform keeps, as one value to store and restore.
    var platformSnapshot: PlatformPreferences {
        PlatformPreferences(
            hideBalances: hideBalances, useFaceID: useFaceID, useAutoLock: useAutoLock,
            requireBiometricForSendActions: requireBiometricForSendActions)
    }
    /// Adopt stored platform preferences without writing them straight back.
    func applyPlatform(_ stored: PlatformPreferences) {
        let previous = platformPersistHandler
        platformPersistHandler = nil
        defer { platformPersistHandler = previous }
        hideBalances = stored.hideBalances
        useFaceID = stored.useFaceID
        useAutoLock = stored.useAutoLock
        requireBiometricForSendActions = stored.requireBiometricForSendActions
    }

    /// Reset to factory defaults. Called from `StoreLifecycleReset.reset()`.
    /// Does NOT trigger the persist handlers; callers are responsible for
    /// scheduling persistence once the whole reset pass is complete.
    func resetToDefaults() {
        let previousPersist = persistHandler
        let previousPlatform = platformPersistHandler
        persistHandler = nil
        platformPersistHandler = nil
        defer { persistHandler = previousPersist; platformPersistHandler = previousPlatform }
        hideBalances = false
        appearanceMode = .dark
        useFaceID = true
        useAutoLock = false
        useStrictRPCOnly = false
        requireBiometricForSendActions = true
        usePriceAlerts = true
        useTransactionStatusNotifications = true
        useLargeMovementNotifications = true
        automaticRefreshFrequencyMinutes = 5
        largeMovementAlertPercentThreshold = 10
        largeMovementAlertUSDThreshold = 50
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
