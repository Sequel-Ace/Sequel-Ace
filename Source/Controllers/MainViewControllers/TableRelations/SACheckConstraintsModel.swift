import Foundation

/// One row of the Relations tab's Check Constraints section.
struct SACheckConstraintItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let expression: String
    let isEnforced: Bool
}

/// State behind the Check Constraints section. Query execution stays with the
/// owning controller, which supplies `addHandler` and `deleteHandler`.
///
/// Kept free of project ObjC types so the Unit Tests target can compile it.
final class SACheckConstraintsModel: ObservableObject {

    @Published private(set) var items: [SACheckConstraintItem] = []
    @Published var selection: Set<SACheckConstraintItem.ID> = []
    @Published var isEnabled = true

    /// Every constraint name already used by the table (foreign keys included),
    /// since MySQL keeps them in one namespace.
    private(set) var takenNames: [String] = []

    /// Returns a server error message on failure, nil on success.
    var addHandler: ((_ name: String, _ expression: String) -> String?)?
    var deleteHandler: ((_ names: [String]) -> Void)?

    var selectedNames: [String] {
        items.filter { selection.contains($0.id) }.map(\.name)
    }

    var canDelete: Bool {
        isEnabled && !selection.isEmpty
    }

    /// Replaces the rows from the dictionaries produced by
    /// `SACheckConstraintSupport.parseDefinition(_:)`, keeping the selection on
    /// constraints that are still present.
    func update(checks: [[String: Any]], takenNames: [String]) {
        let previouslySelected = Set(selectedNames)

        items = checks.enumerated().map { index, check in
            SACheckConstraintItem(
                id: index,
                name: check[SACheckConstraintSupport.nameKey] as? String ?? "",
                expression: check[SACheckConstraintSupport.expressionKey] as? String ?? "",
                isEnforced: (check[SACheckConstraintSupport.enforcedKey] as? NSNumber)?.boolValue ?? true
            )
        }
        selection = Set(items.filter { previouslySelected.contains($0.name) }.map(\.id))
        self.takenNames = takenNames
    }

    // MARK: - Add sheet validation

    /// A message to show next to the name field, or nil when the name is usable.
    /// An empty name is allowed: the server generates one.
    func nameProblem(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return SACheckConstraintSupport.isName(trimmed, takenIn: takenNames)
            ? NSLocalizedString("A constraint with this name already exists.", comment: "check constraints : add sheet : name already in use")
            : nil
    }

    func canAdd(name: String, expression: String) -> Bool {
        !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nameProblem(for: name) == nil
    }
}
