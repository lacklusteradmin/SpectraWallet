import Foundation

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
    var hideBalances: Bool = false { didSet { guard hideBalances != oldValue else { return }; persistHandler?() } }

    // ── Security ────────────────────────────────────────────────────────
    var useFaceID: Bool = true {
        didSet {
            guard useFaceID != oldValue else { return }
            persistHandler?()
            if !useFaceID { useFaceIDDisabledHandler?() }
        }
    }
    var useAutoLock: Bool = false { didSet { guard useAutoLock != oldValue else { return }; persistHandler?() } }
    var useStrictRPCOnly: Bool = false { didSet { guard useStrictRPCOnly != oldValue else { return }; persistHandler?() } }
    var requireBiometricForSendActions: Bool = true {
        didSet { guard requireBiometricForSendActions != oldValue else { return }; persistHandler?() }
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
    var automaticRefreshFrequencyMinutes: Int = 5 {
        didSet {
            let clamped = min(max(automaticRefreshFrequencyMinutes, 5), 60)
            if clamped != automaticRefreshFrequencyMinutes {
                automaticRefreshFrequencyMinutes = clamped
                return
            }
            guard automaticRefreshFrequencyMinutes != oldValue else { return }
            persistHandler?()
            refreshFrequencyChangedHandler?()
        }
    }
    var largeMovementAlertPercentThreshold: Double = 10.0 {
        didSet {
            let clamped = min(max(largeMovementAlertPercentThreshold, 1), 90)
            if clamped != largeMovementAlertPercentThreshold {
                largeMovementAlertPercentThreshold = clamped
                return
            }
            persistHandler?()
        }
    }
    var largeMovementAlertUSDThreshold: Double = 50.0 {
        didSet {
            let clamped = min(max(largeMovementAlertUSDThreshold, 1), 100_000)
            if clamped != largeMovementAlertUSDThreshold {
                largeMovementAlertUSDThreshold = clamped
                return
            }
            persistHandler?()
        }
    }

    // ── Side-effect hooks, wired by `AppState` in its init. Kept out of
    // `@Observable` tracking so closure assignment doesn't cause spurious
    // view invalidations.
    @ObservationIgnored var persistHandler: (() -> Void)?
    @ObservationIgnored var useFaceIDDisabledHandler: (() -> Void)?
    @ObservationIgnored var notificationPermissionRequestHandler: (() -> Void)?
    @ObservationIgnored var refreshFrequencyChangedHandler: (() -> Void)?

    nonisolated init() {}

    /// Reset to factory defaults. Called from `StoreLifecycleReset.reset()`.
    /// Does NOT trigger `persistHandler`; callers are responsible for
    /// scheduling persistence once the whole reset pass is complete.
    func resetToDefaults() {
        let previousPersist = persistHandler
        persistHandler = nil
        defer { persistHandler = previousPersist }
        hideBalances = false
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
