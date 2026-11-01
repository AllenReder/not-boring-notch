//
//  LauncherListTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the sources
//  declared below. The Tests folder is not part of an Xcode target, so each runner is compiled on
//  its own.
//
// SOURCES: NotBoringNotch/components/Launcher/LauncherList.swift NotBoringNotch/components/Launcher/LauncherApps.swift NotBoringNotch/components/Launcher/LauncherSearch.swift NotBoringNotch/components/Launcher/LauncherRomanization.swift
//
//  Helper names are prefixed (`check*` for the assertions, `launcher*` for this runner's fixtures)
//  so they stay distinguishable from the helpers in the other standalone runners in this folder,
//  which are compiled separately but must not read as if they shared a scope.
//
//  What is worth testing without a Mac in front of you is the list's shape, because three separate
//  things read it and a disagreement between them is visible only to the user: the rows that are
//  drawn, the index the selection counts with — which is the app Return opens — and the height the
//  tab asks the notch for, which decides whether the last row is on screen at all. The recents
//  order is here too, because it is what gets written to disk.
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
struct LauncherListTestsRunner {
    static let metrics = LauncherMetrics(rowHeight: 30)

    static func main() {
        testRecentsComeFirstAndAreNotRepeated()
        testAQueryHidesTheRecents()
        testTheSelectionCountsOverBothSections()
        testTheSelectionClamps()
        testAnEmptyListIsOneRowTall()
        testTheHeightCountsTheHeaderOnlyWhenTheRecentsAreShown()
        testTheRecentsOrder()
        print("✅ launcher list tests passed")
    }

    /// The list draws the recents first, newest first, and does not draw the same app twice: the
    /// rows below them are the apps the recents have not already covered.
    static func testRecentsComeFirstAndAreNotRepeated() {
        let apps = [launcherApp("Notes"), launcherApp("Mail"), launcherApp("Safari")]
        let recents = [launcherApp("Safari"), launcherApp("Mail")]

        let list = LauncherList(apps: apps, recents: recents, query: "", metrics: metrics)

        checkEqual(list.rows.map(\.app.name), ["Safari", "Mail", "Notes"],
                   "the recents lead, and the app they cover is not drawn again")
        checkEqual(list.recentRows.map(\.app.name), ["Safari", "Mail"], "the Recent section is those")
        checkEqual(list.otherRows.map(\.app.name), ["Notes"], "and the rest is the others")
    }

    /// A typed field answers the query and shows nothing else, so a recent that also matches is
    /// listed once, in the ranked position, rather than twice.
    static func testAQueryHidesTheRecents() {
        let apps = [launcherApp("Safari"), launcherApp("Mail"), launcherApp("Notes")]
        let list = LauncherList(
            apps: apps, recents: [launcherApp("Notes")], query: "no", metrics: metrics)

        checkEqual(list.recentRows.count, 0, "a query hides the recents")
        checkEqual(list.rows.map(\.app.name), ["Notes"], "and the list is the query's answer")
        checkEqual(list.typed, "no", "the query is carried for the empty-state line")
    }

    /// One index over both sections is what the arrow keys and the pointer share, so it has to be
    /// the index of the row as drawn.
    static func testTheSelectionCountsOverBothSections() {
        let apps = [launcherApp("Notes"), launcherApp("Mail"), launcherApp("Safari")]
        let list = LauncherList(
            apps: apps, recents: [launcherApp("Safari"), launcherApp("Mail")], query: "",
            metrics: metrics)

        checkEqual(list.rows.map(\.index), [0, 1, 2], "the rows are numbered as drawn")
        checkEqual(list.selected(0)?.app.name, "Safari", "the first row")
        checkEqual(list.selected(2)?.app.name, "Notes", "the last row")
    }

    /// The list can change under a selection the user already set, so a selection past the end has
    /// to land on a row that exists rather than open nothing.
    static func testTheSelectionClamps() {
        let apps = [launcherApp("Notes"), launcherApp("Mail")]
        let list = LauncherList(apps: apps, recents: [], query: "", metrics: metrics)

        checkEqual(list.selected(99)?.app.name, "Mail", "past the end lands on the last row")
        checkEqual(list.selected(-5)?.app.name, "Notes", "before the start lands on the first")
        checkTrue(list.selected(0) != nil, "and the first row is reachable")

        let empty = LauncherList(apps: [], recents: [], query: "", metrics: metrics)
        checkTrue(empty.selected(0) == nil, "nothing is selected in an empty list")
    }

    /// An empty list still draws its one line of explanation, so it asks for one row.
    static func testAnEmptyListIsOneRowTall() {
        let list = LauncherList(apps: [], recents: [], query: "", metrics: metrics)
        checkEqual(list.neededHeight, metrics.field + 2 * metrics.spacing + metrics.row,
                   "an empty list is one row tall")
    }

    /// The height is the field, the rows, and the Recent header only when there is one. A tab that
    /// asks for less than it draws has its last row clipped.
    static func testTheHeightCountsTheHeaderOnlyWhenTheRecentsAreShown() {
        let recents = [launcherApp("Safari"), launcherApp("Mail")]
        let apps = recents + [launcherApp("Notes")]

        let all = LauncherList(apps: apps, recents: recents, query: "", metrics: metrics)
        checkEqual(
            all.neededHeight,
            metrics.field + 2 * metrics.spacing + 3 * metrics.row + metrics.header
                + metrics.separator,
            "three rows under a Recent header")

        let searched = LauncherList(apps: apps, recents: recents, query: "o", metrics: metrics)
        checkEqual(
            searched.neededHeight,
            metrics.field + 2 * metrics.spacing + CGFloat(searched.rows.count) * metrics.row,
            "a query draws no Recent header, so it asks for no room for one")
    }

    /// The order that is written to disk: the app just switched to leads, it is not listed twice,
    /// and the list never grows past its cap.
    static func testTheRecentsOrder() {
        checkEqual(
            LauncherRecentsOrder.promoting(["a", "b", "c"], with: "b", limit: 3),
            ["b", "a", "c"], "an app already on the list moves to the front, once")
        checkEqual(
            LauncherRecentsOrder.promoting(["a", "b", "c"], with: "d", limit: 3),
            ["d", "a", "b"], "a new app joins the front and the oldest falls off")
        checkEqual(
            LauncherRecentsOrder.promoting([], with: "a", limit: 5), ["a"],
            "the first recent is the only recent")
    }
}
