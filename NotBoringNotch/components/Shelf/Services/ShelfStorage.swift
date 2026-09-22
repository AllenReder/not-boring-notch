//
//  ShelfStorage.swift
//  NotBoringNotch
//
//  Where the file shelf keeps what has been staged on it.
//
//  This app used to be called boringNotch, and the shelf wrote to
//  Application Support/boringNotch/Shelf. The sources and targets were renamed; the
//  directory on disk was not moved with them, and moving it without looking first would
//  strand whatever somebody had already staged there. So the old directory is adopted the
//  first time the new name is used: renamed in place, not copied and not abandoned.
//

import Foundation

enum ShelfStorage {

    /// The name the shelf wrote to before the app was renamed. On the machine of anybody who
    /// used one of those builds this directory still exists, and still holds their items.
    static let legacyDirectoryName = "boringNotch"

    /// The name it writes to now.
    static let directoryName = "NotBoringNotch"

    /// The shelf's directory under `applicationSupport`, having adopted the legacy one.
    ///
    /// Returns `<applicationSupport>/NotBoringNotch/Shelf`. When that does not exist and a
    /// legacy `<applicationSupport>/boringNotch` does, the legacy directory — the whole tree,
    /// so `Shelf/items.json` and anything else beside it — is moved into place first.
    ///
    /// Nothing is created here. A first run gets a path it creates for itself, which keeps
    /// this to the one job of deciding where the shelf lives.
    static func directory(
        applicationSupport: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let current = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: current.path),
           fileManager.fileExists(atPath: legacy.path) {
            do {
                try fileManager.moveItem(at: legacy, to: current)
            } catch {
                // A move can fail: a permission problem, a second launch racing this one, a
                // stale file sitting at the destination. The legacy directory is still
                // readable where it is, so read it there rather than show an empty shelf.
                return legacy.appendingPathComponent("Shelf", isDirectory: true)
            }
        }

        return current.appendingPathComponent("Shelf", isDirectory: true)
    }

    /// The file the shelf's items are persisted to.
    static func itemsFile(
        applicationSupport: URL,
        fileManager: FileManager = .default
    ) -> URL {
        directory(applicationSupport: applicationSupport, fileManager: fileManager)
            .appendingPathComponent("items.json")
    }
}
