//
//  SAStatementBytes.swift
//  SPMySQLFramework
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation

/// What one attempt to send a statement gets: the bytes to send, in the encoding they were built
/// in, or - when the session the attempt is on cannot take them - the refusal, with the error the
/// server would have given.
@objcMembers
public final class SAStatementAttempt: NSObject {
    /// The bytes to send; nil when the statement is refused.
    public let bytes: NSData?
    /// The encoding the bytes were built in, which is the one the statement's result is read in.
    public let encoding: UInt
    /// The error of a refused statement; 0 when the bytes are there.
    public let errorID: UInt
    public let message: String?
    public let sqlState: String?

    /// An attempt whose bytes fit the session.
    init(bytes: NSData, encoding: UInt) {
        self.bytes = bytes
        self.encoding = encoding
        errorID = 0
        message = nil
        sqlState = nil
    }

    /// An attempt refused because `length` bytes are more than the session takes in one packet,
    /// with the error the server gives for such a statement (`ER_NET_PACKET_TOO_LARGE`).
    init(refusingLength length: Int, over maximumSize: UInt, encoding: UInt) {
        bytes = nil
        self.encoding = encoding
        errorID = 1153
        message = String(
            format: NSLocalizedString(
                "The query length of %lu bytes is larger than max_allowed_packet size (%lu).",
                comment: "error message if max_allowed_packet < query size"
            ),
            UInt(length), maximumSize
        )
        sqlState = "08S01"
    }
}

/// The bytes of one statement, built for the session that sends them.
///
/// A statement is measured before the session it goes to is held - the one check that can still
/// raise the packet limit and reconnect - and those bytes are the ones the first attempt sends,
/// unless the session it holds reads statements in another character set: then, and for a retry
/// that lands on such a session after a reconnect, the bytes are built again for it, where bytes
/// built once up front would go out as they were. The bytes on hand are kept while the encoding
/// stays the same, so a large statement is not serialised twice for nothing. Each attempt's bytes
/// are measured against the packet limit of the session they go to - the same text can need more
/// bytes in another character set than the check before the first attempt measured - and a
/// statement the session cannot take is refused with the error the server would give, rather than
/// sent for the server to refuse and close the connection over.
@objcMembers
public final class SAStatementBytes: NSObject {
    /// `encodingNamedByTheCaller` of a caller that named none: the statement is then serialised in
    /// the character set the session reads statements in.
    public static let encodingOfTheSession: UInt = 0

    /// Kept as the object the caller passed, not bridged to a Swift string: a statement that
    /// converts itself (the tests send one that reports when it is being serialised) is serialised
    /// by its own conversion.
    public let statement: NSString
    /// The encoding the caller asked for, as an import does for the file it reads, or
    /// `encodingOfTheSession`.
    private let encodingNamedByTheCaller: UInt
    private var bytesOnHand: (bytes: NSData, encoding: UInt)?

    /// The encoding the bytes on hand were built in; `encodingOfTheSession` before the statement
    /// was first measured or built.
    public var encoding: UInt { bytesOnHand?.encoding ?? Self.encodingOfTheSession }

    public init(statement: NSString, encodingNamedByTheCaller: UInt) {
        self.statement = statement
        self.encodingNamedByTheCaller = encodingNamedByTheCaller
    }

    /// The statement's length in bytes on a session that reads statements in `sessionEncoding`:
    /// what the check against the packet limit measures before the session is held. The bytes are
    /// kept for the first attempt, which sends them unless the session it holds reads another
    /// encoding.
    public func length(onSessionReading sessionEncoding: UInt) -> UInt {
        UInt(bytes(in: encoding(onSessionReading: sessionEncoding)).length)
    }

    /// The bytes for an attempt on a session that reads statements in `sessionEncoding` and takes
    /// at most `maximumSize` bytes in one packet. The bytes on hand - measured before, or built
    /// for the attempt before - are reused when they were built in the encoding this session reads.
    public func attempt(onSessionReading sessionEncoding: UInt, maximumSize: UInt) -> SAStatementAttempt {
        let encoding = encoding(onSessionReading: sessionEncoding)
        let data = bytes(in: encoding)
        if UInt(data.length) > maximumSize {
            return SAStatementAttempt(refusingLength: data.length, over: maximumSize, encoding: encoding)
        }
        return SAStatementAttempt(bytes: data, encoding: encoding)
    }

    /// The encoding the statement is serialised in for a session reading `sessionEncoding`: the
    /// one the caller named, if any.
    private func encoding(onSessionReading sessionEncoding: UInt) -> UInt {
        encodingNamedByTheCaller == Self.encodingOfTheSession ? sessionEncoding : encodingNamedByTheCaller
    }

    /// The statement's bytes in `encoding` - the ones on hand when they were built in it, built
    /// and kept otherwise.
    private func bytes(in encoding: UInt) -> NSData {
        if let onHand = bytesOnHand, onHand.encoding == encoding {
            return onHand.bytes
        }
        // With lossy conversion allowed Foundation serialises every string, a character the
        // character set lacks as its replacement character; the empty statement is for the
        // conversion that still gives nothing, and is the server's to refuse.
        let data = (statement.data(using: encoding, allowLossyConversion: true) ?? Data()) as NSData
        bytesOnHand = (data, encoding)
        return data
    }
}
