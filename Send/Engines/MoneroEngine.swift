import Foundation

enum MoneroWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case backendNotConfigured
    case backendRejected(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Monero")
        case .invalidAmount:
            return CommonLocalization.invalidAmount("Monero")
        case .backendNotConfigured:
            return AppLocalization.string("Monero backend is not configured.")
        case .backendRejected(let message):
            return AppLocalization.string(message)
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Monero")
        }
    }
}

struct MoneroSendPreview: Equatable {
    let estimatedNetworkFeeXMR: Double
    let priorityLabel: String
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct MoneroSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeXMR: Double
    let verificationStatus: SendBroadcastVerificationStatus
}

enum MoneroWalletEngine {
    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> MoneroSendPreview {
        let source = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidMoneroAddress(source),
              AddressValidation.isValidMoneroAddress(destination) else {
            throw MoneroWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw MoneroWalletEngineError.invalidAmount
        }
        let candidates = MoneroBalanceService.candidateBackendBaseURLs()
        guard !candidates.isEmpty else {
            throw MoneroWalletEngineError.backendNotConfigured
        }
        var lastError: Error = MoneroWalletEngineError.invalidResponse
        for (index, baseURL) in candidates.enumerated() {
            let endpoint = baseURL.appendingPathComponent("v1/monero/estimate-fee")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = MoneroBalanceService.configuredBackendAPIKey() {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(MoneroProvider.PreviewRequest(fromAddress: source, toAddress: destination, amountXMR: amount))
            do {
                let (data, response) = try await ProviderHTTP.sessionData(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    lastError = MoneroWalletEngineError.backendRejected(message)
                    if index < candidates.count - 1, [404, 405, 429, 500, 501, 502, 503, 504].contains(http.statusCode) {
                        continue
                    }
                    throw lastError
                }
                let decoded = try JSONDecoder().decode(MoneroProvider.PreviewResponse.self, from: data)
                guard decoded.estimatedFeeXMR.isFinite, decoded.estimatedFeeXMR >= 0 else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                return MoneroSendPreview(
                    estimatedNetworkFeeXMR: decoded.estimatedFeeXMR,
                    priorityLabel: decoded.priority ?? "normal",
                    spendableBalance: max(0, (try await MoneroBalanceService.fetchBalance(for: source)) - decoded.estimatedFeeXMR),
                    feeRateDescription: decoded.priority ?? "normal",
                    estimatedTransactionBytes: nil,
                    selectedInputCount: nil,
                    usesChangeOutput: nil,
                    maxSendable: max(0, (try await MoneroBalanceService.fetchBalance(for: source)) - decoded.estimatedFeeXMR)
                )
            } catch {
                lastError = error
                if index < candidates.count - 1 {
                    continue
                }
            }
        }
        throw lastError
    }

    static func sendInBackground(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        providerIDs: Set<String>? = nil
    ) async throws -> MoneroSendResult {
        let source = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidMoneroAddress(source),
              AddressValidation.isValidMoneroAddress(destination) else {
            throw MoneroWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw MoneroWalletEngineError.invalidAmount
        }
        let candidates = filteredBackendBaseURLs(providerIDs: providerIDs)
        guard !candidates.isEmpty else {
            throw MoneroWalletEngineError.backendNotConfigured
        }
        var lastError: Error = MoneroWalletEngineError.invalidResponse
        for (index, baseURL) in candidates.enumerated() {
            let endpoint = baseURL.appendingPathComponent("v1/monero/send")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = MoneroBalanceService.configuredBackendAPIKey() {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(MoneroProvider.SendRequest(fromAddress: source, toAddress: destination, amountXMR: amount))
            do {
                let (data, response) = try await ProviderHTTP.sessionData(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    lastError = MoneroWalletEngineError.backendRejected(message)
                    if index < candidates.count - 1, [404, 405, 429, 500, 501, 502, 503, 504].contains(http.statusCode) {
                        continue
                    }
                    throw lastError
                }
                let decoded = try JSONDecoder().decode(MoneroProvider.SendResponse.self, from: data)
                let txid = decoded.txid.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !txid.isEmpty else {
                    lastError = MoneroWalletEngineError.invalidResponse
                    continue
                }
                return MoneroSendResult(
                    transactionHash: txid,
                    estimatedNetworkFeeXMR: max(0, decoded.feeXMR ?? 0),
                    verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: source, transactionHash: txid)
                )
            } catch {
                lastError = error
                if classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                   let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                       ownerAddress: source,
                       destinationAddress: destination,
                       amount: amount
                   ) {
                    return MoneroSendResult(
                        transactionHash: recoveredHash,
                        estimatedNetworkFeeXMR: 0,
                        verificationStatus: await verifyBroadcastedTransactionIfAvailable(
                            ownerAddress: source,
                            transactionHash: recoveredHash
                        )
                    )
                }
                if index < candidates.count - 1 {
                    continue
                }
            }
        }
        throw lastError
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHash.isEmpty else {
            return .deferred
        }
        let result = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        if let snapshot = result.snapshots.first(where: { $0.transactionHash.lowercased() == normalizedHash }) {
            switch snapshot.status {
            case .failed:
                return .failed("The Monero backend reported the transaction as failed.")
            case .pending, .confirmed:
                return .verified
            }
        }
        if let error = result.diagnostics.error, !error.isEmpty {
            return .failed(error)
        }
        return .deferred
    }

    private static func recoverRecentTransactionHashIfAvailable(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async -> String? {
        let result = await MoneroBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        return result.snapshots.first {
            $0.kind == .send
                && abs($0.amount - amount) < 0.000000000001
                && $0.counterpartyAddress.lowercased() == destinationAddress.lowercased()
        }?.transactionHash
    }

    private static func filteredBackendBaseURLs(providerIDs: Set<String>? = nil) -> [URL] {
        let candidates = MoneroBalanceService.candidateBackendBaseURLs()
        guard let providerIDs, !providerIDs.isEmpty else { return candidates }
        return candidates.filter { endpoint in
            switch endpoint.absoluteString {
            case "https://monerolws1.edge.app":
                return providerIDs.contains("edge-lws-1")
            case "https://monerolws2.edge.app":
                return providerIDs.contains("edge-lws-2")
            case "https://monerolws3.edge.app":
                return providerIDs.contains("edge-lws-3")
            default:
                return false
            }
        }
    }
}
