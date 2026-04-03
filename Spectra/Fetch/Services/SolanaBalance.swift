import Foundation
import SolanaSwift

enum SolanaBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Solana")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Solana")
        case .httpError(let statusCode):
            let format = NSLocalizedString("The Solana provider returned HTTP %d.", comment: "")
            return String(format: format, locale: .current, statusCode)
        }
    }
}

struct SolanaHistorySnapshot: Equatable {
    let transactionHash: String
    let assetName: String
    let symbol: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct SolanaHistoryDiagnostics: Equatable {
    let address: String
    let rpcCount: Int
    let sourceUsed: String
    let error: String?
}

struct SolanaSPLTokenBalanceSnapshot: Equatable {
    let mintAddress: String
    let sourceTokenAccountAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}

struct SolanaPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [SolanaSPLTokenBalanceSnapshot]
}

enum SolanaBalanceService {
    private static let legacyTokenProgramID = TokenProgram.id.base58EncodedString
    // Canonical Token-2022 program id on Solana mainnet.
    private static let token2022ProgramID = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    static func endpointCatalog() -> [String] {
        SolanaProvider.balanceEndpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        SolanaProvider.diagnosticsChecks()
    }

    private static func rpcClient(baseURL: String) -> SolanaAPIClient {
        SolanaProvider.rpcClient(baseURL: baseURL)
    }

