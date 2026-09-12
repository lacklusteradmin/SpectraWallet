import Foundation
import SwiftUI

// MARK: - Funds Finder state types

struct FundsFinderHit: Identifiable {
    let id = UUID()
    let candidate: FundsFinderCandidate
    let balanceDisplay: String
    let smallestUnit: String
}

// MARK: - AppState funds-finder properties and methods

@MainActor
extension AppState {
    // ── Published state (observed by FundsFinderView) ──────────────────────

    var isFundsFinderScanning: Bool {
        get { _isFundsFinderScanning }
        set { _isFundsFinderScanning = newValue }
    }
    var fundsFinderProgress: Double {
        get { _fundsFinderProgress }
        set { _fundsFinderProgress = newValue }
    }
    var fundsFinderHits: [FundsFinderHit] {
        get { _fundsFinderHits }
        set { _fundsFinderHits = newValue }
    }
    var fundsFinderScanError: String? {
        get { _fundsFinderScanError }
        set { _fundsFinderScanError = newValue }
    }
    var fundsFinderCheckedCount: Int {
        get { _fundsFinderCheckedCount }
        set { _fundsFinderCheckedCount = newValue }
    }
    var fundsFinderTotalCount: Int {
        get { _fundsFinderTotalCount }
        set { _fundsFinderTotalCount = newValue }
    }

    // ── Scan ───────────────────────────────────────────────────────────────

    func startFundsFinderScan(seedPhrase: String, passphrase: String?) {
        guard !isFundsFinderScanning else { return }
        isFundsFinderScanning = true
        fundsFinderProgress = 0
        fundsFinderHits = []
        fundsFinderCheckedCount = 0
        fundsFinderTotalCount = 0
        fundsFinderScanError = nil

        _fundsFinderScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let request = FundsFinderRequest(
                    seedPhrase: seedPhrase,
                    passphrase: passphrase?.nonEmpty
                )
                let scan = try WalletServiceBridge.shared.beginFundsScan(request: request)
                repeat {
                    let progress = await scan.nextBatch()
                    guard !Task.isCancelled else { return }
                    self.fundsFinderTotalCount = Int(progress.total)
                    self.fundsFinderCheckedCount = Int(progress.checked)
                    self.fundsFinderProgress = progress.total == 0 ? 1 : Double(progress.checked) / Double(progress.total)
                    for read in progress.reads {
                        if let error = read.error { self.fundsFinderScanError = error }
                        if read.funded, let balance = read.balance {
                            self.fundsFinderHits.append(FundsFinderHit(candidate: read.candidate, balanceDisplay: balance.amountDisplay, smallestUnit: balance.smallestUnit))
                        }
                    }
                    if progress.complete { break }
                } while !Task.isCancelled
            } catch {
                if !Task.isCancelled {
                    self.fundsFinderScanError = error.localizedDescription
                }
            }
            self.isFundsFinderScanning = false
        }
    }

    func cancelFundsFinderScan() {
        _fundsFinderScanTask?.cancel()
        _fundsFinderScanTask = nil
        isFundsFinderScanning = false
    }

    func resetFundsFinder() {
        cancelFundsFinderScan()
        fundsFinderProgress = 0
        fundsFinderHits = []
        fundsFinderCheckedCount = 0
        fundsFinderTotalCount = 0
        fundsFinderScanError = nil
    }

}

// MARK: - Backing storage (AppState must declare these vars)

// These @ObservationIgnored-backed vars live in AppState+FundsFinder because
// they drive the FundsFinder UI exclusively. Each is a plain stored property
// synthesised as a computed pair (get/set to the backing var) in the extension
// above, keeping the main AppState.swift clean.
//
// NOTE: Swift @Observable requires that the backing vars are declared on the
// main AppState class, not in an extension. They are declared in AppState.swift
// (see the "Funds Finder backing vars" section). This extension only exposes
// the API surface and scan logic.

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
