# Spectra Swift layer — file-by-file map

This document describes what each file in `swift/` does and how it relates to the Rust core in `core/src/`. The Swift layer is intentionally thin: all business logic (derivation, balance decoding, HTTP calls, SQLite persistence, send-flow planning, diagnostics aggregation, secrets policy) lives in Rust and is surfaced via UniFFI-generated bindings in [generated/spectra_core.swift](generated/spectra_core.swift). Swift only keeps SwiftUI views, `@MainActor ObservableObject` forwarding, and callbacks for iOS-only APIs that Rust cannot reach (Keychain, ActivityKit, UNUserNotificationCenter, UIDevice battery/network signals, biometric prompts).

## Top-level layout

```
swift/
├── shell/                         class AppState + its extensions (UI state orchestrator)
├── send/                          send-flow extensions split out of shell/
├── fetch/                         fetch-/diagnostics-state Swift side
├── derivation/                    derivation-layer Swift wrappers
├── rustbridge/                    thin forwarders onto UniFFI functions
├── views/                         SwiftUI views
├── extensions/                    Live Activity widget + shared attributes
├── tests/                         XCTest targets
├── generated/                     UniFFI-generated bindings (do not edit)
├── resources/                     Assets.xcassets
├── Spectra.xcodeproj/             Xcode project
└── Spectra.xctestplan
```

## shell/ — `class AppState` and its orchestration

`AppState` is the single `@MainActor ObservableObject` the whole SwiftUI app observes. It is sliced across many extension files so individual domains can be read in isolation. `wallets`, `transactions`, and `addressBook` are canonical Swift `@Published` arrays; persistence is durable via [shell/PersistenceStore.swift](shell/PersistenceStore.swift) into the Rust SQLite KV store.

