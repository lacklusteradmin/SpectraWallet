// MARK: - Wallet/transactions/address-book mutation helpers
//
// Swift's `@Published` arrays are the canonical store. These helpers exist
// only to centralise mutation patterns (replace, append, upsert, remove) and
// keep call sites readable. There is no Rust round-trip — direct assignment
// to `self.wallets`, `self.transactions`, `self.addressBook` is fine, but
// going through these helpers preserves the existing call-site style.

import Foundation

@MainActor
extension AppState {
    // ── Wallets ────────────────────────────────────────────────────────
    func setWallets(_ new: [ImportedWallet]) {
        self.wallets = new
    }

    func appendWallet(_ wallet: ImportedWallet) {
        self.wallets.append(wallet)
    }

    func appendWallets(_ new: [ImportedWallet]) {
        self.wallets.append(contentsOf: new)
    }

    /// Insert or replace by `id`. Preserves position when updating.
    func upsertWallet(_ wallet: ImportedWallet) {
        if let idx = self.wallets.firstIndex(where: { $0.id == wallet.id }) {
            self.wallets[idx] = wallet
        } else {
            self.wallets.append(wallet)
        }
    }

    func removeWallet(id: String) {
        self.wallets.removeAll { $0.id == id }
    }

    func removeWallets(where predicate: (ImportedWallet) -> Bool) {
        self.wallets.removeAll(where: predicate)
    }

    // ── Transactions ──────────────────────────────────────────────────
    func setTransactions(_ new: [TransactionRecord]) {
        self.transactions = new
    }

    func prependTransaction(_ transaction: TransactionRecord) {
        self.transactions.insert(transaction, at: 0)
    }

    func removeTransactions(forWalletID walletID: String) {
        self.transactions.removeAll { $0.walletID == walletID }
    }

    func mapTransactions(_ transform: (TransactionRecord) -> TransactionRecord) {
        self.transactions = self.transactions.map(transform)
    }

    // ── Address book ─────────────────────────────────────────────────
    func setAddressBook(_ new: [AddressBookEntry]) {
        self.addressBook = new
    }

    func prependAddressBookEntry(_ entry: AddressBookEntry) {
        self.addressBook.insert(entry, at: 0)
    }

    func removeAddressBookEntry(byID uuid: UUID) {
        self.addressBook.removeAll { $0.id == uuid }
    }
}
