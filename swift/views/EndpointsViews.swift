import SwiftUI
struct EndpointCatalogSettingsView: View {
    @Bindable var store: AppState
    @State private var newEsploraEndpoint: String = ""
    private let copy = EndpointsContentCopy.current
    private var endpointSections: [Chain] {
        Chain.mainnets.filter { AppEndpointDirectory.hasEndpoints($0.id) }
    }
    private var customEsploraEndpoints: [String] { parseBitcoinEsploraEndpoints(raw: store.appSettings.bitcoinEsploraEndpoints) }
    private func addEsploraEndpoint() {
        let trimmed = newEsploraEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var endpoints = customEsploraEndpoints
        guard !endpoints.contains(trimmed) else {
            newEsploraEndpoint = ""
            return
        }
        endpoints.append(trimmed)
        store.updateSetting(.bitcoinEsploraEndpoints(value: endpoints.joined(separator: "\n")))
        newEsploraEndpoint = ""
    }
    /// One endpoint: the URL, and what the catalog says it is.
    ///
    /// The tag line is why the `kind` / `capabilities` split exists — six
    /// identical-looking URLs under one chain gave no way to tell the node
    /// that answers balances from the indexer that answers history. An
    /// endpoint the user typed has no catalog row and shows the URL alone.
    @ViewBuilder
    private func endpointRow(_ endpoint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(endpoint).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
            if let summary = AppEndpointDirectory.tagSummary(for: endpoint) {
                Text(summary).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func endpointRows(_ endpoints: [String]) -> some View {
        ForEach(endpoints, id: \.self) { endpoint in endpointRow(endpoint) }
    }
    @ViewBuilder
    private func namedEndpointGroup(title: String, endpoints: [String]) -> some View {
        if !endpoints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                ForEach(endpoints, id: \.self) { endpoint in endpointRow(endpoint)
                }
            }.padding(.vertical, 2)
        }
    }
    @ViewBuilder
    private func esploraSectionBody() -> some View {
        endpointRows(customEsploraEndpoints)
        TextField(copy.addEsploraEndpointPlaceholder, text: $newEsploraEndpoint).textInputAutocapitalization(.never)
            .autocorrectionDisabled().keyboardType(.URL)
        if let error = endpointValidationError(field: .bitcoinEsploraList, raw: newEsploraEndpoint) {
            Text(error).font(.caption).foregroundStyle(.red)
        }
        Button(copy.addEndpointButtonTitle) {
            addEsploraEndpoint()
        }.disabled(endpointValidationError(field: .bitcoinEsploraList, raw: newEsploraEndpoint) != nil)
        if !customEsploraEndpoints.isEmpty {
            Button(copy.clearCustomEsploraEndpointsTitle, role: .destructive) {
                store.updateSetting(.bitcoinEsploraEndpoints(value: ""))
            }
        }
    }
    @ViewBuilder
    private func backendSectionBody() -> some View {
        if !store.appSettings.moneroBackendBaseUrl.isEmpty {
            endpointRows([store.appSettings.moneroBackendBaseUrl])
        }
        SettingTextField(
            title: copy.customBackendURLPlaceholder, value: store.appSettings.moneroBackendBaseUrl, endpoint: .moneroBackend
        ) { store.updateSetting(.moneroBackendBaseUrl(value: $0)) }
        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    }
    /// The custom-RPC field for any EVM chain.
    @ViewBuilder
    private func customRPCField(for chainName: String) -> some View {
        SettingTextField(title: copy.customRPCURLPlaceholder, value: store.rpcEndpoint(forChain: chainName), endpoint: .evmRpc) {
            store.setRPCEndpoint($0, forChain: chainName)
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    }
    @ViewBuilder
    private func endpointSection(_ chain: Chain) -> some View {
        Section(chain.displayName) {
            let groups = AppEndpointDirectory.groupedSettingsEntries(for: chain.id)
            if groups.count > 1 {
                ForEach(groups, id: \.chainId) { group in
                    namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                }
            } else {
                endpointRows(AppEndpointDirectory.settingsEndpoints(for: chain.id))
            }
            if chain.sendsThroughBackend {
                backendSectionBody()
            } else if !AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainId: chain.id).isEmpty {
                esploraSectionBody()
            } else if chain.isEVM {
                customRPCField(for: chain.displayName)
            }
        }
    }
    var body: some View {
        Form {
            Section {
                Text(copy.intro).font(.caption).foregroundStyle(.secondary)
                if let loadError = AppEndpointDirectory.loadError {
                    Text(loadError).font(.caption).foregroundStyle(.red)
                }
            }
            ForEach(endpointSections) { chain in endpointSection(chain) }
        }.navigationTitle(copy.navigationTitle)
    }
}
