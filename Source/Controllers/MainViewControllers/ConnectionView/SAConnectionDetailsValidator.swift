//
//  SAConnectionDetailsValidator.swift
//  Sequel Ace
//
//  Pre-connection validation lifted out of
//  -[SPConnectionController initiateConnection:] as Phase D3 of the
//  modernization follow-up plan. The validator decides whether the
//  form's current state would produce a viable connection attempt;
//  alert presentation and per-failure UI side effects (clearing
//  enabled toggles, resetting paths) stay in the controller.
//
//  No AppKit dependency — compiled into the Unit Tests target alongside
//  the app target (same pattern as SAViewMode / SADatabaseListManager).
//

import Foundation

/// Discriminator for the kind of validation that failed. Carried as
/// an enum so the controller can branch on it for the per-failure
/// side effects (e.g. SSL key failure clears two state values, host
/// failure clears none).
@objc enum SAConnectionValidationFailureKind: Int {
    case hostMissing
    case sshHostMissing
    case sshKeyFileMissing
    case sslKeyFileMissing
    case sslCertificateFileMissing
    case sslCACertFileMissing
    // Vault-only preconditions. Raised by SAConnectionFormModel rather than the
    // validator below, which is shared with the AppKit controller — that runs
    // its own Vault checks, and duplicating them here would double the alert.
    case vaultHostMissing
    case vaultCredentialsPathMissing
}

/// What the validator returns on failure. Bundles the discriminator
/// and the ready-to-display alert strings — the controller doesn't
/// need to know the wording for each case.
@objc final class SAConnectionValidationFailure: NSObject {
    @objc let kind: SAConnectionValidationFailureKind
    @objc let alertTitle: String
    @objc let alertMessage: String

    init(kind: SAConnectionValidationFailureKind, alertTitle: String, alertMessage: String) {
        self.kind = kind
        self.alertTitle = alertTitle
        self.alertMessage = alertMessage
        super.init()
    }
}

@objc final class SAConnectionDetailsValidator: NSObject {

