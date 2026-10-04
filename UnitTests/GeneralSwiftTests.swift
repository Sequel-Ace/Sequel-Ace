//
//  GeneralSwiftTests.swift
//  Unit Tests
//
//  Created by James on 12/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import XCTest

private enum PerformanceTestOptIn {
    static let environmentVariable = "SEQUEL_ACE_RUN_PERFORMANCE_TESTS"
    static let skipMessage = "Set \(environmentVariable)=1 to run performance measurement tests."

    static var isEnabled: Bool {
        #if SEQUEL_ACE_RUN_PERFORMANCE_TESTS
        return true
        #else
        guard let value = ProcessInfo.processInfo.environment[environmentVariable]?.lowercased() else {
            return false
        }

        return value == "1" || value == "true" || value == "yes"
        #endif
    }
}

// added private so that this class is not in the generated -Swift.h
private final class GeneralSwiftTests: XCTestCase {

    // 0.242s
    func testPerformanceComponents() throws {
        try XCTSkipUnless(PerformanceTestOptIn.isEnabled, PerformanceTestOptIn.skipMessage)

        // This is an example of a performance test case.

        let str = "My name is JIMMY"
        self.measure {

            let iterations = Array(0...100000)

            for _ in iterations {
                _ = str.components(separatedBy: " ")
            }
        }
    }

    // 0.131s
    func testPerformanceSplit() throws {
        try XCTSkipUnless(PerformanceTestOptIn.isEnabled, PerformanceTestOptIn.skipMessage)

        // This is an example of a performance test case.

        let str = "My name is JIMMY"

        self.measure {
            let iterations = Array(0...100000)

            for _ in iterations {
                _ = str.split(separator: " ")
            }
        }
    }

    // 0.103s
    func testPerformanceEnumerateSubstrings() throws {
        try XCTSkipUnless(PerformanceTestOptIn.isEnabled, PerformanceTestOptIn.skipMessage)

        // This is an example of a performance test case.

        let str = "SELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT COUNT(*) FROM `HKWarningsLog`;"

        var newHistMutArray: [String] = []

        let wholeString = str.startIndex..<str.endIndex

        self.measure {
            let iterations = Array(0...10000)

            for _ in iterations {
                str.enumerateSubstrings(in: wholeString, options: NSString.EnumerationOptions.byLines) { (substring, substringRange, enclosingRange, stop) -> () in
                    if let line = substring {
                        newHistMutArray.appendIfNotContains(line)
                    }
                }
            }
        }

        print(newHistMutArray)
    }

    // 0.114 s 
    func testPerformanceSeparatedIntoLines() throws {
        try XCTSkipUnless(PerformanceTestOptIn.isEnabled, PerformanceTestOptIn.skipMessage)

        // This is an example of a performance test case.

        let str = "SELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT * FROM `HKWarningsLog` LIMIT 1000;\nSELECT COUNT(*) FROM `HKWarningsLog`;"

        var newHistMutArray: [String] = []

        self.measure {
            let iterations = Array(0...10000)

            for _ in iterations {
                let lines = str.separatedIntoLines()

                for line in lines  {
                    newHistMutArray.appendIfNotContains(line)
                }
            }
        }

        print(newHistMutArray)
    }
}

final class DateExtensionTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let posix = Locale(identifier: "en_US_POSIX")
    private let utc = TimeZone(identifier: "UTC")!

    /// Formatting with an explicit format must leave the shared medium-style
    /// formatter as it is: Table Information formats Create/Update time with
    /// it, and a `dateFormat` left behind (e.g. `yyyy` from an export file
    /// name) reduced those to the year until the next launch.
    func testStringWithFormatLeavesSharedFormatterUntouched() {
        let shared = DateFormatter.mediumStyleFormatter
        let before = shared.string(from: date)

        _ = date.string(format: "yyyy", locale: posix, timeZone: utc)
        _ = date.string(format: "HH:mm:ss", locale: posix, timeZone: utc)

        XCTAssertEqual(shared.dateStyle, .medium)
        XCTAssertEqual(shared.timeStyle, .medium)
        XCTAssertEqual(shared.string(from: date), before)
    }

    /// Verifies the format, locale and time zone given are the ones used.
    func testStringWithFormatUsesGivenLocaleAndTimeZone() {
        XCTAssertEqual(date.string(format: "yyyy-MM-dd HH:mm:ss", locale: posix, timeZone: utc), "2023-11-14 22:13:20")
        XCTAssertEqual(
            date.string(format: "yyyy-MM-dd HH:mm:ss", locale: posix, timeZone: TimeZone(identifier: "Europe/Berlin")!),
            "2023-11-14 23:13:20"
        )
        XCTAssertEqual(date.string(format: "EEEE", locale: Locale(identifier: "de_DE"), timeZone: utc), "Dienstag")
    }

    /// Verifies the Objective-C entry point formats through the same path.
    func testObjectiveCEntryPointMatchesSwift() {
        let viaObjC = (date as NSDate).string(format: "yyyy-MM-dd", locale: posix as NSLocale, timeZone: utc as NSTimeZone)
        XCTAssertEqual(viaObjC, date.string(format: "yyyy-MM-dd", locale: posix, timeZone: utc))
    }
}
