//
//  SADatabaseAssertion.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
@_implementationOnly import MySQLClient

@objcMembers
public final class SADatabaseAssertionError: NSObject {
    public let errorID: UInt
    public let message: String?
    public let sqlState: String?

    public init(errorID: UInt, message: String?, sqlState: String?) {
        self.errorID = errorID
        self.message = message
        self.sqlState = sqlState
    }
}

final class SADatabaseSessionValueLookup: NSObject {
    let data: Data?
    let error: SADatabaseAssertionError?

    init(data: Data?, error: SADatabaseAssertionError?) {
        self.data = data
        self.error = error
    }
}

@objcMembers
public final class SADatabaseAssertionState: NSObject {
    private enum DatabaseState {
        case unknown
        case none
        case selected(String?)
    }

    private var databaseState = DatabaseState.unknown
    private var connectionAddress: UInt?
    private var connectionThreadID: UInt64?

    @objc(assertDatabase:required:onMySQLConnection:errorStringEncodingValue:stringEncodingProvider:)
    public func assertDatabase(
        _ databaseName: String?,
        required: Bool,
        onMySQLConnection rawConnection: UnsafeMutableRawPointer,
        errorStringEncodingValue: UInt,
        stringEncodingProvider: (String) -> UInt
    ) -> SADatabaseAssertionError? {
        let connection = rawConnection.assumingMemoryBound(to: MYSQL.self)
        synchronizeConnectionIdentity(connection)

        let databaseStateKnown: Bool
        let databaseIsSelected: Bool
        let selectedDatabaseName: String?
        switch databaseState {
        case .unknown:
            databaseStateKnown = false
            databaseIsSelected = false
            selectedDatabaseName = nil
        case .none:
            databaseStateKnown = true
            databaseIsSelected = false
            selectedDatabaseName = nil
        case .selected(let name):
            databaseStateKnown = true
            databaseIsSelected = true
            selectedDatabaseName = name
        }

        var liveDatabaseLookup: SADatabaseSessionValueLookup?
        var databaseSelectionSucceeded = false
        let error = SADatabaseAssertion.assertDatabase(
            databaseName,
            required: required,
            selectedDatabaseName: selectedDatabaseName,
            databaseStateKnown: databaseStateKnown,
            databaseIsSelected: databaseIsSelected,
            stringEncodingProvider: stringEncodingProvider,
            queryActiveDatabaseData: {
                let lookup = self.querySessionValue(
                    "SELECT CAST(DATABASE() AS BINARY)",
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue,
                    queryErrorMessage: "Unable to query the selected database before asserting an empty database context.",
                    resultErrorMessage: "Unable to read the selected database before asserting an empty database context."
                )
                liveDatabaseLookup = lookup
                return lookup
            },
            queryClientCharacterSetData: {
                self.querySessionValue(
                    "SELECT CAST(@@character_set_client AS BINARY)",
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue,
                    queryErrorMessage: "Unable to query the connection character set before selecting the database.",
                    resultErrorMessage: "Unable to read the connection character set before selecting the database."
                )
            },
            executeSQL: { sql in
                self.execute(
                    sql,
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue,
                    fallbackMessage: "Unable to update the connection character set while selecting the database."
                )
            },
            selectDatabase: { databaseNameData in
                let selectionError = self.selectDatabase(
                    databaseNameData,
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue
                )
                databaseSelectionSucceeded = selectionError == nil
                return selectionError
            }
        )

        if databaseSelectionSucceeded, let databaseName, databaseName.isEmpty == false {
            databaseState = .selected(databaseName)
        } else if required,
                  databaseName?.isEmpty != false,
                  databaseStateKnown == false,
                  let liveDatabaseLookup,
                  liveDatabaseLookup.error == nil {
            databaseState = liveDatabaseLookup.data?.isEmpty == false ? .selected(nil) : .none
        }

        return error
    }

