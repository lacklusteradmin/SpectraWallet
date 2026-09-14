// Conversions from the Swift view models back into the core records, used by
// the bridge tests to seed state through the same commands the app issues.
//
// They live in the test target because nothing in the app converts in this
// direction: the app renders core's records, and core builds its own. Swift has
// no `#[cfg(test)]`, so the target boundary is the gate.
import Foundation

@testable import Spectra

extension WalletView {
    /// The authoritative model this view model was rendered from.
    ///
    /// `isWatchOnly` is a Keychain fact the record cannot carry, so the caller
    /// supplies it — see `WalletState` in `core/src/store/state.rs`.
    func walletState(isWatchOnly: Bool) -> WalletState {
        coreWalletState(wallet: self, isWatchOnly: isWatchOnly)
    }
}

extension TransactionRecord {
    var persistedSnapshot: CorePersistedTransactionRecord {
        CorePersistedTransactionRecord(
            deploymentId: deploymentID,
            id: id.uuidString,
            walletId: walletID,
            kind: kind,
            status: status,
            walletName: walletName,
            assetDisplayName: assetDisplayName,
            symbol: symbol,
            chainName: chainName,
            amount: amount,
            address: address,
            transactionHash: transactionHash,
            ethereumNonce: ethereumNonce.map { Int64($0) },
            receiptBlockNumber: receiptBlockNumber.map { Int64($0) },
            receiptGasUsed: receiptGasUsed,
            receiptEffectiveGasPriceGwei: receiptEffectiveGasPriceGwei,
            receiptNetworkFeeEth: receiptNetworkFeeEth,
            feePriorityRaw: feePriorityRaw,
            feeRateDescription: feeRateDescription,
            confirmationCount: confirmationCount.map { Int64($0) },
            dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge,
            dogecoinEstimatedFeeRateDogePerKb: dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: usedChangeOutput,
            sourceDerivationPath: sourceDerivationPath,
            changeDerivationPath: changeDerivationPath,
            sourceAddress: sourceAddress,
            changeAddress: changeAddress,
            signedTransactionPayload: signedTransactionPayload,
            signedTransactionPayloadFormat: signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transactionHistorySource,
            createdAt: createdAt.timeIntervalSinceReferenceDate
        )
    }
}
