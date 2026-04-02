import Foundation
import BigInt
import WalletCore


extension EthereumWalletEngine {
private static func makeHistoryDiagnostics(
    address: String,
    rpcTransferCount: Int,
    rpcError: String?,
    blockscoutTransferCount: Int,
    blockscoutError: String?,
    etherscanTransferCount: Int,
    etherscanError: String?,
    ethplorerTransferCount: Int,
    ethplorerError: String?,
    sourceUsed: String,
    stats: EthereumTransferDecodingStats
) -> EthereumTokenTransferHistoryDiagnostics {
    let denominator = max(1, stats.scannedTransfers)
    let ratio = Double(stats.decodedSupportedTransfers) / Double(denominator)
    return EthereumTokenTransferHistoryDiagnostics(
        address: address,
        rpcTransferCount: rpcTransferCount,
        rpcError: rpcError,
        blockscoutTransferCount: blockscoutTransferCount,
        blockscoutError: blockscoutError,
        etherscanTransferCount: etherscanTransferCount,
        etherscanError: etherscanError,
        ethplorerTransferCount: ethplorerTransferCount,
        ethplorerError: ethplorerError,
        sourceUsed: sourceUsed,
        transferScanCount: stats.scannedTransfers,
        decodedTransferCount: stats.decodedSupportedTransfers,
        unsupportedTransferDropCount: stats.droppedUnsupportedTransfers,
        decodingCompletenessRatio: ratio
    )
}
static func fetchSupportedTokenTransferHistory(
    for address: String,
    rpcEndpoint: URL? = nil,
    etherscanAPIKey: String? = nil,
    maxResults: Int = 200,
    chain: EVMChainContext = .ethereum
) async throws -> [EthereumTokenTransferSnapshot] {
    let result = try await fetchSupportedTokenTransferHistoryWithDiagnostics(
        for: address,
        rpcEndpoint: rpcEndpoint,
        etherscanAPIKey: etherscanAPIKey,
        maxResults: maxResults,
        chain: chain
    )
    return result.snapshots
}

static func fetchSupportedTokenTransferHistoryPageWithDiagnostics(
    for address: String,
    rpcEndpoint: URL? = nil,
    etherscanAPIKey: String? = nil,
    page: Int = 1,
    pageSize: Int = 200,
    trackedTokens: [EthereumSupportedToken]? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> (snapshots: [EthereumTokenTransferSnapshot], diagnostics: EthereumTokenTransferHistoryDiagnostics) {
    let normalizedAddress = try validateAddress(address)
    let safePage = max(1, page)
    let safePageSize = max(1, min(pageSize, 500))
    let chainTokens = trackedTokens ?? supportedTokens(for: chain)
    if chain == .hyperliquid {
        let result = try await fetchTokenTransferHistoryFromHyperliquidExplorerAddressPage(
            normalizedAddress: normalizedAddress,
            chainTokens: chainTokens,
            maxResults: safePageSize,
            page: safePage,
            pageSize: safePageSize,
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: 0,
            blockscoutError: "Blockscout provider is not configured for \(chain.displayName).",
            etherscanTransferCount: result.snapshots.count,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: "Ethplorer provider is not configured for \(chain.displayName).",
            sourceUsed: "hyperliquid-explorer",
            stats: result.stats
        )
        return (result.snapshots, diagnostics)
    }
    let supportedTokensByContract = Dictionary(
        uniqueKeysWithValues: chainTokens.map { (normalizeAddress($0.contractAddress), $0) }
    )
    let supportedTokensBySymbol = Dictionary(
        uniqueKeysWithValues: chainTokens.map { ($0.symbol.uppercased(), $0) }
    )
    var blockscoutTransferCount = 0
    var blockscoutErrorMessage: String?
    var etherscanTransferCount = 0
    var etherscanErrorMessage: String?
    var ethplorerTransferCount = 0
    var ethplorerErrorMessage: String?
    var blockscoutStats = EthereumTransferDecodingStats.zero
    var etherscanStats = EthereumTransferDecodingStats.zero
    var ethplorerStats = EthereumTransferDecodingStats.zero

    let blockscoutPage: [EthereumTokenTransferSnapshot]
    if chain.isEthereumMainnet {
        do {
            let result = try await fetchTokenTransferHistoryFromBlockscout(
                normalizedAddress: normalizedAddress,
                supportedTokensByContract: supportedTokensByContract,
                supportedTokensBySymbol: supportedTokensBySymbol,
                maxResults: safePageSize,
                page: safePage,
                pageSize: safePageSize,
                chain: chain
            )
            blockscoutPage = result.snapshots
            blockscoutStats = result.stats
        } catch {
            blockscoutErrorMessage = error.localizedDescription
            blockscoutPage = []
        }
    } else {
        blockscoutErrorMessage = "Blockscout provider is not configured for \(chain.displayName)."
        blockscoutPage = []
    }
    blockscoutTransferCount = blockscoutPage.count
    if !blockscoutPage.isEmpty {
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: 0,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "blockscout",
            stats: blockscoutStats
        )
        return (blockscoutPage, diagnostics)
    }

    let etherscanPage: [EthereumTokenTransferSnapshot]
    do {
            let result = try await fetchTokenTransferHistoryFromEtherscan(
                normalizedAddress: normalizedAddress,
                chainTokens: chainTokens,
                supportedTokensByContract: supportedTokensByContract,
                supportedTokensBySymbol: supportedTokensBySymbol,
                apiKey: etherscanAPIKey,
            maxResults: safePageSize,
            page: safePage,
            pageSize: safePageSize,
            chain: chain
        )
        etherscanPage = result.snapshots
        etherscanStats = result.stats
    } catch {
        etherscanErrorMessage = error.localizedDescription
        etherscanPage = []
    }
    etherscanTransferCount = etherscanPage.count
    if !etherscanPage.isEmpty {
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: etherscanTransferCount,
            etherscanError: etherscanErrorMessage,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "etherscan",
            stats: EthereumTransferDecodingStats(
                scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers,
                decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers,
                droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers
            )
        )
        return (etherscanPage, diagnostics)
    }

