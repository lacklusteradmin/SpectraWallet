import Foundation

enum WalletRustAppCoreBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain):
            return "The Rust app core does not support \(chain) yet."
        case .rustCoreReturnedNullResponse:
            return "The Rust app core returned an empty response."
        case .rustCoreFailed(let message):
            return message
        case .invalidPayload(let message):
            return message
        }
    }
}

private struct WalletRustFFIJSONResponse {
    var statusCode: Int32
    var payloadUTF8: WalletRustFFIBuffer
    var errorMessageUTF8: WalletRustFFIBuffer
}

private struct WalletRustFFICoreLocalizationDocumentRequest {
    var resourceNameUTF8: WalletRustFFIBuffer
    var preferredLocalesJSONUTF8: WalletRustFFIBuffer
}

private struct WalletRustFFICoreStateReduceRequest {
    var stateJSONUTF8: WalletRustFFIBuffer
    var commandJSONUTF8: WalletRustFFIBuffer
}

private struct WalletRustFFICoreJSONRequest {
    var jsonUTF8: WalletRustFFIBuffer
}

private extension Data {
    func asJSONString() throws -> String {
        guard let json = String(data: self, encoding: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Payload was not valid UTF-8 JSON.")
        }
        return json
    }
}

private struct WalletRustStaticResourceRequest: Encodable {
    let resourceName: String
}

struct WalletRustImportAddresses: Codable {
    let bitcoinAddress: String?
    let bitcoinXpub: String?
    let bitcoinCashAddress: String?
    let bitcoinSVAddress: String?
    let litecoinAddress: String?
    let dogecoinAddress: String?
    let ethereumAddress: String?
    let ethereumClassicAddress: String?
    let tronAddress: String?
    let solanaAddress: String?
    let xrpAddress: String?
    let stellarAddress: String?
    let moneroAddress: String?
    let cardanoAddress: String?
    let suiAddress: String?
    let aptosAddress: String?
    let tonAddress: String?
    let icpAddress: String?
    let nearAddress: String?
    let polkadotAddress: String?
}

struct WalletRustWatchOnlyEntries: Codable {
    let bitcoinAddresses: [String]
    let bitcoinXpub: String?
    let bitcoinCashAddresses: [String]
    let bitcoinSVAddresses: [String]
    let litecoinAddresses: [String]
    let dogecoinAddresses: [String]
    let ethereumAddresses: [String]
    let tronAddresses: [String]
    let solanaAddresses: [String]
    let xrpAddresses: [String]
    let stellarAddresses: [String]
    let cardanoAddresses: [String]
    let suiAddresses: [String]
    let aptosAddresses: [String]
    let tonAddresses: [String]
    let icpAddresses: [String]
    let nearAddresses: [String]
    let polkadotAddresses: [String]
}

