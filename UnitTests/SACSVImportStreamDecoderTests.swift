//
//  SACSVImportStreamDecoderTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import XCTest

final class SACSVImportStreamDecoderTests: XCTestCase {

    private func makeDecoder(_ encoding: String.Encoding, terminator: String = "\n") -> SACSVImportStreamDecoder {
        SACSVImportStreamDecoder(encoding: encoding.rawValue, lineTerminator: terminator)
    }

    private func bytes(_ text: String, _ encoding: String.Encoding) -> Data {
        guard let data = text.data(using: encoding) else {
            XCTFail("\(text) is not representable in \(encoding)")
            return Data()
        }
        return data
    }

    /// Feeds every chunk, then signals end of input, returning one string per call.
    private func feed(_ decoder: SACSVImportStreamDecoder, _ chunks: [Data]) throws -> [String] {
        var pieces = try chunks.map { try decoder.text(byAppending: $0, endOfInput: false) }
        pieces.append(try decoder.text(byAppending: Data(), endOfInput: true))
        return pieces
    }

    // MARK: - Single-byte and UTF-8 behaviour

    func testCompleteLinesAreReturnedAndTheTailWaitsForEndOfInput() throws {
        let decoder = makeDecoder(.utf8)

        XCTAssertEqual(try decoder.text(byAppending: bytes("a,b\nc,d\ne,f", .utf8), endOfInput: false), "a,b\nc,d\n")
        XCTAssertEqual(try decoder.text(byAppending: Data(), endOfInput: true), "e,f")
    }

    func testUTF8CharacterSplitAcrossChunksIsHeldUntilComplete() throws {
        let decoder = makeDecoder(.utf8)
        let eAcute = Array(bytes("é", .utf8))

        XCTAssertEqual(try decoder.text(byAppending: bytes("x\n", .utf8) + Data([eAcute[0]]), endOfInput: false), "x\n")
        XCTAssertEqual(try decoder.text(byAppending: Data([eAcute[1]]) + bytes("\n", .utf8), endOfInput: false), "é\n")
        XCTAssertEqual(try decoder.text(byAppending: Data(), endOfInput: true), "")
    }

    func testTerminatorSplitAcrossChunksIsHeldUntilComplete() throws {
        let decoder = makeDecoder(.utf8, terminator: "\r\n")

        XCTAssertEqual(try decoder.text(byAppending: bytes("a\r", .utf8), endOfInput: false), "")
        XCTAssertEqual(try decoder.text(byAppending: bytes("\nb", .utf8), endOfInput: false), "a\r\n")
        XCTAssertEqual(try decoder.text(byAppending: Data(), endOfInput: true), "b")
    }

    func testUTF8ByteOrderMarkIsNotDecodedIntoTheFirstField() throws {
        let decoder = makeDecoder(.utf8)
        let data = Data([0xEF, 0xBB, 0xBF]) + bytes("id,name\n1,x", .utf8)

        XCTAssertEqual(try feed(decoder, [data]), ["id,name\n", "1,x"])
    }

    func testUndecodableBytesThrow() {
        let decoder = makeDecoder(.utf8)

        XCTAssertThrowsError(try decoder.text(byAppending: Data([0x41, 0xFF, 0x0A]), endOfInput: false)) { error in
            XCTAssertEqual((error as NSError).domain, SACSVImportStreamDecoder.errorDomain)
            XCTAssertEqual((error as NSError).code, SACSVImportStreamDecoder.undecodableErrorCode)
        }
    }

    func testTruncatedCharacterAtEndOfInputThrows() throws {
        let decoder = makeDecoder(.utf8)

        XCTAssertEqual(try decoder.text(byAppending: bytes("a\n", .utf8) + Data([0xC3]), endOfInput: false), "a\n")
        XCTAssertThrowsError(try decoder.text(byAppending: Data(), endOfInput: true))
    }

    func testEmptyTerminatorDefersEverythingToEndOfInput() throws {
        let decoder = makeDecoder(.utf8, terminator: "")

        XCTAssertEqual(try decoder.text(byAppending: bytes("a\nb\n", .utf8), endOfInput: false), "")
        XCTAssertEqual(try decoder.text(byAppending: Data(), endOfInput: true), "a\nb\n")
    }

    func testEmptyInputYieldsEmptyText() throws {
        XCTAssertEqual(try makeDecoder(.utf8).text(byAppending: Data(), endOfInput: true), "")
        XCTAssertEqual(try makeDecoder(.utf16LittleEndian).text(byAppending: Data(), endOfInput: true), "")
        XCTAssertEqual(try makeDecoder(.utf16).text(byAppending: Data(), endOfInput: true), "")
    }

    // MARK: - UTF-16 / UTF-32

    /// U+0A41 followed by U+0100 puts the bytes `0A 00` at an odd offset in
    /// little-endian UTF-16, and U+0100 followed by U+0A41 puts `00 0A` at an
    /// odd offset in big-endian UTF-16. A byte-level scan reads both as a
    /// newline; a code-unit scan must not.
    private let terminatorLookalikes = "\u{0A41}\u{0100}\u{0A41}"

