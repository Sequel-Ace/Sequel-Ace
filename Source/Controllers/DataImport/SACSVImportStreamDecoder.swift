//
//  SACSVImportStreamDecoder.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// Turns the raw byte stream of a CSV file into text, cutting it only at line
/// terminators that sit on character boundaries.
///
/// The CSV importer reads its file in fixed-size chunks, so a chunk can end in
/// the middle of a character. The decoder holds bytes back until a line
/// terminator has been seen and hands out the decoded text up to and including
/// the last complete line. Fixed-width encodings (UTF-16, UTF-32) are scanned
/// one code unit at a time, so a terminator byte that merely occurs inside a
/// code unit is never mistaken for a line ending, and a leading byte-order mark
/// is consumed instead of being decoded into the first field.
@objc final class SACSVImportStreamDecoder: NSObject {

    @objc static let errorDomain = "SACSVImportStreamDecoder"
    @objc static let undecodableErrorCode = 1

    private let requestedEncoding: String.Encoding
    private let lineTerminator: String

    /// The encoding used to decode the stream. It differs from the requested
    /// one only for the byte-order-agnostic Unicode encodings, which are pinned
    /// to the byte order named by the file's BOM (or, without one, to
    /// Foundation's big-endian default) so every chunk decodes consistently.
    private(set) var resolvedEncoding: String.Encoding

    private let codeUnitWidth: Int
    private var terminatorBytes: [UInt8] = []
    private var buffer = Data()
    private var scanPosition = 0
    private var hasResolvedPreamble = false

    /// - Parameters:
    ///   - encoding: The `NSStringEncoding` the file is to be read with.
    ///   - lineTerminator: The line terminator the CSV parser is configured
    ///     with; it is encoded in the same encoding to find line boundaries.
    @objc init(encoding: UInt, lineTerminator: String) {
        let encoding = String.Encoding(rawValue: encoding)
        requestedEncoding = encoding
        resolvedEncoding = encoding
        self.lineTerminator = lineTerminator
        codeUnitWidth = SACSVImportStreamDecoder.codeUnitWidth(for: encoding)
        super.init()
    }

    /// Appends `data` and returns the decoded text of every line that is now
    /// complete. Returns an empty string while no line terminator has been seen
    /// yet. With `endOfInput` set, everything still buffered is decoded as the
    /// final (possibly unterminated) line.
    ///
    /// Throws when the buffered bytes cannot be decoded with the encoding.
    @objc(textByAppendingData:endOfInput:error:)
    func text(byAppending data: Data, endOfInput: Bool) throws -> String {
        buffer.append(data)

        if !hasResolvedPreamble {
            guard buffer.count >= preambleLength || endOfInput else { return "" }
            resolvePreamble()
        }

        let segmentEnd: Int
        if endOfInput {
            segmentEnd = buffer.count
        } else if let lastTerminatorEnd = scanForTerminators() {
            segmentEnd = lastTerminatorEnd
        } else {
            return ""
        }

        let text: String
        if segmentEnd == 0 {
            text = ""
        } else if let decoded = String(data: buffer.prefix(segmentEnd), encoding: resolvedEncoding) {
            text = decoded
        } else {
            throw NSError(
                domain: SACSVImportStreamDecoder.errorDomain,
                code: SACSVImportStreamDecoder.undecodableErrorCode,
                userInfo: [NSLocalizedDescriptionKey: "The CSV data could not be decoded using the selected encoding."]
            )
        }

        buffer = segmentEnd < buffer.count ? buffer.subdata(in: segmentEnd..<buffer.count) : Data()
        scanPosition = max(0, scanPosition - segmentEnd)
        return text
    }

    // MARK: - Scanning

    /// Scans forward from the last examined position and returns the offset
    /// just past the last complete terminator, if any. Comparisons only start
    /// on code unit boundaries. A terminator prefix cut off by the end of the
    /// buffer is left unexamined so the next chunk can complete it.
    private func scanForTerminators() -> Int? {
        let terminatorLength = terminatorBytes.count
        guard terminatorLength > 0 else { return nil }

        let count = buffer.count
        var position = scanPosition
        var lastTerminatorEnd: Int?

        buffer.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            terminatorBytes.withUnsafeBytes { (terminator: UnsafeRawBufferPointer) in
                guard let terminatorBase = terminator.baseAddress else { return }
                while position + codeUnitWidth <= count {
                    let remaining = count - position
                    let comparable = min(remaining, terminatorLength)
                    if memcmp(base + position, terminatorBase, comparable) == 0 {
                        if remaining < terminatorLength { break }
                        position += terminatorLength
                        lastTerminatorEnd = position
                    } else {
                        position += codeUnitWidth
                    }
                }
            }
        }

