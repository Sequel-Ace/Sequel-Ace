//
//  OSLog.swift
//  Sequel Ace
//
//  Created by James on 19/1/2021.
//  Copyright © 2021 Sequel-Ace. All rights reserved.
//

//
//  OSLog.swift
//  Etcetera
//
//  Created by Jared Sinclair on 8/15/15.
//  Copyright © 2015 Nice Boy LLC. All rights reserved.
//
// swiftlint:disable file_length - This is intentionally a one-file, a drop-in.
// swiftlint:disable identifier_name - Clarity!
// swiftlint:disable line_length - I dislike multi-line function signatures.
// swiftlint:disable function_parameter_count - Some problems have lots o' variables.

import Foundation
import os.log

/// Quality-of-life extension of OSLog.
///
/// ## Initial Setup
///
/// First initialize an OSLog instance, ideally for reuse across all applicable
/// logging scenarios:
///
///     static let MyAppLog = OSLog(subsystem: "com.domain.MyApp", category: "App")
///
/// In lieu of any official naming guidelines, here are my recommendations:
///
/// - Your subsystem should use reverse-dns style `com.domain.Reversed`.
///
/// - If your app is broken up into frameworks, include the framework name in
///   the subsystem: "com.domain.MyAppLib" or "com.domain.MyApp.MyLib", etc.
///
/// - Use the category name to describe the general subject matter of the code.
///   This may or may not cut across subsystems. For example, if you are logging
///   all of your CoreData errors, it might be a good idea to use "CoreData" as
///   the category. The category name will appear in [Brackets] in the console
///   output inside Xcode, so keep it short and human-readable. Camel-casing or
///   word capitalization is preferable.
///
/// ## General Usage
///
/// Use the extension methods below wherever you would otherwise use an
/// `os_log()` call or — gasp — a `print()` call:
///
///     MyAppLog.log("Something happened.")
///     MyAppLog.debug("For British eyes only.")
///     MyAppLog.info("Red leather, yellow leather.")
///     MyAppLog.error("Uh oh.")
///     MyAppLog.fault("It's not my...")
///
/// ## Privacy
///
/// Use caution when logging. You don't want to accidentally reveal your app's
/// secrets in log output. You can control the level of security used via the
/// `Privacy` type below. The `.redacted` level will redact content besides
/// static strings and scalar values (see note below for a caveat). The
/// `.visible` level will not redact any logged content.
///
/// - Configure the security privacy on an app-wide basis by setting the value
///   of Options.defaultPrivacy. The default for release builds is `.redacted`.
///   For debug builds, it defaults to `.visible`.
///
/// - Configure the security privacy on a per-call basis by overriding the
///   default argument passed to one of the methods below.
///
/// Using the `.redacted` privacy level is not necessarily enough to redact
/// sensitive console output. Additional environmental configuration may allow
/// sensitive content to appear in plain text, such as when the application is
/// connected to a debugger.
///
/// - SeeAlso: https://developer.apple.com/documentation/os/logging
///
/// ## Source Location
///
/// When called from Objective-C code, os_log will display the caller's source
/// location (function, file, and line number) in the console. Not so with
/// Swift. As a stopgap until Apple fixes this deficiency, you can optionally
/// enable source location when using the "foo(value:" logging methods below:
///
/// - Configure the setting on an app-wide basis by setting the value of
///   `Options.includeSourceLocationInValueLogs` to `true`. For debug builds,
///   the default is `true` because nothing is worse than noisy, disembodied
///   console logs while debugging.
///
/// - Configure the setting on a per-call basis by overriding the default
///   argument passed to the logging method.
///
/// - Note: The `foo(format:args:)` logging methods below will not include any
/// source location info unless you have included it manually in your format
/// string and arguments.
///
///  ## Customize Log Output
///
/// If you have a type whose log output needs special finessing, extend it to
/// conform to `CustomLogRepresentable`. See below for documentation.
extension OSLog {

