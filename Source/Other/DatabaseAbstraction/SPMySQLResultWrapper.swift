//
//  SPMySQLResultWrapper.swift
//  Sequel Ace
//

import Foundation

@objc(SPMySQLResultWrapper)
final class SPMySQLResultWrapper: NSObject, SPDatabaseResult {
    private let result: SPMySQLResult

    @objc(initWithResult:)
    init(result: SPMySQLResult) {
        self.result = result
        super.init()
    }

    @objc var underlyingResult: SPMySQLResult { result }

    func numberOfFields() -> UInt { result.numberOfFields() }
    func numberOfRows() -> UInt64 { result.numberOfRows() }
    func fieldNames() -> [String] { result.fieldNames() as? [String] ?? [] }
    func seekToRow(_ targetRow: UInt64) { result.seek(toRow: targetRow) }
    func getRow() -> Any? { result.getRow() }
    func getRowAsArray() -> [Any]? { result.getRowAsArray() as? [Any] }
    func getRowAsDictionary() -> [AnyHashable: Any]? { result.getRowAsDictionary() as? [AnyHashable: Any] }
    func queryExecutionTime() -> Double { result.queryExecutionTime() }

    @objc func setDefaultRowReturnType(_ type: Int) {
        let selector = NSSelectorFromString("setDefaultRowReturnType:")
        if result.responds(to: selector) {
            _ = result.perform(selector, with: type)
        }
    }

    @objc func setReturnDataAsStrings(_ asStrings: Bool) {
        let selector = NSSelectorFromString("setReturnDataAsStrings:")
        if result.responds(to: selector) {
            _ = result.perform(selector, with: asStrings)
        }
    }

    @objc(countByEnumeratingWithState:objects:count:)
    func countByEnumerating(with state: UnsafeMutablePointer<NSFastEnumerationState>,
                            objects buffer: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                            count len: Int) -> Int {
        let selector = NSSelectorFromString("countByEnumeratingWithState:objects:count:")
        guard result.responds(to: selector) else { return 0 }
        typealias EnumIMP = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSFastEnumerationState>, AutoreleasingUnsafeMutablePointer<AnyObject?>, UInt) -> UInt
        let imp = result.method(for: selector)
        let fn = unsafeBitCast(imp, to: EnumIMP.self)
        return Int(fn(result, selector, state, buffer, UInt(len)))
    }
}
