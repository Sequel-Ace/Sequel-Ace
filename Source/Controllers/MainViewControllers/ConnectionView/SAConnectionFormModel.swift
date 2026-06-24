//
//  SAConnectionFormModel.swift
//  Sequel Ace
//
//  Phase C2 of the SwiftUI migration: the observable model behind
//  SAConnectionFormView. Wraps the value-type SAConnectionInfo so
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

final class SAConnectionFormModel: ObservableObject {

    /// The connection parameters being edited. SwiftUI binds into this
    /// directly (e.g. `$model.info.host`) — mutating any field publishes
    /// a change for the whole model, which is the granularity the form
    /// needs (the effective name and validation state depend on several
    /// fields at once).
    @Published var info: SAConnectionInfo

    init(info: SAConnectionInfo = SAConnectionInfo()) {
        self.info = info
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
        return SAConnectionFormHelpers.generateName(type: info.type,
                                                    host: info.host,
                                                    database: info.database) ?? ""
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
        case .tcpIP, .awsIAM, .vault:
            return hasHost
        }
    }

    // MARK: - Validation

    /// Runs the D3 pre-connection checks against the current values.
    /// Returns nil when the details are valid; otherwise the first
    /// failure, carrying ready-to-display alert strings.
    func validate() -> SAConnectionValidationFailure? {
        SAConnectionDetailsValidator.validate(
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
}
