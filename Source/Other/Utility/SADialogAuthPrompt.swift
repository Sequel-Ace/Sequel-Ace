//
//  SADialogAuthPrompt.swift
//  Sequel Ace
//
//  Copyright © 2026 Sequel-Ace. All rights reserved.
//
//  More info at <https://github.com/Sequel-Ace/Sequel-Ace>
//

import AppKit

/// Answers the questions the bundled `dialog` client authentication plugin
/// asks on behalf of a server — MariaDB/MySQL PAM authentication and anything
/// else that drives a prompt over the auth protocol.
///
/// The plugin looks its asker up once, by symbol, with
/// `dlsym(RTLD_DEFAULT, "mysql_authentication_dialog_ask")`; when it finds
/// nothing it falls back to reading the answer from `stdin` with `fgets`,
/// which in a GUI app means the connection thread blocks forever.
/// `SADialogAuthPrompt+MySQL.swift` exports that symbol and calls in here.
///
/// `NSAlert` rather than SwiftUI: the plugin calls in from whatever thread is
/// connecting and needs an answer before it returns, and the alert may have to
/// run on top of the connection sheet that is already modal. A nested modal
/// session is the one presentation AppKit supports there.
enum SADialogAuthPrompt {

    /// The protocol's question types. The plugin passes the server's type byte
    /// straight through: 1 is an ordinary string, 2 is a password, which must
    /// not be echoed.
    static func isSecure(type: Int32) -> Bool {
        type == 2
    }

    /// The text the user is asked to answer.
    ///
    /// The server writes the question and it is shown as-is, so a server that
    /// sends nothing still gets a sentence the user can act on. A password
    /// asked over an unencrypted connection carries a warning: the dialog
    /// protocol sends every answer in clear text, and the client only
    /// *requires* TLS when SSL or the cleartext plugin was asked for
    /// (`SACleartextAuthPolicy`), so a server that picks `dialog` can reach
    /// this prompt on a plaintext connection.
    static func message(for prompt: String?, secure: Bool, isEncrypted: Bool) -> String {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let question = trimmed.isEmpty
            ? NSLocalizedString(
                "The server is asking for additional authentication.",
                comment: "dialog authentication prompt : fallback message when the server sends no prompt text"
            )
            : trimmed

        guard secure, !isEncrypted else {
            return question
        }
        return question + "\n\n" + NSLocalizedString(
            "This connection is not encrypted, so your answer will be sent to the server in clear text.",
            comment: "dialog authentication prompt : warning shown when a password is asked for over a plaintext connection"
        )
    }

    /// Copies `answer` onto the heap for the plugin, which sends it and then
    /// hands it to `free()`. Returning an allocation of our own rather than
    /// filling the plugin's 1 KB stack buffer keeps a long answer intact
    /// instead of silently truncating a secret.
    static func duplicate(_ answer: String) -> UnsafeMutablePointer<CChar>? {
        answer.withCString { strdup($0) }
    }

    /// Asks on the main thread and blocks the caller until the user answers.
    /// `nil` means the user cancelled; the plugin turns that into a failed
    /// authentication.
    static func ask(prompt: String?, secure: Bool, isEncrypted: Bool) -> String? {
        let message = message(for: prompt, secure: secure, isEncrypted: isEncrypted)
        let warning = secure && !isEncrypted
        if Thread.isMainThread {
            return present(message: message, secure: secure, warning: warning)
        }
        return DispatchQueue.main.sync {
            present(message: message, secure: secure, warning: warning)
        }
    }

    /// Runs the alert. `warning` only changes how loudly it is presented; the
    /// user still decides, because a server without TLS support is exactly the
    /// case this plugin was bundled for and refusing outright would leave it
    /// unusable there.
    private static func present(message: String, secure: Bool, warning: Bool) -> String? {
        assert(Thread.isMainThread)

        let alert = NSAlert()
        alert.alertStyle = warning ? .warning : .informational
        alert.messageText = NSLocalizedString(
            "Authentication Required",
            comment: "dialog authentication prompt : alert title"
        )
        alert.informativeText = message

        let field: NSTextField = secure ? NSSecureTextField() : NSTextField()
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field

        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))

        // The accessory view is only in the window once the alert has laid it
        // out, so first responder has to be set after that, not before.
        alert.layout()
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return field.stringValue
    }
}
