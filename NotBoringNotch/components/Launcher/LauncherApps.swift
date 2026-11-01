//
//  LauncherApps.swift
//  NotBoringNotch
//

import Foundation

/// One application the launcher can open.
struct LauncherApp: Identifiable, Hashable {
    let url: URL
    /// What Finder calls the bundle, so a renamed copy is found under the name the user sees.
    let name: String
    let bundleID: String?

    var id: String { url.path }

    /// What makes two rows the same app: the bundle identifier, or the path for a bundle that has
    /// none. One rule, because the scan, the recents and the list all have to agree on it.
    var identity: String { bundleID ?? id }
}

/// Finds the applications installed on this Mac.
///
/// The scopes are the folders macOS itself treats as app locations, and each is read one level
/// deep: `Utilities`, a vendor's own folder, and nothing further. Walking the whole tree would
/// spend seconds inside bundles whose contents the Finder never shows as an app.
enum LauncherAppScanner {
    static let defaultScopes = [
        "/Applications",
        "/System/Applications",
        "/System/Library/CoreServices/Applications",
        // Cryptex-delivered system apps; the /Applications Safari is a hidden symlink.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        "~/Applications",
    ]

    /// Every installed app, by name. Two copies of one app are one row, and the copy the scope
    /// order reaches first is the one kept.
    static func scan(_ scopes: [String] = defaultScopes) -> [LauncherApp] {
        var seen = Set<String>()
        var apps: [LauncherApp] = []

        for url in appBundles(in: scopes) {
            let app = LauncherApp(
                url: url, name: displayName(of: url),
                bundleID: Bundle(url: url)?.bundleIdentifier)
            guard seen.insert(app.identity).inserted else { continue }
            apps.append(app)
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The name Finder shows, without the extension.
    static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Every `.app` the scopes reach, in scope order.
    private static func appBundles(in scopes: [String]) -> [URL] {
        var visited = Set<String>()
        var result: [URL] = []
        for scope in scopes {
            let root = URL(fileURLWithPath: (scope as NSString).expandingTildeInPath)
            result += appBundles(under: root, depth: 1, visited: &visited)
        }
        return result
    }

    /// An `.app` is never descended into, so a bundle's own resources cost nothing. `visited`
    /// holds resolved paths, so a folder two scopes both reach — `/Applications` and
    /// `/Applications/Utilities` — is read once.
    private static func appBundles(
        under url: URL, depth: Int, visited: inout Set<String>
    ) -> [URL] {
        guard visited.insert(url.resolvingSymlinksInPath().path).inserted,
            let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

        var result: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                result.append(entry)
            } else if depth > 0 {
                result += appBundles(under: entry, depth: depth - 1, visited: &visited)
            }
        }
        return result
    }
}
