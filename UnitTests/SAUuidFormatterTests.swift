//
//  Created by Luis Aguiniga on 2024.07.30
//  Copyright © 2024 Sequel-Ace. All rights reserved.
//

import AppKit
import XCTest


final class SAUuidFormatterTests: XCTestCase {
  let formatter = SAUuidFormatter()

  /// Verifies the field editor allows 36 characters: 32 hex digits and 4 hyphens.
  func testFormatterMaxLengthOverride() {
    XCTAssertEqual(formatter.maxLengthOverride, 36)
  }

  /// Verifies the label shown for the override in the field editor.
  func testFormatterLabelOverride() {
    XCTAssertEqual(formatter.label, "UUID Display Override")
  }

  /// Verifies an empty field is stored as NULL.
  func testEmptyStringToNSNull() {
    let input = ""
    let helper = Helper()

    XCTAssertTrue(formatter.getObjectValue(helper.autoPtr, for: input, errorDescription: helper.autoErrorPtr))
    XCTAssertTrue(helper.obj.pointee is NSNull)
    XCTAssertNil(helper.err.pointee)
  }

  /// Verifies the NULL placeholder is stored as NULL.
  func testNilValueIsValidButAsNSNull() {
    let input = "NULL"
    let helper = Helper()
    let mockFormatter = SAUuidFormatter(userDefaults: MockUserDefault(mockNullValue: "NULL"))

    XCTAssertTrue(mockFormatter.getObjectValue(helper.autoPtr, for: input, errorDescription: helper.autoErrorPtr))
    XCTAssertTrue(helper.obj.pointee is NSNull)
    XCTAssertNil(helper.err.pointee)
  }

  /// Verifies a missing value has no UUID text.
  func testNilObjectToNilString() {
    XCTAssertNil(formatter.string(for: nil))
  }

  /// Verifies a UUID survives the round trip from text to 16 bytes and back.
  func testUuidDataRoundTrip() {
    let input = "772EFFB2-FB9F-FFFF-FFFF-7E50977355E4"
    let helper = Helper()


    XCTAssertTrue(formatter.getObjectValue(helper.autoPtr, for: input, errorDescription: helper.autoErrorPtr))
    XCTAssertTrue(helper.obj.pointee is NSData)

    let data = helper.obj.pointee as! NSData
    XCTAssertEqual(data.length, 16)

    let convertedString = formatter.string(for: data)
    XCTAssertNotNil(convertedString)
    XCTAssertEqual(convertedString!, input)
  }

  /// Verifies characters other than hex digits and hyphens are refused with an error.
  func testInvalidCharacters() {
    let input = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
    let helper = Helper()

    XCTAssertFalse(formatter.getObjectValue(helper.autoPtr, for: input, errorDescription: helper.autoErrorPtr))
    XCTAssertNotNil(helper.err.pointee)
    XCTAssertEqual(helper.err.pointee!, "Invalid UUID Character in: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX")
  }

  /// Verifies an incomplete UUID is refused with the "Invalid UUID" message.
  func testInvalidLength() {
    let input = "01234567-89AB-CDEF"
    let helper = Helper()

    XCTAssertFalse(formatter.getObjectValue(helper.autoPtr, for: input, errorDescription: helper.autoErrorPtr))
    XCTAssertNotNil(helper.err.pointee)
    XCTAssertEqual(helper.err.pointee!, "Invalid UUID: 01234567-89AB-CDEF")
  }

  /// Verifies a value made only of hyphens is refused as an invalid UUID
  /// instead of being saved as an empty binary value.
  func testHyphensOnlyAreInvalidInsteadOfAnEmptyValue() {
    for input in ["----", "-"] {
      let helper = Helper()

      XCTAssertFalse(formatter.getObjectValue(helper.autoPtr, for: input, errorDescription: helper.autoErrorPtr), input)
      XCTAssertNotNil(helper.err.pointee, input)
      XCTAssertEqual(helper.err.pointee, "Invalid UUID: \(input)" as NSString)
    }
  }

  /// Verifies an incomplete but well-formed UUID is accepted while typing.
  func testValidPartial() {
    let input = "01234567-89AB-CDEF"
    let helper = Helper()

    XCTAssertTrue(formatter.isPartialStringValid(input, newEditingString: helper.autoStrPtr, errorDescription: helper.autoErrorPtr))
    XCTAssertNil(helper.err.pointee)
  }

  /// Verifies partial text with invalid characters is refused while typing.
  func testInvalidPartial() {
    let input = "01234567-89AB-XXXX"
    let helper = Helper()

    XCTAssertFalse(formatter.isPartialStringValid(input, newEditingString: helper.autoStrPtr, errorDescription: helper.autoErrorPtr))
    XCTAssertNotNil(helper.err.pointee)
    XCTAssertEqual(helper.err.pointee!, "Invalid UUID Character in: 01234567-89AB-XXXX")
  }

  /// Verifies the start of the NULL placeholder is accepted while typing.
  func testPartialNullValueIsValid() {
    let input = "NU"
    let helper = Helper()
    let mockFormatter = SAUuidFormatter(userDefaults: MockUserDefault(mockNullValue: "NUL"))

    XCTAssertTrue(mockFormatter.isPartialStringValid(input, newEditingString: helper.autoStrPtr, errorDescription: helper.autoErrorPtr))
  }