    let ethplorerPage: [EthereumTokenTransferSnapshot]
    if chain.isEthereumMainnet {
        do {
            let result = try await fetchTokenTransferHistoryFromEthplorer(
                normalizedAddress: normalizedAddress,
                supportedTokensByContract: supportedTokensByContract,
                supportedTokensBySymbol: supportedTokensBySymbol,
                maxResults: safePageSize,
                page: safePage,
                pageSize: safePageSize,
                chain: chain
            )
            ethplorerPage = result.snapshots
            ethplorerStats = result.stats
        } catch {
            ethplorerErrorMessage = error.localizedDescription
            ethplorerPage = []
        }
    } else {
        ethplorerErrorMessage = "Ethplorer provider is not configured for \(chain.displayName)."
        ethplorerPage = []
    }
    ethplorerTransferCount = ethplorerPage.count
    if !ethplorerPage.isEmpty {
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: etherscanTransferCount,
            etherscanError: etherscanErrorMessage,
            ethplorerTransferCount: ethplorerTransferCount,
            ethplorerError: ethplorerErrorMessage,
            sourceUsed: "ethplorer",
            stats: EthereumTransferDecodingStats(
                scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
                decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
                droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
            )
        )
        return (ethplorerPage, diagnostics)
    }

    let diagnostics = makeHistoryDiagnostics(
        address: normalizedAddress,
        rpcTransferCount: 0,
        rpcError: "RPC fallback skipped to avoid long timeout on constrained networks.",
        blockscoutTransferCount: blockscoutTransferCount,
        blockscoutError: blockscoutErrorMessage,
        etherscanTransferCount: etherscanTransferCount,
        etherscanError: etherscanErrorMessage,
        ethplorerTransferCount: ethplorerTransferCount,
        ethplorerError: ethplorerErrorMessage,
        sourceUsed: "none",
        stats: EthereumTransferDecodingStats(
            scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
            decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
            droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
        )
    )
    return ([], diagnostics)
}

