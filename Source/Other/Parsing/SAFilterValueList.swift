import Foundation

/// Builds text literals for IN filters without consulting the connection.
@objc public final class SAFilterValueList: NSObject {
    @objc(quotedSQLFromInput:)
    public static func quotedSQL(from input: String) -> String {
        input.components(separatedBy: CharacterSet(charactersIn: ",")).map { item in
            let value = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.utf8.allSatisfy({ (0x20...0x7E).contains($0) && $0 != 0x5C }) {
                return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
            }
            // Keep backslashes independent of sql_mode and preserve non-ASCII text across connection encodings.
            return "_utf8mb4 X'\(String.rawByteString(Data(value.utf8)))'"
        }.joined(separator: ", ")
    }
}
