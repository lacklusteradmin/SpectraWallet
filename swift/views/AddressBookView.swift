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
    private let supportedChains = [
        "Bitcoin", "Litecoin", "Dogecoin", "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid",
        "Tron", "Solana", "Cardano", "XRP Ledger", "Monero", "Sui", "Aptos", "TON", "Internet Computer", "NEAR", "Polkadot", "Stellar",
    ]
    private var addressPrompt: String {
        switch selectedChainName {
        case "Bitcoin": return "bc1q..."
        case "Litecoin": return "ltc1... / L... / M..."
        case "Dogecoin": return "D..."
        case "Ethereum", "Ethereum Classic", "Arbitrum", "Optimism", "BNB Chain", "Avalanche", "Hyperliquid", "Sui", "Aptos": return "0x..."
        case "Tron": return "T..."
        case "Solana": return "So111..."
        case "Cardano": return "addr1..."
        case "XRP Ledger": return "r..."
        case "Monero": return "4... / 8..."
        case "TON": return "UQ... / EQ..."
        case "Internet Computer": return "64-char account identifier"
        case "NEAR": return "alice.near / 64-char hex"
        case "Polkadot": return "1..."
        case "Stellar": return "G..."
        default: return ""
        }
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