static func fetchSupportedTokenTransferHistoryWithDiagnostics(
    for address: String,
    rpcEndpoint: URL? = nil,
    etherscanAPIKey: String? = nil,
    maxResults: Int = 200,
    trackedTokens: [EthereumSupportedToken]? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> (snapshots: [EthereumTokenTransferSnapshot], diagnostics: EthereumTokenTransferHistoryDiagnostics) {
    let normalizedAddress = try validateAddress(address)

    let chainTokens = trackedTokens ?? supportedTokens(for: chain)
    if chain == .hyperliquid {
        let result = try await fetchTokenTransferHistoryFromHyperliquidExplorerAddressPage(
            normalizedAddress: normalizedAddress,
            chainTokens: chainTokens,
            maxResults: maxResults,
            page: 1,
            pageSize: maxResults,
            rpcEndpoint: rpcEndpoint,
            chain: chain
        )
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: 0,
            blockscoutError: "Blockscout provider is not configured for \(chain.displayName).",
            etherscanTransferCount: result.snapshots.count,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: "Ethplorer provider is not configured for \(chain.displayName).",
            sourceUsed: "hyperliquid-explorer",
            stats: result.stats
        )
        return (Array(result.snapshots.prefix(maxResults)), diagnostics)
    }
    let supportedTokensByContract = Dictionary(
        uniqueKeysWithValues: chainTokens.map { (normalizeAddress($0.contractAddress), $0) }
    )
    let supportedTokensBySymbol = Dictionary(
        uniqueKeysWithValues: chainTokens.map { ($0.symbol.uppercased(), $0) }
    )
    var blockscoutTransferCount = 0
    var blockscoutErrorMessage: String?
    var etherscanTransferCount = 0
    var etherscanErrorMessage: String?
    var ethplorerTransferCount = 0
    var ethplorerErrorMessage: String?
    var blockscoutStats = EthereumTransferDecodingStats.zero
    var etherscanStats = EthereumTransferDecodingStats.zero
    var ethplorerStats = EthereumTransferDecodingStats.zero

    let blockscoutFallback: [EthereumTokenTransferSnapshot]
    if chain.isEthereumMainnet {
        do {
            let result = try await fetchTokenTransferHistoryFromBlockscout(
                normalizedAddress: normalizedAddress,
                supportedTokensByContract: supportedTokensByContract,
                supportedTokensBySymbol: supportedTokensBySymbol,
                maxResults: maxResults,
                chain: chain
            )
            blockscoutFallback = result.snapshots
            blockscoutStats = result.stats
        } catch {
            blockscoutErrorMessage = error.localizedDescription
            blockscoutFallback = []
        }
    } else {
        blockscoutErrorMessage = "Blockscout provider is not configured for \(chain.displayName)."
        blockscoutFallback = []
    }
    blockscoutTransferCount = blockscoutFallback.count
    if !blockscoutFallback.isEmpty {
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: 0,
            etherscanError: nil,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "blockscout",
            stats: blockscoutStats
        )
        return (Array(blockscoutFallback.prefix(maxResults)), diagnostics)
    }

    // Fast path for diagnostics and UI responsiveness.
    let etherscanFallback: [EthereumTokenTransferSnapshot]
    do {
        let result = try await fetchTokenTransferHistoryFromEtherscan(
            normalizedAddress: normalizedAddress,
            chainTokens: chainTokens,
            supportedTokensByContract: supportedTokensByContract,
            supportedTokensBySymbol: supportedTokensBySymbol,
            apiKey: etherscanAPIKey,
            maxResults: maxResults,
            chain: chain
        )
        etherscanFallback = result.snapshots
        etherscanStats = result.stats
    } catch {
        etherscanErrorMessage = error.localizedDescription
        etherscanFallback = []
    }
    etherscanTransferCount = etherscanFallback.count
    if !etherscanFallback.isEmpty {
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: etherscanTransferCount,
            etherscanError: etherscanErrorMessage,
            ethplorerTransferCount: 0,
            ethplorerError: nil,
            sourceUsed: "etherscan",
            stats: EthereumTransferDecodingStats(
                scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers,
                decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers,
                droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers
            )
        )
        return (Array(etherscanFallback.prefix(maxResults)), diagnostics)
    }

    let ethplorerFallback: [EthereumTokenTransferSnapshot]
    if chain.isEthereumMainnet {
        do {
            let result = try await fetchTokenTransferHistoryFromEthplorer(
                normalizedAddress: normalizedAddress,
                supportedTokensByContract: supportedTokensByContract,
                supportedTokensBySymbol: supportedTokensBySymbol,
                maxResults: maxResults,
                chain: chain
            )
            ethplorerFallback = result.snapshots
            ethplorerStats = result.stats
        } catch {
            ethplorerErrorMessage = error.localizedDescription
            ethplorerFallback = []
        }
    } else {
        ethplorerErrorMessage = "Ethplorer provider is not configured for \(chain.displayName)."
        ethplorerFallback = []
    }
    ethplorerTransferCount = ethplorerFallback.count
    if !ethplorerFallback.isEmpty {
        let diagnostics = makeHistoryDiagnostics(
            address: normalizedAddress,
            rpcTransferCount: 0,
            rpcError: nil,
            blockscoutTransferCount: blockscoutTransferCount,
            blockscoutError: blockscoutErrorMessage,
            etherscanTransferCount: etherscanTransferCount,
            etherscanError: etherscanErrorMessage,
            ethplorerTransferCount: ethplorerTransferCount,
            ethplorerError: ethplorerErrorMessage,
            sourceUsed: "ethplorer",
            stats: EthereumTransferDecodingStats(
                scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
                decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
                droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
            )
        )
        return (Array(ethplorerFallback.prefix(maxResults)), diagnostics)
    }

    let diagnostics = makeHistoryDiagnostics(
        address: normalizedAddress,
        rpcTransferCount: 0,
        rpcError: "RPC fallback skipped to avoid long timeout on constrained networks.",
        blockscoutTransferCount: blockscoutTransferCount,
        blockscoutError: blockscoutErrorMessage,
        etherscanTransferCount: etherscanTransferCount,
        etherscanError: etherscanErrorMessage,
        ethplorerTransferCount: ethplorerTransferCount,
        ethplorerError: ethplorerErrorMessage,
        sourceUsed: "none",
        stats: EthereumTransferDecodingStats(
            scannedTransfers: blockscoutStats.scannedTransfers + etherscanStats.scannedTransfers + ethplorerStats.scannedTransfers,
            decodedSupportedTransfers: blockscoutStats.decodedSupportedTransfers + etherscanStats.decodedSupportedTransfers + ethplorerStats.decodedSupportedTransfers,
            droppedUnsupportedTransfers: blockscoutStats.droppedUnsupportedTransfers + etherscanStats.droppedUnsupportedTransfers + ethplorerStats.droppedUnsupportedTransfers
        )
    )
    return ([], diagnostics)
}

private static func etherscanAPIURL(for chain: EVMChainContext) -> URL? {
    if chain.isEthereumFamily {
        return URL(string: "https://api.etherscan.io/v2/api")
    }
    return ChainBackendRegistry.EVMExplorerRegistry.etherscanStyleAPIURL(for: chain.displayName)
}

private static func blockscoutTokenTransfersURL(
    for chain: EVMChainContext,
    normalizedAddress: String,
    page: Int,
    pageSize: Int
) -> URL? {
    ChainBackendRegistry.EVMExplorerRegistry.blockscoutTokenTransfersURL(
        for: chain.displayName,
        normalizedAddress: normalizedAddress,
        page: page,
        pageSize: pageSize
    )
}

private static func blockscoutAccountAPIURL(
    for chain: EVMChainContext,
    normalizedAddress: String,
    action: String,
    page: Int,
    pageSize: Int
) -> URL? {
    ChainBackendRegistry.EVMExplorerRegistry.blockscoutAccountAPIURL(
        for: chain.displayName,
        normalizedAddress: normalizedAddress,
        action: action,
        page: page,
        pageSize: pageSize
    )
}

