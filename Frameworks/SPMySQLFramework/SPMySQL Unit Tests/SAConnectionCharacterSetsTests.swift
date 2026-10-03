//
//  SAConnectionCharacterSetsTests.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import XCTest
@testable import SPMySQL

/// Which character sets a session may run in, and what each one is converted with.
final class SAConnectionCharacterSetsTests: XCTestCase {

    /// The character sets that have no macOS string encoding to carry them. Reading their bytes
    /// as UTF-8 reinterprets the value instead of converting it.
    private let notCarriable = ["armscii8", "geostd8", "hp8", "keybcs2", "swe7"]

    /// The string encoding the framework converts a character set's values with.
    private func encoding(for characterSet: String) -> String.Encoding {
        String.Encoding(rawValue: SPMySQLConnection.stringEncoding(forMySQLCharset: characterSet))
    }

    // MARK: - Which character sets can be run

    /// A character set with a string encoding behind it may be run.
    func testCharacterSetsWithAStringEncodingCanBeRun() {
        for characterSet in ["utf8mb4", "utf8mb3", "latin1", "latin2", "latin5", "latin7", "gbk",
                             "gb2312", "gb18030", "big5", "sjis", "cp932", "euckr", "ujis",
                             "greek", "hebrew", "cp1251", "koi8r", "macroman", "ascii", "binary"] {
            XCTAssertTrue(SAConnectionCharacterSets.canCarryValues(forCharacterSet: characterSet),
                          "\(characterSet) should be usable for a session")
        }
    }

    /// The pre-4.1 names a server can still report are recognised too.
    func testPre41NamesAreRecognised() {
        for characterSet in ["czech", "dos", "german1", "usa7", "danish", "win1251", "euc_kr",
                             "estonia", "hungarian", "koi8_ru", "koi8_ukr", "win1251ukr",
                             "win1250", "croat", "latin1_de"] {
            XCTAssertTrue(SAConnectionCharacterSets.canCarryValues(forCharacterSet: characterSet),
                          "\(characterSet) should be usable for a session")
        }
    }

    /// A character set macOS has no encoding for is not run, however the server spells it.
    func testCharacterSetsWithoutAStringEncodingAreRefused() {
        for characterSet in notCarriable {
            XCTAssertFalse(SAConnectionCharacterSets.canCarryValues(forCharacterSet: characterSet),
                           "\(characterSet) has no string encoding and should not be run")
            XCTAssertFalse(SAConnectionCharacterSets.canCarryValues(forCharacterSet: characterSet.uppercased()),
                           "\(characterSet) should be refused whatever its case")
        }
    }

    /// A name this framework has never been taught is refused rather than guessed at.
    func testAnUnknownCharacterSetIsRefused() {
        XCTAssertFalse(SAConnectionCharacterSets.canCarryValues(forCharacterSet: "utf9mb5"))
        XCTAssertFalse(SAConnectionCharacterSets.canCarryValues(forCharacterSet: ""))
        XCTAssertFalse(SAConnectionCharacterSets.canCarryValues(forCharacterSet: nil))
    }

    /// Character set names are matched however the server spells their case.
    func testTheCaseOfTheNameDoesNotMatter() {
        XCTAssertTrue(SAConnectionCharacterSets.canCarryValues(forCharacterSet: "UTF8MB4"))
        XCTAssertTrue(SAConnectionCharacterSets.canCarryValues(forCharacterSet: "Latin1"))
    }

    /// The name handed back is the one the encoding table is keyed by, which matches it
    /// case-sensitively. A session set up under the caller's spelling would otherwise pass the
    /// check and then find no encoding, leaving its values converted as UTF-8.
    func testTheNameComesBackInTheSpellingTheEncodingTableUses() {
        for spelling in ["LATIN5", "Latin5", "latin5"] {
            XCTAssertEqual(SAConnectionCharacterSets.carriableName(forCharacterSet: spelling), "latin5")
        }
        XCTAssertNil(SAConnectionCharacterSets.carriableName(forCharacterSet: "SWE7"))
        XCTAssertNil(SAConnectionCharacterSets.carriableName(forCharacterSet: nil))

        // The spelling that comes back resolves to a real encoding; the caller's may not.
        let carried = SAConnectionCharacterSets.carriableName(forCharacterSet: "LATIN5")
        XCTAssertNotEqual(encoding(for: carried ?? ""), .utf8)
        XCTAssertEqual(encoding(for: "LATIN5"), .utf8, "the table is case-sensitive, which is why the name is normalised")
    }

