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
