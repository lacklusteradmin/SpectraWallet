import Foundation

extension WalletSendLayer {

    // MARK: - Rust UTXO fee preview decoder

    /// Fetch a UTXO capacity preview from Rust and decode into `BitcoinSendPreview`.
    /// `feeRateSvb = 0` lets Rust fetch a live rate from Blockbook (blocks=3, normal priority).
    private static func decodedUTXOFeePreview(
        chainId: UInt32,
        address: String,
        satPerCoin: Double,
        feeRateSvb: UInt64 = 0
    ) async throws -> BitcoinSendPreview {
        let json = try await WalletServiceBridge.shared.fetchUTXOFeePreviewJSON(
            chainId: chainId,
            address: address,
            feeRateSvb: feeRateSvb
        )
        let rate = UInt64(WalletSendLayer.rustField("fee_rate_svb", from: json)) ?? 1
        let feeSat = UInt64(WalletSendLayer.rustField("estimated_fee_sat", from: json)) ?? 0
        let txBytes = Int(WalletSendLayer.rustField("estimated_tx_bytes", from: json)) ?? 0
        let inputCount = Int(WalletSendLayer.rustField("selected_input_count", from: json)) ?? 0
        let spendableSat = UInt64(WalletSendLayer.rustField("spendable_balance_sat", from: json)) ?? 0
        let maxSendableSat = UInt64(WalletSendLayer.rustField("max_sendable_sat", from: json)) ?? 0
        guard spendableSat > 0 else {
            throw NSError(domain: "UTXOFeePreview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Insufficient funds"])
        }
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: rate,
            estimatedNetworkFeeBTC: Double(feeSat) / satPerCoin,
            feeRateDescription: "\(rate) sat/vB",
            spendableBalance: Double(spendableSat) / satPerCoin,
            estimatedTransactionBytes: txBytes,
            selectedInputCount: inputCount,
            usesChangeOutput: nil,
            maxSendable: Double(maxSendableSat) / satPerCoin
        )
    }

    // MARK: - EVM send preview decoder

    /// Decode the JSON from `fetchEVMSendPreviewJSON` into `EthereumSendPreview`.
    /// Applies explicit nonce and custom fee overrides on top of the Rust-derived values.
    private static func decodeEVMSendPreview(
        json: String,
        explicitNonce: Int?,
        customFees: EthereumCustomFeeConfiguration?
    ) -> EthereumSendPreview? {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let nonce         = explicitNonce ?? (obj["nonce"] as? Int ?? 0)
        let gasLimit      = obj["gas_limit"] as? Int ?? 21_000
        let liveFeeGwei   = obj["max_fee_per_gas_gwei"] as? Double ?? 0
        let livePrioGwei  = obj["max_priority_fee_per_gas_gwei"] as? Double ?? 0
        let maxFeeGwei    = customFees?.maxFeePerGasGwei    ?? liveFeeGwei
        let prioFeeGwei   = customFees?.maxPriorityFeePerGasGwei ?? livePrioGwei

        // Re-compute estimated fee if custom fees were supplied.
        let feeETH: Double
        if customFees != nil {
            let feeWei = Double(gasLimit) * maxFeeGwei * 1_000_000_000
            feeETH = feeWei / 1_000_000_000_000_000_000
        } else {
            feeETH = obj["estimated_fee_eth"] as? Double ?? 0
        }
        let spendableETH  = obj["spendable_eth"] as? Double
        let feeDesc       = customFees != nil
            ? "Max \(String(format: "%.2f", maxFeeGwei)) gwei / Priority \(String(format: "%.2f", prioFeeGwei)) gwei (custom)"
            : obj["fee_rate_description"] as? String

        return EthereumSendPreview(
            nonce: nonce,
            gasLimit: gasLimit,
            maxFeePerGasGwei: maxFeeGwei,
            maxPriorityFeePerGasGwei: prioFeeGwei,
            estimatedNetworkFeeETH: feeETH,
            spendableBalance: spendableETH,
            feeRateDescription: feeDesc,
            estimatedTransactionBytes: nil,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: spendableETH
        )
    }

    // MARK: - Bitcoin HD send preview decoder

    /// Build a `BitcoinSendPreview` from an xpub-balance JSON + fee-estimate JSON.
    /// Uses a fixed 250 vB estimate (1-in-2-out native SegWit P2WPKH).
    private static func decodeBitcoinHDSendPreview(
        balanceJSON: String,
        feeJSON: String
    ) -> BitcoinSendPreview? {
        guard let balData = balanceJSON.data(using: .utf8),
              let balObj  = try? JSONSerialization.jsonObject(with: balData) as? [String: Any] else {
            return nil
        }
        let confirmedSats = (balObj["confirmed_sats"] as? UInt64) ?? 0
        let feeRateRaw    = WalletSendLayer.rustField("sats_per_vbyte", from: feeJSON)
        let feeRateCeil   = max(1, (Double(feeRateRaw) ?? 1.0).rounded(.up))
        let rateU64       = UInt64(feeRateCeil)
        let estimatedBytes: UInt64 = 250
        let feeSat        = rateU64 * estimatedBytes
        let spendableSat  = confirmedSats > feeSat ? confirmedSats - feeSat : 0
        let satPerBTC     = 100_000_000.0
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: rateU64,
            estimatedNetworkFeeBTC: Double(feeSat) / satPerBTC,
            feeRateDescription: "\(rateU64) sat/vB",
            spendableBalance: Double(confirmedSats) / satPerBTC,
            estimatedTransactionBytes: Int(estimatedBytes),
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: Double(spendableSat) / satPerBTC
        )
    }

    // MARK: - Tron send preview decoder

    /// Decode the JSON from `fetchTronSendPreviewJSON` into `TronSendPreview`.
    private static func decodeTronSendPreview(json: String) -> TronSendPreview? {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let feeTRX        = obj["estimated_fee_trx"]  as? Double ?? 0
        let feeLimitSun   = (obj["fee_limit_sun"] as? Int64) ?? Int64(obj["fee_limit_sun"] as? Int ?? 0)
        let spendable     = obj["spendable_balance"]  as? Double ?? 0
        let maxSendable   = obj["max_sendable"]       as? Double ?? spendable
        let feeDesc       = obj["fee_rate_description"] as? String
        return TronSendPreview(
            estimatedNetworkFeeTRX: feeTRX,
            feeLimitSun: feeLimitSun,
            simulationUsed: false,
            spendableBalance: spendable,
            feeRateDescription: feeDesc,
            estimatedTransactionBytes: nil,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: maxSendable
        )
    }

    static func refreshEthereumSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              store.isEVMChain(selectedSendCoin.chainName),
              let fromAddress = store.resolvedEVMAddress(for: wallet, chainName: selectedSendCoin.chainName),
              let amount = Double(store.sendAmount),
              ((selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC" || selectedSendCoin.symbol == "BNB") ? amount >= 0 : amount > 0) else {
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
            return
        }
        if let customEthereumNonceValidationError = store.customEthereumNonceValidationError {
            store.sendError = customEthereumNonceValidationError
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
            return
        }

        let trimmedDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewDestination: String
        if trimmedDestination.isEmpty {
            previewDestination = fromAddress
        } else {
            if AddressValidation.isValidEthereumAddress(trimmedDestination) {
                previewDestination = normalizeEVMAddress(trimmedDestination)
            } else if selectedSendCoin.chainName == "Ethereum", store.isENSNameCandidate(trimmedDestination) {
                do {
                    guard let resolved = try await WalletServiceBridge.shared.resolveENSName(trimmedDestination) else {
                        store.ethereumSendPreview = nil
                        store.isPreparingEthereumSend = false
                        return
                    }
                    previewDestination = resolved
                    store.sendDestinationInfoMessage = "Resolved ENS \(trimmedDestination) to \(resolved)."
                } catch {
                    store.ethereumSendPreview = nil
                    store.isPreparingEthereumSend = false
                    return
                }
            } else {
                store.ethereumSendPreview = nil
                store.isPreparingEthereumSend = false
                return
            }
        }

        guard !store.isPreparingEthereumSend else {
            store.pendingEthereumSendPreviewRefresh = true
            return
        }
        store.isPreparingEthereumSend = true
        defer {
            store.isPreparingEthereumSend = false
            if store.pendingEthereumSendPreviewRefresh {
                store.pendingEthereumSendPreviewRefresh = false
                Task { @MainActor in
                    await refreshEthereumSendPreview(using: store)
                }
            }
        }

        guard let chainId = SpectraChainID.id(for: selectedSendCoin.chainName) else {
            store.ethereumSendPreview = nil
            store.isPreparingEthereumSend = false
            return
        }

        do {
            let valueWei: String
            let toAddress: String
            let dataHex: String

            if selectedSendCoin.symbol == "ETH" || selectedSendCoin.symbol == "ETC"
                || selectedSendCoin.symbol == "BNB" || selectedSendCoin.symbol == "AVAX"
                || selectedSendCoin.symbol == "ARB" || selectedSendCoin.symbol == "OP"
                || selectedSendCoin.symbol == "BASE" {
                // Native EVM send
                let amountWei = NSDecimalNumber(decimal: Decimal(amount) * pow(Decimal(10), 18))
                valueWei = amountWei.stringValue
                toAddress = previewDestination
                dataHex = "0x"
            } else if let token = store.supportedEVMToken(for: selectedSendCoin) {
                // ERC-20 send — build minimal transfer calldata for gas estimation
                valueWei = "0"
                toAddress = token.contractAddress
                let toParam = String(repeating: "0", count: 24)
                    + String(previewDestination.dropFirst(2)).lowercased()
                let dataStub = String(repeating: "0", count: 64)
                dataHex = "0xa9059cbb\(toParam)\(dataStub)"
            } else {
                store.ethereumSendPreview = nil
                store.isPreparingEthereumSend = false
                return
            }

            let previewJSON = try await WalletServiceBridge.shared.fetchEVMSendPreviewJSON(
                chainId: chainId,
                from: fromAddress,
                to: toAddress,
                valueWei: valueWei,
                dataHex: dataHex
            )
            store.ethereumSendPreview = decodeEVMSendPreview(
                json: previewJSON,
                explicitNonce: store.explicitEthereumNonce(),
                customFees: store.customEthereumFeeConfiguration()
            )
            if store.ethereumSendPreview != nil {
                store.sendError = nil
                store.clearSendVerificationNotice()
            }
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.ethereumSendPreview = nil
            store.sendError = "Unable to estimate EVM fee right now. Check RPC and retry."
        }
    }

    static func refreshDogecoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Dogecoin",
              selectedSendCoin.symbol == "DOGE",
              let amount = store.parseDogecoinAmountInput(store.sendAmount),
              amount > 0 else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }

        let trimmedDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty, !store.isValidDogecoinAddressForPolicy(trimmedDestination, networkMode: store.dogecoinNetworkMode(for: wallet)) {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }

        guard let seedPhrase = store.storedSeedPhrase(for: wallet.id) else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }

        guard !store.isPreparingDogecoinSend else {
            store.pendingDogecoinSendPreviewRefresh = true
            return
        }
        store.isPreparingDogecoinSend = true
        defer {
            store.isPreparingDogecoinSend = false
            if store.pendingDogecoinSendPreviewRefresh {
                store.pendingDogecoinSendPreviewRefresh = false
                Task { @MainActor in
                    await refreshDogecoinSendPreview(using: store)
                }
            }
        }

        guard let address = store.resolvedDogecoinAddress(for: wallet) else {
            store.dogecoinSendPreview = nil
            store.isPreparingDogecoinSend = false
            return
        }

        do {
            let json = try await WalletServiceBridge.shared.fetchUTXOFeePreviewJSON(
                chainId: SpectraChainID.dogecoin,
                address: address,
                feeRateSvb: 0
            )
            let rate       = UInt64(WalletSendLayer.rustField("fee_rate_svb", from: json)) ?? 1
            let feeSat     = UInt64(WalletSendLayer.rustField("estimated_fee_sat", from: json)) ?? 0
            let txBytes    = Int(WalletSendLayer.rustField("estimated_tx_bytes", from: json)) ?? 0
            let inputCount = Int(WalletSendLayer.rustField("selected_input_count", from: json)) ?? 0
            let spendSat   = UInt64(WalletSendLayer.rustField("spendable_balance_sat", from: json)) ?? 0
            let maxSat     = UInt64(WalletSendLayer.rustField("max_sendable_sat", from: json)) ?? 0
            let satPerCoin: Double = 100_000_000
            guard spendSat > 0 else {
                store.dogecoinSendPreview = nil
                store.sendError = "Insufficient DOGE funds."
                return
            }
            let feeDOGE = Double(feeSat) / satPerCoin
            store.dogecoinSendPreview = DogecoinSendPreview(
                spendableBalanceDOGE: Double(spendSat) / satPerCoin,
                requestedAmountDOGE:  amount,
                estimatedNetworkFeeDOGE: feeDOGE,
                estimatedFeeRateDOGEPerKB: Double(rate) * 1000 / satPerCoin,
                estimatedTransactionBytes: txBytes,
                selectedInputCount: inputCount,
                usesChangeOutput: spendSat > UInt64(amount * satPerCoin) + feeSat,
                feePriority: store.dogecoinFeePriority,
                maxSendableDOGE: Double(maxSat) / satPerCoin,
                spendableBalance: Double(spendSat) / satPerCoin,
                feeRateDescription: "\(rate) sat/vB",
                maxSendable: Double(maxSat) / satPerCoin
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.dogecoinSendPreview = nil
            store.sendError = "Unable to estimate DOGE fee right now. Check provider health and retry."
        }
    }

    static func refreshBitcoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Bitcoin",
              selectedSendCoin.symbol == "BTC",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.bitcoinSendPreview = nil
            return
        }

        guard store.storedSeedPhrase(for: wallet.id) != nil else {
            store.bitcoinSendPreview = nil
            return
        }

        do {
            if let xpub = wallet.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines),
               !xpub.isEmpty {
                // HD wallet — fetch UTXOs across all derived addresses via xpub scan.
                async let balanceJSONTask = WalletServiceBridge.shared.fetchBitcoinXpubBalanceJSON(xpub: xpub)
                async let feeJSONTask    = WalletServiceBridge.shared.fetchFeeEstimateJSON(chainId: SpectraChainID.bitcoin)
                let (balanceJSON, feeJSON) = try await (balanceJSONTask, feeJSONTask)
                store.bitcoinSendPreview = decodeBitcoinHDSendPreview(
                    balanceJSON: balanceJSON,
                    feeJSON: feeJSON
                )
            } else if let address = store.resolvedBitcoinAddress(for: wallet) {
                // Single-address watch-only wallet.
                store.bitcoinSendPreview = try await decodedUTXOFeePreview(
                    chainId: SpectraChainID.bitcoin,
                    address: address,
                    satPerCoin: 100_000_000
                )
            } else {
                store.bitcoinSendPreview = nil
            }
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.bitcoinSendPreview = nil
            store.sendError = "Unable to estimate BTC fee right now. Check provider health and retry."
        }
    }

    static func refreshBitcoinCashSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Bitcoin Cash",
              selectedSendCoin.symbol == "BCH",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.bitcoinCashSendPreview = nil
            return
        }

        guard store.storedSeedPhrase(for: wallet.id) != nil,
              let sourceAddress = store.resolvedBitcoinCashAddress(for: wallet) else {
            store.bitcoinCashSendPreview = nil
            return
        }
        do {
            store.bitcoinCashSendPreview = try await decodedUTXOFeePreview(
                chainId: SpectraChainID.bitcoinCash,
                address: sourceAddress,
                satPerCoin: 100_000_000
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.bitcoinCashSendPreview = nil
            store.sendError = "Unable to estimate BCH fee right now. Check provider health and retry."
        }
    }

    static func refreshBitcoinSVSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Bitcoin SV",
              selectedSendCoin.symbol == "BSV",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.bitcoinSVSendPreview = nil
            return
        }

        guard store.storedSeedPhrase(for: wallet.id) != nil,
              let sourceAddress = store.resolvedBitcoinSVAddress(for: wallet) else {
            store.bitcoinSVSendPreview = nil
            return
        }
        do {
            store.bitcoinSVSendPreview = try await decodedUTXOFeePreview(
                chainId: SpectraChainID.bitcoinSv,
                address: sourceAddress,
                satPerCoin: 100_000_000
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.bitcoinSVSendPreview = nil
            store.sendError = "Unable to estimate BSV fee right now. Check provider health and retry."
        }
    }

    static func refreshLitecoinSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Litecoin",
              selectedSendCoin.symbol == "LTC",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.litecoinSendPreview = nil
            return
        }

        guard store.storedSeedPhrase(for: wallet.id) != nil,
              let sourceAddress = store.resolvedLitecoinAddress(for: wallet) else {
            store.litecoinSendPreview = nil
            return
        }
        do {
            store.litecoinSendPreview = try await decodedUTXOFeePreview(
                chainId: SpectraChainID.litecoin,
                address: sourceAddress,
                satPerCoin: 100_000_000
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.litecoinSendPreview = nil
            store.sendError = "Unable to estimate LTC fee right now. Check provider health and retry."
        }
    }

    static func refreshTronSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Tron",
              (selectedSendCoin.symbol == "TRX" || selectedSendCoin.symbol == "USDT"),
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.tronSendPreview = nil
            store.isPreparingTronSend = false
            return
        }

        guard let sourceAddress = store.resolvedTronAddress(for: wallet) else {
            store.tronSendPreview = nil
            store.isPreparingTronSend = false
            return
        }

        guard !store.isPreparingTronSend else { return }
        store.isPreparingTronSend = true
        defer { store.isPreparingTronSend = false }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        do {
            let previewJSON = try await WalletServiceBridge.shared.fetchTronSendPreviewJSON(
                address: sourceAddress,
                symbol: selectedSendCoin.symbol,
                contractAddress: selectedSendCoin.contractAddress ?? ""
            )
            store.tronSendPreview = decodeTronSendPreview(json: previewJSON)
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) {
                return
            }
            store.tronSendPreview = nil
            store.sendError = "Unable to estimate Tron fee right now. Check provider health and retry."
        }
    }

    // MARK: - Rust fee preview helpers

    private static func rustFeeAndBalance(chainId: UInt32, address: String) async throws -> (feeJSON: String, balanceJSON: String) {
        async let fee = WalletServiceBridge.shared.fetchFeeEstimateJSON(chainId: chainId)
        async let balance = WalletServiceBridge.shared.fetchBalanceJSON(chainId: chainId, address: address)
        return try await (fee, balance)
    }

    private static func rustFeeDisplay(from feeJSON: String) -> Double {
        Double(WalletSendLayer.rustField("native_fee_display", from: feeJSON)) ?? 0
    }

    private static func rustFeeRaw(from feeJSON: String) -> String {
        WalletSendLayer.rustField("native_fee_raw", from: feeJSON)
    }

    static func refreshSolanaSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              store.isSupportedSolanaSendCoin(selectedSendCoin),
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.solanaSendPreview = nil
            store.isPreparingSolanaSend = false
            return
        }

        guard let sourceAddress = store.resolvedSolanaAddress(for: wallet) else {
            store.solanaSendPreview = nil
            store.isPreparingSolanaSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingSolanaSend else { return }
        store.isPreparingSolanaSend = true
        defer { store.isPreparingSolanaSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.solana, address: sourceAddress)
            let feeSOL = rustFeeDisplay(from: feeJSON)
            let lamports = UInt64(WalletSendLayer.rustField("lamports", from: balanceJSON)) ?? 0
            let balance = Double(lamports) / 1e9
            store.solanaSendPreview = SolanaSendPreview(
                estimatedNetworkFeeSOL: feeSOL,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeSOL)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.solanaSendPreview = nil
            store.sendError = "Unable to estimate Solana fee right now. Check provider health and retry."
        }
    }

    static func refreshXRPSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "XRP Ledger",
              selectedSendCoin.symbol == "XRP",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.xrpSendPreview = nil
            store.isPreparingXRPSend = false
            return
        }

        guard let sourceAddress = store.resolvedXRPAddress(for: wallet) else {
            store.xrpSendPreview = nil
            store.isPreparingXRPSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingXRPSend else { return }
        store.isPreparingXRPSend = true
        defer { store.isPreparingXRPSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.xrp, address: sourceAddress)
            let feeXRP = rustFeeDisplay(from: feeJSON)
            let feeDrops = Int64(rustFeeRaw(from: feeJSON)) ?? 12
            let drops = UInt64(WalletSendLayer.rustField("drops", from: balanceJSON)) ?? 0
            let balance = Double(drops) / 1e6
            store.xrpSendPreview = XRPSendPreview(
                estimatedNetworkFeeXRP: feeXRP,
                feeDrops: feeDrops,
                sequence: 0,
                lastLedgerSequence: 0,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeXRP)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.xrpSendPreview = nil
            store.sendError = "Unable to estimate XRP fee right now. Check provider health and retry."
        }
    }

    static func refreshStellarSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Stellar",
              selectedSendCoin.symbol == "XLM",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.stellarSendPreview = nil
            store.isPreparingStellarSend = false
            return
        }

        guard let sourceAddress = store.resolvedStellarAddress(for: wallet) else {
            store.stellarSendPreview = nil
            store.isPreparingStellarSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingStellarSend else { return }
        store.isPreparingStellarSend = true
        defer { store.isPreparingStellarSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.stellar, address: sourceAddress)
            let feeXLM = rustFeeDisplay(from: feeJSON)
            let feeStroops = Int64(rustFeeRaw(from: feeJSON)) ?? 100
            let stroops = Int64(WalletSendLayer.rustField("stroops", from: balanceJSON)) ?? 0
            let balance = Double(stroops) / 1e7
            store.stellarSendPreview = StellarSendPreview(
                estimatedNetworkFeeXLM: feeXLM,
                feeStroops: feeStroops,
                sequence: 0,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeXLM)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.stellarSendPreview = nil
            store.sendError = "Unable to estimate Stellar fee right now. Check provider health and retry."
        }
    }

    static func refreshMoneroSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Monero",
              selectedSendCoin.symbol == "XMR",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.moneroSendPreview = nil
            store.isPreparingMoneroSend = false
            return
        }

        guard let sourceAddress = store.resolvedMoneroAddress(for: wallet) else {
            store.moneroSendPreview = nil
            store.isPreparingMoneroSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingMoneroSend else { return }
        store.isPreparingMoneroSend = true
        defer { store.isPreparingMoneroSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.monero, address: sourceAddress)
            let feeXMR = rustFeeDisplay(from: feeJSON)
            let piconeros = UInt64(WalletSendLayer.rustField("piconeros", from: balanceJSON)) ?? 0
            let balance = Double(piconeros) / 1e12
            store.moneroSendPreview = MoneroSendPreview(
                estimatedNetworkFeeXMR: feeXMR,
                priorityLabel: "normal",
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeXMR)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.moneroSendPreview = MoneroSendPreview(
                estimatedNetworkFeeXMR: 0.0002,
                priorityLabel: "normal",
                spendableBalance: 0,
                feeRateDescription: "normal",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = error.localizedDescription
        }
    }

    static func refreshCardanoSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Cardano",
              selectedSendCoin.symbol == "ADA",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.cardanoSendPreview = nil
            store.isPreparingCardanoSend = false
            return
        }

        guard let sourceAddress = store.resolvedCardanoAddress(for: wallet) else {
            store.cardanoSendPreview = nil
            store.isPreparingCardanoSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingCardanoSend else { return }
        store.isPreparingCardanoSend = true
        defer { store.isPreparingCardanoSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.cardano, address: sourceAddress)
            let feeADA = rustFeeDisplay(from: feeJSON)
            let lovelace = UInt64(WalletSendLayer.rustField("lovelace", from: balanceJSON)) ?? 0
            let balance = Double(lovelace) / 1e6
            store.cardanoSendPreview = CardanoSendPreview(
                estimatedNetworkFeeADA: feeADA,
                ttlSlot: 0,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeADA)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.cardanoSendPreview = CardanoSendPreview(
                estimatedNetworkFeeADA: 0.2,
                ttlSlot: 0,
                spendableBalance: 0,
                feeRateDescription: nil,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingCardanoSendError(error)
        }
    }

    static func refreshSuiSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Sui",
              selectedSendCoin.symbol == "SUI",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.suiSendPreview = nil
            store.isPreparingSuiSend = false
            return
        }

        guard let sourceAddress = store.resolvedSuiAddress(for: wallet) else {
            store.suiSendPreview = nil
            store.isPreparingSuiSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingSuiSend else { return }
        store.isPreparingSuiSend = true
        defer { store.isPreparingSuiSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.sui, address: sourceAddress)
            let feeSUI = rustFeeDisplay(from: feeJSON)
            let gasBudgetMist = UInt64(rustFeeRaw(from: feeJSON)) ?? 3_000_000
            let mist = UInt64(WalletSendLayer.rustField("mist", from: balanceJSON)) ?? 0
            let balance = Double(mist) / 1e9
            store.suiSendPreview = SuiSendPreview(
                estimatedNetworkFeeSUI: feeSUI,
                gasBudgetMist: gasBudgetMist,
                referenceGasPrice: 1_000,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeSUI)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.suiSendPreview = SuiSendPreview(
                estimatedNetworkFeeSUI: 0.001,
                gasBudgetMist: 3_000_000,
                referenceGasPrice: 1_000,
                spendableBalance: 0,
                feeRateDescription: "Reference gas price: 1000",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingSuiSendError(error)
        }
    }

    static func refreshAptosSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Aptos",
              selectedSendCoin.symbol == "APT",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.aptosSendPreview = nil
            store.isPreparingAptosSend = false
            return
        }

        guard let sourceAddress = store.resolvedAptosAddress(for: wallet) else {
            store.aptosSendPreview = nil
            store.isPreparingAptosSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingAptosSend else { return }
        store.isPreparingAptosSend = true
        defer { store.isPreparingAptosSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.aptos, address: sourceAddress)
            let feeAPT = rustFeeDisplay(from: feeJSON)
            let gasUnitPriceOctas = UInt64(rustFeeRaw(from: feeJSON)) ?? 100
            let octas = UInt64(WalletSendLayer.rustField("octas", from: balanceJSON)) ?? 0
            let balance = Double(octas) / 1e8
            store.aptosSendPreview = AptosSendPreview(
                estimatedNetworkFeeAPT: feeAPT,
                maxGasAmount: 10_000,
                gasUnitPriceOctas: gasUnitPriceOctas,
                spendableBalance: balance,
                feeRateDescription: "\(gasUnitPriceOctas) octas/unit",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeAPT)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.aptosSendPreview = AptosSendPreview(
                estimatedNetworkFeeAPT: 0.0002,
                maxGasAmount: 2_000,
                gasUnitPriceOctas: 100,
                spendableBalance: 0,
                feeRateDescription: "100 octas/unit",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingAptosSendError(error)
        }
    }

    static func refreshTONSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "TON",
              selectedSendCoin.symbol == "TON",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.tonSendPreview = nil
            store.isPreparingTONSend = false
            return
        }

        guard let sourceAddress = store.resolvedTONAddress(for: wallet) else {
            store.tonSendPreview = nil
            store.isPreparingTONSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingTONSend else { return }
        store.isPreparingTONSend = true
        defer { store.isPreparingTONSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.ton, address: sourceAddress)
            let feeTON = rustFeeDisplay(from: feeJSON)
            let nanotons = UInt64(WalletSendLayer.rustField("nanotons", from: balanceJSON)) ?? 0
            let balance = Double(nanotons) / 1e9
            store.tonSendPreview = TONSendPreview(
                estimatedNetworkFeeTON: feeTON,
                sequenceNumber: 0,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeTON)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.tonSendPreview = TONSendPreview(
                estimatedNetworkFeeTON: 0.005,
                sequenceNumber: 0,
                spendableBalance: 0,
                feeRateDescription: nil,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingTONSendError(error)
        }
    }

    static func refreshICPSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Internet Computer",
              selectedSendCoin.symbol == "ICP",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.icpSendPreview = nil
            store.isPreparingICPSend = false
            return
        }

        guard let sourceAddress = store.resolvedICPAddress(for: wallet) else {
            store.icpSendPreview = nil
            store.isPreparingICPSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingICPSend else { return }
        store.isPreparingICPSend = true
        defer { store.isPreparingICPSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.icp, address: sourceAddress)
            let feeICP = rustFeeDisplay(from: feeJSON)
            let feeE8s = UInt64(rustFeeRaw(from: feeJSON)) ?? 10_000
            let e8s = UInt64(WalletSendLayer.rustField("e8s", from: balanceJSON)) ?? 0
            let balance = Double(e8s) / 1e8
            store.icpSendPreview = ICPSendPreview(
                estimatedNetworkFeeICP: feeICP,
                feeE8s: feeE8s,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeICP)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.icpSendPreview = nil
            store.sendError = error.localizedDescription
        }
    }

    static func refreshNearSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "NEAR",
              selectedSendCoin.symbol == "NEAR",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.nearSendPreview = nil
            store.isPreparingNearSend = false
            return
        }

        guard let sourceAddress = store.resolvedNearAddress(for: wallet) else {
            store.nearSendPreview = nil
            store.isPreparingNearSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingNearSend else { return }
        store.isPreparingNearSend = true
        defer { store.isPreparingNearSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.near, address: sourceAddress)
            let feeNEAR = rustFeeDisplay(from: feeJSON)
            let gasPriceYocto = rustFeeRaw(from: feeJSON)
            let balance = RustBalanceDecoder.yoctoNearToDouble(from: balanceJSON) ?? 0
            store.nearSendPreview = NearSendPreview(
                estimatedNetworkFeeNEAR: feeNEAR,
                gasPriceYoctoNear: gasPriceYocto,
                spendableBalance: balance,
                feeRateDescription: gasPriceYocto,
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeNEAR)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.nearSendPreview = NearSendPreview(
                estimatedNetworkFeeNEAR: 0.00005,
                gasPriceYoctoNear: "100000000",
                spendableBalance: 0,
                feeRateDescription: "100000000",
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: 0
            )
            store.sendError = store.userFacingNearSendError(error)
        }
    }

    static func refreshPolkadotSendPreview(using store: WalletStore) async {
        guard let wallet = store.wallet(for: store.sendWalletID),
              let selectedSendCoin = store.selectedSendCoin,
              selectedSendCoin.chainName == "Polkadot",
              selectedSendCoin.symbol == "DOT",
              let amount = Double(store.sendAmount),
              amount > 0 else {
            store.polkadotSendPreview = nil
            store.isPreparingPolkadotSend = false
            return
        }

        guard let seedPhrase = store.storedSeedPhrase(for: wallet.id),
              let sourceAddress = store.resolvedPolkadotAddress(for: wallet) else {
            store.polkadotSendPreview = nil
            store.isPreparingPolkadotSend = false
            return
        }

        let previewDestination = store.sendAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewAddress = previewDestination.isEmpty ? sourceAddress : previewDestination

        guard !store.isPreparingPolkadotSend else { return }
        store.isPreparingPolkadotSend = true
        defer { store.isPreparingPolkadotSend = false }

        do {
            let (feeJSON, balanceJSON) = try await rustFeeAndBalance(chainId: SpectraChainID.polkadot, address: sourceAddress)
            let feeDOT = rustFeeDisplay(from: feeJSON)
            let planckDouble = RustBalanceDecoder.uint128StringField("planck", from: balanceJSON) ?? 0
            let balance = planckDouble / 1e10
            store.polkadotSendPreview = PolkadotSendPreview(
                estimatedNetworkFeeDOT: feeDOT,
                spendableBalance: balance,
                feeRateDescription: WalletSendLayer.rustField("source", from: feeJSON),
                estimatedTransactionBytes: nil,
                selectedInputCount: nil,
                usesChangeOutput: nil,
                maxSendable: max(0, balance - feeDOT)
            )
            store.sendError = nil
        } catch {
            if store.isCancelledRequest(error) { return }
            store.polkadotSendPreview = nil
            store.sendError = store.userFacingPolkadotSendError(error)
        }
    }
}