private static func ethplorerHistoryURL(
    for chain: EVMChainContext,
    normalizedAddress: String,
    requestedLimit: Int
) -> URL? {
    ChainBackendRegistry.EVMExplorerRegistry.ethplorerHistoryURL(
        for: chain.displayName,
        normalizedAddress: normalizedAddress,
        requestedLimit: requestedLimit
    )
}


private static func fetchTokenTransferHistoryFromEtherscan(
    normalizedAddress: String,
    chainTokens: [EthereumSupportedToken],
    supportedTokensByContract: [String: EthereumSupportedToken],
    supportedTokensBySymbol: [String: EthereumSupportedToken],
    apiKey: String?,
    maxResults: Int,
    page: Int = 1,
    pageSize: Int? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
    let trimmedAPIKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let safePage = max(1, page)
    let effectivePageSize = max(10, min(pageSize ?? maxResults, 500))
    var transfers: [EthereumTokenTransferSnapshot] = []
    var scannedTransfers = 0
    var decodedSupportedTransfers = 0
    var droppedUnsupportedTransfers = 0
    for token in chainTokens {
        guard let baseURL = etherscanAPIURL(for: chain) else { continue }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokentx"),
            URLQueryItem(name: "address", value: normalizedAddress),
            URLQueryItem(name: "contractaddress", value: token.contractAddress),
            URLQueryItem(name: "page", value: String(safePage)),
            URLQueryItem(name: "offset", value: String(effectivePageSize)),
            URLQueryItem(name: "sort", value: "desc")
        ]
        if !trimmedAPIKey.isEmpty {
            queryItems.append(URLQueryItem(name: "apikey", value: trimmedAPIKey))
        }
        switch chain {
        case .ethereum, .ethereumSepolia, .ethereumHoodi:
            queryItems.insert(URLQueryItem(name: "chainid", value: String(chain.expectedChainID)), at: 0)
        case .arbitrum:
            queryItems.insert(URLQueryItem(name: "chainid", value: "42161"), at: 0)
        case .optimism:
            queryItems.insert(URLQueryItem(name: "chainid", value: "10"), at: 0)
        case .hyperliquid:
            queryItems.insert(URLQueryItem(name: "chainid", value: "999"), at: 0)
        default:
            break
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { continue }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await fetchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            continue
        }

        let decoded = try JSONDecoder().decode(EtherscanTokenTransferResponse.self, from: data)
        if let status = decoded.status, status != "1" {
            let message = decoded.message ?? "Unknown Etherscan response"
            let reason = decoded.resultText ?? message
            if reason.lowercased().contains("no transactions") {
                continue
            }
            if reason.lowercased().contains("missing/invalid api key") {
                continue
            }
            throw EthereumWalletEngineError.rpcFailure("Etherscan: \(reason)")
        }
        let items = decoded.result
        guard !items.isEmpty else { continue }
        scannedTransfers += items.count

        for (index, item) in items.enumerated() {
            let contract = normalizeAddress(item.contractAddress)
            let normalizedSymbol = item.tokenSymbol.uppercased()
            guard let resolvedToken = supportedTokensByContract[contract] ?? supportedTokensBySymbol[normalizedSymbol] else {
                droppedUnsupportedTransfers += 1
                continue
            }

            let fromAddress = normalizeAddress(item.from)
            let toAddress = normalizeAddress(item.to)
            guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
                continue
            }

            guard let blockNumber = Int(item.blockNumber),
                  let timestampSeconds = TimeInterval(item.timeStamp),
                  let amountUnits = Decimal(string: item.value) else {
                continue
            }
            let decimals = Int(item.tokenDecimal) ?? resolvedToken.decimals
            let amount = amountUnits / decimalPowerOfTen(decimals)

            transfers.append(
                EthereumTokenTransferSnapshot(
                    contractAddress: resolvedToken.contractAddress,
                    tokenName: resolvedToken.name,
                    symbol: resolvedToken.symbol,
                    decimals: resolvedToken.decimals,
                    fromAddress: fromAddress,
                    toAddress: toAddress,
                    amount: amount,
                    transactionHash: item.hash,
                    blockNumber: blockNumber,
                    logIndex: max(0, items.count - index),
                    timestamp: Date(timeIntervalSince1970: timestampSeconds)
                )
            )
            decodedSupportedTransfers += 1
        }
    }

    var seen: Set<String> = []
    transfers = transfers.filter { transfer in
        let key = "\(transfer.transactionHash.lowercased())-\(transfer.symbol)-\(transfer.fromAddress)-\(transfer.toAddress)-\(transfer.amount)"
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }
    transfers.sort { lhs, rhs in
        if lhs.blockNumber != rhs.blockNumber {
            return lhs.blockNumber > rhs.blockNumber
        }
        return lhs.logIndex > rhs.logIndex
    }
    return (
        Array(transfers.prefix(effectivePageSize)),
        EthereumTransferDecodingStats(
            scannedTransfers: scannedTransfers,
            decodedSupportedTransfers: decodedSupportedTransfers,
            droppedUnsupportedTransfers: droppedUnsupportedTransfers
        )
    )
}

