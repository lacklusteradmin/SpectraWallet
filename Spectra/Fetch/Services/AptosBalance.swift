import Foundation

enum AptosBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Aptos")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Aptos")
        case .rpcError(let message):
            return CommonLocalization.rpcError("Aptos", message: message)
        }
    }
}

struct AptosHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct AptosHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct AptosTokenBalanceSnapshot: Equatable {
    let coinType: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}

struct AptosPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [AptosTokenBalanceSnapshot]
}

enum AptosBalanceService {
    static let aptosCoinType = "0x1::aptos_coin::aptoscoin"

    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }

    static func endpointCatalog() -> [String] {
        AptosProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        AptosProvider.diagnosticsChecks()
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidAptosAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizeAddress(address)
        guard isValidAddress(normalized) else {
            throw AptosBalanceServiceError.invalidAddress
        }

        let resourcePath = "accounts/\(normalized)/resource/0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>"
        var request = URLRequest(url: AptosProvider.endpoints[0].appendingPathComponent(resourcePath))
        request.httpMethod = "GET"
        let result: AptosProvider.CoinStoreResource = try await get(request)
        guard let value = result.data?.coin?.value, let octas = Double(value), octas.isFinite, octas >= 0 else {
            throw AptosBalanceServiceError.invalidResponse
        }
        return octas / 100_000_000.0
    }

    static func fetchPortfolio(
        for address: String,
        trackedTokenMetadataByType: [String: KnownTokenMetadata]
    ) async throws -> AptosPortfolioSnapshot {
        let normalized = normalizeAddress(address)
        guard isValidAddress(normalized) else {
            throw AptosBalanceServiceError.invalidAddress
        }

        let trackedByType = Dictionary(
            uniqueKeysWithValues: trackedTokenMetadataByType.map { (normalizeCoinType($0.key), $0.value) }
        )
        let trackedFungibleAssets: [String: KnownTokenMetadata] = Dictionary(
            uniqueKeysWithValues: trackedByType.compactMap { element -> (String, KnownTokenMetadata)? in
                let (identifier, metadata) = element
                return (normalizeAddress(identifier), metadata)
            }
        )
        let trackedByPackageAddress: [String: KnownTokenMetadata] = Dictionary(
            uniqueKeysWithValues: trackedByType.compactMap { element -> (String, KnownTokenMetadata)? in
                let (identifier, metadata) = element
                return (packageAddress(from: identifier), metadata)
            }
        )
        let resourcePath = "accounts/\(normalized)/resources"
        var request = URLRequest(url: AptosProvider.endpoints[0].appendingPathComponent(resourcePath))
        request.httpMethod = "GET"

        let resources: [AptosProvider.AccountResource] = try await get(request)
        var nativeBalance: Double = 0
        var tokenBalances: [AptosTokenBalanceSnapshot] = []

        for resource in resources {
            guard let resourceType = resource.type,
                  let coinType = extractCoinType(from: resourceType),
                  let rawValue = resource.data?.coin?.value,
                  let atomicBalance = Decimal(string: rawValue),
                  atomicBalance.isFinite,
                  atomicBalance >= 0 else {
                continue
            }

            let normalizedCoinType = normalizeCoinType(coinType)
            if normalizedCoinType == aptosCoinType {
                nativeBalance = decimalToDouble(atomicBalance / Decimal(100_000_000))
                continue
            }

            guard let metadata = trackedByType[normalizedCoinType] ?? trackedByPackageAddress[packageAddress(from: normalizedCoinType)] else {
                continue
            }
            let divisor = decimalPowerOfTen(min(max(metadata.decimals, 0), 30))
            let balance = decimalToDouble(atomicBalance / divisor)
            guard balance.isFinite, balance > 0 else { continue }

            tokenBalances.append(
                AptosTokenBalanceSnapshot(
                    coinType: normalizedCoinType,
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

        for (metadataAddress, metadata) in trackedFungibleAssets {
            do {
                let atomicBalance = try await fetchFungibleAssetBalance(
                    ownerAddress: normalized,
                    metadataAddress: metadataAddress
                )
                guard atomicBalance > 0 else { continue }
                let divisor = decimalPowerOfTen(min(max(metadata.decimals, 0), 30))
                let balance = decimalToDouble(atomicBalance / divisor)
                guard balance.isFinite, balance > 0 else { continue }

                tokenBalances.append(
                    AptosTokenBalanceSnapshot(
                        coinType: metadataAddress,
                        symbol: metadata.symbol,
                        name: metadata.name,
                        tokenStandard: metadata.tokenStandard,
                        decimals: metadata.decimals,
                        balance: balance,
                        marketDataID: metadata.marketDataID,
                        coinGeckoID: metadata.coinGeckoID
                    )
                )
            } catch {
                continue
            }
        }

        return AptosPortfolioSnapshot(nativeBalance: nativeBalance, tokenBalances: tokenBalances)
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 40) async -> (snapshots: [AptosHistorySnapshot], diagnostics: AptosHistoryDiagnostics) {
        let normalized = normalizeAddress(address)
        guard isValidAddress(normalized) else {
            return ([], AptosHistoryDiagnostics(address: normalized, sourceUsed: "none", transactionCount: 0, error: AptosBalanceServiceError.invalidAddress.localizedDescription))
        }

        do {
            var request = URLRequest(url: AptosProvider.endpoints[0].appendingPathComponent("accounts/\(normalized)/transactions"))
            request.httpMethod = "GET"
            request.url = URL(string: request.url!.absoluteString + "?limit=\(max(1, min(limit, 100)))")
            let items: [AptosProvider.TransactionItem] = try await get(request)
            let snapshots = items.compactMap { snapshot(from: $0, ownerAddress: normalized) }
            return (snapshots, AptosHistoryDiagnostics(address: normalized, sourceUsed: "aptos-rest", transactionCount: snapshots.count, error: nil))
        } catch {
            return ([], AptosHistoryDiagnostics(address: normalized, sourceUsed: "aptos-rest", transactionCount: 0, error: error.localizedDescription))
        }
    }

    private static func snapshot(from item: AptosProvider.TransactionItem, ownerAddress: String) -> AptosHistorySnapshot? {
        guard (item.type ?? "").lowercased().contains("user_transaction"),
              let hash = item.hash, !hash.isEmpty else {
            return nil
        }

        let function = item.payload?.function?.lowercased() ?? ""
        guard function.contains("transfer") else { return nil }
        let arguments = item.payload?.arguments ?? []
        guard arguments.count >= 2, let amountOctas = Double(arguments[1]), amountOctas.isFinite else {
            return nil
        }

        let sender = normalizeAddress(item.sender ?? "")
        let recipient = normalizeAddress(arguments[0])
        let kind: TransactionKind = sender == ownerAddress.lowercased() ? .send : .receive
        let counterparty = kind == .send ? recipient : sender
        let timestampValue = Double(item.timestamp ?? "") ?? 0
        let createdAt = timestampValue > 0 ? Date(timeIntervalSince1970: timestampValue / 1_000_000.0) : Date()

        return AptosHistorySnapshot(
            transactionHash: hash,
            kind: kind,
            amount: amountOctas / 100_000_000.0,
            counterpartyAddress: counterparty.isEmpty ? ownerAddress : counterparty,
            createdAt: createdAt,
            status: (item.success == false) ? .failed : .confirmed
        )
    }

    private static func get<ResultType: Decodable>(_ request: URLRequest) async throws -> ResultType {
        var lastError: Error?
        for endpoint in AptosProvider.endpoints {
            var request = request
            if let absolute = request.url?.absoluteString {
                let suffix = absolute.replacingOccurrences(of: AptosProvider.endpoints[0].absoluteString, with: "")
                request.url = URL(string: endpoint.absoluteString + suffix)
            } else if let original = request.url?.path {
                request.url = endpoint.appendingPathComponent(original)
            }

            do {
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse else {
                    throw AptosBalanceServiceError.rpcError("Missing HTTP response")
                }
                if http.statusCode == 404 {
                    if ResultType.self == AptosProvider.CoinStoreResource.self {
                        let zero = AptosProvider.CoinStoreResource(data: .init(coin: .init(value: "0")))
                        return zero as! ResultType
                    }
                    if ResultType.self == [AptosProvider.AccountResource].self {
                        return [] as! ResultType
                    }
                    if ResultType.self == [AptosProvider.TransactionItem].self {
                        return [] as! ResultType
                    }
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw AptosBalanceServiceError.rpcError("HTTP \(http.statusCode)")
                }
                return try JSONDecoder().decode(ResultType.self, from: data)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw AptosBalanceServiceError.rpcError(lastError?.localizedDescription ?? "Unknown Aptos RPC error")
    }

    private static func post<Body: Encodable, ResultType: Decodable>(
        _ body: Body,
        path: String
    ) async throws -> ResultType {
        let encoded = try JSONEncoder().encode(body)
        var lastError: Error?
        for endpoint in AptosProvider.endpoints {
            do {
                var request = URLRequest(url: endpoint.appendingPathComponent(path))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = encoded
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse else {
                    throw AptosBalanceServiceError.rpcError("Missing HTTP response")
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw AptosBalanceServiceError.rpcError("HTTP \(http.statusCode)")
                }
                return try JSONDecoder().decode(ResultType.self, from: data)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
        throw AptosBalanceServiceError.rpcError(lastError?.localizedDescription ?? "Unknown Aptos RPC error")
    }

    private static func normalizeAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("0x") ? trimmed : "0x\(trimmed)"
    }

    private static func normalizeCoinType(_ value: String) -> String {
        let lowercased = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return "" }

        var result = ""
        var index = lowercased.startIndex
        while index < lowercased.endIndex {
            if lowercased[index...].hasPrefix("0x") {
                let start = index
                var end = lowercased.index(index, offsetBy: 2)
                while end < lowercased.endIndex, lowercased[end].isHexDigit {
                    end = lowercased.index(after: end)
                }
                result += canonicalHexAddress(String(lowercased[start..<end]))
                index = end
            } else {
                result.append(lowercased[index])
                index = lowercased.index(after: index)
            }
        }
        return result
    }

    private static func canonicalHexAddress(_ value: String) -> String {
        guard value.hasPrefix("0x") else { return value }
        let hex = value.dropFirst(2)
        let trimmed = hex.drop { $0 == "0" }
        return "0x" + (trimmed.isEmpty ? "0" : String(trimmed))
    }

    private static func extractCoinType(from resourceType: String) -> String? {
        guard let start = resourceType.range(of: "CoinStore<")?.upperBound,
              let end = resourceType.lastIndex(of: ">"),
              start <= end else {
            return nil
        }
        return String(resourceType[start..<end])
    }

    private static func fetchFungibleAssetBalance(ownerAddress: String, metadataAddress: String) async throws -> Decimal {
        let request = AptosProvider.ViewFunctionRequest(
            function: "0x1::primary_fungible_store::balance",
            typeArguments: ["0x1::fungible_asset::Metadata"],
            arguments: [normalizeAddress(ownerAddress), normalizeAddress(metadataAddress)]
        )
        let result: [String] = try await post(request, path: "view")
        guard let first = result.first, let balance = Decimal(string: first), balance.isFinite, balance >= 0 else {
            throw AptosBalanceServiceError.invalidResponse
        }
        return balance
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        var value = Decimal(1)
        for _ in 0..<max(exponent, 0) {
            value *= 10
        }
        return value
    }

    private static func packageAddress(from coinType: String) -> String {
        let normalized = normalizeCoinType(coinType)
        guard let package = normalized.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return normalized
        }
        return String(package)
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
