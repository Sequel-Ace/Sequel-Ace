import Foundation

/// Formats the argument of a text IN rule when the user selects “Quote each value”.
@objc public final class SAFilterValueList: NSObject {
    /// Each item is data, including empty items. The connection quotes it for its current SQL mode.
    @objc(quotedSQLFromInput:quote:)
    public static func quotedSQL(from input: String, quote: (String) -> String?) -> String? {
        var literals: [String] = []
        for item in input.components(separatedBy: ",") {
            guard let literal = quote(item.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            literals.append(literal)
        }
        return literals.joined(separator: ", ")
    }
}
