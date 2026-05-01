import Foundation
import SwiftUI
@MainActor
extension AppState {
    func clearOperationalLogs() { diagnostics.clearOperationalLogs() }
    var networkSyncStatusText: String {
        let reachability = isNetworkReachable ? localizedStoreString("reachable") : localizedStoreString("offline")
        let constrained = isConstrainedNetwork ? localizedStoreString("constrained") : localizedStoreString("unconstrained")
        let expensive = isExpensiveNetwork ? localizedStoreString("expensive") : localizedStoreString("non-expensive")
        return localizedStoreFormat(
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
        let event = ChainOperationalEvent(
            id: UUID(), timestamp: Date(), chainName: chainName, level: level, message: message,
            transactionHash: transactionHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let existing = chainOperationalEventsByChain[chainName] ?? []
        let updatedRecords = corePlanAppendChainOperationalEvent(
            existingEvents: existing.map(\.coreRecord), newEvent: event.coreRecord
        )
        chainOperationalEventsByChain[chainName] = updatedRecords.compactMap(ChainOperationalEvent.init(coreRecord:))
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
    func loadChainOperationalEvents() -> [String: [ChainOperationalEvent]] {
        guard let data = UserDefaults.standard.data(forKey: Self.chainOperationalEventsDefaultsKey),
            let decoded = try? JSONDecoder().decode([String: [ChainOperationalEvent]].self, from: data)
        else { return [:] }
        return decoded
    }
    func persistChainOperationalEvents() {
        persistCodableToSQLite(chainOperationalEventsByChain, key: Self.chainOperationalEventsDefaultsKey)
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
            dogecoinConfirmations: transaction.dogecoinConfirmations, dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: transaction.dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: transaction.usedChangeOutput ?? previewDetails?.usesChangeOutput,
            dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput, sourceDerivationPath: transaction.sourceDerivationPath,
            changeDerivationPath: transaction.changeDerivationPath, sourceAddress: transaction.sourceAddress,
            changeAddress: transaction.changeAddress, dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
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
    func consumePendingSelfSendConfirmation(walletID: String, chainName: String, symbol: String, destinationAddress: String, amount: Double)
        -> Bool
    {
        let plan = rustSelfSendConfirmationPlan(
            walletID: walletID, chainName: chainName, symbol: symbol, destinationAddress: destinationAddress, amount: amount,
            ownedAddresses: []
        )
        if plan.clearPendingConfirmation { pendingSelfSendConfirmation = nil }
        return plan.consumeExistingConfirmation
    }
    func requiresSelfSendConfirmation(wallet: ImportedWallet, holding: Coin, destinationAddress: String, amount: Double) -> Bool {
        let ownAddresses: [String]
        if holding.chainName == "Dogecoin" {
            ownAddresses = knownUTXOAddresses(for: wallet, chainName: "Dogecoin")
        } else {
            ownAddresses = knownOwnedAddresses(for: wallet.id)
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
        corePlanSelfSendConfirmation(
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
    func finalityConfirmations(for chainName: String) -> Int { Self.standardFinalityConfirmations }
    func updatedTransaction(
        _ transaction: TransactionRecord, status: TransactionStatus, receiptBlockNumber: Int? = nil, failureReason: String? = nil,
        dogecoinConfirmations: Int? = nil, dogecoinConfirmedNetworkFeeDoge: Double? = nil
    ) -> TransactionRecord {
        TransactionRecord(
            id: transaction.id, walletID: transaction.walletID, kind: transaction.kind, status: status, walletName: transaction.walletName,
            assetName: transaction.assetName, symbol: transaction.symbol, chainName: transaction.chainName, amount: transaction.amount,
            address: transaction.address, transactionHash: transaction.transactionHash, ethereumNonce: transaction.ethereumNonce,
            receiptBlockNumber: receiptBlockNumber ?? transaction.receiptBlockNumber, receiptGasUsed: transaction.receiptGasUsed,
            receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei, receiptNetworkFeeEth: transaction.receiptNetworkFeeEth,
            feePriorityRaw: transaction.feePriorityRaw, feeRateDescription: transaction.feeRateDescription,
            confirmationCount: dogecoinConfirmations ?? transaction.confirmationCount,
            dogecoinConfirmedNetworkFeeDoge: dogecoinConfirmedNetworkFeeDoge ?? transaction.dogecoinConfirmedNetworkFeeDoge,
            dogecoinConfirmations: dogecoinConfirmations ?? transaction.dogecoinConfirmations,
            dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: transaction.dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: transaction.usedChangeOutput, dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath, changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress, changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat, failureReason: failureReason,
            transactionHistorySource: transaction.transactionHistorySource, createdAt: transaction.createdAt
        )
    }
    func statusPollFailureMessage(for transaction: TransactionRecord) -> String {
        localizedStoreFormat(
            "%@ transaction appears stuck and could not be confirmed after extended retries.", transaction.chainName
        )
    }
    private func transactionStatusPollConfig() -> TransactionStatusPollConfig {
        TransactionStatusPollConfig(
            pendingPollSeconds: Self.pendingStatusPollSeconds,
            confirmedPollSeconds: Self.confirmedStatusPollSeconds,
            backoffMaxSeconds: Self.statusPollBackoffMaxSeconds,
            finalityConfirmations: UInt32(Self.standardFinalityConfirmations),
            pendingFailureTimeoutSeconds: Self.pendingFailureTimeoutSeconds,
            pendingFailureMinFailures: UInt32(Self.pendingFailureMinFailures)
        )
    }
    private func coreTrackerState(for transactionID: UUID) -> TransactionStatusTrackerState? {
        statusTrackingByTransactionID[transactionID].map(\.coreRecord)
    }
    private func storeCoreTracker(_ tracker: TransactionStatusTrackerState, for transactionID: UUID) {
        statusTrackingByTransactionID[transactionID] = TransactionStatusTrackingState(coreRecord: tracker)
    }
    func shouldPollTransactionStatus(for transaction: TransactionRecord, now: Date) -> Bool {
        corePlanTransactionStatusShouldPoll(tracker: coreTrackerState(for: transaction.id), nowUnix: now.timeIntervalSince1970)
    }
    func markTransactionStatusPollSuccess(
        for transaction: TransactionRecord, resolvedStatus: TransactionStatus, confirmations: Int? = nil, now: Date
    ) {
        let tracker = corePlanTransactionStatusPollSuccess(
            tracker: coreTrackerState(for: transaction.id),
            resolvedStatusConfirmed: resolvedStatus == .confirmed,
            resolvedStatusPending: resolvedStatus == .pending,
            reportedConfirmations: confirmations.map { UInt32(max(0, $0)) },
            nowUnix: now.timeIntervalSince1970,
            config: transactionStatusPollConfig()
        )
        storeCoreTracker(tracker, for: transaction.id)
    }
    func markTransactionStatusPollFailure(for transaction: TransactionRecord, now: Date) {
        let tracker = corePlanTransactionStatusPollFailure(
            tracker: coreTrackerState(for: transaction.id),
            nowUnix: now.timeIntervalSince1970,
            config: transactionStatusPollConfig()
        )
        storeCoreTracker(tracker, for: transaction.id)
    }
    func stalePendingFailureIDs(from trackedTransactions: [TransactionRecord], now: Date) -> Set<UUID> {
        let inputs = trackedTransactions.map { transaction in
            StalePendingFailureTransactionInput(
                id: transaction.id.uuidString,
                createdAtUnix: transaction.createdAt.timeIntervalSince1970,
                statusIsPending: transaction.status == .pending,
                trackerConsecutiveFailures: UInt32(max(0, statusTrackingByTransactionID[transaction.id]?.consecutiveFailures ?? 0))
            )
        }
        let ids = corePlanStalePendingFailureIds(
            transactions: inputs, nowUnix: now.timeIntervalSince1970, config: transactionStatusPollConfig()
        )
        return Set(ids.compactMap(UUID.init(uuidString:)))
    }
    func applyResolvedPendingTransactionStatuses(
        _ resolvedStatuses: [UUID: PendingTransactionStatusResolution], staleFailureIDs: Set<UUID>, now: Date
    ) {
        guard !resolvedStatuses.isEmpty || !staleFailureIDs.isEmpty else { return }
        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let inputs: [ResolvedPendingTransactionInput] = transactions.compactMap { transaction in
            let resolution = resolvedStatuses[transaction.id]
            let isStale = staleFailureIDs.contains(transaction.id)
            guard resolution != nil || isStale else { return nil }
            return ResolvedPendingTransactionInput(
                id: transaction.id.uuidString,
                oldStatus: transaction.status.rawValue,
                oldFailureReason: transaction.failureReason,
                oldConfirmations: (transaction.dogecoinConfirmations ?? transaction.confirmationCount).map { UInt32(max(0, $0)) },
                resolution: resolution.map {
                    ResolvedPendingStatusInput(status: $0.status.rawValue, confirmations: $0.confirmations.map { UInt32(max(0, $0)) })
                },
                isStaleFailure: isStale,
                currentTracker: coreTrackerState(for: transaction.id)
            )
        }
        let decisions = corePlanApplyResolvedPendingTransactionStatuses(
            inputs: inputs, nowUnix: now.timeIntervalSince1970, config: transactionStatusPollConfig()
        )
        let decisionByID: [UUID: ResolvedPendingTransactionDecision] = Dictionary(
            uniqueKeysWithValues: decisions.compactMap { decision in
                UUID(uuidString: decision.id).map { ($0, decision) }
            }
        )
        for (transactionID, decision) in decisionByID {
            if let tracker = decision.updatedTracker {
                storeCoreTracker(tracker, for: transactionID)
            }
        }
        setTransactions(
            transactions.map { transaction in
                guard let decision = decisionByID[transaction.id] else { return transaction }
                guard let newStatus = TransactionStatus(rawValue: decision.newStatus) else { return transaction }
                let resolution = resolvedStatuses[transaction.id]
                let failureReason: String?
                switch decision.failureReasonDisposition {
                case .none: failureReason = nil
                case .preserve: failureReason = transaction.failureReason
                case .localizedFallback: failureReason = statusPollFailureMessage(for: transaction)
                }
                return updatedTransaction(
                    transaction,
                    status: newStatus,
                    receiptBlockNumber: resolution?.receiptBlockNumber,
                    failureReason: failureReason,
                    dogecoinConfirmations: resolution?.confirmations,
                    dogecoinConfirmedNetworkFeeDoge: resolution?.dogecoinNetworkFeeDoge
                )
            })
        for (transactionID, decision) in decisionByID {
            guard let oldTransaction = oldByID[transactionID], let newTransaction = transactions.first(where: { $0.id == transactionID })
            else { continue }
            if decision.statusChanged, let newStatus = TransactionStatus(rawValue: decision.newStatus) {
                switch decision.emitEventCode {
                case "confirmed":
                    appendChainOperationalEvent(
                        .info, chainName: newTransaction.chainName,
                        message: statusPollConfirmedMessage(for: newTransaction),
                        transactionHash: newTransaction.transactionHash
                    )
                case "failed":
                    appendChainOperationalEvent(
                        .error, chainName: newTransaction.chainName,
                        message: statusPollFailedEventMessage(for: newTransaction),
                        transactionHash: newTransaction.transactionHash
                    )
                default: break
                }
                if decision.sendStatusNotification {
                    sendTransactionStatusNotification(for: oldTransaction, newStatus: newStatus)
                }
            }
            if let confirmations = decision.reachedFinalityConfirmations {
                appendChainOperationalEvent(
                    .info, chainName: newTransaction.chainName,
                    message: statusPollFinalityReachedMessage(for: newTransaction, confirmations: Int(confirmations)),
                    transactionHash: newTransaction.transactionHash
                )
            }
        }
    }

    private func statusPollFailedEventMessage(for transaction: TransactionRecord) -> String {
        switch transaction.chainName {
        case "Dogecoin": return localizedStoreString("DOGE transaction marked failed after extended retries.")
        default: return transaction.failureReason ?? statusPollFailureMessage(for: transaction)
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
            return localizedStoreFormat("DOGE transaction reached finality (%d confirmations).", confirmations)
        default:
            return localizedStoreFormat("Transaction reached finality (%d confirmations).", confirmations)
        }
    }
    func refreshPendingHistoryBackedTransactions(
        chainName: String, addressResolver: (ImportedWallet) -> String?,
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
                for transaction in group { markTransactionStatusPollFailure(for: transaction, now: now) }
                continue
            }
            for transaction in group {
                guard shouldPollTransactionStatus(for: transaction, now: now),
                    let transactionHash = transaction.transactionHash?.lowercased()
                else { continue }
                let resolvedStatus = statusByHash[transactionHash] ?? .pending
                markTransactionStatusPollSuccess(for: transaction, resolvedStatus: resolvedStatus, now: now)
                resolvedStatuses[transaction.id] = PendingTransactionStatusResolution(
                    status: resolvedStatus, receiptBlockNumber: nil, confirmations: nil, dogecoinNetworkFeeDoge: nil
                )
            }
        }
        let staleFailureIDs = stalePendingFailureIDs(from: trackedTransactions, now: now)
        applyResolvedPendingTransactionStatuses(resolvedStatuses, staleFailureIDs: staleFailureIDs, now: now)
    }
    func statusMapByTransactionHash<S: Sequence>(
        from snapshots: S, hash: (S.Element) -> String, status: (S.Element) -> TransactionStatus
    ) -> [String: TransactionStatus] {
        var statusByHash: [String: TransactionStatus] = [:]
        for snapshot in snapshots {
            let transactionHash = hash(snapshot).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transactionHash.isEmpty else { continue }
            statusByHash[transactionHash.lowercased()] = status(snapshot)
        }
        return statusByHash
    }
    func updateTransactionStatus(id: UUID, to status: TransactionStatus) {
        guard let index = transactions.firstIndex(where: { $0.id == id }) else { return }
        let transaction = transactions[index]
        if transaction.chainName == "Dogecoin" { return }
        transactions[index] = TransactionRecord(
            id: transaction.id, walletID: transaction.walletID, kind: transaction.kind, status: status, walletName: transaction.walletName,
            assetName: transaction.assetName, symbol: transaction.symbol, chainName: transaction.chainName, amount: transaction.amount,
            address: transaction.address, transactionHash: transaction.transactionHash, receiptBlockNumber: transaction.receiptBlockNumber,
            receiptGasUsed: transaction.receiptGasUsed, receiptEffectiveGasPriceGwei: transaction.receiptEffectiveGasPriceGwei,
            receiptNetworkFeeEth: transaction.receiptNetworkFeeEth, feePriorityRaw: transaction.feePriorityRaw,
            feeRateDescription: transaction.feeRateDescription, confirmationCount: transaction.confirmationCount,
            dogecoinConfirmedNetworkFeeDoge: transaction.dogecoinConfirmedNetworkFeeDoge,
            dogecoinConfirmations: transaction.dogecoinConfirmations, dogecoinFeePriorityRaw: transaction.dogecoinFeePriorityRaw,
            dogecoinEstimatedFeeRateDogePerKb: transaction.dogecoinEstimatedFeeRateDogePerKb,
            usedChangeOutput: transaction.usedChangeOutput, dogecoinUsedChangeOutput: transaction.dogecoinUsedChangeOutput,
            sourceDerivationPath: transaction.sourceDerivationPath, changeDerivationPath: transaction.changeDerivationPath,
            sourceAddress: transaction.sourceAddress, changeAddress: transaction.changeAddress,
            dogecoinRawTransactionHex: transaction.dogecoinRawTransactionHex,
            signedTransactionPayload: transaction.signedTransactionPayload,
            signedTransactionPayloadFormat: transaction.signedTransactionPayloadFormat, failureReason: transaction.failureReason,
            transactionHistorySource: transaction.transactionHistorySource, createdAt: transaction.createdAt
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
            holdingKey: coin.holdingKey, assetName: coin.name, symbol: coin.symbol, chainName: coin.chainName,
            targetPrice: normalizedTargetPrice, condition: condition
        )
        priceAlerts.insert(alert, at: 0)
        requestPriceAlertNotificationPermission()
    }
    func togglePriceAlertEnabled(id: UUID) {
        guard let index = priceAlerts.firstIndex(where: { $0.id == id }) else { return }
        priceAlerts[index].isEnabled.toggle()
        if !priceAlerts[index].isEnabled { priceAlerts[index].hasTriggered = false }
    }
    func removePriceAlert(id: UUID) {
        priceAlerts.removeAll { $0.id == id }
    }
}
