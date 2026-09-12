//  SAJSONValueDetectorTests.swift
//  Sequel Ace
//
//  Tests for detecting JSON values stored in columns that are not declared with
//  MySQL's JSON type (issue #2514).
//

import XCTest

final class SAJSONValueDetectorTests: XCTestCase {

    func testDetectsJSONObject() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"{"a":1,"b":"two"}"#))
    }

    func testDetectsJSONArray() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"[1,2,3]"#))
    }

    func testDetectsPrettyPrintedJSONWithLeadingWhitespace() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer("\n  {\n    \"a\" : 1\n  }\n"))
    }

    func testDetectsNestedContainers() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"{"rows":[{"id":1},{"id":2}],"total":2}"#))
    }

    func testDetectsUnicodeContent() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"{"name":"Ünïcødé ✅"}"#))
    }

    // Top-level scalars are valid JSON fragments but are indistinguishable from ordinary
    // column values, so they must not pull the editor onto the JSON segment.
    func testRejectsTopLevelScalars() {
        for scalar in ["42", "-1.5", #""text""#, "true", "false", "null"] {
            XCTAssertFalse(SAJSONValueDetector.isJSONContainer(scalar), "should reject \(scalar)")
        }
    }

    func testRejectsMalformedJSON() {
        for malformed in [#"{"a":}"#, #"{"a":1"#, "[1,2,", #"{'a':1}"#] {
            XCTAssertFalse(SAJSONValueDetector.isJSONContainer(malformed), "should reject \(malformed)")
        }
    }

    func testRejectsPlainText() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("Lorem ipsum dolor sit amet"))
    }

    // PHP serialized values have their own editor and must not be claimed by the JSON segment.
    func testRejectsPHPSerializedValue() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(#"a:2:{s:1:"a";i:1;s:1:"b";i:2;}"#))
    }

    // The geometry branch of the field editor puts WKT into the text view.
    func testRejectsWellKnownText() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("POLYGON((0 0,10 0,10 10,0 10,0 0))"))
    }

    // The binary branch of the field editor renders values as a hex string.
    func testRejectsHexString() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("0x5B315D"))
    }

    func testRejectsEmptyAndWhitespaceOnlyValues() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(""))
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("   \n\t "))
    }

    func testRejectsNil() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(nil))
    }

    // A value that merely opens with a brace must still be parsed before being claimed.
    func testRejectsBraceLeadingNonJSON() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("{this is not json}"))
    }

    func testRejectsValuesBeyondTheSizeLimit() {
        let oversized = "[\"" + String(repeating: "a", count: 5 * 1024 * 1024) + "\"]"
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(oversized))
    }
}
