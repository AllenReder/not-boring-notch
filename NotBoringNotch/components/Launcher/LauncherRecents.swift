//
//  LauncherRecents.swift
//  NotBoringNotch
//

import AppKit
import Combine
import Defaults

/// The applications the user switched to most recently, newest first.
///
/// Read from the system rather than learned here: an app opened from the Dock is as much
/// "recently used" as one opened from this launcher, and the notification that says so arrives
/// for both. The list is persisted because a menu bar app gets restarted, and a recents list that
/// emptied itself on every launch would not be one.
@MainActor
final class LauncherRecents: ObservableObject {
    static let shared = LauncherRecents()

    /// One screenful of the notch, so the list never pushes the apps below it out of reach.
    static let limit = 8

    /// Finder is always running and never what the user set out to launch, and we never list
    /// ourselves: taking focus for the search field is not a visit.
    private static let ignored: Set<String> = ["com.apple.finder"]

    @Published private(set) var bundleIDs: [String]

    private init() {
        bundleIDs = Defaults[.launcherRecents]
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            Task { @MainActor in self?.record(app) }
        }
    }

    /// Newest first, each app once. Pure, so the order is checkable without a running system.
    static func promoted(_ bundleIDs: [String], with bundleID: String, limit: Int) -> [String] {
        Array(([bundleID] + bundleIDs.filter { $0 != bundleID }).prefix(limit))
    }

    private func record(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular,
            let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier,
            !Self.ignored.contains(bundleID)
        else { return }

        let updated = Self.promoted(bundleIDs, with: bundleID, limit: Self.limit)
        guard updated != bundleIDs else { return }
        bundleIDs = updated
        Defaults[.launcherRecents] = updated
    }
}
