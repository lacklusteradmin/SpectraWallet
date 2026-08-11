import Foundation

// Swift owns only file I/O and data collection. All struct definitions,
// serialization, and deserialization live in Rust (`core/src/diagnostics/export.rs`).
//
// `DiagnosticsBundlePayload` and `DiagnosticsEnvironmentMetadata` are UniFFI
// records — Swift sees them as plain structs via the generated bindings.

private protocol SimpleAddressHistoryDiag {
    var address: String { get }
    var sourceUsed: String { get }
    var transactionCount: Int32 { get }
    var error: String? { get }
}
extension CardanoHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension XrpHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension StellarHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension MoneroHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension SuiHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension AptosHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension TonHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension IcpHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension NearHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension PolkadotHistoryDiagnostics: SimpleAddressHistoryDiag {}


private func simpleEntries<T: SimpleAddressHistoryDiag>(_ dict: [String: T]) -> [SimpleAddressHistoryEntry] {
    dict.map {
        SimpleAddressHistoryEntry(
            walletId: $0.key, address: $0.value.address, sourceUsed: $0.value.sourceUsed,
            transactionCount: $0.value.transactionCount, error: $0.value.error)
    }
}

extension AppState {

    // MARK: Per-chain JSON helpers (used by DiagnosticsViews)

    private func utxoJSON(
        history: [String: BitcoinHistoryDiagnostics],
        endpoints: [EndpointHealthRow],
        historyUpdatedAt: Date?,
        endpointsUpdatedAt: Date?,
        mode: String? = nil
    ) -> String? {
        diagnosticsBuildUtxoJson(
            history: Array(history.values), endpoints: endpoints,
            historyLastUpdatedAtUnix: historyUpdatedAt?.timeIntervalSince1970,
            endpointsLastUpdatedAtUnix: endpointsUpdatedAt?.timeIntervalSince1970,
            extraNetworkMode: mode)
    }
    private func evmJSON(
        history: [String: EthereumTokenTransferHistoryDiagnostics],
        endpoints: [EvmEndpointHealthRow],
        historyUpdatedAt: Date?,
        endpointsUpdatedAt: Date?
    ) -> String? {
        diagnosticsBuildEvmJson(
            history: history.map { EvmHistoryEntry(walletId: $0.key, diagnostics: $0.value) },
            endpoints: endpoints,
            historyLastUpdatedAtUnix: historyUpdatedAt?.timeIntervalSince1970,
            endpointsLastUpdatedAtUnix: endpointsUpdatedAt?.timeIntervalSince1970)
    }
    private func simpleJSON<T: SimpleAddressHistoryDiag>(
        history: [String: T],
        endpoints: [EndpointHealthRow],
        historyUpdatedAt: Date?,
        endpointsUpdatedAt: Date?
    ) -> String? {
        diagnosticsBuildSimpleAddressJson(
            history: simpleEntries(history), endpoints: endpoints,
            historyLastUpdatedAtUnix: historyUpdatedAt?.timeIntervalSince1970,
            endpointsLastUpdatedAtUnix: endpointsUpdatedAt?.timeIntervalSince1970)
    }

