//
//  SAConnectionFormView.swift
//  Sequel Ace
//
//  Phase C2 of the SwiftUI migration: a SwiftUI form for editing
//  connection details. C2a covered the TCP/IP tab; C2b (here) covers
//  every type ConnectionView.xib offers — TCP/IP, socket, SSH tunnel,
//  AWS IAM and Vault — along with the SSL file options, the colour
//  index and the time-zone popup that the XIB tabs carry.
//
//  Binds into SAConnectionFormModel, which wraps the value-type
//  SAConnectionInfo and reuses the already-extracted validation (D3),
//  favorite decoding (D1) and name generation helpers. The field sets,
//  labels and placeholders below mirror the XIB tab by tab; the model
//  owns which of them a given type shows (forcesSSL and friends).
//
//  Like SAFavoritesList (C1b), nothing hosts this view yet — Phase C3
//  (the standalone connection window) is the intended host, where it
//  will sit next to the SwiftUI favorites list and drive
//  SAConnectionService directly.
//
//  App-target only: it touches SPFavoriteColorSupport (ObjC) for the
//  colour swatches, so it cannot compile into the Unit Tests target.
//  The branchy parts it renders live on the model, which can.
//

import SwiftUI
import AppKit

/// SwiftUI editor for connection details, for every connection type.
struct SAConnectionFormView: View {

    @ObservedObject var model: SAConnectionFormModel

    /// Invoked when the user submits a form that passed validation —
    /// the host initiates the connection (C3: via SAConnectionService).
    var onConnect: (SAConnectionFormModel) -> Void = { _ in }

    /// The first validation failure of the latest submit, surfaced as
    /// an alert (same strings the AppKit flow shows).
    @State private var validationFailure: SAConnectionValidationFailure?

    /// Tracks the Vault Role field so losing focus can commit a pasted path.
    @FocusState private var roleFieldFocused: Bool

