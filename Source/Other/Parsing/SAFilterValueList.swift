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

/// The rule editor captures its arguments on the main thread. The load that will send
/// the query renders those arguments for its connection, even if the editor has since changed.
@objcMembers public final class SATableFilterRequest: NSObject {
    public let requiresConnection: Bool
    private let render: (NSErrorPointer) -> String?

    @objc(initWithSQL:)
    public init(sql: String) {
        requiresConnection = false
        render = { _ in sql }
    }

    @objc(initWithFilterTree:render:)
    public init(filterTree: NSDictionary, render: @escaping (NSErrorPointer) -> String?) {
        requiresConnection = Self.hasQuotedList(filterTree)
        self.render = render
    }

    private static func hasQuotedList(_ rule: NSDictionary) -> Bool {
        if let children = rule["children"] as? [NSDictionary] {
            return children.contains(where: hasQuotedList)
        }
        return rule["quoteEachValue"] as? Bool == true
    }

    @objc(SQLWithError:)
    public func sql(error: NSErrorPointer) -> String? { render(error) }
}
