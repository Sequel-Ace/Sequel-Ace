//
//  Created by Luis Aguiniga on 2024.07.05.
//  Copyright © 2024 Sequel-Ace. All rights reserved.
//

import Foundation
import FMDB
import OSLog

/// Persists the per-column display formats in an SQLite store in the
/// application-support folder. The store is a convenience: when it cannot
/// be opened or created - the folder is not writable, the file is damaged -
/// the manager carries on without it: the formats chosen in the running
/// session are kept in memory, so the table content and its column menu agree
/// with what the user picked, they are simply gone after the next launch. It
/// never terminates the app; the first problem with the store is handed to
/// `problems`, which the app shows.
@objc final class SQLiteDisplayFormatManager: NSObject {
    typealias SchemaBuilder = (_ db: FMDatabase, _ schemaVersion: Int) throws -> Int

    private static let sqliteTableName = "ColumnDisplayOverrides"
    /// The store's file name; the app-only `sharedInstance` in
    /// SASQLiteSharedStoreLocation.swift places it in the application-support folder.
    static let dbFileName = "ColumnDisplayOverrides.db"
    static let log = OSLog(subsystem: "com.sequel-ace.sequel-ace", category: "DisplayFormatManager")

    /// The store, or `nil` when it turned out to be unusable.
    private let queue: FMDatabaseQueue?
    /// Guards the formats chosen in this session.
    private let stateLock = NSLock()
    /// The formats chosen in this session, per table and column. They answer
    /// every read, whether or not they reached the store, so a store that is
    /// unusable or refuses a write does not make the column menu and the
    /// installed formatter disagree with what the user just picked.
    private var sessionOverrides: [SADisplayFormatTableKey: [String: String]] = [:]
    /// Where the store lives, for the problems reported about it.
    private let databasePath: String?
    /// Receives the first problem with the store: one that left the manager
    /// without a store, or a change the store refused. A single failed read is
    /// only logged: the store stays in place and the query may well succeed
    /// again - a store that is really gone refuses the next write, which is
    /// reported.
    let problems = SASQLiteStoreProblemReporter()

    /// Opens or creates the store at `databasePath`. A `nil` path, a file
    /// that cannot be opened, a schema that cannot be created or a table
    /// without the columns the manager reads leaves the manager without a
    /// store, and is reported to `problems`. The app uses `sharedInstance`,
    /// declared in the app-target-only SASQLiteSharedStoreLocation.swift.
    init(databasePath: String?) {
        self.databasePath = databasePath
        var problem: SASQLiteStoreProblem?
        if let databasePath {
            queue = Self.openStore(at: databasePath, problem: &problem)
        } else {
            queue = nil
            problem = SASQLiteStoreProblem(kind: .noLocation, path: nil, reason: nil)
        }
        super.init()
        if let problem {
            problems.report(problem)
        }
    }

    /// Whether formats are persisted; `false` when the store is unusable.
    var isPersistent: Bool {
        queue != nil
    }

    /// Returns the display format of one column: the one chosen in this
    /// session, otherwise the stored one, or `nil` when there is neither.
    @objc func displayOverrideFor(hostName: String, databaseName: String, tableName: String, columnName: String) -> String? {
        let key = SADisplayFormatTableKey(hostName: hostName, databaseName: databaseName, tableName: tableName)
        if let chosen = stateLock.withLock({ sessionOverrides[key]?[columnName] }) {
            return chosen
        }
        guard let queue else {
            return nil
        }
        var found: String? = nil

        let sql = """
            SELECT hostName, databaseName, tableName, columnName, format
            FROM \(Self.sqliteTableName)
            WHERE  hostName=? and databaseName=? and tableName=? and columnName=?
            ORDER BY id DESC
            """
        queue.inDatabase { db in
            do {
                let rs = try db.executeQuery(sql, values: [hostName, databaseName, tableName, columnName])
                while rs.next() {
                    if let format = rs.string(forColumn: "format") {
                        found = format
                        break
                    }
                }
                rs.close()
            }
            catch {
                Self.log.error("Query '\(sql), failed with error: \(error.localizedDescription)")
            }
        }
        queue.close()

        return found
    }

