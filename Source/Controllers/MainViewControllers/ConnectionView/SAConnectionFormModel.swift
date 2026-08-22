//
//  SAConnectionFormModel.swift
//  Sequel Ace
//
//  Phase C2 of the SwiftUI migration: the observable model behind
//  SAConnectionFormView. C2a covered TCP/IP; C2b extends it to every
//  connection type (socket, SSH tunnel, AWS IAM, Vault) plus the SSL
//  file options, colour index and time zone the XIB tabs carry.
//  Wraps the value-type SAConnectionInfo so
//  SwiftUI fields can bind straight into it ($model.info.host), and
//  funnels the pieces extracted in earlier phases:
//  - SAConnectionDetailsValidator (D3) for pre-connection validation
//  - SAConnectionFormHelpers for the auto-generated connection name
//  - SAConnectionInfoObjC for bridging from/to the ObjC controller world
//
//  Pure Foundation + Combine (no AppKit/SwiftUI), so it compiles into
//  the Unit Tests target and the behaviour is pinned by
//  SAConnectionFormModelTests.
//

import Foundation
import Combine

// MARK: - Time Zone Choice

/// The three states the XIB's time-zone popup can be in, collapsed into
/// one value. `SAConnectionInfo` stores this as a (mode, identifier)
/// pair where the identifier is only meaningful in `.useFixedTZ`; this
/// makes the invalid combinations unrepresentable so a SwiftUI picker
/// can bind to a single selection.
enum SATimeZoneChoice: Hashable {
    case server
    case system
    case fixed(String)

    /// Reconstructs the choice from the stored pair. A fixed mode with a
    /// blank identifier degrades to `.server`, matching the AppKit popup,
    /// which has no menu item that could represent it.
    init(mode: SAConnectionTimeZoneMode, identifier: String) {
        switch mode {
        case .useServerTZ:
            self = .server
        case .useSystemTZ:
            self = .system
        case .useFixedTZ:
            self = identifier.isEmpty ? .server : .fixed(identifier)
        }
    }

    var mode: SAConnectionTimeZoneMode {
        switch self {
        case .server: return .useServerTZ
        case .system: return .useSystemTZ
        case .fixed: return .useFixedTZ
        }
    }

    /// Blank for the two relative modes — `-didChangeSelectedTimeZone:`
    /// clears the identifier when leaving the fixed mode, and a stale
    /// identifier would otherwise be written back to the favorite.
    var identifier: String {
        switch self {
        case .server, .system: return ""
        case .fixed(let identifier): return identifier
        }
    }
}

/// One row of the time-zone picker, mirroring `-generateTimeZoneMenuItems`:
/// the two relative entries first, then every known identifier sorted
/// case-insensitively, with a separator wherever the region prefix changes.
enum SATimeZoneMenuEntry: Hashable {
    case choice(SATimeZoneChoice)
    case separator(afterPrefix: String)

    /// The full menu, in order.
    static func menu(identifiers: [String] = TimeZone.knownTimeZoneIdentifiers) -> [SATimeZoneMenuEntry] {
        var entries: [SATimeZoneMenuEntry] = [
            .choice(.server),
            .separator(afterPrefix: ""),
            .choice(.system),
        ]

        var previousPrefix = ""
        for identifier in identifiers.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let prefix = identifier.components(separatedBy: "/").first ?? identifier
            if prefix != previousPrefix {
                previousPrefix = prefix
                entries.append(.separator(afterPrefix: prefix))
            }
            entries.append(.choice(.fixed(identifier)))
        }

        return entries
    }
}

final class SAConnectionFormModel: ObservableObject {

    /// The connection parameters being edited. SwiftUI binds into this
    /// directly (e.g. `$model.info.host`) — mutating any field publishes
    /// a change for the whole model, which is the granularity the form
    /// needs (the effective name and validation state depend on several
    /// fields at once).
    @Published var info: SAConnectionInfo {
        didSet {
            resplitVaultCredentialsPathIfChangedExternally()
        }
    }

    // MARK: Vault mount / role

