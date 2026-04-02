//
//  SAConnectionService.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Extracts MySQL connection establishment logic from SPConnectionController
//  into a standalone service that takes connection parameters and returns
//  a configured SPMySQLConnection or an error.
//

import Foundation

/// Result of a connection attempt, carrying either a live connection or
/// diagnostic error information for the controller to format into UI.
@objc class SAConnectionResult: NSObject {
    @objc let connection: SPMySQLConnection?
    @objc let sshTunnel: SPSSHTunnel?
    @objc let errorTitle: String?
    @objc let errorMessage: String?
    @objc let errorDetail: String?
    @objc let isLocalNetworkDenied: Bool

    // Diagnostic fields for controller-side error formatting
    @objc let lastErrorID: UInt
    @objc let rawErrorMessage: String
    @objc let sshDebugMessages: String
    @objc let connectionType: SAConnectionType
    @objc let socketPath: String
    @objc let databaseSelectionFailed: Bool
    @objc let databaseSelectionError: String

    @objc var isSuccess: Bool { connection != nil && errorTitle == nil }

    @objc init(connection: SPMySQLConnection, sshTunnel: SPSSHTunnel?,
               databaseSelectionFailed: Bool = false, databaseSelectionError: String = "") {
        self.connection = connection
        self.sshTunnel = sshTunnel
        self.errorTitle = nil
        self.errorMessage = nil
        self.errorDetail = nil
        self.isLocalNetworkDenied = false
        self.lastErrorID = 0
        self.rawErrorMessage = ""
        self.sshDebugMessages = ""
        self.connectionType = .tcpIP
        self.socketPath = ""
        self.databaseSelectionFailed = databaseSelectionFailed
        self.databaseSelectionError = databaseSelectionError
        super.init()
    }

    @objc init(errorTitle: String, errorMessage: String?, errorDetail: String?,
               isLocalNetworkDenied: Bool = false,
               lastErrorID: UInt = 0, rawErrorMessage: String = "",
               sshDebugMessages: String = "",
               connectionType: SAConnectionType = .tcpIP, socketPath: String = "") {
        self.connection = nil
        self.sshTunnel = nil
        self.errorTitle = errorTitle
        self.errorMessage = errorMessage
        self.errorDetail = errorDetail
        self.isLocalNetworkDenied = isLocalNetworkDenied
        self.lastErrorID = lastErrorID
        self.rawErrorMessage = rawErrorMessage
        self.sshDebugMessages = sshDebugMessages
        self.connectionType = connectionType
        self.socketPath = socketPath
        self.databaseSelectionFailed = false
        self.databaseSelectionError = ""
        super.init()
    }
}

/// Connection preferences extracted from NSUserDefaults.
@objc class SAConnectionPreferences: NSObject {
    @objc var connectionTimeout: Int = 10
    @objc var useKeepAlive: Bool = true
    @objc var keepAliveInterval: Float = 60.0
    @objc var enableQueryLogging: Bool = false
    @objc var sslCipherList: String?

    @objc static func fromUserDefaults() -> SAConnectionPreferences {
        let prefs = UserDefaults.standard
        let cp = SAConnectionPreferences()
        cp.connectionTimeout = prefs.integer(forKey: SPConnectionTimeoutValue)
        cp.useKeepAlive = prefs.bool(forKey: SPUseKeepAlive)
        cp.keepAliveInterval = prefs.float(forKey: SPKeepAliveInterval)
        cp.enableQueryLogging = prefs.bool(forKey: SPConsoleEnableLogging)
        cp.sslCipherList = prefs.string(forKey: SPSSLCipherListKey)
        return cp
    }
}

/// Service that creates and configures MySQL connections.
///
/// Extracts the pure connection logic from SPConnectionController,
/// making it testable and reusable from different UI contexts.
@objc class SAConnectionService: NSObject {

    /// The delegate that receives MySQL connection callbacks (query logging, etc).
    @objc weak var mySQLDelegate: (any SPMySQLConnectionDelegate)?

    /// Active SSH tunnel, kept alive for the duration of the connection.
    @objc private(set) var activeTunnel: SPSSHTunnel?

