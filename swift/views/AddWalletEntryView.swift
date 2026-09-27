import SwiftUI
struct AddWalletEntryView: View {
    let store: AppState
    @State private var isShowingFundsFinder = false
    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: SpectraLayout.Space.m) {
                    actionCard(
                        title: AppLocalization.string("Create New Wallet"),
                        subtitle: AppLocalization.string("Generate a new seed phrase and set up your wallet."),
                        icon: "plus.circle.fill"
                    ) {
                        store.beginWalletCreation()
                    }
                    actionCard(
                        title: AppLocalization.string("Import Wallet"),
                        subtitle: AppLocalization.string("Use an existing seed phrase or private key."),
                        icon: "arrow.down.circle.fill"
                    ) {
                        store.beginWalletImport()
                    }
                    actionCard(
                        title: AppLocalization.string("Watch Addresses"),
                        subtitle: AppLocalization.string("Track public addresses without adding private keys."),
                        icon: "eye.circle.fill"
                    ) {
                        store.beginWatchAddressesImport()
                    }
                    actionCard(
                        title: AppLocalization.string("Find Lost Funds"),
                        subtitle: AppLocalization.string("Scan 150+ derivation paths to locate hidden balances from any wallet app."),
                        icon: "magnifyingglass.circle.fill"
                    ) {
                        isShowingFundsFinder = true
                    }
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
    private func actionCard(
        title: String, subtitle: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: SpectraLayout.Space.m) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(.tint).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
                    Text(title).font(.headline).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: SpectraLayout.Space.s)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary).padding(
                    .top, SpectraLayout.Space.xs)
            }.padding(SpectraLayout.Space.l).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).spectraBubbleFill().spectraCardFill()
    }
}