    var body: some View {
        Form {
            typeSection
            identitySection
            detailsSection
            timeZoneSection
            securitySection
            if model.showsSSLFileOptions {
                sslFileSection
            }
            connectSection
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

    // MARK: - Sections

    /// Replaces the XIB's tab bar: picking a type swaps the detail
    /// fields below rather than a whole tab view.
    private var typeSection: some View {
        Section {
            Picker(selection: $model.info.type) {
                Text("TCP/IP", comment: "connection type : tcp/ip").tag(SAConnectionType.tcpIP)
                Text("Socket", comment: "connection type : socket").tag(SAConnectionType.socket)
                Text("SSH Tunnel", comment: "connection type : ssh tunnel").tag(SAConnectionType.sshTunnel)
                Text("AWS IAM", comment: "connection type : aws iam").tag(SAConnectionType.awsIAM)
                Text("Vault", comment: "connection type : vault").tag(SAConnectionType.vault)
            } label: {
                Text("Type", comment: "connection view : field label")
            }
            .pickerStyle(.menu)
        }
    }

    /// Name and colour are common to every tab in the XIB.
    private var identitySection: some View {
        Section {
            TextField(text: $model.info.name, prompt: Text(namePrompt)) {
                Text("Name", comment: "connection view : field label")
            }
            SAFavoriteColorPicker(colorIndex: $model.info.colorIndex)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        switch model.info.type {
        case .tcpIP:
            standardFields
        case .socket:
            socketFields
        case .sshTunnel:
            sshFields
        case .awsIAM:
            awsIAMFields
        case .vault:
            vaultFields
        }
    }

    /// Built once: the identifier list is fixed for the process lifetime, and
    /// `body` re-evaluates on every keystroke (any `info` mutation publishes),
    /// which would otherwise re-sort ~600 identifiers each time.
    private static let timeZoneMenu = SATimeZoneMenuEntry.menu()

    private var timeZoneSection: some View {
        Section {
            Picker(selection: timeZoneBinding) {
                ForEach(Self.timeZoneMenu, id: \.self) { entry in
                    switch entry {
                    case .choice(.server):
                        Text("Use Server Time Zone", comment: "Leave the server time zone in place when connecting")
                            .tag(SATimeZoneChoice.server)
                    case .choice(.system):
                        Text("Use System Time Zone", comment: "Set the time zone currently used by the user when connecting")
                            .tag(SATimeZoneChoice.system)
                    case .choice(.fixed(let identifier)):
                        Text(verbatim: identifier).tag(SATimeZoneChoice.fixed(identifier))
                    case .separator:
                        Divider()
                    }
                }
            } label: {
                Text("Time Zone", comment: "connection view : field label")
            }
            .pickerStyle(.menu)
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: $model.allowDataLocalInfile) {
                Text("Allow LOCAL_DATA_INFILE (insecure)", comment: "connection view : allow local data infile checkbox")
            }

            if model.showsClearTextPluginToggle {
                Toggle(isOn: $model.enableClearTextPlugin) {
                    Text("Enable Cleartext plugin (insecure)", comment: "connection view : enable cleartext plugin checkbox")
                }
            }

            if model.showsSSLToggle {
                Toggle(isOn: $model.useSSL) {
                    Text("Require SSL", comment: "connection view : require ssl checkbox")
                }
            }

            if model.showsRequestServerPublicKeyToggle {
                Toggle(isOn: $model.requestServerPublicKey) {
                    Text("Get Public Key", comment: "connection view : get server public key checkbox")
                }
                .help(NSLocalizedString("Request the server RSA public key for caching_sha2_password over non-SSL connections.",
                                        comment: "connection view : get server public key help"))
            }

            if model.forcesSSL {
                Text("SSL/TLS and cleartext plugins are enabled automatically for AWS IAM connections.",
                     comment: "connection view : aws iam security note")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// The XIB's per-tab SSL details container: three optional file
    /// pickers, each gated by its own checkbox and showing "none set"
    /// until a path is chosen.
    private var sslFileSection: some View {
        Section {
            SAOptionalFileRow(
                title: Text("Key File", comment: "connection view : ssl key file label"),
                kind: .sslKey,
                isEnabled: $model.sslKeyFileLocationEnabled,
                path: $model.info.sslKeyFileLocation
            )
            SAOptionalFileRow(
                title: Text("Certificate", comment: "connection view : ssl certificate label"),
                kind: .sslCertificate,
                isEnabled: $model.sslCertificateFileLocationEnabled,
                path: $model.info.sslCertificateFileLocation
            )
            SAOptionalFileRow(
                title: Text("CA Cert", comment: "connection view : ssl ca cert label"),
                kind: .sslCACert,
                isEnabled: $model.sslCACertFileLocationEnabled,
                path: $model.info.sslCACertFileLocation
            )
        }
    }

    private var connectSection: some View {
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

    // MARK: - Per-type field groups

    private var standardFields: some View {
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
            databaseField
            portField
        }
    }

    private var socketFields: some View {
        Section {
            // The socket path is optional: blank means the MySQL default.
            TextField(text: $model.info.socket, prompt: optionalPrompt) {
                Text("Socket", comment: "connection view : field label")
            }
            TextField(text: $model.info.user) {
                Text("Username", comment: "connection view : field label")
            }
            SecureField(text: $model.info.password) {
                Text("Password", comment: "connection view : field label")
            }
            databaseField
        }
    }

    private var sshFields: some View {
        Group {
            Section {
                TextField(text: $model.info.sshHost) {
                    Text("SSH Host", comment: "connection view : field label")
                }
                TextField(text: $model.info.sshUser) {
                    Text("SSH User", comment: "connection view : field label")
                }
                SecureField(text: $model.info.sshPassword) {
                    Text("SSH Password", comment: "connection view : field label")
                }
                TextField(text: $model.info.sshPort, prompt: optionalPrompt) {
                    Text("SSH Port", comment: "connection view : field label")
                }
                SAOptionalFileRow(
                    title: Text("SSH Key", comment: "connection view : ssh key label"),
                    kind: .sshKey,
                    isEnabled: $model.sshKeyLocationEnabled,
                    path: $model.info.sshKeyLocation
                )
            }

            Section {
                TextField(text: $model.info.host) {
                    Text("MySQL Host", comment: "connection view : field label")
                }
                TextField(text: $model.info.user) {
                    Text("Username", comment: "connection view : field label")
                }
                SecureField(text: $model.info.password) {
                    Text("Password", comment: "connection view : field label")
                }
                databaseField
                portField
                // Connecting through a socket on the far side of the tunnel
                // instead of a TCP host — the validator accepts either.
                TextField(text: $model.info.sshRemoteSocketPath, prompt: optionalPrompt) {
                    Text("Remote Socket", comment: "connection view : field label")
                }
            }
        }
    }

    private var awsIAMFields: some View {
        Group {
            Section {
                TextField(text: $model.info.host) {
                    Text("Host", comment: "connection view : field label")
                }
                TextField(text: $model.info.user) {
                    Text("Username", comment: "connection view : field label")
                }
                // IAM authenticates with a token generated from the profile, so
                // a typed password can never be used. -_syncAWSIAMAndSSLInterfaceState
                // disables, clears and relabels the AppKit field; leaving it
                // editable would invite a value that goes nowhere and would then
                // sit in the model for the host and any favorite saved from it.
                SecureField(text: .constant(""),
                            prompt: Text("Generated from AWS IAM profile",
                                         comment: "placeholder when AWS IAM auth is enabled")) {
                    Text("Password", comment: "connection view : field label")
                }
                .disabled(true)
                databaseField
                portField
            }

            Section {
                TextField(text: $model.info.awsProfile) {
                    Text("AWS Profile", comment: "connection view : field label")
                }
                TextField(text: $model.info.awsRegion) {
                    Text("Region", comment: "connection view : field label")
                }
            }
        }
    }

    private var vaultFields: some View {
        Group {
            Section {
                TextField(text: $model.info.host, prompt: Text(verbatim: "e.g. mydb.us-east-1.rds.amazonaws.com")) {
                    Text("Host", comment: "connection view : field label")
                }
                databaseField
                portField
            }

            Section {
                TextField(text: $model.info.vaultHost) {
                    Text("Vault host", comment: "connection view : field label")
                }
                TextField(text: $model.info.vaultPort, prompt: Text(verbatim: "443")) {
                    Text("Vault port", comment: "connection view : field label")
                }
                TextField(text: $model.info.vaultOIDCMount, prompt: Text(verbatim: "oidc")) {
                    Text("OIDC Mount", comment: "connection view : field label")
                }
                TextField(text: $model.vaultMount, prompt: Text(verbatim: "databases_credentials")) {
                    Text("Vault mount", comment: "connection view : field label")
                }
                // The XIB offers this as a combo box backed by a fetched role
                // list (SAVaultRoleListController); the fetch and its Refresh
                // button are C3 scope, so this is the plain text half for now.
                TextField(text: $model.vaultCredentialsRole) {
                    Text("Role", comment: "connection view : field label")
                }
                // Normalize a pasted full path into Mount + Role once editing
                // commits, as -controlTextDidEndEditing: does. Focus loss counts
                // as a commit, so both are wired.
                .focused($roleFieldFocused)
                .onSubmit { model.commitVaultCredentialsRole() }
                .onChange(of: roleFieldFocused) { isFocused in
                    if !isFocused { model.commitVaultCredentialsRole() }
                }
            }
        }
    }

    // MARK: - Shared fields

    private var databaseField: some View {
        TextField(text: $model.info.database, prompt: optionalPrompt) {
            Text("Database", comment: "connection view : field label")
        }
    }

    private var portField: some View {
        TextField(text: $model.info.port, prompt: Text(verbatim: "3306")) {
            Text("Port", comment: "connection view : field label")
        }
    }

    private var optionalPrompt: Text {
        Text("optional", comment: "connection view : optional field placeholder")
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

    private var timeZoneBinding: Binding<SATimeZoneChoice> {
        Binding(
            get: { model.timeZoneChoice },
            set: { model.timeZoneChoice = $0 }
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

// MARK: - Colour picker

/// The XIB's SPColorSelectorView: one swatch per entry of
/// SPFavoriteColorSupport's list, plus a "no colour" state. The stored
/// index is -1 when no colour is set (see SAConnectionInfo+Favorite).
private struct SAFavoriteColorPicker: View {

    @Binding var colorIndex: Int

    /// -1 is the "none" sentinel the favorites plist uses.
    private static let noColorIndex = -1

    private var colors: [NSColor] {
        SPFavoriteColorSupport.sharedInstance().userColorList ?? []
    }

    var body: some View {
        Picker(selection: $colorIndex) {
            Text("None", comment: "connection view : no favorite colour")
                .tag(Self.noColorIndex)
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                // A label as well as the swatch, so the choice is distinguishable
                // without relying on colour perception.
                Label {
                    Text(colorLabel(at: index))
                } icon: {
                    Circle().fill(Color(nsColor: color))
                }
                .tag(index)
            }
        } label: {
            Text("Colour", comment: "connection view : field label")
        }
        .pickerStyle(.menu)
    }

    /// The list is positional and its length is not guaranteed, so the label is
    /// derived from the index rather than a parallel array of hardcoded names —
    /// a shorter or reordered list would otherwise mislabel the swatches.
    private func colorLabel(at index: Int) -> String {
        String(format: NSLocalizedString("Colour %ld",
                                         comment: "connection view : favorite colour by position"),
               index + 1)
    }
}

// MARK: - Optional file row

/// A checkbox plus a path chooser, matching the XIB's SSH-key and SSL
/// file rows: unchecked hides the path, checked shows the chosen file or
/// "none set" until one is picked.
private struct SAOptionalFileRow: View {

    let title: Text
    /// Decides which PEM check the chosen file must pass — the SwiftUI
    /// equivalent of `-chooseKeyLocation:` branching on the sending button.
    let kind: SAConnectionFileKind
    @Binding var isEnabled: Bool
    @Binding var path: String

    @State private var rejection: SAConnectionFileRejection?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isEnabled) { title }
                // Unticking clears the path, as -chooseKeyLocation: does on
                // cancel. Keeping it would make the old file silently reappear
                // on re-tick, and would leave a disabled credential path in any
                // favorite saved or exported afterwards.
                .onChange(of: isEnabled) { isOn in
                    if !isOn { path = "" }
                }

            if isEnabled {
                HStack {
                    Text(verbatim: path.isEmpty
                         ? NSLocalizedString("none set", comment: "connection view : no file chosen")
                         : (path as NSString).abbreviatingWithTildeInPath)
                        .foregroundColor(path.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        chooseFile()
                    } label: {
                        Text("Choose…", comment: "connection view : choose file button")
                    }
                }
            }
        }
        .alert(
            rejection?.alertTitle ?? "",
            isPresented: Binding(
                get: { rejection != nil },
                set: { if !$0 { rejection = nil } }
            ),
            presenting: rejection
        ) { _ in
            Button { rejection = nil } label: { Text("OK", comment: "OK button") }
        } message: { rejection in
            Text(rejection.alertMessage)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Key and certificate files are routinely kept in ~/.ssh.
        panel.showsHiddenFiles = true

        // Cancelling clears the row, as -chooseKeyLocation: does: an enabled
        // checkbox with no path would claim a file the connection cannot use.
        guard panel.runModal() == .OK, let url = panel.url else {
            isEnabled = false
            path = ""
            return
        }

        // Reject a file of the wrong shape before storing it, so the failure
        // surfaces here rather than as an opaque connection error later.
        if let rejection = SAConnectionFileValidator.rejection(forFileAt: url, kind: kind) {
            self.rejection = rejection
            return
        }

        // Persist a read-only security-scoped bookmark before storing the path.
        // Without one the sandbox grants access only for this launch: the panel
        // itself starts access, but a favorite saved with this path would find
        // the file unreadable after a relaunch. Read-only matters because keys
        // are routinely mode 400.
        //
        // A failed bookmark is not fatal — access still works for this launch —
        // so the path is stored either way, matching -chooseKeyLocation:.
        _ = SecureBookmarkManager.sharedInstance.addBookmarkFor(
            url: url,
            options: UInt(NSURL.BookmarkCreationOptions.withSecurityScope.rawValue
                          | NSURL.BookmarkCreationOptions.securityScopeAllowOnlyReadAccess.rawValue),
            isForStaleBookmark: false,
            isForKnownHostsFile: false
        )

        path = url.path
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