- [shell/AppState.swift](shell/AppState.swift) — Declares `class AppState: ObservableObject`. Owns the `@Published` collections + scalars, derived-state caches, persistence-debounce `Task` handles, JSON coders, and logger categories.
- [shell/AppStateTypes.swift](shell/AppStateTypes.swift) — Nested types lifted out of `AppState.swift` for focus: `ResetScope`, `TimeoutError`, `BackgroundSyncProfile`, `MainAppTab`, etc. No runtime state.
- [shell/AppState+CoreStateStore.swift](shell/AppState+CoreStateStore.swift) — Mutation helpers (`setWallets`, `appendWallet`, `upsertWallet`, `removeWallet(id:)`, `setTransactions`, `prependTransaction`, `setAddressBook`, etc.) that centralise the standard add/replace/remove patterns on the three core `@Published` arrays.
- [shell/AppState+RustObserver.swift](shell/AppState+RustObserver.swift) — `WalletBalanceObserver` bridges the Rust per-chain balance refresh engine into AppState's `@Published` mirrors on the main actor.
- [shell/AppState+BalanceRefresh.swift](shell/AppState+BalanceRefresh.swift) — Kicks `WalletServiceBridge.triggerImmediateBalanceRefresh`, then batches per-chain balance deltas with a 30 ms debounce and flushes as one `wallets` mutation to avoid re-render storms.
- [shell/AppState+ReceiveFlow.swift](shell/AppState+ReceiveFlow.swift) — Receive-sheet orchestration. The `receiveAddress()` per-chain dispatch is routed through `corePlanReceiveAddressResolver` in Rust (`core/src/send/flow_helpers.rs`), so Swift only holds the thin `switch` that maps `ReceiveAddressResolverKind` back to the right Swift bridge call.
- [shell/AppState+SendFlow.swift](shell/AppState+SendFlow.swift) — Send-flow state machine: destination validation, risk-probe orchestration, Tron error mapping. Pure-logic helpers (`coreSeedDerivationChainRaw`, `coreMapEthereumSendError`, `coreChainRiskProbeMessages`, `coreSimpleChainRiskProbeConfig`) live in Rust `core/src/send/flow_helpers.rs`; this file glues them to SwiftUI-observable state.
- [shell/AppState+AddressResolution.swift](shell/AppState+AddressResolution.swift) — Resolves chain addresses for an `ImportedWallet` by calling `WalletDerivationLayer.derive…` (which ultimately hits Rust `core/src/derivation`). Handles watch-only addresses and Solana legacy-path preference.
- [shell/AppState+ImportLifecycle.swift](shell/AppState+ImportLifecycle.swift) — Drives `WalletImportDraft` state and the import/edit sheet presentation. Heavy parsing happens in Rust via `corePlanWalletImport`.
- [shell/AppState+PricingFiat.swift](shell/AppState+PricingFiat.swift) — Live-price refresh cadence, fiat-rate refresh, `enum FiatCurrency` (display names routed through `coreFiatCurrencyDisplayName`).
- [shell/AppState+OperationalTelemetry.swift](shell/AppState+OperationalTelemetry.swift) — Network-status text, operational log append/export.
- [shell/AppState+DiagnosticsEndpoints.swift](shell/AppState+DiagnosticsEndpoints.swift) — Per-chain diagnostics wiring. All JSON decoding / record construction is lifted to Rust `core/src/diagnostics`; this file only keeps KeyPath-driven AppState wiring and async orchestration around Rust's `httpRequest` / `httpPostJson` / `diagnosticsProbeJsonrpc` FFI.
- [shell/CoreModels.swift](shell/CoreModels.swift) — Swift-side model structs and enums (`Coin`, `ImportedWallet`, `ChainFeePriorityOption`, `SendPreviewDetails`, `TransactionRecord`, …). Several types are typealiased onto Rust-generated records (e.g. `Coin = CoreCoin`).
- [shell/RegistryModels.swift](shell/RegistryModels.swift) — `WalletChainID` value type + `TokenTrackingChain`/`CoreTokenTrackingChain` conformances. Display-name and alias lookup tables are built from `ChainWikiEntries.json` loaded via `StaticContentCatalog`.
- [shell/ChainRefreshDescriptors.swift](shell/ChainRefreshDescriptors.swift) — `WalletChainRefreshDescriptor` closures for each chain; the `plannedChainRefreshDescriptors` table decides which refresh/balance/history functions run per chain.
- [shell/DashboardStore.swift](shell/DashboardStore.swift) — Pinned-asset prototype catalog + pinning state. Color fields are SwiftUI `Color`, so this stays Swift-side.
- [shell/MaintenanceStore.swift](shell/MaintenanceStore.swift) — Battery/network-gated background maintenance. Decision logic (`computeBackgroundMaintenanceInterval`, `evaluateHeavyRefreshGate`, `activePendingRefreshIntervalForProfile`, `portfolioCompositionSignature`, `coreEvaluateLargeMovement`) is in Rust; this file only injects iOS-platform inputs (`UIDevice.batteryLevel`, `ProcessInfo.isLowPowerModeEnabled`).
- [shell/PersistenceStore.swift](shell/PersistenceStore.swift) — `loadCodableFromSQLite` / `persistCodableToSQLite` round-trips through `WalletServiceBridge.saveState/loadState`, which map to Rust `core/src/store/kv.rs`. All legacy UserDefaults reads are shims; writes go to SQLite.
- [shell/StorePersistenceNormalization.swift](shell/StorePersistenceNormalization.swift) — Rebuilds cached derived state (`cachedWalletByID`, `cachedIncludedPortfolioHoldings`, token-preference caches) using `rustStoreDerivedStatePlan` from Rust. Keeps all SwiftUI-observed caches coherent after mutations.
- [shell/StoreLifecycleReset.swift](shell/StoreLifecycleReset.swift) — App-launch state restoration (`restorePersistedRuntimeConfigurationAndState`) and `ResetScope`-driven wipes.
- [shell/StoreHistoryRefresh.swift](shell/StoreHistoryRefresh.swift) — Transaction-history pagination. Cursors/pages live in Rust (`wsb.historyNextCursor` etc.); Swift just notifies `objectWillChange`.
- [shell/StoreDiagnosticsExport.swift](shell/StoreDiagnosticsExport.swift) — `DiagnosticsEnvironmentMetadata` envelope + typealiases to smooth UniFFI's acronym-casing (`XRPHistoryDiagnostics = XrpHistoryDiagnostics`).
- [shell/Store+Formatting.swift](shell/Store+Formatting.swift) — `localizedStoreString`/`localizedStoreFormat` shortcuts and USD↔fiat conversions. Rate data is stored in Swift `@Published` (`fiatRatesFromUSD`) but the number formatting delegates to Rust helpers for the hot paths.
- [shell/Store+Notifications.swift](shell/Store+Notifications.swift) — Token-preference merge + price-alert evaluation + `UNUserNotificationCenter` scheduling (iOS-only).
- [shell/Platform.swift](shell/Platform.swift) — `PlatformSnapshotEnvelope` and the `makePlatformSnapshot()` implementations used for diagnostics bundle export. Pure value-type projections, no logic.
- [shell/SecureStores.swift](shell/SecureStores.swift) — Keychain-backed `SecureStore`, `SecureSeedStore`, `AppLockPinStore`. Wraps `KeychainAccess`; must stay in Swift because Rust cannot reach the iOS Keychain.
- [shell/StaticContentCatalog.swift](shell/StaticContentCatalog.swift) — Prefers `coreStaticResourceJson` (Rust `core/embedded/`) first, falls back to bundled JSON lookups across many locale paths. Used for `ChainWikiEntries`, `TokenVisualRegistry`, `DerivationPresets`, `SettingsContentCopy`, `DiagnosticsContentCopy`, etc.

