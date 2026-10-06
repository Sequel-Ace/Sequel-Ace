import SwiftUI

/// The Check Constraints section of the Relations tab: a list with add and
/// delete buttons. There is deliberately no edit in place; a check is changed
/// by deleting it and adding it again.
struct SACheckConstraintsView: View {
    @ObservedObject var model: SACheckConstraintsModel
    @State private var isAddSheetPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Check Constraints", comment: "check constraints : section title in the Relations tab"))
                .font(.headline)

            SACheckConstraintsTable(model: model)

            HStack(spacing: 6) {
                Button {
                    isAddSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(NSLocalizedString("Add check constraint", comment: "check constraints : add button tooltip"))
                .disabled(!model.isEnabled)

                Button {
                    model.deleteHandler?(model.selectedNames)
                } label: {
                    Image(systemName: "minus")
                }
                .help(NSLocalizedString("Delete selected check constraint(s)", comment: "check constraints : delete button tooltip"))
                .disabled(!model.canDelete)
            }
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $isAddSheetPresented) {
            SACheckConstraintAddSheet(model: model) {
                isAddSheetPresented = false
            }
        }
    }
}

private struct SACheckConstraintsTable: View {
    @ObservedObject var model: SACheckConstraintsModel

    var body: some View {
        Table(model.items, selection: $model.selection) {
            TableColumn(NSLocalizedString("Name", comment: "check constraints : name column")) { item in
                Text(item.name)
            }
            .width(min: 80, ideal: 160)

            TableColumn(NSLocalizedString("Expression", comment: "check constraints : expression column")) { item in
                Text(item.expression)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.expression)
            }

            TableColumn(NSLocalizedString("Enforced", comment: "check constraints : enforced column")) { item in
                Text(item.isEnforced
                     ? NSLocalizedString("Yes", comment: "yes")
                     : NSLocalizedString("No", comment: "no"))
            }
            .width(60)
        }
        .onDeleteCommand {
            if model.canDelete {
                model.deleteHandler?(model.selectedNames)
            }
        }
    }
}

private struct SACheckConstraintAddSheet: View {
    @ObservedObject var model: SACheckConstraintsModel
    let close: () -> Void

    @State private var name = ""
    @State private var expression = ""
    @State private var serverError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("Add Check Constraint", comment: "check constraints : add sheet title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                TextField(NSLocalizedString("Name (optional)", comment: "check constraints : add sheet : name field placeholder"), text: $name)
                if let problem = model.nameProblem(for: name) {
                    Text(problem)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Text(NSLocalizedString("Expression", comment: "check constraints : expression column"))
                .font(.subheadline)
            TextEditor(text: $expression)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .border(Color(nsColor: .separatorColor))

            if let serverError {
                Text(serverError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button(NSLocalizedString("Cancel", comment: "cancel button"), action: close)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("Add", comment: "add button"), action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdd(name: name, expression: expression))
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private func add() {
        if let error = model.addHandler?(name, expression) {
            serverError = error
        } else {
            close()
        }
    }
}
