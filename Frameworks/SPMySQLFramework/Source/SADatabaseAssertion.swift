//
//  SADatabaseAssertion.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

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

@objcMembers
public final class SADatabaseSessionValueLookup: NSObject {
    public let data: Data?
    public let error: SADatabaseAssertionError?

    public init(data: Data?, error: SADatabaseAssertionError?) {
        self.data = data
        self.error = error
    }
}

@objcMembers
public final class SADatabaseAssertion: NSObject {
    private static let noDatabaseError = SADatabaseAssertionError(
        errorID: 1046,
        message: "No database selected",
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

    @objc(safeCharacterSetNameFromData:)
    public static func safeCharacterSetName(from data: Data?) -> String? {
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

    @objc(assertDatabase:required:activeDatabaseData:connectorTracksSessionState:connectorCharacterSetData:stringEncodingProvider:queryActiveDatabaseData:queryClientCharacterSetData:executeSQL:selectDatabase:)
    public static func assertDatabase(
        _ databaseName: String?,
        required: Bool,
        activeDatabaseData: Data?,
        connectorTracksSessionState: Bool,
        connectorCharacterSetData: Data?,
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
            let selectedDatabaseData: Data?
            if connectorTracksSessionState {
                selectedDatabaseData = activeDatabaseData
            } else {
                let activeDatabaseLookup = queryActiveDatabaseData()
                if let lookupError = activeDatabaseLookup.error {
                    return lookupError
                }
                selectedDatabaseData = activeDatabaseLookup.data
            }
            return selectedDatabaseData?.isEmpty == false ? noDatabaseError : nil
        }

        guard !databaseName.utf8.contains(0) else {
            return databaseNameEncodingError
        }

        if connectorTracksSessionState, activeDatabaseMatches(
            databaseName,
            activeDatabaseData: activeDatabaseData,
            connectorCharacterSetData: connectorCharacterSetData,
            stringEncodingProvider: stringEncodingProvider
        ) {
            return nil
        }

        if let databaseNameData = encodedDatabaseName(databaseName, using: .ascii, nullTerminated: true) {
            return selectDatabase(databaseNameData)
        }

        let clientCharacterSetData: Data?
        if connectorTracksSessionState,
           safeCharacterSetName(from: connectorCharacterSetData) != nil {
            clientCharacterSetData = connectorCharacterSetData
        } else {
            let characterSetLookup = queryClientCharacterSetData()
            if let lookupError = characterSetLookup.error {
                return lookupError
            }
            clientCharacterSetData = characterSetLookup.data
        }

        guard let characterSetName = safeCharacterSetName(from: clientCharacterSetData) else {
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

    private static func activeDatabaseMatches(
        _ databaseName: String,
        activeDatabaseData: Data?,
        connectorCharacterSetData: Data?,
        stringEncodingProvider: (String) -> UInt
    ) -> Bool {
        guard let activeDatabaseData, activeDatabaseData.isEmpty == false else {
            return false
        }

        if encodedDatabaseName(databaseName, using: .utf8, nullTerminated: false) == activeDatabaseData {
            return true
        }

        guard let connectorCharacterSetName = safeCharacterSetName(from: connectorCharacterSetData) else {
            return false
        }

        let connectorStringEncoding = stringEncodingProvider(connectorCharacterSetName)
        guard connectorStringEncoding != 0 else {
            return false
        }

        let connectorEncoding = String.Encoding(rawValue: connectorStringEncoding)
        return encodedDatabaseName(databaseName, using: connectorEncoding, nullTerminated: false) == activeDatabaseData
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
