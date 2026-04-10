import Foundation

enum ICPBalanceServiceError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpError(Int)
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return AppLocalization.string("The ICP account identifier is not valid.")
        case .invalidResponse:
            return AppLocalization.string("The ICP Rosetta response was invalid.")
        case .httpError(let code):
            let format = AppLocalization.string("The ICP Rosetta endpoint returned HTTP %d.")
            return String(format: format, locale: AppLocalization.locale, code)
        case .rpcError(let message):
            let format = AppLocalization.string("ICP Rosetta error: %@")
            return String(format: format, locale: AppLocalization.locale, AppLocalization.string(message))
        }
    }
}

struct ICPHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct ICPHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

enum ICPBalanceService {
    private static let e8Divisor = Decimal(string: "100000000")!

    static func endpointCatalog() -> [String] {
        ICPProvider.endpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        ICPProvider.diagnosticsChecks()
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidICPAddress(address)
    }

    static func fetchBalance(for address: String) async throws -> Double {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            throw ICPBalanceServiceError.invalidAddress
        }

        var lastError: Error?
        for endpoint in ICPProvider.rosettaEndpoints {
            do {
                let request = ICPProvider.AccountBalanceRequest(
                    networkIdentifier: ICPProvider.networkIdentifier,
                    accountIdentifier: ICPProvider.AccountIdentifier(address: normalized)
                )
                let response: ICPProvider.AccountBalanceResponse = try await post(
                    endpoint: endpoint,
                    path: "/account/balance",
                    requestBody: request
                )
                guard let balanceValue = response.balances.first?.value,
                      let balanceDecimal = Decimal(string: balanceValue) else {
                    throw ICPBalanceServiceError.invalidResponse
                }
                return decimalToDouble(balanceDecimal / e8Divisor)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ICPBalanceServiceError.invalidResponse
    }

    static func fetchSuggestedTransferFeeE8s() async throws -> UInt64 {
        var lastError: Error?
        for endpoint in ICPProvider.rosettaEndpoints {
            do {
                let request = ICPProvider.ConstructionMetadataRequest(
                    networkIdentifier: ICPProvider.networkIdentifier,
                    options: ICPProvider.ConstructionMetadataOptions(requestTypes: ["TRANSACTION"]),
                    publicKeys: nil
                )
                let response: ICPProvider.ConstructionMetadataResponse = try await post(
                    endpoint: endpoint,
                    path: "/construction/metadata",
                    requestBody: request
                )
                if let feeValue = response.suggestedFee?.first?.value,
                   let feeE8s = UInt64(feeValue),
                   feeE8s > 0 {
                    return feeE8s
                }
                throw ICPBalanceServiceError.invalidResponse
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ICPBalanceServiceError.invalidResponse
    }

    static func fetchRecentHistoryWithDiagnostics(for address: String, limit: Int = 80) async -> (snapshots: [ICPHistorySnapshot], diagnostics: ICPHistoryDiagnostics) {
        let normalized = normalizedAddress(address)
        guard isValidAddress(normalized) else {
            return (
                [],
                ICPHistoryDiagnostics(
                    address: normalized,
                    sourceUsed: "none",
                    transactionCount: 0,
                    error: ICPBalanceServiceError.invalidAddress.localizedDescription
                )
            )
        }

        let boundedLimit = max(1, min(limit, 80))
        var lastError: String?
        for endpoint in ICPProvider.rosettaEndpoints {
            do {
                let request = ICPProvider.SearchTransactionsRequest(
                    networkIdentifier: ICPProvider.networkIdentifier,
                    accountIdentifier: ICPProvider.AccountIdentifier(address: normalized),
                    transactionIdentifier: nil,
                    limit: boundedLimit
                )
                let response: ICPProvider.SearchTransactionsResponse = try await post(
                    endpoint: endpoint,
                    path: "/search/transactions",
                    requestBody: request
                )
                let snapshots = response.transactions.compactMap { snapshot(from: $0, ownerAddress: normalized) }
                return (
                    snapshots,
                    ICPHistoryDiagnostics(
                        address: normalized,
                        sourceUsed: endpoint,
                        transactionCount: snapshots.count,
                        error: nil
                    )
                )
            } catch {
                lastError = error.localizedDescription
            }
        }

        return (
            [],
            ICPHistoryDiagnostics(
                address: normalized,
                sourceUsed: ICPProvider.rosettaEndpoints.first ?? "none",
                transactionCount: 0,
                error: lastError ?? ICPBalanceServiceError.invalidResponse.localizedDescription
            )
        )
    }

    static func submitSignedTransaction(_ signedTransactionHex: String) async throws -> String {
        let trimmed = signedTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ICPBalanceServiceError.invalidResponse
        }

        var lastError: Error?
        for endpoint in ICPProvider.orderedRosettaEndpoints() {
            do {
                let request = ICPProvider.ConstructionSubmitRequest(
                    networkIdentifier: ICPProvider.networkIdentifier,
                    signedTransaction: trimmed
                )
                let response: ICPProvider.ConstructionSubmitResponse = try await post(
                    endpoint: endpoint,
                    path: "/construction/submit",
                    requestBody: request
                )
                guard let hash = response.transactionIdentifier?.hash?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !hash.isEmpty else {
                    throw ICPBalanceServiceError.invalidResponse
                }
                ChainEndpointReliability.recordAttempt(namespace: ICPProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                return hash
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: ICPProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
            }
        }

        throw lastError ?? ICPBalanceServiceError.invalidResponse
    }

    static func verifyTransactionIfAvailable(_ transactionHash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else {
            return .deferred
        }

        var lastError: String?
        for endpoint in ICPProvider.orderedRosettaEndpoints() {
            do {
                let request = ICPProvider.SearchTransactionsRequest(
                    networkIdentifier: ICPProvider.networkIdentifier,
                    accountIdentifier: nil,
                    transactionIdentifier: ICPProvider.TransactionIdentifier(hash: normalizedHash),
                    limit: 1
                )
                let response: ICPProvider.SearchTransactionsResponse = try await post(
                    endpoint: endpoint,
                    path: "/search/transactions",
                    requestBody: request
                )
                if response.transactions.contains(where: {
                    $0.transaction.transactionIdentifier.hash?.caseInsensitiveCompare(normalizedHash) == .orderedSame
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

    private static func snapshot(from entry: ICPProvider.SearchTransactionEntry, ownerAddress: String) -> ICPHistorySnapshot? {
        let operations = entry.transaction.operations
        let transferOperations = operations.filter {
            $0.type?.caseInsensitiveCompare("TRANSACTION") == .orderedSame
        }
        guard let ownerOperation = transferOperations.first(where: { normalizedAddress($0.account?.address ?? "") == ownerAddress }),
              let valueText = ownerOperation.amount?.value,
              let valueDecimal = Decimal(string: valueText) else {
            return nil
        }

        let transactionHash = entry.transaction.transactionIdentifier.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !transactionHash.isEmpty else { return nil }

        let statusText = ownerOperation.status?.lowercased() ?? ""
        let status: TransactionStatus = statusText.contains("complete") ? .confirmed : .pending
        let kind: TransactionKind = valueDecimal.sign == .minus ? .send : .receive
        let amount = decimalToDouble((valueDecimal.magnitude) / e8Divisor)
        let counterparty = transferOperations.first {
            normalizedAddress($0.account?.address ?? "") != ownerAddress
        }?.account?.address ?? ownerAddress

        let createdAt = entry.transaction.metadata?.timestamp.map {
            Date(timeIntervalSince1970: Double($0) / 1_000_000_000.0)
        } ?? Date()

        return ICPHistorySnapshot(
            transactionHash: transactionHash,
            kind: kind,
            amount: amount,
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: status
        )
    }

    private static func post<RequestBody: Encodable, ResponseBody: Decodable>(
        endpoint: String,
        path: String,
        requestBody: RequestBody
    ) async throws -> ResponseBody {
        guard let url = URL(string: endpoint + path) else {
            throw ICPBalanceServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
        guard let http = response as? HTTPURLResponse else {
            throw ICPBalanceServiceError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            if let rosettaError = try? JSONDecoder().decode(ICPProvider.RosettaErrorResponse.self, from: data),
               let message = rosettaError.details?.errorMessage ?? rosettaError.message {
                throw ICPBalanceServiceError.rpcError(message)
            }
            throw ICPBalanceServiceError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func decimalToDouble(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

}
