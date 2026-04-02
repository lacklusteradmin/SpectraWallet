import Foundation
import BigInt
import WalletCore


extension EthereumWalletEngine {
static func supportedTokens(for chain: EVMChainContext) -> [EthereumSupportedToken] {
    guard let trackingChain = chain.tokenTrackingChain else { return [] }
    return ChainTokenRegistryEntry.builtIn
        .filter { $0.chain == trackingChain }
        .map { entry in
            EthereumSupportedToken(
                name: entry.name,
                symbol: entry.symbol,
                contractAddress: entry.contractAddress,
                decimals: entry.decimals,
                marketDataID: entry.marketDataID,
                coinGeckoID: entry.coinGeckoID
            )
        }
}

static func resolvedRPCEndpoints(preferred: URL?, chain: EVMChainContext) -> [URL] {
    if let preferred {
        return [preferred]
    }
    let orderedEndpointStrings = ChainEndpointReliability.orderedEndpoints(
        namespace: "evm.\(chain.displayName.lowercased().replacingOccurrences(of: " ", with: "-")).rpc",
        candidates: chain.defaultRPCEndpoints
    )
    var endpoints: [URL] = []
    for endpointString in orderedEndpointStrings {
        guard let endpointURL = URL(string: endpointString) else { continue }
        if !endpoints.contains(endpointURL) {
            endpoints.append(endpointURL)
        }
    }
    return endpoints
}

static func resolvedRPCEndpoints(fallbackFrom rpcEndpoint: URL, chain: EVMChainContext) -> [URL] {
    let defaultEndpoints = resolvedRPCEndpoints(preferred: nil, chain: chain)
    guard defaultEndpoints.contains(rpcEndpoint) else {
        return [rpcEndpoint]
    }
    return [rpcEndpoint] + defaultEndpoints.filter { $0 != rpcEndpoint }
}

static func inferredChainContext(for rpcEndpoint: URL) -> EVMChainContext {
    let allContexts: [EVMChainContext] = [.ethereum, .ethereumSepolia, .ethereumHoodi, .arbitrum, .optimism, .bnb, .avalanche, .hyperliquid]
    for context in allContexts {
        let defaults = resolvedRPCEndpoints(preferred: nil, chain: context)
        if defaults.contains(rpcEndpoint) {
            return context
        }
    }
    return .ethereum
}

static func normalizeAddress(_ address: String) -> String {
    address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

static func isValidAddress(_ address: String) -> Bool {
    let normalizedAddress = normalizeAddress(address)
    guard normalizedAddress.count == 42, normalizedAddress.hasPrefix("0x") else {
        return false
    }

    let hexBody = normalizedAddress.dropFirst(2)
    return hexBody.allSatisfy(\.isHexDigit)
}

static func validateAddress(_ address: String) throws -> String {
    let normalizedAddress = normalizeAddress(address)
    guard isValidAddress(normalizedAddress) else {
        throw EthereumWalletEngineError.invalidAddress
    }
    return normalizedAddress
}

static func receiveAddress(for address: String) throws -> String {
    try validateAddress(address)
}

static func resolveENSAddress(_ name: String, chain: EVMChainContext = .ethereum) async throws -> String? {
    guard chain == .ethereum else { return nil }
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalizedName.hasSuffix(".eth"),
          !normalizedName.isEmpty,
          !normalizedName.contains(" ") else {
        return nil
    }
    guard let encodedName = normalizedName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let endpoint = URL(string: "https://api.ensideas.com/ens/resolve/\(encodedName)") else {
        throw EthereumWalletEngineError.invalidResponse
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 12
    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode) else {
        throw EthereumWalletEngineError.rpcFailure("Unable to resolve ENS name right now.")
    }

    let payload = try JSONDecoder().decode(ENSIdeasResolveResponse.self, from: data)
    guard let address = payload.address, isValidAddress(address) else {
        return nil
    }
    return try validateAddress(address)
}

static func fetchCode(
    at address: String,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> String {
    let normalizedAddress = try validateAddress(address)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    return try await performRPC(
        method: "eth_getCode",
        params: [normalizedAddress, "latest"],
        rpcEndpoint: resolvedRPCEndpoint,
        requestID: 35
    )
}

static func hasContractCode(_ code: String) -> Bool {
    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized != "0x" && normalized != "0x0"
}

static func derivedAddress(
    for seedPhrase: String,
    account: UInt32 = 0,
    chain: EVMChainContext = .ethereum,
    derivationPath: String? = nil
) throws -> String {
    let normalizedSeedPhrase = BitcoinWalletEngine.normalizedMnemonicPhrase(from: seedPhrase)
    let wordCount = BitcoinWalletEngine.normalizedMnemonicWords(from: normalizedSeedPhrase).count
    guard wordCount > 0,
          BitcoinWalletEngine.validateMnemonic(normalizedSeedPhrase, expectedWordCount: wordCount) == nil else {
        throw EthereumWalletEngineError.invalidSeedPhrase
    }

    return try walletCoreDerivedAddress(
        seedPhrase: normalizedSeedPhrase,
        account: account,
        chain: chain,
        derivationPath: derivationPath
    )
}

static func derivedAddress(
    forPrivateKey privateKeyHex: String,
    chain: EVMChainContext = .ethereum
) throws -> String {
    let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .ethereum)
    return normalizeAddress(material.address)
}

static func fetchAccountSnapshot(
    for address: String,
    rpcEndpoint: URL? = nil,
    chainID: Int = 1,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumAccountSnapshot {
    let normalizedAddress = try validateAddress(address)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!

    async let balanceHex = performRPC(
        method: "eth_getBalance",
        params: [normalizedAddress, "latest"],
        rpcEndpoint: resolvedRPCEndpoint,
        requestID: 1
    )
    async let blockHex = performRPC(
        method: "eth_blockNumber",
        params: [String](),
        rpcEndpoint: resolvedRPCEndpoint,
        requestID: 2
    )

    let nativeBalanceWei = try decimal(fromHexQuantity: try await balanceHex)
    let blockNumberHex = try await blockHex
    let blockNumber = Int(blockNumberHex.dropFirst(2), radix: 16)

    return EthereumAccountSnapshot(
        address: normalizedAddress,
        chainID: chainID,
        nativeBalanceWei: nativeBalanceWei,
        blockNumber: blockNumber
    )
}

static func nativeBalanceETH(from snapshot: EthereumAccountSnapshot) -> Double {
    let divisor = Decimal(string: "1000000000000000000") ?? 1
    let ethBalance = snapshot.nativeBalanceWei / divisor
    return NSDecimalNumber(decimal: ethBalance).doubleValue
}

static func plannedAccountSnapshot(
    for address: String,
    rpcEndpoint: URL?,
    chainID: Int = 1,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumAccountSnapshot {
    guard let rpcEndpoint else {
        throw EthereumWalletEngineError.missingRPCEndpoint
    }

    return try await fetchAccountSnapshot(
        for: address,
        rpcEndpoint: rpcEndpoint,
        chainID: chainID,
        chain: chain
    )
}

static func plannedTokenBalances(
    for address: String,
    tokenContracts: [String],
    rpcEndpoint: URL?,
    chain: EVMChainContext = .ethereum
) async throws -> [EthereumTokenBalanceSnapshot] {
    let chainTokens = supportedTokens(for: chain)
    let requestedContracts = Set(tokenContracts.map(normalizeAddress))
    let matchingTokens = chainTokens.filter { requestedContracts.contains($0.contractAddress) }
    guard !matchingTokens.isEmpty else { return [] }

    return try await fetchTokenBalances(
        for: address,
        tokens: matchingTokens,
        rpcEndpoint: rpcEndpoint,
        chain: chain
    )
}

static func fetchSupportedTokenBalances(
    for address: String,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> [EthereumTokenBalanceSnapshot] {
    try await fetchTokenBalances(
        for: address,
        tokens: supportedTokens(for: chain),
        rpcEndpoint: rpcEndpoint,
        chain: chain
    )
}

static func fetchTokenBalances(
    for address: String,
    trackedTokens: [EthereumSupportedToken],
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> [EthereumTokenBalanceSnapshot] {
    guard !trackedTokens.isEmpty else { return [] }
    return try await fetchTokenBalances(
        for: address,
        tokens: trackedTokens,
        rpcEndpoint: rpcEndpoint,
        chain: chain
    )
}

private static func fetchTokenBalances(
    for address: String,
    tokens: [EthereumSupportedToken],
    rpcEndpoint: URL?,
    chain: EVMChainContext = .ethereum
) async throws -> [EthereumTokenBalanceSnapshot] {
    let normalizedAddress = try validateAddress(address)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!

    var balances: [EthereumTokenBalanceSnapshot] = []
    for (index, token) in tokens.enumerated() {
        let balanceHex = try await performRPC(
            method: "eth_call",
            params: EthereumCallParameters(
                call: EthereumCallRequest(
                    to: token.contractAddress,
                    data: balanceOfCallData(for: normalizedAddress)
                ),
                blockTag: "latest"
            ),
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 100 + index
        )
        let rawBalance = try decimal(fromHexQuantity: balanceHex)
        let normalizedBalance = rawBalance / decimalPowerOfTen(token.decimals)
        balances.append(
            EthereumTokenBalanceSnapshot(
                contractAddress: token.contractAddress,
                symbol: token.symbol,
                balance: normalizedBalance,
                decimals: token.decimals
            )
        )
    }

    return balances
}

}
