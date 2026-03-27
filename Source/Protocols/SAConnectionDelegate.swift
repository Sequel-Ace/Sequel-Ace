//
//  SAConnectionDelegate.swift
//  Sequel Ace
//
//  Created as part of the modernization effort.
//  Provides a richer connection lifecycle protocol than
//  the legacy SPConnectionControllerDelegateProtocol.
//

import Foundation

/// A protocol defining callbacks for connection lifecycle events.
///
/// This extends the existing `SPConnectionControllerDelegateProtocol` (which only has
/// `connectionControllerInitiatingConnection:` and `connectionControllerConnectAttemptFailed:`)
/// with structured callbacks that include the connection object and connection info,
/// enabling the connection controller to be decoupled from SPDatabaseDocument.
@objc protocol SAConnectionDelegate: AnyObject {

    /// Called when a connection has been successfully established.
    ///
    /// - Parameters:
    ///   - connection: The established MySQL connection.
    ///   - info: The connection parameters that were used.
    @objc func connectionDidEstablish(_ connection: SPMySQLConnection, info: SAConnectionInfoObjC)

    /// Called when a connection attempt has failed.
    ///
    /// - Parameters:
    ///   - error: A description of what went wrong.
    ///   - detail: Optional detailed error information.
    @objc func connectionDidFail(withError error: String, detail: String?)

    /// Called when an active connection has been disconnected.
    @objc optional func connectionDidDisconnect()
}
