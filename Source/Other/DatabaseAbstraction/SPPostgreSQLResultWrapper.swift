//
//  SPPostgreSQLResultWrapper.swift
//  Sequel Ace
//

import Foundation

@objc(SPPostgreSQLResultWrapper)
final class SPPostgreSQLResultWrapper: NSObject, SPDatabaseResult {
    private var result: OpaquePointer?
    private let storedFieldNames: [String]
    private let numRows: Int32
    private let numFields: Int32
    private let queryTime: Double
    private var currentRow: UInt64 = 0

    @objc(initWithResult:queryTime:)
    init(result: OpaquePointer, queryTime: Double) {
        self.result = result
        self.queryTime = queryTime
        self.numRows = sp_postgresql_result_num_rows(result)
        self.numFields = sp_postgresql_result_num_fields(result)

        var names = [String]()
        for i in 0..<numFields {
            if let namePtr = sp_postgresql_result_field_name(result, i) {
                names.append(String(cString: namePtr))
                sp_postgresql_free_string(namePtr)
            } else {
                names.append("col\(i)")
            }
        }
        self.storedFieldNames = names
        super.init()
    }

    deinit {
        if let result {
            sp_postgresql_result_destroy(result)
            self.result = nil
        }
    }

    func numberOfFields() -> UInt { UInt(numFields) }
    func numberOfRows() -> UInt64 { UInt64(numRows) }
    func fieldNames() -> [String] { storedFieldNames }
    func queryExecutionTime() -> Double { queryTime }

    func seekToRow(_ targetRow: UInt64) {
        currentRow = min(targetRow, UInt64(numRows))
    }

    func getRowAsArray() -> [Any]? {
        guard currentRow < UInt64(numRows), let result else { return nil }
        let row = Int32(currentRow)
        currentRow += 1

        var arr = [Any]()
        arr.reserveCapacity(Int(numFields))
        for col in 0..<numFields {
            if let valPtr = sp_postgresql_result_get_value(result, row, col) {
                arr.append(String(cString: valPtr))
                sp_postgresql_free_string(valPtr)
            } else {
                arr.append(NSNull())
            }
        }
        return arr
    }

    func getRowAsDictionary() -> [AnyHashable: Any]? {
        guard currentRow < UInt64(numRows), let result else { return nil }
        let row = Int32(currentRow)
        currentRow += 1

        var dict = [AnyHashable: Any]()
        for col in 0..<numFields {
            let key = col < storedFieldNames.count ? storedFieldNames[Int(col)] : "col\(col)"
            if let valPtr = sp_postgresql_result_get_value(result, row, col) {
                dict[key] = String(cString: valPtr)
                sp_postgresql_free_string(valPtr)
            } else {
                dict[key] = NSNull()
            }
        }
        return dict
    }

    func getRow() -> Any? { getRowAsArray() }

    @objc(countByEnumeratingWithState:objects:count:)
    func countByEnumerating(with state: UnsafeMutablePointer<NSFastEnumerationState>,
                            objects buffer: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                            count len: Int) -> Int {
        if state.pointee.state == 0 {
            state.pointee.mutationsPtr = withUnsafeMutablePointer(to: &state.pointee.extra.0) { $0 }
            state.pointee.state = 1
            currentRow = 0
        }
        var count = 0
        while count < len {
            guard let row = getRowAsArray() else { break }
            buffer.advanced(by: count).pointee = row as NSArray
            count += 1
        }
        state.pointee.itemsPtr = buffer
        return count
    }
}
