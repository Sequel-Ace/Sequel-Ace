//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SPBundleManagerAdditionsTests: XCTestCase {

    func testShouldUpdateDefaultBundleWhenBundledVersionIsHigher() {
        XCTAssertTrue(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 2),
                bundledVersion: NSNumber(value: 3)
            )
        )
    }

    func testShouldNotUpdateDefaultBundleWhenVersionsAreEqual() {
        XCTAssertFalse(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 3),
                bundledVersion: NSNumber(value: 3)
            )
        )
    }

    func testShouldNotUpdateDefaultBundleWhenInstalledVersionIsHigher() {
        XCTAssertFalse(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 4),
                bundledVersion: NSNumber(value: 3)
            )
        )
    }

    func testShouldUpdateDefaultBundleWhenInstalledVersionIsMissing() {
        XCTAssertTrue(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: nil,
                bundledVersion: NSNumber(value: 1)
            )
        )
    }

    func testShouldNotUpdateDefaultBundleWhenBundledVersionIsMissing() {
        XCTAssertFalse(
            SABundleVersionUpdater.shouldUpdateDefaultBundle(
                installedVersion: NSNumber(value: 3),
                bundledVersion: nil
            )
        )
    }
}
