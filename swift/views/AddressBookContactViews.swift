import Foundation
import SwiftUI
import UIKit

/// Every mainnet, because core validates every mainnet, as the rows the shared
/// chain picker draws.
@MainActor private let addressBookChainDescriptors: [SetupChainSelectionDescriptor] =
    Chain.mainnets.compactMap(\.entry).compactMap { chain in
        guard let category = SetupChainCategory(chain: chain) else { return nil }
        return SetupChainSelectionDescriptor(
            id: chain.id, title: chain.name, symbol: chain.gasTokenSymbol,
            chainName: chain.name, color: chain.color.color, category: category
        )
    }

/// Adding a recipient, on its own page behind the address book's `+`.
struct NewAddressBookContactView: View {
    @Bindable var store: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var chainName: String = Chain.mainnets.first?.displayName ?? ""
    @State private var address: String = ""
    @State private var note: String = ""
    @State private var isChoosingChain = false
    @State private var chainSearchText: String = ""

    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        store.canSaveAddressBookEntry(name: name, address: address, chainName: chainName)
    }

    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    spectraPageHeader(
                        title: "New Contact",
                        subtitle: "Name a recipient and save an address you send to often.",
                        systemImage: "person.crop.circle.badge.plus"
                    )
                    contactCard
                    destinationCard
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SpectraBottomActionBar {
                Button {
                    spectraNotificationHaptic(.success)
                    store.addAddressBookEntry(name: name, address: address, chainName: chainName, note: note)
                    dismiss()
                } label: {
                    Label(AppLocalization.string("Save Contact"), systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(.glassProminent)
                .spectraPressable()
                .disabled(!canSave)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isChoosingChain) {
            AllChainsSelectionView(
                chainSearchText: $chainSearchText,
                descriptors: addressBookChainDescriptors,
                selectedChainNames: [chainName],
                toggleSelection: { picked in
                    chainName = picked
                    isChoosingChain = false
                },
                clearAllSelections: nil
            )
        }
    }

    private var contactCard: some View {
        spectraDetailCard(title: "Contact") {
            TextField(AppLocalization.string("Name"), text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(14)
                .spectraInputFieldStyle()
                .foregroundStyle(Color.primary)

            TextField(AppLocalization.string("Note (Optional)"), text: $note)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .spectraInputFieldStyle()
                .foregroundStyle(Color.primary)
        }
    }

    private var destinationCard: some View {
        spectraDetailCard(title: "Saved Address") {
            chainRow

            // `axis: .vertical` keeps the field's placeholder — the chain's own
            // format hint — while letting a 42-character address wrap instead
            // of scrolling out of sight to the left.
            TextField(addressPrompt, text: $address, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
                .lineLimit(1...4)
                .padding(14)
                .spectraInputFieldStyle()
                .foregroundStyle(Color.primary)

            // Only once there is something to judge. The same sentence used to
            // sit here permanently, two lines of instructions dressed as a
            // verdict on an empty field.
            if !trimmedAddress.isEmpty {
                Text(addressValidationMessage)
                    .font(.caption)
                    .foregroundStyle(addressValidationColor)
            }
        }
    }

    private var chainRow: some View {
        let badge = Coin.nativeChainBadge(chainName: chainName) ?? (nil, Color.mint)

        return Button {
            spectraHaptic(.light)
            isChoosingChain = true
        } label: {
            HStack(spacing: 12) {
                CoinBadge(
                    artworkName: badge.artworkName,
                    fallbackText: chainName,
                    color: badge.color,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Chain"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(chainName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.chip)
        }
        .buttonStyle(.plain)
    }

    /// A terse example of what an address on this chain looks like.
    private var addressPrompt: String {
        Chain(displayName: chainName)?.addressPrefixHint ?? AppLocalization.string("Address")
    }

    private var addressValidationMessage: String {
        if store.isDuplicateAddressBookAddress(address, chainName: chainName) {
            return AppLocalization.format("This %@ address is already saved.", chainName)
        }
        return store.addressBookAddressValidationMessage(for: address, chainName: chainName)
    }

    private var addressValidationColor: Color {
        if store.isDuplicateAddressBookAddress(address, chainName: chainName) { return .orange }
        return canSave ? .green : .secondary
    }
}

/// One saved recipient: what it is, and the two things that can be done to it.
///
/// The label is all core lets a contact change, so renaming used to be a sheet
/// of its own reachable only by swiping the row. Deleting was the other swipe
/// action, and neither was visible on the row.
struct AddressBookContactView: View {
    @Bindable var store: AppState
    let entry: AddressBookEntry
    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String = ""
    @State private var isConfirmingDelete = false
    @State private var didCopy = false

    /// The stored contact, so a rename is reflected here rather than leaving
    /// the pushed page showing the name it was opened with.
    private var contact: AddressBookEntry {
        store.addressBook.first { $0.id == entry.id } ?? entry
    }

    private var canRename: Bool {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != contact.name
    }

    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    contactHero
                    labelCard
                    deleteButton
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(AppLocalization.string("Contact"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalization.string("Save")) {
                    store.renameAddressBookEntry(id: contact.id, to: editedName)
                    spectraHaptic(.light)
                }
                .disabled(!canRename)
            }
        }
        .onAppear { editedName = contact.name }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    private var contactHero: some View {
        let badge = Coin.nativeChainBadge(chainName: contact.chainName) ?? (nil, Color.mint)

        return VStack(spacing: 16) {
            CoinBadge(
                artworkName: badge.artworkName,
                fallbackText: contact.chainName,
                color: badge.color,
                size: 56
            )

            VStack(spacing: 4) {
                Text(contact.name)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(contact.subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Whole and wrapped here, where there is room for it: the list row
            // shows the same address elided.
            Text(contact.address)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Button {
                UIPasteboard.general.string = contact.address
                didCopy = true
                spectraHaptic(.light)
            } label: {
                Label(
                    AppLocalization.string(didCopy ? "Copied" : "Copy"),
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .spectraPressable()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .spectraElevatedFill()
    }

    private var labelCard: some View {
        spectraDetailCard(title: "Label") {
            Text(
                AppLocalization.string(
                    "You can update the label for this saved address. The chain, address, and note stay fixed.")
            )
            .spectraHintText()

            TextField(AppLocalization.string("Name"), text: $editedName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(14)
                .spectraInputFieldStyle()
                .foregroundStyle(Color.primary)
        }
    }

    /// The dialog hangs off the button rather than the page, so the popover it
    /// becomes points at what it is asking about instead of at the title bar.
    private var deleteButton: some View {
        Button(role: .destructive) {
            spectraHaptic(.light)
            isConfirmingDelete = true
        } label: {
            Label(AppLocalization.string("Delete Contact"), systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.glass)
        .tint(.red)
        .spectraPressable()
        .confirmationDialog(
            AppLocalization.string("Delete Contact"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Delete"), role: .destructive) {
                spectraHaptic(.medium)
                store.removeAddressBookEntry(id: contact.id)
                dismiss()
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) {}
        }
    }
}
