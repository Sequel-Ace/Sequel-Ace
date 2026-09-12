//  SAJSONValueDetectorTests.swift
//  Sequel Ace
//
//  Tests for detecting JSON values stored in columns that are not declared with
//  MySQL's JSON type (issue #2514).
//

import XCTest

final class SAJSONValueDetectorTests: XCTestCase {

    /// Verifies a JSON object is detected as a container.
    func testDetectsJSONObject() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"{"a":1,"b":"two"}"#))
    }

    /// Verifies a JSON array is detected as a container.
    func testDetectsJSONArray() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"[1,2,3]"#))
    }

    /// Verifies leading whitespace and newlines do not prevent detection.
    func testDetectsPrettyPrintedJSONWithLeadingWhitespace() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer("\n  {\n    \"a\" : 1\n  }\n"))
    }

    /// Verifies containers nested inside containers are detected.
    func testDetectsNestedContainers() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"{"rows":[{"id":1},{"id":2}],"total":2}"#))
    }

    /// Verifies non-ASCII content does not prevent detection.
    func testDetectsUnicodeContent() {
        XCTAssertTrue(SAJSONValueDetector.isJSONContainer(#"{"name":"Ünïcødé ✅"}"#))
    }

    /// Verifies top-level scalars are rejected.
    ///
    /// They are valid JSON fragments but indistinguishable from ordinary column
    /// values, and the JSON segment rejects them too because it parses without
    /// `NSJSONReadingFragmentsAllowed`.
    func testRejectsTopLevelScalars() {
        for scalar in ["42", "-1.5", #""text""#, "true", "false", "null"] {
            XCTAssertFalse(SAJSONValueDetector.isJSONContainer(scalar), "should reject \(scalar)")
        }
    }

    /// Verifies values that only look like JSON are rejected.
    func testRejectsMalformedJSON() {
        for malformed in [#"{"a":}"#, #"{"a":1"#, "[1,2,", #"{'a':1}"#] {
            XCTAssertFalse(SAJSONValueDetector.isJSONContainer(malformed), "should reject \(malformed)")
        }
    }

    /// Verifies ordinary prose is rejected.
    func testRejectsPlainText() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("Lorem ipsum dolor sit amet"))
    }

    /// Verifies PHP serialized values are rejected, since they have their own editor.
    func testRejectsPHPSerializedValue() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(#"a:2:{s:1:"a";i:1;s:1:"b";i:2;}"#))
    }

    /// Verifies well-known text is rejected, as the geometry branch puts WKT into the text view.
    func testRejectsWellKnownText() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("POLYGON((0 0,10 0,10 10,0 10,0 0))"))
    }

    /// Verifies hex strings are rejected, as the binary branch renders values that way.
    func testRejectsHexString() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("0x5B315D"))
    }

    /// Verifies empty and whitespace-only values are rejected.
    func testRejectsEmptyAndWhitespaceOnlyValues() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(""))
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("   \n\t "))
    }

    /// Verifies a nil value is rejected rather than trapping.
    func testRejectsNil() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(nil))
    }

    /// Verifies a value that merely opens with a brace is still parsed before being claimed.
    func testRejectsBraceLeadingNonJSON() {
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer("{this is not json}"))
    }

    /// Verifies values beyond the sniff size limit are rejected without being parsed.
    func testRejectsValuesBeyondTheSizeLimit() {
        let oversized = "[\"" + String(repeating: "a", count: 5 * 1024 * 1024) + "\"]"
        XCTAssertFalse(SAJSONValueDetector.isJSONContainer(oversized))
    }
}
