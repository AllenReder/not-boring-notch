//
//  T3ThreadTitlesTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below.
//
// SOURCES: NotBoringNotchXPCHelper/AgentHooks/T3ThreadTitles.swift NotBoringNotchXPCHelper/AgentHooks/ChildProcess.swift
//
//  The CLI here is a stand-in script that answers as `t3 thread show --json` does, so the test
//  runs the real process plumbing without T3 Code.
//

import Foundation

func checkTitles<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                               file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func fakeCLI(_ body: String) -> (cli: URL, cleanUp: () -> Void) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("t3-cli-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cli = directory.appendingPathComponent("t3")
    try! Data(("#!/bin/sh\n" + body).utf8).write(to: cli)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
    return (cli, { try? FileManager.default.removeItem(at: directory) })
}

func testReadsTheTitleFromWhatTheCLIPrints() {
    func title(_ json: String) -> String? { T3ThreadTitles.title(fromShowJSON: Data(json.utf8)) }
    checkTitles(title(#"{"thread":{"threadId":"a","title":"Agent通知功能"},"messages":[]}"#), "Agent通知功能", "the title")
    checkTitles(title(#"{"thread":{"threadId":"a","title":"  spaced  "}}"#), "spaced", "trimmed")
    checkTitles(title(#"{"thread":{"threadId":"a","title":""}}"#), nil, "an empty title is no title")
    checkTitles(title(#"{"thread":{"threadId":"a"}}"#), nil, "no title")
    checkTitles(title("Error: no such thread"), nil, "not JSON")
}

func testOnlyThreadIDsReachTheCommandLine() {
    checkTitles(T3ThreadTitles.isThreadID("642a6259-dbb6-4069-988d-7dcc740ac212"), true, "a uuid")
    checkTitles(T3ThreadTitles.isThreadID(""), false, "empty")
    checkTitles(T3ThreadTitles.isThreadID("--help"), false, "an option, not an id")
    checkTitles(T3ThreadTitles.isThreadID("-x"), false, "nor anything else that starts with a dash")
    checkTitles(T3ThreadTitles.isThreadID("a-b_c"), true, "dashes and underscores inside are fine")
    checkTitles(T3ThreadTitles.isThreadID("a b"), false, "a space")
    checkTitles(T3ThreadTitles.isThreadID("a;rm -rf ~"), false, "shell characters")
    checkTitles(T3ThreadTitles.isThreadID(String(repeating: "a", count: 129)), false, "too long")
}

func testAsksTheCLIForEachThread() {
    // Answers for th-1 and th-2, fails for anything else, and records what it was asked.
    let (cli, cleanUp) = fakeCLI("""
    echo "$@" >> "$(dirname "$0")/asked"
    case "$6" in
      th-1) echo '{"thread":{"threadId":"th-1","title":"First"}}' ;;
      th-2) echo '{"thread":{"threadId":"th-2","title":"Second"}}' ;;
      *) echo 'no such thread' >&2; exit 1 ;;
    esac
    """)
    defer { cleanUp() }
    let titles = T3ThreadTitles.titles(of: ["th-1", "th-2", "th-gone", "th-1", "bad id"], cli: cli)
    checkTitles(titles, ["th-1": "First", "th-2": "Second"], "each thread T3 Code could name")
    let asked = (try? String(contentsOf: cli.deletingLastPathComponent().appendingPathComponent("asked"), encoding: .utf8)) ?? ""
    checkTitles(asked.split(separator: "\n").sorted(),
                ["thread show --json --messages 0 th-1", "thread show --json --messages 0 th-2",
                 "thread show --json --messages 0 th-gone"],
                "once per thread, and never for an id that is not one")
}

func testGivesUpOnACLIThatHangsOrIsMissing() {
    let (cli, cleanUp) = fakeCLI("sleep 30\n")
    defer { cleanUp() }
    let started = Date()
    checkTitles(T3ThreadTitles.titles(of: ["th-1"], cli: cli), [:], "a CLI that hangs names nothing")
    checkTitles(Date().timeIntervalSince(started) < T3ThreadTitles.timeout + 3, true, "and is abandoned")
    checkTitles(T3ThreadTitles.titles(of: ["th-1"], cli: URL(fileURLWithPath: "/nonexistent/t3")), [:],
                "without T3 Code there is nothing to ask")
}

@main
enum T3ThreadTitlesTests {
    static func main() {
        testReadsTheTitleFromWhatTheCLIPrints()
        testOnlyThreadIDsReachTheCommandLine()
        testAsksTheCLIForEachThread()
        testGivesUpOnACLIThatHangsOrIsMissing()
        print("✅ T3ThreadTitlesTests passed")
    }
}