    // MARK: - Nested Types


    /// The default arguments passed to the methods below.
    public enum Options {

        /// The default Privacy setting to use.
        public static var defaultPrivacy: Privacy = {
            #if DEBUG
            return .visible
            #else
            return .redacted
            #endif
        }()

        /// If `true`, the function, file, and line number will be included in
        /// messages logged using the "foo(value:)" log methods below.
        public static var includeSourceLocationInValueLogs: Bool = {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }()


        /// If `false`,  the filename is not logged.
        public static var logFileName: Bool = {
            return true
        }()

    }

    /// Controls whether log message content is redacted or visible.
    public enum Privacy {

        /// No values will be redacted.
        case visible

        /// Values besides static strings and scalars will be redacted.
        case redacted
    }

    // MARK: - Default

    /// Logs a developer-formatted message using the `.default` type.
    ///
    /// The caller is responsible for including public/private formatting in the
    /// format string, as well as any source location info (line number, etc.).
    ///
    /// - parameter format: A C-style format string.
    ///
    /// - parameter args: A list of arguments to the format string (if any).
    @inlinable
    public func log(format: StaticString, args: CVarArg...) {
        // Use the `(format:array:)` variant to prevent the compiler from
        // wrapping a single argument in an array it thinks you implied.
        let representation = LogMessage(format: format, array: args)
        _etcetera_log(representation: representation, type: .default)
    }

    /// Logs a message using the `.default` type.
    ///
    /// - parameter value: The value to be logged. If the value does not already
    /// conform to CustomLogRepresentable, a default implementation will used.
    @inlinable
    public func log(_ value: Any, privacy: Privacy = Options.defaultPrivacy, includeSourceLocation: Bool = Options.includeSourceLocationInValueLogs, file: String = #file, function: String = #function, line: Int = #line) {
        _etcetera_log(value: value, privacy: privacy, includeSourceLocation: includeSourceLocation, file: file, function: function, line: line, type: .default)
    }

    // MARK: - Info

    /// Logs a developer-formatted message using the `.info` type.
    ///
    /// The caller is responsible for including public/private formatting in the
    /// format string, as well as any source location info (line number, etc.).
    ///
    /// - parameter format: A C-style format string.
    ///
    /// - parameter args: A list of arguments to the format string (if any).
    @inlinable
    public func info(format: StaticString, args: CVarArg...) {
        // Use the `(format:array:)` variant to prevent the compiler from
        // wrapping a single argument in an array it thinks you implied.
        let representation = LogMessage(format: format, array: args)
        #if targetEnvironment(simulator)
        // @workaround for simulator bug in Xcode 10.2 and earlier:
        // https://forums.developer.apple.com/thread/82736#348090
        let type = OSLogType.default
        #else
        let type = OSLogType.info
        #endif
        _etcetera_log(representation: representation, type: type)
    }

    /// Logs a message using the `.info` type.
    ///
    /// - parameter value: The value to be logged. If the value does not already
    /// conform to CustomLogRepresentable, a default implementation will used.
    @inlinable
    public func info(_ value: Any, privacy: Privacy = Options.defaultPrivacy, includeSourceLocation: Bool = Options.includeSourceLocationInValueLogs, file: String = #file, function: String = #function, line: Int = #line) {
        #if targetEnvironment(simulator)
        // @workaround for simulator bug in Xcode 10.2 and earlier:
        // https://forums.developer.apple.com/thread/82736#348090
        let type = OSLogType.default
        #else
        let type = OSLogType.info
        #endif
        _etcetera_log(value: value, privacy: privacy, includeSourceLocation: includeSourceLocation, file: file, function: function, line: line, type: type)
    }

    // MARK: - Debug