    /// Returns the display formats of a table's columns, keyed by column name:
    /// the stored ones, with the ones chosen in this session on top. Empty when
    /// there are neither.
    @objc func allDisplayOverridesFor(hostName: String, databaseName: String, tableName: String) -> [String:String] {
        let key = SADisplayFormatTableKey(hostName: hostName, databaseName: databaseName, tableName: tableName)
        let chosen = stateLock.withLock { sessionOverrides[key] ?? [:] }
        guard let queue else {
            return chosen
        }
        var formats = [String:String]()

        let sql = """
            SELECT hostName, databaseName, tableName, columnName, format
            FROM \(Self.sqliteTableName)
            WHERE  hostName=? and databaseName=? and tableName=?
            ORDER BY id DESC
            """

        queue.inDatabase { db in
            do {
                let rs = try db.executeQuery(sql, values: [hostName, databaseName, tableName])
                while rs.next() {
                    guard let columnName = rs.string(forColumn: "columnName"), let format = rs.string(forColumn: "format") else {
                        continue
                    }
                    formats[columnName] = format
                }
                rs.close()
            }
            catch {
                Self.log.error("Query '\(sql), failed with error: \(error.localizedDescription)")
            }
        }
        queue.close()

        formats.merge(chosen) { _, chosenFormat in chosenFormat }
        return formats
    }

    /// Sets `format` as the display format of one column, replacing an earlier
    /// one; an empty format means no override. It holds for the running session
    /// either way, and is stored when there is a store; a failed write is logged
    /// and reported to `problems`.
    @objc func replaceOverrideFor(hostName: String, databaseName: String, tableName: String, colName: String, format: String) {
        let key = SADisplayFormatTableKey(hostName: hostName, databaseName: databaseName, tableName: tableName)
        stateLock.withLock {
            sessionOverrides[key, default: [:]][colName] = format
        }
        guard let queue else {
            return
        }
        let toAdd = [hostName, databaseName, tableName, colName, format];

        let sql = """
            INSERT OR REPLACE INTO \(Self.sqliteTableName) (hostName, databaseName, tableName, columnName, format) VALUES (?, ?, ?, ?, ?)
            """
        queue.inDatabase { db in
            do {
                try db.executeUpdate(sql, values: toAdd)
            }
            catch {
                Self.log.error("\(error.localizedDescription)")
                problems.report(SASQLiteStoreProblem(kind: .cannotSave, path: databasePath, reason: error.localizedDescription))
            }
        }
        queue.close()
    }

    /// Opens the store at `databasePath` and brings its schema up to date.
    /// Returns `nil` when the file cannot be opened or prepared - the folder
    /// does not exist, the file is not a database, the table cannot be
    /// created; the failure is logged and described in `problem`.
    private static func openStore(at databasePath: String, problem: inout SASQLiteStoreProblem?) -> FMDatabaseQueue? {
        guard let queue = FMDatabaseQueue(path: databasePath) else {
            log.error("Could not open \(databasePath). Column display formats are not persisted.")
            problem = SASQLiteStoreProblem(kind: .cannotOpen, path: databasePath, reason: nil)
            return nil
        }
        if let failure = setupDatabase(in: queue) {
            queue.close()
            problem = SASQLiteStoreProblem(kind: .cannotUse, path: databasePath, reason: failure)
            return nil
        }
        return queue
    }

