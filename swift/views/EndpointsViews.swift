import SwiftUI
struct EndpointCatalogSettingsView: View {
    @Bindable var store: AppState
    @State private var newEsploraEndpoint: String = ""
    private let copy = EndpointsContentCopy.current
    private var endpointSections: [Chain] {
        Chain.mainnets.filter { AppEndpointDirectory.hasEndpoints($0.id) }
    }
    private var customEsploraEndpoints: [String] { parseBitcoinEsploraEndpoints(raw: store.appSettings.bitcoinEsploraEndpoints) }
    /// A family's networks, each with its own endpoints, the selected one
    /// carrying whatever the user configured.
    ///
    /// Bitcoin and Ethereum each had a copy of this naming their own family,
    /// and Dogecoin a third reading the catalog's grouping instead; the other
    /// multi-network families showed one flat list. Which list a network reads
    /// is the only thing that differs, so it is the only thing passed in.
    private func endpointsByNetwork(
        of chain: Chain, endpoints: (NetworkChoice, _ isSelected: Bool) -> [String]
    ) -> [AppEndpointGroupedSettingsEntry] {
        let selected = store.networkChainID(forFamily: chain.id)
        return chain.networkChoices.map { choice in
            AppEndpointGroupedSettingsEntry(networkId: choice.chainId, title: choice.title, endpoints: endpoints(choice, choice.chainId == selected))
        }
    }
    private func esploraEndpointsByNetwork(of chain: Chain) -> [AppEndpointGroupedSettingsEntry] {
        endpointsByNetwork(of: chain) { choice, isSelected in
            let custom = isSelected ? customEsploraEndpoints : []
            return custom.isEmpty ? AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainID: choice.chainId) : custom
        }
    }
    private func evmEndpointsByNetwork(of chain: Chain) -> [AppEndpointGroupedSettingsEntry] {
        endpointsByNetwork(of: chain) { choice, isSelected in
            var endpoints: [String] = []
            let custom = isSelected ? store.rpcEndpoint(forChain: chain.displayName) : ""
            if !custom.isEmpty { endpoints.append(custom) }
            let catalog =
                choice.isTestnet
                ? AppEndpointDirectory.evmRPCEndpoints(for: choice.chainId)
                : AppEndpointDirectory.evmEndpointsWithSupplemental(for: choice.chainId)
            for endpoint in catalog where !endpoints.contains(endpoint) { endpoints.append(endpoint) }
            return endpoints
        }
    }
    private func backendEndpoints(of chain: Chain) -> [String] {
        let stored = store.appSettings.moneroBackendBaseUrl
        return stored.isEmpty ? AppEndpointDirectory.settingsEndpoints(for: chain.id) : [stored]
    }
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
    private func esploraSectionBody(_ chain: Chain) -> some View {
        ForEach(esploraEndpointsByNetwork(of: chain), id: \.networkId) { group in
            namedEndpointGroup(title: group.title, endpoints: group.endpoints)
        }
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
    private func backendSectionBody(_ chain: Chain) -> some View {
        endpointRows(backendEndpoints(of: chain))
        SettingTextField(
            title: copy.customBackendURLPlaceholder, value: store.appSettings.moneroBackendBaseUrl, endpoint: .moneroBackend
        ) { store.updateSetting(.moneroBackendBaseUrl(value: $0)) }
        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    }
    @ViewBuilder
    private func readOnlyEVMSection(_ endpoints: [String]) -> some View {
        endpointRows(endpoints)
        readOnlyFootnote
    }

    /// The custom-RPC field for any EVM chain.
    @ViewBuilder
    private func customRPCField(for chainName: String) -> some View {
        SettingTextField(title: copy.customRPCURLPlaceholder, value: store.rpcEndpoint(forChain: chainName), endpoint: .evmRpc) {
            store.setRPCEndpoint($0, forChain: chainName)
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
    }
    /// One section per chain the catalog says has endpoints worth showing.
    ///
    /// Which body a chain gets follows from what it has — a backend setting,
    /// Esplora bases, an EVM RPC, or more than one network — rather than from
    /// a switch naming Bitcoin, Ethereum, Monero and Dogecoin.
    @ViewBuilder
    private func endpointSection(_ chain: Chain) -> some View {
        Section(chain.displayName) {
            if chain.sendsThroughBackend {
                backendSectionBody(chain)
            } else if !AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainID: chain.id).isEmpty {
                esploraSectionBody(chain)
            } else if chain.isEVM {
                if chain.networkChoices.count > 1 {
                    ForEach(evmEndpointsByNetwork(of: chain), id: \.networkId) { group in
                        namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                    }
                } else {
                    readOnlyEVMSection(AppEndpointDirectory.evmEndpointsWithSupplemental(for: chain.id))
                }
                customRPCField(for: chain.displayName)
            } else {
                let groups = AppEndpointDirectory.groupedSettingsEntries(for: chain.id)
                if groups.count > 1 {
                    ForEach(groups, id: \.networkId) { group in
                        namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                    }
                } else {
                    endpointRows(AppEndpointDirectory.settingsEndpoints(for: chain.id))
                }
            }
        }
    }
    private var readOnlyFootnote: some View {
        Text(copy.readOnlyFootnote).font(.caption).foregroundStyle(.secondary)
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
