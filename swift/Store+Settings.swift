import Foundation

/// The settings core owns, and how this front end mirrors them.
///
/// These eighteen fields were a `PersistedAppSettings` record: iOS built all
/// twenty-three of its fields from its own properties, wrote them together as
/// one blob, and read them back the same way. Two consequences. Every settings
/// change carried a snapshot of every other setting, so two screens editing two
/// settings raced and the later write reinstated the earlier screen's stale
/// copy of everything else. And the CLI could not read or set any of them —
/// which RPC to use, what a send's fee priority is, when an alert fires — while
/// claiming to drive the same core.
///
/// The properties stay where the UI binds to them, and `commitAppSettings`
/// sends one `SetAppSetting` per field that actually changed. Core bounds the
/// numbers and trims the strings, so the value that comes back through
/// `applyCoreState` is the stored one; the mirror adopts it and the round trip
/// stops on the equality guard.
extension AppState {
    /// Send the settings that differ from what core last told us it holds.
    ///
    /// Debounced by the caller — a slider drag or a typed endpoint would
    /// otherwise be one command per frame or per keystroke.
    func commitAppSettings() {
        // Two epochs, on purpose. The scheduled one was claimed when the edit
        // happened, so `awaitPendingCoreStateWrites` covers the debounce; it is
        // settled here. The apply needs a *fresh* one, because a load that
        // started after the edit holds a higher epoch and would otherwise make
        // core's answer to this very command read as stale and be dropped.
        guard let scheduled = pendingAppSettingsEpoch else { return }
        let updates = pendingAppSettingUpdates()
        guard !updates.isEmpty else {
            pendingAppSettingsEpoch = nil
            finishCoreStateRead(scheduled)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var latest: CoreAppState?
            for update in updates {
                guard
                    let transition = try? await WalletServiceBridge.shared.applyStateCommand(
                        .setAppSetting(update: update))
                else { continue }
                latest = transition.state
            }
            self.pendingAppSettingsEpoch = nil
            guard let latest else { self.finishCoreStateRead(scheduled); return }
            let epoch = self.beginCoreStateRead()
            self.finishCoreStateRead(scheduled)
            self.applyCoreState(latest, epoch: epoch)
        }
    }

    /// What this front end holds that core's last answer did not.
    ///
    /// Diffed rather than sent wholesale: the point of the split is that
    /// setting one field says one field. Before the first answer arrives every
    /// field counts as pending, which is what seeds a fresh install.
    private func pendingAppSettingUpdates() -> [AppSettingUpdate] {
        var updates: [AppSettingUpdate] = []
        let known = lastAppliedAppSettings
        func push(_ update: AppSettingUpdate, _ unchanged: Bool) {
            if known == nil || !unchanged { updates.append(update) }
        }
        push(.pricingProvider(value: pricingProvider.rawValue),
             known?.pricingProvider == pricingProvider.rawValue)
        push(.fiatRateProvider(value: fiatRateProvider.rawValue),
             known?.fiatRateProvider == fiatRateProvider.rawValue)
        push(.ethereumRpcEndpoint(value: ethereumRPCEndpoint),
             known?.ethereumRpcEndpoint == ethereumRPCEndpoint)
        push(.etherscanApiKey(value: etherscanAPIKey),
             known?.etherscanApiKey == etherscanAPIKey)
        push(.moneroBackendBaseUrl(value: moneroBackendBaseURL),
             known?.moneroBackendBaseUrl == moneroBackendBaseURL)
        push(.moneroBackendApiKey(value: moneroBackendAPIKey),
             known?.moneroBackendApiKey == moneroBackendAPIKey)
        push(.bitcoinEsploraEndpoints(value: bitcoinEsploraEndpoints),
             known?.bitcoinEsploraEndpoints == bitcoinEsploraEndpoints)
        push(.bitcoinStopGap(value: UInt32(max(0, bitcoinStopGap))),
             known.map { Int($0.bitcoinStopGap) } == bitcoinStopGap)
        push(.bitcoinFeePriority(value: bitcoinFeePriority.rawValue),
             known?.bitcoinFeePriority == bitcoinFeePriority.rawValue)
        push(.dogecoinFeePriority(value: dogecoinFeePriority.rawValue),
             known?.dogecoinFeePriority == dogecoinFeePriority.rawValue)
        push(.useStrictRpcOnly(value: preferences.useStrictRPCOnly),
             known?.useStrictRpcOnly == preferences.useStrictRPCOnly)
        push(.backgroundSyncProfile(value: backgroundSyncProfile.rawValue),
             known?.backgroundSyncProfile == backgroundSyncProfile.rawValue)
        push(
            .automaticRefreshFrequencyMinutes(
                value: UInt32(max(0, preferences.automaticRefreshFrequencyMinutes))),
            known.map { Int($0.automaticRefreshFrequencyMinutes) }
                == preferences.automaticRefreshFrequencyMinutes)
        push(.usePriceAlerts(value: preferences.usePriceAlerts),
             known?.usePriceAlerts == preferences.usePriceAlerts)
        push(.useTransactionStatusNotifications(value: preferences.useTransactionStatusNotifications),
             known?.useTransactionStatusNotifications == preferences.useTransactionStatusNotifications)
        push(.useLargeMovementNotifications(value: preferences.useLargeMovementNotifications),
             known?.useLargeMovementNotifications == preferences.useLargeMovementNotifications)
        push(
            .largeMovementAlertPercentThreshold(
                value: preferences.largeMovementAlertPercentThreshold),
            known?.largeMovementAlertPercentThreshold
                == preferences.largeMovementAlertPercentThreshold)
        push(
            .largeMovementAlertUsdThreshold(value: preferences.largeMovementAlertUSDThreshold),
            known?.largeMovementAlertUsdThreshold == preferences.largeMovementAlertUSDThreshold)
        return updates
    }