## send/ — send-flow extensions (split out of shell/)

- [send/AppState+SendRouting.swift](send/AppState+SendRouting.swift) — `refreshSendPreview()` top-level dispatch by `SendPreviewKind` (chain).
- [send/AppState+SendPreview.swift](send/AppState+SendPreview.swift) — Per-chain preview decoders. UTXO, EVM, and simple-chain previews are built by Rust (`buildUtxoSendPreviewRecord`, `buildEvmSendPreviewRecord`, etc.); Swift orchestrates the async fetch.
- [send/AppState+SendExecution.swift](send/AppState+SendExecution.swift) — `submitSend()` final signing/broadcast path. Delegates to Rust `executeSend` for most chains; only the host/iOS state machine (Live Activity start/complete/fail, `@Published` mutations) remains in Swift.
- [send/SendPreviewTypes.swift](send/SendPreviewTypes.swift) — `EVMChainContext` enum + chain-ID mappings, Swift-side preview/result struct shapes.

## fetch/ — balance / diagnostics Swift side

- [fetch/ChainBackendModels.swift](fetch/ChainBackendModels.swift) — Small Codable registry of which chains support import/balance/receive/send (`AppChainID`, `AppChainDescriptor`, `ChainBackendRecord`).
- [fetch/ChainTypes.swift](fetch/ChainTypes.swift) — `RustBalanceDecoder` thin forwarders (every method is a one-liner into `core/src/fetch/balance_decoder.rs`) + `RustStringEnum` protocol for Rust-owned enums that need `RawRepresentable`/`CaseIterable` in Swift.
- [fetch/DiagnosticsState.swift](fetch/DiagnosticsState.swift) — `WalletDiagnosticsState: ObservableObject`. Holds per-chain `@Published` degraded-state maps and operational-log ring buffer; debounces persistence to the Rust-backed SQLite store.
- [fetch/DiagnosticsStore.swift](fetch/DiagnosticsStore.swift) — Long list of per-chain property shims bridging `AppState.bitcoinSelfTestResults` → `chainDiagnosticsState.bitcoinSelfTestResults`. Pure forwarding — exists to give views a single `@Published` surface.

## derivation/ — Swift wrappers over Rust derivation

- [derivation/WalletDerivationLayer.swift](derivation/WalletDerivationLayer.swift) — `WalletDerivationLayer.derive(...)`. Builds a `WalletRustDerivationRequestModel` and calls the UniFFI function; never does crypto itself. `core/src/derivation/...` owns seed derivation, key derivation, and address encoding.
- [derivation/WalletRustDerivationBridge.swift](derivation/WalletRustDerivationBridge.swift) — Maps Swift's `SeedDerivationChain` / `WalletDerivationNetwork` / requested-output sets onto the Rust FFI enum forms and decodes responses.
- [derivation/Presets.swift](derivation/Presets.swift) — Typealiases (`WalletDerivationChainPreset = AppCoreChainPreset`) + `WalletDerivationPath` helpers. Preset data itself lives in `core/embedded/DerivationPresets.json`.
- `DerivationChecklist.md`, `DerivationTestingFormat.md` — Human-facing notes; not compiled.

