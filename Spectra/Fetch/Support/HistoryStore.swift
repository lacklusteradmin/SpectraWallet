import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum HistoryDatabaseStoreError: LocalizedError {
    case unavailable
    case sqlite(message: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return NSLocalizedString("The history database is unavailable.", comment: "")
        case .sqlite(let message):
            let format = NSLocalizedString("SQLite error: %@", comment: "")
            return String(format: format, locale: .current, NSLocalizedString(message, comment: ""))
        }
    }
}

final class HistoryDatabaseStore {
    static let shared = HistoryDatabaseStore()

    private let databaseHandle: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "app.spectra.history-database")

    private init() {
        var configuredHandle: OpaquePointer?
        do {
            let databaseURL = try Self.databaseURL()
            let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            if sqlite3_open_v2(databaseURL.path, &configuredHandle, flags, nil) != SQLITE_OK {
                let message = Self.sqliteMessage(from: configuredHandle)
                sqlite3_close(configuredHandle)
                throw HistoryDatabaseStoreError.sqlite(message: message)
            }

            if let configuredHandle {
                try Self.execute(
                    sql: "PRAGMA journal_mode=WAL",
                    on: configuredHandle
                )
                try Self.execute(
                    sql: """
                        CREATE TABLE IF NOT EXISTS history_records (
                            id TEXT PRIMARY KEY NOT NULL,
                            wallet_id TEXT,
                            chain_name TEXT NOT NULL,
                            transaction_hash TEXT,
                            created_at REAL NOT NULL,
                            payload BLOB NOT NULL
                        )
                        """,
                    on: configuredHandle
                )
                try Self.execute(
                    sql: "CREATE INDEX IF NOT EXISTS idx_history_records_created_at ON history_records(created_at DESC)",
                    on: configuredHandle
                )
                try Self.execute(
                    sql: "CREATE INDEX IF NOT EXISTS idx_history_records_wallet_id ON history_records(wallet_id)",
                    on: configuredHandle
                )
                try Self.execute(
                    sql: "CREATE INDEX IF NOT EXISTS idx_history_records_chain_name ON history_records(chain_name)",
                    on: configuredHandle
                )
                try Self.execute(
                    sql: "CREATE INDEX IF NOT EXISTS idx_history_records_transaction_hash ON history_records(transaction_hash)",
                    on: configuredHandle
                )
            }
        } catch {
            if let configuredHandle {
                sqlite3_close(configuredHandle)
            }
            configuredHandle = nil
        }
        databaseHandle = configuredHandle
    }

    deinit {
        if let databaseHandle {
            sqlite3_close(databaseHandle)
        }
    }

    func replaceAll(with records: [PersistedTransactionRecord]) throws {
        guard let databaseHandle else { return }
        try queue.sync {
            try Self.beginTransaction(on: databaseHandle)
            do {
                try Self.execute(sql: "DELETE FROM history_records", on: databaseHandle)
                try upsert(records: records, on: databaseHandle)
                try Self.commitTransaction(on: databaseHandle)
            } catch {
                try? Self.rollbackTransaction(on: databaseHandle)
                throw error
            }
        }
    }

    func upsert(records: [PersistedTransactionRecord]) throws {
        guard let databaseHandle, !records.isEmpty else { return }
        try queue.sync {
            try Self.beginTransaction(on: databaseHandle)
            do {
                try upsert(records: records, on: databaseHandle)
                try Self.commitTransaction(on: databaseHandle)
            } catch {
                try? Self.rollbackTransaction(on: databaseHandle)
                throw error
            }
        }
    }

    func delete(ids: [UUID]) throws {
        guard let databaseHandle, !ids.isEmpty else { return }
        let normalizedIDs = ids.map { $0.uuidString.lowercased() }
        try queue.sync {
            let sql = "DELETE FROM history_records WHERE id = ?"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try Self.prepare(sql: sql, on: databaseHandle, statement: &statement)

            try Self.beginTransaction(on: databaseHandle)
            do {
                for id in normalizedIDs {
                    try Self.reset(statement)
                    try Self.bind(text: id, at: 1, in: statement)
                    try Self.step(statement, on: databaseHandle)
                }
                try Self.commitTransaction(on: databaseHandle)
            } catch {
                try? Self.rollbackTransaction(on: databaseHandle)
                throw error
            }
        }
    }

    func clearAll() throws {
        guard let databaseHandle else { return }
        try queue.sync {
            try Self.execute(sql: "DELETE FROM history_records", on: databaseHandle)
            try Self.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)", on: databaseHandle)
            try Self.execute(sql: "VACUUM", on: databaseHandle)
        }
    }

    func hardResetStorage() {
        try? clearAll()
    }

    func fetchAll() throws -> [PersistedTransactionRecord] {
        guard let databaseHandle else { return [] }
        return try queue.sync {
            let sql = """
                SELECT payload
                FROM history_records
                ORDER BY created_at DESC, id ASC
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try Self.prepare(sql: sql, on: databaseHandle, statement: &statement)

            var records: [PersistedTransactionRecord] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    let byteCount = sqlite3_column_bytes(statement, 0)
                    guard byteCount > 0,
                          let bytes = sqlite3_column_blob(statement, 0) else {
                        continue
                    }
                    let payload = Data(bytes: bytes, count: Int(byteCount))
                    if let decoded = try? decoder.decode(PersistedTransactionRecord.self, from: payload) {
                        records.append(decoded)
                    }
                    continue
                }
                if result == SQLITE_DONE {
                    return records
                }
                throw HistoryDatabaseStoreError.sqlite(message: Self.sqliteMessage(from: databaseHandle))
            }
        }
    }

    private func upsert(records: [PersistedTransactionRecord], on databaseHandle: OpaquePointer) throws {
        let sql = """
            INSERT INTO history_records (
                id,
                wallet_id,
                chain_name,
                transaction_hash,
                created_at,
                payload
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                wallet_id = excluded.wallet_id,
                chain_name = excluded.chain_name,
                transaction_hash = excluded.transaction_hash,
                created_at = excluded.created_at,
                payload = excluded.payload
            """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try Self.prepare(sql: sql, on: databaseHandle, statement: &statement)

        for record in records {
            let payload = try encoder.encode(record)
            try Self.reset(statement)
            try Self.bind(text: record.id.uuidString.lowercased(), at: 1, in: statement)
            try Self.bind(optionalText: record.walletID?.uuidString.lowercased(), at: 2, in: statement)
            try Self.bind(text: record.chainName, at: 3, in: statement)
            try Self.bind(optionalText: record.transactionHash?.lowercased(), at: 4, in: statement)
            try Self.bind(double: record.createdAt.timeIntervalSince1970, at: 5, in: statement)
            try Self.bind(blob: payload, at: 6, in: statement)
            try Self.step(statement, on: databaseHandle)
        }
    }

    private static func databaseURL() throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let spectraDirectory = appSupportDirectory.appendingPathComponent("Spectra", isDirectory: true)
        try FileManager.default.createDirectory(at: spectraDirectory, withIntermediateDirectories: true)
        return spectraDirectory.appendingPathComponent("history.sqlite", isDirectory: false)
    }

    private static func deleteStorageFiles() {
        guard let baseURL = try? databaseURL() else { return }
        let fileManager = FileManager.default
        let walURL = URL(fileURLWithPath: baseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: baseURL.path + "-shm")
        try? fileManager.removeItem(at: walURL)
        try? fileManager.removeItem(at: shmURL)
        try? fileManager.removeItem(at: baseURL)
    }

    private static func beginTransaction(on databaseHandle: OpaquePointer) throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION", on: databaseHandle)
    }

    private static func commitTransaction(on databaseHandle: OpaquePointer) throws {
        try execute(sql: "COMMIT TRANSACTION", on: databaseHandle)
    }

    private static func rollbackTransaction(on databaseHandle: OpaquePointer) throws {
        try execute(sql: "ROLLBACK TRANSACTION", on: databaseHandle)
    }

    private static func execute(sql: String, on databaseHandle: OpaquePointer) throws {
        if sqlite3_exec(databaseHandle, sql, nil, nil, nil) != SQLITE_OK {
            throw HistoryDatabaseStoreError.sqlite(message: sqliteMessage(from: databaseHandle))
        }
    }

    private static func prepare(sql: String, on databaseHandle: OpaquePointer, statement: inout OpaquePointer?) throws {
        if sqlite3_prepare_v2(databaseHandle, sql, -1, &statement, nil) != SQLITE_OK {
            throw HistoryDatabaseStoreError.sqlite(message: sqliteMessage(from: databaseHandle))
        }
    }

    private static func reset(_ statement: OpaquePointer?) throws {
        guard let statement else { throw HistoryDatabaseStoreError.unavailable }
        if sqlite3_reset(statement) != SQLITE_OK {
            throw HistoryDatabaseStoreError.sqlite(message: "Failed to reset SQLite statement.")
        }
        if sqlite3_clear_bindings(statement) != SQLITE_OK {
            throw HistoryDatabaseStoreError.sqlite(message: "Failed to clear SQLite statement bindings.")
        }
    }

    private static func step(_ statement: OpaquePointer?, on databaseHandle: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw HistoryDatabaseStoreError.sqlite(message: sqliteMessage(from: databaseHandle))
        }
    }

    private static func bind(text: String, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw HistoryDatabaseStoreError.sqlite(message: "Failed to bind text value.")
        }
    }

    private static func bind(optionalText: String?, at index: Int32, in statement: OpaquePointer?) throws {
        guard let optionalText else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw HistoryDatabaseStoreError.sqlite(message: "Failed to bind null value.")
            }
            return
        }
        try bind(text: optionalText, at: index, in: statement)
    }

    private static func bind(double: Double, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_double(statement, index, double) == SQLITE_OK else {
            throw HistoryDatabaseStoreError.sqlite(message: "Failed to bind numeric value.")
        }
    }

    private static func bind(blob: Data, at index: Int32, in statement: OpaquePointer?) throws {
        let result = blob.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(blob.count), SQLITE_TRANSIENT)
        }
        guard result == SQLITE_OK else {
            throw HistoryDatabaseStoreError.sqlite(message: "Failed to bind blob value.")
        }
    }

    private static func sqliteMessage(from databaseHandle: OpaquePointer?) -> String {
        guard let databaseHandle, let cString = sqlite3_errmsg(databaseHandle) else {
            return "Unknown SQLite error"
        }
        return String(cString: cString)
    }
}
