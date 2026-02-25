//
//  Created by Codex on 2026-02-25.
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import XCTest

final class SPBundleManagerAdditionsTests: XCTestCase {

    func testLocalNetworkPermissionCheckerReturnsFalseForEmptyHost() {
        XCTAssertFalse(
            SALocalNetworkPermissionChecker.isLocalNetworkAccessDenied(
                forHost: "   ",
                port: 3306,
                timeout: 0.1
            )
        )
    }

    func testLocalNetworkPermissionCheckerReturnsFalseForInvalidPort() {
        XCTAssertFalse(
            SALocalNetworkPermissionChecker.isLocalNetworkAccessDenied(
                forHost: "192.168.1.20",
                port: 0,
                timeout: 0.1
            )
        )
    }
}