struct WalletRustImportPlanRequest: Encodable {
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

struct WalletRustSecretInstruction: Decodable {
    let walletID: String
    let secretKind: String
    let shouldStoreSeedPhrase: Bool
    let shouldStorePrivateKey: Bool
    let shouldStorePasswordVerifier: Bool
}

struct WalletRustPlannedWallet: Decodable {
    let walletID: String
    let name: String
    let chainName: String
    let addresses: WalletRustImportAddresses
}

struct WalletRustImportPlan: Decodable {
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

struct WalletRustSecretMaterialDescriptor: Decodable {
    let walletID: String
    let secretKind: String
    let hasSeedPhrase: Bool
    let hasPrivateKey: Bool
    let hasPassword: Bool
    let hasSigningMaterial: Bool
    let seedPhraseStoreKey: String
    let passwordStoreKey: String
    let privateKeyStoreKey: String
}

struct WalletRustWalletSecretIndex: Decodable {
    let descriptors: [WalletRustSecretMaterialDescriptor]
    let signingMaterialWalletIDs: [String]
    let privateKeyBackedWalletIDs: [String]
    let passwordProtectedWalletIDs: [String]
}

struct WalletRustActiveMaintenancePlanRequest: Encodable {
    let nowUnix: Double
    let lastPendingTransactionRefreshAtUnix: Double?
    let lastLivePriceRefreshAtUnix: Double?
    let hasPendingTransactionMaintenanceWork: Bool
    let shouldRunScheduledPriceRefresh: Bool
    let pendingRefreshInterval: Double
    let priceRefreshInterval: Double
}

struct WalletRustActiveMaintenancePlan: Decodable {
    let refreshPendingTransactions: Bool
    let refreshLivePrices: Bool
}

struct WalletRustBackgroundMaintenanceRequest: Encodable {
    let nowUnix: Double
    let isNetworkReachable: Bool
    let lastBackgroundMaintenanceAtUnix: Double?
    let interval: Double
}

struct WalletRustChainRefreshPlanRequest: Encodable {
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

struct WalletRustChainRefreshPlan: Decodable {
    let chainID: String
    let chainName: String
    let refreshHistory: Bool
}

struct WalletRustHistoryRefreshPlanRequest: Encodable {
    let chainIDs: [String]
    let nowUnix: Double
    let interval: Double
    let lastHistoryRefreshAtByChainID: [String: Double]
}

struct WalletRustHistoryWallet: Encodable {
    let walletID: String
    let selectedChain: String
}

struct WalletRustHistoryTransaction: Encodable {
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

struct WalletRustNormalizeHistoryRequest: Encodable {
    let wallets: [WalletRustHistoryWallet]
    let transactions: [WalletRustHistoryTransaction]
    let unknownLabel: String
}

struct WalletRustNormalizedHistoryEntry: Decodable {
    let id: String
    let transactionID: String
    let dedupeKey: String
    let createdAtUnix: Double
    let kind: String
    let status: String
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let address: String
    let transactionHash: String?
    let sourceTag: String
    let providerCount: Int
    let searchIndex: String
}

enum WalletRustTransactionMergeStrategy: String, Encodable {
    case standardUTXO = "standardUtxo"
    case dogecoin = "dogecoin"
    case accountBased = "accountBased"
    case evm = "evm"
}

struct WalletRustTransactionRecord: Codable {
    let id: String
    let walletID: String?
    let kind: String
    let status: String
    let walletName: String
    let assetName: String
    let symbol: String
    let chainName: String
    let amount: Double
    let address: String
    let transactionHash: String?
    let ethereumNonce: Int?
    let receiptBlockNumber: Int?
    let receiptGasUsed: String?
    let receiptEffectiveGasPriceGwei: Double?
    let receiptNetworkFeeETH: Double?
    let feePriorityRaw: String?
    let feeRateDescription: String?
    let confirmationCount: Int?
    let dogecoinConfirmedNetworkFeeDOGE: Double?
    let dogecoinConfirmations: Int?
    let dogecoinFeePriorityRaw: String?
    let dogecoinEstimatedFeeRateDOGEPerKB: Double?
    let usedChangeOutput: Bool?
    let dogecoinUsedChangeOutput: Bool?
    let sourceDerivationPath: String?
    let changeDerivationPath: String?
    let sourceAddress: String?
    let changeAddress: String?
    let dogecoinRawTransactionHex: String?
    let signedTransactionPayload: String?
    let signedTransactionPayloadFormat: String?
    let failureReason: String?
    let transactionHistorySource: String?
    let createdAtUnix: Double
}

struct WalletRustTransactionMergeRequest: Encodable {
    let existingTransactions: [WalletRustTransactionRecord]
    let incomingTransactions: [WalletRustTransactionRecord]
    let strategy: WalletRustTransactionMergeStrategy
    let chainName: String
    let includeSymbolInIdentity: Bool
    let preserveCreatedAtSentinelUnix: Double?
}

struct WalletRustEVMRefreshWalletInput: Encodable {
    let index: Int
    let walletID: String
    let selectedChain: String
    let address: String?
}

struct WalletRustEVMRefreshTargetsRequest: Encodable {
    let chainName: String
    let wallets: [WalletRustEVMRefreshWalletInput]
    let allowedWalletIDs: [String]?
    let groupByNormalizedAddress: Bool
}

struct WalletRustEVMRefreshWalletTarget: Decodable {
    let index: Int
    let walletID: String
    let address: String
    let normalizedAddress: String
}

struct WalletRustEVMGroupedTarget: Decodable {
    let walletIDs: [String]
    let address: String
    let normalizedAddress: String
}

struct WalletRustEVMRefreshPlan: Decodable {
    let walletTargets: [WalletRustEVMRefreshWalletTarget]
    let groupedTargets: [WalletRustEVMGroupedTarget]
}

struct WalletRustDogecoinRefreshWalletInput: Encodable {
    let index: Int
    let walletID: String
    let selectedChain: String
    let addresses: [String]
}

struct WalletRustDogecoinRefreshTargetsRequest: Encodable {
    let wallets: [WalletRustDogecoinRefreshWalletInput]
    let allowedWalletIDs: [String]?
}

struct WalletRustDogecoinRefreshWalletTarget: Decodable {
    let index: Int
    let walletID: String
    let addresses: [String]
}

struct WalletRustWalletBalanceRefreshRequest: Encodable {
    let selectedChain: String
    let hasSeedPhrase: Bool
    let hasExtendedPublicKey: Bool
    let availableAddressKinds: [String]
}

struct WalletRustWalletBalanceRefreshPlan: Decodable {
    let serviceKind: String?
    let usesBulkRefresh: Bool
    let needsTrackedTokens: Bool
}

struct WalletRustSendAssetRoutingInput: Encodable {
    let chainName: String
    let symbol: String
    let isEVMChain: Bool
    let supportsSolanaSendCoin: Bool
}

struct WalletRustSendAssetRoutingPlan: Decodable {
    let previewKind: String?
    let submitKind: String?
    let nativeEVMSymbol: String?
    let isNativeEVMAsset: Bool
    let allowsZeroAmount: Bool
}

struct WalletRustSendPreviewRoutingRequest: Encodable {
    let asset: WalletRustSendAssetRoutingInput?
}

struct WalletRustSendPreviewRoutingPlan: Decodable {
    let activePreviewKind: String?
}

struct WalletRustSendSubmitPreflightRequest: Encodable {
    let walletFound: Bool
    let assetFound: Bool
    let destinationAddress: String
    let amountInput: String
    let availableBalance: Double
    let asset: WalletRustSendAssetRoutingInput?
}

struct WalletRustSendSubmitPreflightPlan: Decodable {
    let submitKind: String
    let previewKind: String?
    let normalizedDestinationAddress: String
    let amount: Double
    let chainName: String
    let symbol: String
    let nativeEVMSymbol: String?
    let isNativeEVMAsset: Bool
    let allowsZeroAmount: Bool
}

struct WalletRustUTXOEntry: Encodable {
    let index: Int
    let value: UInt64
}

struct WalletRustUTXOFeePolicy: Encodable {
    let chainName: String
    let feeModel: String
    let dustThreshold: UInt64
    let minimumRelayFeeRate: Double?
    let minimumAbsoluteFee: UInt64?
    let minimumRelayFeePerKB: Double?
    let baseUnitsPerCoin: Double?
    let maxStandardTransactionBytes: UInt64
    let inputBytes: Int?
    let outputBytes: Int?
    let overheadBytes: Int?
}

struct WalletRustUTXOPreviewRequest: Encodable {
    let inputs: [WalletRustUTXOEntry]
    let feeRate: Double
    let feePolicy: WalletRustUTXOFeePolicy
}

struct WalletRustUTXOPreviewPlan: Decodable {
    let estimatedTransactionBytes: Int
    let estimatedFee: UInt64
    let spendableValue: UInt64
    let inputCount: Int
}

struct WalletRustUTXOSpendPlanRequest: Encodable {
    let inputs: [WalletRustUTXOEntry]
    let targetValue: UInt64
    let feeRate: Double
    let feePolicy: WalletRustUTXOFeePolicy
    let maxInputCount: Int?
}

struct WalletRustUTXOSpendPlan: Decodable {
    let selectedIndices: [Int]
    let totalInputValue: UInt64
    let fee: UInt64
    let change: UInt64
    let usesChangeOutput: Bool
    let estimatedTransactionBytes: Int
}

struct WalletRustTransferHoldingInput: Encodable {
    let index: Int
    let chainName: String
    let symbol: String
    let supportsSend: Bool
    let supportsReceiveAddress: Bool
    let isLiveChain: Bool
    let supportsEVMToken: Bool
    let supportsSolanaSendCoin: Bool
}

struct WalletRustTransferWalletInput: Encodable {
    let walletID: String
    let hasSigningMaterial: Bool
    let holdings: [WalletRustTransferHoldingInput]
}

struct WalletRustTransferAvailabilityRequest: Encodable {
    let wallets: [WalletRustTransferWalletInput]
}

struct WalletRustWalletTransferAvailability: Decodable {
    let walletID: String
    let sendHoldingIndices: [Int]
    let receiveHoldingIndices: [Int]
    let receiveChains: [String]
}

struct WalletRustTransferAvailabilityPlan: Decodable {
    let wallets: [WalletRustWalletTransferAvailability]
    let sendEnabledWalletIDs: [String]
    let receiveEnabledWalletIDs: [String]
}

struct WalletRustCoreBootstrap: Decodable {
    struct Capabilities: Decodable {
        let schemaVersion: UInt32
        let supportsDerivation: Bool
        let supportsFetchContracts: Bool
        let supportsSendContracts: Bool
        let supportsStoreContracts: Bool
        let supportsLocalizationCatalogs: Bool
        let supportsStateReducer: Bool
        let supportedLocales: [String]
        let localizationTables: [String]
    }

