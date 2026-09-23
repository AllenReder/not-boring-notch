//
//  ShelfStorage.swift
//  NotBoringNotch
//
//  Where the file shelf keeps what has been staged on it.
//
//  This app used to be called boringNotch, and the shelf wrote to
//  Application Support/boringNotch/Shelf. The sources and targets were renamed; the directory on
//  disk was not moved with them, and moving it without looking first would strand whatever
//  somebody had already staged there.
//
//  So the old directory is adopted — but as a migration, run once at launch, and not as a side
//  effect of the first view that happens to ask where the shelf lives. The distinction is the
//  whole point of this file: a migration that runs when a view appears is one nobody can observe,
//  that may never run at all, and that fails where no one will look. Resolution below therefore
//  moves nothing, and adoption below says out loud what it did or why it could not.
//

import Foundation

enum ShelfStorage {

    /// The name the shelf wrote to before the app was renamed. On the machine of anybody who used
    /// one of those builds this directory still exists, and still holds their items.
    static let legacyDirectoryName = "boringNotch"

    /// The name it writes to now.
    static let directoryName = "NotBoringNotch"

    // MARK: - The migration

    /// Moves the shelf out of the name the old build wrote, once. Call it at launch.
    ///
    /// Idempotent, and quiet when there is nothing to do. A failure is logged rather than
    /// swallowed: the shelf keeps working from where it is (see `directory`), so nobody is
    /// blocked by it, which is exactly why silence would leave it undiscovered.
    static func adoptLegacyDirectory(fileManager: FileManager = .default) {
        adoptLegacyDirectory(applicationSupport: applicationSupportDirectory(fileManager),
                             fileManager: fileManager)
    }

    /// The same migration, told where to look, so that a test can run it against a fixture.
    static func adoptLegacyDirectory(applicationSupport: URL, fileManager: FileManager = .default) {
        let current = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path) else { return }

        do {
            try fileManager.moveItem(at: legacy, to: current)
            print("🔄 Shelf moved from \(legacyDirectoryName) to \(directoryName)")
        } catch {
            // The shelf keeps working from where it is, so this does not block anybody — which is
            // exactly why it has to be said out loud rather than swallowed.
            print("⚠️ Could not move the shelf out of \(legacy.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Where the shelf is

    /// The directory the shelf's items live in. Moves nothing.
    ///
    /// Prefers the name this app writes to, and reads the legacy one if the shelf is still there —
    /// because adoption has not run yet, or because it could not. Falling back rather than
    /// resolving to an empty directory is what keeps a failed migration from looking like an empty
    /// shelf.
    static func directory(
        applicationSupport: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let current = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        let base = (!fileManager.fileExists(atPath: current.path)
                    && fileManager.fileExists(atPath: legacy.path)) ? legacy : current
        return base.appendingPathComponent("Shelf", isDirectory: true)
    }

    /// The file the shelf's items are persisted to. Moves nothing.
    static func itemsFile(applicationSupport: URL, fileManager: FileManager = .default) -> URL {
        directory(applicationSupport: applicationSupport, fileManager: fileManager)
            .appendingPathComponent("items.json")
    }

    /// The same, for callers that have no reason to know where Application Support is.
    static func itemsFile(fileManager: FileManager = .default) -> URL {
        itemsFile(applicationSupport: applicationSupportDirectory(fileManager), fileManager: fileManager)
    }

    private static func applicationSupportDirectory(_ fileManager: FileManager) -> URL {
        (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)) ?? fileManager.temporaryDirectory
    }
}
