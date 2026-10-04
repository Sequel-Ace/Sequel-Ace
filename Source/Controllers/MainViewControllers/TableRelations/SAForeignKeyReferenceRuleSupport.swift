import Foundation

@objc final class SAForeignKeyReferenceRuleSupport: NSObject {
    @objc(requiresStandardForeignKeyReferencesWithMariaDB:serverVersionIsAtLeast84:restrictionQueryErrored:restrictionValue:)
    static func requiresStandardForeignKeyReferences(isMariaDB: Bool, serverVersionIsAtLeast84: Bool, restrictionQueryErrored: Bool, restrictionValue: Any?) -> Bool {
        guard !isMariaDB, serverVersionIsAtLeast84 else { return false }
        guard !restrictionQueryErrored else { return true }

        return restrictionEnforcesStandardReferences(restrictionValue)
    }

    @objc(singleColumnUniqueReferenceColumns:)
    static func singleColumnUniqueReferenceColumns(_ indexRows: NSArray) -> NSSet {
        var uniqueIndexRows: [String: [NSDictionary]] = [:]

        for case let indexRow as NSDictionary in indexRows {
            guard integerValue(indexRow["Non_unique"]) == 0 else { continue }
            guard let keyName = stringValue(indexRow["Key_name"]), !keyName.isEmpty else { continue }

            uniqueIndexRows[keyName, default: []].append(indexRow)
        }

        var columnNames = Set<String>()
        for indexRows in uniqueIndexRows.values {
            guard indexRows.count == 1, let indexRow = indexRows.first else { continue }

            if let subPart = indexRow["Sub_part"], !(subPart is NSNull), !String(describing: subPart).isEmpty {
                continue
            }

            guard let columnName = stringValue(indexRow["Column_name"]), !columnName.isEmpty else { continue }

            columnNames.insert(columnName)
        }

        return columnNames as NSSet
    }

    static func restrictionEnforcesStandardReferences(_ restrictionValue: Any?) -> Bool {
        guard let normalized = stringValue(restrictionValue)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !normalized.isEmpty else {
            return true
        }

        return !["0", "OFF", "FALSE"].contains(normalized)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }

        return String(describing: value)
    }

    private static func integerValue(_ value: Any?) -> Int {
        guard let value, !(value is NSNull) else { return 0 }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return Int(String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

@objc enum SAFieldRemovalQueryResult: Int {
    case succeeded
    case cancelled
    case failed
}

/// Immutable field-removal details plus sequencing and cancellation state.
///
/// `SPTableStructure` supplies thin bridges for its legacy query, error, and
/// reload calls; this type owns the cross-thread removal orchestration.
@objc final class SAFieldRemovalTask: NSObject {

    @objc let field: String
    @objc let foreignKeyName: String?
    @objc let table: String
    @objc let database: String

    private static let initialCancellationRetryDelay: TimeInterval = 0.025
    private static let maximumCancellationRetryDelay: TimeInterval = 1

    private let stateLock = NSLock()
    private let cancellationQueue = DispatchQueue(
        label: "com.sequel-ace.field-removal-query-cancellation",
        qos: .userInitiated
    )
    private var cancellationRequested = false
    private var queryIsAdmitted = false

    @objc(initWithField:foreignKeyName:table:database:)
    init(field: String, foreignKeyName: String?, table: String, database: String) {
        self.field = field
        self.foreignKeyName = foreignKeyName
        self.table = table
        self.database = database
        super.init()
    }

    @objc func cancel() {
        stateLock.lock()
        cancellationRequested = true
        stateLock.unlock()
    }

    /// Keeps cancellation attempts off the main queue and backs them off while
    /// an admitted query remains active.
    func requestQueryCancellation(_ cancellation: @escaping () -> Void) {
        scheduleCancellationAttempt(
            after: 0,
            nextRetryDelay: Self.initialCancellationRetryDelay,
            cancellation: cancellation
        )
    }

    /// Sequences the optional foreign-key removal and field removal while
    /// keeping legacy controller operations behind focused callbacks.
    @objc(runWithForeignKeyQuery:fieldQuery:foreignKeyFailure:fieldFailure:schemaRefresh:completion:)
    func run(foreignKeyQuery: () -> SAFieldRemovalQueryResult,
             fieldQuery: () -> SAFieldRemovalQueryResult,
             foreignKeyFailure: () -> Void,
             fieldFailure: () -> Void,
             schemaRefresh: () -> Void,
             completion: () -> Void) {
        var previousQueryWasCancelled = false
        var schemaMayHaveChanged = false

        if foreignKeyName != nil,
           let result = runQueryIfAllowed(afterPreviousCancellation: false,
                                          operation: foreignKeyQuery) {
            switch result {
            case .succeeded:
                schemaMayHaveChanged = true
            case .cancelled:
                previousQueryWasCancelled = true
                schemaMayHaveChanged = true
            case .failed:
                foreignKeyFailure()
            }
        }

        if let result = runQueryIfAllowed(
            afterPreviousCancellation: previousQueryWasCancelled,
            operation: fieldQuery
        ) {
            switch result {
            case .succeeded, .cancelled:
                schemaMayHaveChanged = true
            case .failed:
                fieldFailure()
            }
        }

        if schemaMayHaveChanged {
            schemaRefresh()
        }

        if Thread.isMainThread {
            completion()
        } else {
            DispatchQueue.main.sync(execute: completion)
        }
    }

    /// Cancels an admitted query while preventing it from completing its
    /// transition to subsequent connection work. The cancellation closure
    /// must not call back into this task.
    private func cancelAdmittedQuery(_ cancellation: () -> Void) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard cancellationRequested, queryIsAdmitted else {
            return false
        }
        cancellation()
        return true
    }

    private func scheduleCancellationAttempt(
        after delay: TimeInterval,
        nextRetryDelay: TimeInterval,
        cancellation: @escaping () -> Void
    ) {
        cancellationQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, cancelAdmittedQuery(cancellation) else {
                return
            }

            scheduleCancellationAttempt(
                after: nextRetryDelay,
                nextRetryDelay: min(nextRetryDelay * 2, Self.maximumCancellationRetryDelay),
                cancellation: cancellation
            )
        }
    }

    /// Runs a query only while this task remains active and the preceding
    /// query, if any, was not cancelled.
    private func runQueryIfAllowed(
        afterPreviousCancellation queryWasCancelled: Bool,
        operation: () -> SAFieldRemovalQueryResult
    ) -> SAFieldRemovalQueryResult? {
        stateLock.lock()
        guard !queryWasCancelled, !cancellationRequested else {
            stateLock.unlock()
            return nil
        }
        queryIsAdmitted = true
        stateLock.unlock()

        defer {
            stateLock.lock()
            queryIsAdmitted = false
            stateLock.unlock()
        }
        return operation()
    }
}
