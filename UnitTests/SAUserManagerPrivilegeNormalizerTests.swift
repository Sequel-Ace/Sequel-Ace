import XCTest

final class SAUserManagerPrivilegeNormalizerTests: XCTestCase {
    func testMariaDBUsesDeleteHistoryGrantName() {
        XCTAssertEqual(
            SAUserManagerPrivilegeNormalizer.normalizedGrantName(
                "delete versioning rows",
                isMariaDB: true
            ),
            "delete history"
        )
    }

    func testMariaDBNormalizationIsCaseInsensitive() {
        XCTAssertEqual(
            SAUserManagerPrivilegeNormalizer.normalizedGrantName(
                "DELETE VERSIONING ROWS",
                isMariaDB: true
            ),
            "delete history"
        )
    }

    func testMySQLKeepsOriginalGrantName() {
        XCTAssertEqual(
            SAUserManagerPrivilegeNormalizer.normalizedGrantName(
                "delete versioning rows",
                isMariaDB: false
            ),
            "delete versioning rows"
        )
    }

    func testMariaDBKeepsUnrelatedGrantNames() {
        XCTAssertEqual(
            SAUserManagerPrivilegeNormalizer.normalizedGrantName(
                "show create routine",
                isMariaDB: true
            ),
            "show create routine"
        )
    }
}