    @objc(recordSuccessfulQuery:onMySQLConnection:)
    public func recordSuccessfulQuery(
        _ query: String,
        onMySQLConnection rawConnection: UnsafeMutableRawPointer
    ) {
        let connection = rawConnection.assumingMemoryBound(to: MYSQL.self)
        synchronizeConnectionIdentity(connection)

        guard SADatabaseAssertion.queryCouldChangeDatabaseContext(query) else {
            return
        }

        let serverVersion = Int(mysql_get_server_version(connection))
        let serverInfo = mysql_get_server_info(connection).map { String(cString: $0) } ?? ""
        if SADatabaseAssertion.queryMayChangeDatabaseContext(
            query,
            serverVersion: serverVersion,
            serverIsMariaDB: serverInfo.range(of: "mariadb", options: .caseInsensitive) != nil
        ) {
            databaseState = .unknown
        }
    }

    private func synchronizeConnectionIdentity(_ connection: UnsafeMutablePointer<MYSQL>) {
        let currentAddress = UInt(bitPattern: connection)
        let currentThreadID = UInt64(mysql_thread_id(connection))
        if currentAddress != connectionAddress || currentThreadID != connectionThreadID {
            databaseState = .unknown
            connectionAddress = currentAddress
            connectionThreadID = currentThreadID
        }
    }

    private func querySessionValue(
        _ query: String,
        on connection: UnsafeMutablePointer<MYSQL>,
        errorStringEncodingValue: UInt,
        queryErrorMessage: String,
        resultErrorMessage: String
    ) -> SADatabaseSessionValueLookup {
        if realQuery(query, on: connection) != 0 {
            return .init(
                data: nil,
                error: currentError(
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue,
                    fallbackMessage: queryErrorMessage
                )
            )
        }

        guard let result = mysql_store_result(connection) else {
            return .init(
                data: nil,
                error: currentError(
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue,
                    fallbackMessage: resultErrorMessage
                )
            )
        }
        defer { mysql_free_result(result) }

        guard mysql_num_fields(result) >= 1,
              let row = mysql_fetch_row(result) else {
            return .init(
                data: nil,
                error: currentError(
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue,
                    fallbackMessage: resultErrorMessage
                )
            )
        }

        guard let value = row[0] else {
            return .init(data: nil, error: nil)
        }
        guard let lengths = mysql_fetch_lengths(result) else {
            return .init(
                data: nil,
                error: currentError(
                    on: connection,
                    errorStringEncodingValue: errorStringEncodingValue,
                    fallbackMessage: resultErrorMessage
                )
            )
        }

        return .init(data: Data(bytes: value, count: Int(lengths[0])), error: nil)
    }

    private func execute(
        _ sql: String,
        on connection: UnsafeMutablePointer<MYSQL>,
        errorStringEncodingValue: UInt,
        fallbackMessage: String
    ) -> SADatabaseAssertionError? {
        guard realQuery(sql, on: connection) != 0 else {
            return nil
        }
        return currentError(
            on: connection,
            errorStringEncodingValue: errorStringEncodingValue,
            fallbackMessage: fallbackMessage
        )
    }

    private func selectDatabase(
        _ databaseNameData: Data,
        on connection: UnsafeMutablePointer<MYSQL>,
        errorStringEncodingValue: UInt
    ) -> SADatabaseAssertionError? {
        let status = databaseNameData.withUnsafeBytes { bytes -> Int32 in
            guard let databaseNameBytes = bytes.bindMemory(to: CChar.self).baseAddress else {
                return 1
            }
            return mysql_select_db(connection, databaseNameBytes)
        }
        guard status != 0 else {
            return nil
        }
        return currentError(
            on: connection,
            errorStringEncodingValue: errorStringEncodingValue,
            fallbackMessage: "Unable to select the requested database."
        )
    }

    private func realQuery(_ query: String, on connection: UnsafeMutablePointer<MYSQL>) -> Int32 {
        query.utf8CString.withUnsafeBufferPointer { bytes in
            guard let queryBytes = bytes.baseAddress else {
                return 1
            }
            return mysql_real_query(connection, queryBytes, UInt(bytes.count - 1))
        }
    }

