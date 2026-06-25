//
//  SAPHPSerializedParserTests.swift
//  sequel-ace
//
//  Created by Codex on 2026-06-15.
//

import XCTest

final class SAPHPSerializedParserTests: XCTestCase {
    func testRoundTripsStructuredSerializedData() {
        let serialized = "a:4:{s:4:\"name\";s:5:\"Marco\";s:5:\"count\";i:42;s:5:\"valid\";b:1;s:6:\"nested\";a:1:{i:0;s:3:\"yes\";}}"
        let value = SAPHPSerializedParser.parseString(serialized, errorMessage: nil)

        XCTAssertNotNil(value)
        XCTAssertEqual(value?.serializedString(), serialized)
    }

    func testRecalculatesUtf8StringLengths() {
        let value = SAPHPSerializedParser.parseString("s:2:\"é\";", errorMessage: nil)

        XCTAssertNotNil(value)
        value?.scalarValue = "éé"
        XCTAssertEqual(value?.serializedString(), "s:4:\"éé\";")
    }

    func testParsesStringLengthsUsingProvidedEncoding() {
        let serialized = "s:1:\"é\";"
        var errorMessage: NSString?
        let utf8Value = SAPHPSerializedParser.parseString(serialized, errorMessage: &errorMessage)
        let latin1Value = SAPHPSerializedParser.parseString(serialized, encoding: String.Encoding.isoLatin1.rawValue, errorMessage: nil)

        XCTAssertNil(utf8Value)
        XCTAssertNotNil(errorMessage)
        XCTAssertNotNil(latin1Value)
        XCTAssertEqual(latin1Value?.scalarValue, "é")
        XCTAssertEqual(latin1Value?.serializedString(), serialized)
    }

    func testSerializesStringLengthsUsingProvidedEncoding() {
        let value = SAPHPSerializedParser.parseString("s:1:\"é\";", encoding: String.Encoding.isoLatin1.rawValue, errorMessage: nil)

        XCTAssertNotNil(value)
        value?.scalarValue = "éé"
        XCTAssertEqual(value?.serializedString(), "s:2:\"éé\";")
    }

    func testRejectsUnencodableStringForProvidedEncoding() {
        let value = SAPHPSerializedParser.parseString("s:1:\"é\";", encoding: String.Encoding.isoLatin1.rawValue, errorMessage: nil)
        var errorMessage: NSString?

        XCTAssertNotNil(value)
        value?.scalarValue = "€"
        XCTAssertNil(value?.serializedString(errorMessage: &errorMessage))
        XCTAssertNotNil(errorMessage)
    }

    func testParsesAndSerializesPHPEnumCases() {
        let serialized = "a:1:{s:6:\"status\";E:10:\"Suit:Clubs\";}"
        let value = SAPHPSerializedParser.parseString(serialized, errorMessage: nil)
        let firstEntry = value?.children.firstObject as? SAPHPSerializedEntry

        XCTAssertNotNil(value)
        XCTAssertEqual(value?.serializedString(), serialized)
        XCTAssertEqual(firstEntry?.value.scalarValue, "Suit:Clubs")
        XCTAssertEqual(firstEntry?.value.type, .enum)
    }

    func testRejectsLeadingWhitespaceBeforeSerializedValue() {
        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString(" a:1:{i:0;s:3:\"yes\";}", errorMessage: &errorMessage)

        XCTAssertNil(value)
        XCTAssertNotNil(errorMessage)
    }

    func testRejectsTrailingWhitespaceAfterSerializedValue() {
        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString("a:1:{i:0;s:3:\"yes\";} ", errorMessage: &errorMessage)

        XCTAssertNil(value)
        XCTAssertNotNil(errorMessage)
    }

    func testRejectsOversizedSerializedLength() {
        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString("s:184467440737095516150:\"x\";", errorMessage: &errorMessage)

        XCTAssertNil(value)
        XCTAssertNotNil(errorMessage)
    }

    func testRejectsStringLengthBeyondAvailableBytes() {
        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString("s:999:\"abc\";", errorMessage: &errorMessage)

        XCTAssertNil(value)
        XCTAssertNotNil(errorMessage)
    }

    func testRejectsInvalidFloatPayload() {
        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString("d:hello;", errorMessage: &errorMessage)

        XCTAssertNil(value)
        XCTAssertNotNil(errorMessage)
    }

    func testFloatValidationUsesPHPDotDecimalFormat() {
        XCTAssertTrue(SAPHPSerializedValue.isValidPHPFloatString("12.34"))
        XCTAssertFalse(SAPHPSerializedValue.isValidPHPFloatString("12,34"))
    }

