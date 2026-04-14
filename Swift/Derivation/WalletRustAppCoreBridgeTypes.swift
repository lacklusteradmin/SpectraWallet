import Foundation

struct WalletRustImportAddresses {
    let bitcoinAddress: String?, bitcoinXpub: String?, bitcoinCashAddress: String?, bitcoinSvAddress: String?, litecoinAddress: String?, dogecoinAddress: String?, ethereumAddress: String?, ethereumClassicAddress: String?, tronAddress: String?, solanaAddress: String?, xrpAddress: String?, stellarAddress: String?, moneroAddress: String?, cardanoAddress: String?, suiAddress: String?, aptosAddress: String?, tonAddress: String?, icpAddress: String?, nearAddress: String?, polkadotAddress: String?
}

struct WalletRustWatchOnlyEntries {
    let bitcoinAddresses: [String], bitcoinXpub: String?, bitcoinCashAddresses: [String], bitcoinSvAddresses: [String], litecoinAddresses: [String], dogecoinAddresses: [String], ethereumAddresses: [String], tronAddresses: [String], solanaAddresses: [String], xrpAddresses: [String], stellarAddresses: [String], cardanoAddresses: [String], suiAddresses: [String], aptosAddresses: [String], tonAddresses: [String], icpAddresses: [String], nearAddresses: [String], polkadotAddresses: [String]
}

struct WalletRustImportPlanRequest {
    let walletName: String
    let defaultWalletNameStartIndex: Int
    let primarySelectedChainName: String
    let selectedChainNames: [String]
    let plannedWalletIDs: [String]
    let isWatchOnlyImport: Bool
    let isPrivateKeyImport: Bool
    let hasWalletPassword: Bool
    let resolvedAddresses: WalletRustImportAddresses
    let watchOnlyEntries: WalletRustWatchOnlyEntries
}

struct WalletRustSecretInstruction {
    let walletID: String
    let secretKind: String
    let shouldStoreSeedPhrase: Bool
    let shouldStorePrivateKey: Bool
    let shouldStorePasswordVerifier: Bool
}

struct WalletRustPlannedWallet {
    let walletID: String
    let name: String
    let chainName: String
    let addresses: WalletRustImportAddresses
}

struct WalletRustImportPlan {
    let secretKind: String
    let wallets: [WalletRustPlannedWallet]
    let secretInstructions: [WalletRustSecretInstruction]
}

struct WalletRustSecretObservation: Encodable {
    let walletID: String
    let secretKind: String?
    let hasSeedPhrase: Bool
    let hasPrivateKey: Bool
    let hasPassword: Bool
}

struct WalletRustPersistedSnapshotBuildRequest: Encodable {
    let appStateJSON: String
    let secretObservations: [WalletRustSecretObservation]
}

typealias WalletRustSecretMaterialDescriptor = CoreWalletRustSecretMaterialDescriptor
extension CoreWalletRustSecretMaterialDescriptor: Decodable {
    // Legacy Swift acronym (uppercase) accessor forwarding to camelCased UniFFI field.
    public var walletID: String { walletId }
    private enum CodingKeys: String, CodingKey {
        case walletID, secretKind, hasSeedPhrase, hasPrivateKey, hasPassword, hasSigningMaterial, seedPhraseStoreKey, passwordStoreKey, privateKeyStoreKey
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            walletId: try c.decode(String.self, forKey: .walletID),
            secretKind: try c.decode(String.self, forKey: .secretKind),
            hasSeedPhrase: try c.decode(Bool.self, forKey: .hasSeedPhrase),
            hasPrivateKey: try c.decode(Bool.self, forKey: .hasPrivateKey),
            hasPassword: try c.decode(Bool.self, forKey: .hasPassword),
            hasSigningMaterial: try c.decode(Bool.self, forKey: .hasSigningMaterial),
            seedPhraseStoreKey: try c.decode(String.self, forKey: .seedPhraseStoreKey),
            passwordStoreKey: try c.decode(String.self, forKey: .passwordStoreKey),
            privateKeyStoreKey: try c.decode(String.self, forKey: .privateKeyStoreKey)
        )
    }
}

struct WalletRustWalletSecretIndex: Decodable {
    let descriptors: [WalletRustSecretMaterialDescriptor]
    let signingMaterialWalletIDs: [String]
    let privateKeyBackedWalletIDs: [String]
    let passwordProtectedWalletIDs: [String]
}

typealias WalletRustActiveMaintenancePlanRequest = ActiveMaintenancePlanRequest