    struct ChainSummary: Decodable {
        let chainName: String
        let curve: String
        let defaultNetwork: String?
        let defaultDerivationPath: String?
        let endpointCount: Int
        let settingsVisibleEndpointCount: Int
        let explorerEndpointCount: Int
    }

    struct LocalizationSummary: Decodable {
        let supportedLocales: [String]
        let tables: [String]
    }

    let capabilities: Capabilities
    let chains: [ChainSummary]
    let localization: LocalizationSummary
    let liveChainNames: [String]
}

private struct WalletRustFFIPathResolutionRequest {
    var chain: UInt32
    var derivationPathUTF8: WalletRustFFIBuffer
}

private struct WalletRustDerivationPathResolutionPayload: Decodable {
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: String
}

private struct WalletRustSeedDerivationPathsPayload: Decodable {
    let isCustomEnabled: Bool
    let bitcoin: String
    let bitcoinCash: String
    let bitcoinSV: String
    let litecoin: String
    let dogecoin: String
    let ethereum: String
    let ethereumClassic: String
    let arbitrum: String
    let optimism: String
    let avalanche: String
    let hyperliquid: String
    let tron: String
    let solana: String
    let stellar: String
    let xrp: String
    let cardano: String
    let sui: String
    let aptos: String
    let ton: String
    let internetComputer: String
    let near: String
    let polkadot: String

