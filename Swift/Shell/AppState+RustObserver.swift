// Phase-1 Rust→Swift observer bridge.
//
// Rust's app_state event bus publishes typed events whenever the canonical
// store mutates. This file implements the `AppStateObserver` UniFFI foreign
// trait on `AppState` and registers it during `init()`. Every callback hops
// to `@MainActor` before mutating the corresponding `@Published` mirror, so
// SwiftUI reactivity is preserved.
//
// After this bridge is in place, Swift helpers no longer need to assign to
// `self.wallets` / `self.transactions` / `self.addressBook` after calling a
// `store*` function — Rust pushes the new value via the observer.

import Foundation
import Combine

/// Concrete observer forwarded to Rust. Held weakly against `AppState` so
/// `deinit` breaks the retain cycle cleanly.
final class AppStateRustObserver: AppStateObserver, @unchecked Sendable {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func walletsChanged(wallets: [CoreImportedWallet]) {
        let snapshot = wallets
        Task { @MainActor [weak appState] in
            guard let appState else { return }
            appState.applyWalletsFromRust(snapshot)
        }
    }

    func transactionsChanged(transactions: [CorePersistedTransactionRecord]) {
        let snapshot = transactions
        Task { @MainActor [weak appState] in
            guard let appState else { return }
            appState.applyTransactionsFromRust(snapshot)
        }
    }

    func addressBookChanged(entries: [CorePersistedAddressBookEntry]) {
        let snapshot = entries
        Task { @MainActor [weak appState] in
            guard let appState else { return }
            appState.applyAddressBookFromRust(snapshot)
        }
    }

    func diagnosticsChanged() {
        Task { @MainActor [weak appState] in
            appState?.objectWillChange.send()
        }
    }
}

@MainActor
extension AppState {
    /// Register with the Rust event bus. Called from `AppState.init()`.
    /// The returned handle is retained on `self`; dropping it stops the pump.
    func registerRustObserver() {
        // Already registered? Unregister first to avoid duplicate pumps.
        rustObserverHandle?.unregister()
        let observer = AppStateRustObserver(appState: self)
        rustObserver = observer
        Task { @MainActor in
            let handle = await registerAppStateObserver(observer: observer)
            self.rustObserverHandle = handle
        }
    }

    fileprivate func applyWalletsFromRust(_ wallets: [CoreImportedWallet]) {
        // Guard against redundant writes that would trigger walletsRevision
        // bumps and side-effect loops when Rust echoes our own mutation back.
        if wallets.count == self.wallets.count,
           zip(wallets, self.wallets).allSatisfy({ $0.id == $1.id && $0.name == $1.name }) {
            // Cheap identity check. Full structural compare is expensive; the
            // didSet side-effects are idempotent, so on ambiguity we let the
            // assignment through.
            self.wallets = wallets
            return
        }
        self.wallets = wallets
    }

    fileprivate func applyTransactionsFromRust(_ records: [CorePersistedTransactionRecord]) {
        let converted = records.compactMap(TransactionRecord.init(snapshot:))
        // Avoid thrashing when Rust echoes our own write.
        if converted.count == self.transactions.count,
           zip(converted, self.transactions).allSatisfy({ $0.id == $1.id }) {
            return
        }
        self.transactions = converted
    }

    fileprivate func applyAddressBookFromRust(_ entries: [CorePersistedAddressBookEntry]) {
        let converted = entries.compactMap(AddressBookEntry.init(snapshot:))
        if converted.count == self.addressBook.count,
           zip(converted, self.addressBook).allSatisfy({ $0.id == $1.id }) {
            return
        }
        self.addressBook = converted
    }
}