typealias WalletRustActiveMaintenancePlan = ActiveMaintenancePlan

typealias WalletRustBackgroundMaintenanceRequest = BackgroundMaintenanceRequest

struct WalletRustChainRefreshPlanRequest {
    let chainIDs: [String]
    let nowUnix: Double
    let forceChainRefresh: Bool
    let includeHistoryRefreshes: Bool
    let historyRefreshInterval: Double
    let pendingTransactionMaintenanceChainIDs: [String]
    let degradedChainIDs: [String]
    let lastGoodChainSyncByID: [String: Double]
    let lastHistoryRefreshAtByChainID: [String: Double]
    let automaticChainRefreshStalenessInterval: Double
}

typealias WalletRustChainRefreshPlan = ChainRefreshPlan

typealias WalletRustHistoryRefreshPlanRequest = HistoryRefreshPlanRequest

struct WalletRustHistoryWallet {
    let walletID: String
    let selectedChain: String
}

struct WalletRustHistoryTransaction {
    let id: String
    let walletID: String?
    let kind: String
    let status: String
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let address: String
    let transactionHash: String?
    let transactionHistorySource: String?
    let createdAtUnix: Double
}

struct WalletRustNormalizeHistoryRequest {
    let wallets: [WalletRustHistoryWallet]
    let transactions: [WalletRustHistoryTransaction]
    let unknownLabel: String
}

typealias WalletRustBitcoinHistorySnapshotPayload = CoreBitcoinHistorySnapshot

struct WalletRustMergeBitcoinHistorySnapshotsRequest {
    let snapshots: [WalletRustBitcoinHistorySnapshotPayload]
    let ownedAddresses: [String]
    let limit: Int
}

typealias WalletRustNormalizedHistoryEntry = CoreNormalizedHistoryEntry

enum WalletRustTransactionMergeStrategy {
    case standardUTXO
    case dogecoin
    case accountBased
    case evm
}

struct WalletRustTransactionRecord {
    let id: String, walletID: String?, kind: String, status: String
    let walletName: String, assetName: String, symbol: String, chainName: String
    let amount: Double, address: String, transactionHash: String?
    let ethereumNonce: Int?, receiptBlockNumber: Int?, receiptGasUsed: String?
    let receiptEffectiveGasPriceGwei: Double?, receiptNetworkFeeEth: Double?
    let feePriorityRaw: String?, feeRateDescription: String?, confirmationCount: Int?
    let dogecoinConfirmedNetworkFeeDoge: Double?, dogecoinConfirmations: Int?
    let dogecoinFeePriorityRaw: String?, dogecoinEstimatedFeeRateDogePerKb: Double?
    let usedChangeOutput: Bool?, dogecoinUsedChangeOutput: Bool?
    let sourceDerivationPath: String?, changeDerivationPath: String?
    let sourceAddress: String?, changeAddress: String?, dogecoinRawTransactionHex: String?
    let signedTransactionPayload: String?, signedTransactionPayloadFormat: String?
    let failureReason: String?, transactionHistorySource: String?, createdAtUnix: Double
}

struct WalletRustTransactionMergeRequest {
    let existingTransactions: [WalletRustTransactionRecord]
    let incomingTransactions: [WalletRustTransactionRecord]
    let strategy: WalletRustTransactionMergeStrategy
    let chainName: String
    let includeSymbolInIdentity: Bool
    let preserveCreatedAtSentinelUnix: Double?
}

struct WalletRustEVMRefreshWalletInput {
    let index: Int
    let walletID: String
    let selectedChain: String
    let address: String?
}

struct WalletRustEVMRefreshTargetsRequest {
    let chainName: String
    let wallets: [WalletRustEVMRefreshWalletInput]
    let allowedWalletIDs: [String]?
    let groupByNormalizedAddress: Bool
}

struct WalletRustEVMRefreshWalletTarget {
    let index: Int
    let walletID: String
    let address: String
    let normalizedAddress: String
}

struct WalletRustEVMGroupedTarget {
    let walletIDs: [String]
    let address: String
    let normalizedAddress: String
}

struct WalletRustEVMRefreshPlan {
    let walletTargets: [WalletRustEVMRefreshWalletTarget]
    let groupedTargets: [WalletRustEVMGroupedTarget]
}

struct WalletRustDogecoinRefreshWalletInput {
    let index: Int
    let walletID: String
    let selectedChain: String
    let addresses: [String]
}

struct WalletRustDogecoinRefreshTargetsRequest {
    let wallets: [WalletRustDogecoinRefreshWalletInput]
    let allowedWalletIDs: [String]?
}

