//
//  SASpacingTests.swift
//  Unit Tests
//
//  The spacing steps ascend and sit on the 4-pt grid.
//

import CoreGraphics
import XCTest

final class SASpacingTests: XCTestCase {

    private let steps: [CGFloat] = [SASpacing.xxSmall, SASpacing.xSmall, SASpacing.small,
                                    SASpacing.medium, SASpacing.large, SASpacing.xLarge]

    func testStepsAscendStrictly() {
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertEqual(Set(steps).count, steps.count)
    }

    func testStepsSitOnTheFourPointGrid() {
        for step in steps {
            XCTAssertEqual(step.truncatingRemainder(dividingBy: 4), 0, "\(step) is off the 4-pt grid")
        }
        XCTAssertEqual(SASpacing.xxSmall, 4)
    }
}