    var model: SeedDerivationPaths {
        SeedDerivationPaths(
            isCustomEnabled: isCustomEnabled,
            bitcoin: bitcoin,
            bitcoinCash: bitcoinCash,
            bitcoinSV: bitcoinSV,
            litecoin: litecoin,
            dogecoin: dogecoin,
            ethereum: ethereum,
            ethereumClassic: ethereumClassic,
            arbitrum: arbitrum,
            optimism: optimism,
            avalanche: avalanche,
            hyperliquid: hyperliquid,
            tron: tron,
            solana: solana,
            stellar: stellar,
            xrp: xrp,
            cardano: cardano,
            sui: sui,
            aptos: aptos,
            ton: ton,
            internetComputer: internetComputer,
            near: near,
            polkadot: polkadot
        )
    }
}

struct WalletRustResolvedDerivationPath {
    let chain: SeedDerivationChain
    let normalizedPath: String
    let accountIndex: UInt32
    let flavor: SeedDerivationFlavor
}

enum WalletRustAppCoreBridge {
    static func coreBootstrap() throws -> WalletRustCoreBootstrap {
        try decodePayload(WalletRustCoreBootstrap.self, json: try coreBootstrapJson())
    }

    static func localizedDocumentData(
        named resourceName: String,
        preferredLocales: [String]
    ) throws -> Data {
        let localesData = try JSONEncoder().encode(preferredLocales)
        guard let localesJSON = String(data: localesData, encoding: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Preferred locale payload was not valid UTF-8 JSON.")
        }
        return try decodeRawPayload(try coreLocalizationDocumentJson(resourceName: resourceName, preferredLocalesJson: localesJSON))
    }

    static func staticDocumentData(named resourceName: String) throws -> Data {
        try decodeRawPayload(try coreStaticResourceJson(resourceName: resourceName))
    }

    static func staticText(named resourceName: String) throws -> String {
        try coreStaticTextResourceUtf8(resourceName: resourceName)
    }

    static func reduceState<State: Encodable, Command: Encodable, Transition: Decodable>(
        state: State,
        command: Command,
        as type: Transition.Type
    ) throws -> Transition {
        try decodePayload(
            type,
            json: try coreReduceStateJson(
                stateJson: encodeJSONString(state),
                commandJson: encodeJSONString(command)
            )
        )
    }

    static func migrateLegacyWalletStoreData(_ data: Data) throws -> Data {
        try decodeJSONStringToData(try coreMigrateLegacyWalletStoreJson(requestJson: data.asJSONString()))
    }

