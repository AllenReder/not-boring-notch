//
//  LauncherList.swift
//  NotBoringNotch
//

import Foundation

/// What each piece of the launcher occupies. Everything is drawn at these heights rather than
/// letting its text decide, so the height this tab asks the notch for is the height its layout
/// takes — a list the notch clips is a selection the user cannot see.
///
/// The row is the one the user sets, and the icon, the name and the row's corner are fractions of
/// it: a taller row is a bigger icon and a bigger name, not the same row with more padding. What
/// sits around the rows does not scale with them, because the field and the headers are the notch's
/// furniture and the list is what the setting is about.
struct LauncherMetrics {
    /// The row height the fractions below were read against: at 30, an icon is 22 and a name is 13.
    private static let reference: CGFloat = 30

    let rowHeight: CGFloat

    var row: CGFloat { rowHeight }
    var icon: CGFloat { (rowHeight * 22 / Self.reference).rounded() }
    var name: CGFloat { (rowHeight * 13 / Self.reference).rounded() }
    var corner: CGFloat { (rowHeight * 6 / Self.reference).rounded() }

    let field: CGFloat = 32
    let header: CGFloat = 26
    let separator: CGFloat = 13
    /// Between the field and the list, and below the last row.
    let spacing: CGFloat = 8
}

/// What the launcher is showing: the recent apps, then everything else, in the order the list draws
/// them.
///
/// Built once per pass, because ranking every installed app is the expensive part of a keystroke.
/// It answers the three questions the view has about the list — which rows exist, which one the
/// selection is on, and how tall the list has to be — so none of them can disagree with the rows
/// that are actually drawn.
struct LauncherList {
    /// One row: the app, and the index the selection counts with.
    struct Row: Identifiable {
        let index: Int
        let app: LauncherApp
        var id: String { app.id }
    }

    /// The query with the whitespace a paste can carry dropped.
    let typed: String
    let recentRows: [Row]
    let otherRows: [Row]
    /// Every row, in drawing order, so the selection is one index over both sections.
    let rows: [Row]
    let metrics: LauncherMetrics

    init(apps: [LauncherApp], recents: [LauncherApp], query: String, metrics: LauncherMetrics) {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // The recents answer an empty field, and only an empty field: once something is typed,
        // the list answers the query and shows nothing else.
        let shown: [LauncherApp]
        if typed.isEmpty {
            let shownIDs = Set(recents.map(\.identity))
            shown = recents + apps.filter { !shownIDs.contains($0.identity) }
        } else {
            shown = LauncherSearch.ranked(apps, query: typed)
        }

        let rows = shown.enumerated().map { Row(index: $0.offset, app: $0.element) }
        let recentCount = typed.isEmpty ? recents.count : 0

        self.typed = typed
        self.metrics = metrics
        self.rows = rows
        self.recentRows = Array(rows.prefix(recentCount))
        self.otherRows = Array(rows.dropFirst(recentCount))
    }

    var isEmpty: Bool { rows.isEmpty }

    /// The row the selection lands on, clamped: the list can change under a selection the user
    /// already set.
    func selected(_ index: Int) -> Row? {
        rows.isEmpty ? nil : rows[min(max(index, 0), rows.count - 1)]
    }

    /// What this tab's content has to be to show those rows and nothing that sits empty. The notch
    /// adds its own header and padding around it. An empty list is one row tall, because the line
    /// it draws instead of rows is drawn at that height.
    var neededHeight: CGFloat {
        let list =
            rows.isEmpty
            ? metrics.row
            : CGFloat(rows.count) * metrics.row
                + (recentRows.isEmpty ? 0 : metrics.header + metrics.separator)
        return metrics.field + 2 * metrics.spacing + list
    }
}

/// The recents list's one rule: newest first, each app once, never longer than the cap.
///
/// Pure, and here rather than beside the system notification that feeds it, so the order that gets
/// persisted is checkable without a running Mac.
enum LauncherRecentsOrder {
    static func promoting(_ bundleIDs: [String], with bundleID: String, limit: Int) -> [String] {
        Array(([bundleID] + bundleIDs.filter { $0 != bundleID }).prefix(limit))
    }
}