    func testUTF16TerminatorIsOnlyMatchedOnCodeUnitBoundaries() throws {
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            let decoder = makeDecoder(encoding)
            let firstChunk = bytes("a" + terminatorLookalikes, encoding)

            XCTAssertEqual(try decoder.text(byAppending: firstChunk, endOfInput: false), "", "\(encoding)")
            XCTAssertEqual(try decoder.text(byAppending: bytes("\nb", encoding), endOfInput: false), "a" + terminatorLookalikes + "\n", "\(encoding)")
            XCTAssertEqual(try decoder.text(byAppending: Data(), endOfInput: true), "b", "\(encoding)")
        }
    }

    func testUTF16ByteOrderMarkIsConsumedForExplicitByteOrders() throws {
        let littleEndian = makeDecoder(.utf16LittleEndian)
        let littleEndianData = Data([0xFF, 0xFE]) + bytes("id,name\n1,x", .utf16LittleEndian)
        XCTAssertEqual(try feed(littleEndian, [littleEndianData]), ["id,name\n", "1,x"])

        let bigEndian = makeDecoder(.utf16BigEndian)
        let bigEndianData = Data([0xFE, 0xFF]) + bytes("id,name\n1,x", .utf16BigEndian)
        XCTAssertEqual(try feed(bigEndian, [bigEndianData]), ["id,name\n", "1,x"])
    }

    func testUnmarkedUTF16FollowsTheByteOrderMarkForEveryChunk() throws {
        let decoder = makeDecoder(.utf16)
        let firstChunk = Data([0xFF, 0xFE]) + bytes("id,name\n", .utf16LittleEndian)
        let secondChunk = bytes("1,x\n", .utf16LittleEndian)

        XCTAssertEqual(try decoder.text(byAppending: firstChunk, endOfInput: false), "id,name\n")
        XCTAssertEqual(try decoder.text(byAppending: secondChunk, endOfInput: false), "1,x\n")
        XCTAssertEqual(decoder.resolvedEncoding, .utf16LittleEndian)
    }

    func testUnmarkedUTF16WithoutByteOrderMarkDefaultsToBigEndian() throws {
        let decoder = makeDecoder(.utf16)

        XCTAssertEqual(try feed(decoder, [bytes("a\nb", .utf16BigEndian)]), ["a\n", "b"])
        XCTAssertEqual(decoder.resolvedEncoding, .utf16BigEndian)
    }

    func testByteOrderMarkSplitAcrossChunksIsHeld() throws {
        let decoder = makeDecoder(.utf16)
        let payload = Data([0xFF, 0xFE]) + bytes("a\n", .utf16LittleEndian)

        XCTAssertEqual(try decoder.text(byAppending: payload.prefix(1), endOfInput: false), "")
        XCTAssertEqual(try decoder.text(byAppending: payload.dropFirst(1), endOfInput: false), "a\n")
    }

    func testUTF32ByteOrderMarkSelectsByteOrderAndIsConsumed() throws {
        let decoder = makeDecoder(.utf32)
        let data = Data([0xFF, 0xFE, 0x00, 0x00]) + bytes("id\n1", .utf32LittleEndian)

        XCTAssertEqual(try feed(decoder, [data]), ["id\n", "1"])
        XCTAssertEqual(decoder.resolvedEncoding, .utf32LittleEndian)
    }

    func testUTF16CRLFTerminatorSplitAcrossChunksIsHeld() throws {
        let decoder = makeDecoder(.utf16LittleEndian, terminator: "\r\n")
        let data = bytes("a\r\nb", .utf16LittleEndian)

        // Cut inside the four-byte terminator: "a" (2) + "\r" (2) + first byte of "\n".
        XCTAssertEqual(try decoder.text(byAppending: data.prefix(5), endOfInput: false), "")
        XCTAssertEqual(try decoder.text(byAppending: data.dropFirst(5), endOfInput: false), "a\r\n")
        XCTAssertEqual(try decoder.text(byAppending: Data(), endOfInput: true), "b")
    }

    // MARK: - Chunking invariants

    /// Whatever the chunk boundaries, the pieces must concatenate back to the
    /// original text and every piece before the last must end on a terminator.
    func testArbitraryChunkBoundariesPreserveTextInEveryEncoding() throws {
        let text = "id,name,note\n1,\"héllo, wörld\",\(terminatorLookalikes)\n2,日本語,🙂\r\n3,last"
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian]
        let chunkSizes = [1, 2, 3, 5, 7, 11, 13, 64]

        for encoding in encodings {
            let data = bytes(text, encoding)
            for chunkSize in chunkSizes {
                let decoder = makeDecoder(encoding)
                let chunks = stride(from: 0, to: data.count, by: chunkSize).map { start in
                    data.subdata(in: start..<min(start + chunkSize, data.count))
                }

                let pieces = try feed(decoder, chunks)
                let context = "\(encoding) chunked by \(chunkSize)"

                XCTAssertEqual(pieces.joined(), text, context)
                for piece in pieces.dropLast() where !piece.isEmpty {
                    // Compare scalars: "\r\n" is a single grapheme, so hasSuffix("\n") would miss it.
                    XCTAssertEqual(piece.unicodeScalars.last, "\n", "\(context): piece \(piece.debugDescription) does not end on a terminator")
                }
            }
        }
    }
}