## rustbridge/ — UniFFI forwarders

These two files are the `AppState`-facing seam onto UniFFI. They are intentionally thin — add a Rust export, call it everywhere else. The former `WalletRustAppCoreBridge` pass-through wrapper was removed; call `corePlan*` / `coreActiveMaintenancePlan` / etc. directly.

- [rustbridge/WalletServiceBridge.swift](rustbridge/WalletServiceBridge.swift) — `actor WalletServiceBridge` + `enum SpectraChainID`. Owns the singleton `WalletService` instance, surfaces `fetchBalanceJSON`, `fetchHistoryJSON`, `fetchEVMSendPreviewJSON`, `executeSend`, `signAndSend`, `resolveENSName`, `deriveBitcoinAccountXpub`, `saveState/loadState`, etc.
- [rustbridge/WalletRustEndpointCatalogBridge.swift](rustbridge/WalletRustEndpointCatalogBridge.swift) — Calls `appCoreEndpointForId`, `appCoreEndpointRecordsForChainJson`, etc. Decodes the Rust `AppEndpointRecord` catalog stored in `core/embedded/AppEndpointDirectory.json`.

## views/ — SwiftUI

Pure UI. Each file observes `AppState` (`@EnvironmentObject` / `@StateObject`) and renders state. No business logic.

- [views/ContentView.swift](views/ContentView.swift) — App entry (`@main struct SpectraApp`), scene-phase wiring, app-lock overlay.
- [views/DashboardViews.swift](views/DashboardViews.swift) — Portfolio & pinned-asset dashboard.
- [views/HistoryView.swift](views/HistoryView.swift) — Transactions list with pagination.
- [views/ReceiveFlowViews.swift](views/ReceiveFlowViews.swift) — Receive sheet (address QR, chain picker).
- [views/SendFlowViews.swift](views/SendFlowViews.swift) — Send sheet (amount entry, fee priority, preview, confirm).
- [views/WalletFlowViews.swift](views/WalletFlowViews.swift) — Wallet list, detail, edit.
- [views/WalletSetupViews.swift](views/WalletSetupViews.swift) — Wallet import/create flow, network-mode toggles.
- [views/SettingsViews.swift](views/SettingsViews.swift) — Settings screens (fiat, pricing provider, alerts, token preferences, …).
- [views/SettingsTokenComponents.swift](views/SettingsTokenComponents.swift) — Token-picker row components used inside Settings.
- [views/DiagnosticsViews.swift](views/DiagnosticsViews.swift) — Per-chain diagnostics screens (self-tests, endpoint health, history probes).
- [views/EndpointsViews.swift](views/EndpointsViews.swift) — Per-chain endpoint editors.
- [views/ChainWikiViews.swift](views/ChainWikiViews.swift) — Chain info pages (from `ChainWikiEntries.json`).
- [views/TransactionDetailView.swift](views/TransactionDetailView.swift) — Single-transaction detail.
- [views/AddWalletEntryView.swift](views/AddWalletEntryView.swift) — Row component for "add wallet" rows.
- [views/StakingView.swift](views/StakingView.swift), [views/DonationsView.swift](views/DonationsView.swift) — Tab stubs.
- [views/ImportDraft.swift](views/ImportDraft.swift) — `WalletImportDraft: ObservableObject` used by the import sheet.
- [views/IconUIHelpers.swift](views/IconUIHelpers.swift) — `CoinBadge` and icon fallback helpers.
- [views/BundleImageLoader.swift](views/BundleImageLoader.swift) — Loads token PNGs from the bundle `Resources/icons/` folder (bypasses xcassets).
- [views/LiveActivityManager.swift](views/LiveActivityManager.swift) — `SendTransactionLiveActivityManager` — starts/updates/ends `ActivityKit` activities for in-flight sends.

## extensions/ — iOS widget target