  /// Verifies the range-based partial check accepts an incomplete but well-formed UUID.
  func testValidPartialSecondOverride() {
    let input = "01234567-89AB-CDEF"
    let helper = Helper()
    helper.partialStr.pointee = input as NSString

    let res = formatter.isPartialStringValid(
      helper.autoPartialStr,
      proposedSelectedRange: nil,
      originalString: input,
      originalSelectedRange: NSRange(location: 0, length: 0),
      errorDescription: helper.autoErrorPtr
    )
    XCTAssertTrue(res)
    XCTAssertNil(helper.err.pointee)
  }

  /// Verifies the range-based partial check accepts the start of the NULL placeholder.
  func testPartialNullValidPartialSecondOverride() {
    let input = "NU"
    let helper = Helper()
    helper.partialStr.pointee = input as NSString
    let mockFormatter = SAUuidFormatter(userDefaults: MockUserDefault(mockNullValue: "NUL"))

    let res = mockFormatter.isPartialStringValid(
      helper.autoPartialStr,
      proposedSelectedRange: nil,
      originalString: input,
      originalSelectedRange: NSRange(location: 0, length: 0),
      errorDescription: helper.autoErrorPtr
    )
    XCTAssertTrue(res)
    XCTAssertNil(helper.err.pointee)
  }

  /// Verifies the range-based partial check refuses invalid characters.
  func testInvalidPartialSecondOverride() {
    let input = "01234567-89AB-XXXX"
    let helper = Helper()
    helper.partialStr.pointee = input as NSString

    let res = formatter.isPartialStringValid(
      helper.autoPartialStr,
      proposedSelectedRange: nil,
      originalString: input,
      originalSelectedRange: NSRange(location: 14, length: 4),
      errorDescription: helper.autoErrorPtr
    )
    XCTAssertFalse(res)
    XCTAssertNotNil(helper.err.pointee)
  }

  /// Verifies the range-based partial check refuses more than 32 hex digits.
  func testInvalidPartialSecondOverrideTooLong() {
    let input = "01234567-89AB-CDEF-0123-456789ABCDEF000"
    let helper = Helper()
    helper.partialStr.pointee = input as NSString

    let res = formatter.isPartialStringValid(
      helper.autoPartialStr,
      proposedSelectedRange: nil,
      originalString: input,
      originalSelectedRange: NSRange(location: 14, length: 4),
      errorDescription: helper.autoErrorPtr
    )
    XCTAssertFalse(res)
    XCTAssertNotNil(helper.err.pointee)
  }

  class Helper {
    let obj: UnsafeMutablePointer<AnyObject?>
    var autoPtr: AutoreleasingUnsafeMutablePointer<AnyObject?> {
      AutoreleasingUnsafeMutablePointer<AnyObject?>(obj)
    }

    let err: UnsafeMutablePointer<NSString?>
    var autoErrorPtr: AutoreleasingUnsafeMutablePointer<NSString?> {
      AutoreleasingUnsafeMutablePointer<NSString?>(err)
    }

    let str: UnsafeMutablePointer<NSString?>
    var autoStrPtr: AutoreleasingUnsafeMutablePointer<NSString?> {
      AutoreleasingUnsafeMutablePointer<NSString?>(str)
    }

    let partialStr: UnsafeMutablePointer<NSString>
    var autoPartialStr: AutoreleasingUnsafeMutablePointer<NSString> {
      AutoreleasingUnsafeMutablePointer<NSString>(partialStr)
    }

    /// Allocates the pointers the formatter writes its results and errors into.
    init() {
      obj = UnsafeMutablePointer<AnyObject?>.allocate(capacity: 1)
      err = UnsafeMutablePointer<NSString?>.allocate(capacity: 1)
      str = UnsafeMutablePointer<NSString?>.allocate(capacity: 1)
      partialStr = UnsafeMutablePointer<NSString>.allocate(capacity: 1)
      partialStr.initialize(to: "" as NSString)
    }

    /// Releases the pointers allocated in `init()`.
    deinit {
      obj.deallocate()
      err.deallocate()
      str.deallocate()
      partialStr.deinitialize(count: 1)
      partialStr.deallocate()
    }
  }

  class MockUserDefault: UserDefaults {
    let mockNullValue: String

    /// Creates defaults that answer `mockNullValue` for the NULL placeholder.
    convenience init(mockNullValue: String) {
      self.init(mockNullValue: mockNullValue, suiteName: "Mock User Defaults")!
    }

    /// Creates defaults in a fresh suite that answer `mockNullValue` for the NULL placeholder.
    init?(mockNullValue: String, suiteName suitename: String?) {
      UserDefaults().removePersistentDomain(forName: suitename!)

      self.mockNullValue = mockNullValue
      super.init(suiteName: suitename)
    }

    /// Returns the mocked NULL placeholder for `NullValue` and nothing else.
    override func string(forKey defaultName: String) -> String? {
      guard defaultName == "NullValue" else { return nil }
      return mockNullValue
    }
  }
}
