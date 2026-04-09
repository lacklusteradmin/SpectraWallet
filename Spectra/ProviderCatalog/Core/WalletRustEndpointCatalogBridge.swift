import Foundation

enum WalletRustEndpointCatalogBridgeError: LocalizedError {
    case rustCoreReturnedNullResponse
    case rustCoreFailed(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .rustCoreReturnedNullResponse:
            return "The Rust endpoint catalog returned an empty response."
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

private struct WalletRustFFIStringRequest {
    var utf8: WalletRustFFIBuffer
}

private struct WalletRustFFIStringArrayRequest {
    var jsonUTF8: WalletRustFFIBuffer
}

private struct WalletRustFFIEndpointQueryRequest {
    var chainNameUTF8: WalletRustFFIBuffer
    var roleMask: UInt32
    var settingsVisibleOnly: UInt8
}

struct AppEndpointGroupedSettingsEntry: Decodable {
    let title: String
    let endpoints: [String]
}

struct AppEndpointDiagnosticsCheck: Decodable {
    let endpoint: String
    let probeURL: String
}

struct AppEndpointExplorerEntry: Decodable {
    let endpoint: String
    let label: String
}

@_silgen_name("spectra_app_core_json_response_free")
private func spectra_app_core_json_response_free_for_catalog(
    _ response: UnsafeMutablePointer<WalletRustFFIJSONResponse>?
)

@_silgen_name("spectra_app_core_endpoint_records_json")
private func spectra_app_core_endpoint_records_json() -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_endpoint_for_id_json")
private func spectra_app_core_endpoint_for_id_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_endpoints_for_ids_json")
private func spectra_app_core_endpoints_for_ids_json(
    _ request: UnsafePointer<WalletRustFFIStringArrayRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_endpoint_records_for_chain_json")
private func spectra_app_core_endpoint_records_for_chain_json(
    _ request: UnsafePointer<WalletRustFFIEndpointQueryRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_grouped_settings_entries_json")
private func spectra_app_core_grouped_settings_entries_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_diagnostics_checks_json")
private func spectra_app_core_diagnostics_checks_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_transaction_explorer_entry_json")
private func spectra_app_core_transaction_explorer_entry_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_bitcoin_esplora_base_urls_json")
private func spectra_app_core_bitcoin_esplora_base_urls_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_bitcoin_wallet_store_default_base_urls_json")
private func spectra_app_core_bitcoin_wallet_store_default_base_urls_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_evm_rpc_endpoints_json")
private func spectra_app_core_evm_rpc_endpoints_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_explorer_supplemental_endpoints_json")
private func spectra_app_core_explorer_supplemental_endpoints_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_broadcast_provider_options_json")
private func spectra_app_core_broadcast_provider_options_json(
    _ request: UnsafePointer<WalletRustFFIStringRequest>?
) -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_chain_backends_json")
private func spectra_app_core_chain_backends_json() -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_live_chain_names_json")
private func spectra_app_core_live_chain_names_json() -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

@_silgen_name("spectra_app_core_app_chain_descriptors_json")
private func spectra_app_core_app_chain_descriptors_json() -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?

enum WalletRustEndpointCatalogBridge {
    static func records() throws -> [AppEndpointRecord] {
        try decodePayload([AppEndpointRecord].self, invoke: spectra_app_core_endpoint_records_json)
    }

    static func endpoint(_ id: String) throws -> String {
        try withStringRequest(id) { request in
            try decodePayload(String.self, invoke: { spectra_app_core_endpoint_for_id_json(request) })
        }
    }

    static func endpoints(for ids: [String]) throws -> [String] {
        let payload = try JSONEncoder().encode(ids)
        return try withDataRequest(payload) { request in
            try decodePayload([String].self, invoke: { spectra_app_core_endpoints_for_ids_json(request) })
        }
    }

    static func endpointRecords(
        for chainName: String,
        roles: Set<AppEndpointRole>,
        settingsVisibleOnly: Bool
    ) throws -> [AppEndpointRecord] {
        try withEndpointQueryRequest(
            chainName: chainName,
            roles: roles,
            settingsVisibleOnly: settingsVisibleOnly
        ) { request in
            try decodePayload(
                [AppEndpointRecord].self,
                invoke: { spectra_app_core_endpoint_records_for_chain_json(request) }
            )
        }
    }

    static func groupedSettingsEntries(for chainName: String) throws -> [AppEndpointGroupedSettingsEntry] {
        try withStringRequest(chainName) { request in
            try decodePayload(
                [AppEndpointGroupedSettingsEntry].self,
                invoke: { spectra_app_core_grouped_settings_entries_json(request) }
            )
        }
    }

    static func diagnosticsChecks(for chainName: String) throws -> [AppEndpointDiagnosticsCheck] {
        try withStringRequest(chainName) { request in
            try decodePayload(
                [AppEndpointDiagnosticsCheck].self,
                invoke: { spectra_app_core_diagnostics_checks_json(request) }
            )
        }
    }

    static func transactionExplorerEntry(for chainName: String) throws -> AppEndpointExplorerEntry? {
        try withStringRequest(chainName) { request in
            try decodePayload(
                AppEndpointExplorerEntry?.self,
                invoke: { spectra_app_core_transaction_explorer_entry_json(request) }
            )
        }
    }

    static func bitcoinEsploraBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] {
        try withStringRequest(networkMode.rawValue) { request in
            try decodePayload(
                [String].self,
                invoke: { spectra_app_core_bitcoin_esplora_base_urls_json(request) }
            )
        }
    }

    static func bitcoinWalletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) throws -> [String] {
        try withStringRequest(networkMode.rawValue) { request in
            try decodePayload(
                [String].self,
                invoke: { spectra_app_core_bitcoin_wallet_store_default_base_urls_json(request) }
            )
        }
    }

    static func evmRPCEndpoints(for chainName: String) throws -> [String] {
        try withStringRequest(chainName) { request in
            try decodePayload(
                [String].self,
                invoke: { spectra_app_core_evm_rpc_endpoints_json(request) }
            )
        }
    }

    static func explorerSupplementalEndpoints(for chainName: String) throws -> [String] {
        try withStringRequest(chainName) { request in
            try decodePayload(
                [String].self,
                invoke: { spectra_app_core_explorer_supplemental_endpoints_json(request) }
            )
        }
    }

    static func broadcastProviderOptions(for chainName: String) throws -> [ChainBroadcastProviderOption] {
        try withStringRequest(chainName) { request in
            try decodePayload(
                [ChainBroadcastProviderOption].self,
                invoke: { spectra_app_core_broadcast_provider_options_json(request) }
            )
        }
    }

    static func chainBackends() throws -> [ChainBackendRecord] {
        try decodePayload([ChainBackendRecord].self, invoke: spectra_app_core_chain_backends_json)
    }

    static func liveChainNames() throws -> [String] {
        try decodePayload([String].self, invoke: spectra_app_core_live_chain_names_json)
    }

    static func appChainDescriptors() throws -> [AppChainDescriptor] {
        try decodePayload([AppChainDescriptor].self, invoke: spectra_app_core_app_chain_descriptors_json)
    }

    private static func withStringRequest<T>(
        _ string: String,
        body: (UnsafePointer<WalletRustFFIStringRequest>) throws -> T
    ) rethrows -> T {
        let utf8 = Array(string.utf8)
        return try utf8.withUnsafeBufferPointer { buffer in
            var request = WalletRustFFIStringRequest(
                utf8: WalletRustFFIBuffer(
                    ptr: UnsafeMutablePointer(mutating: buffer.baseAddress),
                    len: buffer.count
                )
            )
            return try withUnsafePointer(to: &request, body)
        }
    }

    private static func withDataRequest<T>(
        _ data: Data,
        body: (UnsafePointer<WalletRustFFIStringArrayRequest>) throws -> T
    ) rethrows -> T {
        let bytes = Array(data)
        return try bytes.withUnsafeBufferPointer { buffer in
            var request = WalletRustFFIStringArrayRequest(
                jsonUTF8: WalletRustFFIBuffer(
                    ptr: UnsafeMutablePointer(mutating: buffer.baseAddress),
                    len: buffer.count
                )
            )
            return try withUnsafePointer(to: &request, body)
        }
    }

    private static func withEndpointQueryRequest<T>(
        chainName: String,
        roles: Set<AppEndpointRole>,
        settingsVisibleOnly: Bool,
        body: (UnsafePointer<WalletRustFFIEndpointQueryRequest>) throws -> T
    ) rethrows -> T {
        let utf8 = Array(chainName.utf8)
        return try utf8.withUnsafeBufferPointer { buffer in
            var request = WalletRustFFIEndpointQueryRequest(
                chainNameUTF8: WalletRustFFIBuffer(
                    ptr: UnsafeMutablePointer(mutating: buffer.baseAddress),
                    len: buffer.count
                ),
                roleMask: roleMask(for: roles),
                settingsVisibleOnly: settingsVisibleOnly ? 1 : 0
            )
            return try withUnsafePointer(to: &request, body)
        }
    }

    private static func decodePayload<T: Decodable>(
        _ type: T.Type,
        invoke: () -> UnsafeMutablePointer<WalletRustFFIJSONResponse>?
    ) throws -> T {
        guard let responsePointer = invoke() else {
            throw WalletRustEndpointCatalogBridgeError.rustCoreReturnedNullResponse
        }
        defer {
            spectra_app_core_json_response_free_for_catalog(responsePointer)
        }

        let response = responsePointer.pointee
        if response.statusCode != 0 {
            let message = string(from: response.errorMessageUTF8) ?? "Rust endpoint catalog request failed."
            throw WalletRustEndpointCatalogBridgeError.rustCoreFailed(message)
        }

        guard let payload = data(from: response.payloadUTF8), !payload.isEmpty else {
            throw WalletRustEndpointCatalogBridgeError.invalidPayload("Rust endpoint catalog returned an empty payload.")
        }

        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw WalletRustEndpointCatalogBridgeError.invalidPayload(error.localizedDescription)
        }
    }

    private static func roleMask(for roles: Set<AppEndpointRole>) -> UInt32 {
        roles.reduce(into: UInt32.zero) { partialResult, role in
            let bit: UInt32 = switch role {
            case .read: 1 << 0
            case .balance: 1 << 1
            case .history: 1 << 2
            case .utxo: 1 << 3
            case .fee: 1 << 4
            case .broadcast: 1 << 5
            case .verification: 1 << 6
            case .rpc: 1 << 7
            case .explorer: 1 << 8
            case .backend: 1 << 9
            }
            partialResult |= bit
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