    /// Run the pre-connection checks in the same order as the original
    /// inline code. Returns `nil` if the form is valid, otherwise the
    /// first failure encountered.
    ///
    /// Each `*Location` argument is the raw value the user typed —
    /// the validator handles tilde expansion before checking the file.
    /// Each `*Enabled` argument is the matching checkbox's bool state;
    /// when it's `false`, the file check is skipped (the path is
    /// considered "not provided" rather than "missing").
    ///
    /// `host` and `sshHost` are taken as already-resolved strings.
    /// AWS-directory authorization is intentionally NOT covered here:
    /// it depends on Security framework bookmark state that's hard to
    /// fake in a pure validator and stays inline in the controller.
    @objc static func validate(
        type: SAConnectionType,
        host: String,
        sshHost: String,
        sshRemoteSocketPath: String,
        useSSL: Bool,
        sshKeyLocationEnabled: Bool,
        sshKeyLocation: String?,
        sslKeyFileLocationEnabled: Bool,
        sslKeyFileLocation: String?,
        sslCertificateFileLocationEnabled: Bool,
        sslCertificateFileLocation: String?,
        sslCACertFileLocationEnabled: Bool,
        sslCACertFileLocation: String?
    ) -> SAConnectionValidationFailure? {
        // 1. Host required for TCP/IP, SSH tunnel, and AWS IAM
        //    connections — socket connections use a local socket path.
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSSHHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemoteSocketPath = sshRemoteSocketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let sshTunnelUsesRemoteSocket = type == .sshTunnel && !trimmedRemoteSocketPath.isEmpty
        if (type == .tcpIP || (type == .sshTunnel && !sshTunnelUsesRemoteSocket) || type == .awsIAM) && trimmedHost.isEmpty {
            return SAConnectionValidationFailure(
                kind: .hostMissing,
                alertTitle: NSLocalizedString("Insufficient connection details",
                                              comment: "insufficient details message"),
                alertMessage: NSLocalizedString(
                    "Insufficient details provided to establish a connection. Please enter at least the hostname.",
                    comment: "insufficient details informative message")
            )
        }

        // 2. SSH host required for SSH-tunnel connections.
        if type == .sshTunnel && trimmedSSHHost.isEmpty {
            return SAConnectionValidationFailure(
                kind: .sshHostMissing,
                alertTitle: NSLocalizedString("Insufficient connection details",
                                              comment: "insufficient details message"),
                alertMessage: NSLocalizedString(
                    "Insufficient details provided to establish a connection. Please enter the hostname for the SSH Tunnel, or disable the SSH Tunnel.",
                    comment: "insufficient SSH tunnel details informative message")
            )
        }

        // 3. SSH key file must exist when SSH-tunnel + key location toggle enabled.
        if type == .sshTunnel, sshKeyLocationEnabled, let path = sshKeyLocation,
           !fileExistsExpandingTilde(path) {
            return SAConnectionValidationFailure(
                kind: .sshKeyFileMissing,
                alertTitle: NSLocalizedString("SSH Key not found",
                                              comment: "SSH key check error"),
                alertMessage: NSLocalizedString(
                    "A SSH key location was specified, but no file was found in the specified location.  Please re-select the key and try again.",
                    comment: "SSH key not found message")
            )
        }

        // 4-6. SSL file checks — run for connection types whose MySQL leg can use
        //      the shared SSL file fields. The order matches the original code so that
        //      a multi-issue form produces the same first-error UX.
        //
        //      ⚠️ `.sshTunnel` is absent on purpose, and it is probably an upstream
        //      bug rather than a decision: the SSH tab does have a "Require SSL"
        //      checkbox and its own SSL details container
        //      (`sshConnectionSSLDetailsContainer`, `sslOverSSHKeyFileButton` and
        //      friends), so an enabled-but-missing key/cert/CA on a tunnel reaches
        //      connection setup unchecked. The pre-D3 ObjC read
        //      `(type == SPTCPIPConnection || type == SPSocketConnection) && useSSL`,
        //      D3 preserved that, and `testSSLChecksDoNotApplyToSSHTunnel` pins it.
        //      Changing it would also change the shipping AppKit form, so it wants
        //      its own PR rather than riding along with the SwiftUI work.
        if (type == .tcpIP || type == .socket || type == .vault) && useSSL {
            if sslKeyFileLocationEnabled, let path = sslKeyFileLocation,
               !fileExistsExpandingTilde(path) {
                return SAConnectionValidationFailure(
                    kind: .sslKeyFileMissing,
                    alertTitle: NSLocalizedString("SSL Key File not found",
                                                  comment: "SSL key file check error"),
                    alertMessage: NSLocalizedString(
                        "A SSL key file location was specified, but no file was found in the specified location.  Please re-select the key file and try again.",
                        comment: "SSL key file not found message")
                )
            }

            if sslCertificateFileLocationEnabled, let path = sslCertificateFileLocation,
               !fileExistsExpandingTilde(path) {
                return SAConnectionValidationFailure(
                    kind: .sslCertificateFileMissing,
                    alertTitle: NSLocalizedString("SSL Certificate File not found",
                                                  comment: "SSL certificate file check error"),
                    alertMessage: NSLocalizedString(
                        "A SSL certificate location was specified, but no file was found in the specified location.  Please re-select the certificate and try again.",
                        comment: "SSL certificate file not found message")
                )
            }

            if sslCACertFileLocationEnabled, let path = sslCACertFileLocation,
               !fileExistsExpandingTilde(path) {
                return SAConnectionValidationFailure(
                    kind: .sslCACertFileMissing,
                    alertTitle: NSLocalizedString("SSL Certificate Authority File not found",
                                                  comment: "SSL certificate authority file check error"),
                    alertMessage: NSLocalizedString(
                        "A SSL Certificate Authority certificate location was specified, but no file was found in the specified location.  Please re-select the Certificate Authority certificate and try again.",
                        comment: "SSL CA certificate file not found message")
                )
            }
        }

        return nil
    }

    /// Mirrors the original code's `-stringByExpandingTildeInPath` +
    /// `-fileExistsAtPath:` pair. Exposed via a thin static so tests
    /// can also use it to assert that a known path exists/doesn't.
    @objc static func fileExistsExpandingTilde(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
    }
}

// MARK: - Chooser file kinds

/// The four file rows the connection form offers, and what each one requires
/// of the file the user picks.
///
/// Splitting this out of the AppKit chooser is what lets the SwiftUI form apply
/// the same rules: `-chooseKeyLocation:` branches on which button sent the
/// action, which a SwiftUI row has no equivalent of.
@objc enum SAConnectionFileKind: Int {
    case sshKey
    case sslKey
    case sslCertificate
    case sslCACert

    /// The PEM body marker the file must carry, or nil where the AppKit flow
    /// accepts any file. Only the SSL key and client certificate are checked —
    /// SSH keys and CA certificates are deliberately not, matching
    /// `-chooseKeyLocation:`, which validates just those two.
    var requiredPEMMarker: String? {
        switch self {
        case .sslKey: return "PRIVATE KEY-----"
        case .sslCertificate: return "CERTIFICATE-----"
        case .sshKey, .sslCACert: return nil
        }
    }

