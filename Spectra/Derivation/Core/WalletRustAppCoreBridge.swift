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

@_silgen_name("spectra_app_core_chain_presets_json")
private func spectra_app_core_chain_presets_json() -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_request_compilation_presets_json")
private func spectra_app_core_request_compilation_presets_json() -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_resolve_derivation_path_json")
private func spectra_app_core_resolve_derivation_path_json(
    _ request: UnsafePointer<WalletRustFFIPathResolutionRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_derivation_paths_for_preset_json")
private func spectra_app_core_derivation_paths_for_preset_json(
    _ accountIndex: UInt32
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_json_response_free")
private func spectra_app_core_json_response_free(
    _ response: UnsafeMutablePointer<WalletRustFFIJSONResponse>?
)

@_silgen_name("spectra_core_bootstrap_json")
private func spectra_core_bootstrap_json() -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_localization_document_json")
private func spectra_core_localization_document_json(
    _ request: UnsafePointer<WalletRustFFICoreLocalizationDocumentRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_reduce_state_json")
private func spectra_core_reduce_state_json(
    _ request: UnsafePointer<WalletRustFFICoreStateReduceRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_migrate_legacy_wallet_store_json")
private func spectra_core_migrate_legacy_wallet_store_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_export_legacy_wallet_store_json")
private func spectra_core_export_legacy_wallet_store_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_plan_wallet_import_json")
private func spectra_core_plan_wallet_import_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_active_maintenance_plan_json")
private func spectra_core_active_maintenance_plan_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_should_run_background_maintenance_json")
private func spectra_core_should_run_background_maintenance_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_chain_refresh_plans_json")
private func spectra_core_chain_refresh_plans_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_history_refresh_plans_json")
private func spectra_core_history_refresh_plans_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_normalize_history_json")
private func spectra_core_normalize_history_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_merge_transactions_json")
private func spectra_core_merge_transactions_json(
    _ request: UnsafePointer<WalletRustFFICoreJSONRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_core_json_response_free")
private func spectra_core_json_response_free(
    _ response: UnsafeMutablePointer<WalletRustFFIJSONResponse>?
)

enum WalletRustAppCoreBridge {
    static func coreBootstrap() throws -> WalletRustCoreBootstrap {
        try decodePayload(
            WalletRustCoreBootstrap.self,
            invoke: spectra_core_bootstrap_json,
            free: spectra_core_json_response_free
        )
    }

    static func localizedDocumentData(
        named resourceName: String,
        preferredLocales: [String]
    ) throws -> Data {
        let preferredLocalesData = try JSONEncoder().encode(preferredLocales)
        let resourceNameUTF8 = Array(resourceName.utf8)
        let preferredLocalesUTF8 = Array(preferredLocalesData)

        return try resourceNameUTF8.withUnsafeBufferPointer { resourceNameBuffer in
            try preferredLocalesUTF8.withUnsafeBufferPointer { preferredLocalesBuffer in
                var request = WalletRustFFICoreLocalizationDocumentRequest(
                    resourceNameUTF8: WalletRustFFIBuffer(
                        ptr: UnsafeMutablePointer(mutating: resourceNameBuffer.baseAddress),
                        len: resourceNameBuffer.count
                    ),
                    preferredLocalesJSONUTF8: WalletRustFFIBuffer(
                        ptr: UnsafeMutablePointer(mutating: preferredLocalesBuffer.baseAddress),
                        len: preferredLocalesBuffer.count
                    )
                )
                return try decodeRawPayload(
                    invoke: {
                        withUnsafePointer(to: &request) { pointer in
                            spectra_core_localization_document_json(pointer)
                        }
                    },
                    free: spectra_core_json_response_free
                )
            }
        }
    }

    static func reduceState<State: Encodable, Command: Encodable, Transition: Decodable>(
        state: State,
        command: Command,
        as type: Transition.Type
    ) throws -> Transition {
        let stateData = try JSONEncoder().encode(state)
        let commandData = try JSONEncoder().encode(command)
        let stateUTF8 = Array(stateData)
        let commandUTF8 = Array(commandData)

        return try stateUTF8.withUnsafeBufferPointer { stateBuffer in
            try commandUTF8.withUnsafeBufferPointer { commandBuffer in
                var request = WalletRustFFICoreStateReduceRequest(
                    stateJSONUTF8: WalletRustFFIBuffer(
                        ptr: UnsafeMutablePointer(mutating: stateBuffer.baseAddress),
                        len: stateBuffer.count
                    ),
                    commandJSONUTF8: WalletRustFFIBuffer(
                        ptr: UnsafeMutablePointer(mutating: commandBuffer.baseAddress),
                        len: commandBuffer.count
                    )
                )
                return try decodePayload(
                    type,
                    invoke: {
                        withUnsafePointer(to: &request) { pointer in
                            spectra_core_reduce_state_json(pointer)
                        }
                    },
                    free: spectra_core_json_response_free
                )
            }
        }
    }

    static func migrateLegacyWalletStoreData(_ data: Data) throws -> Data {
        try withCoreJSONRequest(data) { request in
            try decodeRawPayload(
                invoke: { spectra_core_migrate_legacy_wallet_store_json(request) },
                free: spectra_core_json_response_free
            )
        }
    }

    static func exportLegacyWalletStoreData(fromCoreStateData data: Data) throws -> Data {
        try withCoreJSONRequest(data) { request in
            try decodeRawPayload(
                invoke: { spectra_core_export_legacy_wallet_store_json(request) },
                free: spectra_core_json_response_free
            )
        }
    }

    static func planWalletImport(_ request: WalletRustImportPlanRequest) throws -> WalletRustImportPlan {
        let data = try JSONEncoder().encode(request)
        return try withCoreJSONRequest(data) { requestPointer in
            try decodePayload(
                WalletRustImportPlan.self,
                invoke: { spectra_core_plan_wallet_import_json(requestPointer) },
                free: spectra_core_json_response_free
            )
        }
    }

    static func activeMaintenancePlan(
        _ request: WalletRustActiveMaintenancePlanRequest
    ) throws -> WalletRustActiveMaintenancePlan {
        try sendCoreJSONRequest(request, decode: WalletRustActiveMaintenancePlan.self, invoke: spectra_core_active_maintenance_plan_json)
    }

    static func shouldRunBackgroundMaintenance(
        _ request: WalletRustBackgroundMaintenanceRequest
    ) throws -> Bool {
        try sendCoreJSONRequest(request, decode: Bool.self, invoke: spectra_core_should_run_background_maintenance_json)
    }

    static func chainRefreshPlans(
        _ request: WalletRustChainRefreshPlanRequest
    ) throws -> [WalletRustChainRefreshPlan] {
        try sendCoreJSONRequest(request, decode: [WalletRustChainRefreshPlan].self, invoke: spectra_core_chain_refresh_plans_json)
    }

    static func historyRefreshPlans(
        _ request: WalletRustHistoryRefreshPlanRequest
    ) throws -> [String] {
        try sendCoreJSONRequest(request, decode: [String].self, invoke: spectra_core_history_refresh_plans_json)
    }

    static func normalizeHistory(
        _ request: WalletRustNormalizeHistoryRequest
    ) throws -> [WalletRustNormalizedHistoryEntry] {
        try sendCoreJSONRequest(request, decode: [WalletRustNormalizedHistoryEntry].self, invoke: spectra_core_normalize_history_json)
    }

    static func mergeTransactions(
        _ request: WalletRustTransactionMergeRequest
    ) throws -> [WalletRustTransactionRecord] {
        try sendCoreJSONRequest(request, decode: [WalletRustTransactionRecord].self, invoke: spectra_core_merge_transactions_json)
    }

    static func chainPresets() throws -> [WalletDerivationChainPreset] {
        try decodePayload(
            [WalletDerivationChainPreset].self,
            invoke: spectra_app_core_chain_presets_json
        )
    }

    static func requestCompilationPresets() throws -> [WalletDerivationRequestCompilationPreset] {
        try decodePayload(
            [WalletDerivationRequestCompilationPreset].self,
            invoke: spectra_app_core_request_compilation_presets_json
        )
    }

    static func derivationPaths(for preset: SeedDerivationPreset?) throws -> SeedDerivationPaths {
        let accountIndex = preset?.accountIndex ?? 0
        let payload = try decodePayload(
            WalletRustSeedDerivationPathsPayload.self,
            invoke: { spectra_app_core_derivation_paths_for_preset_json(accountIndex) }
        )
        return payload.model
    }

    static func resolve(
        chain: SeedDerivationChain,
        path: String
    ) throws -> WalletRustResolvedDerivationPath {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else {
            throw WalletRustAppCoreBridgeError.rustCoreUnsupportedChain(chain.rawValue)
        }

        let requestData = Array(path.utf8)
        return try requestData.withUnsafeBufferPointer { buffer in
            var request = WalletRustFFIPathResolutionRequest(
                chain: ffiChain.rawValue,
                derivationPathUTF8: WalletRustFFIBuffer(
                    ptr: UnsafeMutablePointer(mutating: buffer.baseAddress),
                    len: buffer.count
                )
            )
            let payload = try decodePayload(
                WalletRustDerivationPathResolutionPayload.self,
                invoke: {
                    withUnsafePointer(to: &request) { pointer in
                        spectra_app_core_resolve_derivation_path_json(pointer)
                    }
                }
            )
            return WalletRustResolvedDerivationPath(
                chain: payload.chain,
                normalizedPath: payload.normalizedPath,
                accountIndex: payload.accountIndex,
                flavor: SeedDerivationFlavor(rawValue: payload.flavor) ?? .standard
            )
        }
    }

    private static func decodePayload<T: Decodable>(
        _ type: T.Type,
        invoke: () -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?,
        free: (UnsafeMutablePointer<WalletRustFFIJSONResponse>?) -> Void = spectra_app_core_json_response_free
    ) throws -> T {
        let payload = try decodeRawPayload(invoke: invoke, free: free)
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw WalletRustAppCoreBridgeError.invalidPayload(error.localizedDescription)
        }
    }

    private static func decodeRawPayload(
        invoke: () -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?,
        free: (UnsafeMutablePointer<WalletRustFFIJSONResponse>?) -> Void
    ) throws -> Data {
        guard let responsePointer = invoke() else {
            throw WalletRustAppCoreBridgeError.rustCoreReturnedNullResponse
        }
        defer {
            free(responsePointer)
        }

        let response = responsePointer.pointee
        if response.statusCode != 0 {
            let message = string(from: response.errorMessageUTF8) ?? "Rust app core request failed."
            throw WalletRustAppCoreBridgeError.rustCoreFailed(message)
        }

        guard let payload = data(from: response.payloadUTF8), !payload.isEmpty else {
            throw WalletRustAppCoreBridgeError.invalidPayload("Rust app core returned an empty payload.")
        }
        return payload
    }

    private static func withCoreJSONRequest<T>(
        _ data: Data,
        body: (UnsafePointer<WalletRustFFICoreJSONRequest>) throws -> T
    ) rethrows -> T {
        let bytes = Array(data)
        return try bytes.withUnsafeBufferPointer { buffer in
            var request = WalletRustFFICoreJSONRequest(
                jsonUTF8: WalletRustFFIBuffer(
                    ptr: UnsafeMutablePointer(mutating: buffer.baseAddress),
                    len: buffer.count
                )
            )
            return try withUnsafePointer(to: &request, body)
        }
    }

    private static func sendCoreJSONRequest<Request: Encodable, Response: Decodable>(
        _ request: Request,
        decode responseType: Response.Type,
        invoke: @escaping (UnsafePointer<WalletRustFFICoreJSONRequest>?) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?
    ) throws -> Response {
        let data = try JSONEncoder().encode(request)
        return try withCoreJSONRequest(data) { requestPointer in
            try decodePayload(
                responseType,
                invoke: { invoke(requestPointer) },
                free: spectra_core_json_response_free
            )
        }
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
