//
//  SAConnectionFormView.swift
//  Sequel Ace
//
//  Phase C2 of the SwiftUI migration: a SwiftUI form for editing
//  connection details, starting with the TCP/IP connection type only
//  (the ConnectionView.xib standard tab). Binds into
//  SAConnectionFormModel, which wraps the value-type SAConnectionInfo
//  and reuses the already-extracted validation (D3) and name
//  generation helpers.
//
//  Like SAFavoritesList (C1b), nothing hosts this view yet — Phase C3
//  (the standalone connection window) is the intended host, where it
//  will sit next to the SwiftUI favorites list and drive
//  SAConnectionService directly. The field set and labels mirror the
//  XIB's TCP/IP tab; SSL file options and the other connection types are
//  follow-up scope.
//

import SwiftUI

/// SwiftUI editor for TCP/IP connection details.
struct SAConnectionFormView: View {

    @ObservedObject var model: SAConnectionFormModel

    /// Invoked when the user submits a form that passed validation —
    /// the host initiates the connection (C3: via SAConnectionService).
    var onConnect: (SAConnectionFormModel) -> Void = { _ in }

    /// The first validation failure of the latest submit, surfaced as
    /// an alert (same strings the AppKit flow shows).
    @State private var validationFailure: SAConnectionValidationFailure?

    var body: some View {
        Form {
            // ── Database backend selector ──────────────────────────────────
            Section {
                Picker(selection: $model.info.databaseBackend) {
                    ForEach([SADatabaseBackend.mysql, SADatabaseBackend.postgresql], id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                } label: {
                    Text("Database", comment: "connection view : database backend picker label")
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField(text: $model.info.name, prompt: Text(namePrompt)) {
                    Text("Name", comment: "connection view : field label")
                }
            }

            Section {
                TextField(text: $model.info.host) {
                    Text("Host", comment: "connection view : field label")
                }
                TextField(text: $model.info.user) {
                    Text("Username", comment: "connection view : field label")
                }
                SecureField(text: $model.info.password) {
                    Text("Password", comment: "connection view : field label")
                }
            }

            Section {
                TextField(text: $model.info.database, prompt: Text("optional", comment: "connection view : optional field placeholder")) {
                    Text("Database", comment: "connection view : field label")
                }
                TextField(text: $model.info.port, prompt: Text(verbatim: model.defaultPortString)) {
                    Text("Port", comment: "connection view : field label")
                }
            }

            // MySQL-only controls — hidden when PostgreSQL is selected
            if model.info.databaseBackend == .mysql {
                Section {
                    Toggle(isOn: requestServerPublicKeyBinding) {
                        Text("Get Public Key", comment: "connection view : get server public key checkbox")
                    }
                    .help(NSLocalizedString("Request the server RSA public key for caching_sha2_password over non-SSL connections.", comment: "connection view : get server public key help"))
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button {
                        submit()
                    } label: {
                        Text("Connect", comment: "connection view : connect button")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAttemptConnection)
                }
            }
        }
        .modifier(SAGroupedFormStyle())
        .alert(
            validationFailure?.alertTitle ?? "",
            isPresented: Binding(
                get: { validationFailure != nil },
                set: { if !$0 { validationFailure = nil } }
            ),
            presenting: validationFailure
        ) { _ in
            Button {
                validationFailure = nil
            } label: {
                Text("OK", comment: "OK button")
            }
        } message: { failure in
            Text(failure.alertMessage)
        }
    }

    /// Placeholder for the name field: the auto-generated name the
    /// connection would get, mirroring the AppKit form's behaviour of
    /// auto-filling "host[/database]" until the user types their own.
    private var namePrompt: String {
        let generated = SAConnectionFormHelpers.generateName(type: model.info.type,
                                                             host: model.info.host,
                                                             database: model.info.database)
        if let generated, !generated.isEmpty {
            return generated
        }
        return NSLocalizedString("Optional Name", comment: "connection view : name field placeholder")
    }

    private var requestServerPublicKeyBinding: Binding<Bool> {
        Binding(
            get: { model.info.requestServerPublicKey != 0 },
            set: { model.info.requestServerPublicKey = $0 ? 1 : 0 }
        )
    }

    private func submit() {
        if let failure = model.validate() {
            validationFailure = failure
            return
        }
        onConnect(model)
    }
}

/// Applies the grouped form style where available (macOS 13+); on
/// macOS 12 the default Form rendering is used.
private struct SAGroupedFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}