    // `info.vaultCredentialsPath` persists the joined "<mount>/creds/<role>",
    // but the form edits the two halves separately — same split the AppKit
    // controller keeps as its `vaultMount` / `vaultCredentialsRole` ivars with
    // a computed `vaultCredentialsPath` on top. They have to be stored rather
    // than computed off the path: `credPath(mount:role:)` returns "" while the
    // role is still blank, so a mount typed first would otherwise vanish.

    @Published var vaultMount: String = "" {
        didSet { rejoinVaultCredentialsPath() }
    }

    @Published var vaultCredentialsRole: String = "" {
        didSet { rejoinVaultCredentialsPath() }
    }

    /// The blank form's historical state: no colour (-1), compression on, AWS
    /// profile "default". Raw `SAConnectionInfo()` matches none of those, so a
    /// model built from it would show the first colour swatch as chosen and
    /// silently connect without compression.
    static var blankFormInfo: SAConnectionInfo {
        SAConnectionInfoObjC.info(fromFavoriteDictionary: nil).info
    }

    init(info: SAConnectionInfo = SAConnectionFormModel.blankFormInfo) {
        self.info = info
        // Same one-read rule as the resplit below (didSet observers do not run
        // during init, but the parameter is the honest source either way).
        let credentialsPath = info.vaultCredentialsPath
        vaultMount = SAVaultCredentialsPath.mount(fromCredPath: credentialsPath)
        vaultCredentialsRole = SAVaultCredentialsPath.role(fromCredPath: credentialsPath)
    }

    /// Splits a full credentials path out of the Role half into Mount + Role.
    ///
    /// Mirrors `-controlTextDidEndEditing:`, which does this on commit rather
    /// than per keystroke so a path being typed is not yanked away mid-edit.
    /// Without it the two controls disagree with the endpoint actually used:
    /// `credPath(mount:role:)` honours a pasted full path and ignores the
    /// mount, so the stale mount stays on screen — and the moment the user
    /// then types a bare role, it silently comes back.
    func commitVaultCredentialsRole() {
        guard SAVaultCredentialsPath.isFullCredPath(vaultCredentialsRole) else { return }

        let pasted = vaultCredentialsRole
        vaultMount = SAVaultCredentialsPath.mount(fromCredPath: pasted)
        vaultCredentialsRole = SAVaultCredentialsPath.role(fromCredPath: pasted)
    }

    private func rejoinVaultCredentialsPath() {
        info.vaultCredentialsPath = SAVaultCredentialsPath.credPath(mount: vaultMount,
                                                                    role: vaultCredentialsRole)
    }

    /// Re-derives the two halves when `info` is replaced wholesale — loading a
    /// favorite, say. Skipped when the path already equals what the current
    /// halves join to, which is what stops `rejoinVaultCredentialsPath` and
    /// this from bouncing off each other.
    private func resplitVaultCredentialsPathIfChangedExternally() {
        let joined = SAVaultCredentialsPath.credPath(mount: vaultMount, role: vaultCredentialsRole)
        guard info.vaultCredentialsPath != joined else { return }

        // Read the incoming path once, up front: assigning either half runs
        // `rejoinVaultCredentialsPath`, which overwrites
        // `info.vaultCredentialsPath` with the half-updated pair — so reading
        // it again for the second half would parse the value we just wrote.
        let incoming = info.vaultCredentialsPath
        vaultMount = SAVaultCredentialsPath.mount(fromCredPath: incoming)
        vaultCredentialsRole = SAVaultCredentialsPath.role(fromCredPath: incoming)
    }

    /// Bridge in from the ObjC wrapper (e.g. the controller's current
    /// details, or a favorite decoded via fromFavoriteDictionary).
    convenience init(objc: SAConnectionInfoObjC) {
        self.init(info: objc.info)
    }

    /// Bridge the edited values back into an ObjC wrapper.
    func apply(to objc: SAConnectionInfoObjC) {
        objc.info = info
    }

    // MARK: - Derived display values

