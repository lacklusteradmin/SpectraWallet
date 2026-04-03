import Foundation

enum EsploraProvider {
    enum ProviderID: String, CaseIterable {
        case blockstream
        case mempool
        case mempoolEmzy
        case maestro
    }

    struct AddressResponse: Decodable {
        let chainStats: AddressStats
        let mempoolStats: AddressStats

        enum CodingKeys: String, CodingKey {
            case chainStats = "chain_stats"
            case mempoolStats = "mempool_stats"
        }
    }

    struct AddressStats: Decodable {
        let fundedTXOSum: Int64
        let spentTXOSum: Int64
        let txCount: Int

        enum CodingKeys: String, CodingKey {
            case fundedTXOSum = "funded_txo_sum"
            case spentTXOSum = "spent_txo_sum"
            case txCount = "tx_count"
        }
    }

    struct TransactionStatus: Decodable {
        let confirmed: Bool
        let blockHeight: Int?

        enum CodingKeys: String, CodingKey {
            case confirmed
            case blockHeight = "block_height"
        }
    }

    struct AddressTransaction: Decodable {
        struct VIN: Decodable {
            struct Prevout: Decodable {
                let scriptpubkeyAddress: String?
                let value: Int64

                enum CodingKeys: String, CodingKey {
                    case scriptpubkeyAddress = "scriptpubkey_address"
                    case value
                }
            }

            let prevout: Prevout?
        }

        struct VOUT: Decodable {
            let scriptpubkeyAddress: String?
            let value: Int64

            enum CodingKeys: String, CodingKey {
                case scriptpubkeyAddress = "scriptpubkey_address"
                case value
            }
        }

        struct Status: Decodable {
            let confirmed: Bool
            let blockHeight: Int?
            let blockTime: TimeInterval?

            enum CodingKeys: String, CodingKey {
                case confirmed
                case blockHeight = "block_height"
                case blockTime = "block_time"
            }
        }

        let txid: String
        let vin: [VIN]
        let vout: [VOUT]
        let status: Status
    }

    static func defaultBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
        ChainBackendRegistry.BitcoinRuntimeEndpoints.esploraBaseURLs(for: networkMode)
    }

    static func runtimeBaseURLs(for networkMode: BitcoinNetworkMode, custom: [String] = []) -> [String] {
        let trimmed = custom
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !trimmed.isEmpty {
            return trimmed
        }
        return defaultBaseURLs(for: networkMode)
    }

    static func filteredBaseURLs(
        for networkMode: BitcoinNetworkMode,
        custom: [String] = [],
        providerIDs: Set<String>? = nil
    ) -> [String] {
        let allEndpoints = runtimeBaseURLs(for: networkMode, custom: custom)
        guard let providerIDs, !providerIDs.isEmpty else {
            return allEndpoints
        }

        let normalized = Set(providerIDs.map { $0.lowercased() })
        let allowEsplora = normalized.contains("esplora")
        let allowMaestro = normalized.contains("maestro-esplora")
        let filtered = allEndpoints.filter { endpoint in
            let isMaestro = endpoint.contains("gomaestro-api.org")
            return isMaestro ? allowMaestro : allowEsplora
        }
        return filtered.isEmpty ? allEndpoints : filtered
    }

    static func url(baseURL: String, path: String) -> URL? {
        URL(string: baseURL + path)
    }

    static func runWithFallback<T>(
        baseURLs: [String],
        operation: @escaping (String) async throws -> T
    ) async throws -> T {
        var firstError: Error?
        var lastError: Error?
        for baseURL in baseURLs {
            do {
                return try await operation(baseURL)
            } catch {
                if firstError == nil {
                    firstError = error
                }
                lastError = error
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw firstError ?? lastError ?? URLError(.cannotLoadFromNetwork)
    }
}
