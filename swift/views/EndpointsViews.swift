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
                let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// An EVM chain's RPC list plus the explorer endpoints the catalog
    /// supplements it with. Only BNB Chain used to be given the supplement; the
    /// list is empty for chains that have none, so asking for every chain costs
    /// nothing and removes the case.
    private func evmEndpoints(for name: String) -> [String] {
        var endpoints = AppEndpointDirectory.evmRPCEndpoints(for: name)
        for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: name)
        where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        return endpoints
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
    @ViewBuilder
    private func endpointRows(_ endpoints: [String]) -> some View {
        ForEach(endpoints, id: \.self) { endpoint in Text(endpoint).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3) }
    }
    @ViewBuilder
    private func namedEndpointGroup(title: String, endpoints: [String]) -> some View {
        if !endpoints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                ForEach(endpoints, id: \.self) { endpoint in Text(endpoint).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
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
        TextField(copy.customEthereumRPCURLPlaceholder, text: $store.ethereumRPCEndpoint)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        if let error = store.ethereumRPCEndpointValidationError { Text(error).font(.caption).foregroundStyle(.red) }
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
    @ViewBuilder
    /// One section per chain the catalog says has endpoints worth showing.
    ///
    /// Was a thirty-case switch, of which twenty-two arms were
    /// `endpointRows(XBalanceService.endpointCatalog())` or
    /// `readOnlyEVMSection(EVMChainContext.x.defaultRPCEndpoints)` — both of
    /// which only restate the chain's own name. What is left is the four chains
    /// whose section is genuinely its own screen.
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
                    readOnlyEVMSection(evmEndpoints(for: chain.displayName))
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
