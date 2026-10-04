//
//  SAParserUtilsTestSupport.swift
//  Sequel Ace
//

import Foundation
import XCTest

/// Owns the regression fixtures in Swift while exposing only the C-call block
/// needed by the legacy Objective-C test target. `public` makes this test-only
/// helper visible in the target's generated Swift header.
@objc public final class SAParserUtilsTestSupport: NSObject {

    @objc(runTestsWithCounter:)
    public static func runTests(counter: @escaping (UnsafePointer<CChar>, UInt) -> UInt) {
        testShortExactBuffers(counter: counter)
        testLongLexerToken(counter: counter)
    }

    private static func testShortExactBuffers(counter: (UnsafePointer<CChar>, UInt) -> UInt) {
        let cases = [
            "", "a", "ab", "abc", "abcd", "selec", "abcdef", "abcdefg", "abcdefgh", "abcdefghi",
            "ä", "こ", "🍏", "🍏🍋"
        ]

        for string in cases {
            let data = Data(string.utf8)
            let byteLength = data.count
            let allocation = UnsafeMutableRawPointer.allocate(
                byteCount: byteLength + 1,
                alignment: MemoryLayout<UInt>.alignment
            )
            defer { allocation.deallocate() }

            // Start one byte into the allocation so the input is unaligned and
            // ends exactly at the allocation boundary, with no NUL terminator.
            // Under ASan, any overread enters the redzone.
            let input = allocation.advanced(by: 1)
            if byteLength > 0 {
                data.withUnsafeBytes { source in
                    input.copyMemory(from: source.baseAddress!, byteCount: byteLength)
                }
            }

            let bytes = input.assumingMemoryBound(to: CChar.self)
            XCTAssertEqual(
                counter(UnsafePointer(bytes), UInt(byteLength)),
                UInt(string.utf16.count),
                "character count for \(string) (\(byteLength) bytes)"
            )
        }
    }

    private static func testLongLexerToken(counter: (UnsafePointer<CChar>, UInt) -> UInt) {
        // The 10-byte pattern shifts relative to the 8-byte word boundary on
        // every repetition, exercising the bulk path and its tail handling.
        let pattern: [UInt8] = [
            0x61,                           // one UTF-8 byte, one UTF-16 code unit
            0xc3, 0xa4,                     // two UTF-8 bytes, one UTF-16 code unit
            0xe3, 0x81, 0x93,               // three UTF-8 bytes, one UTF-16 code unit
            0xf0, 0x9f, 0x8d, 0x8f          // four UTF-8 bytes, two UTF-16 code units
        ]
        let repetitions = 100_000
        let byteLength = pattern.count * repetitions
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: byteLength)
        defer { bytes.deallocate() }

        for repetition in 0..<repetitions {
            let offset = repetition * pattern.count
            for (index, byte) in pattern.enumerated() {
                bytes[offset + index] = byte
            }
        }

        let input = UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self)
        XCTAssertEqual(counter(input, UInt(byteLength)), UInt(5 * repetitions))
    }
}
