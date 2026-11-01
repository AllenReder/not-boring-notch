//
//  LauncherSearchTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the sources
//  declared below. The Tests folder is not part of an Xcode target, so each runner is compiled on
//  its own.
//
// SOURCES: NotBoringNotch/components/Launcher/LauncherSearch.swift NotBoringNotch/components/Launcher/LauncherApps.swift NotBoringNotch/components/Launcher/LauncherRomanization.swift
//
//  Helper names are prefixed (`check*` for the assertions, `launcher*` for this runner's fixtures)
//  so they stay distinguishable from the helpers in the other standalone runners in this folder,
//  which are compiled separately but must not read as if they shared a scope.
//
//  Two things are worth testing without a Mac in front of you. The ranking bands decide which row
//  Return opens, so a tier leaking into another tier is a wrong app launched. And the scan decides
//  what exists at all, so a missed folder or a repeated bundle is a row the user cannot find.
//

import Foundation

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                              file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkTrue(_ condition: Bool, _ message: String = "",
               file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

func launcherApp(_ name: String) -> LauncherApp {
    LauncherApp(
        url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: nil)
}

@main
struct LauncherSearchTestsRunner {
    static func main() {
        testTiersRankInOrder()
        testCaseAccentsAndWidthDoNotHaveToBeTyped()
        testAnotherScriptIsFoundByItsLatinReading()
        testNoMatchAndEmptyQueryReturnNothing()
        testTieIsBrokenAlphabetically()
        testTheListStopsAtTheLimit()
        testScanReadsOneLevelAndSkipsDuplicates()
        testScanVisitsAFolderListedTwiceOnce()
        print("✅ launcher search tests passed")
    }

    /// The five ways a name can answer a query, strongest first. Each is a band of its own, so the
    /// list order never depends on how long a name happens to be.
    static func testTiersRankInOrder() {
        let apps = [
            launcherApp("Unsafaried"),           // substring: inside a name, mid-word
            launcherApp("Not Safari"),           // word start: inside a name, after a space
            launcherApp("Safari Extensions"),    // prefix
            launcherApp("Safari"),               // exact
        ]
        checkEqual(
            LauncherSearch.ranked(apps, query: "safari").map(\.name),
            ["Safari", "Safari Extensions", "Not Safari", "Unsafaried"],
            "exact, then prefix, then a word inside, then a stretch inside")

        // A scattered match still finds its app, below every contiguous one.
        let scattered = LauncherSearch.ranked(
            [launcherApp("Visual Studio Code"), launcherApp("Vscode Helper")], query: "vscode")
        checkEqual(scattered.map(\.name).first, "Vscode Helper",
                   "a contiguous prefix beats a scattered one")
        checkTrue(scattered.contains { $0.name == "Visual Studio Code" },
                  "the letters in order still match")
    }

    static func testCaseAccentsAndWidthDoNotHaveToBeTyped() {
        let apps = [launcherApp("Café"), launcherApp("Safari")]
        checkEqual(LauncherSearch.ranked(apps, query: "CAFE").map(\.name), ["Café"],
                   "a typed query finds the accented name")
        checkEqual(LauncherSearch.ranked(apps, query: "ＳＡＦＡＲＩ").map(\.name), ["Safari"],
                   "a full-width query finds the Latin name")
    }

    /// A name written in Chinese, Japanese or Korean is typed with Latin letters, so it has to be
    /// matched in the letters it is typed with — and a name that is already Latin still wins.
    static func testAnotherScriptIsFoundByItsLatinReading() {
        let apps = [launcherApp("微信"), launcherApp("Safari"), launcherApp("カレンダー")]
        checkEqual(LauncherSearch.ranked(apps, query: "wei").map(\.name), ["微信"],
                   "the reading's opening finds it")
        checkEqual(LauncherSearch.ranked(apps, query: "weixin").map(\.name), ["微信"],
                   "the reading run together finds it too")
        checkEqual(LauncherSearch.ranked(apps, query: "微信").map(\.name), ["微信"],
                   "and so does the name itself")
        checkEqual(LauncherSearch.ranked(apps, query: "karen").map(\.name), ["カレンダー"],
                   "kana reads as its own letters, not as Mandarin")

        // The reading is a fallback, never a better match than the name itself.
        let both = [launcherApp("微信"), launcherApp("Weixin")]
        checkEqual(LauncherSearch.ranked(both, query: "weixin").map(\.name),
                   ["Weixin", "微信"], "a Latin name outranks the reading of another script")
    }

    static func testNoMatchAndEmptyQueryReturnNothing() {
        checkEqual(LauncherSearch.ranked([launcherApp("Safari")], query: "zzz").count, 0,
                   "an unmatched query lists nothing")
        checkEqual(LauncherSearch.ranked([launcherApp("Safari")], query: "   ").count, 0,
                   "an empty query is the caller's to fill, not this one's")
    }

    static func testTieIsBrokenAlphabetically() {
        let ranked = LauncherSearch.ranked(
            [launcherApp("Tool B"), launcherApp("Tool A")], query: "tool").map(\.name)
        checkEqual(ranked, ["Tool A", "Tool B"], "equal scores keep Finder order")
    }

    static func testTheListStopsAtTheLimit() {
        let apps = (1...200).map { launcherApp("App \($0)") }
        checkEqual(LauncherSearch.ranked(apps, query: "app").count, LauncherSearch.limit,
                   "more matches than the list draws are cut, not rendered")
    }

    /// The folders a Mac keeps apps in, one level deep. Anything deeper is a bundle's innards or a
    /// place the Finder never shows an app, and a bundle listed twice is one row.
    static func testScanReadsOneLevelAndSkipsDuplicates() {
        let root = launcherFixture("scan")
        defer { try? FileManager.default.removeItem(at: root) }

        launcherMakeApp(root.appendingPathComponent("Alpha.app"), bundleID: "com.test.alpha")
        launcherMakeApp(
            root.appendingPathComponent("Utilities/Beta.app"), bundleID: "com.test.beta")
        launcherMakeApp(
            root.appendingPathComponent("Nested/Deeper/Gamma.app"), bundleID: "com.test.gamma")
        // The same bundle ID in a second copy: one row, and the first copy is the one kept.
        launcherMakeApp(root.appendingPathComponent("Copy/Alpha.app"), bundleID: "com.test.alpha")

        let scanned = LauncherAppScanner.scan([root.path])
        checkEqual(scanned.map(\.name), ["Alpha", "Beta"], "one level deep, each bundle once")
    }

    /// `/Applications/Utilities` is both inside a scope and a scope of its own, so a folder named
    /// twice must still be read once — the scan runs while the user is typing.
    static func testScanVisitsAFolderListedTwiceOnce() {
        let root = launcherFixture("twice")
        defer { try? FileManager.default.removeItem(at: root) }

        launcherMakeApp(root.appendingPathComponent("Alpha.app"), bundleID: "com.test.alpha")
        launcherMakeApp(
            root.appendingPathComponent("Utilities/Beta.app"), bundleID: "com.test.beta")

        let scanned = LauncherAppScanner.scan([
            root.path, root.appendingPathComponent("Utilities").path,
        ])
        checkEqual(scanned.map(\.name), ["Alpha", "Beta"], "a folder named twice is read once")
    }

    // MARK: - Fixtures

    private static func launcherFixture(_ name: String) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-tests-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A bundle is its Info.plist: the scan reads the identifier from it, so a fake one has to
    /// carry a real one.
    private static func launcherMakeApp(_ url: URL, bundleID: String) {
        let contents = url.appendingPathComponent("Contents")
        try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": url.deletingPathExtension().lastPathComponent,
            "CFBundlePackageType": "APPL",
        ]
        (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
    }
}
