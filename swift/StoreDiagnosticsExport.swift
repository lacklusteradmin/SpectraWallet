import Foundation

// Swift owns only file I/O and data collection. All struct definitions,
// serialization, and deserialization live in Rust (`core/src/diagnostics/export.rs`).
//
// `DiagnosticsBundlePayload` and `DiagnosticsEnvironmentMetadata` are UniFFI
// records — Swift sees them as plain structs via the generated bindings.

// The `SimpleAddressHistoryDiag` protocol and its ten conformances stood here.
// It existed to treat ten identically-shaped records as one type; core stamped
// those out with a macro from a single field list, so there is one record now
// and nothing left for the protocol to unify.

// `simpleEntries`, `utxoJSON`, `evmJSON` and `simpleJSON` stood here: three
// wrappers that read history out of core's registry and handed it straight back
// so core could build JSON from it. `coreDiagnosticsJson` reads its own store.

extension AppState {
    static let diagnosticsBundleChainNames = [
        "Bitcoin",
        "Dogecoin",
        "Bitcoin Cash",
        "Bitcoin SV",
        "Litecoin",
        "Ethereum",
        "Ethereum Classic",
        "Arbitrum",
        "Optimism",
        "BNB Chain",
        "Avalanche",
        "Hyperliquid",
        "Tron",
        "Solana",
        "Stellar",
        "Cardano",
        "XRP Ledger",
        "Monero",
        "Sui",
        "Aptos",
        "TON",
        "Internet Computer",
        "NEAR",
        "Polkadot",
    ]

    /// Diagnostics JSON for one chain.
    ///
    /// Was a 24-case switch over five builders, each fed history this side had
    /// just read out of core's registry and handed straight back across the
    /// FFI. Core owns that storage and `Chain::diagnostics_shape` says which
    /// document to build, so the chain name is the whole input.
    func diagnosticsJSON(for chainName: String) -> String? {
        coreDiagnosticsJson(
            chainName: chainName,
            endpoints: self[endpointHealthFor: chainName].results,
            historyLastUpdatedAtUnix: self[historyRunFor: chainName].lastUpdatedAt?
                .timeIntervalSince1970,
            endpointsLastUpdatedAtUnix: self[endpointHealthFor: chainName].lastUpdatedAt?
                .timeIntervalSince1970,
            extraNetworkMode: chainName == "Bitcoin" ? networkChainID(forFamily: "bitcoin") : nil,
            lastSendErrorAtUnix: chainName == "Tron"
                ? tronLastSendErrorAt?.timeIntervalSince1970 : nil,
            lastSendErrorDetails: chainName == "Tron" ? tronLastSendErrorDetails : nil)
    }

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
            chainDiagnosticsJson: DiagnosticsBundlePayload.chainKeyed(
                Dictionary(
                    uniqueKeysWithValues: Self.diagnosticsBundleChainNames.map {
                        ($0, diagnosticsJSON(for: $0))
                    })))
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
