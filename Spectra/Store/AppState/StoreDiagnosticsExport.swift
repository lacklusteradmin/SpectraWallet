import Foundation

extension WalletStore {
    private func prettyJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return sanitizeDiagnosticsString(string)
    }

    private func sanitizeDiagnosticsString(_ input: String) -> String {
        let knownWords = Set(BIP39EnglishWordList.words.map { $0.lowercased() })
        let mutable = NSMutableString(string: input)

        func replaceMatches(pattern: String, replacement: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let matches = regex.matches(in: mutable as String, range: NSRange(location: 0, length: mutable.length))
            for match in matches.sorted(by: { $0.range.location > $1.range.location }) {
                mutable.replaceCharacters(in: match.range, with: replacement)
            }
        }

        replaceMatches(pattern: #"\b(?:xprv|yprv|zprv|tprv|uprv|vprv)[1-9A-HJ-NP-Za-km-z]{32,}\b"#, replacement: "[REDACTED_EXTENDED_PRIVATE_KEY]")
        replaceMatches(pattern: #"\b(?:0x)?[A-Fa-f0-9]{64}\b"#, replacement: "[REDACTED_PRIVATE_KEY]")

        let wordPattern = #"\b[a-zA-Z]{2,}\b"#
        guard let regex = try? NSRegularExpression(pattern: wordPattern) else {
            return mutable as String
        }

        let matches = regex.matches(in: mutable as String, range: NSRange(location: 0, length: mutable.length))
        guard !matches.isEmpty else {
            return mutable as String
        }

        let currentNSString = mutable
        var sequences: [[NSRange]] = []
        var current: [NSRange] = []
        for match in matches {
            let word = currentNSString.substring(with: match.range).lowercased()
            if knownWords.contains(word) {
                current.append(match.range)
            } else {
                if current.count >= 12 {
                    sequences.append(current)
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= 12 {
            sequences.append(current)
        }

        let replacementRanges = sequences.flatMap { $0 }.sorted { $0.location > $1.location }
        for range in replacementRanges {
            mutable.replaceCharacters(in: range, with: "[REDACTED_SEED_WORD]")
        }
        return mutable as String
    }

    func bitcoinDiagnosticsJSON() -> String? {
        let history = bitcoinHistoryDiagnosticsByWallet.values.map { item in
            [
                "walletID": item.walletID.uuidString,
                "identifier": item.identifier,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "nextCursor": item.nextCursor ?? "",
                "error": item.error ?? ""
            ]
        }
        let endpoints = bitcoinEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "networkMode": bitcoinNetworkMode.rawValue,
            "historyLastUpdatedAt": bitcoinHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": bitcoinEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func tronDiagnosticsJSON() -> String? {
        let history = tronHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "tronScanTxCount": item.tronScanTxCount,
                "tronScanTRC20Count": item.tronScanTRC20Count,
                "sourceUsed": item.sourceUsed,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = tronEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": tronHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": tronEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "lastSendErrorAt": tronLastSendErrorAt?.timeIntervalSince1970 ?? 0,
            "lastSendErrorDetails": tronLastSendErrorDetails ?? "",
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func solanaDiagnosticsJSON() -> String? {
        let history = solanaHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcCount": item.rpcCount,
                "sourceUsed": item.sourceUsed,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = solanaEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": solanaHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": solanaEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func litecoinDiagnosticsJSON() -> String? {
        let history = litecoinHistoryDiagnosticsByWallet.values.map { item in
            [
                "walletID": item.walletID.uuidString,
                "identifier": item.identifier,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "nextCursor": item.nextCursor ?? "",
                "error": item.error ?? ""
            ]
        }
        let endpoints = litecoinEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": litecoinHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": litecoinEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func dogecoinDiagnosticsJSON() -> String? {
        let history = dogecoinHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "identifier": item.identifier,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "nextCursor": item.nextCursor ?? "",
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = dogecoinEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": dogecoinHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": dogecoinEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func bitcoinCashDiagnosticsJSON() -> String? {
        let history = bitcoinCashHistoryDiagnosticsByWallet.values.map { item in
            [
                "walletID": item.walletID.uuidString,
                "identifier": item.identifier,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "nextCursor": item.nextCursor ?? "",
                "error": item.error ?? ""
            ]
        }
        let endpoints = bitcoinCashEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": bitcoinCashHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": bitcoinCashEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func bitcoinSVDiagnosticsJSON() -> String? {
        let history = bitcoinSVHistoryDiagnosticsByWallet.values.map { item in
            [
                "walletID": item.walletID.uuidString,
                "identifier": item.identifier,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "nextCursor": item.nextCursor ?? "",
                "error": item.error ?? ""
            ]
        }
        let endpoints = bitcoinSVEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": bitcoinSVHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": bitcoinSVEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func ethereumDiagnosticsJSON() -> String? {
        let history = ethereumHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcTransferCount": item.rpcTransferCount,
                "rpcError": item.rpcError ?? "",
                "blockscoutTransferCount": item.blockscoutTransferCount,
                "blockscoutError": item.blockscoutError ?? "",
                "etherscanTransferCount": item.etherscanTransferCount,
                "etherscanError": item.etherscanError ?? "",
                "ethplorerTransferCount": item.ethplorerTransferCount,
                "ethplorerError": item.ethplorerError ?? "",
                "sourceUsed": item.sourceUsed,
                "transferScanCount": item.transferScanCount,
                "decodedTransferCount": item.decodedTransferCount,
                "unsupportedTransferDropCount": item.unsupportedTransferDropCount,
                "decodingCompletenessRatio": item.decodingCompletenessRatio
            ]
        }
        let endpoints = ethereumEndpointHealthResults.map { item in
            [
                "label": item.label,
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": ethereumHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": ethereumEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func bnbDiagnosticsJSON() -> String? {
        let history = bnbHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcTransferCount": item.rpcTransferCount,
                "rpcError": item.rpcError ?? "",
                "blockscoutTransferCount": item.blockscoutTransferCount,
                "blockscoutError": item.blockscoutError ?? "",
                "etherscanTransferCount": item.etherscanTransferCount,
                "etherscanError": item.etherscanError ?? "",
                "ethplorerTransferCount": item.ethplorerTransferCount,
                "ethplorerError": item.ethplorerError ?? "",
                "sourceUsed": item.sourceUsed,
                "transferScanCount": item.transferScanCount,
                "decodedTransferCount": item.decodedTransferCount,
                "unsupportedTransferDropCount": item.unsupportedTransferDropCount,
                "decodingCompletenessRatio": item.decodingCompletenessRatio
            ]
        }
        let endpoints = bnbEndpointHealthResults.map { item in
            [
                "label": item.label,
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": bnbHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": bnbEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func arbitrumDiagnosticsJSON() -> String? {
        let history = arbitrumHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcTransferCount": item.rpcTransferCount,
                "rpcError": item.rpcError ?? "",
                "blockscoutTransferCount": item.blockscoutTransferCount,
                "blockscoutError": item.blockscoutError ?? "",
                "etherscanTransferCount": item.etherscanTransferCount,
                "etherscanError": item.etherscanError ?? "",
                "ethplorerTransferCount": item.ethplorerTransferCount,
                "ethplorerError": item.ethplorerError ?? "",
                "sourceUsed": item.sourceUsed,
                "transferScanCount": item.transferScanCount,
                "decodedTransferCount": item.decodedTransferCount,
                "unsupportedTransferDropCount": item.unsupportedTransferDropCount,
                "decodingCompletenessRatio": item.decodingCompletenessRatio
            ]
        }
        let endpoints = arbitrumEndpointHealthResults.map { item in
            [
                "label": item.label,
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": arbitrumHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": arbitrumEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func optimismDiagnosticsJSON() -> String? {
        let history = optimismHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcTransferCount": item.rpcTransferCount,
                "rpcError": item.rpcError ?? "",
                "blockscoutTransferCount": item.blockscoutTransferCount,
                "blockscoutError": item.blockscoutError ?? "",
                "etherscanTransferCount": item.etherscanTransferCount,
                "etherscanError": item.etherscanError ?? "",
                "ethplorerTransferCount": item.ethplorerTransferCount,
                "ethplorerError": item.ethplorerError ?? "",
                "sourceUsed": item.sourceUsed,
                "transferScanCount": item.transferScanCount,
                "decodedTransferCount": item.decodedTransferCount,
                "unsupportedTransferDropCount": item.unsupportedTransferDropCount,
                "decodingCompletenessRatio": item.decodingCompletenessRatio
            ]
        }
        let endpoints = optimismEndpointHealthResults.map { item in
            [
                "label": item.label,
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": optimismHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": optimismEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func avalancheDiagnosticsJSON() -> String? {
        let history = avalancheHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcTransferCount": item.rpcTransferCount,
                "rpcError": item.rpcError ?? "",
                "blockscoutTransferCount": item.blockscoutTransferCount,
                "blockscoutError": item.blockscoutError ?? "",
                "etherscanTransferCount": item.etherscanTransferCount,
                "etherscanError": item.etherscanError ?? "",
                "ethplorerTransferCount": item.ethplorerTransferCount,
                "ethplorerError": item.ethplorerError ?? "",
                "sourceUsed": item.sourceUsed,
                "transferScanCount": item.transferScanCount,
                "decodedTransferCount": item.decodedTransferCount,
                "unsupportedTransferDropCount": item.unsupportedTransferDropCount,
                "decodingCompletenessRatio": item.decodingCompletenessRatio
            ]
        }
        let endpoints = avalancheEndpointHealthResults.map { item in
            [
                "label": item.label,
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": avalancheHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": avalancheEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func hyperliquidDiagnosticsJSON() -> String? {
        let history = hyperliquidHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcTransferCount": item.rpcTransferCount,
                "rpcError": item.rpcError ?? "",
                "blockscoutTransferCount": item.blockscoutTransferCount,
                "blockscoutError": item.blockscoutError ?? "",
                "etherscanTransferCount": item.etherscanTransferCount,
                "etherscanError": item.etherscanError ?? "",
                "ethplorerTransferCount": item.ethplorerTransferCount,
                "ethplorerError": item.ethplorerError ?? "",
                "sourceUsed": item.sourceUsed,
                "transferScanCount": item.transferScanCount,
                "decodedTransferCount": item.decodedTransferCount,
                "unsupportedTransferDropCount": item.unsupportedTransferDropCount,
                "decodingCompletenessRatio": item.decodingCompletenessRatio
            ]
        }
        let endpoints = hyperliquidEndpointHealthResults.map { item in
            [
                "label": item.label,
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": hyperliquidHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": hyperliquidEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func etcDiagnosticsJSON() -> String? {
        let history = etcHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "rpcTransferCount": item.rpcTransferCount,
                "rpcError": item.rpcError ?? "",
                "blockscoutTransferCount": item.blockscoutTransferCount,
                "blockscoutError": item.blockscoutError ?? "",
                "etherscanTransferCount": item.etherscanTransferCount,
                "etherscanError": item.etherscanError ?? "",
                "ethplorerTransferCount": item.ethplorerTransferCount,
                "ethplorerError": item.ethplorerError ?? "",
                "sourceUsed": item.sourceUsed,
                "transferScanCount": item.transferScanCount,
                "decodedTransferCount": item.decodedTransferCount,
                "unsupportedTransferDropCount": item.unsupportedTransferDropCount,
                "decodingCompletenessRatio": item.decodingCompletenessRatio
            ]
        }
        let endpoints = etcEndpointHealthResults.map { item in
            [
                "label": item.label,
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": etcHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": etcEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func cardanoDiagnosticsJSON() -> String? {
        let history = cardanoHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = cardanoEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": cardanoHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": cardanoEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func xrpDiagnosticsJSON() -> String? {
        let history = xrpHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = xrpEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": xrpHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": xrpEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func stellarDiagnosticsJSON() -> String? {
        let history = stellarHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = stellarEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": stellarHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": stellarEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func moneroDiagnosticsJSON() -> String? {
        let history = moneroHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = moneroEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": moneroHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": moneroEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func suiDiagnosticsJSON() -> String? {
        let history = suiHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = suiEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": suiHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": suiEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func aptosDiagnosticsJSON() -> String? {
        let history = aptosHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = aptosEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": aptosHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": aptosEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func tonDiagnosticsJSON() -> String? {
        let history = tonHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = tonEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": tonHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": tonEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func icpDiagnosticsJSON() -> String? {
        let history = icpHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = icpEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": icpHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": icpEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func nearDiagnosticsJSON() -> String? {
        let history = nearHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = nearEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": nearHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": nearEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    func polkadotDiagnosticsJSON() -> String? {
        let history = polkadotHistoryDiagnosticsByWallet.map { (walletID, item) in
            [
                "walletID": walletID.uuidString,
                "address": item.address,
                "sourceUsed": item.sourceUsed,
                "transactionCount": item.transactionCount,
                "error": item.error ?? ""
            ] as [String: Any]
        }
        let endpoints = polkadotEndpointHealthResults.map { item in
            [
                "endpoint": item.endpoint,
                "reachable": item.reachable,
                "statusCode": item.statusCode ?? -1,
                "detail": item.detail
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "historyLastUpdatedAt": polkadotHistoryDiagnosticsLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "endpointsLastUpdatedAt": polkadotEndpointHealthLastUpdatedAt?.timeIntervalSince1970 ?? 0,
            "history": history,
            "endpoints": endpoints
        ]
        return prettyJSONString(from: payload)
    }

    // Writes an on-device diagnostics JSON bundle users can export for support/debugging.
    func exportDiagnosticsBundle() throws -> URL {
        let payload = buildDiagnosticsBundlePayload()
        let data = try Self.diagnosticsBundleEncoder.encode(payload)
        let stamp = Self.exportFilenameTimestampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = try diagnosticsBundleExportsDirectoryURL()
            .appendingPathComponent("spectra-diagnostics-\(stamp)")
            .appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func diagnosticsBundleExportsDirectoryURL() throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseDirectory
            .appendingPathComponent("Diagnostics Bundles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func diagnosticsBundleExportURLs() -> [URL] {
        guard let directory = try? diagnosticsBundleExportsDirectoryURL(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    func deleteDiagnosticsBundleExport(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func importDiagnosticsBundle(from url: URL) throws -> DiagnosticsBundlePayload {
        let data = try Data(contentsOf: url)
        let payload = try Self.diagnosticsBundleDecoder.decode(DiagnosticsBundlePayload.self, from: data)
        lastImportedDiagnosticsBundle = payload
        return payload
    }

    private func buildDiagnosticsBundlePayload() -> DiagnosticsBundlePayload {
        let info = Bundle.main.infoDictionary ?? [:]
        let appVersion = (info["CFBundleShortVersionString"] as? String) ?? "unknown"
        let buildNumber = (info["CFBundleVersion"] as? String) ?? "unknown"

        let metadata = DiagnosticsEnvironmentMetadata(
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier,
            pricingProvider: pricingProvider.rawValue,
            selectedFiatCurrency: selectedFiatCurrency.rawValue,
            walletCount: wallets.count,
            transactionCount: transactions.count
        )

        return DiagnosticsBundlePayload(
            schemaVersion: 1,
            generatedAt: Date(),
            environment: metadata,
            chainDegradedMessages: diagnostics.chainDegradedMessages,
            bitcoinDiagnosticsJSON: bitcoinDiagnosticsJSON() ?? "{}",
            bitcoinSVDiagnosticsJSON: bitcoinSVDiagnosticsJSON() ?? "{}",
            litecoinDiagnosticsJSON: litecoinDiagnosticsJSON() ?? "{}",
            ethereumDiagnosticsJSON: ethereumDiagnosticsJSON() ?? "{}",
            arbitrumDiagnosticsJSON: arbitrumDiagnosticsJSON() ?? "{}",
            optimismDiagnosticsJSON: optimismDiagnosticsJSON() ?? "{}",
            bnbDiagnosticsJSON: bnbDiagnosticsJSON() ?? "{}",
            avalancheDiagnosticsJSON: avalancheDiagnosticsJSON() ?? "{}",
            hyperliquidDiagnosticsJSON: hyperliquidDiagnosticsJSON() ?? "{}",
            tronDiagnosticsJSON: tronDiagnosticsJSON() ?? "{}",
            solanaDiagnosticsJSON: solanaDiagnosticsJSON() ?? "{}",
            stellarDiagnosticsJSON: stellarDiagnosticsJSON() ?? "{}"
        )
    }
}
