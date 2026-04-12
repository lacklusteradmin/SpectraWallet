import Foundation
import Combine

// MARK: - SendMachineDriver
//
// @MainActor wrapper around the Rust SendStateMachine.
// Owns one machine instance per active send sheet and routes effects:
//   • FetchFeePreview  → right bridge method for the chain family
//   • SubmitTransaction → right signing bridge + records the transaction
//
// fee_raw encoding conventions (driver encodes on FeeReady, decodes on Submit):
//   BTC          → "<fee_rate_svb_double>"    (e.g. "10.0")
//   BCH/BSV/LTC/DOGE → "<fee_sat_uint64>"     (e.g. "10000")
//   ADA          → "<fee_lovelace_uint64>"
//   SUI          → "<gas_budget_mist_uint64>"
//   EVM          → full EVM preview JSON string
//   all others   → "" (fee is implicit in Rust's signing layer)

@MainActor
final class SendMachineDriver: ObservableObject {

    // MARK: Published — consumed by UI

    @Published var isFetchingFee: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var feeDisplay: String?
    /// Set during EVM fee fetch so the advanced EVM section can show nonce/gas detail.
    @Published var evmPreviewJSON: String?
    @Published var errorMessage: String?
    @Published var successTxid: String?

    // MARK: Private

    private let machine: SendStateMachine = SendStateMachine()
    private weak var store: WalletStore?

    /// Wallet + holding context injected by the store when a send begins.
    private var walletID: UUID?
    private var holdingKey: String?

    // MARK: Init

    init(store: WalletStore) {
        self.store = store
    }

    // MARK: - Public API

    /// Reset everything and register the wallet + holding for this send session.
    /// Must be called before firing any events.
    func begin(walletID: UUID, holdingKey: String) {
        self.walletID = walletID
        self.holdingKey = holdingKey
        machine.reset()
        resetPublishedState()
    }

    func sendSetAsset(chainId: UInt32, symbol: String, contract: String?, decimals: UInt8) {
        var fields: [String: Any] = [
            "kind": "setAsset",
            "chainId": chainId,
            "symbol": symbol,
            "decimals": decimals,
        ]
        if let contract { fields["contract"] = contract }
        applyEvent(fields)
    }

    func sendSetAddress(_ destination: String) {
        applyEvent(["kind": "setAddress", "destination": destination])
    }

    func sendSetAmount(_ amountDisplay: String) {
        applyEvent(["kind": "setAmount", "amountDisplay": amountDisplay])
    }

    func sendRequestFeePreview() {
        applyEvent(["kind": "requestFeePreview"])
    }

    func sendConfirm() {
        applyEvent(["kind": "confirm"])
    }

    func sendReset() {
        machine.reset()
        walletID = nil
        holdingKey = nil
        resetPublishedState()
    }

    // MARK: - Event machinery