    private static func withRPCClient<T>(_ operation: (SolanaAPIClient) async throws -> T) async throws -> T {
        var lastError: Error?
        for baseURL in SolanaProvider.balanceRPCBaseURLs {
            do {
                return try await operation(rpcClient(baseURL: baseURL))
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SolanaBalanceServiceError.invalidResponse
    }

    struct KnownTokenMetadata {
        let symbol: String
        let name: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }

    static let usdtMintAddress = PublicKey.usdtMint.base58EncodedString
    static let usdcMintAddress = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    static let pyusdMintAddress = "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"
    static let usdgMintAddress = "2u1tszSeqZ3qBWF3uNGPFc8TzMk2tdiwknnRMWGWjGWH"
    static let usd1MintAddress = "USD1ttGY1N17NEEHLmELoaybftRBUSErhqYiQzvEmuB"
    static let linkMintAddress = "LinkhB3afbBKb2EQQu7s7umdZceV3wcvAUJhQAfQ23L"
    static let wlfiMintAddress = "WLFinEv6ypjkczcS83FZqFpgFZYwQXutRbxGe7oC16g"
    static let jupMintAddress = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
    static let bonkMintAddress = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"

    static let knownTokenMetadataByMint: [String: KnownTokenMetadata] = [
        PublicKey.usdtMint.base58EncodedString: KnownTokenMetadata(
            symbol: "USDT",
            name: "Tether USD",
            decimals: 6,
            marketDataID: "825",
            coinGeckoID: "tether"
        ),
        usdcMintAddress: KnownTokenMetadata(
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            marketDataID: "3408",
            coinGeckoID: "usd-coin"
        ),
        pyusdMintAddress: KnownTokenMetadata(
            symbol: "PYUSD",
            name: "PayPal USD",
            decimals: 6,
            marketDataID: "27772",
            coinGeckoID: "paypal-usd"
        ),
        usdgMintAddress: KnownTokenMetadata(
            symbol: "USDG",
            name: "Global Dollar",
            decimals: 6,
            marketDataID: "0",
            coinGeckoID: "global-dollar"
        ),
        usd1MintAddress: KnownTokenMetadata(
            symbol: "USD1",
            name: "USD1",
            decimals: 6,
            marketDataID: "0",
            coinGeckoID: ""
        ),
        linkMintAddress: KnownTokenMetadata(
            symbol: "LINK",
            name: "Chainlink",
            decimals: 8,
            marketDataID: "1975",
            coinGeckoID: "chainlink"
        ),
        wlfiMintAddress: KnownTokenMetadata(
            symbol: "WLFI",
            name: "World Liberty Financial",
            decimals: 6,
            marketDataID: "0",
            coinGeckoID: ""
        ),
        jupMintAddress: KnownTokenMetadata(
            symbol: "JUP",
            name: "Jupiter",
            decimals: 6,
            marketDataID: "29210",
            coinGeckoID: "jupiter-exchange-solana"
        ),
        bonkMintAddress: KnownTokenMetadata(
            symbol: "BONK",
            name: "Bonk",
            decimals: 5,
            marketDataID: "23095",
            coinGeckoID: "bonk"
        )
    ]

    static func mintAddress(for symbol: String) -> String? {
        switch symbol.uppercased() {
        case "USDT":
            return usdtMintAddress
        case "USDC":
            return usdcMintAddress
        case "PYUSD":
            return pyusdMintAddress
        case "USDG":
            return usdgMintAddress
        case "USD1":
            return usd1MintAddress
        case "LINK":
            return linkMintAddress
        case "WLFI":
            return wlfiMintAddress
        case "JUP":
            return jupMintAddress
        case "BONK":
            return bonkMintAddress
        default:
            return nil
        }
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidSolanaAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            throw SolanaBalanceServiceError.invalidAddress
        }
        let lamports = try await withRPCClient { client in
            try await client.getBalance(account: normalized, commitment: "confirmed")
        }
        return Double(lamports) / 1_000_000_000.0
    }

    static func fetchPortfolio(for address: String) async throws -> SolanaPortfolioSnapshot {
        try await fetchPortfolio(for: address, trackedTokenMetadataByMint: knownTokenMetadataByMint)
    }

    static func fetchPortfolio(
        for address: String,
        trackedTokenMetadataByMint: [String: KnownTokenMetadata]
    ) async throws -> SolanaPortfolioSnapshot {
        var nativeBalance: Double?
        var tokenBalances: [SolanaSPLTokenBalanceSnapshot]?
        var nativeError: Error?
        var tokenError: Error?

        do {
            nativeBalance = try await fetchBalance(for: address)
        } catch {
            nativeError = error
        }

        do {
            tokenBalances = try await fetchSPLTokenBalances(
                for: address,
                trackedTokenMetadataByMint: trackedTokenMetadataByMint
            )
        } catch {
            tokenError = error
        }

        if let nativeBalance, let tokenBalances {
            return SolanaPortfolioSnapshot(nativeBalance: nativeBalance, tokenBalances: tokenBalances)
        }
        if let nativeBalance {
            // Token account queries are less reliable on some public RPCs; keep native balance visible.
            return SolanaPortfolioSnapshot(nativeBalance: nativeBalance, tokenBalances: [])
        }
        if let tokenBalances {
            // Keep token balances visible even if SOL native balance fetch fails.
            return SolanaPortfolioSnapshot(nativeBalance: 0, tokenBalances: tokenBalances)
        }

        throw tokenError as? SolanaBalanceServiceError ?? nativeError ?? SolanaBalanceServiceError.invalidResponse
    }

    static func fetchSPLTokenBalances(for address: String) async throws -> [SolanaSPLTokenBalanceSnapshot] {
        try await fetchSPLTokenBalances(for: address, trackedTokenMetadataByMint: knownTokenMetadataByMint)
    }

    static func fetchSPLTokenBalances(
        for address: String,
        trackedTokenMetadataByMint: [String: KnownTokenMetadata]
    ) async throws -> [SolanaSPLTokenBalanceSnapshot] {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            throw SolanaBalanceServiceError.invalidAddress
        }

        // Prefer parsed-RPC first: it is more deterministic across public providers
        // for SPL balances than typed/base64 decode paths.
        if let parsedFirst = try? await fetchSPLTokenBalancesViaParsedRPC(
            for: normalized,
            trackedTokenMetadataByMint: trackedTokenMetadataByMint
        ), !parsedFirst.isEmpty {
            return parsedFirst.sorted { lhs, rhs in
                if lhs.balance != rhs.balance {
                    return lhs.balance > rhs.balance
                }
                return lhs.symbol < rhs.symbol
            }
        }

        let tokenAccounts = try await fetchOwnedTokenAccounts(for: normalized)

        guard !tokenAccounts.isEmpty else {
            return []
        }

        var rawByMint: [String: UInt64] = [:]
        var sourceTokenAccountByMint: [String: String] = [:]
        for account in tokenAccounts {
            let mint = account.account.data.mint.base58EncodedString
            rawByMint[mint, default: 0] += account.account.data.lamports
            let candidate = account.pubkey
            if sourceTokenAccountByMint[mint] == nil {
                sourceTokenAccountByMint[mint] = candidate
            }
        }

        let mintAddresses = Array(rawByMint.keys)
        let trackedMintAddresses = mintAddresses.filter { trackedTokenMetadataByMint[$0] != nil }
        guard !trackedMintAddresses.isEmpty else {
            return []
        }
        let mintData = try await withRPCClient { client in
            try await client.getMultipleMintDatas(
                mintAddresses: trackedMintAddresses,
                commitment: "confirmed",
                mintType: TokenMintState.self
            )
        }

        let snapshots: [SolanaSPLTokenBalanceSnapshot] = trackedMintAddresses.compactMap { mint in
            guard let rawAmount = rawByMint[mint], rawAmount > 0 else {
                return nil
            }
            let fallbackMetadata = KnownTokenMetadata(
                symbol: String(mint.prefix(4)).uppercased(),
                name: "SPL Token",
                decimals: 0,
                marketDataID: "0",
                coinGeckoID: ""
            )
            let metadata = trackedTokenMetadataByMint[mint] ?? fallbackMetadata

            let decimals = Int(mintData[mint]?.decimals ?? UInt8(metadata.decimals))
            let divisor = pow(10.0, Double(decimals))
            guard divisor > 0 else { return nil }
            let balance = Double(rawAmount) / divisor
            guard balance > 0 else { return nil }
            guard let sourceTokenAccountAddress = sourceTokenAccountByMint[mint], !sourceTokenAccountAddress.isEmpty else {
                return nil
            }

            return SolanaSPLTokenBalanceSnapshot(
                mintAddress: mint,
                sourceTokenAccountAddress: sourceTokenAccountAddress,
                symbol: metadata.symbol,
                name: metadata.name,
                tokenStandard: "SPL",
                decimals: decimals,
                balance: balance,
                marketDataID: metadata.marketDataID,
                coinGeckoID: metadata.coinGeckoID
            )
        }

        return snapshots.sorted { lhs, rhs in
            if lhs.balance != rhs.balance {
                return lhs.balance > rhs.balance
            }
            return lhs.symbol < rhs.symbol
        }
    }

