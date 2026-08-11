//  SAEditorTokensTests.swift
//  Sequel Ace
//
//  Tests for the SQL editor keyword set (SPEditorTokens.l) and the
//  autocomplete keyword source (CompletionTokens.plist core_keywords).
//

import XCTest

final class SAEditorTokensTests: XCTestCase {

    // Issue #321: non-InnoDB storage engines must appear in autocomplete
    // (core_keywords of CompletionTokens.plist). On stock main this fails for
    // MYISAM, BLACKHOLE, CSV, SEQUENCE, COLUMNSTORE, SPIDER, ROCKSDB, ARIA, CONNECT.
    func testStorageEnginesAreInCoreKeywords() {
        let plistURL = Bundle(for: type(of: self)).url(forResource: "CompletionTokens", withExtension: "plist")
        XCTAssertNotNil(plistURL, "CompletionTokens.plist must be bundled into the Unit Tests target")

        let plist = plistURL.flatMap { NSDictionary(contentsOf: $0) }
        XCTAssertNotNil(plist, "plist must parse")

        let coreKeywords = plist?["core_keywords"] as? [String]
        XCTAssertNotNil(coreKeywords, "core_keywords array must exist")

        let coreKeywordSet = Set(coreKeywords ?? [])
        let engines: [String] = ["MYISAM", "INNODB", "BLACKHOLE", "CSV",
                                 "SEQUENCE", "COLUMNSTORE", "SPIDER",
                                 "ROCKSDB", "ARIA", "CONNECT"]
        for engine in engines {
            XCTAssertTrue(coreKeywordSet.contains(engine),
                          "\(engine) must be a core_keyword for autocomplete (issue #321)")
        }
    }
}
