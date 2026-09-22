//
//  ShelfStorageMigrationTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/components/Shelf/Services/ShelfStorage.swift
//
//  The directory this migration adopts was created by an older build and still exists on
//  the machines of everybody who used one, holding whatever they had staged. So the legacy
//  name below is spelled out rather than read from the production constant: a test that
//  asked the implementation what its own legacy name was would pass against a typo.
//
//  Helper names are prefixed — `check*` for the assertions, `shelf*` for this runner's
//  fixtures — so they stay distinguishable from the helpers in the other standalone runners
//  in this folder, which are compiled separately but must not read as if they shared a scope.
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

/// An empty Application Support directory of the kind the app is handed, under a unique
/// name so that runners never share one.
func shelfSupportDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("shelf-storage-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func shelfWrite(_ body: String, under name: String, in support: URL) {
    let shelf = support.appendingPathComponent(name, isDirectory: true)
        .appendingPathComponent("Shelf", isDirectory: true)
    try? FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
    try? body.write(to: shelf.appendingPathComponent("items.json"), atomically: true, encoding: .utf8)
}

func shelfContents(at url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

@main
struct ShelfStorageMigrationTestsRunner {
    static func main() {
        testAdoptsTheShelfAnOlderBuildLeftBehind()
        testPrefersTheNewDirectoryWhenBothExist()
        testCreatesNothingWhenThereIsNothingToAdopt()
        testAdoptionIsIdempotent()
        testTheShelfDirectorySitsUnderTheNewName()
        print("🎉 ShelfStorageMigrationTests: all passed")
    }

    /// The behaviour this file exists for: the items somebody staged under the old directory
    /// are still there after the rename.
    static func testAdoptsTheShelfAnOlderBuildLeftBehind() {
        let support = shelfSupportDirectory()
        shelfWrite("[staged before the rename]", under: "boringNotch", in: support)

        let items = ShelfStorage.itemsFile(applicationSupport: support)

        checkEqual(items, support
            .appendingPathComponent("NotBoringNotch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
            .appendingPathComponent("items.json"),
            "the shelf now lives under the new name")
        checkEqual(shelfContents(at: items), "[staged before the rename]",
            "the items staged under the old name survived the move")
        checkTrue(!FileManager.default.fileExists(atPath: support
            .appendingPathComponent("boringNotch").path),
            "the old directory is gone, not duplicated")
    }

    static func testPrefersTheNewDirectoryWhenBothExist() {
        let support = shelfSupportDirectory()
        shelfWrite("[old]", under: "boringNotch", in: support)
        shelfWrite("[new]", under: "NotBoringNotch", in: support)

        let items = ShelfStorage.itemsFile(applicationSupport: support)

        checkEqual(shelfContents(at: items), "[new]",
            "an existing shelf under the new name is never overwritten")
        checkEqual(shelfContents(at: support
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
            .appendingPathComponent("items.json")), "[old]",
            "and the old directory is left where it is, not deleted")
    }

    /// Creating the directory is the caller's job, and it already did it before the rename.
    /// This exists so the migration does not quietly take on a second responsibility.
    static func testCreatesNothingWhenThereIsNothingToAdopt() {
        let support = shelfSupportDirectory()

        let items = ShelfStorage.itemsFile(applicationSupport: support)

        checkEqual(items, support
            .appendingPathComponent("NotBoringNotch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
            .appendingPathComponent("items.json"),
            "the path is still resolved for a first run")
        checkTrue(!FileManager.default.fileExists(atPath: support
            .appendingPathComponent("NotBoringNotch").path),
            "but nothing is created on the migration's behalf")
    }

    static func testAdoptionIsIdempotent() {
        let support = shelfSupportDirectory()
        shelfWrite("[staged]", under: "boringNotch", in: support)

        let first = ShelfStorage.itemsFile(applicationSupport: support)
        let second = ShelfStorage.itemsFile(applicationSupport: support)

        checkEqual(first, second, "the same path on both launches")
        checkEqual(shelfContents(at: second), "[staged]",
            "the second launch does not lose what the first one adopted")
    }

    static func testTheShelfDirectorySitsUnderTheNewName() {
        let support = shelfSupportDirectory()
        shelfWrite("[staged]", under: "boringNotch", in: support)

        checkEqual(ShelfStorage.directory(applicationSupport: support), support
            .appendingPathComponent("NotBoringNotch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true),
            "the directory is the one the item file lives in")
    }
}