    func bitcoinDiagnosticsJSON() -> String? {
        utxoJSON(
            history: bitcoinHistoryDiagnosticsByWallet, endpoints: bitcoinEndpointHealthResults,
            historyUpdatedAt: bitcoinHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: bitcoinEndpointHealthLastUpdatedAt, mode: bitcoinNetworkMode.rawValue)
    }
    func dogecoinDiagnosticsJSON() -> String? {
        utxoJSON(
            history: dogecoinHistoryDiagnosticsByWallet, endpoints: dogecoinEndpointHealthResults,
            historyUpdatedAt: dogecoinHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: dogecoinEndpointHealthLastUpdatedAt)
    }
    func bitcoinCashDiagnosticsJSON() -> String? {
        utxoJSON(
            history: bitcoinCashHistoryDiagnosticsByWallet, endpoints: bitcoinCashEndpointHealthResults,
            historyUpdatedAt: bitcoinCashHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: bitcoinCashEndpointHealthLastUpdatedAt)
    }
    func bitcoinSVDiagnosticsJSON() -> String? {
        utxoJSON(
            history: bitcoinSVHistoryDiagnosticsByWallet, endpoints: bitcoinSVEndpointHealthResults,
            historyUpdatedAt: bitcoinSVHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: bitcoinSVEndpointHealthLastUpdatedAt)
    }
    func litecoinDiagnosticsJSON() -> String? {
        utxoJSON(
            history: litecoinHistoryDiagnosticsByWallet, endpoints: litecoinEndpointHealthResults,
            historyUpdatedAt: litecoinHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: litecoinEndpointHealthLastUpdatedAt)
    }
    func ethereumDiagnosticsJSON() -> String? {
        evmJSON(
            history: ethereumHistoryDiagnosticsByWallet, endpoints: ethereumEndpointHealthResults,
            historyUpdatedAt: ethereumHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: ethereumEndpointHealthLastUpdatedAt)
    }
    func etcDiagnosticsJSON() -> String? {
        evmJSON(
            history: etcHistoryDiagnosticsByWallet, endpoints: etcEndpointHealthResults,
            historyUpdatedAt: etcHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: etcEndpointHealthLastUpdatedAt)
    }
    func arbitrumDiagnosticsJSON() -> String? {
        evmJSON(
            history: arbitrumHistoryDiagnosticsByWallet, endpoints: arbitrumEndpointHealthResults,
            historyUpdatedAt: arbitrumHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: arbitrumEndpointHealthLastUpdatedAt)
    }
    func optimismDiagnosticsJSON() -> String? {
        evmJSON(
            history: optimismHistoryDiagnosticsByWallet, endpoints: optimismEndpointHealthResults,
            historyUpdatedAt: optimismHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: optimismEndpointHealthLastUpdatedAt)
    }
    func bnbDiagnosticsJSON() -> String? {
        evmJSON(
            history: bnbHistoryDiagnosticsByWallet, endpoints: bnbEndpointHealthResults,
            historyUpdatedAt: bnbHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: bnbEndpointHealthLastUpdatedAt)
    }
    func avalancheDiagnosticsJSON() -> String? {
        evmJSON(
            history: avalancheHistoryDiagnosticsByWallet, endpoints: avalancheEndpointHealthResults,
            historyUpdatedAt: avalancheHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: avalancheEndpointHealthLastUpdatedAt)
    }
    func hyperliquidDiagnosticsJSON() -> String? {
        evmJSON(
            history: hyperliquidHistoryDiagnosticsByWallet, endpoints: hyperliquidEndpointHealthResults,
            historyUpdatedAt: hyperliquidHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: hyperliquidEndpointHealthLastUpdatedAt)
    }
    func tronDiagnosticsJSON() -> String? {
        diagnosticsBuildTronJson(
            history: tronHistoryDiagnosticsByWallet.map { TronHistoryEntry(walletId: $0.key, diagnostics: $0.value) },
            endpoints: tronEndpointHealthResults,
            historyLastUpdatedAtUnix: tronHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970,
            endpointsLastUpdatedAtUnix: tronEndpointHealthLastUpdatedAt?.timeIntervalSince1970,
            lastSendErrorAtUnix: tronLastSendErrorAt?.timeIntervalSince1970, lastSendErrorDetails: tronLastSendErrorDetails)
    }
    func solanaDiagnosticsJSON() -> String? {
        diagnosticsBuildSolanaJson(
            history: solanaHistoryDiagnosticsByWallet.map { SolanaHistoryEntry(walletId: $0.key, diagnostics: $0.value) },
            endpoints: solanaEndpointHealthResults,
            historyLastUpdatedAtUnix: solanaHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970,
            endpointsLastUpdatedAtUnix: solanaEndpointHealthLastUpdatedAt?.timeIntervalSince1970)
    }
    func stellarDiagnosticsJSON() -> String? {
        simpleJSON(
            history: stellarHistoryDiagnosticsByWallet, endpoints: stellarEndpointHealthResults,
            historyUpdatedAt: stellarHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: stellarEndpointHealthLastUpdatedAt)
    }
    func cardanoDiagnosticsJSON() -> String? {
        simpleJSON(
            history: cardanoHistoryDiagnosticsByWallet, endpoints: cardanoEndpointHealthResults,
            historyUpdatedAt: cardanoHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: cardanoEndpointHealthLastUpdatedAt)
    }
    func xrpDiagnosticsJSON() -> String? {
        simpleJSON(
            history: xrpHistoryDiagnosticsByWallet, endpoints: xrpEndpointHealthResults,
            historyUpdatedAt: xrpHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: xrpEndpointHealthLastUpdatedAt)
    }
    func moneroDiagnosticsJSON() -> String? {
        simpleJSON(
            history: moneroHistoryDiagnosticsByWallet, endpoints: moneroEndpointHealthResults,
            historyUpdatedAt: moneroHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: moneroEndpointHealthLastUpdatedAt)
    }
    func suiDiagnosticsJSON() -> String? {
        simpleJSON(
            history: suiHistoryDiagnosticsByWallet, endpoints: suiEndpointHealthResults,
            historyUpdatedAt: suiHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: suiEndpointHealthLastUpdatedAt)
    }
    func aptosDiagnosticsJSON() -> String? {
        simpleJSON(
            history: aptosHistoryDiagnosticsByWallet, endpoints: aptosEndpointHealthResults,
            historyUpdatedAt: aptosHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: aptosEndpointHealthLastUpdatedAt)
    }
    func tonDiagnosticsJSON() -> String? {
        simpleJSON(
            history: tonHistoryDiagnosticsByWallet, endpoints: tonEndpointHealthResults,
            historyUpdatedAt: tonHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: tonEndpointHealthLastUpdatedAt)
    }
    func icpDiagnosticsJSON() -> String? {
        simpleJSON(
            history: icpHistoryDiagnosticsByWallet, endpoints: icpEndpointHealthResults,
            historyUpdatedAt: icpHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: icpEndpointHealthLastUpdatedAt)
    }
    func nearDiagnosticsJSON() -> String? {
        simpleJSON(
            history: nearHistoryDiagnosticsByWallet, endpoints: nearEndpointHealthResults,
            historyUpdatedAt: nearHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: nearEndpointHealthLastUpdatedAt)
    }
    func polkadotDiagnosticsJSON() -> String? {
        simpleJSON(
            history: polkadotHistoryDiagnosticsByWallet, endpoints: polkadotEndpointHealthResults,
            historyUpdatedAt: polkadotHistoryDiagnosticsLastUpdatedAt,
            endpointsUpdatedAt: polkadotEndpointHealthLastUpdatedAt)
    }