    func testFloatValidationRejectsNoncanonicalSpecialTokens() {
        XCTAssertTrue(SAPHPSerializedValue.isValidPHPFloatString("INF"))
        XCTAssertTrue(SAPHPSerializedValue.isValidPHPFloatString("-INF"))
        XCTAssertTrue(SAPHPSerializedValue.isValidPHPFloatString("NAN"))
        XCTAssertFalse(SAPHPSerializedValue.isValidPHPFloatString("inf"))
        XCTAssertFalse(SAPHPSerializedValue.isValidPHPFloatString("-inf"))
        XCTAssertFalse(SAPHPSerializedValue.isValidPHPFloatString("nan"))
    }

    func testRejectsNoncanonicalSerializedSpecialFloatTokens() {
        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString("d:inf;", errorMessage: &errorMessage)

        XCTAssertNil(value)
        XCTAssertNotNil(errorMessage)
    }

    func testRejectsExcessiveNestingDepth() {
        var serialized = "s:3:\"end\";"
        for _ in 0..<600 {
            serialized = "a:1:{i:0;" + serialized + "}"
        }

        var errorMessage: NSString?
        let value = SAPHPSerializedParser.parseString(serialized, errorMessage: &errorMessage)

        XCTAssertNil(value)
        XCTAssertNotNil(errorMessage)
    }

    func testIntegerEditsAreTrimmedBeforeSerialization() {
        let value = SAPHPSerializedParser.parseString("i:1;", errorMessage: nil)
        value?.scalarValue = SAPHPSerializedValue.normalizedIntegerString(fromEditedString: " 42 ") ?? ""

        XCTAssertEqual(value?.serializedString(), "i:42;")
    }

    func testAddingArrayChildUsesNextIntegerKey() {
        let value = SAPHPSerializedParser.parseString("a:2:{i:0;s:4:\"zero\";i:2;s:3:\"two\";}", errorMessage: nil)
        let entry = SAPHPSerializedEntry()
        entry.keyIsInteger = true
        entry.key = value?.nextAvailableArrayKey()
        entry.value = SAPHPSerializedValue.value(with: .string)

        value?.children.add(entry)

        XCTAssertEqual(value?.serializedString(), "a:3:{i:0;s:4:\"zero\";i:2;s:3:\"two\";i:3;s:0:\"\";}")
    }

    func testAddingNestedArrayChildSerializesSubArray() {
        let value = SAPHPSerializedParser.parseString("a:1:{i:0;s:4:\"root\";}", errorMessage: nil)
        let entry = SAPHPSerializedEntry()
        entry.keyIsInteger = true
        entry.key = value?.nextAvailableArrayKey()
        entry.value = SAPHPSerializedValue.value(with: .array)

        let nestedEntry = SAPHPSerializedEntry()
        nestedEntry.parent = entry
        nestedEntry.keyIsInteger = true
        nestedEntry.key = entry.value.nextAvailableArrayKey()
        nestedEntry.value = SAPHPSerializedValue.value(with: .string)
        nestedEntry.value.scalarValue = "nested"
        entry.value.children.add(nestedEntry)

        value?.children.add(entry)

        XCTAssertEqual(value?.serializedString(), "a:2:{i:0;s:4:\"root\";i:1;a:1:{i:0;s:6:\"nested\";}}")
    }

    func testDetectsReferencesRecursively() {
        let withoutReference = SAPHPSerializedParser.parseString("a:1:{i:0;s:5:\"plain\";}", errorMessage: nil)
        let withReference = SAPHPSerializedParser.parseString("a:2:{i:0;s:5:\"plain\";i:1;R:2;}", errorMessage: nil)

        XCTAssertNotNil(withoutReference)
        XCTAssertNotNil(withReference)
        XCTAssertFalse(withoutReference?.containsReference() ?? true)
        XCTAssertTrue(withReference?.containsReference() ?? false)
    }

    func testAddingObjectChildUsesUniquePropertyName() {
        let value = SAPHPSerializedParser.parseString("O:8:\"stdClass\":2:{s:12:\"new_property\";s:3:\"old\";s:14:\"new_property_2\";s:3:\"two\";}", errorMessage: nil)
        let entry = SAPHPSerializedEntry()
        entry.keyIsInteger = false
        entry.key = value?.uniqueObjectPropertyName()
        entry.value = SAPHPSerializedValue.value(with: .string)

        value?.children.add(entry)

        XCTAssertEqual(value?.serializedString(), "O:8:\"stdClass\":3:{s:12:\"new_property\";s:3:\"old\";s:14:\"new_property_2\";s:3:\"two\";s:14:\"new_property_3\";s:0:\"\";}")
    }
}