struct WalletRustDogecoinRefreshWalletTarget {
    let index: Int
    let walletID: String
    let addresses: [String]
}

struct WalletRustSendAssetRoutingInput {
    let chainName: String
    let symbol: String
    let isEVMChain: Bool
    let supportsSolanaSendCoin: Bool
    var supportsNearTokenSend: Bool = false
}

struct WalletRustSendPreviewRoutingRequest {
    let asset: WalletRustSendAssetRoutingInput?
}

typealias WalletRustSendPreviewRoutingPlan = SendPreviewRoutingPlan

struct WalletRustSendSubmitPreflightRequest {
    let walletFound: Bool
    let assetFound: Bool
    let destinationAddress: String
    let amountInput: String
    let availableBalance: Double
    let asset: WalletRustSendAssetRoutingInput?
}

typealias WalletRustSendSubmitPreflightPlan = SendSubmitPreflightPlan

struct WalletRustTransferHoldingInput {
    let index: Int
    let chainName: String
    let symbol: String
    let supportsSend: Bool
    let supportsReceiveAddress: Bool
    let isLiveChain: Bool
    let supportsEVMToken: Bool
    let supportsSolanaSendCoin: Bool
}

struct WalletRustTransferWalletInput {
    let walletID: String
    let hasSigningMaterial: Bool
    let holdings: [WalletRustTransferHoldingInput]
}

struct WalletRustTransferAvailabilityRequest {
    let wallets: [WalletRustTransferWalletInput]
}

struct WalletRustWalletTransferAvailability {
    let walletID: String
    let sendHoldingIndices: [Int]
    let receiveHoldingIndices: [Int]
    let receiveChains: [String]
}

struct WalletRustTransferAvailabilityPlan {
    let wallets: [WalletRustWalletTransferAvailability]
    let sendEnabledWalletIDs: [String]
    let receiveEnabledWalletIDs: [String]
}

struct WalletRustStoreDerivedHoldingInput {
    let holdingIndex: Int
    let assetIdentityKey: String
    let symbolUpper: String
    let amount: String
    let isPricedAsset: Bool
}

struct WalletRustStoreDerivedWalletInput {
    let walletID: String
    let includeInPortfolioTotal: Bool
    let hasSigningMaterial: Bool
    let isPrivateKeyBacked: Bool
    let holdings: [WalletRustStoreDerivedHoldingInput]
}

struct WalletRustStoreDerivedStateRequest {
    let wallets: [WalletRustStoreDerivedWalletInput]
}

struct WalletRustWalletHoldingRef {
    let walletID: String
    let holdingIndex: Int
}

struct WalletRustGroupedPortfolioHolding {
    let assetIdentityKey: String
    let walletID: String
    let holdingIndex: Int
    let totalAmount: String
}

struct WalletRustStoreDerivedStatePlan {
    let includedPortfolioHoldingRefs: [WalletRustWalletHoldingRef]
    let uniquePriceRequestHoldingRefs: [WalletRustWalletHoldingRef]
    let groupedPortfolio: [WalletRustGroupedPortfolioHolding]
    let signingMaterialWalletIDs: [String]
    let privateKeyBackedWalletIDs: [String]
}

typealias WalletRustOwnedAddressAggregationRequest = OwnedAddressAggregationRequest

struct WalletRustReceiveSelectionHoldingInput {
    let holdingIndex: Int
    let chainName: String
    let hasContractAddress: Bool
}

struct WalletRustReceiveSelectionRequest {
    let receiveChainName: String
    let availableReceiveChains: [String]
    let availableReceiveHoldings: [WalletRustReceiveSelectionHoldingInput]
}

typealias WalletRustReceiveSelectionPlan = ReceiveSelectionPlan

struct WalletRustPendingSelfSendConfirmationInput {
    let walletID: String
    let chainName: String
    let symbol: String
    let destinationAddressLowercased: String
    let amount: Double
    let createdAtUnix: Double
}

struct WalletRustSelfSendConfirmationRequest {
    let pendingConfirmation: WalletRustPendingSelfSendConfirmationInput?
    let walletID: String
    let chainName: String
    let symbol: String
    let destinationAddress: String
    let amount: Double
    let nowUnix: Double
    let windowSeconds: Double
    let ownedAddresses: [String]
}

typealias WalletRustSelfSendConfirmationPlan = SelfSendConfirmationPlan

struct WalletRustResolvedDerivationPath {
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: SeedDerivationFlavor
}
