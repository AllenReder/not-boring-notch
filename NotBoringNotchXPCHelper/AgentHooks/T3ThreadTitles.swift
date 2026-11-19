//
//  T3ThreadTitles.swift
//  NotBoringNotchXPCHelper
//
//  Asks T3 Code what its threads are called. The hooks know only a session's thread id; the title
//  lives in the running T3 Code, which its own CLI reads for us: `t3 thread show --json`. The
//  sandboxed app cannot run it, so the helper does.
//

import Foundation

enum T3ThreadTitles {
    /// The CLI T3 Code installs for its agents (`$T3CODE_CLI_PATH`).
    static func cli(home: URL) -> URL { home.appendingPathComponent(".t3/bin/t3") }

    /// Seconds one lookup may take before it is abandoned.
    static let timeout: TimeInterval = 5

    /// thread id -> title, for each thread T3 Code could name. Asks for all of them at once.
    static func titles(of threadIDs: [String], cli: URL) -> [String: String] {
        guard FileManager.default.isExecutableFile(atPath: cli.path) else { return [:] }
        let ids = Array(Set(threadIDs.filter(isThreadID)))
        var titles: [String: String] = [:]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            guard let output = run(cli, ["thread", "show", "--json", "--messages", "0", ids[index]]),
                  let title = title(fromShowJSON: output) else { return }
            lock.withLock { titles[ids[index]] = title }
        }
        return titles
    }

    /// The title in what `t3 thread show --json` printed, if it has a non-empty one.
    static func title(fromShowJSON data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thread = json["thread"] as? [String: Any],
              let title = (thread["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    /// Ids come from a header any local process could send; only an id's own characters reach
    /// the command line.
    static func isThreadID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128
            && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }

    /// The command's output, or nil when it failed or took too long.
    private static func run(_ executable: URL, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        // Read while it runs, so a large reply cannot fill the pipe and stall it.
        var data = Data()
        let read = DispatchGroup()
        read.enter()
        DispatchQueue.global().async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            read.leave()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = read.wait(timeout: .now() + 1)
            return nil
        }
        // The pipe ends when the process does; anything that kept it open gets a second.
        guard read.wait(timeout: .now() + 1) == .success else { return nil }
        return process.terminationStatus == 0 ? data : nil
    }
}
