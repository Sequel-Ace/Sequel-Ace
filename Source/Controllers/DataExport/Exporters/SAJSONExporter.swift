//
//  SAJSONExporter.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Delegate of `SAJSONExporter`; SPExportController implements it. Every method is called on the main thread.
@objc protocol SAJSONExporterDelegate: NSObjectProtocol {
    func jsonExportProcessWillBegin(_ exporter: SAJSONExporter)
    func jsonExportProcessComplete(_ exporter: SAJSONExporter)
    func jsonExportProcessProgressUpdated(_ exporter: SAJSONExporter)
    func jsonExportProcessWillBeginWritingData(_ exporter: SAJSONExporter)
    @objc(cancelExportForFile:) func cancelExport(forFile fileName: String)
}

/// Exports a table, or a query / filtered result, as a JSON array of objects keyed by column name.
/// The JSON text itself is built by `SAJSONExportFormatter`; this class fetches the rows and writes them.
@objcMembers final class SAJSONExporter: SPExporter, @unchecked Sendable {

    weak var delegate: SAJSONExporterDelegate?

    /// Rows to export, the first row being the column names. `nil` for a table export.
    var jsonDataArray: [Any]?

    /// The table to export when `jsonDataArray` is `nil`.
    var jsonTableName: String?

    var jsonPrettyPrint = true

    /// Write this table's array as a member of a top-level object keyed by table name, for several
    /// tables sharing one file. The exporters sharing a file run one after another, so the first
    /// opens the object and the last closes it.
    var jsonKeyByTableName = false
    var jsonIsFirstTableInFile = true
    var jsonIsLastTableInFile = true

    init(delegate: SAJSONExporterDelegate) {
        self.delegate = delegate
        super.init()
    }

    override func exportOperation() {
        let dataArray = jsonDataArray
        let tableName = jsonTableName ?? ""

        if let dataArray {
            if dataArray.isEmpty { return }
        } else if tableName.isEmpty || (databaseName ?? "").isEmpty {
            return
        }

        notifyDelegate { $0.jsonExportProcessWillBegin(self) }
        exportProcessIsRunning = true

        var streamingResult: SPMySQLStreamingResult?
        let fieldNames: [String]
        var numericColumns: [Bool]?
        var characterSets: [Int] = []
        let totalRows: Int

        if let dataArray {
            fieldNames = ((dataArray.first as? [Any]) ?? []).map { "\($0)" }
            totalRows = dataArray.count - 1
        } else {
            let quotedTableName = (tableName as NSString).backtickQuoted() ?? tableName
            let count = connection.getFirstField(fromQuery: "SELECT COUNT(1) FROM \(quotedTableName)", assertingDatabase: databaseName)
            totalRows = (count as? NSString)?.integerValue ?? (count as? NSNumber)?.intValue ?? 0

            streamingResult = connection.streamingQueryString("SELECT * FROM \(quotedTableName)",
                                                              useLowMemoryBlockingStreaming: exportUsingLowMemoryBlockingStreaming,
                                                              assertingDatabase: databaseName) as? SPMySQLStreamingResult
            guard let streamingResult else {
                exportProcessIsRunning = false
                notifyDelegate { $0.jsonExportProcessComplete(self) }
                return
            }

            fieldNames = (streamingResult.fieldNames() as? [String]) ?? []
            // The result's own field types say which columns are numeric (BIT is excluded: its
            // values are bit strings such as "0101")
            let fieldDefinitions = (streamingResult.fieldDefinitions() as? [[String: Any]]) ?? []
            numericColumns = fieldDefinitions.map {
                let grouping = $0["typegrouping"] as? String
                return grouping == "integer" || grouping == "float"
            }
            characterSets = fieldDefinitions.map { ($0["charsetnr"] as? NSNumber)?.intValue ?? 63 }
        }

        let stringEncoding = String.Encoding(rawValue: connection.stringEncoding())

        let formatter = SAJSONExportFormatter(columnNames: fieldNames,
                                              numericColumns: numericColumns,
                                              tableKey: jsonKeyByTableName ? tableName : nil,
                                              prettyPrint: jsonPrettyPrint)

        write(formatter.opening(isFirstInFile: jsonIsFirstTableInFile))

        notifyDelegate { $0.jsonExportProcessWillBeginWritingData(self) }

        var rowsWritten = 0
        var lastProgressValue = 0.0

        while true {
            if exportOutputFile.fileHandleError != nil {
                let path = exportOutputFile.exportFilePath ?? ""
                onMainThreadSync { self.delegate?.cancelExport(forFile: path) }
                return
            }

            if isCancelled {
                if let streamingResult {
                    connection.cancelCurrentQuery()
                    streamingResult.cancelLoad()
                }
                return
            }

            let finished: Bool = autoreleasepool {
                let row: [Any]?
                if let dataArray {
                    row = rowsWritten < totalRows ? dataArray[rowsWritten + 1] as? [Any] : nil
                } else {
                    row = streamingResult?.getRowAsArray()
                }
                guard let row else { return true }

                let cells = row.enumerated().map { column, cell -> Any in
                    if let geometry = cell as? SPMySQLGeometryData {
                        return geometry.wktString() as Any
                    }
                    guard column < characterSets.count else { return cell }
                    return SAJSONExportFormatter.textCell(cell, characterSetNumber: characterSets[column], encoding: stringEncoding)
                }
                write(formatter.row(cells, index: rowsWritten))
                return false
            }
            if finished { break }

            rowsWritten += 1

            if totalRows > 0 {
                let progress = Double(rowsWritten) * (exportMaxProgress / Double(totalRows))
                if progress > lastProgressValue {
                    exportProgressValue = progress
                    lastProgressValue = progress
                }
            }

            notifyDelegate { $0.jsonExportProcessProgressUpdated(self) }
        }

        write(formatter.closing(rowCount: rowsWritten, isLastInFile: jsonIsLastTableInFile))

        exportOutputFile.exportFileHandle.synchronizeFile()

        exportProcessIsRunning = false

        notifyDelegate { $0.jsonExportProcessComplete(self) }
    }

    // MARK: - Private

    /// Calls the delegate asynchronously on the main thread, like the ObjC exporters'
    /// `performSelectorOnMainThread:withObject:waitUntilDone:NO`. Like those, the block keeps the
    /// exporter alive until the delegate has seen it: the operation queue releases it as soon as
    /// `exportOperation` returns.
    private func notifyDelegate(_ call: @escaping (SAJSONExporterDelegate) -> Void) {
        DispatchQueue.main.async {
            guard let delegate = self.delegate else { return }
            call(delegate)
        }
    }

    private func onMainThreadSync(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