    private func applyEvent(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields),
              let json = String(data: data, encoding: .utf8),
              let result = try? machine.applyEvent(eventJson: json) else { return }
        processResult(result)
    }

    private func processResult(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let effects = obj["effects"] as? [[String: Any]] else { return }
        for effect in effects {
            dispatchEffect(effect)
        }
    }

    private func dispatchEffect(_ effect: [String: Any]) {
        guard let kind = effect["kind"] as? String else { return }
        switch kind {
        case "fetchFeePreview":   handleFetchFeePreview(effect)
        case "submitTransaction": handleSubmitTransaction(effect)
        case "showError":         errorMessage = effect["message"] as? String
        case "dismiss":           break  // UI observes successTxid
        default:                  break
        }
    }

    // MARK: - FetchFeePreview effect

    private func handleFetchFeePreview(_ effect: [String: Any]) {
        guard let chainId = effectChainId(effect) else { return }
        let symbol      = effect["symbol"]      as? String ?? ""
        let contract    = effect["contract"]    as? String
        let destination = effect["destination"] as? String ?? ""
        let amountDisplay = effect["amountDisplay"] as? String ?? ""

        isFetchingFee = true
        feeDisplay    = nil
        errorMessage  = nil
        evmPreviewJSON = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.fetchFee(
                    chainId: chainId, symbol: symbol, contract: contract,
                    destination: destination, amountDisplay: amountDisplay
                )
                self.isFetchingFee  = false
                self.feeDisplay     = result.display
                self.evmPreviewJSON = result.evmJSON
                self.applyEvent(["kind": "feeReady",
                                 "feeDisplay": result.display,
                                 "feeRaw": result.raw])
            } catch {
                self.isFetchingFee = false
                self.applyEvent(["kind": "feeFailed",
                                 "reason": error.localizedDescription])
            }
        }
    }

    private struct FeeResult {
        let display: String
        let raw: String
        let evmJSON: String?
    }

    private func fetchFee(
        chainId: UInt32,
        symbol: String,
        contract: String?,
        destination: String,
        amountDisplay: String
    ) async throws -> FeeResult {
        let bridge  = WalletServiceBridge.shared
        let amount  = Double(amountDisplay) ?? 0
        let wallet  = resolvedWallet()

        switch chainId {

        // ── Bitcoin ──────────────────────────────────────────────────────────
        case SpectraChainID.bitcoin:
            // HD wallet path: use xpub-based balance + fee estimate
            if let xpub = wallet?.bitcoinXPub?.trimmingCharacters(in: .whitespacesAndNewlines),
               !xpub.isEmpty {
                async let balJSON = bridge.fetchBitcoinXpubBalanceJSON(xpub: xpub)
                async let feeJSON = bridge.fetchFeeEstimateJSON(chainId: chainId)
                let (bal, fee) = try await (balJSON, feeJSON)
                let rateRaw   = SendMachineDriver.rustField("sats_per_vbyte", from: fee)
                let rate      = max(1.0, (Double(rateRaw) ?? 1.0).rounded(.up))
                let feeSat    = UInt64(rate) * 250
                let feeBTC    = Double(feeSat) / 1e8
                let display   = "\(Int(rate)) sat/vB · \(String(format: "%.8f", feeBTC)) BTC"
                return FeeResult(display: display, raw: "\(rate)", evmJSON: nil)
            }
            // Single-address path
            guard let address = wallet.flatMap({ store?.resolvedBitcoinAddress(for: $0) }) else {
                throw MachineDriverError.missingAddress("Bitcoin")
            }
            let json    = try await bridge.fetchUTXOFeePreviewJSON(chainId: chainId, address: address, feeRateSvb: 0)
            let rate    = Double(SendMachineDriver.rustField("fee_rate_svb", from: json)) ?? 10
            let feeSat  = UInt64(SendMachineDriver.rustField("estimated_fee_sat", from: json)) ?? 0
            let feeBTC  = Double(feeSat) / 1e8
            let display = "\(Int(rate)) sat/vB · \(String(format: "%.8f", feeBTC)) BTC"
            return FeeResult(display: display, raw: "\(rate)", evmJSON: nil)

        // ── Bitcoin Cash ─────────────────────────────────────────────────────
        case SpectraChainID.bitcoinCash:
            guard let address = wallet.flatMap({ store?.resolvedBitcoinCashAddress(for: $0) }) else {
                throw MachineDriverError.missingAddress("Bitcoin Cash")
            }
            let json    = try await bridge.fetchUTXOFeePreviewJSON(chainId: chainId, address: address, feeRateSvb: 0)
            let feeSat  = UInt64(SendMachineDriver.rustField("estimated_fee_sat", from: json)) ?? 0
            let feeBCH  = Double(feeSat) / 1e8
            return FeeResult(display: "\(String(format: "%.8f", feeBCH)) BCH", raw: "\(feeSat)", evmJSON: nil)

        // ── Bitcoin SV ───────────────────────────────────────────────────────
        case SpectraChainID.bitcoinSv:
            guard let address = wallet.flatMap({ store?.resolvedBitcoinSVAddress(for: $0) }) else {
                throw MachineDriverError.missingAddress("Bitcoin SV")
            }
            let json    = try await bridge.fetchUTXOFeePreviewJSON(chainId: chainId, address: address, feeRateSvb: 0)
            let feeSat  = UInt64(SendMachineDriver.rustField("estimated_fee_sat", from: json)) ?? 0
            let feeBSV  = Double(feeSat) / 1e8
            return FeeResult(display: "\(String(format: "%.8f", feeBSV)) BSV", raw: "\(feeSat)", evmJSON: nil)

        // ── Litecoin ─────────────────────────────────────────────────────────
        case SpectraChainID.litecoin:
            guard let address = wallet.flatMap({ store?.resolvedLitecoinAddress(for: $0) }) else {
                throw MachineDriverError.missingAddress("Litecoin")
            }
            let json    = try await bridge.fetchUTXOFeePreviewJSON(chainId: chainId, address: address, feeRateSvb: 0)
            let feeSat  = UInt64(SendMachineDriver.rustField("estimated_fee_sat", from: json)) ?? 0
            let feeLTC  = Double(feeSat) / 1e8
            return FeeResult(display: "\(String(format: "%.8f", feeLTC)) LTC", raw: "\(feeSat)", evmJSON: nil)

        // ── Dogecoin ─────────────────────────────────────────────────────────
        case SpectraChainID.dogecoin:
            guard let address = wallet.flatMap({ store?.resolvedDogecoinAddress(for: $0) }) else {
                throw MachineDriverError.missingAddress("Dogecoin")
            }
            let json    = try await bridge.fetchUTXOFeePreviewJSON(chainId: chainId, address: address, feeRateSvb: 0)
            let feeSat  = UInt64(SendMachineDriver.rustField("estimated_fee_sat", from: json)) ?? 0
            let feeDOGE = Double(feeSat) / 1e8
            return FeeResult(display: "\(String(format: "%.8f", feeDOGE)) DOGE", raw: "\(feeSat)", evmJSON: nil)

        // ── EVM chains ───────────────────────────────────────────────────────
        case let id where Self.evmChainIds.contains(id):
            guard let chainName = Self.evmChainName[id],
                  let fromAddress = wallet.flatMap({ store?.resolvedEVMAddress(for: $0, chainName: chainName) }) else {
                throw MachineDriverError.missingAddress("EVM (\(chainId))")
            }
            let isNative   = contract == nil
            let valueWei: String
            let toAddress: String
            let dataHex: String
            if isNative {
                valueWei  = Self.tokenAmountToRawString(amount, decimals: 18)
                toAddress = destination.isEmpty ? fromAddress : destination
                dataHex   = "0x"
            } else if let contractAddr = contract {
                // ERC-20: encode a minimal transfer calldata stub for gas estimation
                valueWei  = "0"
                toAddress = contractAddr
                let dest   = destination.isEmpty ? fromAddress : destination
                let toParam = String(repeating: "0", count: 24) + dest.dropFirst(dest.hasPrefix("0x") ? 2 : 0).lowercased()
                let dataStub = String(repeating: "0", count: 64)
                dataHex   = "0xa9059cbb\(toParam)\(dataStub)"
            } else {
                throw MachineDriverError.missingAddress("EVM token")
            }
            let previewJSON = try await bridge.fetchEVMSendPreviewJSON(
                chainId: id, from: fromAddress, to: toAddress, valueWei: valueWei, dataHex: dataHex
            )
            let feeETH = (try? JSONSerialization.jsonObject(with: Data(previewJSON.utf8))) as? [String: Any]
            let feeVal = feeETH?["estimated_fee_eth"] as? Double ?? 0
            let nativeSymbol = Self.evmNativeSymbol[id] ?? "ETH"
            let display = String(format: "≈ %.6f \(nativeSymbol)", feeVal)
            return FeeResult(display: display, raw: previewJSON, evmJSON: previewJSON)

        // ── Tron ─────────────────────────────────────────────────────────────
        case SpectraChainID.tron:
            guard let address = wallet.flatMap({ store?.resolvedTronAddress(for: $0) }) else {
                throw MachineDriverError.missingAddress("Tron")
            }
            let previewJSON = try await bridge.fetchTronSendPreviewJSON(
                address: address, symbol: symbol, contractAddress: contract ?? ""
            )
            let obj  = (try? JSONSerialization.jsonObject(with: Data(previewJSON.utf8))) as? [String: Any]
            let fee  = obj?["estimated_fee_trx"] as? Double ?? 0
            let display = fee > 0 ? String(format: "≈ %.6f TRX", fee) : "Standard TRX fee"
            return FeeResult(display: display, raw: "", evmJSON: nil)

        // ── Cardano ──────────────────────────────────────────────────────────
        case SpectraChainID.cardano:
            let json    = try await bridge.fetchFeeEstimateJSON(chainId: chainId)
            let display = SendMachineDriver.rustField("native_fee_display", from: json)
            let raw     = SendMachineDriver.rustField("native_fee_raw", from: json)
            return FeeResult(display: display.isEmpty ? "≈ 0.17 ADA" : display, raw: raw, evmJSON: nil)

        // ── Sui ──────────────────────────────────────────────────────────────
        case SpectraChainID.sui:
            let json    = try await bridge.fetchFeeEstimateJSON(chainId: chainId)
            let display = SendMachineDriver.rustField("native_fee_display", from: json)
            let raw     = SendMachineDriver.rustField("native_fee_raw", from: json)
            return FeeResult(display: display.isEmpty ? "Standard SUI fee" : display, raw: raw, evmJSON: nil)

        // ── All other simple chains (SOL, XRP, XLM, DOT, APT, TON, NEAR, ICP, XMR) ──
        default:
            let json    = try await bridge.fetchFeeEstimateJSON(chainId: chainId)
            let display = SendMachineDriver.rustField("native_fee_display", from: json)
            return FeeResult(display: display.isEmpty ? "Standard network fee" : display, raw: "", evmJSON: nil)
        }
    }

    // MARK: - SubmitTransaction effect

    private func handleSubmitTransaction(_ effect: [String: Any]) {
        guard let chainId       = effectChainId(effect) else { return }
        let symbol      = effect["symbol"]        as? String ?? ""
        let contract    = effect["contract"]      as? String
        let destination = effect["destination"]   as? String ?? ""
        let amountDisplay = effect["amountDisplay"] as? String ?? ""
        let feeRaw      = effect["feeRaw"]        as? String ?? ""

        guard let wid  = walletID,
              let hkey = holdingKey,
              let store else {
            errorMessage = "Send session context is missing."
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let txid = try await self.submitTransaction(
                    chainId: chainId, symbol: symbol, contract: contract,
                    destination: destination, amountDisplay: amountDisplay,
                    feeRaw: feeRaw, walletID: wid, holdingKey: hkey
                )
                self.isSubmitting = false
                self.successTxid  = txid
                self.applyEvent(["kind": "txSuccess", "txid": txid])
            } catch {
                self.isSubmitting = false
                let message = error.localizedDescription
                self.errorMessage = message
                self.applyEvent(["kind": "txError", "reason": message])
            }
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func submitTransaction(
        chainId: UInt32,
        symbol: String,
        contract: String?,
        destination: String,
        amountDisplay: String,
        feeRaw: String,
        walletID: UUID,
        holdingKey: String
    ) async throws -> String {
        guard let store else { throw MachineDriverError.storeGone }
        guard let wallet = store.wallet(for: walletID.uuidString) else {
            throw MachineDriverError.walletNotFound(walletID)
        }
        guard let holding = wallet.holdings.first(where: { $0.holdingKey == holdingKey }) else {
            throw MachineDriverError.holdingNotFound(holdingKey)
        }
        let amount = Double(amountDisplay) ?? 0
        let bridge = WalletServiceBridge.shared

        // ── Helper to record a completed send ──────────────────────────────
        func record(txid: String, chainName: String, payload: String, format: String) {
            let rec = store.decoratePendingSendTransaction(TransactionRecord(
                walletID: wallet.id,
                kind: .send,
                status: .pending,
                walletName: wallet.name,
                assetName: holding.name,
                symbol: holding.symbol,
                chainName: chainName,
                amount: amount,
                address: destination,
                transactionHash: txid,
                signedTransactionPayload: payload,
                signedTransactionPayloadFormat: format
            ), holding: holding)
            store.recordPendingSentTransaction(rec)
            Task { @MainActor in
                await store.runPostSendRefreshActions(for: chainName, verificationStatus: .verified)
            }
        }

        switch chainId {

        // ── Bitcoin ──────────────────────────────────────────────────────────
        case SpectraChainID.bitcoin:
            guard let seedPhrase   = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Bitcoin")
            }
            guard let sourceAddress = store.resolvedBitcoinAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Bitcoin")
            }
            let amountSat  = UInt64(amount * 1e8)
            let feeRateSvB = Double(feeRaw) ?? 10
            let resultJSON = try await bridge.signAndSendWithDerivation(
                chainId: chainId, seedPhrase: seedPhrase, chain: .bitcoin,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoin)
            ) { privKeyHex, _ in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_sat\":\(amountSat),\"fee_rate_svb\":\(feeRateSvB),\"private_key_hex\":\"\(privKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Bitcoin", payload: resultJSON, format: "bitcoin.rust_json")
            return txid

        // ── Bitcoin Cash ─────────────────────────────────────────────────────
        case SpectraChainID.bitcoinCash:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Bitcoin Cash")
            }
            guard let sourceAddress = store.resolvedBitcoinCashAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Bitcoin Cash")
            }
            let amountSat = UInt64(amount * 1e8)
            let feeSat    = UInt64(feeRaw) ?? 1000
            let resultJSON = try await bridge.signAndSendWithDerivation(
                chainId: chainId, seedPhrase: seedPhrase, chain: .bitcoinCash,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinCash)
            ) { privKeyHex, _ in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Bitcoin Cash", payload: resultJSON, format: "bitcoin_cash.rust_json")
            return txid

        // ── Bitcoin SV ───────────────────────────────────────────────────────
        case SpectraChainID.bitcoinSv:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Bitcoin SV")
            }
            guard let sourceAddress = store.resolvedBitcoinSVAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Bitcoin SV")
            }
            let amountSat = UInt64(amount * 1e8)
            let feeSat    = UInt64(feeRaw) ?? 1000
            let resultJSON = try await bridge.signAndSendWithDerivation(
                chainId: chainId, seedPhrase: seedPhrase, chain: .bitcoinSV,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .bitcoinSV)
            ) { privKeyHex, _ in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Bitcoin SV", payload: resultJSON, format: "bitcoin_sv.rust_json")
            return txid

        // ── Litecoin ─────────────────────────────────────────────────────────
        case SpectraChainID.litecoin:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Litecoin")
            }
            guard let sourceAddress = store.resolvedLitecoinAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Litecoin")
            }
            let amountSat = UInt64(amount * 1e8)
            let feeSat    = UInt64(feeRaw) ?? 1000
            let resultJSON = try await bridge.signAndSendWithDerivation(
                chainId: chainId, seedPhrase: seedPhrase, chain: .litecoin,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .litecoin)
            ) { privKeyHex, _ in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Litecoin", payload: resultJSON, format: "litecoin.rust_json")
            return txid

        // ── Dogecoin ─────────────────────────────────────────────────────────
        case SpectraChainID.dogecoin:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Dogecoin")
            }
            guard let sourceAddress = store.resolvedDogecoinAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Dogecoin")
            }
            let amountSat = UInt64(amount * 1e8)
            let feeSat    = UInt64(feeRaw) ?? 3500
            let resultJSON = try await bridge.signAndSendWithDerivation(
                chainId: chainId, seedPhrase: seedPhrase, chain: .dogecoin,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .dogecoin)
            ) { privKeyHex, _ in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_sat\":\(amountSat),\"fee_sat\":\(feeSat),\"private_key_hex\":\"\(privKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Dogecoin", payload: resultJSON, format: "dogecoin.rust_json")
            return txid

        // ── Solana (SOL or SPL token) ─────────────────────────────────────
        case SpectraChainID.solana:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Solana")
            }
            guard let sourceAddress = store.resolvedSolanaAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Solana")
            }
            let resultJSON: String
            if contract == nil {
                // Native SOL
                let lamports = UInt64(amount * 1e9)
                resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                    chainId: chainId, seedPhrase: seedPhrase, chain: .solana,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .solana)
                ) { privKeyHex, pubKeyHex in
                    "{\"from_pubkey_hex\":\"\(pubKeyHex)\",\"to\":\"\(destination)\",\"lamports\":\(lamports),\"private_key_hex\":\"\(privKeyHex)\"}"
                }
            } else if let mintAddress = contract {
                // SPL token: look up decimals from tracked-token metadata
                let trackedTokens = store.solanaTrackedTokens(includeDisabled: true)
                let resolvedMint  = SolanaBalanceService.mintAddress(for: symbol) ?? mintAddress
                guard let tokenMetadata = trackedTokens[resolvedMint] ?? trackedTokens[mintAddress] else {
                    throw MachineDriverError.unsupported("\(symbol) on Solana is not configured for sending.")
                }
                let decimals   = tokenMetadata.decimals
                let scale      = pow(10.0, Double(decimals))
                let amountRaw  = UInt64((amount * scale).rounded())
                resultJSON = try await bridge.signAndSendTokenWithDerivation(
                    chainId: chainId, seedPhrase: seedPhrase, chain: .solana,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .solana)
                ) { privKeyHex, pubKeyHex in
                    let pk = pubKeyHex ?? ""
                    return "{\"from_pubkey_hex\":\"\(pk)\",\"to\":\"\(destination)\",\"mint\":\"\(mintAddress)\",\"amount_raw\":\"\(amountRaw)\",\"decimals\":\(decimals),\"private_key_hex\":\"\(privKeyHex)\"}"
                }
            } else {
                throw MachineDriverError.unsupported("Solana token missing mint address")
            }
            let txid = SendMachineDriver.rustField("signature", from: resultJSON)
            record(txid: txid, chainName: "Solana", payload: resultJSON, format: "solana.rust_json")
            return txid

        // ── XRP ──────────────────────────────────────────────────────────────
        case SpectraChainID.xrp:
            guard let sourceAddress = store.resolvedXRPAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("XRP Ledger")
            }
            let drops = UInt64(amount * 1e6)
            let resultJSON: String
            if let seedPhrase = store.storedSeedPhrase(for: walletID) {
                resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                    chainId: chainId, seedPhrase: seedPhrase, chain: .xrp,
                    derivationPath: store.walletDerivationPath(for: wallet, chain: .xrp)
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"drops\":\(drops),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
                }
            } else if let pk = store.storedPrivateKey(for: walletID) {
                let norm = pk.hasPrefix("0x") ? String(pk.dropFirst(2)) : pk
                resultJSON = try await bridge.signAndSend(
                    chainId: chainId,
                    paramsJson: "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"drops\":\(drops),\"private_key_hex\":\"\(norm)\"}"
                )
            } else {
                throw MachineDriverError.missingSeedPhrase("XRP")
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "XRP Ledger", payload: resultJSON, format: "xrp.rust_json")
            return txid

        // ── Stellar ───────────────────────────────────────────────────────────
        case SpectraChainID.stellar:
            guard let sourceAddress = store.resolvedStellarAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Stellar")
            }
            let stroops = Int64(amount * 1e7)
            let resultJSON: String
            if let seedPhrase = store.storedSeedPhrase(for: walletID) {
                resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                    chainId: chainId, seedPhrase: seedPhrase, chain: .stellar,
                    derivationPath: wallet.seedDerivationPaths.stellar
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"stroops\":\(stroops),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
                }
            } else if let pk = store.storedPrivateKey(for: walletID) {
                let norm = pk.hasPrefix("0x") ? String(pk.dropFirst(2)) : pk
                resultJSON = try await bridge.signAndSend(
                    chainId: chainId,
                    paramsJson: "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"stroops\":\(stroops),\"private_key_hex\":\"\(norm)\"}"
                )
            } else {
                throw MachineDriverError.missingSeedPhrase("Stellar")
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Stellar", payload: resultJSON, format: "stellar.rust_json")
            return txid

        // ── Monero ────────────────────────────────────────────────────────────
        case SpectraChainID.monero:
            let piconeros  = UInt64(amount * 1e12)
            let resultJSON = try await bridge.signAndSend(
                chainId: chainId,
                paramsJson: "{\"to\":\"\(destination)\",\"piconeros\":\(piconeros),\"priority\":2}"
            )
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Monero", payload: resultJSON, format: "monero.rust_json")
            return txid

        // ── Cardano ───────────────────────────────────────────────────────────
        case SpectraChainID.cardano:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Cardano")
            }
            guard let sourceAddress = store.resolvedCardanoAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Cardano")
            }
            let amountLovelace = UInt64(amount * 1e6)
            let feeLovelace    = UInt64(feeRaw) ?? 170_000
            let resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                chainId: chainId, seedPhrase: seedPhrase, chain: .cardano,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .cardano)
            ) { privKeyHex, pubKeyHex in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_lovelace\":\(amountLovelace),\"fee_lovelace\":\(feeLovelace),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Cardano", payload: resultJSON, format: "cardano.rust_json")
            return txid

        // ── Sui ───────────────────────────────────────────────────────────────
        case SpectraChainID.sui:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Sui")
            }
            guard let sourceAddress = store.resolvedSuiAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Sui")
            }
            let mistAmount  = UInt64(amount * 1e9)
            let gasBudget   = UInt64(feeRaw) ?? 1_000_000
            let resultJSON  = try await bridge.signAndSendWithDerivationAndPubKey(
                chainId: chainId, seedPhrase: seedPhrase, chain: .sui,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .sui)
            ) { privKeyHex, pubKeyHex in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"mist\":\(mistAmount),\"gas_budget\":\(gasBudget),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("digest", from: resultJSON)
            record(txid: txid, chainName: "Sui", payload: resultJSON, format: "sui.rust_json")
            return txid

        // ── Aptos ─────────────────────────────────────────────────────────────
        case SpectraChainID.aptos:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Aptos")
            }
            guard let sourceAddress = store.resolvedAptosAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Aptos")
            }
            let octasAmount = UInt64(amount * 1e8)
            let resultJSON  = try await bridge.signAndSendWithDerivationAndPubKey(
                chainId: chainId, seedPhrase: seedPhrase, chain: .aptos,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .aptos)
            ) { privKeyHex, pubKeyHex in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"octas\":\(octasAmount),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Aptos", payload: resultJSON, format: "aptos.rust_json")
            return txid

        // ── TON ───────────────────────────────────────────────────────────────
        case SpectraChainID.ton:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("TON")
            }
            guard let sourceAddress = store.resolvedTONAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("TON")
            }
            let nanotons   = UInt64(amount * 1e9)
            let resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                chainId: chainId, seedPhrase: seedPhrase, chain: .ton,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .ton)
            ) { privKeyHex, pubKeyHex in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"nanotons\":\(nanotons),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "TON", payload: resultJSON, format: "ton.rust_json")
            return txid

        // ── Internet Computer ─────────────────────────────────────────────────
        case SpectraChainID.icp:
            guard let sourceAddress = store.resolvedICPAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("ICP")
            }
            let e8sAmount = UInt64(amount * 1e8)
            let resultJSON: String
            if let seedPhrase = store.storedSeedPhrase(for: walletID) {
                resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                    chainId: chainId, seedPhrase: seedPhrase, chain: .internetComputer,
                    derivationPath: wallet.seedDerivationPaths.internetComputer
                ) { privKeyHex, pubKeyHex in
                    "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"e8s\":\(e8sAmount),\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
                }
            } else if let pk = store.storedPrivateKey(for: walletID) {
                let norm = pk.hasPrefix("0x") ? String(pk.dropFirst(2)) : pk
                resultJSON = try await bridge.signAndSend(
                    chainId: chainId,
                    paramsJson: "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"e8s\":\(e8sAmount),\"private_key_hex\":\"\(norm)\"}"
                )
            } else {
                throw MachineDriverError.missingSeedPhrase("ICP")
            }
            let txid = SendMachineDriver.rustField("block_index", from: resultJSON)
            record(txid: txid.isEmpty ? resultJSON : txid, chainName: "Internet Computer",
                   payload: resultJSON, format: "icp.rust_json")
            return txid.isEmpty ? resultJSON : txid

        // ── NEAR ──────────────────────────────────────────────────────────────
        case SpectraChainID.near:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("NEAR")
            }
            guard let sourceAddress = store.resolvedNearAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("NEAR")
            }
            let yoctoStr   = SendMachineDriver.nearToYoctoString(amount)
            let resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                chainId: chainId, seedPhrase: seedPhrase, chain: .near,
                derivationPath: store.walletDerivationPath(for: wallet, chain: .near)
            ) { privKeyHex, pubKeyHex in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"yocto_near\":\"\(yoctoStr)\",\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "NEAR", payload: resultJSON, format: "near.rust_json")
            return txid

        // ── Polkadot ──────────────────────────────────────────────────────────
        case SpectraChainID.polkadot:
            guard let seedPhrase    = store.storedSeedPhrase(for: walletID) else {
                throw MachineDriverError.missingSeedPhrase("Polkadot")
            }
            guard let sourceAddress = store.resolvedPolkadotAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Polkadot")
            }
            let planckStr  = SendMachineDriver.dotToPlanckString(amount)
            let resultJSON = try await bridge.signAndSendWithDerivationAndPubKey(
                chainId: chainId, seedPhrase: seedPhrase, chain: .polkadot,
                derivationPath: wallet.seedDerivationPaths.polkadot
            ) { privKeyHex, pubKeyHex in
                "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"planck\":\"\(planckStr)\",\"private_key_hex\":\"\(privKeyHex)\",\"public_key_hex\":\"\(pubKeyHex)\"}"
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Polkadot", payload: resultJSON, format: "polkadot.rust_json")
            return txid

        // ── Tron (TRX or TRC-20) ──────────────────────────────────────────────
        case SpectraChainID.tron:
            guard let sourceAddress = store.resolvedTronAddress(for: wallet) else {
                throw MachineDriverError.missingAddress("Tron")
            }
            let resultJSON: String
            if let seedPhrase = store.storedSeedPhrase(for: walletID) {
                if contract == nil {
                    // Native TRX
                    let amountSun = UInt64(amount * 1e6)
                    resultJSON = try await bridge.signAndSendWithDerivation(
                        chainId: chainId, seedPhrase: seedPhrase, chain: .tron,
                        derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_sun\":\(amountSun),\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                } else if let contractAddr = contract {
                    // TRC-20 (USDT-TRC20 uses 6 decimals)
                    let amountRaw  = UInt64((amount * 1_000_000.0).rounded())
                    resultJSON = try await bridge.signAndSendTokenWithDerivation(
                        chainId: chainId, seedPhrase: seedPhrase, chain: .tron,
                        derivationPath: wallet.seedDerivationPaths.tron
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contractAddr)\",\"to\":\"\(destination)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(privKeyHex)\"}"
                    }
                } else {
                    throw MachineDriverError.unsupported("Tron token missing contract")
                }
            } else if let pk = store.storedPrivateKey(for: walletID) {
                let norm = pk.hasPrefix("0x") ? String(pk.dropFirst(2)) : pk
                if contract == nil {
                    let amountSun = UInt64(amount * 1e6)
                    resultJSON = try await bridge.signAndSend(
                        chainId: chainId,
                        paramsJson: "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"amount_sun\":\(amountSun),\"private_key_hex\":\"\(norm)\"}"
                    )
                } else if let contractAddr = contract {
                    let amountRaw = UInt64((amount * 1_000_000.0).rounded())
                    resultJSON = try await bridge.signAndSendToken(
                        chainId: chainId,
                        paramsJson: "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contractAddr)\",\"to\":\"\(destination)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(norm)\"}"
                    )
                } else {
                    throw MachineDriverError.unsupported("Tron token")
                }
            } else {
                throw MachineDriverError.missingSeedPhrase("Tron")
            }
            let txid = SendMachineDriver.rustField("txid", from: resultJSON)
            record(txid: txid, chainName: "Tron", payload: resultJSON, format: "tron.rust_json")
            return txid

        // ── EVM chains (ETH, ARB, OP, AVAX, BASE, ETC, BSC, HL) ─────────────
        case let id where Self.evmChainIds.contains(id):
            guard let chainName = Self.evmChainName[id] else {
                throw MachineDriverError.unsupported("EVM chain \(id)")
            }
            let evmDerivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: chainName) ?? .ethereum
            guard let sourceAddress = store.resolvedEVMAddress(for: wallet, chainName: chainName) else {
                throw MachineDriverError.missingAddress(chainName)
            }
            // Parse EVM preview JSON stored in fee_raw
            let previewObj = (try? JSONSerialization.jsonObject(with: Data(feeRaw.utf8))) as? [String: Any]
            let overridesFragment: String = {
                guard let obj = previewObj else { return "" }
                var frags: [String] = []
                // Pass along nonce/gas overrides if present in stored preview
                if let nonce = obj["nonce"] as? Int { frags.append("\"nonce\":\(nonce)") }
                return frags.isEmpty ? "" : "," + frags.joined(separator: ",")
            }()
            let resultJSON: String
            let spectraChainId = id
            if contract == nil {
                // Native EVM asset
                let valueWei = Self.tokenAmountToRawString(amount, decimals: 18)
                if let seedPhrase = store.storedSeedPhrase(for: walletID) {
                    resultJSON = try await bridge.signAndSendWithDerivation(
                        chainId: spectraChainId, seedPhrase: seedPhrase,
                        chain: evmDerivationChain,
                        derivationPath: store.walletDerivationPath(for: wallet, chain: evmDerivationChain)
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"value_wei\":\"\(valueWei)\",\"private_key_hex\":\"\(privKeyHex)\"\(overridesFragment)}"
                    }
                } else if let pk = store.storedPrivateKey(for: walletID) {
                    let payload = "{\"from\":\"\(sourceAddress)\",\"to\":\"\(destination)\",\"value_wei\":\"\(valueWei)\",\"private_key_hex\":\"\(pk)\"\(overridesFragment)}"
                    resultJSON = try await bridge.signAndSend(chainId: spectraChainId, paramsJson: payload)
                } else {
                    throw MachineDriverError.missingSeedPhrase(chainName)
                }
            } else if let contractAddr = contract {
                // ERC-20 token — look up decimals via store's supported-token registry
                guard let token = store.supportedEVMToken(for: holding) else {
                    throw MachineDriverError.unsupported("\(symbol) on \(chainName) is not configured for sending.")
                }
                let amountRaw  = Self.tokenAmountToRawString(amount, decimals: token.decimals)
                if let seedPhrase = store.storedSeedPhrase(for: walletID) {
                    resultJSON = try await bridge.signAndSendTokenWithDerivation(
                        chainId: spectraChainId, seedPhrase: seedPhrase,
                        chain: evmDerivationChain,
                        derivationPath: store.walletDerivationPath(for: wallet, chain: evmDerivationChain)
                    ) { privKeyHex, _ in
                        "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contractAddr)\",\"to\":\"\(destination)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(privKeyHex)\"\(overridesFragment)}"
                    }
                } else if let pk = store.storedPrivateKey(for: walletID) {
                    let payload = "{\"from\":\"\(sourceAddress)\",\"contract\":\"\(contractAddr)\",\"to\":\"\(destination)\",\"amount_raw\":\"\(amountRaw)\",\"private_key_hex\":\"\(pk)\"\(overridesFragment)}"
                    resultJSON = try await bridge.signAndSendToken(chainId: spectraChainId, paramsJson: payload)
                } else {
                    throw MachineDriverError.missingSeedPhrase(chainName)
                }
            } else {
                throw MachineDriverError.unsupported("\(chainName) token")
            }
            let evmResult = Self.decodeEvmSendResult(resultJSON)
            record(txid: evmResult.txid, chainName: chainName,
                   payload: evmResult.rawHex.isEmpty ? resultJSON : evmResult.rawHex,
                   format: "evm.raw_hex")
            return evmResult.txid

        default:
            throw MachineDriverError.unsupported("chain \(chainId)")
        }
    }

    // MARK: - Helpers

    private func resolvedWallet() -> ImportedWallet? {
        guard let wid = walletID else { return nil }
        return store?.wallet(for: wid.uuidString)
    }

    private func resetPublishedState() {
        isFetchingFee  = false
        isSubmitting   = false
        feeDisplay     = nil
        evmPreviewJSON = nil
        errorMessage   = nil
        successTxid    = nil
    }

    private func effectChainId(_ effect: [String: Any]) -> UInt32? {
        if let n = effect["chainId"] as? NSNumber { return n.uint32Value }
        if let s = effect["chainId"] as? String   { return UInt32(s) }
        return nil
    }

    // MARK: - Static chain tables

    static let evmChainIds: Set<UInt32> = [
        SpectraChainID.ethereum, SpectraChainID.arbitrum, SpectraChainID.optimism,
        SpectraChainID.avalanche, SpectraChainID.base, SpectraChainID.ethereumClassic,
        SpectraChainID.bsc, SpectraChainID.hyperliquid,
    ]

    private static let evmChainName: [UInt32: String] = [
        SpectraChainID.ethereum:       "Ethereum",
        SpectraChainID.arbitrum:       "Arbitrum",
        SpectraChainID.optimism:       "Optimism",
        SpectraChainID.avalanche:      "Avalanche",
        SpectraChainID.base:           "Base",
        SpectraChainID.ethereumClassic: "Ethereum Classic",
        SpectraChainID.bsc:            "BNB Chain",
        SpectraChainID.hyperliquid:    "Hyperliquid",
    ]

    private static let evmNativeSymbol: [UInt32: String] = [
        SpectraChainID.ethereum:        "ETH",
        SpectraChainID.arbitrum:        "ETH",
        SpectraChainID.optimism:        "ETH",
        SpectraChainID.base:            "ETH",
        SpectraChainID.avalanche:       "AVAX",
        SpectraChainID.ethereumClassic: "ETC",
        SpectraChainID.bsc:             "BNB",
        SpectraChainID.hyperliquid:     "HYPE",
    ]

    // MARK: - Amount-scaling helpers (mirrors WalletSendLayer, kept here for when that file is deleted)

    static func tokenAmountToRawString(_ amount: Double, decimals: Int) -> String {
        guard amount.isFinite, amount >= 0 else { return "0" }
        let formatted = String(format: "%.9f", amount)
        let parts = formatted.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? "0"
        var frac  = parts.count > 1 ? String(parts[1]) : ""
        if frac.count < decimals {
            frac += String(repeating: "0", count: decimals - frac.count)
        } else if frac.count > decimals {
            frac  = String(frac.prefix(decimals))
        }
        let combined = whole + frac
        let trimmed  = combined.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    static func nearToYoctoString(_ near: Double) -> String {
        let formatted = String(format: "%.12f", near)
        let noDecimal = formatted.replacingOccurrences(of: ".", with: "")
        let yoctoStr  = noDecimal + String(repeating: "0", count: 12)
        let trimmed   = yoctoStr.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    static func dotToPlanckString(_ dot: Double) -> String {
        "\(UInt64((dot * 1e10).rounded()))"
    }

    static func rustField(_ key: String, from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val  = obj[key] else { return "" }
        if let s = val as? String { return s }
        return "\(val)"
    }

    private struct EVMSendResult { let txid: String; let rawHex: String }
    private static func decodeEvmSendResult(_ json: String) -> EVMSendResult {
        EVMSendResult(
            txid:   rustField("txid", from: json),
            rawHex: rustField("raw_tx_hex", from: json)
        )
    }
}

// MARK: - Errors

enum MachineDriverError: LocalizedError {
    case storeGone
    case walletNotFound(UUID)
    case holdingNotFound(String)
    case missingSeedPhrase(String)
    case missingAddress(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .storeGone:               return "Send session expired."
        case .walletNotFound(let id):  return "Wallet not found: \(id)."
        case .holdingNotFound(let k):  return "Asset not found: \(k)."
        case .missingSeedPhrase(let c): return "This wallet's seed phrase is unavailable (\(c))."
        case .missingAddress(let c):   return "Unable to resolve signing address (\(c))."
        case .unsupported(let c):      return "\(c) sending is not supported yet."
        }
    }
}
