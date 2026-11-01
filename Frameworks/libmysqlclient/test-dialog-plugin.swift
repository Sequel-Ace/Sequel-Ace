// Exercises the actual dialog plugin binary through its public authentication ABI.
// Run with swiftc and the framework's MySQLClient module map (see README.md).
import Foundation
import MySQLClient

private enum SADialogPluginTest {
    static var encrypted = false
    static var packets: [[UInt8]?] = []
    static var packetIndex = 0
    static var packetBuffer: UnsafeMutablePointer<UInt8>?
    static var answer: String?
    static var prompts: [(Int32, String)] = []
    static var writes: [String] = []
    static let cipher = strdup("synthetic-test-cipher")!
}

// The old plugin uses this symbol to bypass the callback over TLS. Exporting a
// deterministic transport lets the same test exercise both paths without a server.
@_cdecl("mysql_get_ssl_cipher")
public func saTestSSLCipher(_ mysql: UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? {
    SADialogPluginTest.encrypted ? UnsafePointer(SADialogPluginTest.cipher) : nil
}

@_cdecl("mysql_authentication_dialog_ask")
public func saTestDialogAsk(
    _ mysql: UnsafeMutableRawPointer?, _ type: Int32,
    _ prompt: UnsafePointer<CChar>?, _ buffer: UnsafeMutablePointer<CChar>?, _ length: Int32
) -> UnsafeMutablePointer<CChar>? {
    SADialogPluginTest.prompts.append((type, prompt.map(String.init(cString:)) ?? ""))
    return SADialogPluginTest.answer.flatMap { strdup($0) }
}

let pluginPath = CommandLine.arguments[1]
guard let handle = dlopen(pluginPath, RTLD_NOW | RTLD_LOCAL) else {
    fatalError(String(cString: dlerror()))
}
defer { dlclose(handle) }
guard let declaration = dlsym(handle, "_mysql_client_plugin_declaration_") else {
    fatalError("Missing dialog plugin declaration")
}
let plugin = declaration.assumingMemoryBound(to: st_mysql_client_plugin_AUTHENTICATION.self)
precondition(plugin.pointee.type == MYSQL_CLIENT_AUTHENTICATION_PLUGIN)
precondition(String(cString: plugin.pointee.name) == "dialog")
let initialized = withVaList([]) { plugin.pointee.`init`?(nil, 0, 0, $0) }
precondition(initialized == 0, "Dialog initialization failed")

let scenarios: [(String, [[UInt8]?], Int32, String)] = [
    ("empty final password", [[5, 0]], 2, ""),
    ("empty nonfinal password", [[4, 0], [0]], 2, ""),
    ("change user", [nil, [0]], 2, ""),
    ("named password", [[5] + Array("Password:".utf8) + [0]], 2, "Password:"),
    ("ordinary question", [[3] + Array("Confirm:".utf8) + [0]], 1, "Confirm:")
]
var checks = 0
for encrypted in [false, true] {
    for (name, packets, type, prompt) in scenarios {
        for answer: String? in [nil, "explicit-test-answer", "", String(repeating: "pässwörd", count: 400)] {
            SADialogPluginTest.encrypted = encrypted
            SADialogPluginTest.packets = packets
            SADialogPluginTest.packetIndex = 0
            SADialogPluginTest.answer = answer
            SADialogPluginTest.prompts = []
            SADialogPluginTest.writes = []
            var mysql = MYSQL()
            mysql.passwd = strdup("synthetic-saved-password")
            defer { free(mysql.passwd) }
            var vio = MYSQL_PLUGIN_VIO()
            vio.read_packet = { _, destination in
                SADialogPluginTest.packetBuffer?.deallocate()
                SADialogPluginTest.packetBuffer = nil
                guard SADialogPluginTest.packetIndex < SADialogPluginTest.packets.count else { return -1 }
                let packet = SADialogPluginTest.packets[SADialogPluginTest.packetIndex]
                SADialogPluginTest.packetIndex += 1
                guard let packet else { destination?.pointee = nil; return 0 }
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: packet.count)
                buffer.initialize(from: packet, count: packet.count)
                SADialogPluginTest.packetBuffer = buffer
                destination?.pointee = buffer
                return Int32(packet.count)
            }
            vio.write_packet = { _, bytes, length in
                guard let bytes, length > 0, bytes[Int(length) - 1] == 0 else { return 1 }
                SADialogPluginTest.writes.append(String(decoding: UnsafeBufferPointer(start: bytes, count: Int(length) - 1), as: UTF8.self))
                return 0
            }
            let result = plugin.pointee.authenticate_user?(&vio, &mysql)
            let label = "\(name), TLS=\(encrypted), accepted=\(answer != nil)"
            precondition(SADialogPluginTest.prompts.count == 1, "No consent callback: \(label)")
            precondition(SADialogPluginTest.prompts[0].0 == type && SADialogPluginTest.prompts[0].1 == prompt, "Wrong prompt: \(label)")
            precondition(SADialogPluginTest.writes == answer.map { [$0] } ?? [], "Unexpected password transmission: \(label)")
            precondition(answer == nil ? result == CR_ERROR : (result == CR_OK || result == CR_OK_HANDSHAKE_COMPLETE), "Wrong auth outcome: \(label)")
            checks += 1
        }
    }
}
SADialogPluginTest.packetBuffer?.deallocate()
free(SADialogPluginTest.cipher)
print("Passed \(checks) dialog plugin consent cases")
