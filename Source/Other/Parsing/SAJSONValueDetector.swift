import Foundation

/// Decides whether a field value should be presented on the field editor's JSON segment.
///
/// `SPFieldEditorController` recognizes MySQL's JSON column type from the field type, but JSON is
/// just as often kept in a plain text column - MariaDB's `longtext ... CHECK (json_valid(<column>))`,
/// for instance - where the column type carries no hint at all. Sniffing the value covers those.
@objc final class SAJSONValueDetector: NSObject {
    /// Values longer than this are not sniffed, so that opening the field editor on a large blob
    /// does not pay for a full JSON parse it is unlikely to need.
    private static let maximumDetectableByteCount = 5 * 1024 * 1024

    /// Returns whether `value` is a JSON object or array.
    ///
    /// Top-level scalars (`42`, `"text"`, `true`, `null`) are deliberately not treated as JSON.
    /// They are indistinguishable from ordinary column values, and the JSON segment rejects them
    /// too, because it parses without `NSJSONReadingFragmentsAllowed`.
    @objc static func isJSONContainer(_ value: String?) -> Bool {
        guard let value = value, !value.isEmpty, value.utf8.count <= maximumDetectableByteCount else { return false }

        // Cheap rejection before parsing: JSON containers can only start with these.
        guard let firstCharacter = value.first(where: { !$0.isWhitespace }),
              firstCharacter == "{" || firstCharacter == "[" else { return false }

        guard let data = value.data(using: .utf8) else { return false }

        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