    static func resolveOwnedTokenAccount(for ownerAddress: String, mintAddress: String) async throws -> String? {
        let normalizedOwner = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMint = mintAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalizedOwner),
              AddressValidation.isValidSolanaAddress(normalizedMint) else {
            throw SolanaBalanceServiceError.invalidAddress
        }

        do {
            let accounts = try await withRPCClient { client in
                try await client.getTokenAccountsByOwner(
                    pubkey: normalizedOwner,
                    params: OwnerInfoParams(mint: normalizedMint, programId: legacyTokenProgramID),
                    configs: RequestConfiguration(commitment: "confirmed", encoding: "base64")
                )
            }
            if !accounts.isEmpty {
                let sorted = accounts.sorted { lhs, rhs in
                    lhs.account.data.lamports > rhs.account.data.lamports
                }
                return sorted.first?.pubkey
            }

            let token2022Accounts = try await withRPCClient { client in
                try await client.getTokenAccountsByOwner(
                    pubkey: normalizedOwner,
                    params: OwnerInfoParams(mint: normalizedMint, programId: token2022ProgramID),
                    configs: RequestConfiguration(commitment: "confirmed", encoding: "base64")
                )
            }
            guard !token2022Accounts.isEmpty else { return nil }
            let sorted = token2022Accounts.sorted { lhs, rhs in
                lhs.account.data.lamports > rhs.account.data.lamports
            }
            return sorted.first?.pubkey
        } catch {
            // Some RPC nodes intermittently fail mint-scoped token-account queries.
            // Fall back to owner-wide SPL balance scan and pick the matching mint.
            do {
                let tokenBalances = try await fetchSPLTokenBalances(
                    for: normalizedOwner,
                    trackedTokenMetadataByMint: [normalizedMint: KnownTokenMetadata(
                        symbol: String(normalizedMint.prefix(4)).uppercased(),
                        name: "SPL Token",
                        decimals: 0,
                        marketDataID: "0",
                        coinGeckoID: ""
                    )]
                )
                return tokenBalances.first(where: { $0.mintAddress.caseInsensitiveCompare(normalizedMint) == .orderedSame })?.sourceTokenAccountAddress
            } catch {
                return nil
            }
        }
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 40) async -> (snapshots: [SolanaHistorySnapshot], diagnostics: SolanaHistoryDiagnostics) {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidAddress(normalized) else {
            return (
                [],
                SolanaHistoryDiagnostics(
                    address: normalized,
                    rpcCount: 0,
                    sourceUsed: "none",
                    error: SolanaBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        do {
            let ownedTokenAccounts = try await withRPCClient { client in
                let legacyAccounts = try await client.getTokenAccountsByOwner(
                    pubkey: normalized,
                    params: OwnerInfoParams(mint: nil, programId: legacyTokenProgramID),
                    configs: RequestConfiguration(commitment: "confirmed", encoding: "base64")
                )
                let token2022Accounts = try await client.getTokenAccountsByOwner(
                    pubkey: normalized,
                    params: OwnerInfoParams(mint: nil, programId: token2022ProgramID),
                    configs: RequestConfiguration(commitment: "confirmed", encoding: "base64")
                )
                return legacyAccounts + token2022Accounts
            }
            let ownedTokenMintByAccountAddress = Dictionary(
                uniqueKeysWithValues: ownedTokenAccounts.map {
                    ($0.pubkey.lowercased(), $0.account.data.mint.base58EncodedString)
                }
            )

            let signatures = try await withRPCClient { client in
                try await client.getSignaturesForAddress(
                    address: normalized,
                    configs: RequestConfiguration(limit: max(1, min(limit, 100)))
                )
            }

            if signatures.isEmpty {
                return (
                    [],
                    SolanaHistoryDiagnostics(address: normalized, rpcCount: 0, sourceUsed: "solana-rpc", error: nil)
                )
            }

            let snapshots = await withTaskGroup(of: SolanaHistorySnapshot?.self, returning: [SolanaHistorySnapshot].self) { group in
                for item in signatures {
                    group.addTask {
                        await buildHistorySnapshot(
                            address: normalized,
                            signature: item,
                            ownedTokenMintByAccountAddress: ownedTokenMintByAccountAddress
                        )
                    }
                }

                var collected: [SolanaHistorySnapshot] = []
                for await snapshot in group {
                    if let snapshot {
                        collected.append(snapshot)
                    }
                }
                return collected.sorted { $0.createdAt > $1.createdAt }
            }

            return (
                snapshots,
                SolanaHistoryDiagnostics(address: normalized, rpcCount: snapshots.count, sourceUsed: "solana-rpc", error: nil)
            )
        } catch {
            return (
                [],
                SolanaHistoryDiagnostics(address: normalized, rpcCount: 0, sourceUsed: "none", error: error.localizedDescription)
            )
        }
    }

    private static func buildHistorySnapshot(
        address: String,
        signature: SignatureInfo,
        ownedTokenMintByAccountAddress: [String: String]
    ) async -> SolanaHistorySnapshot? {
        guard !signature.signature.isEmpty else { return nil }

        do {
            let transaction = try await withRPCClient { client in
                try await client.getTransaction(
                    signature: signature.signature,
                    commitment: "confirmed"
                )
            }
            guard let transaction else { return nil }

            let accountKeys = transaction.transaction.message.accountKeys.map(\.publicKey.base58EncodedString)
            guard let accountIndex = accountKeys.firstIndex(where: { $0.caseInsensitiveCompare(address) == .orderedSame }) else {
                return nil
            }

            let preBalances = transaction.meta?.preBalances ?? []
            let postBalances = transaction.meta?.postBalances ?? []
            guard preBalances.indices.contains(accountIndex), postBalances.indices.contains(accountIndex) else {
                return nil
            }

            let preLamports = Int64(preBalances[accountIndex])
            let postLamports = Int64(postBalances[accountIndex])
            let deltaLamports = postLamports - preLamports
            if deltaLamports != 0 {
                let amountSOL = abs(Double(deltaLamports)) / 1_000_000_000.0
                let kind: TransactionKind = deltaLamports < 0 ? .send : .receive
                let status: TransactionStatus = signature.err == nil ? .confirmed : .failed
                let createdAt = Date(timeIntervalSince1970: TimeInterval(transaction.blockTime ?? signature.blockTime ?? 0))
                let counterparty = firstCounterparty(from: accountKeys, excluding: address)

                return SolanaHistorySnapshot(
                    transactionHash: signature.signature,
                    assetName: "Solana",
                    symbol: "SOL",
                    kind: kind,
                    amount: amountSOL,
                    counterpartyAddress: counterparty,
                    createdAt: createdAt,
                    status: status
                )
            }

            let tokenDelta = computeTokenDelta(
                transaction: transaction,
                accountKeys: accountKeys,
                ownedTokenMintByAccountAddress: ownedTokenMintByAccountAddress
            )
            guard let tokenDelta else { return nil }

            let amount = abs(tokenDelta.deltaAmount)
            guard amount > 0 else { return nil }
            let kind: TransactionKind = tokenDelta.deltaAmount < 0 ? .send : .receive
            let status: TransactionStatus = signature.err == nil ? .confirmed : .failed
            let createdAt = Date(timeIntervalSince1970: TimeInterval(transaction.blockTime ?? signature.blockTime ?? 0))
            let counterparty = firstCounterparty(from: accountKeys, excluding: address)

            return SolanaHistorySnapshot(
                transactionHash: signature.signature,
                assetName: tokenDelta.metadata.name,
                symbol: tokenDelta.metadata.symbol,
                kind: kind,
                amount: amount,
                counterpartyAddress: counterparty,
                createdAt: createdAt,
                status: status
            )
        } catch {
            return nil
        }
    }

    private struct TokenHistoryDelta {
        let metadata: KnownTokenMetadata
        let deltaAmount: Double
    }

    private static func computeTokenDelta(
        transaction: TransactionInfo,
        accountKeys: [String],
        ownedTokenMintByAccountAddress: [String: String]
    ) -> TokenHistoryDelta? {
        let preTokenBalances = transaction.meta?.preTokenBalances ?? []
        let postTokenBalances = transaction.meta?.postTokenBalances ?? []

        var preByIndex: [UInt64: TokenBalance] = [:]
        var postByIndex: [UInt64: TokenBalance] = [:]
        for item in preTokenBalances {
            preByIndex[item.accountIndex] = item
        }
        for item in postTokenBalances {
            postByIndex[item.accountIndex] = item
        }

        let indices = Set(preByIndex.keys).union(postByIndex.keys)
        var best: TokenHistoryDelta?

        for index in indices {
            guard let intIndex = Int(exactly: index),
                  accountKeys.indices.contains(intIndex) else { continue }
            let tokenAccountAddress = accountKeys[intIndex].lowercased()
            guard let ownedMint = ownedTokenMintByAccountAddress[tokenAccountAddress],
                  let metadata = knownTokenMetadataByMint[ownedMint] else { continue }

            let preAmountRaw = preByIndex[index]?.uiTokenAmount.amount ?? "0"
            let postAmountRaw = postByIndex[index]?.uiTokenAmount.amount ?? "0"
            guard let preRaw = Decimal(string: preAmountRaw),
                  let postRaw = Decimal(string: postAmountRaw) else { continue }

            let deltaRaw = postRaw - preRaw
            if deltaRaw == .zero { continue }

            let divisor = pow(10.0, Double(metadata.decimals))
            guard divisor > 0 else { continue }

            let rawNS = NSDecimalNumber(decimal: deltaRaw)
            let deltaAmount = rawNS.doubleValue / divisor
            if deltaAmount == 0 { continue }

            let candidate = TokenHistoryDelta(metadata: metadata, deltaAmount: deltaAmount)
            if let current = best {
                if abs(candidate.deltaAmount) > abs(current.deltaAmount) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    private static func firstCounterparty(from accountKeys: [String], excluding address: String) -> String {
        accountKeys.first(where: { $0.caseInsensitiveCompare(address) != .orderedSame }) ?? address
    }

    private static func fetchOwnedTokenAccounts(for ownerAddress: String) async throws -> [TokenAccount<TokenAccountState>] {
        try await withRPCClient { client in
            let legacyAccounts = try await client.getTokenAccountsByOwner(
                pubkey: ownerAddress,
                params: OwnerInfoParams(mint: nil, programId: legacyTokenProgramID),
                configs: RequestConfiguration(commitment: "confirmed", encoding: "base64")
            )
            let token2022Accounts = try await client.getTokenAccountsByOwner(
                pubkey: ownerAddress,
                params: OwnerInfoParams(mint: nil, programId: token2022ProgramID),
                configs: RequestConfiguration(commitment: "confirmed", encoding: "base64")
            )
            return legacyAccounts + token2022Accounts
        }
    }

    private static func fetchSPLTokenBalancesViaParsedRPC(
        for ownerAddress: String,
        trackedTokenMetadataByMint: [String: KnownTokenMetadata]
    ) async throws -> [SolanaSPLTokenBalanceSnapshot] {
        let programs = [legacyTokenProgramID, token2022ProgramID]
        var lastError: Error?

        for baseURL in SolanaProvider.balanceRPCBaseURLs {
            var rawByMint: [String: Decimal] = [:]
            var sourceTokenAccountByMint: [String: String] = [:]
            var decimalsByMint: [String: Int] = [:]

            for programID in programs {
                guard let endpoint = URL(string: baseURL) else { continue }
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 20
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "getTokenAccountsByOwner",
                        "params": [
                            ownerAddress,
                            ["programId": programID],
                            ["encoding": "jsonParsed", "commitment": "confirmed"],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                        continue
                    }
                    guard
                        let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                        let result = root["result"] as? [String: Any],
                        let value = result["value"] as? [[String: Any]]
                    else {
                        continue
                    }

                    for item in value {
                        guard
                            let pubkey = item["pubkey"] as? String,
                            let account = item["account"] as? [String: Any],
                            let dataObj = account["data"] as? [String: Any],
                            let parsed = dataObj["parsed"] as? [String: Any],
                            let info = parsed["info"] as? [String: Any],
                            let mint = info["mint"] as? String,
                            let tokenAmount = info["tokenAmount"] as? [String: Any],
                            let amountText = tokenAmount["amount"] as? String,
                            let rawAmount = Decimal(string: amountText),
                            rawAmount > 0
                        else {
                            continue
                        }

                        rawByMint[mint, default: 0] += rawAmount
                        if sourceTokenAccountByMint[mint] == nil {
                            sourceTokenAccountByMint[mint] = pubkey
                        }
                        if let decimals = tokenAmount["decimals"] as? Int {
                            decimalsByMint[mint] = decimals
                        }
                    }
                } catch {
                    lastError = error
                    continue
                }
            }

            guard !rawByMint.isEmpty else { continue }

            let snapshots: [SolanaSPLTokenBalanceSnapshot] = rawByMint.compactMap { mint, rawAmount in
                guard
                    let metadata = trackedTokenMetadataByMint[mint],
                    let sourceTokenAccountAddress = sourceTokenAccountByMint[mint],
                    !sourceTokenAccountAddress.isEmpty
                else {
                    return nil
                }

                let decimals = decimalsByMint[mint] ?? metadata.decimals
                let divisor = pow(10.0, Double(decimals))
                guard divisor > 0 else { return nil }
                let amount = NSDecimalNumber(decimal: rawAmount).doubleValue / divisor
                guard amount > 0 else { return nil }

                return SolanaSPLTokenBalanceSnapshot(
                    mintAddress: mint,
                    sourceTokenAccountAddress: sourceTokenAccountAddress,
                    symbol: metadata.symbol,
                    name: metadata.name,
                    tokenStandard: "SPL",
                    decimals: decimals,
                    balance: amount,
                    marketDataID: metadata.marketDataID,
                    coinGeckoID: metadata.coinGeckoID
                )
            }

            if !snapshots.isEmpty {
                return snapshots
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }
}
