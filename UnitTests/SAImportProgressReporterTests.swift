//
//  SAImportProgressReporterTests.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation
import XCTest

final class SAImportProgressReporterTests: XCTestCase {

    private var now: TimeInterval = 1_000

    private func makeReporter(minimumInterval: TimeInterval = 0.1) -> SAImportProgressReporter {
        SAImportProgressReporter(unknownTotalFormat: "Imported %@ of test data",
                                 minimumInterval: minimumInterval,
                                 clock: { self.now })
    }

    /// The app's binary byte formatter, which the importer has always used for progress text.
    private func bytes(_ count: UInt) -> String {
        ByteCountFormatter.string(byteSize: Int64(count)) as String
    }

    // MARK: - Formatting

    func testUncompressedUpdateTracksTheDecompressedPositionAgainstTheTotal() {
        let update = makeReporter().update(bytesProcessed: 2_500, totalBytes: 10_000, isCompressed: false, compressedBytesRead: 0)

        XCTAssertEqual(update?.barValue, 2_500)
        XCTAssertEqual(update?.text, String(format: NSLocalizedString("Imported %@ of %@", comment: ""), bytes(2_500), bytes(10_000)))
    }

    func testCompressedUpdateTracksTheCompressedPositionAndUsesTheUnknownTotalFormat() {
        let update = makeReporter().update(bytesProcessed: 2_500, totalBytes: 800, isCompressed: true, compressedBytesRead: 300)

        XCTAssertEqual(update?.barValue, 300)
        XCTAssertEqual(update?.text, "Imported \(bytes(2_500)) of test data")
    }

    func testByteCountsKeepTheImporterBinaryUnits() {
        let update = makeReporter().update(bytesProcessed: 1_048_576, totalBytes: 3 * 1_073_741_824, isCompressed: false, compressedBytesRead: 0)

        // The exact digits depend on the locale's decimal separator; the units do not.
        let words = update?.text.split(separator: " ").map(String.init) ?? []
        XCTAssertTrue(words.contains("MiB"), update?.text ?? "nil")
        XCTAssertTrue(words.contains("GiB"), update?.text ?? "nil")
        XCTAssertFalse(words.contains("MB"), update?.text ?? "nil")
    }

    // MARK: - Throttling

    func testTheFirstUpdateIsNeverThrottled() {
        XCTAssertNotNil(makeReporter().update(bytesProcessed: 1, totalBytes: 2, isCompressed: false, compressedBytesRead: 0))
    }

    func testUpdatesWithinTheMinimumIntervalAreSuppressed() {
        let reporter = makeReporter()
        XCTAssertNotNil(reporter.update(bytesProcessed: 1, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))

        now += 0.05
        XCTAssertNil(reporter.update(bytesProcessed: 2, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))
        now += 0.049
        XCTAssertNil(reporter.update(bytesProcessed: 3, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))
    }

    func testAnUpdateIsDeliveredOnceTheMinimumIntervalHasElapsed() {
        let reporter = makeReporter()
        XCTAssertNotNil(reporter.update(bytesProcessed: 1, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))

        now += 0.1
        let update = reporter.update(bytesProcessed: 4, totalBytes: 10, isCompressed: false, compressedBytesRead: 0)
        XCTAssertEqual(update?.barValue, 4)
    }

    func testASuppressedUpdateDoesNotRestartTheInterval() {
        let reporter = makeReporter()
        XCTAssertNotNil(reporter.update(bytesProcessed: 1, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))

        now += 0.08
        XCTAssertNil(reporter.update(bytesProcessed: 2, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))
        now += 0.02
        XCTAssertNotNil(reporter.update(bytesProcessed: 3, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))
    }

    func testTheDeliveredUpdateCarriesTheLatestPositionNotTheSuppressedOnes() {
        let reporter = makeReporter()
        _ = reporter.update(bytesProcessed: 1, totalBytes: 10, isCompressed: false, compressedBytesRead: 0)
        now += 0.01
        _ = reporter.update(bytesProcessed: 5, totalBytes: 10, isCompressed: false, compressedBytesRead: 0)
        now += 0.1
        XCTAssertEqual(reporter.update(bytesProcessed: 9, totalBytes: 10, isCompressed: false, compressedBytesRead: 0)?.barValue, 9)
    }

    func testEachReporterStartsWithAFreshInterval() {
        let first = makeReporter()
        XCTAssertNotNil(first.update(bytesProcessed: 1, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))

        XCTAssertNotNil(makeReporter().update(bytesProcessed: 1, totalBytes: 10, isCompressed: false, compressedBytesRead: 0))
    }

    func testTheDefaultMinimumIntervalIsATenthOfASecond() {
        XCTAssertEqual(SAImportProgressReporter.defaultMinimumInterval, 0.1)
    }
}