    static func exportLegacyWalletStoreData(fromCoreStateData data: Data) throws -> Data {
        try decodeJSONStringToData(try coreExportLegacyWalletStoreJson(requestJson: data.asJSONString()))
    }

    static func buildPersistedSnapshotData(
        appStateData: Data,
        secretObservations: [WalletRustSecretObservation]
    ) throws -> Data {
        guard let appStateJSON = String(data: appStateData, encoding: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Core state payload was not valid UTF-8 JSON.")
        }
        let request = WalletRustPersistedSnapshotBuildRequest(
            appStateJSON: appStateJSON,
            secretObservations: secretObservations
        )
        return try decodeJSONStringToData(try coreBuildPersistedSnapshotJson(requestJson: encodeJSONString(request)))
    }

    static func walletSecretIndex(fromCoreSnapshotData data: Data) throws -> WalletRustWalletSecretIndex {
        try decodePayload(WalletRustWalletSecretIndex.self, json: try coreWalletSecretIndexJson(requestJson: data.asJSONString()))
    }

    static func planWalletImport(_ request: WalletRustImportPlanRequest) throws -> WalletRustImportPlan {
        try decodePayload(WalletRustImportPlan.self, json: try corePlanWalletImportJson(requestJson: encodeJSONString(request)))
    }

    static func activeMaintenancePlan(
        _ request: WalletRustActiveMaintenancePlanRequest
    ) throws -> WalletRustActiveMaintenancePlan {
        try sendCoreJSONRequest(request, decode: WalletRustActiveMaintenancePlan.self, invoke: coreActiveMaintenancePlanJson)
    }

    static func shouldRunBackgroundMaintenance(
        _ request: WalletRustBackgroundMaintenanceRequest
    ) throws -> Bool {
        try sendCoreJSONRequest(request, decode: Bool.self, invoke: coreShouldRunBackgroundMaintenanceJson)
    }

    static func chainRefreshPlans(
        _ request: WalletRustChainRefreshPlanRequest
    ) throws -> [WalletRustChainRefreshPlan] {
        try sendCoreJSONRequest(request, decode: [WalletRustChainRefreshPlan].self, invoke: coreChainRefreshPlansJson)
    }

    static func historyRefreshPlans(
        _ request: WalletRustHistoryRefreshPlanRequest
    ) throws -> [String] {
        try sendCoreJSONRequest(request, decode: [String].self, invoke: coreHistoryRefreshPlansJson)
    }

    static func normalizeHistory(
        _ request: WalletRustNormalizeHistoryRequest
    ) throws -> [WalletRustNormalizedHistoryEntry] {
        try sendCoreJSONRequest(request, decode: [WalletRustNormalizedHistoryEntry].self, invoke: coreNormalizeHistoryJson)
    }

    static func planEVMRefreshTargets(
        _ request: WalletRustEVMRefreshTargetsRequest
    ) throws -> WalletRustEVMRefreshPlan {
        try sendCoreJSONRequest(request, decode: WalletRustEVMRefreshPlan.self, invoke: corePlanEvmRefreshTargetsJson)
    }

    static func planDogecoinRefreshTargets(
        _ request: WalletRustDogecoinRefreshTargetsRequest
    ) throws -> [WalletRustDogecoinRefreshWalletTarget] {
        try sendCoreJSONRequest(request, decode: [WalletRustDogecoinRefreshWalletTarget].self, invoke: corePlanDogecoinRefreshTargetsJson)
    }

    static func planWalletBalanceRefresh(
        _ request: WalletRustWalletBalanceRefreshRequest
    ) throws -> WalletRustWalletBalanceRefreshPlan {
        try sendCoreJSONRequest(request, decode: WalletRustWalletBalanceRefreshPlan.self, invoke: corePlanWalletBalanceRefreshJson)
    }

    static func planTransferAvailability(
        _ request: WalletRustTransferAvailabilityRequest
    ) throws -> WalletRustTransferAvailabilityPlan {
        try sendCoreJSONRequest(request, decode: WalletRustTransferAvailabilityPlan.self, invoke: corePlanTransferAvailabilityJson)
    }

    static func routeSendAsset(
        _ request: WalletRustSendAssetRoutingInput
    ) throws -> WalletRustSendAssetRoutingPlan {
        try sendCoreJSONRequest(request, decode: WalletRustSendAssetRoutingPlan.self, invoke: coreRouteSendAssetJson)
    }

