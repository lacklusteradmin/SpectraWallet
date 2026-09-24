import Foundation

// Swift owns only file I/O and data collection. All struct definitions,
// serialization, and deserialization live in Rust (`core/src/diagnostics/export.rs`).
//
// `DiagnosticsBundlePayload` and `DiagnosticsEnvironmentMetadata` are UniFFI
// records — Swift sees them as plain structs via the generated bindings.

extension AppState {
    /// Every mainnet — the same set the diagnostics hub offers a screen for.
    static let diagnosticsBundleChains = Chain.mainnets

    func diagnosticsJSON(for chain: Chain) -> String? {
        diagnosticsJson(
            chainId: chain.id,
            endpoints: self[endpointHealthFor: chain].results,
            historyLastUpdatedAtUnix: self[historyRunFor: chain].lastUpdatedAt?
                .timeIntervalSince1970,
            endpointsLastUpdatedAtUnix: self[endpointHealthFor: chain].lastUpdatedAt?
                .timeIntervalSince1970,
            // Any family with a network to choose.
            extraNetworkMode: chain.networkChoices.count > 1 ? selectedChainId(forFamily: chain.id) : nil)
    }

    private func buildDiagnosticsBundle() -> DiagnosticsBundlePayload {
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = DiagnosticsEnvironmentMetadata(
            appVersion: (info["CFBundleShortVersionString"] as? String) ?? "unknown",
            buildNumber: (info["CFBundleVersion"] as? String) ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier,
            selectedFiatCurrency: selectedFiatCurrency.code,
            walletCount: Int64(wallets.count),
            transactionCount: Int64(transactionCount))
        return DiagnosticsBundlePayload(
            schemaVersion: 1,
            generatedAt: Date().timeIntervalSince1970,
            environment: environment,
            chainDegraded: diagnostics.chainDegraded,
            chainDiagnosticsJson: Dictionary(
                uniqueKeysWithValues: Self.diagnosticsBundleChains.map {
                    ($0.id, diagnosticsJSON(for: $0) ?? "{}")
                }))
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

    func diagnosticsJSON(for chain: Chain) -> String? { chainDiagnosticsJson[chain.id] }
}
