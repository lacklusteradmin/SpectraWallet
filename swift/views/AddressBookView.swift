import Foundation
import SwiftUI
import UIKit

/// Saved recipients, with adding a contact as a toolbar action.
struct AddressBookView: View {
    @Bindable var store: AppState
    @State private var isAddingContact = false
    @State private var openContact: AddressBookEntry?

    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    spectraPageHeader(
                        title: "Saved Addresses",
                        subtitle: "Pick a saved recipient during a send instead of pasting an address.",
                        systemImage: "person.crop.circle"
                    )

                    rejectionNotice

                    if store.addressBook.isEmpty {
                        SpectraEmptyStateCard(
                            title: "No saved addresses yet",
                            message: "Save frequent recipients here so future sends are faster.",
                            systemImage: "person.crop.circle.badge.plus",
                            actionTitle: "New Contact",
                            actionSystemImage: "plus",
                            action: {
                                spectraHaptic(.light)
                                isAddingContact = true
                            }
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.addressBook) { entry in
                                AddressBookContactCard(entry: entry) { openContact = entry }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(AppLocalization.string("Address Book"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    spectraHaptic(.light)
                    isAddingContact = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppLocalization.string("New Contact"))
            }
        }
        .navigationDestination(isPresented: $isAddingContact) {
            NewAddressBookContactView(store: store)
        }
        .navigationDestination(item: $openContact) { entry in
            AddressBookContactView(store: store, entry: entry)
        }
    }

    /// Core's reason for refusing a contact. `addressBookError` has been set
    /// since address-book commands moved to core and no screen showed it, so a
    /// refused save was indistinguishable from a save that did nothing.
    @ViewBuilder
    private var rejectionNotice: some View {
        if let addressBookError = store.addressBookError {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                Text(verbatim: addressBookError)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    store.addressBookError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("Close"))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(Color.red.opacity(0.12)),
                in: .rect(cornerRadius: SpectraLayout.Radius.compact)
            )
        }
    }
}

/// One saved recipient. The row opens the contact; copy is its own button.
private struct AddressBookContactCard: View {
    let entry: AddressBookEntry
    let onOpen: () -> Void
    @State private var didCopy = false

    var body: some View {
        let badge = Coin.nativeChainBadge(chainName: entry.chainName) ?? (nil, Color.mint)

        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    CoinBadge(
                        artworkName: badge.artworkName,
                        fallbackText: entry.chainName,
                        color: badge.color,
                        size: 42
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Text(entry.subtitleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        // One line, elided in the middle: an address is
                        // recognised by both ends, and wrapping it to two
                        // monospaced lines made it, rather than the name, the
                        // largest thing in the row.
                        Text(entry.address)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                UIPasteboard.general.string = entry.address
                didCopy = true
                spectraHaptic(.light)
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(AppLocalization.string(didCopy ? "Copied" : "Copy"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.compact)
        // The row said "Copied" for the rest of the screen's life: the state
        // was one `copiedEntryID` on the page and nothing ever cleared it.
        // `.task(id:)` cancels with the row, so a card scrolled away mid-timer
        // does not come back still claiming it.
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
