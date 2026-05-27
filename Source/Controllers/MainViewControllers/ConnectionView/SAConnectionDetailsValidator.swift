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
        if (type == .tcpIP || type == .sshTunnel || type == .awsIAM) && host.isEmpty {
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
        if type == .sshTunnel && sshHost.isEmpty {
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