        scanPosition = position
        return lastTerminatorEnd
    }

    // MARK: - Byte order and BOM handling

    /// Bytes needed at the start of the stream before a BOM can be recognised
    /// and, for the Unicode encodings, the byte order settled. Zero for
    /// encodings that carry no BOM.
    private var preambleLength: Int {
        switch requestedEncoding {
        case .utf8:
            return 3
        case .utf16, .utf16BigEndian, .utf16LittleEndian:
            return 2
        case .utf32, .utf32BigEndian, .utf32LittleEndian:
            return 4
        default:
            return 0
        }
    }

    /// Pins the decoding encoding to a concrete byte order, drops a matching
    /// BOM from the buffer, and derives the terminator's byte sequence in that
    /// same byte order.
    private func resolvePreamble() {
        hasResolvedPreamble = true

        let (encoding, bomLength) = SACSVImportStreamDecoder.byteOrder(for: requestedEncoding, leading: buffer)
        resolvedEncoding = encoding
        if bomLength > 0 {
            buffer = bomLength < buffer.count ? buffer.subdata(in: bomLength..<buffer.count) : Data()
        }

        terminatorBytes = lineTerminator.data(using: encoding).map { [UInt8]($0) } ?? []
    }

    /// Returns the concrete encoding to decode with and the length of the BOM
    /// to drop from the start of `data`. UTF-8 is stripped explicitly rather
    /// than relying on Foundation to do so, since only the byte-order-agnostic
    /// UTF-16/UTF-32 encodings are documented to consume their BOM.
    private static func byteOrder(for encoding: String.Encoding, leading data: Data) -> (String.Encoding, bomLength: Int) {
        let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
        let utf16LittleEndianBOM: [UInt8] = [0xFF, 0xFE]
        let utf16BigEndianBOM: [UInt8] = [0xFE, 0xFF]
        let utf32LittleEndianBOM: [UInt8] = [0xFF, 0xFE, 0x00, 0x00]
        let utf32BigEndianBOM: [UInt8] = [0x00, 0x00, 0xFE, 0xFF]

        switch encoding {
        case .utf8:
            return (encoding, data.starts(with: utf8BOM) ? 3 : 0)
        case .utf16:
            if data.starts(with: utf16LittleEndianBOM) { return (.utf16LittleEndian, 2) }
            if data.starts(with: utf16BigEndianBOM) { return (.utf16BigEndian, 2) }
            return (.utf16BigEndian, 0)
        case .utf16LittleEndian:
            return (encoding, data.starts(with: utf16LittleEndianBOM) ? 2 : 0)
        case .utf16BigEndian:
            return (encoding, data.starts(with: utf16BigEndianBOM) ? 2 : 0)
        case .utf32:
            if data.starts(with: utf32LittleEndianBOM) { return (.utf32LittleEndian, 4) }
            if data.starts(with: utf32BigEndianBOM) { return (.utf32BigEndian, 4) }
            return (.utf32BigEndian, 0)
        case .utf32LittleEndian:
            return (encoding, data.starts(with: utf32LittleEndianBOM) ? 4 : 0)
        case .utf32BigEndian:
            return (encoding, data.starts(with: utf32BigEndianBOM) ? 4 : 0)
        default:
            return (encoding, 0)
        }
    }

    /// The scan stride: a terminator can only start on a code unit boundary,
    /// so fixed-width encodings are stepped by their unit size.
    private static func codeUnitWidth(for encoding: String.Encoding) -> Int {
        switch encoding {
        case .utf16, .utf16BigEndian, .utf16LittleEndian:
            return 2
        case .utf32, .utf32BigEndian, .utf32LittleEndian:
            return 4
        default:
            return 1
        }
    }
}
