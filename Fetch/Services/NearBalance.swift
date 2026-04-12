import Foundation

struct NearHistorySnapshot: Equatable {
    let transactionHash: String
    let kind: TransactionKind
    let amount: Double
    let counterpartyAddress: String
    let createdAt: Date
    let status: TransactionStatus
}

struct NearHistoryDiagnostics: Equatable {
    let address: String
    let sourceUsed: String
    let transactionCount: Int
    let error: String?
}

struct NearTokenBalanceSnapshot: Equatable {
    let contractAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}

enum NearBalanceService {
    struct KnownTokenMetadata: Equatable {
        let symbol: String
        let name: String
        let tokenStandard: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }

    static func endpointCatalog() -> [String] {
        NearProvider.endpointCatalog()
    }

    static func rpcEndpointCatalog() -> [String] {
        NearProvider.rpcEndpoints
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        NearProvider.diagnosticsChecks()
    }

    static func parseHistoryResponse(_ data: Data, ownerAddress: String) throws -> [NearHistorySnapshot] {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let rows = historyRows(from: jsonObject)
        return rows.compactMap { snapshot(from: $0, ownerAddress: ownerAddress) }
    }

    private static func historyRows(from jsonObject: Any) -> [[String: Any]] {
        if let rows = jsonObject as? [[String: Any]] {
            return rows
        }
        guard let dictionary = jsonObject as? [String: Any] else {
            return []
        }
        if let rows = dictionary["txns"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["transactions"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["data"] as? [[String: Any]] {
            return rows
        }
        if let rows = dictionary["result"] as? [[String: Any]] {
            return rows
        }
        return []
    }

    private static func snapshot(from row: [String: Any], ownerAddress: String) -> NearHistorySnapshot? {
        guard let hash = stringValue(in: row, keys: ["transaction_hash", "hash", "receipt_id"]),
              !hash.isEmpty else {
            return nil
        }

        let owner = normalizedAddress(ownerAddress)
        let signer = normalizedAddress(
            stringValue(in: row, keys: ["signer_account_id", "predecessor_account_id", "signer_id", "signer"]) ?? ""
        )
        let receiver = normalizedAddress(
            stringValue(in: row, keys: ["receiver_account_id", "receiver_id", "receiver"]) ?? ""
        )

        let kind: TransactionKind
        let counterparty: String
        if signer == owner {
            kind = .send
            counterparty = receiver
        } else if receiver == owner {
            kind = .receive
            counterparty = signer
        } else if !signer.isEmpty {
            kind = .receive
            counterparty = signer
        } else {
            kind = .send
            counterparty = receiver
        }

        let depositYocto = depositText(in: row).flatMap { Decimal(string: $0) } ?? 0
        let amount = decimalToDouble(depositYocto / Decimal(string: "1000000000000000000000000")!)
        let createdAt = timestampDate(in: row) ?? Date()

        return NearHistorySnapshot(
            transactionHash: hash,
            kind: kind,
            amount: amount,
            counterpartyAddress: counterparty,
            createdAt: createdAt,
            status: .confirmed
        )
    }

    private static func depositText(in row: [String: Any]) -> String? {
        if let direct = stringValue(in: row, keys: ["deposit", "amount"]), !direct.isEmpty {
            return direct
        }

        if let actionsAggregate = row["actions_agg"] as? [String: Any],
           let aggregateDeposit = stringValue(in: actionsAggregate, keys: ["deposit", "total_deposit", "amount"]),
           !aggregateDeposit.isEmpty {
            return aggregateDeposit
        }

        if let actions = row["actions"] as? [[String: Any]] {
            for action in actions {
                if let deposit = stringValue(in: action, keys: ["deposit", "amount"]), !deposit.isEmpty {
                    return deposit
                }
                if let args = action["args"] as? [String: Any],
                   let nestedDeposit = stringValue(in: args, keys: ["deposit", "amount"]),
                   !nestedDeposit.isEmpty {
                    return nestedDeposit
                }
            }
        }

        return nil
    }

    private static func timestampDate(in row: [String: Any]) -> Date? {
        if let timestamp = numericTimestamp(in: row, keys: ["block_timestamp", "timestamp", "included_in_block_timestamp"]) {
            return normalizedDate(fromTimestamp: timestamp)
        }

        for nestedKey in ["block", "receipt_block", "included_in_block", "receipt"] {
            if let nested = row[nestedKey] as? [String: Any],
               let timestamp = numericTimestamp(in: nested, keys: ["block_timestamp", "timestamp"]) {
                return normalizedDate(fromTimestamp: timestamp)
            }
        }

        return nil
    }

    private static func normalizedDate(fromTimestamp timestamp: Double) -> Date? {
        guard timestamp > 0 else { return nil }
        if timestamp >= 1_000_000_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000_000_000.0)
        }
        if timestamp >= 1_000_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000.0)
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func numericTimestamp(in row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = row[key] as? NSNumber {
                return number.doubleValue
            }
            if let string = row[key] as? String, let parsed = Double(string) {
                return parsed
            }
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
            if let number = row[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func decimalToDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