    // MARK: Bundle construction (Rust-owned struct, Swift fills it in)

    private func buildDiagnosticsBundle() -> DiagnosticsBundlePayload {
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = DiagnosticsEnvironmentMetadata(
            appVersion: (info["CFBundleShortVersionString"] as? String) ?? "unknown",
            buildNumber: (info["CFBundleVersion"] as? String) ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier,
            pricingProvider: pricingProvider.rawValue,
            selectedFiatCurrency: selectedFiatCurrency.rawValue,
            walletCount: Int64(wallets.count),
            transactionCount: Int64(transactions.count))
        return DiagnosticsBundlePayload(
            schemaVersion: 1,
            generatedAt: Date().timeIntervalSince1970,
            environment: environment,
            chainDegradedMessages: diagnostics.chainDegradedMessages,
            chainDiagnosticsJson: DiagnosticsBundlePayload.chainKeyed([
                "Bitcoin": bitcoinDiagnosticsJSON(),
                "Dogecoin": dogecoinDiagnosticsJSON(),
                "Bitcoin Cash": bitcoinCashDiagnosticsJSON(),
                "Bitcoin SV": bitcoinSVDiagnosticsJSON(),
                "Litecoin": litecoinDiagnosticsJSON(),
                "Ethereum": ethereumDiagnosticsJSON(),
                "Ethereum Classic": etcDiagnosticsJSON(),
                "Arbitrum": arbitrumDiagnosticsJSON(),
                "Optimism": optimismDiagnosticsJSON(),
                "BNB Chain": bnbDiagnosticsJSON(),
                "Avalanche": avalancheDiagnosticsJSON(),
                "Hyperliquid": hyperliquidDiagnosticsJSON(),
                "Tron": tronDiagnosticsJSON(),
                "Solana": solanaDiagnosticsJSON(),
                "Stellar": stellarDiagnosticsJSON(),
                "Cardano": cardanoDiagnosticsJSON(),
                "XRP Ledger": xrpDiagnosticsJSON(),
                "Monero": moneroDiagnosticsJSON(),
                "Sui": suiDiagnosticsJSON(),
                "Aptos": aptosDiagnosticsJSON(),
                "TON": tonDiagnosticsJSON(),
                "Internet Computer": icpDiagnosticsJSON(),
                "NEAR": nearDiagnosticsJSON(),
                "Polkadot": polkadotDiagnosticsJSON(),
            ]))
    }

