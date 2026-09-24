import SwiftUI

/// A cancellable projection of core's durable scan. No keys or scan state live in Swift.
struct MoneroSyncView: View {
    let store: AppState
    @State private var status: MoneroSyncStatus?
    @State private var password = ""
    @State private var restoreHeight = ""
    @State private var running = false
    @State private var error: String?

    var body: some View {
        Group {
            if let status {
                VStack(alignment: .leading, spacing: 12) {
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
                        if store.wallet(for: store.sendFlow.walletId)?.signing.requiresPassword ?? true {
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
                            .buttonStyle(.glassProminent).tint(.orange)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                .padding(SpectraLayout.cardPadding)
                .spectraCardFill()
            }
        }
        .task(id: store.sendFlow.walletId) {
            do { status = try await store.bridge.moneroSyncStatus(walletId: store.sendFlow.walletId) }
            catch { self.error = error.localizedDescription }
        }
        .task(id: running) {
            guard running else { return }
            defer { password = ""; running = false }
            guard await store.authenticateForSensitiveAction(.send, reason: AppLocalization.string("Authorize local wallet sync")) else { return }
            do {
                var height: UInt64?
                if status?.targetHeight == 0 && !restoreHeight.isEmpty {
                    guard let parsed = UInt64(restoreHeight) else {
                        error = AppLocalization.string("Invalid restore height")
                        return
                    }
                    height = parsed
                }
                let walletId = store.sendFlow.walletId
                let secret = password.isEmpty ? nil : password
                repeat {
                    try Task.checkCancellation()
                    status = try await store.bridge.syncMoneroWallet(walletId: walletId, password: secret, restoreHeight: height)
                    height = nil
                } while status?.complete != true
                error = nil
                await store.refreshBalances()
            } catch is CancellationError {
                // Completed batches are already persisted by core.
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { password = ""; running = false }
    }
}
