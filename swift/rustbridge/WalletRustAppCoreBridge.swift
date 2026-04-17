import Foundation

enum WalletRustAppCoreBridgeError: LocalizedError {
    case rustCoreUnsupportedChain(String)
    var errorDescription: String? {
        switch self {
        case .rustCoreUnsupportedChain(let chain): return "The Rust app core does not support \(chain) yet."
        }
    }
}

enum WalletRustAppCoreBridge {

    // ─── Typed bridge functions (pass-through to UniFFI exports) ─────────────

    static func planWalletImport(_ request: WalletImportRequest) throws -> WalletImportPlan {
        try corePlanWalletImport(request: request)
    }

    static func activeMaintenancePlan(_ request: ActiveMaintenancePlanRequest) -> ActiveMaintenancePlan {
        coreActiveMaintenancePlan(request: request)
    }

    static func shouldRunBackgroundMaintenance(_ request: BackgroundMaintenanceRequest) -> Bool {
        coreShouldRunBackgroundMaintenance(request: request)
    }

    static func chainRefreshPlans(_ request: ChainRefreshPlanRequest) -> [ChainRefreshPlan] {
        coreChainRefreshPlans(request: request)
    }

    static func historyRefreshPlans(_ request: HistoryRefreshPlanRequest) -> [String] {
        coreHistoryRefreshPlans(request: request)
    }

    static func normalizeHistory(_ request: NormalizeHistoryRequest) -> [CoreNormalizedHistoryEntry] {
        coreNormalizeHistory(request: request)
    }

    static func mergeBitcoinHistorySnapshots(_ request: MergeBitcoinHistorySnapshotsRequest) -> [CoreBitcoinHistorySnapshot] {
        coreMergeBitcoinHistorySnapshots(request: request)
    }

    static func planEVMRefreshTargets(_ request: EvmRefreshTargetsRequest) -> EvmRefreshPlan {
        corePlanEvmRefreshTargets(request: request)
    }

    static func planDogecoinRefreshTargets(_ request: DogecoinRefreshTargetsRequest) -> [DogecoinRefreshWalletTarget] {
        corePlanDogecoinRefreshTargets(request: request)
    }

    static func planTransferAvailability(_ request: TransferAvailabilityRequest) -> TransferAvailabilityPlan {
        corePlanTransferAvailability(request: request)
    }

    static func planStoreDerivedState(_ request: StoreDerivedStateRequest) -> StoreDerivedStatePlan {
        corePlanStoreDerivedState(request: request)
    }

    static func aggregateOwnedAddresses(_ request: OwnedAddressAggregationRequest) -> [String] {
        coreAggregateOwnedAddresses(request: request)
    }

    static func planReceiveSelection(_ request: ReceiveSelectionRequest) -> ReceiveSelectionPlan {
        corePlanReceiveSelection(request: request)
    }

    static func planSelfSendConfirmation(_ request: SelfSendConfirmationRequest) -> SelfSendConfirmationPlan {
        corePlanSelfSendConfirmation(request: request)
    }

    static func planSendPreviewRouting(_ request: SendPreviewRoutingRequest) -> SendPreviewRoutingPlan {
        corePlanSendPreviewRouting(request: request)
    }

    static func planSendSubmitPreflight(_ request: SendSubmitPreflightRequest) throws -> SendSubmitPreflightPlan {
        try corePlanSendSubmitPreflight(request: request)
    }

    static func mergeTransactions(_ request: TransactionMergeRequest) -> [CoreTransactionRecord] {
        coreMergeTransactions(request: request)
    }

    static func encodeHistoryRecordsJSON(_ records: [HistoryRecordEncodeInput]) throws -> String {
        try coreEncodeHistoryRecordsJson(records: records)
    }

    // ─── Derivation bridge (unchanged — calls derivation FFI, not core) ────────

    static func chainPresets() throws -> [WalletDerivationChainPreset] {
        try appCoreChainPresets().map { preset in
            WalletDerivationChainPreset(
                chain: SeedDerivationChain(rawValue: preset.chain)!,
                curve: WalletDerivationCurve(rawValue: preset.curve)!,
                networks: preset.networks.map { n in
                    WalletDerivationNetworkPreset(
                        network: WalletDerivationNetwork(rawValue: n.network)!,
                        title: n.title, detail: n.detail, isDefault: n.isDefault
                    )
                },
                derivationPaths: preset.derivationPaths.map { p in
                    WalletDerivationPathPreset(
                        title: p.title, detail: p.detail,
                        derivationPath: p.derivationPath, isDefault: p.isDefault
                    )
                }
            )
        }
    }

    static func requestCompilationPresets() throws -> [WalletDerivationRequestCompilationPreset] {
        try appCoreRequestCompilationPresets().map { preset in
            WalletDerivationRequestCompilationPreset(
                chain: SeedDerivationChain(rawValue: preset.chain)!,
                derivationAlgorithm: WalletDerivationRequestDerivationAlgorithmPreset(rawValue: preset.derivationAlgorithm)!,
                addressAlgorithm: WalletDerivationRequestAddressAlgorithmPreset(rawValue: preset.addressAlgorithm)!,
                publicKeyFormat: WalletDerivationRequestPublicKeyFormatPreset(rawValue: preset.publicKeyFormat)!,
                scriptPolicy: WalletDerivationRequestScriptPolicyPreset(rawValue: preset.scriptPolicy)!,
                fixedScriptType: preset.fixedScriptType.flatMap { WalletDerivationRequestScriptTypePreset(rawValue: $0) },
                bitcoinPurposeScriptMap: preset.bitcoinPurposeScriptMap.map { dict in
                    dict.compactMapValues { WalletDerivationRequestScriptTypePreset(rawValue: $0) }
                }
            )
        }
    }

    static func derivationPaths(for preset: SeedDerivationPreset?) throws -> SeedDerivationPaths {
        try appCoreDerivationPathsForPreset(accountIndex: preset?.accountIndex ?? 0)
    }

    static func resolve(chain: SeedDerivationChain, path: String) throws -> WalletRustResolvedDerivationPath {
        guard let ffiChain = WalletRustFFIChain(chain: chain) else {
            throw WalletRustAppCoreBridgeError.rustCoreUnsupportedChain(chain.rawValue)
        }
        let resolution = try appCoreResolveDerivationPath(chain: ffiChain.rawValue, derivationPath: path)
        return WalletRustResolvedDerivationPath(
            chain: SeedDerivationChain(rawValue: resolution.chain)!,
            normalizedPath: resolution.normalizedPath,
            accountIndex: resolution.accountIndex,
            flavor: SeedDerivationFlavor(rawValue: resolution.flavor) ?? .standard
        )
    }

}