static func fetchNativeTransferHistoryPageFromEtherscan(
    for normalizedAddress: String,
    apiKey: String?,
    page: Int = 1,
    pageSize: Int = 100,
    chain: EVMChainContext = .ethereum
) async throws -> [EthereumNativeTransferSnapshot] {
    if chain == .hyperliquid {
        return try await fetchNativeTransferHistoryPageFromHyperliquidExplorerAddressPage(
            normalizedAddress: normalizedAddress,
            page: page,
            pageSize: pageSize,
            chain: chain
        )
    }
    let trimmedAPIKey = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let baseURL = etherscanAPIURL(for: chain) else {
        return []
    }

    let safePage = max(1, page)
    let effectivePageSize = max(10, min(pageSize, 500))
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    var queryItems = [
        URLQueryItem(name: "module", value: "account"),
        URLQueryItem(name: "action", value: "txlist"),
        URLQueryItem(name: "address", value: normalizedAddress),
        URLQueryItem(name: "page", value: String(safePage)),
        URLQueryItem(name: "offset", value: String(effectivePageSize)),
        URLQueryItem(name: "sort", value: "desc")
    ]
    if !trimmedAPIKey.isEmpty {
        queryItems.append(URLQueryItem(name: "apikey", value: trimmedAPIKey))
    }
    switch chain {
    case .ethereum, .ethereumSepolia, .ethereumHoodi:
        queryItems.insert(URLQueryItem(name: "chainid", value: String(chain.expectedChainID)), at: 0)
    case .arbitrum:
        queryItems.insert(URLQueryItem(name: "chainid", value: "42161"), at: 0)
    case .optimism:
        queryItems.insert(URLQueryItem(name: "chainid", value: "10"), at: 0)
    case .hyperliquid:
        queryItems.insert(URLQueryItem(name: "chainid", value: "999"), at: 0)
    default:
        break
    }
    components?.queryItems = queryItems
    guard let url = components?.url else { return [] }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode) else {
        return []
    }

    let decoded = try JSONDecoder().decode(EtherscanNormalTransactionResponse.self, from: data)
    if let status = decoded.status, status != "1" {
        let message = decoded.message ?? "Unknown Etherscan response"
        let reason = decoded.resultText ?? message
        if reason.lowercased().contains("no transactions") {
            return []
        }
        if reason.lowercased().contains("missing/invalid api key") {
            return []
        }
        throw EthereumWalletEngineError.rpcFailure("Etherscan: \(reason)")
    }

    return decoded.result.compactMap { item in
        let fromAddress = normalizeAddress(item.from)
        let toAddress = normalizeAddress(item.to)
        guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
            return nil
        }
        if item.isError == "1" || item.txreceipt_status == "0" {
            return nil
        }
        guard let blockNumber = Int(item.blockNumber),
              let timestampSeconds = TimeInterval(item.timeStamp),
              let amountWei = Decimal(string: item.value) else {
            return nil
        }
        let amount = amountWei / decimalPowerOfTen(18)

        return EthereumNativeTransferSnapshot(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            transactionHash: item.hash,
            blockNumber: blockNumber,
            timestamp: Date(timeIntervalSince1970: timestampSeconds)
        )
    }
}

static func fetchNativeTransferHistoryPageFromBlockscout(
    for normalizedAddress: String,
    page: Int = 1,
    pageSize: Int = 100,
    chain: EVMChainContext = .ethereum
) async throws -> [EthereumNativeTransferSnapshot] {
    guard let url = blockscoutAccountAPIURL(
        for: chain,
        normalizedAddress: normalizedAddress,
        action: "txlist",
        page: page,
        pageSize: pageSize
    ) else {
        return []
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode) else {
        return []
    }

    let decoded = try JSONDecoder().decode(BlockscoutNormalTransactionsResponse.self, from: data)
    guard !decoded.items.isEmpty else { return [] }

    return decoded.items.compactMap { item in
        guard item.result?.lowercased() != "error" else {
            return nil
        }
        guard let fromHash = item.from?.hash,
              let toHash = item.to?.hash else {
            return nil
        }
        let fromAddress = normalizeAddress(fromHash)
        let toAddress = normalizeAddress(toHash)
        guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
            return nil
        }
        guard let blockNumber = item.block?.height,
              let timestampRaw = item.timestamp,
              let timestamp = iso8601Formatter.date(from: timestampRaw),
              let valueRaw = item.value,
              let amountWei = Decimal(string: valueRaw) else {
            return nil
        }

        return EthereumNativeTransferSnapshot(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amountWei / decimalPowerOfTen(18),
            transactionHash: item.hash ?? "",
            blockNumber: blockNumber,
            timestamp: timestamp
        )
    }
}