    /// The fallback is one every server offering more than the pre-4.1 character sets has.
    func testTheFallbackIsUTF8() {
        XCTAssertEqual(SAConnectionCharacterSets.fallbackCharacterSet, "utf8mb4")
        XCTAssertTrue(SAConnectionCharacterSets.canCarryValues(forCharacterSet:
            SAConnectionCharacterSets.fallbackCharacterSet))
    }

    // MARK: - The list and the encoding table say the same thing

    /// Every character set declared carriable really does map to an encoding of its own, rather
    /// than falling through to the UTF-8 guess the table ends in. The UTF-8 character sets, and
    /// binary, are the ones legitimately mapped to UTF-8.
    func testEveryCarriableCharacterSetHasAnEncodingOfItsOwn() {
        let legitimatelyUTF8 = ["utf8", "utf8mb3", "utf8mb4", "binary"]
        for characterSet in ["ascii", "big5", "cp1250", "cp1251", "cp1256", "cp1257", "cp850",
                             "cp852", "cp866", "cp932", "dec8", "eucjpms", "euckr", "gb18030",
                             "gb2312", "gbk", "greek", "hebrew", "koi8r", "koi8u", "latin1",
                             "latin2", "latin5", "latin7", "macce", "macroman", "sjis", "tis620",
                             "ucs2", "ujis", "utf16", "utf16le", "utf32"] {
            XCTAssertTrue(SAConnectionCharacterSets.canCarryValues(forCharacterSet: characterSet))
            if !legitimatelyUTF8.contains(characterSet) {
                XCTAssertNotEqual(encoding(for: characterSet), .utf8,
                                  "\(characterSet) falls through to the UTF-8 guess but is listed as carriable")
            }
        }
    }

    /// And every character set that is refused is one the table has nothing for - so nothing is
    /// turned away that could in fact have been converted.
    func testEveryRefusedCharacterSetFallsThroughTheTable() {
        for characterSet in notCarriable {
            XCTAssertEqual(encoding(for: characterSet), .utf8,
                           "\(characterSet) has an encoding of its own and should not be refused")
        }
    }

    // MARK: - The corrected mappings

    /// gb2312 is EUC-CN on the wire. Mapped to the bare GB 2312-80 standard, which has no ASCII
    /// range, converting a value yielded no bytes at all and nothing could be written.
    func testGB2312ConvertsValuesIncludingASCII() throws {
        let gb2312 = encoding(for: "gb2312")
        let ascii = try XCTUnwrap("a'b".data(using: gb2312))
        XCTAssertEqual(ascii, Data([0x61, 0x27, 0x62]))
        // 数据库 in EUC-CN.
        let chinese = try XCTUnwrap("数据库".data(using: gb2312))
        XCTAssertEqual(chinese, Data([0xCA, 0xFD, 0xBE, 0xDD, 0xBF, 0xE2]))
    }

    /// MySQL's greek is ISO 8859-7, which puts the Greek alphabet where Windows-1253 puts
    /// punctuation.
    func testGreekIsISO8859_7() throws {
        let greek = encoding(for: "greek")
        let alpha = try XCTUnwrap("Α".data(using: greek))	// U+0391 GREEK CAPITAL LETTER ALPHA
        XCTAssertEqual(alpha, Data([0xC1]))
        let tonos = try XCTUnwrap("΄".data(using: greek))	// U+0384 GREEK TONOS
        XCTAssertEqual(tonos, Data([0xB4]))
    }

    /// MySQL's latin5 is ISO 8859-9, where the 80-9F range holds control characters rather than
    /// the punctuation Windows-1254 puts there.
    func testLatin5IsISO8859_9() throws {
        let latin5 = encoding(for: "latin5")
        let dotlessI = try XCTUnwrap("ı".data(using: latin5))	// U+0131, Turkish dotless i
        XCTAssertEqual(dotlessI, Data([0xFD]))
        // Windows-1254 reads 0x80 as the euro sign; ISO 8859-9, like the server, does not.
        XCTAssertNotEqual("€".data(using: latin5), Data([0x80]))
    }