- [extensions/SharedLiveActivities/SendLiveActivityAttributes.swift](extensions/SharedLiveActivities/SendLiveActivityAttributes.swift) — `ActivityAttributes` shared between the main app and the widget extension (compiled into both targets).
- [extensions/SpectraLiveActivityExtension/SendLiveActivityWidget.swift](extensions/SpectraLiveActivityExtension/SendLiveActivityWidget.swift) — The `WidgetBundle` / `ActivityConfiguration` rendered on the Lock Screen and Dynamic Island.
- `extensions/SpectraLiveActivityExtension/Info.plist` — extension Info.plist.

## tests/ — XCTest

- [tests/AppStateTests.swift](tests/AppStateTests.swift) — High-level `AppState` behavior.
- [tests/RefreshPlannerTests.swift](tests/RefreshPlannerTests.swift) — Verifies `plannedChainRefreshDescriptors` ordering and chain-name → ID mapping.
- [tests/NetworkClientTests.swift](tests/NetworkClientTests.swift) — `EVMChainContext` display names / chain-ID mappings.
- [tests/DiagnosticsStateTests.swift](tests/DiagnosticsStateTests.swift), [tests/DiagnosticsBundleTests.swift](tests/DiagnosticsBundleTests.swift) — Diagnostics state and bundle export.
- [tests/SecureSeedStoreTests.swift](tests/SecureSeedStoreTests.swift) — Keychain-backed seed store round-trip.
- [tests/SolanaBalanceTests.swift](tests/SolanaBalanceTests.swift) — Balance-decoder smoke test for Solana JSON shape.

## generated/ — UniFFI output (do not edit)

- [generated/spectra_core.swift](generated/spectra_core.swift) — Swift bindings for every `#[uniffi::export]` in `core/src/` and `ffi/src/`. Regenerated by `scripts/bindgen-ios.sh`.
- `generated/spectra_coreFFI.h`, `.modulemap`, `-Bridging-Header.h` — C-ABI headers the Swift module imports.

## resources/

- `resources/Assets.xcassets` — Image/color asset catalog. Token PNGs live in the top-level `Resources/icons/` folder (referenced by a `PBXFileSystemSynchronizedRootGroup`), and JSON content strings live in `core/embedded/` so Rust can load them too.

---

## How Swift talks to Rust

1. **Static content.** JSON/text data files live in `core/embedded/` (chain wiki, endpoint directory, derivation presets, token visual registry, BIP-39 word list). Swift loads them via `coreStaticResourceJson` in [shell/StaticContentCatalog.swift](shell/StaticContentCatalog.swift); Bundle JSON is only a fallback for localized strings.
2. **Canonical state.** Wallets / transactions / address book are Swift `@Published` arrays on `AppState`. Durable persistence lives in `core/src/store/` (SQLite via `rusqlite`); Swift writes flow through [shell/PersistenceStore.swift](shell/PersistenceStore.swift) and helpers in [shell/AppState+CoreStateStore.swift](shell/AppState+CoreStateStore.swift).
3. **HTTP / fetch.** `WalletService` in Rust owns `reqwest` clients. [rustbridge/WalletServiceBridge.swift](rustbridge/WalletServiceBridge.swift) is the async-facing actor; every network call eventually goes through it.
4. **Derivation.** Swift never does key derivation. [derivation/WalletDerivationLayer.swift](derivation/WalletDerivationLayer.swift) builds a request model and calls the UniFFI entry point backed by `core/src/derivation/`.
5. **Secrets.** Seed phrases and PINs sit in the iOS Keychain via [shell/SecureStores.swift](shell/SecureStores.swift). Rust's secrets *policy* (which keys, which access classes) is mirrored in Rust types, but the actual Keychain IO is Swift-only by necessity.
6. **Platform callbacks that Rust can't reach.** `UIDevice.batteryLevel`, `ProcessInfo.isLowPowerModeEnabled`, `NWPathMonitor` reachability, `ActivityKit` live activities, `UNUserNotificationCenter` notifications, biometric prompts — all stay in Swift and feed their signals into Rust-evaluated policy functions (see [shell/MaintenanceStore.swift](shell/MaintenanceStore.swift)).