    // MARK: File I/O

    func exportDiagnosticsBundle() throws -> URL {
        let payload = buildDiagnosticsBundle()
        guard let json = diagnosticsBundleToJson(payload: payload) else {
            throw DiagnosticsBundleError.serializationFailed
        }
        guard let data = json.data(using: .utf8) else {
            throw DiagnosticsBundleError.serializationFailed
        }
        let stamp = Self.exportFilenameTimestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = try diagnosticsBundleExportsDirectoryURL()
            .appendingPathComponent("spectra-diagnostics-\(stamp)")
            .appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
    func diagnosticsBundleExportsDirectoryURL() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Diagnostics Bundles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    func diagnosticsBundleExportURLs() -> [URL] {
        guard let directory = try? diagnosticsBundleExportsDirectoryURL(),
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "json" }.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
    }
    func deleteDiagnosticsBundleExport(at url: URL) throws { try FileManager.default.removeItem(at: url) }
    @discardableResult
    func importDiagnosticsBundle(from url: URL) throws -> DiagnosticsBundlePayload {
        let data = try Data(contentsOf: url)
        guard let json = String(data: data, encoding: .utf8),
            let payload = diagnosticsBundleFromJson(json: json)
        else { throw DiagnosticsBundleError.invalidBundle }
        lastImportedDiagnosticsBundle = payload
        return payload
    }
}

enum DiagnosticsBundleError: Error {
    case serializationFailed
    case invalidBundle
}

extension DiagnosticsBundlePayload {
    var generatedAtDate: Date { Date(timeIntervalSince1970: generatedAt) }

    /// Fold a chain-display-name → JSON table into the chain-id-keyed map,
    /// substituting `"{}"` for chains with no data. Ids come from the Rust
    /// registry, so the bundle keys stay canonical.
    static func chainKeyed(_ byChainName: [String: String?]) -> [String: String] {
        var byChainID: [String: String] = [:]
        for (chainName, json) in byChainName {
            let id = coreResolveChainId(input: chainName)
            guard !id.isEmpty else { continue }
            byChainID[id] = json ?? "{}"
        }
        return byChainID
    }

    /// Diagnostics JSON for a chain, by display name.
    func diagnosticsJSON(forChainNamed chainName: String) -> String? {
        chainDiagnosticsJson[coreResolveChainId(input: chainName)]
    }
}