    /// The active MySQL connection being established (nil when idle).
    @objc private(set) var activeConnection: SPMySQLConnection?

    /// Stored completion for SSH tunnel callback.
    private var sshTunnelCompletion: ((SPSSHTunnel?, String?) -> Void)?

    // MARK: - Public API

    /// Creates and configures an SPMySQLConnection from the given parameters.
    /// Runs on a background thread; calls completion on the main thread.
    @objc func connect(
        with info: SAConnectionInfoObjC,
        preferences: SAConnectionPreferences,
        password: String,
        sshPassword: String,
        parentWindow: NSWindow?,
        completion: @escaping (SAConnectionResult) -> Void
    ) {
        if info.type == .sshTunnel {
            establishSSHTunnel(info: info, sshPassword: sshPassword, parentWindow: parentWindow) { [weak self] (tunnel: SPSSHTunnel?, error: String?) in
                guard let self = self else { return }
                if let tunnel = tunnel {
                    self.activeTunnel = tunnel
                    self.connectMySQL(info: info, preferences: preferences, password: password, tunnel: tunnel, completion: completion)
                } else {
                    let result = SAConnectionResult(
                        errorTitle: NSLocalizedString("SSH connection failed!", comment: ""),
                        errorMessage: error,
                        errorDetail: nil
                    )
                    DispatchQueue.main.async { completion(result) }
                }
            }
        } else {
            connectMySQL(info: info, preferences: preferences, password: password, tunnel: nil, completion: completion)
        }
    }

    /// Cancels an in-progress connection attempt.
    @objc func cancel() {
        if let conn = activeConnection {
            conn.setDelegate(nil)
            Thread.detachNewThread {
                conn.disconnect()
            }
        }
        activeTunnel?.disconnect()
        activeConnection = nil
        activeTunnel = nil
    }

    // MARK: - Private: MySQL Connection

