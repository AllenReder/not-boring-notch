// The launcher lists every app installed on the Mac that records the film. The studio shows it a
// curated shelf instead: symlinks, in a scratch `~/Applications`, to the few apps the film names.
//
// The launcher's scanner reads fixed folders, so the studio swaps `contentsOfDirectory` for the
// scanner's own scopes: `/Applications` answers with the curated links, and the system scopes
// answer with nothing. Everything else reads as usual.

import AppKit

@MainActor enum StageApps {
    /// Bundle IDs of the apps the launcher may show: the recents, and one more that matches `te`.
    static let bundleIDs = Seams.launcherRecents + ["com.apple.Terminal"]

    private static let emptyScopes: Set<String> = [
        "/System/Applications",
        "/System/Library/CoreServices/Applications",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
    ]

    /// Written once in `install`, before the launcher's scanner first runs.
    nonisolated(unsafe) private static var curated: [URL] = []

    static func install() {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("StageApplications", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        curated = bundleIDs.compactMap { id in
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let link = dir.appendingPathComponent(app.lastPathComponent)
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
            return link
        }
        let original = class_getInstanceMethod(FileManager.self, #selector(FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)))!
        let swapped = class_getInstanceMethod(FileManager.self, #selector(FileManager.stage_contentsOfDirectory(at:includingPropertiesForKeys:options:)))!
        method_exchangeImplementations(original, swapped)
    }

    nonisolated static func answer(for url: URL) -> [URL]? {
        if url.path == "/Applications" { return curated }
        if emptyScopes.contains(url.path) { return [] }
        return nil
    }
}

extension FileManager {
    @objc func stage_contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: DirectoryEnumerationOptions) throws -> [URL] {
        if let answer = StageApps.answer(for: url) { return answer }
        // Swapped: this calls the original.
        return try stage_contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
    }
}
