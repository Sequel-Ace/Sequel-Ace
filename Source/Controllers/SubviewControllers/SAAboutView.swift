//
//  SAAboutView.swift
//  Sequel Ace
//
//  Created as part of the XIB to SwiftUI migration.
//  Copyright © 2024-2026 Sequel-Ace. All rights reserved.
//

import SwiftUI

struct SAAboutView: View {
    @State private var showingLicense = false

    private let appName: String = {
        let bundle = Bundle.main
        return "Sequel Ace" + (bundle.isSnapshotBuild ? " Beta" : "")
    }()

    private let versionText: String = {
        let bundle = Bundle.main
        let buildLabel = bundle.isSnapshotBuild
            ? NSLocalizedString("Beta Build", comment: "beta build label")
            : NSLocalizedString("Build", comment: "build label")
        return "Version \(bundle.version ?? "")\n\(buildLabel) \(bundle.build ?? "")"
    }()

    private let credits: AttributedString = loadMarkdownResource("Credits")
    private let license: AttributedString = loadMarkdownResource("License")

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 150, height: 150)

                Text(appName)
                    .font(.system(size: 18))

                Text(versionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 4)

                Button("License") {
                    showingLicense = true
                }
                .controlSize(.large)
            }
            .frame(width: 170)
            .padding([.vertical, .leading], 20)

            ScrollView {
                Text(credits)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 320)
        .sheet(isPresented: $showingLicense) {
            SALicenseSheetView(license: license, isPresented: $showingLicense)
        }
    }

    private static func loadMarkdownResource(_ name: String) -> AttributedString {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8),
              let attrString = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else {
            return AttributedString("")
        }
        return attrString
    }
}

struct SALicenseSheetView: View {
    let license: AttributedString
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                Text(license)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button("OK") {
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
    }
}
