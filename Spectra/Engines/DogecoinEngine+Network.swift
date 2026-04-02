import Foundation

extension DogecoinWalletEngine {
    static func fetchSpendableUTXOs(for address: String) throws -> [DogecoinUTXO] {
        if networkMode == .testnet {
            let utxos = try fetchElectrsUTXOs(for: address)
            if !utxos.isEmpty {
                cacheUTXOs(utxos, for: address)
                return utxos
            }
            if let cached = cachedUTXOs(for: address) {
                return cached
            }
            return []
        }

        var providerErrors: [String] = []
        var providerResults: [UTXOProvider: [DogecoinUTXO]] = [:]

        for provider in UTXOProvider.allCases {
            do {
                let utxos: [DogecoinUTXO]
                switch provider {
                case .blockchair:
                    utxos = try fetchBlockchairUTXOs(for: address)
                case .blockcypher:
                    utxos = try fetchBlockCypherUTXOs(for: address)
                }
                providerResults[provider] = sanitizeUTXOs(utxos)
            } catch {
                providerErrors.append("\(provider.rawValue): \(error.localizedDescription)")
            }
        }

        if providerResults.isEmpty {
            if let cached = cachedUTXOs(for: address) {
                return cached
            }
            throw DogecoinWalletEngineError.networkFailure("All UTXO providers failed (\(providerErrors.joined(separator: " | "))).")
        }

        let merged: [DogecoinUTXO]
        if let blockchairUTXOs = providerResults[.blockchair],
           let blockcypherUTXOs = providerResults[.blockcypher] {
            merged = try mergeConsistentUTXOs(
                blockchairUTXOs: blockchairUTXOs,
                blockcypherUTXOs: blockcypherUTXOs
            )
        } else {
            merged = providerResults.values.first ?? []
        }

        if !merged.isEmpty {
            cacheUTXOs(merged, for: address)
            return merged
        }

        return cachedUTXOs(for: address) ?? []
    }

