import Foundation
import SwiftUI

@MainActor
extension WalletStore {
    // MARK: - Operational Logs and Telemetry
    // Clears user-visible runtime telemetry logs in Settings.
    // This does not affect wallet data, balances, or transaction history.
    func clearOperationalLogs() {
        diagnostics.clearOperationalLogs()
    }

    var networkSyncStatusText: String {
        let reachability = isNetworkReachable ? localizedStoreString("reachable") : localizedStoreString("offline")
        let constrained = isConstrainedNetwork ? localizedStoreString("constrained") : localizedStoreString("unconstrained")
        let expensive = isExpensiveNetwork ? localizedStoreString("expensive") : localizedStoreString("non-expensive")
        return localizedStoreFormat(
            "Network: %@, %@, %@ • Auto refresh: %d min",
            reachability,
            constrained,
            expensive,
            automaticRefreshFrequencyMinutes
        )
    }

    // Produces a plain-text export suitable for support/debug sharing.
    // Output is chronologically ordered and includes level/category/source context.
    func exportOperationalLogsText(events: [OperationalLogEvent]? = nil) -> String {
        diagnostics.exportOperationalLogsText(
            networkSyncStatusText: networkSyncStatusText,
            events: events
        )
    }

    // Central structured log sink used by diagnostics page and export.
    func appendOperationalLog(
        _ level: OperationalLogEvent.Level,
        category: String,
        message: String,
        chainName: String? = nil,
        walletID: UUID? = nil,
        transactionHash: String? = nil,
        source: String? = nil,
        metadata: String? = nil
    ) {
        diagnostics.appendOperationalLog(
            level,
            category: category,
            message: message,
            chainName: chainName,
            walletID: walletID,
            transactionHash: transactionHash,
            source: source,
            metadata: metadata
        )
    }

