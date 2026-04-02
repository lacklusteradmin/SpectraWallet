import Foundation
import BigInt
import WalletCore


extension EthereumWalletEngine {
private static func reliabilityNamespace(for chain: EVMChainContext) -> String {
    "evm.\(chain.displayName.lowercased().replacingOccurrences(of: " ", with: "-")).rpc"
}

static func fetchSendPreview(
    from fromAddress: String,
    to toAddress: String,
    amountETH: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumSendPreview {
    let parameters = try await fetchSendParameters(
        from: fromAddress,
        to: toAddress,
        valueWei: weiDecimal(fromETH: amountETH),
        data: nil,
        explicitNonce: explicitNonce,
        customFees: customFees,
        rpcEndpoint: rpcEndpoint,
        chain: chain
    )
    let estimatedNetworkFeeWei = Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei
    let accountSnapshot = try await fetchAccountSnapshot(
        for: fromAddress,
        rpcEndpoint: resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first,
        chain: chain
    )
    let spendableBalance = max(0, nativeBalanceETH(from: accountSnapshot) - eth(fromWei: estimatedNetworkFeeWei))
    return EthereumSendPreview(
        nonce: parameters.nonce,
        gasLimit: parameters.gasLimit,
        maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
        maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
        estimatedNetworkFeeETH: eth(fromWei: estimatedNetworkFeeWei),
        spendableBalance: spendableBalance,
        feeRateDescription: String(format: "Max %.2f gwei / Priority %.2f gwei", gwei(fromWei: parameters.maxFeePerGasWei), gwei(fromWei: parameters.maxPriorityFeePerGasWei)),
        estimatedTransactionBytes: nil,
        selectedInputCount: nil,
        usesChangeOutput: nil,
        maxSendable: spendableBalance
    )
}

static func send(
    seedPhrase: String,
    to toAddress: String,
    amountETH: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum,
    derivationAccount: UInt32 = 0
) async throws -> EthereumSendResult {
    let normalizedFromAddress = try derivedAddress(for: seedPhrase, account: derivationAccount, chain: chain)
    let normalizedToAddress = try validateAddress(toAddress)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
    guard chainID == chain.expectedChainID else {
        throw EthereumWalletEngineError.unsupportedNetwork
    }

    let parameters = try await fetchSendParameters(
        from: normalizedFromAddress,
        to: normalizedToAddress,
        valueWei: weiDecimal(fromETH: amountETH),
        data: nil,
        explicitNonce: explicitNonce,
        customFees: customFees,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let preview = EthereumSendPreview(
        nonce: parameters.nonce,
        gasLimit: parameters.gasLimit,
        maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
        maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
        estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei),
        spendableBalance: nil,
        feeRateDescription: String(format: "Max %.2f gwei / Priority %.2f gwei", gwei(fromWei: parameters.maxFeePerGasWei), gwei(fromWei: parameters.maxPriorityFeePerGasWei)),
        estimatedTransactionBytes: nil,
        selectedInputCount: nil,
        usesChangeOutput: nil,
        maxSendable: nil
    )

    let rawTransaction = try signTransaction(
        seedPhrase: seedPhrase,
        toAddress: normalizedToAddress,
        valueWei: weiDecimal(fromETH: amountETH),
        parameters: parameters,
        chainID: chainID,
        derivationAccount: derivationAccount,
        chain: chain
    )

    let transactionHash = try await broadcastRawTransaction(
        rawTransaction,
        preferredRPCEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
        transactionHash: transactionHash,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    return EthereumSendResult(
        fromAddress: normalizedFromAddress,
        transactionHash: transactionHash,
        rawTransactionHex: encodedSignedTransactionHex(from: rawTransaction),
        preview: preview,
        verificationStatus: verificationStatus
    )
}

static func send(
    privateKeyHex: String,
    to toAddress: String,
    amountETH: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumSendResult {
    let normalizedFromAddress = try derivedAddress(forPrivateKey: privateKeyHex, chain: chain)
    let normalizedToAddress = try validateAddress(toAddress)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
    guard chainID == chain.expectedChainID else {
        throw EthereumWalletEngineError.unsupportedNetwork
    }

    let parameters = try await fetchSendParameters(
        from: normalizedFromAddress,
        to: normalizedToAddress,
        valueWei: weiDecimal(fromETH: amountETH),
        data: nil,
        explicitNonce: explicitNonce,
        customFees: customFees,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let preview = EthereumSendPreview(
        nonce: parameters.nonce,
        gasLimit: parameters.gasLimit,
        maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
        maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
        estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei),
        spendableBalance: nil,
        feeRateDescription: String(format: "Max %.2f gwei / Priority %.2f gwei", gwei(fromWei: parameters.maxFeePerGasWei), gwei(fromWei: parameters.maxPriorityFeePerGasWei)),
        estimatedTransactionBytes: nil,
        selectedInputCount: nil,
        usesChangeOutput: nil,
        maxSendable: nil
    )

    let rawTransaction = try signTransaction(
        privateKeyHex: privateKeyHex,
        toAddress: normalizedToAddress,
        valueWei: weiDecimal(fromETH: amountETH),
        parameters: parameters,
        chainID: chainID,
        chain: chain
    )

    let transactionHash = try await broadcastRawTransaction(
        rawTransaction,
        preferredRPCEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
        transactionHash: transactionHash,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    return EthereumSendResult(
        fromAddress: normalizedFromAddress,
        transactionHash: transactionHash,
        rawTransactionHex: encodedSignedTransactionHex(from: rawTransaction),
        preview: preview,
        verificationStatus: verificationStatus
    )
}

static func fetchTokenSendPreview(
    from fromAddress: String,
    to toAddress: String,
    token: EthereumSupportedToken,
    amount: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumSendPreview {
    let callData = try transferCallData(
        to: toAddress,
        amount: amount,
        decimals: token.decimals
    )
    let parameters = try await fetchSendParameters(
        from: fromAddress,
        to: token.contractAddress,
        valueWei: 0,
        data: callData,
        explicitNonce: explicitNonce,
        customFees: customFees,
        rpcEndpoint: rpcEndpoint,
        chain: chain
    )
    let estimatedNetworkFeeWei = Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei
    let tokenBalance = try await plannedTokenBalances(
        for: fromAddress,
        tokenContracts: [token.contractAddress],
        rpcEndpoint: resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first,
        chain: chain
    ).first?.balance
    let spendableBalance = tokenBalance.map { NSDecimalNumber(decimal: $0).doubleValue }
    return EthereumSendPreview(
        nonce: parameters.nonce,
        gasLimit: parameters.gasLimit,
        maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
        maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
        estimatedNetworkFeeETH: eth(fromWei: estimatedNetworkFeeWei),
        spendableBalance: spendableBalance,
        feeRateDescription: String(format: "Max %.2f gwei / Priority %.2f gwei", gwei(fromWei: parameters.maxFeePerGasWei), gwei(fromWei: parameters.maxPriorityFeePerGasWei)),
        estimatedTransactionBytes: nil,
        selectedInputCount: nil,
        usesChangeOutput: nil,
        maxSendable: spendableBalance
    )
}

static func sendToken(
    seedPhrase: String,
    to toAddress: String,
    token: EthereumSupportedToken,
    amount: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum,
    derivationAccount: UInt32 = 0
) async throws -> EthereumSendResult {
    let normalizedFromAddress = try derivedAddress(for: seedPhrase, account: derivationAccount, chain: chain)
    let normalizedRecipientAddress = try validateAddress(toAddress)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
    guard chainID == chain.expectedChainID else {
        throw EthereumWalletEngineError.unsupportedNetwork
    }

    let callData = try transferCallData(
        to: normalizedRecipientAddress,
        amount: amount,
        decimals: token.decimals
    )
    let parameters = try await fetchSendParameters(
        from: normalizedFromAddress,
        to: token.contractAddress,
        valueWei: 0,
        data: callData,
        explicitNonce: explicitNonce,
        customFees: customFees,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let preview = EthereumSendPreview(
        nonce: parameters.nonce,
        gasLimit: parameters.gasLimit,
        maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
        maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
        estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei),
        spendableBalance: nil,
        feeRateDescription: String(format: "Max %.2f gwei / Priority %.2f gwei", gwei(fromWei: parameters.maxFeePerGasWei), gwei(fromWei: parameters.maxPriorityFeePerGasWei)),
        estimatedTransactionBytes: nil,
        selectedInputCount: nil,
        usesChangeOutput: nil,
        maxSendable: nil
    )

    let amountUnits = scaledUnitDecimal(fromAmount: amount, decimals: token.decimals)
    let rawTransaction = try signERC20Transaction(
        seedPhrase: seedPhrase,
        tokenContract: token.contractAddress,
        recipientAddress: normalizedRecipientAddress,
        amountUnits: amountUnits,
        parameters: parameters,
        chainID: chainID,
        derivationAccount: derivationAccount,
        chain: chain
    )

    let transactionHash = try await broadcastRawTransaction(
        rawTransaction,
        preferredRPCEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
        transactionHash: transactionHash,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    return EthereumSendResult(
        fromAddress: normalizedFromAddress,
        transactionHash: transactionHash,
        rawTransactionHex: encodedSignedTransactionHex(from: rawTransaction),
        preview: preview,
        verificationStatus: verificationStatus
    )
}

static func sendToken(
    privateKeyHex: String,
    to toAddress: String,
    token: EthereumSupportedToken,
    amount: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumSendResult {
    let normalizedFromAddress = try derivedAddress(forPrivateKey: privateKeyHex, chain: chain)
    let normalizedRecipientAddress = try validateAddress(toAddress)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    let chainID = try await fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
    guard chainID == chain.expectedChainID else {
        throw EthereumWalletEngineError.unsupportedNetwork
    }

    let callData = try transferCallData(
        to: normalizedRecipientAddress,
        amount: amount,
        decimals: token.decimals
    )
    let parameters = try await fetchSendParameters(
        from: normalizedFromAddress,
        to: token.contractAddress,
        valueWei: 0,
        data: callData,
        explicitNonce: explicitNonce,
        customFees: customFees,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let preview = EthereumSendPreview(
        nonce: parameters.nonce,
        gasLimit: parameters.gasLimit,
        maxFeePerGasGwei: gwei(fromWei: parameters.maxFeePerGasWei),
        maxPriorityFeePerGasGwei: gwei(fromWei: parameters.maxPriorityFeePerGasWei),
        estimatedNetworkFeeETH: eth(fromWei: Decimal(parameters.gasLimit) * parameters.maxFeePerGasWei),
        spendableBalance: nil,
        feeRateDescription: String(format: "Max %.2f gwei / Priority %.2f gwei", gwei(fromWei: parameters.maxFeePerGasWei), gwei(fromWei: parameters.maxPriorityFeePerGasWei)),
        estimatedTransactionBytes: nil,
        selectedInputCount: nil,
        usesChangeOutput: nil,
        maxSendable: nil
    )

    let amountUnits = scaledUnitDecimal(fromAmount: amount, decimals: token.decimals)
    let rawTransaction = try signERC20Transaction(
        privateKeyHex: privateKeyHex,
        tokenContract: token.contractAddress,
        recipientAddress: normalizedRecipientAddress,
        amountUnits: amountUnits,
        parameters: parameters,
        chainID: chainID,
        chain: chain
    )

    let transactionHash = try await broadcastRawTransaction(
        rawTransaction,
        preferredRPCEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    let verificationStatus = await verifyBroadcastedTransactionIfAvailable(
        transactionHash: transactionHash,
        rpcEndpoint: resolvedRPCEndpoint,
        chain: chain
    )
    return EthereumSendResult(
        fromAddress: normalizedFromAddress,
        transactionHash: transactionHash,
        rawTransactionHex: encodedSignedTransactionHex(from: rawTransaction),
        preview: preview,
        verificationStatus: verificationStatus
    )
}

static func rebroadcastSignedTransaction(
    rawTransactionHex: String,
    preferredRPCEndpoint: URL? = nil,
    chain: EVMChainContext
) async throws -> String {
    let normalized = rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = normalized.hasPrefix("0x") ? String(normalized.dropFirst(2)) : normalized
    guard let rawTransaction = Data(hexEncoded: hex) else {
        throw EthereumWalletEngineError.invalidResponse
    }
    return try await broadcastRawTransaction(
        rawTransaction,
        preferredRPCEndpoint: preferredRPCEndpoint,
        chain: chain
    )
}

static func verifyBroadcastedTransactionIfAvailable(
    transactionHash: String,
    rpcEndpoint: URL,
    chain: EVMChainContext
) async -> SendBroadcastVerificationStatus {
    let attempts = 3
    var lastError: Error?
    let candidateEndpoints = resolvedRPCEndpoints(fallbackFrom: rpcEndpoint, chain: chain)

    for attempt in 0 ..< attempts {
        for endpoint in candidateEndpoints {
            do {
                if let receipt = try await fetchTransactionReceipt(
                    transactionHash: transactionHash,
                    rpcEndpoint: endpoint,
                    chain: chain
                ) {
                    if receipt.status == "0x0" {
                        return .failed("Transaction was mined with failed execution status.")
                    }
                    return .verified
                }
            } catch {
                lastError = error
            }
        }

        if attempt < attempts - 1 {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    if let lastError {
        return .failed(lastError.localizedDescription)
    }
    return .deferred
}

static func sendTokenInBackground(
    seedPhrase: String,
    to toAddress: String,
    token: EthereumSupportedToken,
    amount: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum,
    derivationAccount: UInt32 = 0
) async throws -> EthereumSendResult {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let result = try await sendToken(
                        seedPhrase: seedPhrase,
                        to: toAddress,
                        token: token,
                        amount: amount,
                        explicitNonce: explicitNonce,
                        customFees: customFees,
                        rpcEndpoint: rpcEndpoint,
                        chain: chain,
                        derivationAccount: derivationAccount
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

static func sendInBackground(
    privateKeyHex: String,
    to toAddress: String,
    amountETH: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumSendResult {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let result = try await send(
                        privateKeyHex: privateKeyHex,
                        to: toAddress,
                        amountETH: amountETH,
                        explicitNonce: explicitNonce,
                        customFees: customFees,
                        rpcEndpoint: rpcEndpoint,
                        chain: chain
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

static func sendTokenInBackground(
    privateKeyHex: String,
    to toAddress: String,
    token: EthereumSupportedToken,
    amount: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumSendResult {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let result = try await sendToken(
                        privateKeyHex: privateKeyHex,
                        to: toAddress,
                        token: token,
                        amount: amount,
                        explicitNonce: explicitNonce,
                        customFees: customFees,
                        rpcEndpoint: rpcEndpoint,
                        chain: chain
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

static func fetchTransactionReceipt(
    transactionHash: String,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumTransactionReceipt? {
    let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedHash.hasPrefix("0x"), normalizedHash.count == 66 else {
        throw EthereumWalletEngineError.invalidResponse
    }

    let candidateRPCEndpoints = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain)
    var lastError: Error?
    var sawValidEmptyReceipt = false
    var requestID = 14
    for endpoint in candidateRPCEndpoints {
        let payload = EthereumJSONRPCRequest(
            id: requestID,
            method: "eth_getTransactionReceipt",
            params: [normalizedHash]
        )
        requestID += 1

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 20
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await fetchData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else {
                throw EthereumWalletEngineError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(EthereumTransactionReceiptJSONRPCResponse.self, from: data)
            if let rpcError = decoded.error {
                throw EthereumWalletEngineError.rpcFailure(rpcError.message)
            }

            guard let receiptPayload = decoded.result else {
                sawValidEmptyReceipt = true
                continue
            }

            let blockNumber = receiptPayload.blockNumber.flatMap { Int($0.dropFirst(2), radix: 16) }
            let gasUsed = try receiptPayload.gasUsed.map(decimal(fromHexQuantity:))
            let effectiveGasPriceWei = try receiptPayload.effectiveGasPrice.map(decimal(fromHexQuantity:))
            return EthereumTransactionReceipt(
                transactionHash: receiptPayload.transactionHash,
                blockNumber: blockNumber,
                status: receiptPayload.status,
                gasUsed: gasUsed,
                effectiveGasPriceWei: effectiveGasPriceWei
            )
        } catch {
            lastError = error
        }
    }

    if sawValidEmptyReceipt {
        return nil
    }
    throw lastError ?? EthereumWalletEngineError.invalidResponse
}

static func sendInBackground(
    seedPhrase: String,
    to toAddress: String,
    amountETH: Double,
    explicitNonce: Int? = nil,
    customFees: EthereumCustomFeeConfiguration? = nil,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum,
    derivationAccount: UInt32 = 0
) async throws -> EthereumSendResult {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            Task {
                do {
                    let result = try await send(
                        seedPhrase: seedPhrase,
                        to: toAddress,
                        amountETH: amountETH,
                        explicitNonce: explicitNonce,
                        customFees: customFees,
                        rpcEndpoint: rpcEndpoint,
                        chain: chain,
                        derivationAccount: derivationAccount
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

static func fetchRPCHealth(rpcEndpoint: URL? = nil, chain: EVMChainContext = .ethereum) async throws -> EthereumRPCHealthSnapshot {
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    async let chainID = fetchChainID(rpcEndpoint: resolvedRPCEndpoint)
    async let blockHex = performRPC(
        method: "eth_blockNumber",
        params: [String](),
        rpcEndpoint: resolvedRPCEndpoint,
        requestID: 31
    )

    let latestBlockHex = try await blockHex
    guard let latestBlockNumber = Int(latestBlockHex.dropFirst(2), radix: 16) else {
        throw EthereumWalletEngineError.invalidHexQuantity
    }

    return EthereumRPCHealthSnapshot(
        chainID: try await chainID,
        latestBlockNumber: latestBlockNumber
    )
}

static func fetchTransactionCount(
    for address: String,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> Int {
    let normalizedAddress = try validateAddress(address)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    let nonceHex = try await performRPC(
        method: "eth_getTransactionCount",
        params: [normalizedAddress, "latest"],
        rpcEndpoint: resolvedRPCEndpoint,
        requestID: 32
    )
    return Int(nonceHex.dropFirst(2), radix: 16) ?? 0
}

static func fetchTransactionNonce(
    for transactionHash: String,
    rpcEndpoint: URL? = nil,
    chain: EVMChainContext = .ethereum
) async throws -> Int {
    let normalizedHash = transactionHash.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedHash.hasPrefix("0x"), normalizedHash.count == 66 else {
        throw EthereumWalletEngineError.invalidResponse
    }
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    let payload: EthereumTransactionPayload = try await performRPCDecoded(
        method: "eth_getTransactionByHash",
        params: [normalizedHash],
        rpcEndpoint: resolvedRPCEndpoint,
        requestID: 33
    )
    guard let nonceHex = payload.nonce else {
        throw EthereumWalletEngineError.invalidResponse
    }
    return Int(nonceHex.dropFirst(2), radix: 16) ?? 0
}

static func broadcastRawTransaction(
    _ rawTransaction: Data,
    preferredRPCEndpoint: URL?,
    chain: EVMChainContext = .ethereum
) async throws -> String {
    let rawHex = "0x" + rawTransaction.map { String(format: "%02x", $0) }.joined()
    let fallbackTransactionHash = "0x" + Hash.keccak256(data: rawTransaction).map { String(format: "%02x", $0) }.joined()
    let rpcEndpoint = resolvedRPCEndpoints(preferred: preferredRPCEndpoint, chain: chain).first!
    let attempts = 2
    var lastError: Error?

    for _ in 0 ..< attempts {
        do {
            return try await performRPC(
                method: "eth_sendRawTransaction",
                params: [rawHex],
                rpcEndpoint: rpcEndpoint,
                requestID: 12
            )
        } catch {
            let disposition = classifySendBroadcastFailure(error.localizedDescription)
            if disposition == .alreadyBroadcast {
                return fallbackTransactionHash
            }
            lastError = error
            if disposition != .retryable {
                break
            }
        }
    }

    throw lastError ?? EthereumWalletEngineError.invalidResponse
}

private static func encodedSignedTransactionHex(from rawTransaction: Data) -> String {
    "0x" + rawTransaction.map { String(format: "%02x", $0) }.joined()
}

static func performRPC<Params: Encodable>(
    method: String,
    params: Params,
    rpcEndpoint: URL,
    requestID: Int
) async throws -> String {
    let inferred = inferredChainContext(for: rpcEndpoint)
    let endpoints = resolvedRPCEndpoints(fallbackFrom: rpcEndpoint, chain: inferred)
    var lastError: Error?
    var nextRequestID = requestID
    for endpoint in endpoints {
        do {
            let result = try await performRPCOnce(
                method: method,
                params: params,
                rpcEndpoint: endpoint,
                requestID: nextRequestID
            )
            ChainEndpointReliability.recordAttempt(
                namespace: reliabilityNamespace(for: inferredChainContext(for: endpoint)),
                endpoint: endpoint.absoluteString,
                success: true
            )
            return result
        } catch {
            lastError = error
            ChainEndpointReliability.recordAttempt(
                namespace: reliabilityNamespace(for: inferredChainContext(for: endpoint)),
                endpoint: endpoint.absoluteString,
                success: false
            )
            nextRequestID += 1
        }
    }
    throw lastError ?? EthereumWalletEngineError.invalidResponse
}

static func performRPCOnce<Params: Encodable>(
    method: String,
    params: Params,
    rpcEndpoint: URL,
    requestID: Int
) async throws -> String {
    let payload = EthereumJSONRPCRequest(
        id: requestID,
        method: method,
        params: params
    )
    var request = URLRequest(url: rpcEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 20
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode) else {
        throw EthereumWalletEngineError.invalidResponse
    }

    let decoded = try JSONDecoder().decode(EthereumJSONRPCResponse.self, from: data)
    if let rpcError = decoded.error {
        throw EthereumWalletEngineError.rpcFailure(rpcError.message)
    }

    guard let result = decoded.result else {
        throw EthereumWalletEngineError.invalidResponse
    }

    return result
}

static func performRPCDecoded<Params: Encodable, Result: Decodable>(
    method: String,
    params: Params,
    rpcEndpoint: URL,
    requestID: Int
) async throws -> Result {
    let inferred = inferredChainContext(for: rpcEndpoint)
    let endpoints = resolvedRPCEndpoints(fallbackFrom: rpcEndpoint, chain: inferred)
    var lastError: Error?
    var nextRequestID = requestID
    for endpoint in endpoints {
        do {
            let result: Result = try await performRPCDecodedOnce(
                method: method,
                params: params,
                rpcEndpoint: endpoint,
                requestID: nextRequestID
            )
            ChainEndpointReliability.recordAttempt(
                namespace: reliabilityNamespace(for: inferredChainContext(for: endpoint)),
                endpoint: endpoint.absoluteString,
                success: true
            )
            return result
        } catch {
            lastError = error
            ChainEndpointReliability.recordAttempt(
                namespace: reliabilityNamespace(for: inferredChainContext(for: endpoint)),
                endpoint: endpoint.absoluteString,
                success: false
            )
            nextRequestID += 1
        }
    }
    throw lastError ?? EthereumWalletEngineError.invalidResponse
}

static func performRPCDecodedOnce<Params: Encodable, Result: Decodable>(
    method: String,
    params: Params,
    rpcEndpoint: URL,
    requestID: Int
) async throws -> Result {
    let payload = EthereumJSONRPCRequest(
        id: requestID,
        method: method,
        params: params
    )
    var request = URLRequest(url: rpcEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 20
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await fetchData(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200 ..< 300).contains(httpResponse.statusCode) else {
        throw EthereumWalletEngineError.invalidResponse
    }

    let decoded = try JSONDecoder().decode(EthereumJSONRPCDecodedResponse<Result>.self, from: data)
    if let rpcError = decoded.error {
        throw EthereumWalletEngineError.rpcFailure(rpcError.message)
    }

    guard let result = decoded.result else {
        throw EthereumWalletEngineError.invalidResponse
    }

    return result
}

static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
}

static func fetchEIP1559FeeParameters(
    rpcEndpoint: URL,
    customFees: EthereumCustomFeeConfiguration?
) async throws -> (maxFeePerGasWei: Decimal, maxPriorityFeePerGasWei: Decimal) {
    if let customFees {
        let maxFeePerGasWei = Decimal(string: String(format: "%.9f", customFees.maxFeePerGasGwei))! * decimalPowerOfTen(9)
        let maxPriorityFeePerGasWei = Decimal(string: String(format: "%.9f", customFees.maxPriorityFeePerGasGwei))! * decimalPowerOfTen(9)
        guard maxFeePerGasWei > 0,
              maxPriorityFeePerGasWei > 0,
              maxFeePerGasWei >= maxPriorityFeePerGasWei else {
            throw EthereumWalletEngineError.rpcFailure("Invalid custom fee settings. Max fee must be greater than or equal to priority fee.")
        }
        return (maxFeePerGasWei, maxPriorityFeePerGasWei)
    }

    async let feeHistory: EthereumFeeHistoryResult = performRPCDecoded(
        method: "eth_feeHistory",
        params: EthereumFeeHistoryParameters(
            blockCountHex: "0x5",
            blockTag: "latest",
            rewardPercentiles: [25, 50, 75]
        ),
        rpcEndpoint: rpcEndpoint,
        requestID: 21
    )
    async let fallbackGasPriceHex = performRPC(
        method: "eth_gasPrice",
        params: [String](),
        rpcEndpoint: rpcEndpoint,
        requestID: 22
    )

    do {
        let history = try await feeHistory
        let fallbackGasPriceWei = try decimal(fromHexQuantity: try await fallbackGasPriceHex)
        guard let latestBaseFeeHex = history.baseFeePerGas.last else {
            return (fallbackGasPriceWei, min(fallbackGasPriceWei, Decimal(2_000_000_000)))
        }

        let latestBaseFeeWei = try decimal(fromHexQuantity: latestBaseFeeHex)
        let rewardCandidates = history.reward?.flatMap { $0 } ?? []
        let priorityCandidatesWei: [Decimal] = try rewardCandidates.map { try decimal(fromHexQuantity: $0) }
        let suggestedPriorityWei = priorityCandidatesWei.max() ?? Decimal(2_000_000_000)
        let boundedPriorityWei = min(max(suggestedPriorityWei, Decimal(1_000_000_000)), Decimal(5_000_000_000))
        let suggestedMaxFeeWei = (latestBaseFeeWei * 2) + boundedPriorityWei
        let maxFeeWei = max(suggestedMaxFeeWei, fallbackGasPriceWei)
        return (maxFeeWei, boundedPriorityWei)
    } catch {
        let fallbackGasPriceWei = try decimal(fromHexQuantity: try await fallbackGasPriceHex)
        return (fallbackGasPriceWei, min(fallbackGasPriceWei, Decimal(2_000_000_000)))
    }
}

static func fetchSendParameters(
    from fromAddress: String,
    to toAddress: String,
    valueWei: Decimal,
    data: String?,
    explicitNonce: Int?,
    customFees: EthereumCustomFeeConfiguration?,
    rpcEndpoint: URL?,
    chain: EVMChainContext = .ethereum
) async throws -> EthereumSendParameters {
    let normalizedFromAddress = try validateAddress(fromAddress)
    let normalizedToAddress = try validateAddress(toAddress)
    let resolvedRPCEndpoint = resolvedRPCEndpoints(preferred: rpcEndpoint, chain: chain).first!
    let valueHex = hexQuantity(from: valueWei)

    // Best-effort simulation only. Some RPC providers return opaque internal errors for
    // valid token transfers; we still want nonce/fee preview to proceed.
    _ = try? await performRPC(
        method: "eth_call",
        params: EthereumSimulationParameters(
            call: EthereumSimulationRequest(
                from: normalizedFromAddress,
                to: normalizedToAddress,
                value: valueHex,
                data: data
            ),
            blockTag: "latest"
        ),
        rpcEndpoint: resolvedRPCEndpoint,
        requestID: 9
    )

    async let nonceHex: String? = explicitNonce == nil
        ? performRPC(
            method: "eth_getTransactionCount",
            params: [normalizedFromAddress, "pending"],
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 10
        )
        : nil
    async let feeParameters = fetchEIP1559FeeParameters(
        rpcEndpoint: resolvedRPCEndpoint,
        customFees: customFees
    )

    let nonce: Int
    if let explicitNonce {
        nonce = explicitNonce
    } else {
        let resolvedNonceHex = try await nonceHex ?? "0x0"
        nonce = Int(resolvedNonceHex.dropFirst(2), radix: 16) ?? 0
    }
    let gasLimit: Int
    do {
        let gasLimitHex = try await performRPC(
            method: "eth_estimateGas",
            params: [
                EthereumEstimateGasRequest(
                    from: normalizedFromAddress,
                    to: normalizedToAddress,
                    value: valueHex,
                    data: data
                )
            ],
            rpcEndpoint: resolvedRPCEndpoint,
            requestID: 11
        )
        gasLimit = Int(gasLimitHex.dropFirst(2), radix: 16) ?? (data == nil ? 21_000 : 120_000)
    } catch {
        gasLimit = data == nil ? 21_000 : 120_000
    }
    let resolvedFeeParameters = try await feeParameters
    return EthereumSendParameters(
        nonce: nonce,
        gasLimit: gasLimit,
        maxFeePerGasWei: resolvedFeeParameters.maxFeePerGasWei,
        maxPriorityFeePerGasWei: resolvedFeeParameters.maxPriorityFeePerGasWei
    )
}

static func fetchChainID(rpcEndpoint: URL) async throws -> Int {
    let chainIDHex = try await performRPC(
        method: "eth_chainId",
        params: [String](),
        rpcEndpoint: rpcEndpoint,
        requestID: 13
    )
    guard let chainID = Int(chainIDHex.dropFirst(2), radix: 16) else {
        throw EthereumWalletEngineError.invalidHexQuantity
    }
    return chainID
}

static func balanceOfCallData(for address: String) -> String {
    let normalizedAddress = normalizeAddress(address)
    let addressBody = normalizedAddress.dropFirst(2)
    let paddedAddress = String(repeating: "0", count: max(0, 64 - addressBody.count)) + addressBody
    return "0x70a08231\(paddedAddress)"
}

private static func transferCallData(
    to address: String,
    amount: Double,
    decimals: Int
) throws -> String {
    let normalizedAddress = try validateAddress(address)
    let addressBody = normalizedAddress.dropFirst(2)
    let paddedAddress = String(repeating: "0", count: max(0, 64 - addressBody.count)) + addressBody
    let tokenUnits = scaledUnitDecimal(fromAmount: amount, decimals: decimals)
    let amountHex = hexString(from: tokenUnits)
    let paddedAmount = String(repeating: "0", count: max(0, 64 - amountHex.count)) + amountHex
    return "0xa9059cbb\(paddedAddress)\(paddedAmount)"
}

private static func transferCallData(
    to address: String,
    amountUnits: Decimal
) throws -> String {
    let normalizedAddress = try validateAddress(address)
    let addressBody = normalizedAddress.dropFirst(2)
    let paddedAddress = String(repeating: "0", count: max(0, 64 - addressBody.count)) + addressBody
    let amountHex = hexString(from: amountUnits)
    let paddedAmount = String(repeating: "0", count: max(0, 64 - amountHex.count)) + amountHex
    return "0xa9059cbb\(paddedAddress)\(paddedAmount)"
}

static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
    guard exponent > 0 else { return 1 }
    var result = Decimal(1)
    for _ in 0 ..< exponent {
        result *= 10
    }
    return result
}

static func weiDecimal(fromETH amountETH: Double) -> Decimal {
    scaledUnitDecimal(fromAmount: amountETH, decimals: 18)
}

static func scaledUnitDecimal(fromAmount amount: Double, decimals: Int) -> Decimal {
    let normalizedAmount = max(amount, 0)
    guard normalizedAmount.isFinite else { return 0 }
    let base = NSDecimalNumber(decimal: decimalPowerOfTen(max(decimals, 0)))
    let scaled = NSDecimalNumber(value: normalizedAmount).multiplying(by: base)
    return scaled.rounding(accordingToBehavior: nil).decimalValue
}

static func gwei(fromWei wei: Decimal) -> Double {
    let gweiValue = wei / decimalPowerOfTen(9)
    return NSDecimalNumber(decimal: gweiValue).doubleValue
}

static func eth(fromWei wei: Decimal) -> Double {
    let ethValue = wei / decimalPowerOfTen(18)
    return NSDecimalNumber(decimal: ethValue).doubleValue
}

static func hexQuantity(from decimal: Decimal) -> String {
    "0x" + hexString(from: decimal)
}

static func hexString(from decimal: Decimal) -> String {
    guard let uintValue = try? bigUInt(from: decimal) else { return "0" }
    return uintValue == 0 ? "0" : String(uintValue, radix: 16)
}

static func wholeNumberString(from decimal: Decimal) -> String {
    var sourceValue = decimal
    var wholeValue = Decimal()
    NSDecimalRound(&wholeValue, &sourceValue, 0, .down)
    return NSDecimalNumber(decimal: wholeValue).stringValue
}

static func bigUInt(from decimal: Decimal) throws -> BigUInt {
    let wholeString = wholeNumberString(from: decimal)
    guard let value = BigUInt(wholeString) else {
        throw EthereumWalletEngineError.invalidHexQuantity
    }
    return value
}

static func data(fromHexString hexString: String) throws -> Data {
    let normalized = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
    guard normalized.count.isMultiple(of: 2) else {
        throw EthereumWalletEngineError.invalidHexQuantity
    }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(normalized.count / 2)
    var index = normalized.startIndex
    while index < normalized.endIndex {
        let nextIndex = normalized.index(index, offsetBy: 2)
        let byteString = normalized[index ..< nextIndex]
        guard let byte = UInt8(byteString, radix: 16) else {
            throw EthereumWalletEngineError.invalidHexQuantity
        }
        bytes.append(byte)
        index = nextIndex
    }
    return Data(bytes)
}

static func decimal(fromHexQuantity hexQuantity: String) throws -> Decimal {
    let normalizedQuantity = hexQuantity.lowercased()
    guard normalizedQuantity.hasPrefix("0x") else {
        throw EthereumWalletEngineError.invalidHexQuantity
    }
    let body = String(normalizedQuantity.dropFirst(2))
    guard !body.isEmpty else { return .zero }
    guard let value = BigUInt(body, radix: 16),
          let decimalValue = Decimal(string: value.description) else {
        throw EthereumWalletEngineError.invalidHexQuantity
    }
    return decimalValue
}

static func signTransaction(
    seedPhrase: String,
    toAddress: String,
    valueWei: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    derivationAccount: UInt32,
    chain: EVMChainContext
) throws -> Data {
    let walletCoreSigned = try walletCoreSignNativeTransaction(
        seedPhrase: seedPhrase,
        toAddress: toAddress,
        valueWei: valueWei,
        parameters: parameters,
        chainID: chainID,
        derivationAccount: derivationAccount,
        chain: chain
    )
    return walletCoreSigned
}

static func signTransaction(
    privateKeyHex: String,
    toAddress: String,
    valueWei: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    chain: EVMChainContext
) throws -> Data {
    try walletCoreSignNativeTransaction(
        privateKeyHex: privateKeyHex,
        toAddress: toAddress,
        valueWei: valueWei,
        parameters: parameters,
        chainID: chainID,
        chain: chain
    )
}

static func signERC20Transaction(
    seedPhrase: String,
    tokenContract: String,
    recipientAddress: String,
    amountUnits: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    derivationAccount: UInt32,
    chain: EVMChainContext
) throws -> Data {
    let walletCoreSigned = try walletCoreSignERC20Transaction(
        seedPhrase: seedPhrase,
        tokenContract: tokenContract,
        recipientAddress: recipientAddress,
        amountUnits: amountUnits,
        parameters: parameters,
        chainID: chainID,
        derivationAccount: derivationAccount,
        chain: chain
    )
    return walletCoreSigned
}

static func signERC20Transaction(
    privateKeyHex: String,
    tokenContract: String,
    recipientAddress: String,
    amountUnits: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    chain: EVMChainContext
) throws -> Data {
    try walletCoreSignERC20Transaction(
        privateKeyHex: privateKeyHex,
        tokenContract: tokenContract,
        recipientAddress: recipientAddress,
        amountUnits: amountUnits,
        parameters: parameters,
        chainID: chainID,
        chain: chain
    )
}

static func serializedUInt256Data(from value: Int) -> Data {
    serializedUInt256Data(from: Decimal(value))
}

static func serializedUInt256Data(from value: Decimal) -> Data {
    guard let uintValue = try? bigUInt(from: value) else { return Data([0]) }
    let serialized = uintValue.serialize()
    return serialized.isEmpty ? Data([0]) : serialized
}

static func walletCoreDerivedAddress(
    seedPhrase: String,
    account: UInt32,
    chain: EVMChainContext,
    derivationPath: String?
) throws -> String {
    let material = try walletCoreMaterial(
        seedPhrase: seedPhrase,
        account: account,
        chain: chain,
        derivationPath: derivationPath
    )
    return normalizeAddress(material.address)
}

static func walletCoreSignNativeTransaction(
    seedPhrase: String,
    toAddress: String,
    valueWei: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    derivationAccount: UInt32,
    chain: EVMChainContext
) throws -> Data {
    let material = try walletCoreMaterial(
        seedPhrase: seedPhrase,
        account: derivationAccount,
        chain: chain,
        derivationPath: nil
    )
    return try walletCoreSignNativeTransaction(
        privateKeyData: material.privateKeyData,
        toAddress: toAddress,
        valueWei: valueWei,
        parameters: parameters,
        chainID: chainID
    )
}

static func walletCoreSignNativeTransaction(
    privateKeyHex: String,
    toAddress: String,
    valueWei: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    chain: EVMChainContext
) throws -> Data {
    let material = try walletCoreMaterial(privateKeyHex: privateKeyHex, chain: chain)
    return try walletCoreSignNativeTransaction(
        privateKeyData: material.privateKeyData,
        toAddress: toAddress,
        valueWei: valueWei,
        parameters: parameters,
        chainID: chainID
    )
}

static func walletCoreSignNativeTransaction(
    privateKeyData: Data,
    toAddress: String,
    valueWei: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int
) throws -> Data {
    var input = EthereumSigningInput()
    input.chainID = serializedUInt256Data(from: chainID)
    input.nonce = serializedUInt256Data(from: parameters.nonce)
    input.txMode = .enveloped
    input.gasLimit = serializedUInt256Data(from: parameters.gasLimit)
    input.maxInclusionFeePerGas = serializedUInt256Data(from: parameters.maxPriorityFeePerGasWei)
    input.maxFeePerGas = serializedUInt256Data(from: parameters.maxFeePerGasWei)
    input.toAddress = toAddress
    input.privateKey = privateKeyData

    var tx = EthereumTransaction()
    var transfer = EthereumTransaction.Transfer()
    transfer.amount = serializedUInt256Data(from: valueWei)
    tx.transfer = transfer
    input.transaction = tx

    let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
    guard output.errorMessage.isEmpty, !output.encoded.isEmpty else {
        throw EthereumWalletEngineError.rpcFailure(
            output.errorMessage.isEmpty ? "Wallet Core failed to sign Ethereum transaction." : output.errorMessage
        )
    }
    return output.encoded
}

static func walletCoreSignERC20Transaction(
    seedPhrase: String,
    tokenContract: String,
    recipientAddress: String,
    amountUnits: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    derivationAccount: UInt32,
    chain: EVMChainContext
) throws -> Data {
    let material = try walletCoreMaterial(
        seedPhrase: seedPhrase,
        account: derivationAccount,
        chain: chain,
        derivationPath: nil
    )
    return try walletCoreSignERC20Transaction(
        privateKeyData: material.privateKeyData,
        tokenContract: tokenContract,
        recipientAddress: recipientAddress,
        amountUnits: amountUnits,
        parameters: parameters,
        chainID: chainID
    )
}

static func walletCoreSignERC20Transaction(
    privateKeyHex: String,
    tokenContract: String,
    recipientAddress: String,
    amountUnits: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int,
    chain: EVMChainContext
) throws -> Data {
    let material = try walletCoreMaterial(privateKeyHex: privateKeyHex, chain: chain)
    return try walletCoreSignERC20Transaction(
        privateKeyData: material.privateKeyData,
        tokenContract: tokenContract,
        recipientAddress: recipientAddress,
        amountUnits: amountUnits,
        parameters: parameters,
        chainID: chainID
    )
}

static func walletCoreSignERC20Transaction(
    privateKeyData: Data,
    tokenContract: String,
    recipientAddress: String,
    amountUnits: Decimal,
    parameters: EthereumSendParameters,
    chainID: Int
) throws -> Data {
    var input = EthereumSigningInput()
    input.chainID = serializedUInt256Data(from: chainID)
    input.nonce = serializedUInt256Data(from: parameters.nonce)
    input.txMode = .enveloped
    input.gasLimit = serializedUInt256Data(from: parameters.gasLimit)
    input.maxInclusionFeePerGas = serializedUInt256Data(from: parameters.maxPriorityFeePerGasWei)
    input.maxFeePerGas = serializedUInt256Data(from: parameters.maxFeePerGasWei)
    input.toAddress = tokenContract
    input.privateKey = privateKeyData

    var tx = EthereumTransaction()
    var transfer = EthereumTransaction.ERC20Transfer()
    transfer.to = recipientAddress
    transfer.amount = serializedUInt256Data(from: amountUnits)
    tx.erc20Transfer = transfer
    input.transaction = tx

    let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
    guard output.errorMessage.isEmpty, !output.encoded.isEmpty else {
        throw EthereumWalletEngineError.rpcFailure(
            output.errorMessage.isEmpty ? "Wallet Core failed to sign ERC-20 transaction." : output.errorMessage
        )
    }
    return output.encoded
}

static func walletCoreMaterial(
    seedPhrase: String,
    account: UInt32,
    chain: EVMChainContext,
    derivationPath: String?
) throws -> WalletCoreDerivationMaterial {
    let resolvedPath = derivationPath ?? chain.derivationPath(account: account)
    return try WalletCoreDerivation.deriveMaterial(
        seedPhrase: seedPhrase,
        coin: .ethereum,
        derivationPath: resolvedPath
    )
}

static func walletCoreMaterial(
    privateKeyHex: String,
    chain _: EVMChainContext
) throws -> WalletCoreDerivationMaterial {
    try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .ethereum)
}
}
