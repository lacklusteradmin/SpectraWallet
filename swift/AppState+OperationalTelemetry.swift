import Foundation
import SwiftUI
@MainActor
extension AppState {
    func clearOperationalLogs() { diagnostics.clearOperationalLogs() }
    var networkSyncStatusText: String {
        let reachability = isNetworkReachable ? localizedStoreString("reachable") : localizedStoreString("offline")
        let constrained = isConstrainedNetwork ? localizedStoreString("constrained") : localizedStoreString("unconstrained")
        let expensive = isExpensiveNetwork ? localizedStoreString("expensive") : localizedStoreString("non-expensive")
        return AppLocalization.format(
            "Network: %@, %@, %@ • Auto refresh: %d min", reachability, constrained, expensive, preferences.automaticRefreshFrequencyMinutes
        )
    }
    func exportOperationalLogsText(events: [OperationalLogEvent]? = nil) -> String {
        diagnostics.exportOperationalLogsText(networkSyncStatusText: networkSyncStatusText, events: events)
    }
    func appendOperationalLog(
        _ level: OperationalLogEvent.Level, category: String, message: String, chainName: String? = nil, walletID: String? = nil,
        transactionHash: String? = nil, source: String? = nil, metadata: String? = nil
    ) {
        diagnostics.appendOperationalLog(
            level, category: category, message: message, chainName: chainName, walletID: walletID, transactionHash: transactionHash,
            source: source, metadata: metadata
        )
    }
    func appendChainOperationalEvent(
        _ level: ChainOperationalEvent.Level, chainName: String, message: String, transactionHash: String? = nil
    ) {
        // Core stamps the id and the time, applies the cap and persists.
        Task {
            try? await WalletServiceBridge.shared.appendChainOperationalEvent(
                chainName: chainName, level: level, message: message,
                transactionHash: transactionHash?.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let mappedLevel: OperationalLogEvent.Level
        switch level {
        case .info: mappedLevel = .info
        case .warning: mappedLevel = .warning
        case .error: mappedLevel = .error
        }
        appendOperationalLog(
            mappedLevel, category: "\(chainName) Broadcast", message: message, chainName: chainName, transactionHash: transactionHash
        )
    }
    func noteSendBroadcastQueued(for transaction: TransactionRecord) {
        appendChainOperationalEvent(
            .info, chainName: transaction.chainName, message: "\(transaction.symbol) send broadcast accepted.",
            transactionHash: transaction.transactionHash
        )
    }
    func noteSendBroadcastVerification(
        chainName: String, verificationStatus: SendBroadcastVerificationStatus, transactionHash: String?
    ) {
        switch verificationStatus {
        case .verified:
            appendChainOperationalEvent(
                .info, chainName: chainName, message: "Broadcast verified by provider.", transactionHash: transactionHash
            )
        case .deferred:
            appendChainOperationalEvent(
                .warning, chainName: chainName, message: "Broadcast accepted; verification deferred.", transactionHash: transactionHash
            )
        case .failed(let message):
            appendChainOperationalEvent(
                .warning, chainName: chainName, message: "Broadcast verification warning: \(message)", transactionHash: transactionHash
            )
        }
    }
    func noteSendBroadcastFailure(for chainName: String, message: String) {
        appendChainOperationalEvent(.error, chainName: chainName, message: "Send failed: \(message)")
    }
    func decoratePendingSendTransaction(_ transaction: TransactionRecord, holding: Coin, confirmationCount: Int? = 0) -> TransactionRecord {
        let previewDetails = sendPreviewDetails(for: holding)
        return TransactionRecord(
            id: transaction.id, walletID: transaction.walletID, kind: transaction.kind, status: transaction.status,
            walletName: transaction.walletName, assetName: transaction.assetName, symbol: transaction.symbol,
            chainName: transaction.chainName, amount: transaction.amount, address: transaction.address,
            transactionHash: transaction.transactionHash, ethereumNonce: transaction.ethereumNonce,
            receiptBlockNumber: transaction.receiptBlockNumber, receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: transaction.receiptNetworkFeeEth,
            feePriorityRaw: transaction.feePriorityRaw ?? feePriorityOption(for: holding.chainName).rawValue,
            feeRateDescription: transaction.feeRateDescription ?? previewDetails?.feeRateDescription,
            confirmationCount: transaction.confirmationCount ?? confirmationCount,
            dogecoinConfirmedNetworkFeeDoge: transaction.dogecoinConfirmedNetworkFeeDoge,
            dogecoinEstimatedFeeRateDogePerKb: transaction.dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: transaction.usedChangeOutput ?? previewDetails?.usesChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath, sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat, failureReason: transaction.failureReason,
            transactionHistorySource: transaction.transactionHistorySource, createdAt: transaction.createdAt
        )
    }
    func registerPendingSelfSendConfirmation(
        walletID: String, chainName: String, symbol: String, destinationAddress: String, amount: Double
    ) {
        pendingSelfSendConfirmation = PendingSelfSendConfirmation(
            walletID: walletID, chainName: chainName, symbol: symbol, destinationAddressLowercased: destinationAddress.lowercased(),
            amount: amount, createdAt: Date()
        )
    }
    func requiresSelfSendConfirmation(wallet: ImportedWallet, holding: Coin, destinationAddress: String, amount: Double) async -> Bool {
        let ownAddresses: [String]
        if holding.chainName == "Dogecoin" {
            ownAddresses = await knownUTXOAddresses(for: wallet, chainName: "Dogecoin")
        } else {
            ownAddresses = await knownOwnedAddresses(for: wallet.id)
        }
        let plan = rustSelfSendConfirmationPlan(
            walletID: wallet.id, chainName: holding.chainName, symbol: holding.symbol, destinationAddress: destinationAddress,
            amount: amount, ownedAddresses: ownAddresses
        )
        if plan.clearPendingConfirmation { pendingSelfSendConfirmation = nil }
        guard plan.requiresConfirmation else { return false }
        if plan.consumeExistingConfirmation {
            pendingSelfSendConfirmation = nil
            return false
        }
        registerPendingSelfSendConfirmation(
            walletID: wallet.id, chainName: holding.chainName, symbol: holding.symbol, destinationAddress: destinationAddress,
            amount: amount
        )
        sendError =
            "This \(holding.symbol) destination belongs to your wallet. Tap Send again within \(Int(Self.selfSendConfirmationWindowSeconds))s to confirm intentional self-send."
        if holding.chainName == "Dogecoin" {
            appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE self-send confirmation required.")
        }
        return true
    }
    private func rustSelfSendConfirmationPlan(
        walletID: String, chainName: String, symbol: String, destinationAddress: String, amount: Double, ownedAddresses: [String]
    ) -> SelfSendConfirmationPlan {
        coreSelfSendConfirmation(
            request: SelfSendConfirmationRequest(
                pendingConfirmation: pendingSelfSendConfirmation.map {
                    PendingSelfSendConfirmationInput(
                        walletId: $0.walletID, chainName: $0.chainName, symbol: $0.symbol,
                        destinationAddressLowercased: $0.destinationAddressLowercased, amount: $0.amount,
                        createdAtUnix: $0.createdAt.timeIntervalSince1970
                    )
                }, walletId: walletID, chainName: chainName, symbol: symbol, destinationAddress: destinationAddress, amount: amount,
                nowUnix: Date().timeIntervalSince1970, windowSeconds: Self.selfSendConfirmationWindowSeconds, ownedAddresses: ownedAddresses
            )
        )
    }
    func statusPollFailureMessage(for transaction: TransactionRecord) -> String {
        AppLocalization.format(
            "%@ transaction appears stuck and could not be confirmed after extended retries.", transaction.chainName
        )
    }
    // Core owns the confirmation-poll backoff table. These forward the poll
    // outcome and read back the schedule; nothing about it is cached here.

    func shouldPollTransactionStatus(for transaction: TransactionRecord) async -> Bool {
        let due = try? await WalletServiceBridge.shared.transactionsDueForStatusPoll(
            ids: [transaction.id.uuidString])
        // An unreachable core must not wedge polling off permanently.
        return due.map { !$0.isEmpty } ?? true
    }
    func markTransactionStatusPollSuccess(
        for transaction: TransactionRecord, resolvedStatus: TransactionStatus,
        confirmations: Int? = nil
    ) async {
        let outcome: StatusPollOutcome =
            switch resolvedStatus {
            case .confirmed: .confirmed(confirmations: confirmations.map { UInt32(max(0, $0)) })
            case .pending: .pending
            default: .unresolved
            }
        try? await WalletServiceBridge.shared.recordStatusPoll(
            id: transaction.id.uuidString, outcome: outcome)
    }
    func markTransactionStatusPollFailure(for transaction: TransactionRecord) async {
        try? await WalletServiceBridge.shared.recordStatusPoll(
            id: transaction.id.uuidString, outcome: .failed)
    }
    /// Hand core one chain's resolved statuses; it stores the results and says
    /// what changed.
    ///
    /// Core computes its own stale failures and writes its own records, so what
    /// is left here is the two things this platform owns: the localized text of
    /// an operational event, and a notification.
    func applyResolvedPendingStatuses(
        chainName: String, resolutions: [UUID: PendingTransactionStatusResolution]
    ) async {
        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let inputs = resolutions.map { id, resolution in
            ResolvedPendingStatus(
                id: id.uuidString, status: resolution.status.rawValue,
                confirmations: resolution.confirmations.map { UInt32(max(0, $0)) },
                receiptBlockNumber: resolution.receiptBlockNumber.map(Int64.init),
                dogecoinNetworkFeeDoge: resolution.dogecoinNetworkFeeDoge)
        }
        let changes = (try? await WalletServiceBridge.shared.applyResolvedPendingStatuses(
            chainName: chainName, resolutions: inputs)) ?? []
        guard !changes.isEmpty else { return }
        if let stored = try? await WalletServiceBridge.shared.storedTransactions() {
            adoptTransactionsFromCore(stored.compactMap(TransactionRecord.init(snapshot:)))
        }

        for change in changes {
            guard let id = UUID(uuidString: change.id) else { continue }
            let transaction = transactions.first(where: { $0.id == id }) ?? oldByID[id]
            guard let transaction else { continue }
            if change.statusChanged {
                switch change.emitEventCode {
                case "confirmed":
                    appendChainOperationalEvent(
                        .info, chainName: change.chainName,
                        message: statusPollConfirmedMessage(for: transaction),
                        transactionHash: change.transactionHash)
                case "failed":
                    appendChainOperationalEvent(
                        .error, chainName: change.chainName,
                        message: statusPollFailedEventMessage(for: transaction),
                        transactionHash: change.transactionHash)
                default: break
                }
                if change.sendStatusNotification, let oldTransaction = oldByID[id],
                    let newStatus = TransactionStatus(rawValue: change.newStatus)
                {
                    sendTransactionStatusNotification(for: oldTransaction, newStatus: newStatus)
                }
            }
            if let confirmations = change.reachedFinalityConfirmations {
                appendChainOperationalEvent(
                    .info, chainName: change.chainName,
                    message: statusPollFinalityReachedMessage(
                        for: transaction, confirmations: Int(confirmations)),
                    transactionHash: change.transactionHash)
            }
        }
    }

    private func statusPollFailedEventMessage(for transaction: TransactionRecord) -> String {
        switch transaction.chainName {
        case "Dogecoin": return localizedStoreString("DOGE transaction marked failed after extended retries.")
        default: return transaction.localizedFailureReason ?? statusPollFailureMessage(for: transaction)
        }
    }

    private func statusPollConfirmedMessage(for transaction: TransactionRecord) -> String {
        switch transaction.chainName {
        case "Dogecoin": return localizedStoreString("DOGE transaction confirmed.")
        default: return "Transaction confirmed on-chain."
        }
    }

    private func statusPollFinalityReachedMessage(for transaction: TransactionRecord, confirmations: Int) -> String {
        switch transaction.chainName {
        case "Dogecoin":
            return AppLocalization.format("DOGE transaction reached finality (%d confirmations).", confirmations)
        default:
            return AppLocalization.format("Transaction reached finality (%d confirmations).", confirmations)
        }
    }
    func refreshPendingHistoryBackedTransactions(
        chainName: String, addressResolver: (ImportedWallet) -> String?,
        fetchStatuses: @escaping (String) async -> ([String: TransactionStatus], Bool)
    ) async {
        let trackedTransactions = transactions.filter { transaction in
            transaction.kind == .send
                && transaction.chainName == chainName
                && transaction.status == .pending
                && transaction.transactionHash != nil
        }
        guard !trackedTransactions.isEmpty else { return }
        let walletsByID = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        let groupedTransactions = Dictionary(grouping: trackedTransactions) { transaction in
            transaction.walletID.flatMap { walletsByID[$0] }.flatMap(addressResolver)
        }
        var resolvedStatuses: [UUID: PendingTransactionStatusResolution] = [:]
        for (address, group) in groupedTransactions {
            guard let address else { continue }
            let (statusByHash, hadError) = await fetchStatuses(address)
            if hadError {
                for transaction in group { await markTransactionStatusPollFailure(for: transaction) }
                continue
            }
            for transaction in group {
                guard await shouldPollTransactionStatus(for: transaction),
                    let transactionHash = transaction.transactionHash?.lowercased()
                else { continue }
                let resolvedStatus = statusByHash[transactionHash] ?? .pending
                await markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus, receiptBlockNumber: nil, confirmations: nil, dogecoinNetworkFeeDoge: nil
                )
            }
        }
        await applyResolvedPendingStatuses(chainName: chainName, resolutions: resolvedStatuses)
    }
    func addPriceAlert(for coin: Coin, targetPrice: Double, condition: PriceAlertCondition) {
        let normalizedTargetPrice = (targetPrice * 100).rounded() / 100
        let isDuplicate = priceAlerts.contains { alert in
            alert.holdingKey == coin.holdingKey
                && alert.condition == condition
                && abs(alert.targetPrice - normalizedTargetPrice) < 0.0001
        }
        guard !isDuplicate else { return }
        let alert = PriceAlertRule(
            holdingKey: coin.holdingKey, assetName: coin.name, symbol: coin.symbol, chainName: coin.chainName,
            targetPrice: normalizedTargetPrice, condition: condition
        )
        priceAlerts.insert(alert, at: 0)
        requestPriceAlertNotificationPermission()
    }
    func togglePriceAlertEnabled(id: String) {
        guard let index = priceAlerts.firstIndex(where: { $0.id == id }) else { return }
        priceAlerts[index].isEnabled.toggle()
        if !priceAlerts[index].isEnabled { priceAlerts[index].hasTriggered = false }
    }
    func removePriceAlert(id: String) {
        priceAlerts.removeAll { $0.id == id }
    }
}
