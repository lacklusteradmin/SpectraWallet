import SwiftUI
import Combine

struct EndpointCatalogSettingsView: View {
    let store: WalletStore
    @StateObject private var refreshSignal: ViewRefreshSignal
    @State private var newBitcoinEndpoint: String = ""
    private let copy = EndpointsContentCopy.current

    init(store: WalletStore) {
        self.store = store
        _refreshSignal = StateObject(
            wrappedValue: ViewRefreshSignal([
                store.$bitcoinEsploraEndpoints.asVoidSignal(),
                store.$bitcoinNetworkMode.asVoidSignal(),
                store.$dogecoinAllowTestnet.asVoidSignal(),
                store.$ethereumNetworkMode.asVoidSignal(),
                store.$ethereumRPCEndpoint.asVoidSignal(),
                store.$moneroBackendBaseURL.asVoidSignal()
            ])
        )
    }

    private var endpointSections: [AppChainDescriptor] {
        ChainBackendRegistry.endpointCatalogChains
    }

    private var parsedBitcoinCustomEndpoints: [String] {
        store.bitcoinEsploraEndpoints
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var bitcoinEndpoints: [String] {
        BitcoinWalletEngine.endpointCatalog(for: store.bitcoinNetworkMode, custom: parsedBitcoinCustomEndpoints)
    }

    private var bitcoinEndpointsByNetwork: [(title: String, endpoints: [String])] {
        BitcoinNetworkMode.allCases.map { mode in
            let custom = mode == store.bitcoinNetworkMode ? parsedBitcoinCustomEndpoints : []
            let title = mode == .mainnet ? "Bitcoin" : "Bitcoin \(mode.displayName)"
            return (title: title, endpoints: BitcoinWalletEngine.endpointCatalog(for: mode, custom: custom))
        }
    }

    private var ethereumEndpoints: [String] {
        var endpoints: [String] = []
        let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            endpoints.append(custom)
        }
        let context = store.evmChainContext(for: "Ethereum") ?? .ethereum
        for endpoint in context.defaultRPCEndpoints where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        for endpoint in ChainBackendRegistry.EVMExplorerRegistry.supplementalEndpointCatalogEntries(for: ChainBackendRegistry.ethereumChainName) {
            if !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
        }
        return endpoints
    }

    private var ethereumEndpointsByNetwork: [(title: String, endpoints: [String])] {
        EthereumNetworkMode.allCases.map { mode in
            var endpoints: [String] = []
            if mode == store.ethereumNetworkMode {
                let custom = store.ethereumRPCEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                if !custom.isEmpty {
                    endpoints.append(custom)
                }
            }
            let context: EVMChainContext = switch mode {
            case .mainnet:
                .ethereum
            case .sepolia:
                .ethereumSepolia
            case .hoodi:
                .ethereumHoodi
            }
            for endpoint in context.defaultRPCEndpoints where !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
            if mode == .mainnet {
                for endpoint in ChainBackendRegistry.EVMExplorerRegistry.supplementalEndpointCatalogEntries(for: ChainBackendRegistry.ethereumChainName) where !endpoints.contains(endpoint) {
                    endpoints.append(endpoint)
                }
            }
            let title = mode == .mainnet ? "Ethereum" : "Ethereum \(mode.displayName)"
            return (title: title, endpoints: endpoints)
        }
    }

    private var ethereumClassicEndpoints: [String] {
        EVMChainContext.ethereumClassic.defaultRPCEndpoints
    }

    private var arbitrumEndpoints: [String] {
        EVMChainContext.arbitrum.defaultRPCEndpoints
    }

    private var optimismEndpoints: [String] {
        EVMChainContext.optimism.defaultRPCEndpoints
    }

    private var bnbEndpoints: [String] {
        var endpoints = EVMChainContext.bnb.defaultRPCEndpoints
        for endpoint in ChainBackendRegistry.EVMExplorerRegistry.supplementalEndpointCatalogEntries(for: ChainBackendRegistry.bnbChainName) {
            if !endpoints.contains(endpoint) {
                endpoints.append(endpoint)
            }
        }
        return endpoints
    }

    private var avalancheEndpoints: [String] {
        EVMChainContext.avalanche.defaultRPCEndpoints
    }

    private var hyperliquidEndpoints: [String] {
        EVMChainContext.hyperliquid.defaultRPCEndpoints
    }

    private var dogecoinEndpoints: [String] {
        DogecoinBalanceService.endpointCatalog()
    }