    /// Take core's settings as the truth, without sending them back.
    ///
    /// Each assignment is guarded, because these properties commit on `didSet`
    /// and an unguarded adopt would send core its own values in a loop.
    func adoptAppSettings(_ settings: AppSettings) {
        // An edit that has been made but not yet sent is newer than anything
        // core can answer with — the launch load is still in flight while the
        // user is already on the settings screen. Adopting here would overwrite
        // what they just typed, and then the diff would find nothing to send.
        guard pendingAppSettingsEpoch == nil else { return }
        lastAppliedAppSettings = settings
        if let value = PricingProvider(rawValue: settings.pricingProvider),
            value != pricingProvider { pricingProvider = value }
        if let value = FiatRateProvider(rawValue: settings.fiatRateProvider),
            value != fiatRateProvider { fiatRateProvider = value }
        if let value = BitcoinFeePriority(rawValue: settings.bitcoinFeePriority),
            value != bitcoinFeePriority { bitcoinFeePriority = value }
        if let value = DogecoinFeePriority(rawValue: settings.dogecoinFeePriority),
            value != dogecoinFeePriority { dogecoinFeePriority = value }
        if let value = BackgroundSyncProfile(rawValue: settings.backgroundSyncProfile),
            value != backgroundSyncProfile { backgroundSyncProfile = value }
        if settings.ethereumRpcEndpoint != ethereumRPCEndpoint {
            ethereumRPCEndpoint = settings.ethereumRpcEndpoint
        }
        if settings.etherscanApiKey != etherscanAPIKey { etherscanAPIKey = settings.etherscanApiKey }
        if settings.moneroBackendBaseUrl != moneroBackendBaseURL {
            moneroBackendBaseURL = settings.moneroBackendBaseUrl
        }
        if settings.moneroBackendApiKey != moneroBackendAPIKey {
            moneroBackendAPIKey = settings.moneroBackendApiKey
        }
        if settings.bitcoinEsploraEndpoints != bitcoinEsploraEndpoints {
            bitcoinEsploraEndpoints = settings.bitcoinEsploraEndpoints
        }
        if Int(settings.bitcoinStopGap) != bitcoinStopGap {
            bitcoinStopGap = Int(settings.bitcoinStopGap)
        }
        if settings.useStrictRpcOnly != preferences.useStrictRPCOnly {
            preferences.useStrictRPCOnly = settings.useStrictRpcOnly
        }
        if Int(settings.automaticRefreshFrequencyMinutes)
            != preferences.automaticRefreshFrequencyMinutes
        {
            preferences.automaticRefreshFrequencyMinutes =
                Int(settings.automaticRefreshFrequencyMinutes)
        }
        if settings.usePriceAlerts != preferences.usePriceAlerts {
            preferences.usePriceAlerts = settings.usePriceAlerts
        }
        if settings.useTransactionStatusNotifications
            != preferences.useTransactionStatusNotifications
        {
            preferences.useTransactionStatusNotifications = settings.useTransactionStatusNotifications
        }
        if settings.useLargeMovementNotifications != preferences.useLargeMovementNotifications {
            preferences.useLargeMovementNotifications = settings.useLargeMovementNotifications
        }
        if settings.largeMovementAlertPercentThreshold
            != preferences.largeMovementAlertPercentThreshold
        {
            preferences.largeMovementAlertPercentThreshold =
                settings.largeMovementAlertPercentThreshold
        }
        if settings.largeMovementAlertUsdThreshold != preferences.largeMovementAlertUSDThreshold {
            preferences.largeMovementAlertUSDThreshold = settings.largeMovementAlertUsdThreshold
        }
    }
}

/// The four settings that stayed on the platform.
///
/// Hiding balances is one front end's presentation; Face ID, auto-lock and
/// biometric-gated sends are one platform's capability, and a CLI has neither
/// the concept nor a way to honour them. They persist through the generic
/// key-value store rather than as a typed record crossing the boundary.
struct PlatformPreferences: Codable, Equatable {
    var hideBalances = false
    var useFaceID = true
    var useAutoLock = false
    var requireBiometricForSendActions = true
}
