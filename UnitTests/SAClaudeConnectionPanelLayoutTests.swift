//
//  SAClaudeConnectionPanelLayoutTests.swift
//  Unit Tests
//

import AppKit
import XCTest

final class SAClaudeConnectionPanelLayoutTests: XCTestCase {
    private typealias L = SAClaudeConnectionPanelLayout
    private typealias Spec = SAClaudeConnectionRowSpec

    // MARK: Classification

    func testClassificationTable() {
        typealias S = SAClaudeConnectionSection
        let table: [(SAClaudeConnectionType, [String: (S, Int)])] = [
            (.tcpip, ["host": (.server, 0), "port": (.server, 1), "database": (.server, 2),
                      "user": (.signIn, 0), "password": (.signIn, 1),
                      "enableClearTextPlugin": (.advanced, 4), "useSSL": (.advanced, 5), "requestServerPublicKey": (.advanced, 5),
                      "sslKeyFileLocation": (.advanced, 6), "sslCertificateFileLocation": (.advanced, 7), "sslCACertFileLocation": (.advanced, 8)]),
            (.socket, ["socket": (.server, 0), "database": (.server, 1),
                       "user": (.signIn, 0), "password": (.signIn, 1),
                       "enableClearTextPlugin": (.advanced, 4), "useSSL": (.advanced, 5),
                       "sslKeyFileLocation": (.advanced, 6), "sslCertificateFileLocation": (.advanced, 7), "sslCACertFileLocation": (.advanced, 8)]),
            (.ssh, ["host": (.server, 0), "port": (.server, 1), "database": (.server, 2), "sshRemoteSocketPath": (.server, 3),
                    "user": (.signIn, 0), "password": (.signIn, 1),
                    "sshHost": (.sshTunnel, 0), "sshUser": (.sshTunnel, 1), "sshPassword": (.sshTunnel, 2),
                    "sshKeyLocation": (.sshTunnel, 2), "sshPort": (.sshTunnel, 3),
                    "enableClearTextPlugin": (.advanced, 4), "useSSL": (.advanced, 5),
                    "sslKeyFileLocation": (.advanced, 6), "sslCertificateFileLocation": (.advanced, 7), "sslCACertFileLocation": (.advanced, 8)]),
            (.awsIAM, ["host": (.server, 0), "port": (.server, 1), "database": (.server, 2),
                       "user": (.signIn, 0), "password": (.signIn, 1), "awsProfile": (.signIn, 2), "awsRegion": (.signIn, 3),
                       "awsSSLNote": (.advanced, 6)]),
            (.vault, ["host": (.server, 0), "port": (.server, 1), "database": (.server, 2),
                      "vaultHost": (.vault, 0), "vaultMount": (.vault, 1), "vaultCredentialsRole": (.vault, 2),
                      "vaultPort": (.vault, 3), "vaultOIDCMount": (.vault, 4),
                      "enableClearTextPlugin": (.advanced, 4), "useSSL": (.advanced, 5),
                      "sslKeyFileLocation": (.advanced, 6), "sslCertificateFileLocation": (.advanced, 7), "sslCACertFileLocation": (.advanced, 8)]),
        ]
        for (type, expected) in table {
            for (key, want) in expected {
                let got = SAClaudeConnectionClassifier.placement(keyPath: key, type: type)
                XCTAssertEqual(got?.section, want.0, "\(key) on \(type)")
                XCTAssertEqual(got?.order, want.1, "\(key) on \(type)")
            }
            // Advanced fields present on every type.
            for (key, order) in [("name", 0), ("colour", 1), ("timeZone", 2), ("allowDataLocalInfile", 3)] {
                let got = SAClaudeConnectionClassifier.placement(keyPath: key, type: type)
                XCTAssertEqual(got?.section, .advanced, "\(key) on \(type)")
                XCTAssertEqual(got?.order, order, "\(key) on \(type)")
            }
        }
    }