    private var dogecoinEndpointsByNetwork: [(title: String, endpoints: [String])] {
        DogecoinNetworkMode.allCases.map { mode in
            let title = mode == .mainnet ? "Dogecoin" : "Dogecoin \(mode.displayName)"
            let endpoints = mode == .mainnet
                ? [
                    ChainBackendRegistry.DogecoinRuntimeEndpoints.blockchairBaseURL,
                    ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL,
                    ChainBackendRegistry.DogecoinRuntimeEndpoints.dogechainBaseURL,
                ]
                : [ChainBackendRegistry.DogecoinRuntimeEndpoints.testnetElectrsBaseURL]
            return (title: title, endpoints: endpoints)
        }
    }

    private var moneroEndpoints: [String] {
        let trimmed = store.moneroBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return [trimmed]
        }
        return [MoneroBalanceService.defaultPublicBackend.baseURL]
    }

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

    @ViewBuilder
    private func endpointRows(_ endpoints: [String]) -> some View {
        ForEach(endpoints, id: \.self) { endpoint in
            Text(endpoint)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func namedEndpointGroup(title: String, endpoints: [String]) -> some View {
        if !endpoints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                ForEach(endpoints, id: \.self) { endpoint in
                    Text(endpoint)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func endpointSection(_ descriptor: AppChainDescriptor) -> some View {
        Section(descriptor.chainName) {
            switch descriptor.id {
            case .bitcoin:
                ForEach(bitcoinEndpointsByNetwork, id: \.title) { group in
                    namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                }

                TextField(copy.addEsploraEndpointPlaceholder, text: $newBitcoinEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button(copy.addEndpointButtonTitle) {
                    addBitcoinEndpoint()
                }

                if !parsedBitcoinCustomEndpoints.isEmpty {
                    Button(copy.clearCustomBitcoinEndpointsTitle, role: .destructive) {
                        store.bitcoinEsploraEndpoints = ""
                    }
                }

                if let error = store.bitcoinEsploraEndpointsValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            case .bitcoinCash:
                endpointRows(BitcoinCashBalanceService.endpointCatalog())
            case .litecoin:
                endpointRows(LitecoinBalanceService.endpointCatalog())
            case .dogecoin:
                ForEach(dogecoinEndpointsByNetwork, id: \.title) { group in
                    namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                }
            case .ethereum:
                ForEach(ethereumEndpointsByNetwork, id: \.title) { group in
                    namedEndpointGroup(title: group.title, endpoints: group.endpoints)
                }

                TextField(
                    copy.customEthereumRPCURLPlaceholder,
                    text: Binding(
                        get: { store.ethereumRPCEndpoint },
                        set: { store.ethereumRPCEndpoint = $0 }
                    )
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let error = store.ethereumRPCEndpointValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            case .ethereumClassic:
                endpointRows(ethereumClassicEndpoints)
                readOnlyFootnote
            case .arbitrum:
                endpointRows(arbitrumEndpoints)
                readOnlyFootnote
            case .optimism:
                endpointRows(optimismEndpoints)
                readOnlyFootnote
            case .bnb:
                endpointRows(bnbEndpoints)
                readOnlyFootnote
            case .avalanche:
                endpointRows(avalancheEndpoints)
                readOnlyFootnote
            case .hyperliquid:
                endpointRows(hyperliquidEndpoints)
                readOnlyFootnote
            case .tron:
                endpointRows(TronBalanceService.endpointCatalog())
            case .solana:
                endpointRows(SolanaBalanceService.endpointCatalog())
            case .cardano:
                endpointRows(CardanoBalanceService.endpointCatalog())
            case .xrp:
                endpointRows(XRPBalanceService.endpointCatalog())
            case .stellar:
                endpointRows(StellarBalanceService.endpointCatalog())
            case .monero:
                endpointRows(moneroEndpoints)

                TextField(
                    copy.customMoneroBackendURLPlaceholder,
                    text: Binding(
                        get: { store.moneroBackendBaseURL },
                        set: { store.moneroBackendBaseURL = $0 }
                    )
                )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let error = store.moneroBackendBaseURLValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            case .sui:
                endpointRows(SuiBalanceService.endpointCatalog())
            case .aptos:
                endpointRows(AptosBalanceService.endpointCatalog())
            case .ton:
                endpointRows(TONBalanceService.endpointCatalog())
            case .icp:
                endpointRows(ICPBalanceService.endpointCatalog())
            case .near:
                endpointRows(NearBalanceService.endpointCatalog())
            case .polkadot:
                endpointRows(PolkadotBalanceService.endpointCatalog())
            case .bitcoinSV:
                endpointRows(BitcoinSVBalanceService.endpointCatalog())
            }
        }
    }

    private var readOnlyFootnote: some View {
        Text(copy.readOnlyFootnote)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        Form {
            Section {
                Text(copy.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(endpointSections) { descriptor in
                endpointSection(descriptor)
            }
        }
        .navigationTitle(copy.navigationTitle)
    }
}
