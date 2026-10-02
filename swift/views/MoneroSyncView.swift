import SwiftUI

/// A cancellable projection of core's durable scan. No keys or scan state live in Swift.
struct MoneroSyncView: View {
    let store: AppState
    let walletId: String
    @State private var status: MoneroSyncStatus?
    @State private var password = ""
    @State private var restoreHeight = ""
    @State private var running = false
    @State private var error: String?

    var body: some View {
        Group {
            if let status {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                    Text(AppLocalization.string("Local Monero Wallet")).font(.headline)
                    Text(AppLocalization.string("Scanning and signing happen on this device. Keys stay on this device."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "\(status.scannedHeight) / \(status.targetHeight)")
                        .monospacedDigit()
                    if running {
                        ProgressView()
                        Button(AppLocalization.string("Cancel")) { running = false }
                            .buttonStyle(.glass)
                    } else {
                        if store.wallet(for: walletId)?.signing.requiresPassword ?? true {
                            SecureField(AppLocalization.string("Wallet Password"), text: $password)
                                .spectraInputFieldStyle()
                        }
                        if status.targetHeight == 0 {
                            TextField(AppLocalization.string("Restore height (default 0)"), text: $restoreHeight)
                                .keyboardType(.numberPad).spectraInputFieldStyle()
                            Text(AppLocalization.string("Use a height before your first receipt. A later height can miss funds."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button(AppLocalization.string("Sync Local Wallet")) { running = true }
                            .buttonStyle(.glassProminent)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                .padding(SpectraLayout.cardPadding)
                .spectraCardFill()
            }
        }
        .task(id: walletId) {
            do { status = try await store.moneroSyncStatus(walletId: walletId) }
            catch { self.error = userErrorMessage(error) }
        }
        .task(id: running) {
            guard running else { return }
            defer { password = ""; running = false }
            var height: UInt64?
            if status?.targetHeight == 0 && !restoreHeight.isEmpty {
                guard let parsed = UInt64(restoreHeight) else {
                    error = AppLocalization.string("Invalid restore height")
                    return
                }
                height = parsed
            }
            error = await store.syncMoneroWallet(
                walletId: walletId, password: password.isEmpty ? nil : password, restoreHeight: height
            ) { status = $0 }
        }
        .onDisappear { password = ""; running = false }
    }
}