    /// File extensions the chooser must refuse outright.
    ///
    /// `-panel:shouldEnableURL:` greys out `.pub` files so an SSH *public* key
    /// cannot be picked as an identity file — OpenSSH cannot use one, and the
    /// failure would otherwise only appear when the tunnel connects.
    var rejectedExtensions: Set<String> {
        switch self {
        case .sshKey: return ["pub"]
        case .sslKey, .sslCertificate, .sslCACert: return []
        }
    }
}

/// Why a chosen file was rejected, carrying the same strings the AppKit alert
/// shows.
struct SAConnectionFileRejection {
    let alertTitle: String
    let alertMessage: String
}

/// PEM shape checks for the files the connection form accepts, lifted out of
/// `-validateKeyFile:error:` / `-validateCertFile:error:` so they can be tested
/// without a controller. Pure: the caller supplies the file's contents.
@objc final class SAConnectionFileValidator: NSObject {

    /// Whether `contents` looks like a PEM block for `kind`.
    ///
    /// Mirrors the original paragraph walk: a BEGIN line and an END line, each
    /// carrying the marker. Paragraph enumeration is what handles `\n`, `\r`
    /// and `\r\n` alike, so the split below uses `.newlines` rather than
    /// splitting on `\n` only. Kinds with no marker accept anything.
    static func isValidPEM(contents: String, kind: SAConnectionFileKind) -> Bool {
        guard let marker = kind.requiredPEMMarker else { return true }

        var foundBegin = false
        var foundEnd = false

        for line in contents.components(separatedBy: .newlines) {
            guard line.contains(marker) else { continue }
            if line.contains("-----BEGIN") { foundBegin = true }
            if line.contains("-----END") { foundEnd = true }
        }

        return foundBegin && foundEnd
    }

    /// The rejection for a file that failed `isValidPEM`, or nil when it passed.
    /// `fileName` is the display name used in the title, as the original used
    /// `-lastPathComponent`.
    static func rejection(contents: String,
                          kind: SAConnectionFileKind,
                          fileName: String) -> SAConnectionFileRejection? {
        guard !isValidPEM(contents: contents, kind: kind) else { return nil }

        switch kind {
        case .sslKey:
            return SAConnectionFileRejection(
                alertTitle: String(format: NSLocalizedString("“%@” is not a valid private key file.",
                                                             comment: "connection view : ssl : key file picker : wrong format error title"),
                                   fileName),
                alertMessage: NSLocalizedString("Make sure the file contains a RSA private key and is using PEM encoding.",
                                                comment: "connection view : ssl : key file picker : wrong format error description")
            )
        case .sslCertificate:
            return SAConnectionFileRejection(
                alertTitle: String(format: NSLocalizedString("“%@” is not a valid client certificate file.",
                                                             comment: "connection view : ssl : client cert file picker : wrong format error title"),
                                   fileName),
                alertMessage: NSLocalizedString("Make sure the file contains a X.509 client certificate and is using PEM encoding.",
                                                comment: "connection view : ssl : client cert picker : wrong format error description")
            )
        case .sshKey, .sslCACert:
            // Unreachable: these kinds have no marker, so isValidPEM passed.
            return nil
        }
    }

    /// Reads `url` and returns its rejection, or nil when it is acceptable.
    /// An unreadable file is reported with the underlying read error, matching
    /// the original, which surfaced the NSData error before its own check.
    static func rejection(forFileAt url: URL, kind: SAConnectionFileKind) -> SAConnectionFileRejection? {
        if kind.rejectedExtensions.contains(url.pathExtension.lowercased()) {
            return SAConnectionFileRejection(
                alertTitle: String(format: NSLocalizedString("“%@” is a public key.",
                                                             comment: "connection view : ssh : key file picker : public key error title"),
                                   url.lastPathComponent),
                alertMessage: NSLocalizedString("Choose the private key instead — the file without the .pub extension.",
                                                comment: "connection view : ssh : key file picker : public key error description")
            )
        }

        guard kind.requiredPEMMarker != nil else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            return SAConnectionFileRejection(alertTitle: error.localizedDescription,
                                             alertMessage: (error as NSError).localizedRecoverySuggestion ?? "")
        }

        // ASCII, as the original decoded it: PEM is ASCII-armoured, and a
        // non-ASCII byte means this is not a PEM file to begin with.
        let contents = String(data: data, encoding: .ascii) ?? ""
        return rejection(contents: contents, kind: kind, fileName: url.lastPathComponent)
    }
}