    /// Logs the source location of the call site using the `.debug` type.
    @inlinable
    public func trace(file: String = #file, function: String = #function, line: Int = #line) {
        #if targetEnvironment(simulator)
        // @workaround for simulator bug in Xcode 10.2 and earlier:
        // https://forums.developer.apple.com/thread/82736#348090
        let type = OSLogType.default
        #else
        let type = OSLogType.debug
        #endif
        _etcetera_log(value: "<OSLog.trace>", privacy: .visible, includeSourceLocation: true, file: file, function: function, line: line, type: type)
    }

    /// Logs a developer-formatted message using the `.debug` type.
    ///
    /// The caller is responsible for including public/private formatting in the
    /// format string, as well as any source location info (line number, etc.).
    ///
    /// - parameter format: A C-style format string.
    ///
    /// - parameter args: A list of arguments to the format string (if any).
    @inlinable
    public func debug(format: StaticString, args: CVarArg...) {
        // Use the `(format:array:)` variant to prevent the compiler from
        // wrapping a single argument in an array it thinks you implied.
        let representation = LogMessage(format: format, array: args)
        #if targetEnvironment(simulator)
        // @workaround for simulator bug in Xcode 10.2 and earlier:
        // https://forums.developer.apple.com/thread/82736#348090
        let type = OSLogType.default
        #else
        let type = OSLogType.debug
        #endif
        _etcetera_log(representation: representation, type: type)
    }

    /// Logs a message using the `.debug` type.
    ///
    /// - parameter value: The value to be logged. If the value does not already
    /// conform to CustomLogRepresentable, a default implementation will used.
    @inlinable
    public func debug(_ value: Any, privacy: Privacy = Options.defaultPrivacy, includeSourceLocation: Bool = Options.includeSourceLocationInValueLogs, file: String = #file, function: String = #function, line: Int = #line) {
        #if targetEnvironment(simulator)
        // @workaround for simulator bug in Xcode 10.2 and earlier:
        // https://forums.developer.apple.com/thread/82736#348090
        let type = OSLogType.default
        #else
        let type = OSLogType.debug
        #endif
        _etcetera_log(value: value, privacy: privacy, includeSourceLocation: includeSourceLocation, file: file, function: function, line: line, type: type)
    }

    // MARK: - Error

    /// Logs a developer-formatted message using the `.error` type.
    ///
    /// The caller is responsible for including public/private formatting in the
    /// format string, as well as any source location info (line number, etc.).
    ///
    /// - parameter format: A C-style format string.
    ///
    /// - parameter args: A list of arguments to the format string (if any).
    @inlinable
    public func error(format: StaticString, args: CVarArg...) {
        // Use the `(format:array:)` variant to prevent the compiler from
        // wrapping a single argument in an array it thinks you implied.
        let representation = LogMessage(format: format, array: args)
        _etcetera_log(representation: representation, type: .error)
    }

    /// Logs a message using the `.error` type.
    ///
    /// - parameter value: The value to be logged. If the value does not already
    /// conform to CustomLogRepresentable, a default implementation will used.
    @inlinable
    public func error(_ value: Any, privacy: Privacy = Options.defaultPrivacy, includeSourceLocation: Bool = Options.includeSourceLocationInValueLogs, file: String = #file, function: String = #function, line: Int = #line) {
        _etcetera_log(value: value, privacy: privacy, includeSourceLocation: includeSourceLocation, file: file, function: function, line: line, type: .error)
    }

    // MARK: - Fault

    /// Logs a developer-formatted message using the `.fault` type.
    ///
    /// The caller is responsible for including public/private formatting in the
    /// format string, as well as any source location info (line number, etc.).
    ///
    /// - parameter format: A C-style format string.
    ///
    /// - parameter args: A list of arguments to the format string (if any).
    @inlinable
    public func fault(format: StaticString, args: CVarArg...) {
        // Use the `(format:array:)` variant to prevent the compiler from
        // wrapping a single argument in an array it thinks you implied.
        let representation = LogMessage(format: format, array: args)
        _etcetera_log(representation: representation, type: .fault)
    }

