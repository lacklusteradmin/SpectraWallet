import SwiftUI
struct EndpointCatalogSettingsView: View {
    @Bindable var store: AppState
    @State private var newBitcoinEndpoint: String = ""
    private let copy = EndpointsContentCopy.current
    private var endpointSections: [Chain] {
        Chain.mainnets.filter { AppEndpointDirectory.hasEndpoints($0.displayName) }
    }
    private var parsedBitcoinCustomEndpoints: [String] {
        store.bitcoinEsploraEndpoints.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }
    /// Core lists the networks and titles them; this only decides whose custom
    /// endpoints to fold in.
    private var bitcoinEndpointsByNetwork: [AppEndpointGroupedSettingsEntry] {
        let selected = store.networkChainID(forFamily: "bitcoin")
        return (Chain(id: "bitcoin")?.networkChoices ?? []).map { choice in
            let custom = choice.chainId == selected ? parsedBitcoinCustomEndpoints : []
            return AppEndpointGroupedSettingsEntry(
                title: choice.title,
                endpoints: Self.esploraRuntimeBaseURLs(forChainID: choice.chainId, custom: custom))
        }
    }
    private var ethereumEndpointsByNetwork: [AppEndpointGroupedSettingsEntry] {
        let selected = store.networkChainID(forFamily: "ethereum")
        return (Chain(id: "ethereum")?.networkChoices ?? []).map { choice in
            var endpoints: [String] = []
            if choice.chainId == selected {
                let custom = store.rpcEndpoint(forChain: "Ethereum")
                if !custom.isEmpty { endpoints.append(custom) }
            }
            guard let context = EVMChainContext(chainName: choice.title) else {
                return AppEndpointGroupedSettingsEntry(title: choice.title, endpoints: endpoints)
            }
            for endpoint in context.defaultRPCEndpoints where !endpoints.contains(endpoint) { endpoints.append(endpoint) }
            if !choice.isTestnet {
                for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: "Ethereum") where !endpoints.contains(endpoint) {
                    endpoints.append(endpoint)
                }
            }
            return AppEndpointGroupedSettingsEntry(title: choice.title, endpoints: endpoints)
        }
    }
    private var moneroEndpoints: [String] {
        let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return [trimmed] }
        return [MoneroBalanceService.defaultPublicBackend.baseURL]
    }
    private var dogecoinEndpointsByNetwork: [AppEndpointGroupedSettingsEntry] { AppEndpointDirectory.groupedSettingsEntries(for: "Dogecoin") }
    private func addBitcoinEndpoint() {
        let trimmed = newBitcoinEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var endpoints = parsedBitcoinCustomEndpoints
        guard !endpoints.contains(trimmed) else {
            newBitcoinEndpoint = ""
            return
        }
        endpoints.append(trimmed)
        store.bitcoinEsploraEndpoints = endpoints.joined(separator: "\n")
        newBitcoinEndpoint = ""
    }
    private static func esploraRuntimeBaseURLs(forChainID chainID: String, custom: [String] = []) -> [String] {
        let trimmed = custom.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !trimmed.isEmpty { return trimmed }
        return AppEndpointDirectory.bitcoinEsploraBaseURLs(forChainID: chainID)
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
    private var bitcoinSectionBody: some View {
        ForEach(bitcoinEndpointsByNetwork, id: \.title) { group in
            namedEndpointGroup(title: group.title, endpoints: group.endpoints)
        }
        TextField(copy.addEsploraEndpointPlaceholder, text: $newBitcoinEndpoint).textInputAutocapitalization(.never)
            .autocorrectionDisabled().keyboardType(.URL)
        Button(copy.addEndpointButtonTitle) {
            addBitcoinEndpoint()
        }
        if !parsedBitcoinCustomEndpoints.isEmpty {
            Button(copy.clearCustomBitcoinEndpointsTitle, role: .destructive) {
                store.bitcoinEsploraEndpoints = ""
            }
        }
        if let error = store.bitcoinEsploraEndpointsValidationError { Text(error).font(.caption).foregroundStyle(.red) }
    }
    @ViewBuilder
    private var ethereumSectionBody: some View {
        ForEach(ethereumEndpointsByNetwork, id: \.title) { group in
            namedEndpointGroup(title: group.title, endpoints: group.endpoints)
        }
        customRPCField(for: "Ethereum")
    }
    @ViewBuilder
    private var moneroSectionBody: some View {
        endpointRows(moneroEndpoints)
        TextField(copy.customMoneroBackendURLPlaceholder, text: $store.moneroBackendBaseURL)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        if let error = store.moneroBackendBaseURLValidationError { Text(error).font(.caption).foregroundStyle(.red) }
    }
    @ViewBuilder
    private func readOnlyEVMSection(_ endpoints: [String]) -> some View {
        endpointRows(endpoints)
        readOnlyFootnote
    }

    /// The custom-RPC field, for any EVM chain.
    ///
    /// Ethereum had this and the other twenty-two EVM mainnets did not — not
    /// because the field was missing here, but because the setting behind it
    /// was a single `ethereum_rpc_endpoint` string read through an accessor
    /// that returned nil for every other name.
    @ViewBuilder
    private func customRPCField(for chainName: String) -> some View {
        TextField(
            copy.customRPCURLPlaceholder,
            text: Binding(
                get: { store.rpcEndpoint(forChain: chainName) },
                set: { store.setRPCEndpoint($0, forChain: chainName) })
        )
        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        if let error = store.rpcEndpointValidationError(forChain: chainName) {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
    @ViewBuilder
    /// One section per chain the catalog says has endpoints worth showing.
    private func endpointSection(_ chain: Chain) -> some View {
        Section(chain.displayName) {
            switch chain {
            case .bitcoin: bitcoinSectionBody
            case .ethereum: ethereumSectionBody
            case .monero: moneroSectionBody
            case .dogecoin:
                ForEach(dogecoinEndpointsByNetwork, id: \.title) { group in
                    namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                }
            default:
                if chain.isEVM {
                    readOnlyEVMSection(AppEndpointDirectory.evmEndpointsWithSupplemental(for: chain.displayName))
                    customRPCField(for: chain.displayName)
                } else {
                    endpointRows(AppEndpointDirectory.settingsEndpoints(for: chain.displayName))
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
            }
            ForEach(endpointSections) { chain in endpointSection(chain) }
        }.navigationTitle(copy.navigationTitle)
    }
}
