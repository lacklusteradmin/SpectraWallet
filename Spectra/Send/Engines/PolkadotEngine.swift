import Foundation
import SwiftProtobuf
import WalletCore

enum PolkadotWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Polkadot")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Polkadot")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Polkadot")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Polkadot")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("Polkadot", message: message)
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("Polkadot", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Polkadot", message: message)
        }
    }
}

struct PolkadotSendPreview: Equatable {
    let estimatedNetworkFeeDOT: Double
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct PolkadotSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeDOT: Double
    let signedExtrinsicHex: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum PolkadotWalletEngine {
    private static let dotDivisor = Decimal(string: "10000000000")!

    static func derivedAddress(for seedPhrase: String, derivationPath: String = "m/44'/354'/0'") throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .polkadot,
            derivationPath: derivationPath
        )
        let normalized = material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidPolkadotAddress(normalized) else {
            throw PolkadotWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func estimateSendPreview(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String = "m/44'/354'/0'"
    ) async throws -> PolkadotSendPreview {
        let prepared = try await prepareSignedExtrinsic(
            seedPhrase: seedPhrase,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            derivationPath: derivationPath
        )
        let fee = try await fetchFeeEstimate(for: prepared.encodedExtrinsicHex)
        let balanceDOT = try await PolkadotBalanceService.fetchBalance(for: ownerAddress)
        let maxSendable = max(0, balanceDOT - fee)
        return PolkadotSendPreview(
            estimatedNetworkFeeDOT: fee,
            spendableBalance: maxSendable,
            feeRateDescription: nil,
            estimatedTransactionBytes: prepared.encodedExtrinsicHex.count / 2,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: maxSendable
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String = "m/44'/354'/0'"
    ) async throws -> PolkadotSendResult {
        let prepared = try await prepareSignedExtrinsic(
            seedPhrase: seedPhrase,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            derivationPath: derivationPath
        )
        let fee = (try? await fetchFeeEstimate(for: prepared.encodedExtrinsicHex)) ?? 0
        let transactionHash: String
        do {
            transactionHash = try await broadcastExtrinsic(prepared.encodedExtrinsicHex)
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: ownerAddress,
                      destinationAddress: destinationAddress,
                      amount: amount
                  ) else {
                throw error
            }
            transactionHash = recoveredHash
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
            ownerAddress: ownerAddress,
            transactionHash: transactionHash
        )
        return PolkadotSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeDOT: fee,
            signedExtrinsicHex: prepared.encodedExtrinsicHex,
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedExtrinsicHex: String,
        expectedTransactionHash: String? = nil
    ) async throws -> PolkadotSendResult {
        let normalizedExtrinsic = signedExtrinsicHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexPayload = normalizedExtrinsic.hasPrefix("0x") ? String(normalizedExtrinsic.dropFirst(2)) : normalizedExtrinsic
        guard !hexPayload.isEmpty,
              Data(hexString: hexPayload) != nil else {
            throw PolkadotWalletEngineError.invalidResponse
        }
        let transactionHash = try await broadcastExtrinsic(normalizedExtrinsic)
        let recoveredHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : transactionHash
        return PolkadotSendResult(
            transactionHash: recoveredHash,
            estimatedNetworkFeeDOT: 0,
            signedExtrinsicHex: normalizedExtrinsic,
            verificationStatus: await PolkadotBalanceService.verifyTransactionIfAvailable(recoveredHash)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        await PolkadotBalanceService.verifyTransactionIfAvailable(transactionHash)
    }

    private struct PreparedExtrinsic {
        let encodedExtrinsicHex: String
    }

    private static func prepareSignedExtrinsic(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        derivationPath: String
    ) async throws -> PreparedExtrinsic {
        let normalizedOwner = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidPolkadotAddress(normalizedOwner),
              AddressValidation.isValidPolkadotAddress(normalizedDestination) else {
            throw PolkadotWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw PolkadotWalletEngineError.invalidAmount
        }

        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .polkadot,
            derivationPath: derivationPath
        )
        guard !material.privateKeyData.isEmpty else {
            throw PolkadotWalletEngineError.invalidSeedPhrase
        }
        guard material.address == normalizedOwner else {
            throw PolkadotWalletEngineError.invalidAddress
        }

        let txMaterial = try await fetchTransactionMaterial()
        let nonce = try await fetchNonce(for: normalizedOwner)
        let blockNumber = UInt64(txMaterial.at.height) ?? 0
        guard let privateKey = PrivateKey(data: material.privateKeyData) else {
            throw PolkadotWalletEngineError.invalidSeedPhrase
        }
        let value = try planckData(fromDOT: amount)

        let input = PolkadotSigningInput.with {
            $0.genesisHash = Data(hexString: txMaterial.genesisHash) ?? Data()
            $0.blockHash = Data(hexString: txMaterial.at.hash) ?? Data()
            $0.nonce = UInt64(max(nonce, 0))
            $0.specVersion = UInt32(txMaterial.specVersion) ?? 0
            $0.network = CoinType.polkadot.ss58Prefix
            $0.transactionVersion = UInt32(txMaterial.txVersion) ?? 0
            $0.privateKey = privateKey.data
            $0.era = PolkadotEra.with {
                $0.blockNumber = blockNumber
                $0.period = 64
            }
            $0.balanceCall.transfer = PolkadotBalance.Transfer.with {
                $0.toAddress = normalizedDestination
                $0.value = value
            }
        }

        let output: PolkadotSigningOutput = AnySigner.sign(input: input, coin: .polkadot)
        guard output.error == .ok else {
            let message = output.errorMessage.isEmpty ? String(describing: output.error) : output.errorMessage
            throw PolkadotWalletEngineError.signingFailed(message)
        }
        guard !output.encoded.isEmpty else {
            throw PolkadotWalletEngineError.signingFailed("WalletCore returned an empty extrinsic.")
        }

        return PreparedExtrinsic(encodedExtrinsicHex: "0x" + output.encoded.hexString)
    }

    private static func fetchTransactionMaterial() async throws -> PolkadotProvider.TransactionMaterial {
        var lastError: Error?
        for endpoint in PolkadotProvider.orderedSidecarEndpoints() {
            guard let url = URL(string: "\(endpoint)/transaction/material") else { continue }
            do {
                let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw PolkadotWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let decoded = try JSONDecoder().decode(PolkadotProvider.TransactionMaterial.self, from: data)
                ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                return decoded
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
            }
        }
        throw lastError ?? PolkadotWalletEngineError.invalidResponse
    }

    private static func fetchNonce(for address: String) async throws -> Int {
        var lastError: Error?
        for endpoint in PolkadotProvider.orderedSidecarEndpoints() {
            guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(endpoint)/accounts/\(encoded)/balance-info") else { continue }
            do {
                let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw PolkadotWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let info = try JSONDecoder().decode(PolkadotProvider.SidecarBalanceInfo.self, from: data)
                ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                return info.nonce ?? 0
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
            }
        }
        throw lastError ?? PolkadotWalletEngineError.invalidResponse
    }

    private static func fetchFeeEstimate(for extrinsicHex: String) async throws -> Double {
        let payload = try JSONSerialization.data(withJSONObject: ["tx": extrinsicHex], options: [])
        var lastError: Error?
        for endpoint in PolkadotProvider.orderedSidecarEndpoints() {
            guard let url = URL(string: "\(endpoint)/transaction/fee-estimate") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload

            do {
                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) else {
                    throw PolkadotWalletEngineError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                let envelope = try JSONDecoder().decode(PolkadotProvider.FeeEstimateEnvelope.self, from: data)
                if let feeText = envelope.estimatedFee ?? envelope.partialFee,
                   let fee = Decimal(string: feeText) {
                    ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                    return decimalToDouble(fee / dotDivisor)
                }
                if let inclusion = envelope.inclusionFee {
                    let base = Decimal(string: inclusion.baseFee ?? "0") ?? 0
                    let len = Decimal(string: inclusion.lenFee ?? "0") ?? 0
                    let adjusted = Decimal(string: inclusion.adjustedWeightFee ?? "0") ?? 0
                    let total = base + len + adjusted
                    if total > 0 {
                        ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                        return decimalToDouble(total / dotDivisor)
                    }
                }
                throw PolkadotWalletEngineError.invalidResponse
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
            }
        }
        throw lastError ?? PolkadotWalletEngineError.invalidResponse
    }

    private static func broadcastExtrinsic(_ extrinsicHex: String) async throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["tx": extrinsicHex], options: [])
        var lastError: Error?
        for endpoint in PolkadotProvider.orderedSidecarEndpoints() {
            guard let url = URL(string: "\(endpoint)/transaction") else { continue }
            for attempt in 0 ..< 2 {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = payload

                do {
                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                    guard let http = response as? HTTPURLResponse,
                          (200 ... 299).contains(http.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        let body = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
                        throw PolkadotWalletEngineError.networkError(body)
                    }
                    if let envelope = try? JSONDecoder().decode(PolkadotProvider.BroadcastEnvelope.self, from: data),
                       let hash = envelope.hash ?? envelope.txHash,
                       !hash.isEmpty {
                        ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                        return hash
                    }
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let hash = object["hash"] as? String ?? object["txHash"] as? String,
                       !hash.isEmpty {
                        ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: true)
                        return hash
                    }
                    throw PolkadotWalletEngineError.invalidResponse
                } catch {
                    lastError = error
                    ChainEndpointReliability.recordAttempt(namespace: PolkadotProvider.endpointReliabilityNamespace, endpoint: endpoint, success: false)
                    if attempt < 1, classifySendBroadcastFailure(error.localizedDescription) == .retryable {
                        continue
                    }
                    break
                }
            }
        }
        throw lastError ?? PolkadotWalletEngineError.broadcastFailed("All Polkadot broadcast endpoints failed.")
    }

    private static func recoverRecentTransactionHashIfAvailable(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async -> String? {
        let result = await PolkadotBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        return result.snapshots.first {
            $0.kind == .send
                && abs($0.amount - amount) < 0.0000000001
                && $0.counterpartyAddress.lowercased() == destinationAddress.lowercased()
        }?.transactionHash
    }

    private static func planckData(fromDOT amount: Double) throws -> Data {
        guard amount > 0 else {
            throw PolkadotWalletEngineError.invalidAmount
        }
        let amountText = String(format: "%.10f", amount)
        guard let dot = Decimal(string: amountText) else {
            throw PolkadotWalletEngineError.invalidAmount
        }
        let planckDecimal = dot * dotDivisor
        let rounded = NSDecimalNumber(decimal: planckDecimal).rounding(accordingToBehavior: nil)
        guard let integer = UInt64(exactly: rounded) else {
            throw PolkadotWalletEngineError.invalidAmount
        }
        return littleEndianUnsignedIntegerData(integer)
    }

    private static func littleEndianUnsignedIntegerData(_ value: UInt64) -> Data {
        if value == 0 { return Data([0]) }
        var little = value.littleEndian
        let data = withUnsafeBytes(of: &little) { Data($0) }
        if let lastNonZero = data.lastIndex(where: { $0 != 0 }) {
            return data.prefix(through: lastNonZero)
        }
        return Data([0])
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

}

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