    func appendChainOperationalEvent(
        _ level: ChainOperationalEvent.Level,
        chainName: String,
        message: String,
        transactionHash: String? = nil
    ) {
        let event = ChainOperationalEvent(
            id: UUID(),
            timestamp: Date(),
            chainName: chainName,
            level: level,
            message: message,
            transactionHash: transactionHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var events = chainOperationalEventsByChain[chainName] ?? []
        events.insert(event, at: 0)
        if events.count > 200 {
            events = Array(events.prefix(200))
        }
        chainOperationalEventsByChain[chainName] = events

        let mappedLevel: OperationalLogEvent.Level
        switch level {
        case .info:
            mappedLevel = .info
        case .warning:
            mappedLevel = .warning
        case .error:
            mappedLevel = .error
        }
        appendOperationalLog(
            mappedLevel,
            category: "\(chainName) Broadcast",
            message: message,
            chainName: chainName,
            transactionHash: transactionHash
        )
    }

    func loadChainOperationalEvents() -> [String: [ChainOperationalEvent]] {
        guard let data = UserDefaults.standard.data(forKey: Self.chainOperationalEventsDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: [ChainOperationalEvent]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func persistChainOperationalEvents() {
        guard let data = try? JSONEncoder().encode(chainOperationalEventsByChain) else { return }
        UserDefaults.standard.set(data, forKey: Self.chainOperationalEventsDefaultsKey)
    }

    func noteSendBroadcastQueued(for transaction: TransactionRecord) {
        appendChainOperationalEvent(
            .info,
            chainName: transaction.chainName,
            message: "\(transaction.symbol) send broadcast accepted.",
            transactionHash: transaction.transactionHash
        )
    }

    func noteSendBroadcastVerification(
        chainName: String,
        verificationStatus: SendBroadcastVerificationStatus,
        transactionHash: String?
    ) {
        switch verificationStatus {
        case .verified:
            appendChainOperationalEvent(
                .info,
                chainName: chainName,
                message: "Broadcast verified by provider.",
                transactionHash: transactionHash
            )
        case .deferred:
            appendChainOperationalEvent(
                .warning,
                chainName: chainName,
                message: "Broadcast accepted; verification deferred.",
                transactionHash: transactionHash
            )
        case .failed(let message):
            appendChainOperationalEvent(
                .warning,
                chainName: chainName,
                message: "Broadcast verification warning: \(message)",
                transactionHash: transactionHash
            )
        }
    }

    func noteSendBroadcastFailure(for chainName: String, message: String) {
        appendChainOperationalEvent(.error, chainName: chainName, message: "Send failed: \(message)")
    }

    func decoratePendingSendTransaction(
        _ transaction: TransactionRecord,
        holding: Coin,
        confirmationCount: Int? = 0
    ) -> TransactionRecord {
        let previewDetails = sendPreviewDetails(for: holding)
        return TransactionRecord(
            id: transaction.id,
            walletID: transaction.walletID,
            kind: transaction.kind,
            status: transaction.status,
            walletName: transaction.walletName,
            assetName: transaction.assetName,
            symbol: transaction.symbol,
            chainName: transaction.chainName,
            amount: transaction.amount,
            address: transaction.address,
            transactionHash: transaction.transactionHash,
            ethereumNonce: transaction.ethereumNonce,
            receiptBlockNumber: transaction.receiptBlockNumber,
            receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
            feePriorityRaw: transaction.feePriorityRaw ?? feePriorityOption(for: holding.chainName).rawValue,
            feeRateDescription: transaction.feeRateDescription ?? previewDetails?.feeRateDescription,
            confirmationCount: transaction.confirmationCount ?? confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: transaction.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: transaction.dogecoinConfirmations,
            dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: transaction.usedChangeOutput ?? previewDetails?.usesChangeOutput,
            dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat,
            failureReason: transaction.failureReason,
            transactionHistorySource: transaction.transactionHistorySource,
            createdAt: transaction.createdAt
        )
    }

    func registerPendingSelfSendConfirmation(
        walletID: UUID,
        chainName: String,
        symbol: String,
        destinationAddress: String,
        amount: Double
    ) {
        pendingSelfSendConfirmation = PendingSelfSendConfirmation(
            walletID: walletID,
            chainName: chainName,
            symbol: symbol,
            destinationAddressLowercased: destinationAddress.lowercased(),
            amount: amount,
            createdAt: Date()
        )
    }

    func consumePendingSelfSendConfirmation(
        walletID: UUID,
        chainName: String,
        symbol: String,
        destinationAddress: String,
        amount: Double
    ) -> Bool {
        guard let pendingSelfSendConfirmation else { return false }

        let isExpired = Date().timeIntervalSince(pendingSelfSendConfirmation.createdAt) > Self.selfSendConfirmationWindowSeconds
        guard !isExpired else {
            self.pendingSelfSendConfirmation = nil
            return false
        }

        let sameWallet = pendingSelfSendConfirmation.walletID == walletID
        let sameChain = pendingSelfSendConfirmation.chainName == chainName
        let sameSymbol = pendingSelfSendConfirmation.symbol == symbol
        let sameDestination = pendingSelfSendConfirmation.destinationAddressLowercased == destinationAddress.lowercased()
        let sameAmount = abs(pendingSelfSendConfirmation.amount - amount) < 0.00000001
        guard sameWallet, sameChain, sameSymbol, sameDestination, sameAmount else {
            self.pendingSelfSendConfirmation = nil
            return false
        }

        self.pendingSelfSendConfirmation = nil
        return true
    }

    func requiresSelfSendConfirmation(
        wallet: ImportedWallet,
        holding: Coin,
        destinationAddress: String,
        amount: Double
    ) -> Bool {
        let ownAddressSet: Set<String>
        if holding.chainName == "Dogecoin" {
            ownAddressSet = Set(knownDogecoinAddresses(for: wallet).map { $0.lowercased() })
        } else {
            ownAddressSet = Set(knownOwnedAddresses(for: wallet.id).map { $0.lowercased() })
        }
        guard ownAddressSet.contains(destinationAddress.lowercased()) else { return false }

        if consumePendingSelfSendConfirmation(
            walletID: wallet.id,
            chainName: holding.chainName,
            symbol: holding.symbol,
            destinationAddress: destinationAddress,
            amount: amount
        ) {
            return false
        }

        registerPendingSelfSendConfirmation(
            walletID: wallet.id,
            chainName: holding.chainName,
            symbol: holding.symbol,
            destinationAddress: destinationAddress,
            amount: amount
        )
        sendError = "This \(holding.symbol) destination belongs to your wallet. Tap Send again within \(Int(Self.selfSendConfirmationWindowSeconds))s to confirm intentional self-send."
        if holding.chainName == "Dogecoin" {
            appendChainOperationalEvent(.warning, chainName: "Dogecoin", message: "DOGE self-send confirmation required.")
        }
        return true
    }

    func finalityConfirmations(for chainName: String) -> Int {
        Self.standardFinalityConfirmations
    }

    func updatedTransaction(
        _ transaction: TransactionRecord,
        status: TransactionStatus,
        receiptBlockNumber: Int? = nil,
        failureReason: String? = nil,
        dogecoinConfirmations: Int? = nil,
        dogecoinConfirmedNetworkFeeDOGE: Double? = nil
    ) -> TransactionRecord {
        TransactionRecord(
            id: transaction.id,
            walletID: transaction.walletID,
            kind: transaction.kind,
            status: status,
            walletName: transaction.walletName,
            assetName: transaction.assetName,
            symbol: transaction.symbol,
            chainName: transaction.chainName,
            amount: transaction.amount,
            address: transaction.address,
            transactionHash: transaction.transactionHash,
            ethereumNonce: transaction.ethereumNonce,
            receiptBlockNumber: receiptBlockNumber ?? transaction.receiptBlockNumber,
            receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
            feePriorityRaw: transaction.feePriorityRaw,
            feeRateDescription: transaction.feeRateDescription,
            confirmationCount: dogecoinConfirmations ?? transaction.confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: dogecoinConfirmedNetworkFeeDOGE ?? transaction.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: dogecoinConfirmations ?? transaction.dogecoinConfirmations,
            dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: transaction.usedChangeOutput,
            dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat,
            failureReason: failureReason,
            transactionHistorySource: transaction.transactionHistorySource,
            createdAt: transaction.createdAt
        )
    }

    func statusPollFailureMessage(for transaction: TransactionRecord) -> String {
        localizedStoreFormat(
            "%@ transaction appears stuck and could not be confirmed after extended retries.",
            transaction.chainName
        )
    }

    func shouldPollTransactionStatus(for transaction: TransactionRecord, now: Date) -> Bool {
        let tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
        if tracker.reachedFinality {
            return false
        }
        return now >= tracker.nextCheckAt
    }

    func markTransactionStatusPollSuccess(
        for transaction: TransactionRecord,
        resolvedStatus: TransactionStatus,
        confirmations: Int? = nil,
        now: Date
    ) {
        var tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
        tracker.lastCheckedAt = now
        tracker.consecutiveFailures = 0

        let reachedFinality: Bool
        if resolvedStatus == .pending {
            reachedFinality = false
        } else {
            reachedFinality = (confirmations ?? finalityConfirmations(for: transaction.chainName)) >= finalityConfirmations(for: transaction.chainName)
        }

        if reachedFinality {
            tracker.reachedFinality = true
            tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
        } else if resolvedStatus == .confirmed {
            tracker.nextCheckAt = now.addingTimeInterval(Self.confirmedStatusPollSeconds)
        } else {
            tracker.nextCheckAt = now.addingTimeInterval(Self.pendingStatusPollSeconds)
        }

        statusTrackingByTransactionID[transaction.id] = tracker
    }

    func markTransactionStatusPollFailure(for transaction: TransactionRecord, now: Date) {
        var tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
        tracker.lastCheckedAt = now
        tracker.consecutiveFailures += 1

        let exponentialBackoff = min(
            Self.pendingStatusPollSeconds * pow(2, Double(max(0, tracker.consecutiveFailures - 1))),
            Self.statusPollBackoffMaxSeconds
        )
        tracker.nextCheckAt = now.addingTimeInterval(exponentialBackoff)
        statusTrackingByTransactionID[transaction.id] = tracker
    }

    func stalePendingFailureIDs(from trackedTransactions: [TransactionRecord], now: Date) -> Set<UUID> {
        Set(
            trackedTransactions.compactMap { transaction in
                guard transaction.status == .pending else { return nil }
                let age = now.timeIntervalSince(transaction.createdAt)
                guard age >= Self.pendingFailureTimeoutSeconds else { return nil }
                let tracker = statusTrackingByTransactionID[transaction.id]
                guard (tracker?.consecutiveFailures ?? 0) >= Self.pendingFailureMinFailures else { return nil }
                return transaction.id
            }
        )
    }

    func applyResolvedPendingTransactionStatuses(
        _ resolvedStatuses: [UUID: PendingTransactionStatusResolution],
        staleFailureIDs: Set<UUID>,
        now: Date
    ) {
        guard !resolvedStatuses.isEmpty || !staleFailureIDs.isEmpty else { return }

        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        transactions = transactions.map { transaction in
            if let resolution = resolvedStatuses[transaction.id] {
                if resolution.status != .pending {
                    var tracker = statusTrackingByTransactionID[transaction.id] ?? TransactionStatusTrackingState.initial(now: now)
                    tracker.reachedFinality = (resolution.confirmations ?? finalityConfirmations(for: transaction.chainName)) >= finalityConfirmations(for: transaction.chainName)
                    tracker.nextCheckAt = now.addingTimeInterval(Self.statusPollBackoffMaxSeconds)
                    statusTrackingByTransactionID[transaction.id] = tracker
                }
                return updatedTransaction(
                    transaction,
                    status: resolution.status,
                    receiptBlockNumber: resolution.receiptBlockNumber,
                    failureReason: resolution.status == .failed ? (transaction.failureReason ?? statusPollFailureMessage(for: transaction)) : nil,
                    dogecoinConfirmations: resolution.confirmations,
                    dogecoinConfirmedNetworkFeeDOGE: resolution.dogecoinNetworkFeeDOGE
                )
            }

            guard staleFailureIDs.contains(transaction.id) else { return transaction }
            return updatedTransaction(
                transaction,
                status: .failed,
                failureReason: transaction.failureReason ?? statusPollFailureMessage(for: transaction)
            )
        }

        for (transactionID, resolution) in resolvedStatuses {
            guard let oldTransaction = oldByID[transactionID],
                  let newTransaction = transactions.first(where: { $0.id == transactionID }),
                  oldTransaction.status != newTransaction.status else {
                continue
            }
            if resolution.status == .confirmed {
                appendChainOperationalEvent(
                    .info,
                    chainName: newTransaction.chainName,
                    message: "Transaction confirmed on-chain.",
                    transactionHash: newTransaction.transactionHash
                )
            } else if resolution.status == .failed {
                appendChainOperationalEvent(
                    .error,
                    chainName: newTransaction.chainName,
                    message: newTransaction.failureReason ?? statusPollFailureMessage(for: newTransaction),
                    transactionHash: newTransaction.transactionHash
                )
            }
            sendTransactionStatusNotification(for: oldTransaction, newStatus: resolution.status)
        }

        for failedID in staleFailureIDs {
            guard let oldTransaction = oldByID[failedID],
                  oldTransaction.status != .failed else {
                continue
            }
            appendChainOperationalEvent(
                .error,
                chainName: oldTransaction.chainName,
                message: oldTransaction.failureReason ?? statusPollFailureMessage(for: oldTransaction),
                transactionHash: oldTransaction.transactionHash
            )
            sendTransactionStatusNotification(for: oldTransaction, newStatus: .failed)
        }
    }

    func refreshPendingHistoryBackedTransactions(
        chainName: String,
        addressResolver: (ImportedWallet) -> String?,
        fetchStatuses: @escaping (String) async -> ([String: TransactionStatus], Bool)
    ) async {
        let now = Date()
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
                for transaction in group {
                    markTransactionStatusPollFailure(for: transaction, now: now)
                }
                continue
            }

            for transaction in group {
                guard shouldPollTransactionStatus(for: transaction, now: now),
                      let transactionHash = transaction.transactionHash?.lowercased() else {
                    continue
                }
                let resolvedStatus = statusByHash[transactionHash] ?? .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus,
                    receiptBlockNumber: nil,
                    confirmations: nil,
                    dogecoinNetworkFeeDOGE: nil
                )
            }
        }

        let staleFailureIDs = stalePendingFailureIDs(from: trackedTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }

    func statusMapByTransactionHash<S: Sequence>(
        from snapshots: S,
        hash: (S.Element) -> String,
        status: (S.Element) -> TransactionStatus
    ) -> [String: TransactionStatus] {
        var statusByHash: [String: TransactionStatus] = [:]
        for snapshot in snapshots {
            let transactionHash = hash(snapshot).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transactionHash.isEmpty else { continue }
            statusByHash[transactionHash.lowercased()] = status(snapshot)
        }
        return statusByHash
    }

    func shouldPollDogecoinStatus(for transaction: TransactionRecord, now: Date) -> Bool {
        shouldPollTransactionStatus(for: transaction, now: now)
    }

    func markDogecoinStatusPollSuccess(
        for transaction: TransactionRecord,
        status: DogecoinTransactionStatus,
        now: Date
    ) {
        markTransactionStatusPollSuccess(
            for: transaction,
            resolvedStatus: status.confirmed ? .confirmed : .pending,
            confirmations: status.confirmations ?? transaction.dogecoinConfirmations,
            now: now
        )
    }

    func markDogecoinStatusPollFailure(for transaction: TransactionRecord, now: Date) {
        markTransactionStatusPollFailure(for: transaction, now: now)
    }

    
    func updateTransactionStatus(id: UUID, to status: TransactionStatus) {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { return }
        let transaction = transactions[index]
        if transaction.chainName == "Dogecoin" {
            return
        }
        transactions[index] = TransactionRecord(
            id: transaction.id,
            walletID: transaction.walletID,
            kind: transaction.kind,
            status: status,
            walletName: transaction.walletName,
            assetName: transaction.assetName,
            symbol: transaction.symbol,
            chainName: transaction.chainName,
            amount: transaction.amount,
            address: transaction.address,
            transactionHash: transaction.transactionHash,
            receiptBlockNumber: transaction.receiptBlockNumber,
            receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeETH: transaction.receiptNetworkFeeETH,
            feePriorityRaw: transaction.feePriorityRaw,
            feeRateDescription: transaction.feeRateDescription,
            confirmationCount: transaction.confirmationCount,
            dogecoinConfirmedNetworkFeeDOGE: transaction.dogecoinConfirmedNetworkFeeDOGE,
            dogecoinConfirmations: transaction.dogecoinConfirmations,
            dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDOGEPerKB: transaction.dogecoinEstimatedFeeRateDOGEPerKB,
            usedChangeOutput: transaction.usedChangeOutput,
            dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat,
            failureReason: transaction.failureReason,
            transactionHistorySource: transaction.transactionHistorySource,
            createdAt: transaction.createdAt
        )
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
            holdingKey: coin.holdingKey,
            assetName: coin.name,
            symbol: coin.symbol,
            chainName: coin.chainName,
            targetPrice: normalizedTargetPrice,
            condition: condition
        )
        priceAlerts.insert(alert, at: 0)
        requestPriceAlertNotificationPermission()
    }
    
    func togglePriceAlertEnabled(id: UUID) {
        guard let index = priceAlerts.firstIndex(where: { $0.id == id }) else { return }
        priceAlerts[index].isEnabled.toggle()
        if !priceAlerts[index].isEnabled {
            priceAlerts[index].hasTriggered = false
        }
    }
    
    func removePriceAlert(id: UUID) {
        priceAlerts.removeAll { $0.id == id }
    }

}
