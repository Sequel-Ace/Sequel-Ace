//
//  SAScriptRunner+SPMySQL.swift
//  Sequel Ace
//
//  App-target-only bridge from SAScriptRunner's connection protocols to
//  SPMySQLConnection / SPMySQLResult, so the runner itself stays free of
//  framework types and builds in the Unit Tests target.
//

import Foundation

extension SPMySQLConnection: SAScriptQueryConnection {

    var scriptServerVersion: Int {
        Int(serverMajorVersion()) * 10000 + Int(serverMinorVersion()) * 100 + Int(serverReleaseVersion())
    }

    var scriptServerVersionString: String? { serverVersionString() }

    func runScriptStatement(_ statement: String, assertingDatabaseContext database: String?) -> SAScriptQueryResult? {
        let result = queryString(statement,
                                 usingEncoding: stringEncoding(),
                                 with: SPMySQLResultAsFastStreamingResult,
                                 assertingDatabaseContext: database) as? SPMySQLResult
        return result.map(SAScriptMySQLResult.init(result:))
    }

    func scriptFirstField(fromQuery query: String, assertingDatabase database: String?) -> Any? {
        getFirstField(fromQuery: query, assertingDatabase: database)
    }

    var scriptQueryErrored: Bool { queryErrored() }
    var scriptLastErrorID: Int { Int(lastErrorID()) }
    var scriptLastSqlstate: String? { lastSqlstate() }
    var scriptLastErrorMessage: String? { lastErrorMessage() }
    var scriptRowsAffectedByLastQuery: UInt64 { rowsAffectedByLastQuery() }
    var scriptLastQueryWasCancelled: Bool { lastQueryWasCancelled }
}

/// Wraps an SPMySQLResult (normally an SPMySQLStreamingResult) for the runner.
final class SAScriptMySQLResult: SAScriptQueryResult {
    private let result: SPMySQLResult

    init(result: SPMySQLResult) {
        self.result = result
    }

    var numberOfFields: Int { Int(result.numberOfFields()) }
    var fieldNames: [String] { (result.fieldNames() as? [String]) ?? [] }
    var queryExecutionTime: Double { result.queryExecutionTime() }

    func nextRow() -> [SAScriptCell]? {
        result.getRowAsArray().map { $0.map(SAScriptCell.init(mysqlValue:)) }
    }

    func cancelLoad() {
        (result as? SPMySQLStreamingResult)?.cancelLoad()
    }
}

extension SAScriptCell {
    init(mysqlValue value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let geometry as SPMySQLGeometryData:
            self = .binary(geometry.data() ?? Data())
        case let data as Data:
            self = .binary(data)
        case let string as String:
            self = .text(string)
        case let number as NSNumber:
            self = .text(number.stringValue)
        default:
            self = .text(String(describing: value))
        }
    }
}
