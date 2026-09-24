import Foundation

@MainActor
extension AppState {
    func addressBookAddressValidationMessage(for address: String, chain: Chain) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = trimmed.isEmpty
        if !isEmpty, isValidAddress(trimmed, on: chain) { return AppLocalization.format("Valid %@ address.", chain.displayName) }

        // The sentence a chain has of its own, looked up by id. These are
        // content, so they live in the locale files keyed by chain id; a chain
        // with none falls back to a template built from the catalog's
        // `address_prefix_hint`.
        let key = "addressHint.\(chain.id).\(isEmpty ? "empty" : "invalid")"
        let localized = AppLocalization.string(key)
        if localized != key { return localized }

        let hint = chain.addressPrefixHint
        guard !hint.isEmpty else {
            return isEmpty
                ? localizedStoreString("Enter an address for the selected chain.")
                : AppLocalization.format("Enter a valid %@ address.", chain.displayName)
        }
        return isEmpty
            ? AppLocalization.format("%@ addresses look like %@", chain.displayName, hint)
            : AppLocalization.format("Enter a valid %@ address — they look like %@", chain.displayName, hint)
    }
    /// Enables the save button. Core still validates the address and refuses a
    /// duplicate — whether two addresses are the same recipient is its rule.
    func canSaveAddressBookEntry(name: String, address: String, chain: Chain) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && isValidAddress(address, on: chain)
    }
    /// Save a recipient. Core trims, normalizes the address, validates it,
    /// rejects duplicates and assigns the entry's id.
    func addAddressBookEntry(name: String, address: String, chain: Chain, note: String = "") {
        enqueueAddressBookCommand(.addAddressBookEntry(
            name: name, chainId: chain.id, address: address, note: note))
    }
    func canSaveRecipientToAddressBook(_ tx: TransactionRecord) -> Bool {
        guard tx.kind == .send, let chain = tx.chain else { return false }
        return canSaveAddressBookEntry(name: AppLocalization.format("%@ Recipient", tx.symbol), address: tx.address, chain: chain)
    }
    func saveRecipientToAddressBook(_ tx: TransactionRecord) {
        guard tx.kind == .send, let chain = tx.chain else { return }
        addAddressBookEntry(
            name: AppLocalization.format("%@ Recipient", tx.symbol), address: tx.address, chain: chain,
            note: AppLocalization.string("Saved from recent send"))
    }
    func renameAddressBookEntry(id: String, to newName: String) {
        enqueueAddressBookCommand(.renameAddressBookEntry(id: id, name: newName))
    }
    func removeAddressBookEntry(id: String) {
        enqueueAddressBookCommand(.removeAddressBookEntry(id: id))
    }
    /// Preserve UI intent order across actor reentrancy. Core still owns every
    /// mutation; this task chain only orders the shell's forwarding and adoption.
    private func enqueueAddressBookCommand(_ command: StateCommand) {
        let previous = addressBookCommandTask
        addressBookCommandTask = Task { @MainActor [weak self] in
            await previous?.value
            await self?.sendAddressBookCommand(command)
        }
    }
    func awaitPendingAddressBookCommands() async {
        await addressBookCommandTask?.value
    }
    /// Send an address-book command and mirror the result.
    ///
    /// A refusal arrives as an `addressBookRejected` event carrying the reason
    /// core decided on; surfacing it beats silently doing nothing.
    private func sendAddressBookCommand(_ command: StateCommand) async {
        guard let transition = try? await self.bridge.applyStateCommand(command)
        else { return }
        // A read begun while the write was pending may hold the old contacts.
        // Invalidate it when the committed command returns, not when it starts.
        applyCoreState(transition.state)
        addressBookError = nil
        for case .addressBookRejected(let reason) in transition.events {
            addressBookError = addressBookRejectionMessage(reason)
        }
    }
    private func addressBookRejectionMessage(_ reason: AddressBookRejection) -> String {
        switch reason {
        case .emptyName: return localizedStoreString("Enter a name for this contact.")
        case .invalidAddress: return localizedStoreString("That address is not valid for this chain.")
        case .duplicateAddress: return localizedStoreString("That address is already saved.")
        }
    }
    var sendAddressBookEntries: [AddressBookEntry] {
        guard let selectedSendCoin else { return [] }
        return addressBook.filter { $0.chainId == selectedSendCoin.chainId }
    }
}
