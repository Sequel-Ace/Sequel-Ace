//
//  SAAboutView.swift
//  Sequel Ace
//
//  Created as part of the XIB to SwiftUI migration.
//  Copyright © 2024-2026 Sequel-Ace. All rights reserved.
//

import SwiftUI

struct SAAboutView: View {
    /// The Claude kit's colours, injected by `SAAboutWindowController`, which owns them (the sheet gets them again below).
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.text)

                Text(versionText)
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 4)

                HStack(spacing: 8) {
                    Button("License") {
                        showingLicense = true
                    }
                    .buttonStyle(SAClaudeSecondaryButtonStyle(size: .form))

                    Link("Privacy Policy", destination: SAAnalyticsConsentPolicy.privacyPolicyURL)
                        .font(.system(size: NSFont.systemFontSize))
                        .foregroundColor(palette.accent)
                        .fixedSize()
                }
            }
            .frame(width: 170)
            .padding([.vertical, .leading], 20)

            ScrollView {
                Text(credits.tintingLinks(with: palette.accent))
                    .font(.system(size: 12))
                    .foregroundColor(palette.secondary)
                    .tint(palette.accent)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 320)
        .background(palette.surface.ignoresSafeArea())
        .sheet(isPresented: $showingLicense) {
            SALicenseSheetView(license: license, isPresented: $showingLicense)
                .environmentObject(palette)
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

private extension AttributedString {
    /// The same text with every link run in `colour` (a link otherwise takes the system accent, not the Claude one).
    func tintingLinks(with colour: Color) -> AttributedString {
        var result = self
        for run in result.runs where run.link != nil {
            result[run.range].foregroundColor = colour
        }
        return result
    }
}

struct SALicenseSheetView: View {
    @EnvironmentObject private var palette: SAClaudeSwiftUIPalette
    let license: AttributedString
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                Text(license.tintingLinks(with: palette.accent))
                    .font(.system(size: 12))
                    .foregroundColor(palette.text)
                    .tint(palette.accent)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button("OK") {
                    isPresented = false
                }
                .buttonStyle(SAClaudePrimaryButtonStyle(size: .form))
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .background(palette.surface.ignoresSafeArea())
    }
}
