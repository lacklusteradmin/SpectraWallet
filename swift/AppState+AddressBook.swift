import Foundation

@MainActor
extension AppState {
    func addressBookAddressValidationMessage(for address: String, chainName: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmpty = trimmed.isEmpty
        let isValid = !isEmpty && isValidAddress(trimmed, for: chainName)
        if !isEmpty, isValid { return AppLocalization.format("Valid %@ address.", chainName) }

        // The sentence a chain has of its own, looked up by id. These are
        // content, so they live in the locale files keyed by chain id; a chain
        // with none falls back to a template built from the catalog's
        // `address_prefix_hint`.
        guard let chain = Chain(displayName: chainName) else {
            return AppLocalization.format("Enter a valid %@ address.", chainName)
        }
        let key = "addressHint.\(chain.id).\(isEmpty ? "empty" : "invalid")"
        let localized = AppLocalization.string(key)
        if localized != key { return localized }

        let hint = chain.addressPrefixHint
        guard !hint.isEmpty else {
            return isEmpty
                ? localizedStoreString("Enter an address for the selected chain.")
                : AppLocalization.format("Enter a valid %@ address.", chainName)
        }
        return isEmpty
            ? AppLocalization.format("%@ addresses look like %@", chainName, hint)
            : AppLocalization.format("Enter a valid %@ address — they look like %@", chainName, hint)
    }
    func isDuplicateAddressBookAddress(_ address: String, chainName: String, excluding entryID: String? = nil) -> Bool {
        let normalized = normalizedAddress(address, for: chainName)
        guard !normalized.isEmpty else { return false }
        return addressBook.contains {
            $0.id != entryID && $0.chainName == chainName && $0.address.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }
    func canSaveAddressBookEntry(name: String, address: String, chainName: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && isValidAddress(address, for: chainName)
            && !isDuplicateAddressBookAddress(address, chainName: chainName)
    }
    /// Save a recipient. Core trims, normalizes the address, validates it and
    /// rejects duplicates; the UI does not pre-check beyond disabling the
    /// button via `canSaveAddressBookEntry`.
    func addAddressBookEntry(name: String, address: String, chainName: String, note: String = "") {
        enqueueAddressBookCommand(.addAddressBookEntry(
            id: UUID().uuidString, name: name, chainName: chainName,
            address: address, note: note))
    }
    func canSaveLastSentRecipientToAddressBook() -> Bool {
        guard let tx = lastSentTransaction, tx.kind == .send else { return false }
        return canSaveAddressBookEntry(name: AppLocalization.format("%@ Recipient", tx.symbol), address: tx.address, chainName: tx.chainName)
    }
    func saveLastSentRecipientToAddressBook() {
        guard let tx = lastSentTransaction, tx.kind == .send else { return }
        addAddressBookEntry(
            name: AppLocalization.format("%@ Recipient", tx.symbol), address: tx.address, chainName: tx.chainName,
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
        guard let transition = try? await WalletServiceBridge.shared.applyStateCommand(command)
        else { return }
        // A read begun while the write was pending may hold the old contacts.
        // Invalidate it when the committed command returns, not when it starts.
        applyCoreState(transition.state, epoch: beginCoreStateRead())
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
        return addressBook.filter { $0.chainName == selectedSendCoin.chainName }
    }
}