    /// Creates the table when the store's schema version predates it, records the
    /// new version and verifies the table. Returns the description of the step
    /// that failed, which is logged, or `nil` when the store is ready.
    private static func setupDatabase(in queue: FMDatabaseQueue) -> String? {
        let builder: SchemaBuilder = { (db, schemaVersion: Int) in
            db.beginTransaction()
            var newSchemaVersion = schemaVersion

            if schemaVersion < 1 {
                // IF NOT EXISTS: a launch that died between creating the table and
                // writing the version leaves the table in place at version 0.
                // Creating it again would fail and switch persistence off for good,
                // so the existing table is taken over and the version written again;
                // a table with another schema fails the column check below, leaves
                // the file as it was and the store unused.
                let createTableSql = """
                    CREATE TABLE IF NOT EXISTS \(sqliteTableName) (
                      id            INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                      hostName      TEXT NOT NULL,
                      databaseName  TEXT NOT NULL,
                      tableName     TEXT NOT NULL,
                      columnName    TEXT NOT NULL,
                      format        TEXT NOT NULL,

                      CONSTRAINT host_db_table UNIQUE (hostName, databaseName, tableName, columnName)
                    )
                    """
                let createIndexSql = """
                    CREATE UNIQUE INDEX IF NOT EXISTS host_db_table_idx ON \(sqliteTableName) (hostName, databaseName, tableName, columnName)
                    """

                do {
                    try db.executeUpdate(createTableSql)
                    try db.executeUpdate(createIndexSql)
                    // A table taken over has to be one this manager can read;
                    // otherwise nothing is committed and no version is written.
                    try verifyTable(db)
                }
                catch {
                    db.rollback()
                    throw error
                }

                newSchemaVersion = 1
                log.debug("self.newSchemaVersion \(newSchemaVersion)")
                log.info("Creating ColumnDisplayFormats Version 1 was successful!")
            }

            db.commit()
            return newSchemaVersion
        }

        var failure: String? = nil
        queue.inDatabase { db in
            do {
                let initialVersion = try loadCurrentSchemaVersion(db)
                let finalVersion = try builder(db, initialVersion)
                try finalizeSchemaVersion(db, initialVersion, finalVersion)
                try verifyTable(db)
            }
            catch {
                log.error("Preparing \(dbFileName) failed: \(error.localizedDescription). Column display formats are not persisted.")
                failure = error.localizedDescription
            }
        }
        queue.close()
        return failure
    }

    /// Reads the store's schema version from `PRAGMA user_version`; 0 for a new file.
    private static func loadCurrentSchemaVersion(_ db: FMDatabase) throws -> Int {
        var version = 0
        let rs = try db.executeQuery("PRAGMA user_version")
        if rs.next() {
            version = rs.long(forColumnIndex: 0)
            log.debug("startingSchemaVersion = \(version)")
        }
        rs.close()

        return version
    }

    /// Succeeds only when the table exists with every column the manager
    /// reads. A file whose schema version says the table was created, but
    /// whose table is missing or different, is not used: its formats could
    /// not be read, while writes might still land in it.
    private static func verifyTable(_ db: FMDatabase) throws {
        let rs = try db.executeQuery("SELECT id, hostName, databaseName, tableName, columnName, format FROM \(sqliteTableName) LIMIT 0")
        rs.close()
    }

    /// Writes `finalVersion` to `PRAGMA user_version` when the schema builder
    /// raised the version.
    private static func finalizeSchemaVersion(_ db: FMDatabase, _ initialVersion: Int, _ finalVersion: Int) throws {
        guard finalVersion != initialVersion, finalVersion > 0 else {
            return
        }

        let query = "PRAGMA user_version = \(finalVersion)"
        log.debug("query = \(query)")
        try db.executeUpdate(query)
    }
}


fileprivate extension FMDatabase {
    func executeQuery(_ sql: String) throws -> FMResultSet {
        try self.executeQuery(sql, values: nil)
    }

    func executeUpdate(_ sql: String) throws {
        try self.executeUpdate(sql, values: nil)
    }
}

/// One table of one database on one host: what the formats chosen in a
/// session are kept under.
private struct SADisplayFormatTableKey: Hashable {
    let hostName: String
    let databaseName: String
    let tableName: String
}

// MARK: - Store problems
//
// Shared by both SQLite managers. They live in this file because it is
// compiled into the app and into the Unit Tests target; the app-only
// SASQLiteSharedStoreLocation.swift shows the problems to the user.

/// The kinds of problem one of the app's SQLite stores can have, each with its
/// own explanation.
enum SASQLiteStoreProblemKind: Equatable {
    /// The data folder could not be found or created.
    case noLocation
    /// The file could not be opened.
    case cannotOpen
    /// The file opened but could not be prepared or read.
    case cannotUse
    /// A change could not be written to the file.
    case cannotSave
}

/// What went wrong with one of the app's SQLite stores, and the message that
/// tells the user about it.
final class SASQLiteStoreProblem: NSObject {
    /// What went wrong.
    let kind: SASQLiteStoreProblemKind
    /// The store's file; `nil` when there is no location.
    let path: String?
    /// The underlying error's description, when there is one.
    let reason: String?

    /// Describes a problem.
    ///
    /// - Parameters:
    ///   - kind: What went wrong.
    ///   - path: The store's file, if there is one.
    ///   - reason: The underlying error's description, if there is one. A
    ///     refused change always carries one.
    init(kind: SASQLiteStoreProblemKind, path: String?, reason: String?) {
        self.kind = kind
        self.path = path
        self.reason = reason
        super.init()
    }

