//
//  SAClaudeThemeRefresher.swift
//  Sequel Ace
//
//  Keeps the installed copies of the bundled Claude editor themes current.
//  The app's theme installer never overwrites an existing file, so an updated
//  bundled theme would otherwise never reach an existing install. Pure
//  Foundation, shared with the Unit Tests target.
//

import Foundation

@objc final class SAClaudeThemeRefresher: NSObject {

    static let themeNames = ["Claude Dark", "Claude Light"]

    /// Overwrites installed copies of the bundled Claude themes whose contents differ, and reloads
    /// the editor colours when the refreshed theme is the current one. Returns the refreshed names.
    @discardableResult
    @objc(refreshInstalledThemesFromDirectory:toDirectory:defaults:)
    static func refreshInstalledThemes(from bundledDirectory: String, to installedDirectory: String, defaults: UserDefaults) -> [String] {
        let fileManager = FileManager.default
        var refreshed: [String] = []
        for name in themeNames {
            let bundledPath = (bundledDirectory as NSString).appendingPathComponent(name + ".spTheme")
            let installedPath = (installedDirectory as NSString).appendingPathComponent(name + ".spTheme")
            // A missing installed copy is the installer's job, not ours.
            guard fileManager.fileExists(atPath: installedPath),
                  let bundledData = try? Data(contentsOf: URL(fileURLWithPath: bundledPath), options: .uncached),
                  let installedData = try? Data(contentsOf: URL(fileURLWithPath: installedPath), options: .uncached),
                  bundledData != installedData else { continue }
            do {
                try bundledData.write(to: URL(fileURLWithPath: installedPath), options: .atomic)
            } catch {
                continue
            }
            refreshed.append(name)
            // The appearance switcher won't reload a theme whose name is already current.
            if let current = defaults.string(forKey: SAEditorThemeLoader.themeNameKey),
               current.caseInsensitiveCompare(name) == .orderedSame {
                SAEditorThemeLoader.loadTheme(atPath: installedPath, into: defaults)
            }
        }
        return refreshed
    }
}
