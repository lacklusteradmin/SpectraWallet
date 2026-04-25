import SwiftUI
struct EndpointCatalogSettingsView: View {
    @Bindable var store: AppState
    @State private var newBitcoinEndpoint: String = ""
    private let copy = EndpointsContentCopy.current
    private var endpointSections: [AppChainDescriptor] { AppEndpointDirectory.endpointCatalogChains }
    private var parsedBitcoinCustomEndpoints: [String] {
        store.bitcoinEsploraEndpoints.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }
    private var bitcoinEndpointsByNetwork: [AppEndpointGroupedSettingsEntry] {
        BitcoinNetworkMode.allCases.map { mode in
            let custom = mode == store.bitcoinNetworkMode ? parsedBitcoinCustomEndpoints : []
            let title = mode == .mainnet ? "Bitcoin" : "Bitcoin \(mode.displayName)"
            return AppEndpointGroupedSettingsEntry(title: title, endpoints: Self.esploraRuntimeBaseURLs(for: mode, custom: custom))
        }
    }
    private var ethereumEndpointsByNetwork: [AppEndpointGroupedSettingsEntry] {
        EthereumNetworkMode.allCases.map { mode in
            var endpoints: [String] = []
            if mode == store.ethereumNetworkMode {
                let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                if !custom.isEmpty { endpoints.append(custom) }
            }
            let context: EVMChainContext =
                switch mode {
                case .mainnet: .ethereum
                case .sepolia: .ethereumSepolia
                case .hoodi: .ethereumHoodi
                }
            for endpoint in context.defaultRPCEndpoints where !endpoints.contains(endpoint) { endpoints.append(endpoint) }
            if mode == .mainnet {
                for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: "Ethereum") where !endpoints.contains(endpoint) {
                    endpoints.append(endpoint)
                }
            }
            let title = mode == .mainnet ? "Ethereum" : "Ethereum \(mode.displayName)"
            return AppEndpointGroupedSettingsEntry(title: title, endpoints: endpoints)
        }
    }
    private var bnbEndpoints: [String] {
        var endpoints = EVMChainContext.bnb.defaultRPCEndpoints
        for endpoint in AppEndpointDirectory.explorerSupplementalEndpoints(for: "BNB Chain") {
            if !endpoints.contains(endpoint) { endpoints.append(endpoint) }
        }
        return endpoints
    }
    private var moneroEndpoints: [String] {
        let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return [trimmed] }
        return [MoneroBalanceService.defaultPublicBackend.baseURL]
    }
    private var dogecoinEndpointsByNetwork: [AppEndpointGroupedSettingsEntry] { DogecoinBalanceService.endpointCatalogByNetwork() }
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
    private static func esploraRuntimeBaseURLs(for networkMode: BitcoinNetworkMode, custom: [String] = []) -> [String] {
        let trimmed = custom.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !trimmed.isEmpty { return trimmed }
        return AppEndpointDirectory.bitcoinEsploraBaseURLs(for: networkMode)
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
    private func endpointSection(_ descriptor: AppChainDescriptor) -> some View {
        Section(descriptor.chainName) {
            switch descriptor.id {
            case .bitcoin: bitcoinSectionBody
            case .bitcoinCash: endpointRows(BitcoinCashBalanceService.endpointCatalog())
            case .litecoin: endpointRows(LitecoinBalanceService.endpointCatalog())
            case .dogecoin:
                ForEach(dogecoinEndpointsByNetwork, id: \.title) { group in
                    namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                }
            case .ethereum: ethereumSectionBody
            case .ethereumClassic: readOnlyEVMSection(EVMChainContext.ethereumClassic.defaultRPCEndpoints)
            case .arbitrum: readOnlyEVMSection(EVMChainContext.arbitrum.defaultRPCEndpoints)
            case .optimism: readOnlyEVMSection(EVMChainContext.optimism.defaultRPCEndpoints)
            case .bnb: readOnlyEVMSection(bnbEndpoints)
            case .avalanche: readOnlyEVMSection(EVMChainContext.avalanche.defaultRPCEndpoints)
            case .hyperliquid: readOnlyEVMSection(EVMChainContext.hyperliquid.defaultRPCEndpoints)
            case .polygon: readOnlyEVMSection(EVMChainContext.polygon.defaultRPCEndpoints)
            case .base: readOnlyEVMSection(EVMChainContext.base.defaultRPCEndpoints)
            case .linea: readOnlyEVMSection(EVMChainContext.linea.defaultRPCEndpoints)
            case .scroll: readOnlyEVMSection(EVMChainContext.scroll.defaultRPCEndpoints)
            case .blast: readOnlyEVMSection(EVMChainContext.blast.defaultRPCEndpoints)
            case .mantle: readOnlyEVMSection(EVMChainContext.mantle.defaultRPCEndpoints)
            case .tron: endpointRows(TronBalanceService.endpointCatalog())
            case .solana: endpointRows(SolanaBalanceService.endpointCatalog())
            case .cardano: endpointRows(CardanoBalanceService.endpointCatalog())
            case .xrp: endpointRows(XRPBalanceService.endpointCatalog())
            case .stellar: endpointRows(StellarBalanceService.endpointCatalog())
            case .monero: moneroSectionBody
            case .sui: endpointRows(SuiBalanceService.endpointCatalog())
            case .aptos: endpointRows(AptosBalanceService.endpointCatalog())
            case .ton: endpointRows(TONBalanceService.endpointCatalog())
            case .icp: endpointRows(ICPBalanceService.endpointCatalog())
            case .near: endpointRows(NearBalanceService.endpointCatalog())
            case .polkadot: endpointRows(PolkadotBalanceService.endpointCatalog())
            case .bitcoinSV: endpointRows(BitcoinSVBalanceService.endpointCatalog())
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
            ForEach(endpointSections) { descriptor in endpointSection(descriptor) }
        }.navigationTitle(copy.navigationTitle)
    }
}
