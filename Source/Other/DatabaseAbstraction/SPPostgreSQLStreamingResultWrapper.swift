//
//  SPPostgreSQLStreamingResultWrapper.swift
//  Sequel Ace
//

import Foundation

@objc(SPPostgreSQLStreamingResultWrapper)
final class SPPostgreSQLStreamingResultWrapper: NSObject, SPDatabaseResult {
    private var result: OpaquePointer?
    private let storedFieldNames: [String]
    private let numFields: Int32
    private let queryTime: Double
    private var totalRowsFetched: UInt64 = 0
    private var currentBatchSize: Int32 = 0
    private var batchRowIndex: Int32 = 0

    @objc(initWithStreamingResult:queryTime:)
    init(streamingResult: OpaquePointer, queryTime: Double) {
        self.result = streamingResult
        self.queryTime = queryTime
        self.numFields = sp_postgresql_streaming_result_num_fields(streamingResult)

        var names = [String]()
        for i in 0..<numFields {
            if let namePtr = sp_postgresql_streaming_result_field_name(streamingResult, i) {
                names.append(String(cString: namePtr))
                sp_postgresql_free_string(namePtr)
            } else {
                names.append("col\(i)")
            }
        }
        self.storedFieldNames = names
        super.init()
        fetchNextBatch()
    }

    deinit {
        if let result {
            sp_postgresql_streaming_result_destroy(result)
            self.result = nil
        }
    }

    @objc func markConnectionDisconnected() {
        if let result {
            sp_postgresql_streaming_result_mark_disconnected(result)
        }
    }

    private func fetchNextBatch() {
        guard let result, sp_postgresql_streaming_result_has_more(result) != 0 else {
            currentBatchSize = 0
            return
        }
        let rows = sp_postgresql_streaming_result_next_batch(result, nil, nil)
        currentBatchSize = max(rows, 0)
        batchRowIndex = 0
    }

    func numberOfFields() -> UInt { UInt(numFields) }

    func numberOfRows() -> UInt64 {
        guard let result else { return totalRowsFetched }
        let total = sp_postgresql_streaming_result_total_rows(result)
        return total >= 0 ? UInt64(total) : totalRowsFetched
    }

    func fieldNames() -> [String] { storedFieldNames }
    func queryExecutionTime() -> Double { queryTime }
    func seekToRow(_ row: UInt64) { /* streaming results cannot seek backwards */ }

    func getRowAsArray() -> [Any]? {
        guard let result else { return nil }

        while batchRowIndex >= currentBatchSize {
            guard sp_postgresql_streaming_result_has_more(result) != 0 else { return nil }
            fetchNextBatch()
            if currentBatchSize == 0 { return nil }
        }

        let batchRow = batchRowIndex
        batchRowIndex += 1
        totalRowsFetched += 1

        var arr = [Any]()
        arr.reserveCapacity(Int(numFields))
        for col in 0..<numFields {
            if let valPtr = sp_postgresql_streaming_result_get_batch_value(result, batchRow, col) {
                arr.append(String(cString: valPtr))
                sp_postgresql_free_string(valPtr)
            } else {
                arr.append(NSNull())
            }
        }
        return arr
    }

    func getRowAsDictionary() -> [AnyHashable: Any]? {
        guard let row = getRowAsArray() else { return nil }
        var dict = [AnyHashable: Any]()
        for (index, value) in row.enumerated() where index < storedFieldNames.count {
            dict[storedFieldNames[index]] = value
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