    private func connectMySQL(
        info: SAConnectionInfoObjC,
        preferences: SAConnectionPreferences,
        password: String,
        tunnel: SPSSHTunnel?,
        completion: @escaping (SAConnectionResult) -> Void
    ) {
        Thread.detachNewThread { [weak self] in
            guard let self = self else { return }

            let conn = SPMySQLConnection()
            self.activeConnection = conn

            conn.username = info.user

            switch info.type {
            case .socket:
                conn.useSocket = true
                conn.socketPath = info.socket

            case .sshTunnel:
                conn.useSocket = false
                conn.host = "127.0.0.1"
                if let tunnel = tunnel {
                    conn.port = UInt(tunnel.localPort())
                    conn.setProxy(tunnel)
                }

            case .tcpIP, .awsIAM:
                conn.useSocket = false
                conn.host = info.host
                conn.port = UInt(info.port) ?? 3306

            @unknown default:
                break
            }

            conn.password = password
            conn.allowDataLocalInfile = info.allowDataLocalInfile != 0
            conn.enableClearTextPlugin = info.enableClearTextPlugin != 0

            if info.useSSL != 0 {
                conn.useSSL = true
                if info.sslKeyFileLocationEnabled != 0 {
                    conn.sslKeyFilePath = info.sslKeyFileLocation
                }
                if info.sslCertificateFileLocationEnabled != 0 {
                    conn.sslCertificatePath = info.sslCertificateFileLocation
                }
                if info.sslCACertFileLocationEnabled != 0 {
                    conn.sslCACertificatePath = info.sslCACertFileLocation
                }
                if let cipher = preferences.sslCipherList {
                    conn.sslCipherList = cipher
                }
            }

            if !info.useCompression {
                conn.removeClientFlags(.compression)
            }

            if let delegate = self.mySQLDelegate {
                conn.setDelegate(delegate)
            }
            conn.delegateQueryLogging = preferences.enableQueryLogging
            conn.timeout = UInt(preferences.connectionTimeout)
            conn.useKeepAlive = preferences.useKeepAlive
            conn.keepAliveInterval = CGFloat(preferences.keepAliveInterval)

            conn.connect()

            // SSH tunnel fallback: if connection failed through tunnel,
            // wait briefly for SSH debug output, then retry with fallback port
            if !conn.isConnected(), let tunnel = tunnel {
                Thread.sleep(forTimeInterval: 0.1)
                if tunnel.state() == SPMySQLProxyForwardingFailed,
                   tunnel.localPortFallback() > 0 {
                    conn.port = UInt(tunnel.localPortFallback())
                    conn.connect()
                    if !conn.isConnected() {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
            }

            if !conn.isConnected() {
                let errorString = conn.lastErrorMessage() ?? ""
                let errorID = conn.lastErrorID()

                let result = SAConnectionResult(
                    errorTitle: NSLocalizedString("Unable to connect", comment: ""),
                    errorMessage: errorString,
                    errorDetail: errorID == 1045
                        ? NSLocalizedString("Please check your username and password and try again.", comment: "")
                        : nil,
                    isLocalNetworkDenied: errorString.lowercased().contains("network"),
                    lastErrorID: errorID,
                    rawErrorMessage: errorString,
                    sshDebugMessages: tunnel?.debugMessages() ?? "",
                    connectionType: info.type,
                    socketPath: info.socket
                )

                DispatchQueue.main.async { completion(result) }
                return
            }

            // Database selection
            if !info.database.isEmpty && !conn.selectDatabase(info.database) {
                let dbError = conn.lastErrorMessage() ?? ""
                let result = SAConnectionResult(
                    connection: conn, sshTunnel: tunnel,
                    databaseSelectionFailed: true,
                    databaseSelectionError: dbError
                )
                DispatchQueue.main.async { completion(result) }
                return
            }

            switch info.timeZoneMode {
            case .useSystemTZ:
                conn.updateTimeZoneIdentifier(TimeZone.current.identifier)
            case .useFixedTZ:
                if !info.timeZoneIdentifier.isEmpty {
                    conn.updateTimeZoneIdentifier(info.timeZoneIdentifier)
                }
            case .useServerTZ:
                break
            @unknown default:
                break
            }

            let result = SAConnectionResult(connection: conn, sshTunnel: tunnel)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Private: SSH Tunnel

    private func establishSSHTunnel(
        info: SAConnectionInfoObjC,
        sshPassword: String,
        parentWindow: NSWindow?,
        completion: @escaping (SPSSHTunnel?, String?) -> Void
    ) {
        let sshPort = Int(info.sshPort) ?? 22
        let mysqlPort = Int(info.port) ?? 3306

        guard let tunnel = SPSSHTunnel(
            toHost: info.sshHost,
            port: sshPort,
            login: info.sshUser,
            tunnellingToPort: mysqlPort,
            onHost: info.host
        ) else {
            completion(nil, "Failed to create SSH tunnel")
            return
        }

        if let window = parentWindow {
            tunnel.setParentWindow(window)
        }

        if !info.connectionSSHKeychainItemName.isEmpty {
            tunnel.setPasswordKeychainName(info.connectionSSHKeychainItemName,
                                          account: info.connectionSSHKeychainItemAccount)
        } else {
            tunnel.setPassword(sshPassword)
        }

        if info.sshKeyLocationEnabled != 0 && !info.sshKeyLocation.isEmpty {
            tunnel.setKeyFilePath(info.sshKeyLocation)
        }

        tunnel.setConnectionStateChange(#selector(sshTunnelStateChanged(_:)),
                                       delegate: self)

        self.activeTunnel = tunnel
        self.sshTunnelCompletion = completion
        tunnel.connect()
    }

    @objc private func sshTunnelStateChanged(_ tunnel: SPSSHTunnel) {
        let state = tunnel.state()

        if state == SPMySQLProxyConnected {
            let completion = sshTunnelCompletion
            sshTunnelCompletion = nil
            completion?(tunnel, nil)
        } else if state == SPMySQLProxyLaunchFailed || state == SPMySQLProxyForwardingFailed {
            let error = tunnel.lastError() ?? "SSH tunnel failed"
            let completion = sshTunnelCompletion
            sshTunnelCompletion = nil
            tunnel.disconnect()
            completion?(nil, error)
        }
    }
}