    func testClassificationAbsentAndUnknown() {
        XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "host", type: .socket))
        XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "socket", type: .tcpip))
        XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "user", type: .vault))
        XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "useSSL", type: .awsIAM))
        XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "enableClearTextPlugin", type: .awsIAM))
        XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "awsProfile", type: .tcpip))
        for type in [SAClaudeConnectionType.tcpip, .socket, .ssh, .awsIAM, .vault] {
            XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "somethingNew", type: type))
            XCTAssertNil(SAClaudeConnectionClassifier.placement(keyPath: "sshKeyLocationEnabled", type: type))
        }
    }

    func testRequiredKeyPathsArePlaceableForEveryType() {
        let tcpip = SAClaudeConnectionClassifier.requiredKeyPaths(for: .tcpip)
        XCTAssertTrue(tcpip.isSuperset(of: ["host", "port", "database", "user", "password", "name", "allowDataLocalInfile", "useSSL"]))
        for type in [SAClaudeConnectionType.tcpip, .socket, .ssh, .awsIAM, .vault] {
            for key in SAClaudeConnectionClassifier.requiredKeyPaths(for: type) {
                XCTAssertNotNil(SAClaudeConnectionClassifier.placement(keyPath: key, type: type), "\(key) on \(type)")
            }
        }
        XCTAssertFalse(SAClaudeConnectionClassifier.requiredKeyPaths(for: .socket).contains("host"))
        XCTAssertTrue(SAClaudeConnectionClassifier.requiredKeyPaths(for: .socket).contains("socket"))
        XCTAssertTrue(SAClaudeConnectionClassifier.requiredKeyPaths(for: .vault).contains("vaultOIDCMount"))
        XCTAssertTrue(SAClaudeConnectionClassifier.requiredKeyPaths(for: .awsIAM).contains("awsRegion"))
    }

    // MARK: Layout helpers

    private func field(_ id: String, _ section: SAClaudeConnectionSection) -> Spec {
        Spec(id: id, label: id, kind: .field, section: section)
    }

    private var tcpipRows: [Spec] {
        [field("host", .server), field("port", .server), field("database", .server),
         field("user", .signIn), field("password", .signIn)]
    }

    private var advancedRows: [Spec] {
        [field("name", .advanced),
         Spec(id: "colour", label: "Colour", kind: .colour, section: .advanced),
         Spec(id: "timeZone", label: "Time zone", kind: .field, section: .advanced),
         Spec(id: "allowDataLocalInfile", label: nil, kind: .checkbox, section: .advanced),
         Spec(id: "enableClearTextPlugin", label: nil, kind: .checkbox, section: .advanced),
         Spec(id: "useSSL", label: nil, kind: .checkboxPair, section: .advanced)]
    }

    private var sslFileRows: [Spec] {
        ["sslKeyFileLocation", "sslCertificateFileLocation", "sslCACertFileLocation"].map {
            Spec(id: $0, label: $0, kind: .fileRow, section: .advanced)
        }
    }

    private func row(_ f: L.Frames, _ id: String) -> L.RowFrame {
        guard let found = f.rows.first(where: { $0.id == id }) else {
            XCTFail("missing row \(id)")
            return L.RowFrame(id: id, label: nil, control: .zero)
        }
        return found
    }

    /// Top-down y of a rect's top edge.
    private func top(_ r: NSRect, in f: L.Frames) -> CGFloat { f.height - r.maxY }

    // MARK: Layout

    func testTCPIPClosedAtWidth760() {
        let f = L.frames(type: .tcpip, rows: tcpipRows, width: 760, advancedOpen: false, tabsWidth: 200)
        XCTAssertEqual(f.height, 272)
        XCTAssertEqual(row(f, "host").label?.minX, 16)
        XCTAssertEqual(row(f, "user").label?.minX, 392)
        XCTAssertEqual(row(f, "host").control.minX, 128)
        XCTAssertEqual(row(f, "host").control.width, 352 - 104 - 8)
        XCTAssertEqual(row(f, "user").control.minX, 392 + 112)

        // Header row: 32 tall at the top, tabs right-aligned.
        XCTAssertEqual(f.header, NSRect(x: 16, y: 272 - 16 - 32, width: 728 - 200, height: 32))
        XCTAssertEqual(f.tabs, NSRect(x: 760 - 16 - 200, y: 272 - 16 - 32, width: 200, height: 32))

        // Server title sits above the host row; both columns start at the same y.
        let serverTitle = f.sectionTitles[.server]!
        XCTAssertEqual(top(serverTitle, in: f), 16 + 32 + 12)
        XCTAssertEqual(top(row(f, "host").control, in: f), top(serverTitle, in: f) + 18)
        XCTAssertEqual(top(row(f, "user").control, in: f), top(row(f, "host").control, in: f))
        XCTAssertEqual(top(f.sectionTitles[.signIn]!, in: f), top(serverTitle, in: f))
        XCTAssertEqual(top(row(f, "port").control, in: f), top(row(f, "host").control, in: f) + 32)
        XCTAssertEqual(top(row(f, "password").control, in: f), top(row(f, "user").control, in: f) + 32)

        // Disclosure after the taller (left) column + section gap; action row at the bottom.
        XCTAssertEqual(f.disclosure, NSRect(x: 16, y: 272 - (16 + 32 + 12 + 114 + 10 + 28), width: 728, height: 28))
        XCTAssertEqual(f.actionRow, NSRect(x: 16, y: 16, width: 728, height: 32))
        XCTAssertNil(f.sectionTitles[.advanced])
        XCTAssertEqual(f.rows.count, 5)
    }

    func testAdvancedOpenAddsThreeRowsInTwoColumns() {
        let f = L.frames(type: .tcpip, rows: tcpipRows + advancedRows, width: 760, advancedOpen: true, tabsWidth: 200)
        XCTAssertEqual(f.height, 378)
        // Alternating left / right in order.
        XCTAssertEqual(row(f, "name").label?.minX, 16)
        XCTAssertEqual(row(f, "colour").label?.minX, 392)
        XCTAssertEqual(row(f, "timeZone").label?.minX, 16)
        XCTAssertEqual(top(row(f, "name").control, in: f), top(row(f, "colour").control, in: f))
        XCTAssertEqual(top(row(f, "timeZone").control, in: f), top(row(f, "name").control, in: f) + 32)
        // Advanced rows start sectionGap below the disclosure.
        XCTAssertEqual(top(row(f, "name").control, in: f), top(f.disclosure, in: f) + 28 + 10)
        // Checkbox rows have no label rect; their control starts after the label column.
        XCTAssertNil(row(f, "allowDataLocalInfile").label)
        XCTAssertNil(row(f, "useSSL").label)
        XCTAssertEqual(row(f, "allowDataLocalInfile").control.minX, 392 + 104 + 8)
        XCTAssertEqual(row(f, "enableClearTextPlugin").control.minX, 16 + 104 + 8)
    }

    func testClosedAdvancedRowsAreNotLaidOut() {
        let f = L.frames(type: .tcpip, rows: tcpipRows + advancedRows, width: 760, advancedOpen: false, tabsWidth: 200)
        XCTAssertEqual(f.height, 272)
        XCTAssertEqual(f.rows.count, 5)
    }

    func testSSLOnAddsThreeFileRows() {
        let off = L.frames(type: .tcpip, rows: tcpipRows + advancedRows, width: 760, advancedOpen: true, tabsWidth: 200)
        let on = L.frames(type: .tcpip, rows: tcpipRows + advancedRows + sslFileRows, width: 760, advancedOpen: true, tabsWidth: 200)
        XCTAssertEqual(on.height - off.height, 64)   // 6 rows -> 3 lines, 9 rows -> 5 lines
        XCTAssertEqual(on.height, 378 + 64)
        XCTAssertEqual(row(on, "sslKeyFileLocation").label?.minX, 16)   // advanced index 6 -> left
        XCTAssertEqual(row(on, "sslCertificateFileLocation").label?.minX, 392)
    }

    func testSSHColumns() {
        let rows = [field("host", .server), field("port", .server), field("database", .server), field("sshRemoteSocketPath", .server),
                    field("user", .signIn), field("password", .signIn),
                    field("sshHost", .sshTunnel), field("sshUser", .sshTunnel), field("sshPassword", .sshTunnel), field("sshPort", .sshTunnel)]
        let f = L.frames(type: .ssh, rows: rows, width: 760, advancedOpen: false, tabsWidth: 200)
        // Left: 18 + 4*32 + 10 + 18 + 2*32 = 238; right: 18 + 4*32 = 146.
        XCTAssertEqual(f.height, 16 + 32 + 12 + 238 + 10 + 28 + 12 + 32 + 16)
        XCTAssertEqual(row(f, "sshHost").label?.minX, 392)
        XCTAssertEqual(row(f, "user").label?.minX, 16)
        XCTAssertEqual(top(f.sectionTitles[.signIn]!, in: f), top(f.sectionTitles[.server]!, in: f) + 18 + 4 * 32 + 10)
        XCTAssertEqual(top(f.sectionTitles[.sshTunnel]!, in: f), top(f.sectionTitles[.server]!, in: f))
        XCTAssertNil(f.sectionTitles[.vault])
    }

    func testAWSAuthorisedVersusNot() {
        let base = [field("host", .server), field("port", .server), field("database", .server),
                    field("user", .signIn), field("password", .signIn)]
        let authorised = base + [field("awsProfile", .signIn),
                                 Spec(id: "awsRegion", label: "Region", kind: .comboWithButton, section: .signIn)]
        let notAuthorised = base + [Spec(id: "awsAuthorise", label: nil, kind: .button, section: .signIn),
                                    Spec(id: "awsNote", label: nil, kind: .note(height: 30), section: .signIn)]
        let a = L.frames(type: .awsIAM, rows: authorised, width: 760, advancedOpen: false, tabsWidth: 200)
        let n = L.frames(type: .awsIAM, rows: notAuthorised, width: 760, advancedOpen: false, tabsWidth: 200)
        // Right column: 18 + 4*32 = 146 vs 18 + 3*32 + 30 = 144; left is 114, so the right column drives both.
        XCTAssertEqual(a.height, 16 + 32 + 12 + 146 + 10 + 28 + 12 + 32 + 16)
        XCTAssertEqual(n.height, a.height - 2)
        XCTAssertNil(row(n, "awsNote").label)
        XCTAssertEqual(row(n, "awsNote").control.height, 30)
        XCTAssertEqual(row(n, "awsNote").control.minX, 392 + 112)
    }

    func testOneColumnBelow620() {
        let rows = tcpipRows + advancedRows
        let f = L.frames(type: .tcpip, rows: rows, width: 600, advancedOpen: true, tabsWidth: 200)
        for r in f.rows {
            XCTAssertEqual(r.control.minX, 16 + 104 + 8, r.id)
            XCTAssertEqual(r.control.width, 600 - 32 - 104 - 8, r.id)
        }
        // Server then signIn stacked; advanced rows each on their own line.
        let serverTop = top(f.sectionTitles[.server]!, in: f)
        XCTAssertEqual(top(f.sectionTitles[.signIn]!, in: f), serverTop + 18 + 3 * 32 + 10)
        let stacked = 16 + 32 + 12 + (18 + 96) + 10 + (18 + 64) + 10 + 28 + 10 + 6 * 32 + 12 + 32 + 16
        XCTAssertEqual(f.height, CGFloat(stacked))
        XCTAssertEqual(f.tabs.maxX, 600 - 16)
        let boundary = L.frames(type: .tcpip, rows: tcpipRows, width: 620, advancedOpen: false, tabsWidth: 200)
        XCTAssertEqual(row(boundary, "user").label?.minX, 16 + (620 - 32 - 24) / 2 + 24)
    }

    func testHeightForKind() {
        XCTAssertEqual(L.height(for: .field), 32)
        XCTAssertEqual(L.height(for: .checkbox), 32)
        XCTAssertEqual(L.height(for: .checkboxPair), 32)
        XCTAssertEqual(L.height(for: .colour), 32)
        XCTAssertEqual(L.height(for: .button), 32)
        XCTAssertEqual(L.height(for: .fileRow), 32)
        XCTAssertEqual(L.height(for: .comboWithButton), 32)
        XCTAssertEqual(L.height(for: .note(height: 30)), 30)
    }

    // MARK: Advanced predicate

    private func state(useSSL: Bool = false, local: Bool = false, clearText: Bool = false, publicKey: Bool = false,
                       serverTZ: Bool = true, files: [String?] = [nil, nil, nil]) -> SAClaudeConnectionAdvancedState {
        SAClaudeConnectionAdvancedState(useSSL: useSSL, allowDataLocalInfile: local, enableClearTextPlugin: clearText,
                                        requestServerPublicKey: publicKey, timeZoneIsServerDefault: serverTZ, sslFiles: files)
    }

    func testHasNonDefault() {
        XCTAssertFalse(SAClaudeConnectionAdvanced.hasNonDefault(state()))
        XCTAssertFalse(SAClaudeConnectionAdvanced.hasNonDefault(state(files: ["", nil, ""])))
        XCTAssertTrue(SAClaudeConnectionAdvanced.hasNonDefault(state(useSSL: true)))
        XCTAssertTrue(SAClaudeConnectionAdvanced.hasNonDefault(state(local: true)))
        XCTAssertTrue(SAClaudeConnectionAdvanced.hasNonDefault(state(clearText: true)))
        XCTAssertTrue(SAClaudeConnectionAdvanced.hasNonDefault(state(publicKey: true)))
        XCTAssertTrue(SAClaudeConnectionAdvanced.hasNonDefault(state(serverTZ: false)))
        XCTAssertTrue(SAClaudeConnectionAdvanced.hasNonDefault(state(files: [nil, "/tmp/ca.pem", nil])))
    }

    // MARK: Subtitle

    func testSubtitle() {
        typealias S = SAClaudeConnectionSummary
        XCTAssertEqual(S.subtitle(type: .tcpip, host: "127.0.0.1", port: "3307", socket: "", sshHost: ""), "MySQL · 127.0.0.1:3307")
        XCTAssertEqual(S.subtitle(type: .tcpip, host: "127.0.0.1", port: "", socket: "", sshHost: ""), "MySQL · 127.0.0.1:3306")
        XCTAssertEqual(S.subtitle(type: .tcpip, host: "", port: "", socket: "", sshHost: ""), "MySQL · localhost:3306")
        XCTAssertEqual(S.subtitle(type: .awsIAM, host: "db.aws", port: "3306", socket: "", sshHost: ""), "MySQL · db.aws:3306")
        XCTAssertEqual(S.subtitle(type: .vault, host: "db", port: "", socket: "", sshHost: ""), "MySQL · db:3306")
        XCTAssertEqual(S.subtitle(type: .socket, host: "", port: "", socket: "/tmp/mysql.sock", sshHost: ""), "Socket · /tmp/mysql.sock")
        XCTAssertEqual(S.subtitle(type: .socket, host: "", port: "", socket: "", sshHost: ""), "Socket · default")
        XCTAssertEqual(S.subtitle(type: .ssh, host: "127.0.0.1", port: "3307", socket: "", sshHost: "bastion"), "SSH · 127.0.0.1:3307 via bastion")
        XCTAssertEqual(S.subtitle(type: .ssh, host: "127.0.0.1", port: "3307", socket: "", sshHost: ""), "SSH · 127.0.0.1:3307")
    }
}
