import Foundation

// ─── Typealiases: WalletRust* → UniFFI-generated types ──────────────────────
// These preserve backward compatibility at call sites while eliminating
// the separate struct definitions and toFFI()/toWalletRust() conversion glue.

typealias WalletRustImportAddresses = WalletImportAddresses
typealias WalletRustWatchOnlyEntries = WalletImportWatchOnlyEntries
typealias WalletRustImportPlanRequest = WalletImportRequest
typealias WalletRustImportPlan = WalletImportPlan
typealias WalletRustPlannedWallet = PlannedWallet
typealias WalletRustSecretInstruction = WalletSecretInstruction
typealias WalletRustSecretMaterialDescriptor = CoreWalletRustSecretMaterialDescriptor
typealias WalletRustActiveMaintenancePlanRequest = ActiveMaintenancePlanRequest
typealias WalletRustActiveMaintenancePlan = ActiveMaintenancePlan
typealias WalletRustBackgroundMaintenanceRequest = BackgroundMaintenanceRequest
typealias WalletRustChainRefreshPlanRequest = ChainRefreshPlanRequest
typealias WalletRustChainRefreshPlan = ChainRefreshPlan
typealias WalletRustHistoryRefreshPlanRequest = HistoryRefreshPlanRequest
typealias WalletRustHistoryWallet = HistoryWallet
typealias WalletRustHistoryTransaction = HistoryTransaction
typealias WalletRustNormalizeHistoryRequest = NormalizeHistoryRequest
typealias WalletRustBitcoinHistorySnapshotPayload = CoreBitcoinHistorySnapshot
typealias WalletRustMergeBitcoinHistorySnapshotsRequest = MergeBitcoinHistorySnapshotsRequest
typealias WalletRustNormalizedHistoryEntry = CoreNormalizedHistoryEntry
typealias WalletRustTransactionMergeStrategy = TransactionMergeStrategy
typealias WalletRustTransactionRecord = CoreTransactionRecord
typealias WalletRustTransactionMergeRequest = TransactionMergeRequest
typealias WalletRustEVMRefreshWalletInput = EvmRefreshWalletInput
typealias WalletRustEVMRefreshTargetsRequest = EvmRefreshTargetsRequest
typealias WalletRustEVMRefreshWalletTarget = EvmRefreshWalletTarget
typealias WalletRustEVMGroupedTarget = EvmGroupedTarget
typealias WalletRustEVMRefreshPlan = EvmRefreshPlan
typealias WalletRustDogecoinRefreshWalletInput = DogecoinRefreshWalletInput
typealias WalletRustDogecoinRefreshTargetsRequest = DogecoinRefreshTargetsRequest
typealias WalletRustDogecoinRefreshWalletTarget = DogecoinRefreshWalletTarget
typealias WalletRustSendAssetRoutingInput = SendAssetRoutingInput
typealias WalletRustSendPreviewRoutingRequest = SendPreviewRoutingRequest
typealias WalletRustSendPreviewRoutingPlan = SendPreviewRoutingPlan
typealias WalletRustSendSubmitPreflightRequest = SendSubmitPreflightRequest
typealias WalletRustSendSubmitPreflightPlan = SendSubmitPreflightPlan
typealias WalletRustTransferHoldingInput = TransferHoldingInput
typealias WalletRustTransferWalletInput = TransferWalletInput
typealias WalletRustTransferAvailabilityRequest = TransferAvailabilityRequest
typealias WalletRustWalletTransferAvailability = WalletTransferAvailability
typealias WalletRustTransferAvailabilityPlan = TransferAvailabilityPlan
typealias WalletRustStoreDerivedHoldingInput = StoreDerivedHoldingInput
typealias WalletRustStoreDerivedWalletInput = StoreDerivedWalletInput
typealias WalletRustStoreDerivedStateRequest = StoreDerivedStateRequest
typealias WalletRustWalletHoldingRef = WalletHoldingRef
typealias WalletRustGroupedPortfolioHolding = GroupedPortfolioHolding
typealias WalletRustStoreDerivedStatePlan = StoreDerivedStatePlan
typealias WalletRustOwnedAddressAggregationRequest = OwnedAddressAggregationRequest
typealias WalletRustReceiveSelectionHoldingInput = ReceiveSelectionHoldingInput
typealias WalletRustReceiveSelectionRequest = ReceiveSelectionRequest
typealias WalletRustReceiveSelectionPlan = ReceiveSelectionPlan
typealias WalletRustPendingSelfSendConfirmationInput = PendingSelfSendConfirmationInput
typealias WalletRustSelfSendConfirmationRequest = SelfSendConfirmationRequest
typealias WalletRustSelfSendConfirmationPlan = SelfSendConfirmationPlan

// ─── Convenience extensions: Swift-acronym property names ───────────────────
// UniFFI generates camelCase (`walletId`), Swift convention is uppercase
// acronyms (`walletID`). These computed properties bridge the naming gap
// so existing call sites compile without modification.

extension PlannedWallet {
    var walletID: String { walletId }
}
extension WalletSecretInstruction {
    var walletID: String { walletId }
}
extension EvmRefreshWalletTarget {
    var walletID: String { walletId }
}
extension EvmGroupedTarget {
    var walletIDs: [String] { walletIds }
}
extension DogecoinRefreshWalletTarget {
    var walletID: String { walletId }
}
extension WalletTransferAvailability {
    var walletID: String { walletId }
}
extension TransferAvailabilityPlan {
    var sendEnabledWalletIDs: [String] { sendEnabledWalletIds }
    var receiveEnabledWalletIDs: [String] { receiveEnabledWalletIds }
}
extension StoreDerivedStatePlan {
    var signingMaterialWalletIDs: [String] { signingMaterialWalletIds }
    var privateKeyBackedWalletIDs: [String] { privateKeyBackedWalletIds }
}
extension WalletHoldingRef {
    var walletID: String { walletId }
}
extension GroupedPortfolioHolding {
    var walletID: String { walletId }
}
extension CoreTransactionRecord {
    var walletID: String? { walletId }
}

// ─── Enum case backward compat ──────────────────────────────────────────────

extension TransactionMergeStrategy {
    static var standardUTXO: Self { .standardUtxo }
}

// ─── Types kept as standalone structs (not direct UniFFI records) ────────────

struct WalletRustResolvedDerivationPath {
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: SeedDerivationFlavor
}
