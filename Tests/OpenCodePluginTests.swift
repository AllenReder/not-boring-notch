//
//  OpenCodePluginTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below.
//
// SOURCES: NotBoringNotchXPCHelper/AgentHooks/OpenCodePlugin.swift NotBoringNotchXPCHelper/AgentHooks/PiExtension.swift NotBoringNotchXPCHelper/AgentHooks/AgentPluginFile.swift NotBoringNotchXPCHelper/AgentHooks/AgentHooksModels.swift
//
//  The plugin is JavaScript inside a Swift string, so these tests run it: Tests/OpenCodePlugin/
//  replay.mjs loads the bundled source under node (or bun), feeds it what real OpenCode 2.3.2
//  runs produced (Tests/Fixtures/opencode/serve-capture.jsonl, cut from a logging plugin's capture
//  of `opencode serve` by Tests/OpenCodePlugin/make-fixture.py), and collects what it posts to a
//  stand-in for the notch. The capture holds a turn that reads, one that asks for approval, one
//  that asks a question, a sub-agent, an interrupt during a pending approval, a failed turn, a
//  deletion, and two directories served by two copies of the plugin that each hear every event.
//  Without node or bun the runner says so and passes.
//

import Foundation

func checkPlugin(_ condition: Bool, _ message: String = "",
                 file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: \(message) at \(file):\(line)")
        exit(1)
    }
}

struct Replay {
    var process: (pid: Int, ppid: Int)
    var posts: [(headers: [String: String], body: [String: Any])]
}

let testsFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func runtime() -> String? {
    for candidate in ["node", "bun"] {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        probe.arguments = [candidate, "--version"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        if (try? probe.run()) != nil {
            probe.waitUntilExit()
            if probe.terminationStatus == 0 { return candidate }
        }
    }
    return nil
}

func replay(_ runtime: String, plugin: URL, flags: [String] = []) -> Replay {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [runtime, testsFolder.appendingPathComponent("OpenCodePlugin/replay.mjs").path, plugin.path,
                         testsFolder.appendingPathComponent("Fixtures/opencode/serve-capture.jsonl").path] + flags
    let pipe = Pipe()
    process.standardOutput = pipe
    try! process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    checkPlugin(process.terminationStatus == 0, "the replay ran to the end")

    var lines = String(decoding: output, as: UTF8.self).split(separator: "\n")
        .map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    let me = (lines.removeFirst()["process"] as! [String: Int])
    return Replay(process: (me["pid"]!, me["ppid"]!), posts: lines.map {
        ($0["headers"] as! [String: String], $0["body"] as! [String: Any])
    })
}

func fixtureBodies(_ name: String) -> [[String: Any]] {
    try! String(contentsOf: testsFolder.appendingPathComponent("Fixtures/opencode/\(name)"), encoding: .utf8)
        .split(separator: "\n").map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
}

@main
struct OpenCodePluginTestsRunner {
    static func main() throws {
        guard let runtime = runtime() else {
            print("⚠️  neither node nor bun is installed; the OpenCode plugin was not run")
            return
        }
        let plugin = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oc-plugin-\(UUID().uuidString).mjs")
        try OpenCodePlugin.file.source.write(to: plugin, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: plugin) }

        let all = replay(runtime, plugin: plugin)
        testItPostsWhatTheReducerIsToReplay(all)
        testEveryEventIsPostedOnceByTheCopyOfItsDirectory(all)
        testASubAgentIsReportedUnderItsRoot(all)
        testEveryPostCarriesTheT3ThreadOfItsRootSession(all)
        testASharedServiceReportsNoProcess(replay(runtime, plugin: plugin, flags: ["--service"]))
        testAPrivateChildIsWatchedThroughItsParent(replay(runtime, plugin: plugin, flags: ["--stdio"]), plain: all)
        print("✅ OpenCodePluginTests passed")
    }

    /// The committed posted fixture is what the reducer tests replay, so it must be what the
    /// plugin really posts for the capture.
    static func testItPostsWhatTheReducerIsToReplay(_ run: Replay) {
        let expected = fixtureBodies("serve-posted.jsonl")
        checkPlugin(run.posts.count == expected.count, "\(run.posts.count) posts, the fixture has \(expected.count)")
        for (index, post) in run.posts.enumerated() {
            checkPlugin(NSDictionary(dictionary: post.body).isEqual(to: expected[index]),
                        "post \(index) is \(post.body), the fixture has \(expected[index])")
        }
    }

    /// Two copies of the plugin, one per directory, hear every event; only the copy whose
    /// directory the session belongs to posts it.
    static func testEveryEventIsPostedOnceByTheCopyOfItsDirectory(_ run: Replay) {
        func count(_ name: String, session: String) -> Int {
            run.posts.filter { $0.body["hook_event_name"] as? String == name && ($0.body["session_id"] as? String)?.hasSuffix(session) == true }.count
        }
        checkPlugin(count("session.execution.started", session: "DS5bHX") == 1, "the session of the second directory started once")
        checkPlugin(count("session.execution.succeeded", session: "DS5bHX") == 1, "and succeeded once")
        let directories = run.posts.filter { ($0.body["session_id"] as? String)?.hasSuffix("DS5bHX") == true }.map { $0.body["cwd"] as? String }
        checkPlugin(directories == ["/work/oc-proj2", "/work/oc-proj2"], "both from its own directory, got \(directories)")
        checkPlugin(count("session.deleted", session: "XIH5a1") == 1, "a deletion both copies hear is posted once")
    }

    static func testASubAgentIsReportedUnderItsRoot(_ run: Replay) {
        let child = "ses_e08b7bd74ffe9eFe2STvipkO3R"
        let root = "ses_e08ba637cffetplGsUYMPqQFI7"
        let theirs = run.posts.filter { $0.body["agent_id"] as? String == child }
        checkPlugin(!theirs.isEmpty && theirs.allSatisfy { $0.body["session_id"] as? String == root },
                    "every event of the sub-agent is posted under the root's id")
        checkPlugin(theirs.first?.body["hook_event_name"] as? String == "session.created", "starting with its creation")
        checkPlugin(theirs.last?.body["hook_event_name"] as? String == "session.execution.succeeded", "and ending with its end")
        checkPlugin(run.posts.filter { $0.body["session_id"] as? String == child }.isEmpty, "none under its own id")
    }

    static func testEveryPostCarriesTheT3ThreadOfItsRootSession(_ run: Replay) {
        for post in run.posts {
            let isRoot = (post.body["session_id"] as? String)?.hasSuffix("PqQFI7") == true
            checkPlugin((post.headers["x-agent-t3-thread"] == "thread-1") == isRoot, "the thread is the root session's: \(post.body)")
            checkPlugin(!isRoot || post.headers["x-agent-t3-environment"] == "env-1", "with the environment read from T3's home")
        }
    }

    static func testASharedServiceReportsNoProcess(_ run: Replay) {
        checkPlugin(!run.posts.isEmpty, "it still posts")
        for post in run.posts {
            checkPlugin(post.headers["x-agent-pid"] == nil && post.headers["x-agent-host-bundle"] == nil
                        && post.headers["x-agent-term-program"] == nil,
                        "the service's pid and environment belong to whoever started it: \(post.headers)")
        }
        checkPlugin(run.posts.contains { $0.headers["x-agent-t3-thread"] != nil }, "but a T3 thread is still named")
    }

    static func testAPrivateChildIsWatchedThroughItsParent(_ run: Replay, plain: Replay) {
        checkPlugin(run.posts.allSatisfy { $0.headers["x-agent-pid"] == String(run.process.ppid) },
                    "a private serve --stdio child is watched through its parent")
        checkPlugin(run.posts.allSatisfy { $0.headers["x-agent-host-bundle"] == "com.example.host" && $0.headers["x-agent-term-program"] == "replay-term" },
                    "with the environment it inherited")
        checkPlugin(plain.posts.allSatisfy { $0.headers["x-agent-pid"] == String(plain.process.pid) },
                    "any other server is watched as itself")
    }
}
