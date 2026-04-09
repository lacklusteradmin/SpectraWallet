import Foundation

enum AppEndpointRole: String, Hashable, CaseIterable, Decodable {
    case read
    case balance
    case history
    case utxo
    case fee
    case broadcast
    case verification
    case rpc
    case explorer
    case backend
}

struct AppEndpointRecord: Hashable, Decodable {
    let id: String
    let chainName: String
    let groupTitle: String
    let providerID: String
    let endpoint: String
    let roles: Set<AppEndpointRole>
    let probeURL: String?
    let settingsVisible: Bool
    let explorerLabel: String?

    init(
        id: String,
        chainName: String,
        groupTitle: String? = nil,
        providerID: String,
        endpoint: String,
        roles: Set<AppEndpointRole>,
        probeURL: String? = nil,
        settingsVisible: Bool = true,
        explorerLabel: String? = nil
    ) {
        self.id = id
        self.chainName = chainName
        self.groupTitle = groupTitle ?? chainName
        self.providerID = providerID
        self.endpoint = endpoint
        self.roles = roles
        self.probeURL = probeURL
        self.settingsVisible = settingsVisible
        self.explorerLabel = explorerLabel
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case chainName
        case groupTitle
        case providerID
        case endpoint
        case roles
        case probeURL
        case settingsVisible
        case explorerLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let chainName = try container.decode(String.self, forKey: .chainName)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            chainName: chainName,
            groupTitle: try container.decodeIfPresent(String.self, forKey: .groupTitle) ?? chainName,
            providerID: try container.decode(String.self, forKey: .providerID),
            endpoint: try container.decode(String.self, forKey: .endpoint),
            roles: try container.decode(Set<AppEndpointRole>.self, forKey: .roles),
            probeURL: try container.decodeIfPresent(String.self, forKey: .probeURL),
            settingsVisible: try container.decode(Bool.self, forKey: .settingsVisible),
            explorerLabel: try container.decodeIfPresent(String.self, forKey: .explorerLabel)
        )
    }
}

enum AppEndpointDirectory {
    static let records: [AppEndpointRecord] = loadRecords()

    static func endpoint(_ id: String) -> String {
        do {
            return try WalletRustEndpointCatalogBridge.endpoint(id)
        } catch {
            preconditionFailure("Rust endpoint lookup failed for id \(id): \(error.localizedDescription)")
        }
    }

    static func endpoints(for ids: [String]) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.endpoints(for: ids)
        } catch {
            preconditionFailure("Rust endpoint lookup failed for ids \(ids): \(error.localizedDescription)")
        }
    }

    static func endpointRecords(
        for chainName: String,
        roles: Set<AppEndpointRole>? = nil,
        settingsVisibleOnly: Bool = false
    ) -> [AppEndpointRecord] {
        do {
            return try WalletRustEndpointCatalogBridge.endpointRecords(
                for: chainName,
                roles: roles ?? [],
                settingsVisibleOnly: settingsVisibleOnly
            )
        } catch {
            preconditionFailure("Rust endpoint records failed for \(chainName): \(error.localizedDescription)")
        }
    }

    static func groupedSettingsEntries(for chainName: String) -> [(title: String, endpoints: [String])] {
        do {
            return try WalletRustEndpointCatalogBridge.groupedSettingsEntries(for: chainName).map {
                (title: $0.title, endpoints: $0.endpoints)
            }
        } catch {
            preconditionFailure("Rust grouped settings entries failed for \(chainName): \(error.localizedDescription)")
        }
    }

    static func settingsEndpoints(for chainName: String) -> [String] {
        groupedSettingsEntries(for: chainName).flatMap(\.endpoints)
    }

    static func diagnosticsChecks(for chainName: String) -> [(endpoint: String, probeURL: String)] {
        do {
            return try WalletRustEndpointCatalogBridge.diagnosticsChecks(for: chainName).map {
                (endpoint: $0.endpoint, probeURL: $0.probeURL)
            }
        } catch {
            preconditionFailure("Rust diagnostics checks failed for \(chainName): \(error.localizedDescription)")
        }
    }

    static func evmRPCEndpoints(for chainName: String) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.evmRPCEndpoints(for: chainName)
        } catch {
            preconditionFailure("Rust EVM RPC lookup failed for \(chainName): \(error.localizedDescription)")
        }
    }

    static func explorerSupplementalEndpoints(for chainName: String) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.explorerSupplementalEndpoints(for: chainName)
        } catch {
            preconditionFailure("Rust explorer endpoint lookup failed for \(chainName): \(error.localizedDescription)")
        }
    }

    static func transactionExplorerBaseURL(for chainName: String) -> String? {
        do {
            return try WalletRustEndpointCatalogBridge.transactionExplorerEntry(for: chainName)?.endpoint
        } catch {
            preconditionFailure("Rust transaction explorer lookup failed for \(chainName): \(error.localizedDescription)")
        }
    }

    static func transactionExplorerLabel(for chainName: String) -> String? {
        do {
            return try WalletRustEndpointCatalogBridge.transactionExplorerEntry(for: chainName)?.label
        } catch {
            preconditionFailure("Rust transaction explorer label lookup failed for \(chainName): \(error.localizedDescription)")
        }
    }

    static func bitcoinEsploraBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.bitcoinEsploraBaseURLs(for: networkMode)
        } catch {
            preconditionFailure("Rust Bitcoin Esplora lookup failed for \(networkMode.rawValue): \(error.localizedDescription)")
        }
    }

    static func bitcoinWalletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
        do {
            return try WalletRustEndpointCatalogBridge.bitcoinWalletStoreDefaultBaseURLs(for: networkMode)
        } catch {
            preconditionFailure("Rust Bitcoin wallet-store lookup failed for \(networkMode.rawValue): \(error.localizedDescription)")
        }
    }

    private static func loadRecords() -> [AppEndpointRecord] {
        do {
            return try WalletRustEndpointCatalogBridge.records()
        } catch {
            preconditionFailure("Rust endpoint catalog failed to load: \(error.localizedDescription)")
        }
    }
}
