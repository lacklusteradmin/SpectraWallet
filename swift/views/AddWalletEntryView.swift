import SwiftUI
private func localizedAddWalletString(_ key: String) -> String {
    AppLocalization.string(key)
}
struct AddWalletEntryView: View {
    let store: AppState
    var body: some View {
        ZStack {
            SpectraBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    actionCard(
                        title: localizedAddWalletString("Create New Wallet"), subtitle: localizedAddWalletString("Generate a new seed phrase and set up your wallet."), icon: "plus.circle.fill", tint: Color.green
                    ) {
                        store.beginWalletCreation()
                    }
                    actionCard(
                        title: localizedAddWalletString("Import Wallet"), subtitle: localizedAddWalletString("Use an existing seed phrase or private key."), icon: "arrow.down.circle.fill", tint: Color.blue
                    ) {
                        store.beginWalletImport()
                    }
                    actionCard(
                        title: localizedAddWalletString("Watch Addresses"), subtitle: localizedAddWalletString("Track public addresses without adding private keys."), icon: "eye.circle.fill", tint: Color.orange
                    ) {
                        store.beginWatchAddressesImport()
                    }}.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            }}.navigationTitle(localizedAddWalletString("Add Wallet")).navigationBarTitleDisplayMode(.inline)
    }
    private func actionCard(
        title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(tint).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.primary.opacity(0.72)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Color.primary.opacity(0.38)).padding(.top, 4)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 22))
    }
}
