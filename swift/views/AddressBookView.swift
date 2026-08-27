import Foundation
import SwiftUI
import UIKit
struct AddressBookView: View {
    let store: AppState
    @State private var contactName: String = ""
    @State private var selectedChainName: String = "Bitcoin"
    @State private var address: String = ""
    @State private var note: String = ""
    @State private var formMessage: String?
    @State private var editingEntry: AddressBookEntry?
    @State private var editedName: String = ""
    @State private var copiedEntryID: String?
    /// Every mainnet, because core validates every mainnet.
    private var supportedChains: [String] { Chain.mainnets.map(\.displayName) }
    /// A terse format example, for the chains that have one.
    ///
    /// A terse example of what an address on this chain looks like.
    ///
    /// A fifteen-arm switch stood here, one arm of it naming nine EVM chains.
    /// It is a fact about the chain, so it is a catalog column now — which
    /// also means the EVM family gets it from `is_evm` rather than from a list
    /// that had Base, Polygon, Linea and the rest missing.
    private var addressPrompt: String {
        Chain(displayName: selectedChainName)?.addressPrefixHint ?? ""
    }
    private var addressValidationMessage: String {
        if store.isDuplicateAddressBookAddress(address, chainName: selectedChainName) {
            return AppLocalization.format("This %@ address is already saved.", selectedChainName)
        }
        return store.addressBookAddressValidationMessage(for: address, chainName: selectedChainName)
    }
    private var addressValidationColor: Color {
        if store.isDuplicateAddressBookAddress(address, chainName: selectedChainName) { return .orange }
        return store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) ? .green : .secondary
    }
    private var canRenameSelectedEntry: Bool {
        guard let editingEntry else { return false }
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedName != editingEntry.name
    }
    var body: some View {
        Form {
            Section(AppLocalization.string("New Contact")) {
                TextField(AppLocalization.string("Name"), text: $contactName).textInputAutocapitalization(.words).autocorrectionDisabled()
                Picker(AppLocalization.string("Chain"), selection: $selectedChainName) {
                    ForEach(supportedChains, id: \.self) { chainName in Text(chainName).tag(chainName) }
                }
                TextField(addressPrompt, text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(addressValidationMessage).font(.caption).foregroundStyle(addressValidationColor)
                TextField(AppLocalization.string("Note (Optional)"), text: $note).textInputAutocapitalization(.sentences)
                if let formMessage {
                    Text(formMessage).font(.caption).foregroundStyle(
                        store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName)
                            ? Color.secondary : Color.red)
                }
                Button(AppLocalization.string("Save Contact")) {
                    saveContact()
                }.spectraPressable()
                    .disabled(!store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName))
            }
            Section(AppLocalization.string("Saved Addresses")) {
                if store.addressBook.isEmpty {
                    SpectraEmptyStateCard(
                        title: "No saved addresses yet",
                        message: "Save frequent recipients here so future sends are faster.",
                        systemImage: "person.crop.circle.badge.plus"
                    )
                } else {
                    ForEach(store.addressBook) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.headline)
                                    Text(entry.subtitleText).spectraHintText()
                                    Text(entry.address).font(.caption.monospaced()).textSelection(.enabled)
                                }
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = entry.address
                                    copiedEntryID = entry.id
                                    spectraHaptic(.light)
                                } label: {
                                    Label(
                                        copiedEntryID == entry.id ? AppLocalization.string("Copied") : AppLocalization.string("Copy"),
                                        systemImage: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc"
                                    ).font(.caption.weight(.semibold))
                                }.buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 4).swipeActions {
                            Button(AppLocalization.string("Edit")) {
                                spectraHaptic(.light)
                                editingEntry = entry
                                editedName = entry.name
                            }
                            Button(AppLocalization.string("Delete"), role: .destructive) {
                                spectraHaptic(.medium)
                                store.removeAddressBookEntry(id: entry.id)
                            }
                        }
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("Address Book")).sheet(item: $editingEntry) { entry in
            NavigationStack {
                Form {
                    Section {
                        Text(
                            AppLocalization.string(
                                "You can update the label for this saved address. The chain, address, and note stay fixed.")
                        ).spectraHintText()
                    }
                    Section(AppLocalization.string("Saved Address")) {
                        Text(entry.chainName)
                        Text(entry.address).font(.caption.monospaced()).textSelection(.enabled)
                        if !entry.note.isEmpty { Text(entry.note).spectraHintText() }
                    }
                    Section(AppLocalization.string("Label")) {
                        TextField(AppLocalization.string("Name"), text: $editedName).textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }.navigationTitle(AppLocalization.string("Edit Label")).toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(AppLocalization.string("Cancel")) {
                            editingEntry = nil
                            editedName = ""
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalization.string("Save")) {
                            store.renameAddressBookEntry(id: entry.id, to: editedName)
                            editingEntry = nil
                            editedName = ""
                        }.disabled(!canRenameSelectedEntry)
                    }
                }
            }
        }
    }
    private func saveContact() {
        guard store.canSaveAddressBookEntry(name: contactName, address: address, chainName: selectedChainName) else {
            spectraNotificationHaptic(.error)
            formMessage = AppLocalization.format("Enter a unique valid %@ address and a contact name.", selectedChainName)
            return
        }
        spectraNotificationHaptic(.success)
        store.addAddressBookEntry(name: contactName, address: address, chainName: selectedChainName, note: note)
        contactName = ""
        address = ""
        note = ""
        formMessage = AppLocalization.string("Address saved.")
    }
}
