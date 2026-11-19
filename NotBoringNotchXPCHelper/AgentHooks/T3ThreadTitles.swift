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
            guard let output = ChildProcess.output(cli, ["thread", "show", "--json", "--messages", "0", ids[index]],
                                                    timeout: timeout),
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
    /// the command line, and never as an option: an id starts with a letter or a digit.
    static func isThreadID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, CharacterSet.alphanumerics.contains(first) else { return false }
        return id.count <= 128
            && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }
}
