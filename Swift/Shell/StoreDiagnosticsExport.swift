import Foundation
private protocol SimpleAddressHistoryDiag {
    var address: String { get }
    var sourceUsed: String { get }
    var transactionCount: Int32 { get }
    var error: String? { get }
}
extension CardanoHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension XRPHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension StellarHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension MoneroHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension SuiHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension AptosHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension TONHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension ICPHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension NearHistoryDiagnostics: SimpleAddressHistoryDiag {}
extension PolkadotHistoryDiagnostics: SimpleAddressHistoryDiag {}

private func rustRow(_ r: BitcoinEndpointHealthResult) -> EndpointHealthRow {
    EndpointHealthRow(endpoint: r.endpoint, reachable: r.reachable, statusCode: r.statusCode.map { Int32($0) }, detail: r.detail)
}
private func rustRow(_ r: EthereumEndpointHealthResult) -> EvmEndpointHealthRow {
    EvmEndpointHealthRow(label: r.label, endpoint: r.endpoint, reachable: r.reachable, statusCode: r.statusCode.map { Int32($0) }, detail: r.detail)
}
private func simpleEntries<T: SimpleAddressHistoryDiag>(_ dict: [String: T]) -> [SimpleAddressHistoryEntry] {
    dict.map { SimpleAddressHistoryEntry(walletId: $0.key, address: $0.value.address, sourceUsed: $0.value.sourceUsed, transactionCount: $0.value.transactionCount, error: $0.value.error) }
}
extension AppState {
    private func utxoJSON(_ history: [String: BitcoinHistoryDiagnostics], _ endpoints: [BitcoinEndpointHealthResult], _ h: Date?, _ e: Date?, _ mode: String? = nil) -> String? {
        diagnosticsBuildUtxoJson(history: Array(history.values), endpoints: endpoints.map(rustRow), historyLastUpdatedAtUnix: h?.timeIntervalSince1970, endpointsLastUpdatedAtUnix: e?.timeIntervalSince1970, extraNetworkMode: mode)
    }
    private func evmJSON(_ history: [String: EthereumTokenTransferHistoryDiagnostics], _ endpoints: [EthereumEndpointHealthResult], _ h: Date?, _ e: Date?) -> String? {
        diagnosticsBuildEvmJson(history: history.map { EvmHistoryEntry(walletId: $0.key, diagnostics: $0.value) }, endpoints: endpoints.map(rustRow), historyLastUpdatedAtUnix: h?.timeIntervalSince1970, endpointsLastUpdatedAtUnix: e?.timeIntervalSince1970)
    }
    private func simpleJSON<T: SimpleAddressHistoryDiag>(_ history: [String: T], _ endpoints: [BitcoinEndpointHealthResult], _ h: Date?, _ e: Date?) -> String? {
        diagnosticsBuildSimpleAddressJson(history: simpleEntries(history), endpoints: endpoints.map(rustRow), historyLastUpdatedAtUnix: h?.timeIntervalSince1970, endpointsLastUpdatedAtUnix: e?.timeIntervalSince1970)
    }
    func bitcoinDiagnosticsJSON() -> String? { utxoJSON(bitcoinHistoryDiagnosticsByWallet, bitcoinEndpointHealthResults, bitcoinHistoryDiagnosticsLastUpdatedAt, bitcoinEndpointHealthLastUpdatedAt, bitcoinNetworkMode.rawValue) }
    func litecoinDiagnosticsJSON() -> String? { utxoJSON(litecoinHistoryDiagnosticsByWallet, litecoinEndpointHealthResults, litecoinHistoryDiagnosticsLastUpdatedAt, litecoinEndpointHealthLastUpdatedAt) }
    func dogecoinDiagnosticsJSON() -> String? { utxoJSON(dogecoinHistoryDiagnosticsByWallet, dogecoinEndpointHealthResults, dogecoinHistoryDiagnosticsLastUpdatedAt, dogecoinEndpointHealthLastUpdatedAt) }
    func bitcoinCashDiagnosticsJSON() -> String? { utxoJSON(bitcoinCashHistoryDiagnosticsByWallet, bitcoinCashEndpointHealthResults, bitcoinCashHistoryDiagnosticsLastUpdatedAt, bitcoinCashEndpointHealthLastUpdatedAt) }
    func bitcoinSVDiagnosticsJSON() -> String? { utxoJSON(bitcoinSVHistoryDiagnosticsByWallet, bitcoinSVEndpointHealthResults, bitcoinSVHistoryDiagnosticsLastUpdatedAt, bitcoinSVEndpointHealthLastUpdatedAt) }
    func ethereumDiagnosticsJSON() -> String? { evmJSON(ethereumHistoryDiagnosticsByWallet, ethereumEndpointHealthResults, ethereumHistoryDiagnosticsLastUpdatedAt, ethereumEndpointHealthLastUpdatedAt) }
    func bnbDiagnosticsJSON() -> String? { evmJSON(bnbHistoryDiagnosticsByWallet, bnbEndpointHealthResults, bnbHistoryDiagnosticsLastUpdatedAt, bnbEndpointHealthLastUpdatedAt) }
    func arbitrumDiagnosticsJSON() -> String? { evmJSON(arbitrumHistoryDiagnosticsByWallet, arbitrumEndpointHealthResults, arbitrumHistoryDiagnosticsLastUpdatedAt, arbitrumEndpointHealthLastUpdatedAt) }
    func optimismDiagnosticsJSON() -> String? { evmJSON(optimismHistoryDiagnosticsByWallet, optimismEndpointHealthResults, optimismHistoryDiagnosticsLastUpdatedAt, optimismEndpointHealthLastUpdatedAt) }
    func avalancheDiagnosticsJSON() -> String? { evmJSON(avalancheHistoryDiagnosticsByWallet, avalancheEndpointHealthResults, avalancheHistoryDiagnosticsLastUpdatedAt, avalancheEndpointHealthLastUpdatedAt) }
    func hyperliquidDiagnosticsJSON() -> String? { evmJSON(hyperliquidHistoryDiagnosticsByWallet, hyperliquidEndpointHealthResults, hyperliquidHistoryDiagnosticsLastUpdatedAt, hyperliquidEndpointHealthLastUpdatedAt) }
    func etcDiagnosticsJSON() -> String? { evmJSON(etcHistoryDiagnosticsByWallet, etcEndpointHealthResults, etcHistoryDiagnosticsLastUpdatedAt, etcEndpointHealthLastUpdatedAt) }
    func tronDiagnosticsJSON() -> String? {
        diagnosticsBuildTronJson(history: tronHistoryDiagnosticsByWallet.map { TronHistoryEntry(walletId: $0.key, diagnostics: $0.value) }, endpoints: tronEndpointHealthResults.map(rustRow), historyLastUpdatedAtUnix: tronHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970, endpointsLastUpdatedAtUnix: tronEndpointHealthLastUpdatedAt?.timeIntervalSince1970, lastSendErrorAtUnix: tronLastSendErrorAt?.timeIntervalSince1970, lastSendErrorDetails: tronLastSendErrorDetails)
    }
    func solanaDiagnosticsJSON() -> String? {
        diagnosticsBuildSolanaJson(history: solanaHistoryDiagnosticsByWallet.map { SolanaHistoryEntry(walletId: $0.key, diagnostics: $0.value) }, endpoints: solanaEndpointHealthResults.map(rustRow), historyLastUpdatedAtUnix: solanaHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970, endpointsLastUpdatedAtUnix: solanaEndpointHealthLastUpdatedAt?.timeIntervalSince1970)
    }
    func cardanoDiagnosticsJSON() -> String? { simpleJSON(cardanoHistoryDiagnosticsByWallet, cardanoEndpointHealthResults, cardanoHistoryDiagnosticsLastUpdatedAt, cardanoEndpointHealthLastUpdatedAt) }
    func xrpDiagnosticsJSON() -> String? { simpleJSON(xrpHistoryDiagnosticsByWallet, xrpEndpointHealthResults, xrpHistoryDiagnosticsLastUpdatedAt, xrpEndpointHealthLastUpdatedAt) }
    func stellarDiagnosticsJSON() -> String? { simpleJSON(stellarHistoryDiagnosticsByWallet, stellarEndpointHealthResults, stellarHistoryDiagnosticsLastUpdatedAt, stellarEndpointHealthLastUpdatedAt) }
    func moneroDiagnosticsJSON() -> String? { simpleJSON(moneroHistoryDiagnosticsByWallet, moneroEndpointHealthResults, moneroHistoryDiagnosticsLastUpdatedAt, moneroEndpointHealthLastUpdatedAt) }
    func suiDiagnosticsJSON() -> String? { simpleJSON(suiHistoryDiagnosticsByWallet, suiEndpointHealthResults, suiHistoryDiagnosticsLastUpdatedAt, suiEndpointHealthLastUpdatedAt) }
    func aptosDiagnosticsJSON() -> String? { simpleJSON(aptosHistoryDiagnosticsByWallet, aptosEndpointHealthResults, aptosHistoryDiagnosticsLastUpdatedAt, aptosEndpointHealthLastUpdatedAt) }
    func tonDiagnosticsJSON() -> String? { simpleJSON(tonHistoryDiagnosticsByWallet, tonEndpointHealthResults, tonHistoryDiagnosticsLastUpdatedAt, tonEndpointHealthLastUpdatedAt) }
    func icpDiagnosticsJSON() -> String? { simpleJSON(icpHistoryDiagnosticsByWallet, icpEndpointHealthResults, icpHistoryDiagnosticsLastUpdatedAt, icpEndpointHealthLastUpdatedAt) }
    func nearDiagnosticsJSON() -> String? { simpleJSON(nearHistoryDiagnosticsByWallet, nearEndpointHealthResults, nearHistoryDiagnosticsLastUpdatedAt, nearEndpointHealthLastUpdatedAt) }
    func polkadotDiagnosticsJSON() -> String? { simpleJSON(polkadotHistoryDiagnosticsByWallet, polkadotEndpointHealthResults, polkadotHistoryDiagnosticsLastUpdatedAt, polkadotEndpointHealthLastUpdatedAt) }
    func exportDiagnosticsBundle() throws -> URL {
        let payload = buildDiagnosticsBundlePayload()
        let data = try Self.diagnosticsBundleEncoder.encode(payload)
        let stamp = Self.exportFilenameTimestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = try diagnosticsBundleExportsDirectoryURL().appendingPathComponent("spectra-diagnostics-\(stamp)").appendingPathExtension("json")
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
        guard let directory = try? diagnosticsBundleExportsDirectoryURL(), let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
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
        let payload = try Self.diagnosticsBundleDecoder.decode(DiagnosticsBundlePayload.self, from: data)
        lastImportedDiagnosticsBundle = payload
        return payload
    }
    private func buildDiagnosticsBundlePayload() -> DiagnosticsBundlePayload {
        let info = Bundle.main.infoDictionary ?? [:]
        let appVersion = (info["CFBundleShortVersionString"] as? String) ?? "unknown"
        let buildNumber = (info["CFBundleVersion"] as? String) ?? "unknown"
        let metadata = DiagnosticsEnvironmentMetadata(appVersion: appVersion, buildNumber: buildNumber, osVersion: ProcessInfo.processInfo.operatingSystemVersionString, localeIdentifier: Locale.current.identifier, timeZoneIdentifier: TimeZone.current.identifier, pricingProvider: pricingProvider.rawValue, selectedFiatCurrency: selectedFiatCurrency.rawValue, walletCount: wallets.count, transactionCount: transactions.count)
        return DiagnosticsBundlePayload(schemaVersion: 1, generatedAt: Date(), environment: metadata, chainDegradedMessages: diagnostics.chainDegradedMessages, bitcoinDiagnosticsJSON: bitcoinDiagnosticsJSON() ?? "{}", bitcoinSVDiagnosticsJSON: bitcoinSVDiagnosticsJSON() ?? "{}", litecoinDiagnosticsJSON: litecoinDiagnosticsJSON() ?? "{}", ethereumDiagnosticsJSON: ethereumDiagnosticsJSON() ?? "{}", arbitrumDiagnosticsJSON: arbitrumDiagnosticsJSON() ?? "{}", optimismDiagnosticsJSON: optimismDiagnosticsJSON() ?? "{}", bnbDiagnosticsJSON: bnbDiagnosticsJSON() ?? "{}", avalancheDiagnosticsJSON: avalancheDiagnosticsJSON() ?? "{}", hyperliquidDiagnosticsJSON: hyperliquidDiagnosticsJSON() ?? "{}", tronDiagnosticsJSON: tronDiagnosticsJSON() ?? "{}", solanaDiagnosticsJSON: solanaDiagnosticsJSON() ?? "{}", stellarDiagnosticsJSON: stellarDiagnosticsJSON() ?? "{}")
    }
}
