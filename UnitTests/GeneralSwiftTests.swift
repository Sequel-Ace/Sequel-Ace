//
//  GeneralSwiftTests.swift
//  Unit Tests
//
//  Created by James on 12/1/2021.
//  Copyright © 2020-2022 Sequel-Ace. All rights reserved.
//

import XCTest

// added private so that this class is not in the generated -Swift.h
private final class GeneralSwiftTests: XCTestCase {

    // 0.242s
    func testPerformanceComponents() throws {
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
