//
//  SADatabaseScopedValueCache.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

@objcMembers
public final class SADatabaseScopedValueCache: NSObject {
    private var databaseName: String?
    private var cachedValue: String?

    @objc(valueForDatabase:loader:)
    public func value(
        forDatabase databaseName: String?,
        loader: (String?) -> String?
    ) -> String? {
        if self.databaseName != databaseName {
            cachedValue = nil
            self.databaseName = databaseName
        }

        if cachedValue == nil {
            cachedValue = loader(databaseName)
            self.databaseName = databaseName
        }

        return cachedValue
    }

    public func reset() {
        databaseName = nil
        cachedValue = nil
    }
}
