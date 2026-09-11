//
//  SAImportProgressReporter.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//

import Foundation

/// One progress-sheet update: the bar's new value and the text beneath it.
@objc final class SAImportProgressUpdate: NSObject {

    @objc let barValue: Double
    @objc let text: String

    init(barValue: Double, text: String) {
        self.barValue = barValue
        self.text = text
        super.init()
    }
}

/// Throttles and formats the progress an import pushes to its sheet.
///
/// The importer calls `update(...)` after every row or statement; the reporter
/// answers with an update at most once per `minimumInterval` and `nil` the rest
/// of the time. Elapsed time is measured on a monotonic clock so a wall-clock
/// change during a long import cannot suppress updates.
@objc final class SAImportProgressReporter: NSObject {

    static let defaultMinimumInterval: TimeInterval = 0.1

    private let unknownTotalFormat: String
    private let knownTotalFormat: String
    private let minimumInterval: TimeInterval
    private let clock: () -> TimeInterval
    private var lastUpdateTime: TimeInterval?

    /// - Parameter unknownTotalFormat: format used when the file is compressed
    ///   and the decompressed total is unknown. Takes one `%@`, the formatted
    ///   decompressed position.
    @objc convenience init(unknownTotalFormat: String) {
        self.init(unknownTotalFormat: unknownTotalFormat,
                  minimumInterval: SAImportProgressReporter.defaultMinimumInterval,
                  clock: { ProcessInfo.processInfo.systemUptime })
    }

    init(unknownTotalFormat: String, minimumInterval: TimeInterval, clock: @escaping () -> TimeInterval) {
        self.unknownTotalFormat = unknownTotalFormat
        self.knownTotalFormat = NSLocalizedString("Imported %@ of %@", comment: "import progress text")
        self.minimumInterval = minimumInterval
        self.clock = clock
        super.init()
    }

    /// Returns the update to show, or `nil` when the last one is too recent.
    ///
    /// - Parameters:
    ///   - bytesProcessed: position in the decompressed data.
    ///   - totalBytes: the file's size on disk.
    ///   - isCompressed: whether the file is compressed, in which case the bar
    ///     tracks `compressedBytesRead` against `totalBytes` and the text uses
    ///     the unknown-total format.
    ///   - compressedBytesRead: the file handle's position in the compressed file.
    @objc(updateForBytesProcessed:totalBytes:isCompressed:compressedBytesRead:)
    func update(bytesProcessed: UInt, totalBytes: UInt, isCompressed: Bool, compressedBytesRead: UInt) -> SAImportProgressUpdate? {
        let now = clock()
        if let last = lastUpdateTime, now - last < minimumInterval {
            return nil
        }
        lastUpdateTime = now

        let processedText = ByteCountFormatter.string(fromByteCount: Int64(bytesProcessed), countStyle: .file)
        if isCompressed {
            return SAImportProgressUpdate(barValue: Double(compressedBytesRead),
                                          text: String(format: unknownTotalFormat, processedText))
        }
        let totalText = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        return SAImportProgressUpdate(barValue: Double(bytesProcessed),
                                      text: String(format: knownTotalFormat, processedText, totalText))
    }
}
