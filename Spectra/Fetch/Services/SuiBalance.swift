import Foundation

enum SuiBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Sui")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Sui")
        case .rpcError(let message):
            return CommonLocalization.rpcError("Sui", message: message)
        }
    }
}

struct SuiHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct SuiHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct SuiTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}

struct SuiPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [SuiTokenBalanceSnapshot]
}

enum SuiBalanceService {
    static let suiCoinType = "0x2::sui::SUI"

    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }
    static func endpointCatalog() -> [String] {
        SuiProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        SuiProvider.diagnosticsChecks()
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidSuiAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizeAddress(address)
        guard isValidAddress(normalized) else {
            throw SuiBalanceServiceError.invalidAddress
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "suix_getBalance",
            "params": [normalized, suiCoinType]
        ]

        let result: SuiProvider.BalanceResult = try await postRPC(payload: payload)
        guard let totalBalance = result.totalBalance,
              let mist = Double(totalBalance),
              mist.isFinite,
              mist >= 0 else {
            throw SuiBalanceServiceError.invalidResponse
        }

        return mist / 1_000_000_000.0
    }

    static func fetchPortfolio(
        for address: String,
        trackedTokenMetadataByCoinType: [String: KnownTokenMetadata]
    ) async throws -> SuiPortfolioSnapshot {
        let normalized = normalizeAddress(address)
        guard isValidAddress(normalized) else {
            throw SuiBalanceServiceError.invalidAddress
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "suix_getAllBalances",
            "params": [normalized]
        ]

        let results: [SuiProvider.CoinBalanceResult] = try await postRPC(payload: payload)
        let trackedEntries = trackedTokenMetadataByCoinType.map { (normalizeCoinType($0.key), $0.value) }
        let trackedByCoinType = Dictionary(uniqueKeysWithValues: trackedEntries)
        let trackedByPackageAddress = Dictionary(
            uniqueKeysWithValues: trackedEntries.map { (packageAddress(from: $0.0), $0.1) }
        )

        var nativeBalance: Double = 0
        var tokenBalances: [SuiTokenBalanceSnapshot] = []

        for result in results {
            let normalizedCoinType = normalizeCoinType(result.coinType)
            guard let totalBalance = result.totalBalance,
                  let rawBalance = Double(totalBalance),
                  rawBalance.isFinite,
                  rawBalance >= 0 else {
                continue
            }

            if normalizedCoinType == normalizeCoinType(suiCoinType) {
                nativeBalance = rawBalance / 1_000_000_000.0
                continue
            }

            guard let metadata = trackedByCoinType[normalizedCoinType]
                ?? trackedByPackageAddress[packageAddress(from: normalizedCoinType)] else {
                continue
            }
            let divisor = pow(10, Double(min(max(metadata.decimals, 0), 18)))
            let balance = rawBalance / divisor
            guard balance.isFinite, balance > 0 else { continue }

            tokenBalances.append(
                SuiTokenBalanceSnapshot(
                    coinType: result.coinType ?? normalizedCoinType,
                    symbol: metadata.symbol,
                    name: metadata.name,
                    tokenStandard: metadata.tokenStandard,
                    decimals: metadata.decimals,
                    balance: balance,
                    marketDataID: metadata.marketDataID,
                    coinGeckoID: metadata.coinGeckoID
                )
            )
        }

        return SuiPortfolioSnapshot(nativeBalance: nativeBalance, tokenBalances: tokenBalances)
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 40) async -> (snapshots: [SuiHistorySnapshot], diagnostics: SuiHistoryDiagnostics) {
        let normalized = normalizeAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                SuiHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: SuiBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        var fromItems: [SuiProvider.TransactionBlock] = []
        var toItems: [SuiProvider.TransactionBlock] = []
        var errors: [String] = []

        do {
            fromItems = try await fetchTransactionBlocks(address: normalized, filterKey: "FromAddress", limit: limit)
        } catch {
            errors.append(error.localizedDescription)
        }

        do {
            toItems = try await fetchTransactionBlocks(address: normalized, filterKey: "ToAddress", limit: limit)
        } catch {
            errors.append(error.localizedDescription)
        }

        let firstError = errors.first

        if !fromItems.isEmpty || !toItems.isEmpty {
            var deduped: [String: SuiHistorySnapshot] = [:]
            for item in (fromItems + toItems) {
                guard let digest = item.digest, !digest.isEmpty else { continue }
                let snapshot = snapshotFromTransaction(item, ownerAddress: normalized)
                guard let snapshot else { continue }
                let key = digest.lowercased()
                if let existing = deduped[key] {
                    if snapshot.createdAt > existing.createdAt {
                        deduped[key] = snapshot
                    }
                } else {
                    deduped[key] = snapshot
                }
            }

            let sorted = deduped.values.sorted { $0.createdAt > $1.createdAt }
            return (
                sorted,
                SuiHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "sui-json-rpc",
                    transactionCount: sorted.count,
                    error: firstError
                )
            )
        }

        return (
            [],
            SuiHistoryDiagnostics(
                address: normalized,
                sourceUsed: "sui-json-rpc",
                transactionCount: 0,
                error: firstError ?? SuiBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    private static func fetchTransactionBlocks(address: String, filterKey: String, limit: Int) async throws -> [SuiProvider.TransactionBlock] {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "suix_queryTransactionBlocks",
            "params": [
                [
                    "filter": [filterKey: address],
                    "options": [
                        "showEffects": true,
                        "showInput": true,
                        "showBalanceChanges": true
                    ]
                ],
                NSNull(),
                max(1, min(limit, 100)),
                true
            ]
        ]

        let response: SuiProvider.QueryTxBlocksResponse = try await postRPC(payload: payload)
        return response.data ?? []
    }

    private static func snapshotFromTransaction(_ tx: SuiProvider.TransactionBlock, ownerAddress: String) -> SuiHistorySnapshot? {
        guard let digest = tx.digest, !digest.isEmpty else { return nil }

        let status: TransactionStatus = {
            let raw = tx.effects?.status?.status?.lowercased() ?? ""
            if raw == "success" {
                return .confirmed
            }
            if raw.isEmpty {
                return .pending
            }
            return .failed
        }()

        let sender = tx.transaction?.data?.sender?.lowercased() ?? ""

        var deltaMist: Double = 0
        if let changes = tx.balanceChanges {
            for change in changes {
                guard (change.coinType ?? "").caseInsensitiveCompare(suiCoinType) == .orderedSame,
                      let owner = change.owner?.addressOwner?.lowercased(),
                      owner == ownerAddress.lowercased(),
                      let amountText = change.amount,
                      let amount = Double(amountText),
                      amount.isFinite else {
                    continue
                }
                deltaMist += amount
            }
        }

        // Fallback when balanceChanges are missing for the tx query response.
        let inferredKind: TransactionKind
        if deltaMist == 0 {
            inferredKind = sender == ownerAddress.lowercased() ? .send : .receive
        } else {
            inferredKind = deltaMist < 0 ? .send : .receive
        }

        let amountSUI = abs(deltaMist) / 1_000_000_000.0
        let timestampMs = Double(tx.timestampMs ?? "") ?? 0
        let createdAt = timestampMs > 0 ? Date(timeIntervalSince1970: timestampMs / 1_000.0) : Date()

        return SuiHistorySnapshot(
            transactionHash: digest,
            kind: inferredKind,
            amount: amountSUI,
            counterpartyAddress: sender.isEmpty ? ownerAddress : sender,
            createdAt: createdAt,
            status: status
        )
    }

    private static func normalizeAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizeCoinType(_ coinType: String?) -> String {
        let trimmed = coinType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !trimmed.isEmpty else { return "" }

        let components = trimmed.split(separator: "::", omittingEmptySubsequences: false)
        guard let first = components.first else { return trimmed }

        let normalizedPackage = normalizeHexAddressComponent(String(first))
        guard components.count > 1 else { return normalizedPackage }
        return ([normalizedPackage] + components.dropFirst().map(String.init)).joined(separator: "::")
    }

    private static func packageAddress(from normalizedCoinType: String) -> String {
        guard let package = normalizedCoinType.split(separator: "::", omittingEmptySubsequences: false).first else {
            return normalizedCoinType
        }
        return String(package)
    }

    private static func normalizeHexAddressComponent(_ value: String) -> String {
        guard value.hasPrefix("0x") else { return value }
        let hexPortion = value.dropFirst(2)
        let trimmedHex = hexPortion.drop { $0 == "0" }
        let canonicalHex = trimmedHex.isEmpty ? "0" : String(trimmedHex)
        return "0x" + canonicalHex
    }

    private static func postRPC<ResultType: Decodable>(payload: [String: Any]) async throws -> ResultType {
        var lastError: Error?
        for endpoint in SuiProvider.rpcURLs {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw SuiBalanceServiceError.rpcError("HTTP \(code)")
                }

                let decoded = try JSONDecoder().decode(SuiProvider.RPCEnvelope<ResultType>.self, from: data)
                if let result = decoded.result {
                    return result
                }

                let message = decoded.error?.message ?? "Unknown Sui RPC error"
                throw SuiBalanceServiceError.rpcError(message)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw SuiBalanceServiceError.rpcError(lastError?.localizedDescription ?? "Unknown Sui RPC error")
    }
}