    /// Logs a message using the `.fault` type.
    ///
    /// - parameter value: The value to be logged. If the value does not already
    /// conform to CustomLogRepresentable, a default implementation will used.
    @inlinable
    public func fault(_ value: Any, privacy: Privacy = Options.defaultPrivacy, includeSourceLocation: Bool = Options.includeSourceLocationInValueLogs, file: String = #file, function: String = #function, line: Int = #line) {
        _etcetera_log(value: value, privacy: privacy, includeSourceLocation: includeSourceLocation, file: file, function: function, line: line, type: .fault)
    }

    // MARK: - Internal

    @usableFromInline
    internal func _etcetera_log(value: Any, privacy: Privacy, includeSourceLocation: Bool, file: String, function: String, line: Int, type: OSLogType) {
        var fileName = file
        if Options.logFileName == false {
            fileName = ""
        }
        let loggable = (value as? CustomLogRepresentable) ?? AnyLoggable(value)
        let representation = loggable.logRepresentation(includeSourceLocation: includeSourceLocation, privacy: privacy, file: fileName, function: function, line: line)
        _etcetera_log(representation: representation, type: type)
    }

    @usableFromInline
    internal func _etcetera_log(representation: LogMessage, type: OSLogType) {
        // http://www.openradar.me/33203955
        // Sigh...
        // or should I say
        // sigh, sigh, sigh, sigh, sigh, sigh, sigh, sigh, sigh
        let f = representation.format
        let a = representation.args
        switch a.count {
            case 9: os_log(f, log: self, type: type, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8])
            case 8: os_log(f, log: self, type: type, a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
            case 7: os_log(f, log: self, type: type, a[0], a[1], a[2], a[3], a[4], a[5], a[6])
            case 6: os_log(f, log: self, type: type, a[0], a[1], a[2], a[3], a[4], a[5])
            case 5: os_log(f, log: self, type: type, a[0], a[1], a[2], a[3], a[4])
            case 4: os_log(f, log: self, type: type, a[0], a[1], a[2], a[3])
            case 3: os_log(f, log: self, type: type, a[0], a[1], a[2])
            case 2: os_log(f, log: self, type: type, a[0], a[1])
            case 1: os_log(f, log: self, type: type, a[0])
            default: os_log(f, log: self, type: type)
        }
    }

}

//------------------------------------------------------------------------------
// MARK: - CustomLogRepresentable
//------------------------------------------------------------------------------

/// If you have a type whose log output needs special finessing, extend it to
/// conform to `CustomLogRepresentable`.
///
/// The format string you provide in a returned LogMessage will be passed
/// directly into the underlying `os_log` call, so all the same privacy and
/// formatting rules apply as if you had called into `os_log` yourself.
///
/// ## Sample Implementation
///
///        struct PorExemplo: CustomLogRepresentable {
///            let id: uuid_t
///            let token: String
///
///            func logRepresentation(privacy: OSLog.Privacy) ->
///                LogMessage {
///                var id = self.id
///                return withUnsafePointer(to: &id) { ptr in
///                    ptr.withMemoryRebound(to: UInt8.self, capacity:
///                        MemoryLayout<uuid_t>.size) { bytePtr ->
///                            LogMessage in
///                            LogMessage("PorExemplo(id: %{public,
///                                uuid_t}.16P, token: %{private}@)",
///                                bytePtr, token)
///                    }
///                }
///            }
///
///            func logRepresentation(privacy: OSLog.Privacy, file:
///                String, function: String, line: Int) -> LogMessage
///                {
///                var id = self.id
///                return withUnsafePointer(to: &id) { ptr in
///                    ptr.withMemoryRebound(to: UInt8.self, capacity:
///                        MemoryLayout<uuid_t>.size) { bytePtr ->
///                            LogMessage in
///                            LogMessage("%{public}@ %{public}@ Line %ld:
///                                PorExemplo(id: %{public, uuid_t}.16P,
///                                token: %{private}@)", file, function,
///                                line, bytePtr, token)
///                    }
///                }
///            }
///        }
///
/// You can ignore the `privacy` arguments passed to the protocol methods if
/// they are not applicable to your type's log message representation.
/// Otherwise, your implementation should vary the format strings used based on
/// the indicated privacy setting.
///
/// The method variant that includes source location arguments will be called if
/// the log method (or the global setting) included the option to reveal source
/// location in the logs. This is a stopgap measure until OSLog supports showing
/// source locations in logs originating from Swift code.
public protocol CustomLogRepresentable {
    func logRepresentation(privacy: OSLog.Privacy) -> LogMessage
    func logRepresentation(privacy: OSLog.Privacy, file: String, function: String, line: Int) -> LogMessage
}