    private func currentError(
        on connection: UnsafeMutablePointer<MYSQL>,
        errorStringEncodingValue: UInt,
        fallbackMessage: String
    ) -> SADatabaseAssertionError {
        let errorID = UInt(mysql_errno(connection))
        guard errorID != 0 else {
            return .init(errorID: 0, message: fallbackMessage, sqlState: nil)
        }

        return .init(
            errorID: errorID,
            message: decodedCString(mysql_error(connection), encodingValue: errorStringEncodingValue),
            sqlState: decodedCString(mysql_sqlstate(connection), encodingValue: String.Encoding.isoLatin1.rawValue)
        )
    }

    private func decodedCString(_ bytes: UnsafePointer<CChar>?, encodingValue: UInt) -> String? {
        guard let bytes else {
            return nil
        }

        let data = Data(bytes: bytes, count: strlen(bytes))
        return String(data: data, encoding: String.Encoding(rawValue: encodingValue))
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }
}

final class SADatabaseAssertion: NSObject {
    private static let unexpectedDatabaseError = SADatabaseAssertionError(
        errorID: 1046,
        message: "A database is unexpectedly selected on this connection.",
        sqlState: "3D000"
    )

    private static let characterSetLookupError = SADatabaseAssertionError(
        errorID: 0,
        message: "Unable to determine the connection character set before selecting the database.",
        sqlState: nil
    )

    private static let databaseNameEncodingError = SADatabaseAssertionError(
        errorID: 0,
        message: "Unable to encode the database name before selecting it.",
        sqlState: nil
    )

    private static let identifierPattern = #"(`(?:``|[^`])*`|"(?:""|[^"])*"|[^\s;]+)"#
    private static let identifierSeparator = #"(?:\s+|(?=[`"]))"#
    private static let databaseContextChangingRegex = makeRegex(
        pattern: "(?is)^\\s*(?:USE\(identifierSeparator)\(identifierPattern)|DROP\\s+(?:DATABASE|SCHEMA)\(identifierSeparator)(?:IF\\s+EXISTS\(identifierSeparator))?\(identifierPattern))\\s*;?\\s*$"
    )

