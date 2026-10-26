//
//  SADialogAuthPrompt+MySQL.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import Foundation
import SPMySQL

/// The symbol the `dialog` client plugin looks for. Named for C, so it cannot
/// take the Swift function's name.
///
/// The contract is the plugin's: return either `buffer`, filled in, or an
/// allocation the plugin will `free()`, or `nil` to fail authentication.
/// `buffer` goes unused because the answer is returned on the heap instead.
///
/// This lives apart from `SADialogAuthPrompt` because it reaches the client
/// library through the framework, which the Unit Tests target does not link;
/// everything decidable without a live handle stays in the testable half.
@_cdecl("mysql_authentication_dialog_ask")
public func saMySQLAuthenticationDialogAsk(
    _ mysql: UnsafeMutableRawPointer?,
    _ type: Int32,
    _ prompt: UnsafePointer<CChar>?,
    _ buffer: UnsafeMutablePointer<CChar>?,
    _ bufferLength: Int32
) -> UnsafeMutablePointer<CChar>? {
    let question = prompt.map { String(cString: $0) }
    // The plugin always passes its handle; with none there is no way to tell
    // what the transport negotiated, so warn rather than imply encryption.
    let isEncrypted = mysql.map { SADialogAuthTransport.isEncrypted(handle: $0) } ?? false

    guard let answer = SADialogAuthPrompt.ask(
        prompt: question,
        secure: SADialogAuthPrompt.isSecure(type: type),
        isEncrypted: isEncrypted
    ) else {
        return nil
    }
    return SADialogAuthPrompt.duplicate(answer)
}