    /// The name shown for this connection: the user-entered name when
    /// present, otherwise the auto-generated "host[/database]" name the
    /// AppKit form produces (SAConnectionFormHelpers.generateName), or
    /// "" when there is not enough information yet.
    var effectiveName: String {
        let trimmed = info.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return generatedName ?? ""
    }

    /// The auto-generated name for the current values, or nil when there is not
    /// enough to build one. Vault names come from the Vault endpoint and role
    /// rather than the database host.
    var generatedName: String? {
        SAConnectionFormHelpers.generateName(type: info.type,
                                             host: info.host,
                                             database: info.database,
                                             vaultHost: info.vaultHost,
                                             vaultCredentialsPath: info.vaultCredentialsPath)
    }

    /// True when the form has the minimum input to attempt a connection
    /// (used to enable the Connect button before full validation runs).
    /// Mirrors the host rule in SAConnectionDetailsValidator: an SSH
    /// tunnel that targets a remote socket path doesn't need a MySQL
    /// host (SAConnectionService connects through the socket instead).
    var canAttemptConnection: Bool {
        let hasHost = !info.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch info.type {
        case .socket:
            return true
        case .sshTunnel:
            let hasRemoteSocket = !info.sshRemoteSocketPath
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasHost || hasRemoteSocket
        case .tcpIP, .awsIAM:
            return hasHost
        case .vault:
            // Vault needs its own endpoint and a credentials path on top of the
            // database host — `-initiateConnection:` rejects all three.
            return hasHost
                && !info.vaultHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !info.vaultCredentialsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Time zone

    /// The time-zone popup's selection, collapsing the stored
    /// (mode, identifier) pair. Setting it writes both, clearing the
    /// identifier outside the fixed mode exactly as
    /// `-didChangeSelectedTimeZone:` does.
    var timeZoneChoice: SATimeZoneChoice {
        get { SATimeZoneChoice(mode: info.timeZoneMode, identifier: info.timeZoneIdentifier) }
        set {
            info.timeZoneMode = newValue.mode
            info.timeZoneIdentifier = newValue.identifier
        }
    }

    // MARK: - Flag bridges

    // SAConnectionInfo stores these as Int because they cross into ObjC as
    // 0/1; SwiftUI Toggles need Bool. Non-zero counts as on, which is what
    // the ObjC `-boolValue` reads the favorite plist with.

    private func flag(_ keyPath: WritableKeyPath<SAConnectionInfo, Int>) -> Bool {
        info[keyPath: keyPath] != 0
    }

    private func setFlag(_ keyPath: WritableKeyPath<SAConnectionInfo, Int>, _ isOn: Bool) {
        info[keyPath: keyPath] = isOn ? 1 : 0
    }

    var useSSL: Bool {
        get { flag(\.useSSL) }
        set { setFlag(\.useSSL, newValue) }
    }

    var allowDataLocalInfile: Bool {
        get { flag(\.allowDataLocalInfile) }
        set { setFlag(\.allowDataLocalInfile, newValue) }
    }

    var enableClearTextPlugin: Bool {
        get { flag(\.enableClearTextPlugin) }
        set { setFlag(\.enableClearTextPlugin, newValue) }
    }

    var requestServerPublicKey: Bool {
        get { flag(\.requestServerPublicKey) }
        set { setFlag(\.requestServerPublicKey, newValue) }
    }

    var sshKeyLocationEnabled: Bool {
        get { flag(\.sshKeyLocationEnabled) }
        set { setFlag(\.sshKeyLocationEnabled, newValue) }
    }

    var sslKeyFileLocationEnabled: Bool {
        get { flag(\.sslKeyFileLocationEnabled) }
        set { setFlag(\.sslKeyFileLocationEnabled, newValue) }
    }

    var sslCertificateFileLocationEnabled: Bool {
        get { flag(\.sslCertificateFileLocationEnabled) }
        set { setFlag(\.sslCertificateFileLocationEnabled, newValue) }
    }

    var sslCACertFileLocationEnabled: Bool {
        get { flag(\.sslCACertFileLocationEnabled) }
        set { setFlag(\.sslCACertFileLocationEnabled, newValue) }
    }

    // MARK: - Per-type form shape

    /// AWS IAM turns SSL and the cleartext plugin on itself, so its tab
    /// shows neither toggle — it shows a static explanatory label instead
    /// (see `awsIAMConnectionFormContainer` in ConnectionView.xib, which
    /// is also the only tab with no SSL details container).
    var forcesSSL: Bool {
        info.type == .awsIAM
    }

    /// Whether the "Require SSL" toggle is offered at all.
    var showsSSLToggle: Bool {
        !forcesSSL
    }

    /// Whether the three SSL file pickers (key / certificate / CA cert)
    /// are visible. The XIB reveals that container only while the type's
    /// SSL toggle is on, and never for AWS IAM.
    var showsSSLFileOptions: Bool {
        showsSSLToggle && useSSL
    }

    /// The cleartext-plugin toggle is likewise absent from the AWS tab.
    var showsClearTextPluginToggle: Bool {
        !forcesSSL
    }

    /// "Get Public Key" is offered on every tab except AWS IAM.
    var showsRequestServerPublicKeyToggle: Bool {
        !forcesSSL
    }

    // MARK: - Identity changes

    /// Drops both stored passwords.
    ///
    /// `-controlTextDidEndEditing:` clears the database *and* SSH password
    /// whenever the standard host, standard user, SSH host or SSH user changes,
    /// so credentials hydrated for one account are never sent under another
    /// identity. Called on commit rather than per keystroke, as there.
    func clearPasswordsAfterIdentityChange() {
        info.password = ""
        info.sshPassword = ""
    }

    // MARK: - Validation

    /// Runs the D3 pre-connection checks against the current values.
    /// Returns nil when the details are valid; otherwise the first
    /// failure, carrying ready-to-display alert strings.
    func validate() -> SAConnectionValidationFailure? {
        if let vaultFailure = validateVaultDetails() {
            return vaultFailure
        }

        return SAConnectionDetailsValidator.validate(
            type: info.type,
            host: info.host,
            sshHost: info.sshHost,
            sshRemoteSocketPath: info.sshRemoteSocketPath,
            useSSL: info.useSSL != 0,
            sshKeyLocationEnabled: info.sshKeyLocationEnabled != 0,
            sshKeyLocation: info.sshKeyLocation,
            sslKeyFileLocationEnabled: info.sslKeyFileLocationEnabled != 0,
            sslKeyFileLocation: info.sslKeyFileLocation,
            sslCertificateFileLocationEnabled: info.sslCertificateFileLocationEnabled != 0,
            sslCertificateFileLocation: info.sslCertificateFileLocation,
            sslCACertFileLocationEnabled: info.sslCACertFileLocationEnabled != 0,
            sslCACertFileLocation: info.sslCACertFileLocation
        )
    }

    /// The three Vault preconditions `-initiateConnection:` enforces before it
    /// starts authenticating, in its order. They are not in
    /// `SAConnectionDetailsValidator` because that is shared with the AppKit
    /// controller, which still runs these itself; duplicating them there would
    /// double the alert.
    private func validateVaultDetails() -> SAConnectionValidationFailure? {
        guard info.type == .vault else { return nil }

        let title = NSLocalizedString("Insufficient connection details",
                                      comment: "insufficient details message")

        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if blank(info.vaultHost) {
            return SAConnectionValidationFailure(
                kind: .vaultHostMissing,
                alertTitle: title,
                alertMessage: NSLocalizedString("A Vault host is required to connect.",
                                                comment: "vault host required connect message")
            )
        }

        if blank(info.vaultCredentialsPath) {
            return SAConnectionValidationFailure(
                kind: .vaultCredentialsPathMissing,
                alertTitle: title,
                alertMessage: NSLocalizedString("A Vault credentials path is required to connect. Fill in the mount and role, or paste a full path into the Role field.",
                                                comment: "vault creds path required connect message")
            )
        }

        if blank(info.host) {
            return SAConnectionValidationFailure(
                kind: .hostMissing,
                alertTitle: title,
                alertMessage: NSLocalizedString("A database host is required to connect.",
                                                comment: "vault db host required connect message")
            )
        }

        return nil
    }
}