    static func safeCharacterSetName(from data: Data?) -> String? {
        guard let data,
              let name = String(data: data, encoding: .ascii),
              name.isEmpty == false,
              name.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 48...57, 65...90, 95, 97...122:
                      return true
                  default:
                      return false
                  }
              }) else {
            return nil
        }

        return name
    }

    static func assertDatabase(
        _ databaseName: String?,
        required: Bool,
        selectedDatabaseName: String?,
        databaseStateKnown: Bool,
        databaseIsSelected: Bool,
        stringEncodingProvider: (String) -> UInt,
        queryActiveDatabaseData: () -> SADatabaseSessionValueLookup,
        queryClientCharacterSetData: () -> SADatabaseSessionValueLookup,
        executeSQL: (String) -> SADatabaseAssertionError?,
        selectDatabase: (Data) -> SADatabaseAssertionError?
    ) -> SADatabaseAssertionError? {
        guard required else {
            return nil
        }

        guard let databaseName, databaseName.isEmpty == false else {
            if databaseStateKnown {
                return databaseIsSelected ? unexpectedDatabaseError : nil
            } else {
                let activeDatabaseLookup = queryActiveDatabaseData()
                if let lookupError = activeDatabaseLookup.error {
                    return lookupError
                }
                return activeDatabaseLookup.data?.isEmpty == false ? unexpectedDatabaseError : nil
            }
        }

        guard !databaseName.utf8.contains(0) else {
            return databaseNameEncodingError
        }

        if databaseStateKnown, selectedDatabaseName == databaseName {
            return nil
        }

        if let databaseNameData = encodedDatabaseName(databaseName, using: .ascii, nullTerminated: true) {
            return selectDatabase(databaseNameData)
        }

        // A negotiated CLIENT_SESSION_TRACK capability does not guarantee that
        // character_set_client is in session_track_system_variables. Query the
        // live value whenever a non-ASCII selection is actually required.
        let characterSetLookup = queryClientCharacterSetData()
        if let lookupError = characterSetLookup.error {
            return lookupError
        }

        guard let characterSetName = safeCharacterSetName(from: characterSetLookup.data) else {
            return characterSetLookupError
        }

        let clientStringEncodingValue = stringEncodingProvider(characterSetName)
        guard clientStringEncodingValue != 0 else {
            return characterSetLookupError
        }

        let clientStringEncoding = String.Encoding(rawValue: clientStringEncodingValue)
        if let databaseNameData = encodedDatabaseName(databaseName, using: clientStringEncoding, nullTerminated: true) {
            return selectDatabase(databaseNameData)
        }

        if let utf8SelectionError = executeSQL("SET CHARACTER_SET_CLIENT=utf8mb4") {
            return utf8SelectionError
        }

        guard let utf8DatabaseNameData = encodedDatabaseName(databaseName, using: .utf8, nullTerminated: true) else {
            let restoreError = executeSQL("SET CHARACTER_SET_CLIENT=\(characterSetName)")
            return restoreError ?? databaseNameEncodingError
        }

        let selectionError = selectDatabase(utf8DatabaseNameData)
        let restoreError = executeSQL("SET CHARACTER_SET_CLIENT=\(characterSetName)")

        // The selection failure is the primary error. A restoration failure only
        // replaces an otherwise successful selection, because leaking utf8mb4 into
        // the caller-managed session would make the target query unsafe to execute.
        return selectionError ?? restoreError
    }

    static func queryMayChangeDatabaseContext(
        _ query: String,
        serverVersion: Int,
        serverIsMariaDB: Bool
    ) -> Bool {
        // Most queries cannot affect the default database. Avoid allocating a
        // Character array for large payloads unless the first keyword is USE
        // or DROP, or leading comments require conservative inspection.
        guard queryCouldChangeDatabaseContext(query) else {
            return false
        }

        let queryWithoutComments = stripSQLComments(
            query,
            serverVersion: serverVersion,
            serverIsMariaDB: serverIsMariaDB
        )
        let range = NSRange(queryWithoutComments.startIndex..<queryWithoutComments.endIndex, in: queryWithoutComments)
        return databaseContextChangingRegex.firstMatch(in: queryWithoutComments, range: range) != nil
    }

    static func queryCouldChangeDatabaseContext(_ query: String) -> Bool {
        guard let start = query.firstIndex(where: { !$0.isWhitespace }) else {
            return false
        }

        let suffix = query[start...]
        if suffix.hasPrefix("#") || suffix.hasPrefix("--") || suffix.hasPrefix("/*") {
            return true
        }

        return hasLeadingKeyword("USE", in: query, at: start)
            || hasLeadingKeyword("DROP", in: query, at: start)
    }

    // Keep this implementation's lexical rules and executable-comment gates
    // mirrored in SPCustomQuerySQLClassifier.swift. The framework invalidates
    // connection assertion state; the app copy derives a batch's database.
    static func stripSQLComments(
        _ source: String,
        serverVersion: Int,
        serverIsMariaDB: Bool
    ) -> String {
        let characters = Array(source)
        var result = ""
        var index = 0
        var quote: Character?

        while index < characters.count {
            let character = characters[index]

            if let activeQuote = quote {
                result.append(character)
                if character == "\\", activeQuote != "`", index + 1 < characters.count {
                    index += 1
                    result.append(characters[index])
                } else if character == activeQuote {
                    if index + 1 < characters.count, characters[index + 1] == activeQuote {
                        index += 1
                        result.append(characters[index])
                    } else {
                        quote = nil
                    }
                }
                index += 1
                continue
            }

            if character == "'" || character == "\"" || character == "`" {
                quote = character
                result.append(character)
                index += 1
                continue
            }
            if character == "#" {
                result.append(" ")
                index += 1
                while index < characters.count, characters[index] != "\n" {
                    index += 1
                }
                continue
            }

            if character == "-",
               index + 1 < characters.count,
               characters[index + 1] == "-",
               (index + 2 == characters.count
                || characters[index + 2].unicodeScalars.allSatisfy({ $0.value <= 0x20 })) {
                result.append(" ")
                index += 2
                while index < characters.count, characters[index] != "\n" {
                    index += 1
                }
                continue
            }

            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                var executableContentStart: Int?
                var isMariaDBOnlyComment = false
                if index + 2 < characters.count, characters[index + 2] == "!" {
                    executableContentStart = index + 3
                } else if index + 3 < characters.count,
                          (characters[index + 2] == "M" || characters[index + 2] == "m"),
                          characters[index + 3] == "!" {
                    executableContentStart = index + 4
                    isMariaDBOnlyComment = true
                }

                var closingIndex = index + 2
                while closingIndex + 1 < characters.count,
                      !(characters[closingIndex] == "*" && characters[closingIndex + 1] == "/") {
                    closingIndex += 1
                }
                let hasClosingMarker = closingIndex + 1 < characters.count
                let contentEnd = hasClosingMarker ? closingIndex : characters.count

                result.append(" ")
                if var contentStart = executableContentStart {
                    let versionStart = contentStart
                    while contentStart < contentEnd,
                          characters[contentStart].unicodeScalars.count == 1,
                          characters[contentStart].unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) {
                        contentStart += 1
                    }
                    let hasVersionGate = contentStart > versionStart
                    let requiredVersion = hasVersionGate
                        ? Int(String(characters[versionStart..<contentStart]))
                        : nil
                    if shouldPreserveExecutableComment(
                        requiredVersion: requiredVersion,
                        hasVersionGate: hasVersionGate,
                        isMariaDBOnlyComment: isMariaDBOnlyComment,
                        serverVersion: serverVersion,
                        serverIsMariaDB: serverIsMariaDB
                    ), contentStart < contentEnd {
                        result.append(stripSQLComments(
                            String(characters[contentStart..<contentEnd]),
                            serverVersion: serverVersion,
                            serverIsMariaDB: serverIsMariaDB
                        ))
                    }
                    result.append(" ")
                }

                index = hasClosingMarker ? closingIndex + 2 : characters.count
                continue
            }

            result.append(character)
            index += 1
        }

        return result
    }

    private static func shouldPreserveExecutableComment(
        requiredVersion: Int?,
        hasVersionGate: Bool,
        isMariaDBOnlyComment: Bool,
        serverVersion: Int,
        serverIsMariaDB: Bool
    ) -> Bool {
        if isMariaDBOnlyComment && !serverIsMariaDB {
            return false
        }
        if hasVersionGate && requiredVersion == nil {
            return false
        }
        if let requiredVersion, requiredVersion > serverVersion {
            return false
        }
        if serverIsMariaDB,
           !isMariaDBOnlyComment,
           let requiredVersion,
           (50_700...99_999).contains(requiredVersion) {
            return false
        }
        return true
    }

    private static func hasLeadingKeyword(
        _ keyword: String,
        in query: String,
        at start: String.Index
    ) -> Bool {
        var queryIndex = start
        for keywordCharacter in keyword {
            guard queryIndex < query.endIndex,
                  query[queryIndex].lowercased() == keywordCharacter.lowercased() else {
                return false
            }
            query.formIndex(after: &queryIndex)
        }

        guard queryIndex < query.endIndex else {
            return true
        }
        return !isIdentifierCharacter(query[queryIndex])
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character == "$" || character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func makeRegex(pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid database assertion regular expression '\(pattern)': \(error)")
        }
    }

    private static func encodedDatabaseName(
        _ databaseName: String,
        using encoding: String.Encoding,
        nullTerminated: Bool
    ) -> Data? {
        guard var data = databaseName.data(using: encoding, allowLossyConversion: false),
              !data.contains(0) else {
            return nil
        }

        if nullTerminated {
            data.append(0)
        }
        return data
    }

}
