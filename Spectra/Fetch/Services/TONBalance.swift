import Foundation
import WalletCore

enum TONBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("TON")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("TON")
        case .rpcError(let message):
            return CommonLocalization.rpcError("TON", message: message)
        }
    }
}

struct TONHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct TONHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct TONJettonBalanceSnapshot: Equatable {
    let masterAddress: String
    let walletAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}

struct TONPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [TONJettonBalanceSnapshot]
}

enum TONBalanceService {
    private static let tonDivisor = Decimal(string: "1000000000")!

    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }

    static func endpointCatalog() -> [String] {
        TONProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        TONProvider.diagnosticsChecks()
    }

    static func normalizeJettonMasterAddress(_ address: String) -> String {
        canonicalAddressIdentifier(address)
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidTONAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw TONBalanceServiceError.invalidAddress
        }

        var lastError: Error?
        for endpoint in TONProvider.apiV2BaseURLs {
            do {
                var components = URLComponents(string: "\(endpoint)/getWalletInformation")
                components?.queryItems = [URLQueryItem(name: "address", value: normalized)]
                guard let url = components?.url else {
                    throw TONBalanceServiceError.invalidResponse
                }
                let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw TONBalanceServiceError.rpcError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let envelope = try JSONDecoder().decode(TONProvider.WalletInformationEnvelope.self, from: data)
                guard envelope.ok == true,
                      let balanceText = envelope.result?.balance,
                      let balance = Decimal(string: balanceText) else {
                    throw TONBalanceServiceError.rpcError(envelope.error ?? "Missing TON balance.")
                }
                return decimalToDouble(balance / tonDivisor)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? TONBalanceServiceError.invalidResponse
    }

    static func fetchPortfolio(
        for address: String,
        trackedTokenMetadataByMasterAddress: [String: KnownTokenMetadata]
    ) async throws -> TONPortfolioSnapshot {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw TONBalanceServiceError.invalidAddress
        }

        async let nativeBalanceTask = fetchBalance(for: normalized)
        let tokenBalances = try await fetchTrackedJettonBalances(
            for: normalized,
            trackedTokenMetadataByMasterAddress: trackedTokenMetadataByMasterAddress
        )

        return TONPortfolioSnapshot(
            nativeBalance: try await nativeBalanceTask,
            tokenBalances: tokenBalances
        )
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 40) async -> (snapshots: [TONHistorySnapshot], diagnostics: TONHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                TONHistoryDiagnostics(address: normalized, sourceUsed: "none", transactionCount: 0, error: TONBalanceServiceError.invalidAddress.localizedDescription)
            )
        }

        let boundedLimit = max(1, min(limit, 80))
        var lastError: String?
        for endpoint in TONProvider.apiV2BaseURLs {
            do {
                var components = URLComponents(string: "\(endpoint)/getTransactions")
                components?.queryItems = [
                    URLQueryItem(name: "address", value: normalized),
                    URLQueryItem(name: "limit", value: String(boundedLimit))
                ]
                guard let url = components?.url else {
                    throw TONBalanceServiceError.invalidResponse
                }
                let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw TONBalanceServiceError.rpcError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let snapshots = try parseTransactionHistoryResponse(data, ownerAddress: normalized)
                return (
                    snapshots,
                    TONHistoryDiagnostics(address: normalized, sourceUsed: endpoint, transactionCount: snapshots.count, error: nil)
                )
            } catch {
                lastError = error.localizedDescription
            }
        }

        return (
            [],
            TONHistoryDiagnostics(
                address: normalized,
                sourceUsed: TONProvider.apiV2BaseURLs.first ?? "none",
                transactionCount: 0,
                error: lastError ?? TONBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    static func verifyTransactionIfAvailable(_ transactionHash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else {
            return .deferred
        }

        var lastError: String?
        for endpoint in TONProvider.apiV3BaseURLs {
            do {
                var components = URLComponents(string: "\(endpoint)/transactions")
                components?.queryItems = [
                    URLQueryItem(name: "hash", value: normalizedHash),
                    URLQueryItem(name: "limit", value: "1")
                ]
                guard let url = components?.url else {
                    throw TONBalanceServiceError.invalidResponse
                }

                let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw TONBalanceServiceError.rpcError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }

                let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                let rows = transactionRows(from: jsonObject)
                if rows.contains(where: {
                    (stringValue(in: $0, keys: ["hash", "transaction_hash"]) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(normalizedHash) == .orderedSame
                }) {
                    return .verified
                }
            } catch {
                lastError = error.localizedDescription
            }
        }

        if let lastError {
            return .failed(lastError)
        }
        return .deferred
    }

    private static func parseTransactionHistoryResponse(_ data: Data, ownerAddress: String) throws -> [TONHistorySnapshot] {
        if let envelope = try? JSONDecoder().decode(TONProvider.TransactionsEnvelope.self, from: data),
           let result = envelope.result {
            return result.compactMap { snapshot(from: $0, ownerAddress: ownerAddress) }
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let rows = transactionRows(from: jsonObject)
        return rows.compactMap { snapshot(from: $0, ownerAddress: ownerAddress) }
    }

    private static func transactionRows(from jsonObject: Any) -> [[String: Any]] {
        if let rows = jsonObject as? [[String: Any]] {
            return rows
        }
        guard let dictionary = jsonObject as? [String: Any] else {
            return []
        }
        if let rows = dictionary["result"] as? [[String: Any]] {
            return rows
        }
        if let result = dictionary["result"] as? [String: Any] {
            if let rows = result["transactions"] as? [[String: Any]] {
                return rows
            }
            if let rows = result["items"] as? [[String: Any]] {
                return rows
            }
        }
        if let rows = dictionary["transactions"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["items"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["transactions"] as? [[String: Any]] {
            return rows
        }
        return []
    }

    private static func snapshot(from row: [String: Any], ownerAddress: String) -> TONHistorySnapshot? {
        let txHash = stringValue(in: row, keys: ["hash", "transaction_hash"])
            ?? ((row["transaction_id"] as? [String: Any]).flatMap { stringValue(in: $0, keys: ["hash"]) })
        guard let txHash, !txHash.isEmpty else { return nil }

        let timestampValue = numberValue(in: row, keys: ["utime", "timestamp", "now"]) ?? 0
        let timestamp = Date(timeIntervalSince1970: timestampValue)

        let inbound = row["in_msg"] as? [String: Any]
        let outboundMessages = (row["out_msgs"] as? [[String: Any]]) ?? []

        let inboundDestination = normalizedAddress(stringValue(in: inbound ?? [:], keys: ["destination", "dst"]) ?? "")
        let inboundSource = normalizedAddress(stringValue(in: inbound ?? [:], keys: ["source", "src"]) ?? "")
        let inboundValue = decimalValue(in: inbound ?? [:], keys: ["value", "amount"]) ?? 0
        if inboundDestination == ownerAddress, inboundSource != ownerAddress, inboundValue > 0 {
            return TONHistorySnapshot(
                transactionHash: txHash,
                kind: .receive,
                amount: decimalToDouble(inboundValue / tonDivisor),
                counterpartyAddress: stringValue(in: inbound ?? [:], keys: ["source", "src"]) ?? ownerAddress,
                createdAt: timestamp,
                status: .confirmed
            )
        }

        if let outbound = outboundMessages.first(where: {
            normalizedAddress(stringValue(in: $0, keys: ["destination", "dst"]) ?? "") != ownerAddress
                && (decimalValue(in: $0, keys: ["value", "amount"]) ?? 0) > 0
        }), let amount = decimalValue(in: outbound, keys: ["value", "amount"]), amount > 0 {
            return TONHistorySnapshot(
                transactionHash: txHash,
                kind: .send,
                amount: decimalToDouble(amount / tonDivisor),
                counterpartyAddress: stringValue(in: outbound, keys: ["destination", "dst"]) ?? ownerAddress,
                createdAt: timestamp,
                status: .confirmed
            )
        }

        return nil
    }

    private static func snapshot(from entry: TONProvider.TransactionEntry, ownerAddress: String) -> TONHistorySnapshot? {
        let txHash = entry.transactionID?.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !txHash.isEmpty else { return nil }

        let inbound = entry.inMsg
        let outboundMessages = entry.outMsgs ?? []
        let timestamp = Date(timeIntervalSince1970: Double(entry.utime ?? 0))

        if normalizedAddress(inbound?.destination ?? "") == ownerAddress,
           normalizedAddress(inbound?.source ?? "") != ownerAddress,
           let amountText = inbound?.value,
           let amount = Decimal(string: amountText),
           amount > 0 {
            return TONHistorySnapshot(
                transactionHash: txHash,
                kind: .receive,
                amount: decimalToDouble(amount / tonDivisor),
                counterpartyAddress: inbound?.source ?? ownerAddress,
                createdAt: timestamp,
                status: .confirmed
            )
        }

        if let outbound = outboundMessages.first(where: {
            normalizedAddress($0.destination ?? "") != ownerAddress && (Decimal(string: $0.value ?? "") ?? 0) > 0
        }), let amountText = outbound.value, let amount = Decimal(string: amountText), amount > 0 {
            return TONHistorySnapshot(
                transactionHash: txHash,
                kind: .send,
                amount: decimalToDouble(amount / tonDivisor),
                counterpartyAddress: outbound.destination ?? ownerAddress,
                createdAt: timestamp,
                status: .confirmed
            )
        }

        return nil
    }

    private static func stringValue(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let string = row[key] as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func numberValue(in row: [String: Any], keys: [String]) -> TimeInterval? {
        for key in keys {
            if let number = row[key] as? NSNumber {
                return number.doubleValue
            }
            if let string = row[key] as? String, let value = Double(string) {
                return value
            }
        }
        return nil
    }

    private static func decimalValue(in row: [String: Any], keys: [String]) -> Decimal? {
        for key in keys {
            if let string = row[key] as? String, let value = Decimal(string: string) {
                return value
            }
            if let number = row[key] as? NSNumber {
                return number.decimalValue
            }
        }
        return nil
    }

    private static func fetchTrackedJettonBalances(
        for address: String,
        trackedTokenMetadataByMasterAddress: [String: KnownTokenMetadata]
    ) async throws -> [TONJettonBalanceSnapshot] {
        let trackedByMaster = Dictionary(
            uniqueKeysWithValues: trackedTokenMetadataByMasterAddress.map {
                (normalizeJettonMasterAddress($0.key), $0.value)
            }
        )
        guard !trackedByMaster.isEmpty else { return [] }

        var lastError: Error?
        for endpoint in TONProvider.apiV3BaseURLs {
            do {
                var components = URLComponents(string: "\(endpoint)/jetton/wallets")
                components?.queryItems = [
                    URLQueryItem(name: "owner_address", value: address),
                    URLQueryItem(name: "limit", value: "200")
                ]
                guard let url = components?.url else {
                    throw TONBalanceServiceError.invalidResponse
                }

                let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw TONBalanceServiceError.rpcError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }

                let envelope = try JSONDecoder().decode(TONProvider.JettonWalletsEnvelope.self, from: data)
                let wallets = envelope.jettonWallets ?? []
                var snapshots: [TONJettonBalanceSnapshot] = []
                snapshots.reserveCapacity(wallets.count)

                for wallet in wallets {
                    let masterAddress = normalizeJettonMasterAddress(wallet.jetton?.address ?? "")
                    guard let metadata = trackedByMaster[masterAddress],
                          let balanceText = wallet.balance,
                          let rawBalance = Decimal(string: balanceText),
                          rawBalance > 0 else {
                        continue
                    }

                    let divisor = decimalPowerOfTen(min(max(metadata.decimals, 0), 30))
                    let balance = decimalToDouble(rawBalance / divisor)
                    guard balance.isFinite, balance > 0 else { continue }

                    snapshots.append(
                        TONJettonBalanceSnapshot(
                            masterAddress: wallet.jetton?.address ?? masterAddress,
                            walletAddress: wallet.address ?? "",
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

                return snapshots
            } catch {
                lastError = error
            }
        }

        throw lastError ?? TONBalanceServiceError.invalidResponse
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decimalToDouble(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        guard exponent > 0 else { return result }
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }

    private static func canonicalAddressIdentifier(_ address: String?) -> String {
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        if let anyAddress = AnyAddress(string: trimmed, coin: .ton) {
            return anyAddress.description
        }
        return trimmed
    }
}
