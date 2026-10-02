import SwiftUI

/// A cancellable projection of core's durable scan. No keys or scan state live in Swift.
struct MoneroSyncView: View {
    let store: AppState
    let walletId: String
    @State private var vm = MoneroSyncViewModel()

    var body: some View {
        Group {
            if let status = vm.status {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
                    Text(AppLocalization.string("Local Monero Wallet")).font(.headline)
                    Text(AppLocalization.string("Scanning and signing happen on this device. Keys stay on this device."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "\(status.scannedHeight) / \(status.targetHeight)")
                        .monospacedDigit()
                    if vm.isRunning {
                        ProgressView()
                        Button(AppLocalization.string("Cancel")) { vm.cancel() }
                            .buttonStyle(.glass)
                    } else {
                        if store.wallet(for: walletId)?.signing.requiresPassword ?? true {
                            SecureField(AppLocalization.string("Wallet Password"), text: $vm.password)
                                .spectraInputFieldStyle()
                        }
                        if status.targetHeight == 0 {
                            TextField(AppLocalization.string("Restore height (default 0)"), text: $vm.restoreHeight)
                                .keyboardType(.numberPad).spectraInputFieldStyle()
                            Text(AppLocalization.string("Use a height before your first receipt. A later height can miss funds."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button(AppLocalization.string("Sync Local Wallet")) { vm.begin() }
                            .buttonStyle(.glassProminent)
                    }
                    if let error = vm.error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                .padding(SpectraLayout.cardPadding)
                .spectraCardFill()
            }
        }
        .task(id: walletId) {
            do {
                let status = try await store.moneroSyncStatus(walletId: walletId)
                guard !Task.isCancelled else { return }
                vm.status = status
            } catch {
                guard !Task.isCancelled else { return }
                vm.error = userErrorMessage(error)
            }
        }
        .task(id: vm.requestId) {
            guard let request = vm.requestId else { return }
            await vm.sync(request: request) { password, height, progress in
                await store.syncMoneroWallet(
                    walletId: walletId, password: password, restoreHeight: height, progress: progress)
            }
        }
        .onDisappear { vm.cancel() }
    }
}