/// The customized representation of a type, used when configuring os_log inputs.
public struct LogMessage {

    /// The C-style format string.
    public let format: StaticString

    /// The argument list (what you would otherwise pass as a comma-delimited
    /// list of variadic arguments to `os_log`).
    ///
    /// - Warning: Due to Earth's atmosphere, CustomLogRepresentable can only be
    /// initialized with an arg list containing up to nine items. Attempting to
    /// initialize with more than nine arguments will trip an assertion.
    public let args: [CVarArg]

    /// Primary Initializer
    public init(_ format: StaticString, _ args: CVarArg...) {
        assert(args.count < 10, "The Swift overlay of os_log prevents this OSLog extension from accepting an unbounded number of args.")
        self.format = format
        self.args = args
    }

    /// Convenience initializer.
    ///
    /// Use this initializer if you are forwarding a `CVarArg...` list from
    /// a calling Swift function and need to prevent the compiler from treating
    /// a single value as an implied array containing that single value, e.g.
    /// from an infering `Array<Int>` from a single `Int` argument.
    public init(format: StaticString, array args: [CVarArg]) {
        assert(args.count < 10, "The Swift overlay of os_log prevents this OSLog extension from accepting an unbounded number of args.")
        self.format = format
        self.args = args
    }

}

extension CustomLogRepresentable {

    @inlinable
    public func logRepresentation(privacy: OSLog.Privacy) -> LogMessage {
        switch privacy {
        case .visible:
            return LogMessage("%{public}@", logDescription)
        case .redacted:
            return LogMessage("%{private}@", logDescription)
        }
    }

    @inlinable
    public func logRepresentation(privacy: OSLog.Privacy, file: String, function: String, line: Int) -> LogMessage {
        switch privacy {
        case .visible:
            return LogMessage("%{public}@ %{public}@ Line %ld: %{public}@", file, function, line, logDescription)
        case .redacted:
            return LogMessage("%{public}@ %{public}@ Line %ld: %{private}@", file, function, line, logDescription)
        }
    }

    @usableFromInline
    func logRepresentation(includeSourceLocation: Bool, privacy: OSLog.Privacy, file: String, function: String, line: Int) -> LogMessage {
        if includeSourceLocation {
            let filename = file.split(separator: "/").last.flatMap { String($0) } ?? file
            return logRepresentation(privacy: privacy, file: filename, function: function, line: line)
        } else {
            return logRepresentation(privacy: privacy)
        }
    }

    @usableFromInline
    var logDescription: String {
        let value: Any = (self as? AnyLoggable)?.loggableValue ?? self
        if let string = value as? String {
            return string
        }
        #if DEBUG
        if let custom = value as? CustomDebugStringConvertible {
            return custom.debugDescription
        }
        #endif
        if let convertible = value as? CustomStringConvertible {
            return convertible.description
        }
        return "\(value)"
    }

}

private struct AnyLoggable: CustomLogRepresentable {
    let loggableValue: Any

    init(_ value: Any) {
        loggableValue = value
    }
}

extension NSError: CustomLogRepresentable { }
extension String: CustomLogRepresentable { }
extension Bool: CustomLogRepresentable { }
extension Int: CustomLogRepresentable { }
extension UInt: CustomLogRepresentable { }
