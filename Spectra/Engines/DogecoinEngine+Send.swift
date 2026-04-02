import Foundation
import WalletCore

extension DogecoinWalletEngine {
    static func walletCoreSignTransaction(
        keyMaterial: SigningKeyMaterial,
        utxos: [DogecoinUTXO],
        destinationAddress: String,
        amountDOGE: Double,
        changeAddress: String,
        feeRateDOGEPerKB: Double
    ) throws -> DogecoinWalletCoreSigningResult {
        let request = DogecoinWalletCoreSigningRequest(
            keyMaterial: keyMaterial,
            utxos: utxos,
            destinationAddress: destinationAddress,
            amountDOGE: amountDOGE,
            changeAddress: changeAddress,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let signingInput = try buildWalletCoreSigningInput(from: request)
        return try signWithWalletCore(input: signingInput)
    }

    static func buildWalletCoreSigningInput(
        from request: DogecoinWalletCoreSigningRequest
    ) throws -> BitcoinSigningInput {
        guard let sourceScript = standardScriptPubKey(for: request.keyMaterial.address) else {
            throw DogecoinWalletEngineError.transactionBuildFailed("Unable to derive source script for selected UTXOs.")
        }
        let amountKoinu = UInt64((request.amountDOGE * koinuPerDOGE).rounded())
        let feePerByteKoinu = max(1, Int64(((request.feeRateDOGEPerKB * koinuPerDOGE) / 1_000).rounded(.up)))

        var signingInput = BitcoinSigningInput()
        signingInput.hashType = 0x01
        signingInput.amount = Int64(amountKoinu)
        signingInput.byteFee = feePerByteKoinu
        signingInput.toAddress = walletCoreCompatibleAddress(request.destinationAddress)
        signingInput.changeAddress = walletCoreCompatibleAddress(request.changeAddress)
        signingInput.coinType = CoinType.dogecoin.rawValue
        signingInput.privateKey = [request.keyMaterial.privateKeyData]
        signingInput.utxo = try request.utxos.map { try walletCoreUnspentTransaction(from: $0, sourceScript: sourceScript) }
        return signingInput
    }

    static func walletCoreUnspentTransaction(
        from utxo: DogecoinUTXO,
        sourceScript: Data
    ) throws -> BitcoinUnspentTransaction {
        guard let txHashData = Data(hexEncoded: utxo.transactionHash), txHashData.count == 32 else {
            throw DogecoinWalletEngineError.transactionBuildFailed("One or more UTXOs had invalid txid encoding.")
        }
        var outPoint = BitcoinOutPoint()
        outPoint.hash = Data(txHashData.reversed())
        outPoint.index = UInt32(utxo.index)
        outPoint.sequence = UInt32.max

        var unspent = BitcoinUnspentTransaction()
        unspent.amount = Int64(utxo.value)
        unspent.script = sourceScript
        unspent.outPoint = outPoint
        return unspent
    }

    static func signWithWalletCore(input: BitcoinSigningInput) throws -> DogecoinWalletCoreSigningResult {
        let output: BitcoinSigningOutput = AnySigner.sign(input: input, coin: .dogecoin)
        if !output.errorMessage.isEmpty || output.encoded.isEmpty {
            throw DogecoinWalletEngineError.transactionSignFailed
        }
        return DogecoinWalletCoreSigningResult(
            encodedTransaction: output.encoded,
            transactionHash: output.transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func buildSpendPlan(
        from utxos: [DogecoinUTXO],
        amountDOGE: Double,
        feeRateDOGEPerKB: Double,
        maxInputCount: Int?
    ) throws -> DogecoinSpendPlan {
        guard amountDOGE >= dustThresholdDOGE else {
            throw DogecoinWalletEngineError.amountBelowDustThreshold
        }

        let sortedUTXOs = utxos.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            if $0.transactionHash != $1.transactionHash { return $0.transactionHash < $1.transactionHash }
            return $0.index < $1.index
        }

        let effectiveMaxInputCount = maxInputCount.map { max(1, $0) }
        var candidates: [[DogecoinUTXO]] = []
        candidates.reserveCapacity(sortedUTXOs.count * 2)

        var prefix: [DogecoinUTXO] = []
        prefix.reserveCapacity(sortedUTXOs.count)
        for utxo in sortedUTXOs {
            prefix.append(utxo)
            if let effectiveMaxInputCount, prefix.count > effectiveMaxInputCount {
                continue
            }
            candidates.append(prefix)
        }

        for utxo in sortedUTXOs {
            candidates.append([utxo])
        }

        var bestPlan: DogecoinSpendPlan?
        for candidate in candidates {
            guard let plan = evaluateCandidate(
                candidate,
                amountDOGE: amountDOGE,
                feeRateDOGEPerKB: feeRateDOGEPerKB
            ) else {
                continue
            }
            if let currentBest = bestPlan {
                if isBetterSpendPlan(plan, than: currentBest) {
                    bestPlan = plan
                }
            } else {
                bestPlan = plan
            }
        }

        guard let bestPlan else {
            throw DogecoinWalletEngineError.insufficientFunds
        }
        return bestPlan
    }

    static func evaluateCandidate(
        _ utxos: [DogecoinUTXO],
        amountDOGE: Double,
        feeRateDOGEPerKB: Double
    ) -> DogecoinSpendPlan? {
        guard !utxos.isEmpty else { return nil }
        let inputDOGE = Double(utxos.reduce(0) { $0 + $1.value }) / koinuPerDOGE

        let bytesWithChange = estimateTransactionBytes(inputCount: utxos.count, outputCount: 2)
        let feeWithChange = estimateNetworkFeeDOGE(
            estimatedBytes: bytesWithChange,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let changeWithChange = inputDOGE - amountDOGE - feeWithChange
        if changeWithChange >= dustThresholdDOGE {
            return DogecoinSpendPlan(
                utxos: utxos,
                totalInputDOGE: inputDOGE,
                feeDOGE: feeWithChange,
                changeDOGE: changeWithChange,
                usesChangeOutput: true,
                estimatedTransactionBytes: bytesWithChange
            )
        }

        let bytesWithoutChange = estimateTransactionBytes(inputCount: utxos.count, outputCount: 1)
        let baseFeeWithoutChange = estimateNetworkFeeDOGE(
            estimatedBytes: bytesWithoutChange,
            feeRateDOGEPerKB: feeRateDOGEPerKB
        )
        let remainderDOGE = inputDOGE - amountDOGE - baseFeeWithoutChange
        guard remainderDOGE >= 0 else {
            return nil
        }
        let effectiveFeeDOGE = baseFeeWithoutChange + remainderDOGE
        return DogecoinSpendPlan(
            utxos: utxos,
            totalInputDOGE: inputDOGE,
            feeDOGE: effectiveFeeDOGE,
            changeDOGE: 0,
            usesChangeOutput: false,
            estimatedTransactionBytes: bytesWithoutChange
        )
    }

    static func isBetterSpendPlan(_ lhs: DogecoinSpendPlan, than rhs: DogecoinSpendPlan) -> Bool {
        if lhs.usesChangeOutput != rhs.usesChangeOutput {
            return lhs.usesChangeOutput && !rhs.usesChangeOutput
        }
        if lhs.utxos.count != rhs.utxos.count {
            return lhs.utxos.count < rhs.utxos.count
        }
        if lhs.feeDOGE != rhs.feeDOGE {
            return lhs.feeDOGE < rhs.feeDOGE
        }
        return lhs.changeDOGE < rhs.changeDOGE
    }

    static func estimateTransactionBytes(inputCount: Int, outputCount: Int) -> Int {
        10 + (148 * inputCount) + (34 * outputCount)
    }

    static func estimateNetworkFeeDOGE(estimatedBytes: Int, feeRateDOGEPerKB: Double) -> Double {
        let kb = max(1, Int(ceil(Double(estimatedBytes) / 1000)))
        return Double(kb) * max(minRelayFeePerKB, feeRateDOGEPerKB)
    }

    static func broadcastRawTransaction(_ rawHex: String) throws {
        if networkMode == .testnet {
            try broadcastRawTransactionViaElectrs(rawHex)
            return
        }
        let providerOrder = orderedBroadcastProviders(counters: loadBroadcastReliabilityCounters())
        var providerErrors: [String] = []

        for provider in providerOrder {
            let maxAttempts = 2
            for attempt in 0 ..< maxAttempts {
                do {
                    try broadcastRawTransaction(rawHex, via: provider)
                    recordBroadcastAttempt(provider: provider, success: true)
                    return
                } catch {
                    let errorDescription = error.localizedDescription
                    if isAlreadyBroadcastedError(errorDescription) {
                        recordBroadcastAttempt(provider: provider, success: true)
                        return
                    }

                    recordBroadcastAttempt(provider: provider, success: false)
                    let shouldRetry = attempt < maxAttempts - 1 && isRetryableBroadcastError(errorDescription)
                    if shouldRetry {
                        usleep(UInt32(250_000 * (attempt + 1)))
                        continue
                    }

                    providerErrors.append("\(provider.rawValue.capitalized): \(errorDescription)")
                    break
                }
            }
        }

        let message = providerErrors.isEmpty
            ? "No broadcast provider accepted the transaction."
            : providerErrors.joined(separator: " | ")
        throw DogecoinWalletEngineError.broadcastFailed(message)
    }

    static func broadcastRawTransaction(_ rawHex: String, via provider: BroadcastProvider) throws {
        switch provider {
        case .blockchair:
            try broadcastRawTransactionViaBlockchair(rawHex)
        case .blockcypher:
            try broadcastRawTransactionViaBlockCypher(rawHex)
        }
    }

    static func broadcastRawTransactionViaBlockchair(_ rawHex: String) throws {
        guard let url = blockchairURL(path: "/push/transaction") else {
            throw DogecoinWalletEngineError.broadcastFailed("Invalid Dogecoin broadcast endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: rawHex)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let context = object["context"] as? [String: Any],
           let errorMessage = context["error"] as? String,
           !errorMessage.isEmpty {
            throw DogecoinWalletEngineError.broadcastFailed(errorMessage)
        }
    }

    static func broadcastRawTransactionViaBlockCypher(_ rawHex: String) throws {
        guard let url = blockcypherURL(path: "/txs/push") else {
            throw DogecoinWalletEngineError.broadcastFailed("Invalid BlockCypher broadcast endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["tx": rawHex], options: [])

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: 0
        )
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorMessage = object["error"] as? String, !errorMessage.isEmpty {
                throw DogecoinWalletEngineError.broadcastFailed(errorMessage)
            }
            if let errors = object["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["error"] as? String,
               !message.isEmpty {
                throw DogecoinWalletEngineError.broadcastFailed(message)
            }
        }
    }

    static func broadcastRawTransactionViaElectrs(_ rawHex: String) throws {
        guard let url = electrsURL(path: "/tx") else {
            throw DogecoinWalletEngineError.broadcastFailed("Invalid Dogecoin testnet broadcast endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = rawHex.data(using: .utf8)

        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: 0
        )
        let responseBody = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !responseBody.isEmpty, responseBody.lowercased().contains("error") {
            throw DogecoinWalletEngineError.broadcastFailed(responseBody)
        }
    }

    static func isAlreadyBroadcastedError(_ message: String) -> Bool {
        if classifySendBroadcastFailure(message) == .alreadyBroadcast {
            return true
        }
        let normalized = message.lowercased()
        return normalized.contains("already in blockchain")
            || normalized.contains("already in block chain")
            || normalized.contains("txn-already")
            || normalized.contains("already spent")
    }

    static func isRetryableBroadcastError(_ message: String) -> Bool {
        if classifySendBroadcastFailure(message) == .retryable {
            return true
        }
        return message.lowercased().contains("network")
    }

    static func orderedBroadcastProviders(
        counters: [String: BroadcastProviderReliabilityCounter]
    ) -> [BroadcastProvider] {
        enabledBroadcastProviders().sorted { lhs, rhs in
            let left = counters[lhs.rawValue] ?? BroadcastProviderReliabilityCounter(successCount: 0, failureCount: 0, lastUpdatedAt: 0)
            let right = counters[rhs.rawValue] ?? BroadcastProviderReliabilityCounter(successCount: 0, failureCount: 0, lastUpdatedAt: 0)
            let leftAttempts = left.successCount + left.failureCount
            let rightAttempts = right.successCount + right.failureCount
            let leftSuccessRate = leftAttempts == 0 ? 1.0 : Double(left.successCount) / Double(leftAttempts)
            let rightSuccessRate = rightAttempts == 0 ? 1.0 : Double(right.successCount) / Double(rightAttempts)

            if leftSuccessRate != rightSuccessRate {
                return leftSuccessRate > rightSuccessRate
            }
            if left.successCount != right.successCount {
                return left.successCount > right.successCount
            }
            return left.lastUpdatedAt > right.lastUpdatedAt
        }
    }

    static func enabledBroadcastProviders() -> [BroadcastProvider] {
        broadcastProviderSelectionLock.lock()
        defer { broadcastProviderSelectionLock.unlock() }
        guard let configuredProviderIDs = UserDefaults.standard.array(forKey: broadcastProviderSelectionDefaultsKey) as? [String] else {
            return BroadcastProvider.allCases
        }
        let providers = configuredProviderIDs.compactMap(BroadcastProvider.init(rawValue:))
        return providers.isEmpty ? BroadcastProvider.allCases : providers
    }

    static func loadBroadcastReliabilityCounters() -> [String: BroadcastProviderReliabilityCounter] {
        guard let data = UserDefaults.standard.data(forKey: broadcastReliabilityDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: BroadcastProviderReliabilityCounter].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func saveBroadcastReliabilityCounters(_ counters: [String: BroadcastProviderReliabilityCounter]) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: broadcastReliabilityDefaultsKey)
    }

    static func recordBroadcastAttempt(provider: BroadcastProvider, success: Bool) {
        var counters = loadBroadcastReliabilityCounters()
        var counter = counters[provider.rawValue] ?? BroadcastProviderReliabilityCounter(
            successCount: 0,
            failureCount: 0,
            lastUpdatedAt: 0
        )
        if success {
            counter.successCount += 1
        } else {
            counter.failureCount += 1
        }
        counter.lastUpdatedAt = Date().timeIntervalSince1970
        counters[provider.rawValue] = counter
        saveBroadcastReliabilityCounters(counters)
    }

    static func verifyBroadcastedTransactionIfAvailable(
        txid: String
    ) -> PostBroadcastVerificationStatus {
        let maxAttempts = 3
        for attempt in 0 ..< maxAttempts {
            let status = verifyPresenceOnlyIfAvailable(txid: txid)
            if status == .verified {
                return .verified
            }
            if attempt < maxAttempts - 1 {
                usleep(UInt32(350_000 * (attempt + 1)))
            }
        }
        return .deferred
    }

    static func verifyPresenceOnlyIfAvailable(txid: String) -> PostBroadcastVerificationStatus {
        if networkMode == .testnet {
            return (try? fetchElectrsTransactionHash(txid: txid)) != nil ? .verified : .deferred
        }
        if (try? fetchBlockchairTransactionHash(txid: txid)) != nil { return .verified }
        if (try? fetchBlockCypherTransactionHash(txid: txid)) != nil { return .verified }
        if (try? fetchSoChainTransactionHash(txid: txid)) != nil { return .verified }
        return .deferred
    }

    static func fetchBlockchairTransactionHash(txid: String) throws -> String? {
        guard let entry = try fetchBlockchairTransaction(txid: txid),
              let txHash = entry.transaction.hash,
              !txHash.isEmpty else {
            return nil
        }
        return txHash
    }

    static func fetchBlockCypherTransactionHash(txid: String) throws -> String? {
        guard let payload = try fetchBlockCypherTransaction(txid: txid),
              let txHash = payload.hash,
              !txHash.isEmpty else {
            return nil
        }
        return txHash
    }

    static func fetchSoChainTransactionHash(txid: String) throws -> String? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(ChainBackendRegistry.DogecoinRuntimeEndpoints.sochainBaseURL)/get_tx/DOGE/\(encodedTXID)") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid SoChain transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(request, timeout: networkTimeoutSeconds, retries: 0)
        let payload = try JSONDecoder().decode(SoChainTransactionResponse.self, from: data)
        guard payload.status?.lowercased() == "success",
              let tx = payload.data,
              let txHash = tx.txid,
              !txHash.isEmpty else {
            return nil
        }
        return txHash
    }

    static func fetchElectrsTransactionHash(txid: String) throws -> String? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = electrsURL(path: "/tx/\(encodedTXID)/status") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin testnet transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(request, timeout: networkTimeoutSeconds, retries: 0)
        let payload = try JSONDecoder().decode(ElectrsTransactionStatus.self, from: data)
        return payload.confirmed ? txid : nil
    }

    static func fetchBlockchairTransaction(txid: String) throws -> BlockchairTransactionDashboardEntry? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockchairURL(path: "/dashboards/transactions/\(encodedTXID)") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(request, timeout: networkTimeoutSeconds, retries: 0)
        let payload = try JSONDecoder().decode(BlockchairTransactionDashboardResponse.self, from: data)
        return payload.data.values.first
    }

    static func fetchBlockCypherTransaction(txid: String) throws -> BlockCypherTransactionResponse? {
        guard let encodedTXID = txid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = blockcypherURL(path: "/txs/\(encodedTXID)") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher Dogecoin transaction lookup URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(request, timeout: networkTimeoutSeconds, retries: 0)

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = object["error"] as? String,
           !errorMessage.isEmpty {
            if errorMessage.lowercased().contains("not found") {
                return nil
            }
            throw DogecoinWalletEngineError.networkFailure("BlockCypher transaction lookup failed: \(errorMessage)")
        }

        return try JSONDecoder().decode(BlockCypherTransactionResponse.self, from: data)
    }
}
