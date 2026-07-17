//
//  SADatabaseScopedValueCacheTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest

final class SADatabaseScopedValueCacheTests: XCTestCase {
    func testCachesValueForMatchingDatabase() {
        let cache = SADatabaseScopedValueCache()
        var loadedDatabases: [String?] = []

        let first = cache.value(forDatabase: "first") { database in
            loadedDatabases.append(database)
            return "utf8mb4"
        }
        let second = cache.value(forDatabase: "first") { database in
            loadedDatabases.append(database)
            return "unexpected"
        }

        XCTAssertEqual(first, "utf8mb4")
        XCTAssertEqual(second, "utf8mb4")
        XCTAssertEqual(loadedDatabases.count, 1)
        XCTAssertEqual(loadedDatabases[0], "first")
    }

    func testReloadsValueWhenDatabaseChanges() {
        let cache = SADatabaseScopedValueCache()
        var loadedDatabases: [String?] = []

        let first = cache.value(forDatabase: "first") { database in
            loadedDatabases.append(database)
            return "utf8mb4"
        }
        let second = cache.value(forDatabase: "second") { database in
            loadedDatabases.append(database)
            return "latin1"
        }

        XCTAssertEqual(first, "utf8mb4")
        XCTAssertEqual(second, "latin1")
        XCTAssertEqual(loadedDatabases.count, 2)
        XCTAssertEqual(loadedDatabases[0], "first")
        XCTAssertEqual(loadedDatabases[1], "second")
    }

    func testNilDatabaseIsAnExplicitCacheKey() {
        let cache = SADatabaseScopedValueCache()
        var loadCount = 0

        let first = cache.value(forDatabase: nil) { database in
            XCTAssertNil(database)
            loadCount += 1
            return "server-context-value"
        }
        let second = cache.value(forDatabase: nil) { _ in
            loadCount += 1
            return "unexpected"
        }

        XCTAssertEqual(first, "server-context-value")
        XCTAssertEqual(second, "server-context-value")
        XCTAssertEqual(loadCount, 1)
    }

    func testFailedLoadIsRetriedAndResetClearsSuccessfulValue() {
        let cache = SADatabaseScopedValueCache()
        var loadCount = 0

        XCTAssertNil(cache.value(forDatabase: "first") { _ in
            loadCount += 1
            return nil
        })
        XCTAssertEqual(cache.value(forDatabase: "first") { _ in
            loadCount += 1
            return "utf8mb4"
        }, "utf8mb4")

        cache.reset()

        XCTAssertEqual(cache.value(forDatabase: "first") { _ in
            loadCount += 1
            return "latin1"
        }, "latin1")
        XCTAssertEqual(loadCount, 3)
    }
}