    /// The message for the user: what went wrong, what it means for them, and
    /// what they can do about it.
    ///
    /// - Parameter consequence: What the problem means for the store's data,
    ///   such as that pins are not kept.
    /// - Returns: The paragraphs of the message.
    func message(consequence: String) -> String {
        // Unabbreviated on purpose: Sequel Ace is sandboxed, so its home
        // directory is the app's container and the store sits in the container's
        // Application Support folder. Abbreviating with a tilde would print
        // "~/Library/Application Support/Sequel Ace/Data/…", a path the user
        // would look for in vain.
        let file = path ?? ""
        var paragraphs: [String] = []
        switch kind {
        case .noLocation:
            paragraphs.append(NSLocalizedString("Sequel Ace could not find or create its data folder in Application Support.", comment: "SQLite store problem: the folder for the app's data files is missing"))
        case .cannotOpen:
            paragraphs.append(String(format: NSLocalizedString("Sequel Ace could not open the file “%@”.", comment: "SQLite store problem: the data file could not be opened; the argument is its path"), file))
        case .cannotUse:
            if let reason {
                paragraphs.append(String(format: NSLocalizedString("Sequel Ace could not use the file “%1$@”: %2$@", comment: "SQLite store problem: the data file could not be prepared or read; the arguments are its path and the error"), file, reason))
            } else {
                paragraphs.append(String(format: NSLocalizedString("Sequel Ace could not read the file “%@”.", comment: "SQLite store problem: the data file holds entries that cannot be read; the argument is its path"), file))
            }
        case .cannotSave:
            paragraphs.append(String(format: NSLocalizedString("Sequel Ace could not save to the file “%1$@”: %2$@", comment: "SQLite store problem: a change could not be written to the data file; the arguments are its path and the error"), file, reason ?? ""))
        }
        paragraphs.append(consequence)
        if kind != .noLocation {
            paragraphs.append(NSLocalizedString("Make sure the file and its folder can be written to.", comment: "SQLite store problem: advice for a file or folder that cannot be written to"))
        }
        if kind == .cannotUse || kind == .cannotSave {
            paragraphs.append(NSLocalizedString("If the file is damaged, quit Sequel Ace and move the file out of its folder; Sequel Ace creates a new one the next time it starts.", comment: "SQLite store problem: advice for a damaged data file"))
        }
        return paragraphs.joined(separator: "\n\n")
    }

    /// What Finder should show: the file when it exists, otherwise its folder
    /// when that exists; `nil` when neither does.
    var revealURL: URL? {
        guard let path else {
            return nil
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let folder = (path as NSString).deletingLastPathComponent
        return fileManager.fileExists(atPath: folder) ? URL(fileURLWithPath: folder, isDirectory: true) : nil
    }
}

/// Hands the first problem with a store to whoever shows it - once, so the
/// user is told once per launch. A problem found before anyone listens is
/// kept until someone does.
final class SASQLiteStoreProblemReporter {
    private let lock = NSLock()
    private var reported: SASQLiteStoreProblem?
    private var delivered = false
    private var handler: ((SASQLiteStoreProblem) -> Void)?

    /// The first problem reported, if any.
    var firstProblem: SASQLiteStoreProblem? {
        lock.withLock { reported }
    }

    /// Records a problem; only the first one is kept and handed on. The handler
    /// runs on the calling thread, outside the reporter's lock, and must not block.
    ///
    /// - Parameter problem: What went wrong.
    func report(_ problem: SASQLiteStoreProblem) {
        let deliver: ((SASQLiteStoreProblem) -> Void)? = lock.withLock {
            guard reported == nil else {
                return nil
            }
            reported = problem
            guard let handler else {
                return nil
            }
            delivered = true
            return handler
        }
        deliver?(problem)
    }

    /// Sets who is told about the first problem; one reported already is handed
    /// over at once.
    ///
    /// - Parameter handler: Receives the problem; it must not block.
    func onProblem(_ handler: @escaping (SASQLiteStoreProblem) -> Void) {
        let pending: SASQLiteStoreProblem? = lock.withLock {
            self.handler = handler
            guard let reported, !delivered else {
                return nil
            }
            delivered = true
            return reported
        }
        if let pending {
            handler(pending)
        }
    }
}