    static func planSendPreviewRouting(
        _ request: WalletRustSendPreviewRoutingRequest
    ) throws -> WalletRustSendPreviewRoutingPlan {
        try sendCoreJSONRequest(request, decode: WalletRustSendPreviewRoutingPlan.self, invoke: corePlanSendPreviewRoutingJson)
    }

    static func planSendSubmitPreflight(
        _ request: WalletRustSendSubmitPreflightRequest
    ) throws -> WalletRustSendSubmitPreflightPlan {
        try sendCoreJSONRequest(request, decode: WalletRustSendSubmitPreflightPlan.self, invoke: corePlanSendSubmitPreflightJson)
    }

    static func planUTXOPreview(
        _ request: WalletRustUTXOPreviewRequest
    ) throws -> WalletRustUTXOPreviewPlan {
        try sendCoreJSONRequest(request, decode: WalletRustUTXOPreviewPlan.self, invoke: corePlanUtxoPreviewJson)
    }

    static func planUTXOSpend(
        _ request: WalletRustUTXOSpendPlanRequest
    ) throws -> WalletRustUTXOSpendPlan {
        try sendCoreJSONRequest(request, decode: WalletRustUTXOSpendPlan.self, invoke: corePlanUtxoSpendJson)
    }

    static func mergeTransactions(
        _ request: WalletRustTransactionMergeRequest
    ) throws -> [WalletRustTransactionRecord] {
        try sendCoreJSONRequest(request, decode: [WalletRustTransactionRecord].self, invoke: coreMergeTransactionsJson)
    }

    static func chainPresets() throws -> [WalletDerivationChainPreset] {
        try decodePayload([WalletDerivationChainPreset].self, json: try appCoreChainPresetsJson())
    }

    static func requestCompilationPresets() throws -> [WalletDerivationRequestCompilationPreset] {
        try decodePayload([WalletDerivationRequestCompilationPreset].self, json: try appCoreRequestCompilationPresetsJson())
    }

    static func derivationPaths(for preset: SeedDerivationPreset?) throws -> SeedDerivationPaths {
        let accountIndex = preset?.accountIndex ?? 0
        let payload = try decodePayload(WalletRustSeedDerivationPathsPayload.self, json: try appCoreDerivationPathsForPresetJson(accountIndex: accountIndex))
        return payload.model
    }

    static func resolve(
        chain: SeedDerivationChain,
        path: String
    ) throws -> WalletRustResolvedDerivationPath {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else {
            throw WalletRustAppCoreBridgeError.rustCoreUnsupportedChain(chain.rawValue)
        }

        let payload = try decodePayload(
            WalletRustDerivationPathResolutionPayload.self,
            json: try appCoreResolveDerivationPathJson(chain: ffiChain.rawValue, derivationPath: path)
        )
        return WalletRustResolvedDerivationPath(
            chain: payload.chain,
            normalizedPath: payload.normalizedPath,
            accountIndex: payload.accountIndex,
            flavor: SeedDerivationFlavor(rawValue: payload.flavor) ?? .standard
        )
    }

    private static func decodePayload<T: Decodable>(
        _ type: T.Type,
        json: String
    ) throws -> T {
        guard let payload = json.data(using: .utf8), !payload.isEmpty else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core returned an empty payload.")
        }
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw WalletRustAppCoreBridgeError.invalidPayload(error.localizedDescription)
        }
    }

    private static func decodeRawPayload(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core returned an empty payload.")
        }
        return payload
    }

    private static func sendCoreJSONRequest<Request: Encodable, Response: Decodable>(
        _ request: Request,
        decode responseType: Response.Type,
        invoke: @escaping (String) throws -> String
    ) throws -> Response {
        try decodePayload(responseType, json: try invoke(encodeJSONString(request)))
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Encoded request was not valid UTF-8 JSON.")
        }
        return json
    }

    private static func decodeJSONStringToData(_ json: String) throws -> Data {
        guard let data = json.data(using: .utf8) else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core payload was not valid UTF-8.")
        }
        return data
    }

    private static func string(from buffer: WalletRustFFIBuffer) -> String? {
        guard let data = data(from: buffer) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func data(from buffer: WalletRustFFIBuffer) -> Data? {
        guard let ptr = buffer.ptr, buffer.len > 0 else {
            return nil
        }
        return Data(bytes: ptr, count: buffer.len)
    }
}