    /// MySQL's euckr is the extended CP949, which covers syllables plain EUC-KR cannot.
    func testEUCKRIsTheExtendedForm() throws {
        let euckr = encoding(for: "euckr")
        // U+AC01 각 sits in the extension CP949 adds over EUC-KR.
        XCTAssertNotNil("각".data(using: euckr))
        let hangul = try XCTUnwrap("한글".data(using: euckr))
        XCTAssertEqual(hangul, Data([0xC7, 0xD1, 0xB1, 0xDB]))
    }

    /// The pre-4.1 name for a character set converts the same way the current name does.
    func testThePre41NamesMatchTheirCurrentEquivalents() {
        for (old, current) in [("euc_kr", "euckr"), ("win1251", "cp1251"), ("win1250", "cp1250"),
                               ("czech", "latin2"), ("hungarian", "latin2"), ("croat", "latin2"),
                               ("usa7", "ascii"), ("german1", "latin1"), ("latin1_de", "latin1"),
                               ("koi8_ru", "koi8r"), ("koi8_ukr", "koi8u"), ("estonia", "latin7")] {
            XCTAssertEqual(encoding(for: old), encoding(for: current),
                           "\(old) and \(current) are the same character set and must convert alike")
        }
    }

    /// gb18030 was missing from the table and fell through to the UTF-8 guess.
    func testGB18030HasItsOwnEncoding() throws {
        let gb18030 = encoding(for: "gb18030")
        XCTAssertNotEqual(gb18030, .utf8)
        let chinese = try XCTUnwrap("数据库".data(using: gb18030))
        XCTAssertEqual(chinese, Data([0xCA, 0xFD, 0xBE, 0xDD, 0xBF, 0xE2]))
    }

    // MARK: - The two directions agree

    /// Going from a string encoding to a character set and back must land on the same
    /// encoding. The SQL import names the character set an imported file is in this way, so a
    /// pair that disagrees has the server read the file as something it is not.
    func testTheCharacterSetForAnEncodingConvertsBackToThatEncoding() {
        // Three deliberate approximations, each documented where it is made: ISO 8859-1 is
        // named latin1, which MySQL defines as Windows-1252; non-lossy ASCII and big-endian
        // UTF-32 are named for their general form.
        let approximations: Set<String.Encoding> = [
            .isoLatin1, .nonLossyASCII, .utf32BigEndian,
        ]
        let encodings: [String.Encoding] = [
            .ascii, .japaneseEUC, .utf8, .isoLatin1, .nonLossyASCII, .shiftJIS, .isoLatin2,
            .unicode, .windowsCP1251, .windowsCP1252, .windowsCP1250, .macOSRoman,
            .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian,
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.isoLatinGreek.rawValue))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.isoLatin5.rawValue))),
        ]
        for stringEncoding in encodings where !approximations.contains(stringEncoding) {
            guard let characterSet = SPMySQLConnection.mySQLCharset(forStringEncoding: stringEncoding.rawValue) else {
                XCTFail("no character set for \(stringEncoding)")
                continue
            }
            XCTAssertEqual(encoding(for: characterSet), stringEncoding,
                           "\(characterSet) does not convert back to the encoding it was named for")
        }
    }

    /// Windows-1253 and Windows-1254 are not MySQL's greek and latin5 - they disagree over 22
    /// and 25 bytes - so they no longer name them for an import.
    func testTheWindowsCodePagesDoNotNameTheISOCharacterSets() {
        XCTAssertNil(SPMySQLConnection.mySQLCharset(forStringEncoding: String.Encoding.windowsCP1253.rawValue))
        XCTAssertNil(SPMySQLConnection.mySQLCharset(forStringEncoding: String.Encoding.windowsCP1254.rawValue))
    }

    /// The character sets that were already right stay right.
    func testTheMappingsThatWereCorrectAreUnchanged() throws {
        XCTAssertEqual(encoding(for: "utf8mb4"), .utf8)
        XCTAssertEqual(try XCTUnwrap("Grüße".data(using: encoding(for: "latin1"))),
                       Data([0x47, 0x72, 0xFC, 0xDF, 0x65]))
        // The GBK sequence BF 5C, whose second byte is a backslash.
        XCTAssertEqual(try XCTUnwrap("縗".data(using: encoding(for: "gbk"))), Data([0xBF, 0x5C]))
        XCTAssertEqual(try XCTUnwrap("デ".data(using: encoding(for: "sjis"))), Data([0x83, 0x66]))
    }
}