private static func fetchTokenTransferHistoryFromEthplorer(
    normalizedAddress: String,
    supportedTokensByContract: [String: EthereumSupportedToken],
    supportedTokensBySymbol: [String: EthereumSupportedToken],
    maxResults: Int,
    page: Int = 1,
    pageSize: Int? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
    let safePage = max(1, page)
    let effectivePageSize = max(10, min(pageSize ?? maxResults, 500))
    let requestedLimit = min(max(safePage * effectivePageSize, effectivePageSize), 1000)
    guard let url = ethplorerHistoryURL(
        for: chain,
        normalizedAddress: normalizedAddress,
        requestedLimit: requestedLimit
    ) else {
        return (.init(), .zero)
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode) else {
        return (.init(), .zero)
    }

    if let errorDecoded = try? JSONDecoder().decode(EthplorerErrorResponse.self, from: data),
       let errorMessage = errorDecoded.error?.message,
       !errorMessage.isEmpty {
        throw EthereumWalletEngineError.rpcFailure("Ethplorer: \(errorMessage)")
    }

    let decoded = try JSONDecoder().decode(EthplorerAddressHistoryResponse.self, from: data)
    guard let operations = decoded.operations, !operations.isEmpty else {
        return (.init(), .zero)
    }

    var transfers: [EthereumTokenTransferSnapshot] = []
    transfers.reserveCapacity(operations.count)
    var scannedTransfers = 0
    var decodedSupportedTransfers = 0
    var droppedUnsupportedTransfers = 0
    for (index, op) in operations.enumerated() {
        scannedTransfers += 1
        guard let txHash = op.transactionHash,
              let from = op.from,
              let to = op.to,
              let tokenAddress = op.tokenInfo?.address,
              let valueString = op.value,
              let timestamp = op.timestamp else {
            continue
        }

        let normalizedContract = normalizeAddress(tokenAddress)
        let symbol = op.tokenInfo?.symbol?.uppercased() ?? ""
        guard let supportedToken = supportedTokensByContract[normalizedContract] ?? supportedTokensBySymbol[symbol] else {
            droppedUnsupportedTransfers += 1
            continue
        }

        let normalizedFrom = normalizeAddress(from)
        let normalizedTo = normalizeAddress(to)
        guard normalizedFrom == normalizedAddress || normalizedTo == normalizedAddress else {
            continue
        }

        guard let rawValue = Decimal(string: valueString) else {
            continue
        }
        let amount = rawValue / decimalPowerOfTen(supportedToken.decimals)
        let blockNumber = op.blockNumber ?? 0

        transfers.append(
            EthereumTokenTransferSnapshot(
                contractAddress: supportedToken.contractAddress,
                tokenName: supportedToken.name,
                symbol: supportedToken.symbol,
                decimals: supportedToken.decimals,
                fromAddress: normalizedFrom,
                toAddress: normalizedTo,
                amount: amount,
                transactionHash: txHash,
                blockNumber: blockNumber,
                logIndex: max(0, operations.count - index),
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
        )
        decodedSupportedTransfers += 1
    }

    transfers.sort { lhs, rhs in
        if lhs.blockNumber != rhs.blockNumber {
            return lhs.blockNumber > rhs.blockNumber
        }
        return lhs.logIndex > rhs.logIndex
    }
    let pageSlice = paginateTransferSnapshots(
        transfers,
        page: safePage,
        pageSize: effectivePageSize
    )
    return (
        Array(pageSlice.prefix(effectivePageSize)),
        EthereumTransferDecodingStats(
            scannedTransfers: scannedTransfers,
            decodedSupportedTransfers: decodedSupportedTransfers,
            droppedUnsupportedTransfers: droppedUnsupportedTransfers
        )
    )
}

private static func fetchTokenTransferHistoryFromBlockscout(
    normalizedAddress: String,
    supportedTokensByContract: [String: EthereumSupportedToken],
    supportedTokensBySymbol: [String: EthereumSupportedToken],
    maxResults: Int,
    page: Int = 1,
    pageSize: Int? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
    let safePage = max(1, page)
    let effectivePageSize = max(10, min(pageSize ?? maxResults, 200))
    guard let url = blockscoutTokenTransfersURL(
        for: chain,
        normalizedAddress: normalizedAddress,
        page: safePage,
        pageSize: effectivePageSize
    ) else {
        return (.init(), .zero)
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode) else {
        return (.init(), .zero)
    }

    let decoded = try JSONDecoder().decode(BlockscoutTokenTransfersResponse.self, from: data)
    guard !decoded.items.isEmpty else { return (.init(), .zero) }

    var transfers: [EthereumTokenTransferSnapshot] = []
    transfers.reserveCapacity(decoded.items.count)
    var scannedTransfers = 0
    var decodedSupportedTransfers = 0
    var droppedUnsupportedTransfers = 0
    for (index, item) in decoded.items.enumerated() {
        scannedTransfers += 1
        guard let txHash = item.transaction_hash,
              let from = item.from?.hash,
              let to = item.to?.hash,
              let tokenAddress = item.token?.address,
              let rawValue = item.total?.value,
              let decimalValue = Decimal(string: rawValue) else {
            continue
        }

        let normalizedContract = normalizeAddress(tokenAddress)
        let symbol = item.token?.symbol?.uppercased() ?? ""
        guard let supportedToken = supportedTokensByContract[normalizedContract] ?? supportedTokensBySymbol[symbol] else {
            droppedUnsupportedTransfers += 1
            continue
        }

        let normalizedFrom = normalizeAddress(from)
        let normalizedTo = normalizeAddress(to)
        guard normalizedFrom == normalizedAddress || normalizedTo == normalizedAddress else {
            continue
        }

        let amount = decimalValue / decimalPowerOfTen(supportedToken.decimals)
        let blockNumber = item.block_number ?? 0
        let timestamp = item.timestamp.flatMap { iso8601Formatter.date(from: $0) }
        transfers.append(
            EthereumTokenTransferSnapshot(
                contractAddress: supportedToken.contractAddress,
                tokenName: supportedToken.name,
                symbol: supportedToken.symbol,
                decimals: supportedToken.decimals,
                fromAddress: normalizedFrom,
                toAddress: normalizedTo,
                amount: amount,
                transactionHash: txHash,
                blockNumber: blockNumber,
                logIndex: max(0, decoded.items.count - index),
                timestamp: timestamp
            )
        )
        decodedSupportedTransfers += 1
    }

    transfers.sort { lhs, rhs in
        if lhs.blockNumber != rhs.blockNumber {
            return lhs.blockNumber > rhs.blockNumber
        }
        return lhs.logIndex > rhs.logIndex
    }
    return (
        Array(transfers.prefix(effectivePageSize)),
        EthereumTransferDecodingStats(
            scannedTransfers: scannedTransfers,
            decodedSupportedTransfers: decodedSupportedTransfers,
            droppedUnsupportedTransfers: droppedUnsupportedTransfers
        )
    )
}

private static func fetchTokenTransferHistoryFromHyperliquidExplorerAddressPage(
    normalizedAddress: String,
    chainTokens: [EthereumSupportedToken],
    maxResults: Int,
    page: Int,
    pageSize: Int,
    rpcEndpoint: URL?,
    chain: EVMChainContext
) async throws -> (snapshots: [EthereumTokenTransferSnapshot], stats: EthereumTransferDecodingStats) {
    let resolvedTransactions = try await fetchHyperliquidExplorerResolvedTransactions(
        normalizedAddress: normalizedAddress,
        page: page,
        pageSize: pageSize,
        rpcEndpoint: rpcEndpoint,
        chain: chain
    )
    guard !resolvedTransactions.isEmpty else {
        return ([], .zero)
    }

    let supportedTokensByContract = Dictionary(
        uniqueKeysWithValues: chainTokens.map { (normalizeAddress($0.contractAddress), $0) }
    )
    let transferTopic = "0xddf252ad"
    var scannedTransfers = 0
    var decodedSupportedTransfers = 0
    var droppedUnsupportedTransfers = 0
    var snapshots: [EthereumTokenTransferSnapshot] = []

    for transaction in resolvedTransactions {
        for log in transaction.logs {
            scannedTransfers += 1
            guard let firstTopic = log.topics.first?.lowercased(),
                  firstTopic.hasPrefix(transferTopic),
                  log.topics.count >= 3 else {
                continue
            }

            let contractAddress = normalizeAddress(log.address)
            guard let token = supportedTokensByContract[contractAddress] else {
                droppedUnsupportedTransfers += 1
                continue
            }

            guard let fromAddress = addressFromIndexedTopic(log.topics[1]),
                  let toAddress = addressFromIndexedTopic(log.topics[2]) else {
                continue
            }
            guard fromAddress == normalizedAddress || toAddress == normalizedAddress else {
                continue
            }

            let amountUnits = try decimal(fromHexQuantity: log.data)
            let amount = amountUnits / decimalPowerOfTen(token.decimals)
            let logIndex = log.logIndex.flatMap { Int($0.dropFirst(2), radix: 16) } ?? 0
            snapshots.append(
                EthereumTokenTransferSnapshot(
                    contractAddress: token.contractAddress,
                    tokenName: token.name,
                    symbol: token.symbol,
                    decimals: token.decimals,
                    fromAddress: fromAddress,
                    toAddress: toAddress,
                    amount: amount,
                    transactionHash: transaction.transactionHash,
                    blockNumber: transaction.blockNumber,
                    logIndex: logIndex,
                    timestamp: transaction.timestamp
                )
            )
            decodedSupportedTransfers += 1
        }
    }

    snapshots.sort { lhs, rhs in
        if lhs.blockNumber != rhs.blockNumber {
            return lhs.blockNumber > rhs.blockNumber
        }
        return lhs.logIndex > rhs.logIndex
    }

    return (
        Array(snapshots.prefix(maxResults)),
        EthereumTransferDecodingStats(
            scannedTransfers: scannedTransfers,
            decodedSupportedTransfers: decodedSupportedTransfers,
            droppedUnsupportedTransfers: droppedUnsupportedTransfers
        )
    )
}

private static func fetchNativeTransferHistoryPageFromHyperliquidExplorerAddressPage(
    normalizedAddress: String,
    page: Int,
    pageSize: Int,
    chain: EVMChainContext
) async throws -> [EthereumNativeTransferSnapshot] {
    let resolvedTransactions = try await fetchHyperliquidExplorerResolvedTransactions(
        normalizedAddress: normalizedAddress,
        page: page,
        pageSize: pageSize,
        rpcEndpoint: nil,
        chain: chain
    )

    return resolvedTransactions.compactMap { transaction in
        guard transaction.fromAddress == normalizedAddress || transaction.toAddress == normalizedAddress else {
            return nil
        }
        return EthereumNativeTransferSnapshot(
            fromAddress: transaction.fromAddress,
            toAddress: transaction.toAddress,
            amount: transaction.value / decimalPowerOfTen(18),
            transactionHash: transaction.transactionHash,
            blockNumber: transaction.blockNumber,
            timestamp: transaction.timestamp
        )
    }
}

private static func fetchHyperliquidExplorerResolvedTransactions(
    normalizedAddress: String,
    page: Int,
    pageSize: Int,
    rpcEndpoint: URL?,
    chain: EVMChainContext
) async throws -> [HyperliquidExplorerResolvedTransaction] {
    guard page == 1 else { return [] }
    let transactionHashes = try await fetchHyperliquidExplorerTransactionHashes(
        for: normalizedAddress,
        maxResults: max(1, min(pageSize, 25))
    )
    guard !transactionHashes.isEmpty else { return [] }

    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    var transactionsByHash: [String: (payload: EthereumTransactionByHashPayload, receipt: EthereumTransactionReceiptWithLogsPayload)] = [:]
    try await withThrowingTaskGroup(of: (String, EthereumTransactionByHashPayload, EthereumTransactionReceiptWithLogsPayload)?.self) { group in
        for transactionHash in transactionHashes {
            group.addTask {
                do {
                    let payload: EthereumTransactionByHashPayload = try await performRPCDecoded(
                        method: "eth_getTransactionByHash",
                        params: [transactionHash],
                        rpcEndpoint: resolvedRPCEndpoint,
                        requestID: 71
                    )
                    let receipt: EthereumTransactionReceiptWithLogsPayload = try await performRPCDecoded(
                        method: "eth_getTransactionReceipt",
                        params: [transactionHash],
                        rpcEndpoint: resolvedRPCEndpoint,
                        requestID: 72
                    )
                    guard receipt.status != "0x0",
                          let blockNumberHex = payload.blockNumber ?? receipt.blockNumber,
                          !blockNumberHex.isEmpty else {
                        return nil
                    }
                    return (transactionHash, payload, receipt)
                } catch {
                    return nil
                }
            }
        }

        for try await item in group {
            guard let item else { continue }
            transactionsByHash[item.0] = (item.1, item.2)
        }
    }

    let blockHexes = Set(transactionsByHash.values.compactMap { $0.payload.blockNumber ?? $0.receipt.blockNumber })
    var timestampsByBlockHex: [String: Date] = [:]
    try await withThrowingTaskGroup(of: (String, Date?).self) { group in
        for blockHex in blockHexes {
            group.addTask {
                do {
                    let block: EthereumBlockPayload = try await performRPCDecoded(
                        method: "eth_getBlockByNumber",
                        params: EthereumBlockByNumberParameters(
                            blockNumber: blockHex,
                            includeTransactions: false
                        ),
                        rpcEndpoint: resolvedRPCEndpoint,
                        requestID: 73
                    )
                    let timestampValue = Int(block.timestamp.dropFirst(2), radix: 16).map(TimeInterval.init)
                    return (blockHex, timestampValue.map { Date(timeIntervalSince1970: $0) })
                } catch {
                    return (blockHex, nil)
                }
            }
        }

        for try await (blockHex, timestamp) in group {
            if let timestamp {
                timestampsByBlockHex[blockHex] = timestamp
            }
        }
    }

    return transactionHashes.compactMap { transactionHash in
        guard let resolved = transactionsByHash[transactionHash] else { return nil }
        let blockNumberHex = resolved.payload.blockNumber ?? resolved.receipt.blockNumber ?? ""
        guard let blockNumber = Int(blockNumberHex.dropFirst(2), radix: 16),
              let value = try? decimal(fromHexQuantity: resolved.payload.value) else {
            return nil
        }
        return HyperliquidExplorerResolvedTransaction(
            transactionHash: transactionHash,
            blockNumber: blockNumber,
            fromAddress: normalizeAddress(resolved.payload.from),
            toAddress: normalizeAddress(resolved.payload.to ?? ""),
            value: value,
            timestamp: timestampsByBlockHex[blockNumberHex],
            logs: resolved.receipt.logs
        )
    }
}

private static func fetchHyperliquidExplorerTransactionHashes(
    for normalizedAddress: String,
    maxResults: Int
) async throws -> [String] {
    guard let url = ChainBackendRegistry.EVMExplorerRegistry.addressExplorerURL(
        for: ChainBackendRegistry.hyperliquidChainName,
        normalizedAddress: normalizedAddress
    ) else {
        return []
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        forHTTPHeaderField: "User-Agent"
    )
    request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode),
          let html = String(data: data, encoding: .utf8) else {
        return []
    }

    let pattern = #"/tx/(0x[0-9a-fA-F]{64})"#
    let regex = try NSRegularExpression(pattern: pattern)
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    let matches = regex.matches(in: html, range: nsRange)

    var hashes: [String] = []
    var seen: Set<String> = []
    for match in matches {
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            continue
        }
        let hash = String(html[range]).lowercased()
        guard !seen.contains(hash) else { continue }
        seen.insert(hash)
        hashes.append(hash)
        if hashes.count >= maxResults {
            break
        }
    }
    return hashes
}

private static func addressFromIndexedTopic(_ topic: String) -> String? {
    let normalized = topic.lowercased()
    guard normalized.hasPrefix("0x"), normalized.count >= 42 else { return nil }
    let startIndex = normalized.index(normalized.endIndex, offsetBy: -40)
    return normalizeAddress("0x" + String(normalized[startIndex...]))
}

private static func paginateTransferSnapshots(
    _ snapshots: [EthereumTokenTransferSnapshot],
    page: Int,
    pageSize: Int
) -> [EthereumTokenTransferSnapshot] {
    let safePage = max(1, page)
    let safePageSize = max(1, pageSize)
    let startIndex = (safePage - 1) * safePageSize
    guard startIndex < snapshots.count else { return [] }
    let endIndex = min(startIndex + safePageSize, snapshots.count)
    return Array(snapshots[startIndex ..< endIndex])
}

#if DEBUG
static func paginateTransferSnapshotsForTesting(
    _ snapshots: [EthereumTokenTransferSnapshot],
    page: Int,
    pageSize: Int
) -> [EthereumTokenTransferSnapshot] {
    paginateTransferSnapshots(snapshots, page: page, pageSize: pageSize)
}
#endif

}
