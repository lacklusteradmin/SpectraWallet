import SwiftUI
struct AddWalletEntryView: View {
    let store: AppState
    @State private var isShowingFundsFinder = false
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                SpectraRowGroup(data: entries) { entry in
                    Button(action: entry.action) { entryRow(entry) }.buttonStyle(.plain)
                }.spectraScreenPadding()
            }
        }
        .navigationTitle(AppLocalization.string("Add Wallet")).navigationBarTitleDisplayMode(.inline)
        .navigationDestination(
            isPresented: Binding(
                get: { store.walletImport.isPresented && store.walletImport.editingWalletId == nil },
                set: { isPresented in
                    if !isPresented { store.walletImport.isPresented = false }
                }
            )
        ) {
            SetupView(store: store, draft: store.walletImport.draft)
        }
        .navigationDestination(
            isPresented: $isShowingFundsFinder
        ) {
            FundsFinderView(bridge: store.bridge)
        }
    }
    private struct Entry: Identifiable {
        let title: String
        let subtitle: String
        let icon: String
        let action: @MainActor () -> Void
        var id: String { title }
    }
    private var entries: [Entry] {
        [
            Entry(
                title: AppLocalization.string("Create New Wallet"),
                subtitle: AppLocalization.string("Generate a new seed phrase and set up your wallet."),
                icon: "plus.circle.fill"
            ) { store.beginWalletCreation() },
            Entry(
                title: AppLocalization.string("Import Wallet"),
                subtitle: AppLocalization.string("Use an existing seed phrase or private key."),
                icon: "arrow.down.circle.fill"
            ) { store.beginWalletImport() },
            Entry(
                title: AppLocalization.string("Watch Addresses"),
                subtitle: AppLocalization.string("Track public addresses without adding private keys."),
                icon: "eye.circle.fill"
            ) { store.beginWatchAddressesImport() },
            Entry(
                title: AppLocalization.string("Find Lost Funds"),
                subtitle: AppLocalization.string("Scan 150+ derivation paths to locate hidden balances from any wallet app."),
                icon: "magnifyingglass.circle.fill"
            ) { isShowingFundsFinder = true },
        ]
    }
    private func entryRow(_ entry: Entry) -> some View {
        HStack(spacing: SpectraLayout.Space.m) {
            Image(systemName: entry.icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(.tint).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                Text(entry.title).font(.headline).foregroundStyle(Color.primary)
                Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: SpectraLayout.Space.s)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }.spectraRowPadding()
    }
}