    static func sanitizeUTXOs(_ utxos: [DogecoinUTXO]) -> [DogecoinUTXO] {
        var deduped: [String: DogecoinUTXO] = [:]
        for utxo in utxos where utxo.value > 0 {
            let key = outpointKey(hash: utxo.transactionHash, index: utxo.index)
            if let existing = deduped[key] {
                deduped[key] = existing.value >= utxo.value ? existing : utxo
            } else {
                deduped[key] = utxo
            }
        }

        return deduped.values.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            if lhs.transactionHash != rhs.transactionHash {
                return lhs.transactionHash < rhs.transactionHash
            }
            return lhs.index < rhs.index
        }
    }

    static func mergeConsistentUTXOs(
        blockchairUTXOs: [DogecoinUTXO],
        blockcypherUTXOs: [DogecoinUTXO]
    ) throws -> [DogecoinUTXO] {
        let blockchairMap = Dictionary(uniqueKeysWithValues: blockchairUTXOs.map { (outpointKey(hash: $0.transactionHash, index: $0.index), $0) })
        let blockcypherMap = Dictionary(uniqueKeysWithValues: blockcypherUTXOs.map { (outpointKey(hash: $0.transactionHash, index: $0.index), $0) })

        let blockchairKeys = Set(blockchairMap.keys)
        let blockcypherKeys = Set(blockcypherMap.keys)
        let overlap = blockchairKeys.intersection(blockcypherKeys)

        for key in overlap {
            guard let lhs = blockchairMap[key], let rhs = blockcypherMap[key] else { continue }
            if lhs.value != rhs.value {
                throw DogecoinWalletEngineError.networkFailure("UTXO providers returned conflicting values for the same outpoint. Refusing to build Dogecoin transaction.")
            }
        }

        if !blockchairKeys.isEmpty, !blockcypherKeys.isEmpty, overlap.isEmpty {
            throw DogecoinWalletEngineError.networkFailure("UTXO providers disagree on spendable set (no overlap). Refusing to build Dogecoin transaction.")
        }

        let merged = Array(blockchairMap.values) + blockcypherMap.compactMap { key, value in
            blockchairMap[key] == nil ? value : nil
        }
        return sanitizeUTXOs(merged)
    }

    static func outpointKey(hash: String, index: Int) -> String {
        "\(hash.lowercased()):\(index)"
    }

    static func blockchairURL(path: String) -> URL? {
        URL(string: ChainBackendRegistry.DogecoinRuntimeEndpoints.blockchairBaseURL + path)
    }

    static func blockcypherURL(path: String) -> URL? {
        URL(string: ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL + path)
    }

    static func electrsURL(path: String) -> URL? {
        URL(string: ChainBackendRegistry.DogecoinRuntimeEndpoints.testnetElectrsBaseURL + path)
    }

    static func normalizedAddressCacheKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func cacheUTXOs(_ utxos: [DogecoinUTXO], for address: String) {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        utxoCacheByAddress[key] = CachedUTXOSet(utxos: utxos, updatedAt: Date())
    }

    static func cachedUTXOs(for address: String) -> [DogecoinUTXO]? {
        let key = normalizedAddressCacheKey(address)
        utxoCacheLock.lock()
        defer { utxoCacheLock.unlock() }
        guard let cached = utxoCacheByAddress[key] else { return nil }
        guard Date().timeIntervalSince(cached.updatedAt) <= utxoCacheTTLSeconds else {
            utxoCacheByAddress[key] = nil
            return nil
        }
        return cached.utxos
    }

    static func fetchBlockchairUTXOs(for address: String) throws -> [DogecoinUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let baseURL = blockchairURL(path: "/dashboards/address/\(encodedAddress)"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }
        components.queryItems = [URLQueryItem(name: "limit", value: "200")]
        guard let url = components.url else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(DogecoinAddressDashboardResponse.self, from: data)
        return payload.data.values.first?.utxo ?? []
    }

    static func fetchBlockCypherUTXOs(for address: String) throws -> [DogecoinUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let baseURL = blockcypherURL(path: "/addrs/\(encodedAddress)"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin address URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "unspentOnly", value: "true"),
            URLQueryItem(name: "includeScript", value: "true"),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components.url else {
            throw DogecoinWalletEngineError.networkFailure("Invalid BlockCypher request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherAddressResponse.self, from: data)
        let confirmed = payload.txrefs ?? []
        let pending = payload.unconfirmedTxrefs ?? []
        return (confirmed + pending).map {
            DogecoinUTXO(transactionHash: $0.txHash, index: $0.txOutputIndex, value: $0.value)
        }
    }

    static func fetchElectrsUTXOs(for address: String) throws -> [DogecoinUTXO] {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = electrsURL(path: "/address/\(encodedAddress)/utxo") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin testnet address URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode([ElectrsUTXO].self, from: data)
        return payload.map {
            DogecoinUTXO(transactionHash: $0.txid, index: $0.vout, value: UInt64(max(0, $0.value)))
        }
    }

    static func resolveNetworkFeeRateDOGEPerKB(feePriority: FeePriority) -> Double {
        let deterministicFallback: Double
        switch feePriority {
        case .economy:
            deterministicFallback = minRelayFeePerKB
        case .normal:
            deterministicFallback = max(minRelayFeePerKB, 0.015)
        case .priority:
            deterministicFallback = max(minRelayFeePerKB, 0.03)
        }
        if networkMode == .testnet {
            return adjustedFeeRateDOGEPerKB(baseRate: deterministicFallback, feePriority: feePriority)
        }
        let candidates = (try? fetchBlockCypherFeeRateCandidatesDOGEPerKB()) ?? []
        let baseRate = candidates.isEmpty ? deterministicFallback : candidates.sorted()[candidates.count / 2]
        let boundedRate = max(minRelayFeePerKB, min(baseRate, 10))
        return adjustedFeeRateDOGEPerKB(baseRate: boundedRate, feePriority: feePriority)
    }

    static func adjustedFeeRateDOGEPerKB(baseRate: Double, feePriority: FeePriority) -> Double {
        let multiplier: Double
        switch feePriority {
        case .economy:
            multiplier = 0.9
        case .normal:
            multiplier = 1.0
        case .priority:
            multiplier = 1.25
        }
        let adjusted = baseRate * multiplier
        return max(minRelayFeePerKB, min(adjusted, 25))
    }

    static func fetchBlockCypherFeeRateCandidatesDOGEPerKB() throws -> [Double] {
        guard let url = blockcypherURL(path: "") else {
            throw DogecoinWalletEngineError.networkFailure("Invalid Dogecoin network fee endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try performSynchronousRequest(
            request,
            timeout: networkTimeoutSeconds,
            retries: networkRetryCount
        )
        let payload = try JSONDecoder().decode(BlockCypherNetworkResponse.self, from: data)
        let candidates = [payload.lowFeePerKB, payload.mediumFeePerKB, payload.highFeePerKB]
            .compactMap { $0 }
            .map { $0 / koinuPerDOGE }
            .filter { $0 > 0 }

        guard !candidates.isEmpty else {
            throw DogecoinWalletEngineError.networkFailure("Fee-rate data was missing from BlockCypher.")
        }
        return candidates
    }

    static func performSynchronousRequest(
        _ request: URLRequest,
        timeout: TimeInterval = networkTimeoutSeconds,
        retries: Int = networkRetryCount
    ) throws -> Data {
        do {
            return try UTXOEngineSupport.performSynchronousRequest(
                request,
                timeout: timeout,
                retries: retries
            )
        } catch {
            throw DogecoinWalletEngineError.networkFailure(error.localizedDescription)
        }
    }
}
