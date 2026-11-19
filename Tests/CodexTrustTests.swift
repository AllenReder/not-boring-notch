//
//  CodexTrustTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh.
//
// SOURCES: NotBoringNotchXPCHelper/AgentHooks/CodexTrust.swift NotBoringNotchXPCHelper/AgentHooks/AgentHookEntries.swift NotBoringNotchXPCHelper/AgentHooks/AgentHookInstaller.swift NotBoringNotchXPCHelper/AgentHooks/ConfigFile.swift NotBoringNotchXPCHelper/AgentHooks/JSONSurgeon.swift NotBoringNotchXPCHelper/AgentHooks/CodexHooksConfig.swift NotBoringNotchXPCHelper/AgentHooks/AgentHooksModels.swift
//
//  Never runs the real `codex`. The exchange with `codex app-server` is checked against a fake
//  executable that answers like it, and the choice of which hooks to trust is a pure function
//  checked on its own.
//

import Foundation

func checkTrust(_ condition: Bool, _ message: String = "",
                file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: \(message) at \(file):\(line)")
        exit(1)
    }
}

let sandboxRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trust-test-\(UUID().uuidString)")
let home = sandboxRoot.appendingPathComponent("home")
let hooksFile = home.appendingPathComponent(".codex/hooks.json")
let ourScript = home.appendingPathComponent(".not-boring-notch/bin/notch-agent-hook")

/// A `hooks/list` result as `codex app-server` reports it: ours (one trusted, two not), a hook of
/// the user's in the same file, and one of ours-by-name in somebody else's file.
func listResult() -> String {
    func hook(_ key: String, _ command: String, _ status: String, _ hash: String, source: String? = nil) -> String {
        #"{"key":"\#(key)","command":"\#(command)","trustStatus":"\#(status)","currentHash":"\#(hash)","sourcePath":"\#(source ?? hooksFile.path)"}"#
    }
    let hooks = [
        hook("hooks.json:SessionStart:0", "\(ourScript.path) codex", "untrusted", "sha256:aaa"),
        hook("hooks.json:Stop:0", "\(ourScript.path) codex", "modified", "sha256:bbb"),
        hook("hooks.json:PreToolUse:0", "\(ourScript.path) codex", "trusted", "sha256:ccc"),
        hook("hooks.json:Stop:1", "/usr/local/bin/their-hook", "untrusted", "sha256:ddd"),
        hook("hooks.json:Stop:2", "/elsewhere/notch-agent-hook codex", "untrusted", "sha256:eee"),
        hook("project:Stop:0", "\(ourScript.path) codex", "untrusted", "sha256:fff", source: "/some/project/.codex/hooks.json"),
    ]
    return #"{"jsonrpc":"2.0","id":2,"result":{"data":[{"cwd":"\#(home.path)","hooks":[\#(hooks.joined(separator: ","))]}]}}"#
}

/// Writes an executable that answers an app-server's three requests and logs what it was sent.
func fakeCodex(named name: String, body: String) -> String {
    let url = sandboxRoot.appendingPathComponent(name)
    try! Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}

let log = sandboxRoot.appendingPathComponent("requests.log")

func answeringServer(list: String, batchReply: String = #"{"jsonrpc":"2.0","id":3,"result":{"status":"ok"}}"#) -> String {
    let listFile = sandboxRoot.appendingPathComponent("list.json")
    try! Data(list.utf8).write(to: listFile)
    return fakeCodex(named: "fake-codex", body: """
    while IFS= read -r line; do
      printf '%s\\n' "$line" >> '\(log.path)'
      case "$line" in
        *'"method":"initialize"'*) echo '{"jsonrpc":"2.0","id":1,"result":{"userAgent":"fake"}}' ;;
        *'"method":"hooks/list"'*) echo '{"jsonrpc":"2.0","method":"hooks/changed","params":{}}'; cat '\(listFile.path)'; echo ;;
        *'"method":"config/batchWrite"'*) echo '\(batchReply)' ;;
      esac
    done
    """)
}

func requests() -> [[String: Any]] {
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").compactMap {
        try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
}

@main
enum CodexTrustTests {
    static func main() throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        // Which hooks are chosen.
        let list = try JSONSerialization.jsonObject(with: Data(listResult().utf8)) as! [String: Any]
        let result = list["result"] as! [String: Any]
        let state = CodexTrust.untrustedState(in: result, hooksFile: hooksFile.path, script: ourScript)
        checkTrust(Set(state.keys) == ["hooks.json:SessionStart:0", "hooks.json:Stop:0"],
                   "only our untrusted or modified hooks in our file are chosen, got \(state.keys.sorted())")
        let session = state["hooks.json:SessionStart:0"] as? [String: String]
        checkTrust(session == ["trusted_hash": "sha256:aaa"], "each carries the hash Codex computed, got \(String(describing: session))")
        checkTrust(CodexTrust.untrustedState(in: [:], hooksFile: hooksFile.path, script: ourScript).isEmpty, "an empty answer has nothing to trust")
        checkTrust(CodexTrust.untrustedState(in: ["data": []], hooksFile: hooksFile.path, script: ourScript).isEmpty, "no workspace has nothing to trust")

        // The exchange, start to finish.
        let server = answeringServer(list: listResult())
        let trusted = try CodexTrust.trustOurHooks(hooksFile: hooksFile, script: ourScript, home: home, executable: server)
        checkTrust(trusted == 2, "two hooks were trusted, got \(trusted)")
        let sent = requests()
        checkTrust(sent.map { $0["method"] as? String } == ["initialize", "initialized", "hooks/list", "config/batchWrite"],
                   "the requests, in order, got \(sent.map { $0["method"] ?? "?" })")
        checkTrust(sent[1]["id"] == nil, "`initialized` is a notification, without an id")
        checkTrust(sent.allSatisfy { $0["jsonrpc"] as? String == "2.0" }, "every message is JSON-RPC 2.0")
        checkTrust(((sent[0]["params"] as? [String: Any])?["clientInfo"] as? [String: String])?["name"] == "not-boring-notch", "names itself")
        checkTrust((sent[2]["params"] as? [String: Any])?["cwds"] as? [String] == [home.path], "lists the hooks for the home directory")
        let edit = ((sent[3]["params"] as? [String: Any])?["edits"] as? [[String: Any]])?.first
        checkTrust(edit?["keyPath"] as? String == "hooks.state" && edit?["mergeStrategy"] as? String == "upsert", "upserts hooks.state, got \(String(describing: edit))")
        let written = edit?["value"] as? [String: [String: String]]
        checkTrust(written == ["hooks.json:SessionStart:0": ["trusted_hash": "sha256:aaa"],
                               "hooks.json:Stop:0": ["trusted_hash": "sha256:bbb"]], "writes exactly the chosen hashes, got \(String(describing: written))")

        // Nothing to trust: nothing is written.
        try? FileManager.default.removeItem(at: log)
        let none = answeringServer(list: #"{"jsonrpc":"2.0","id":2,"result":{"data":[{"cwd":"x","hooks":[]}]}}"#)
        checkTrust(try CodexTrust.trustOurHooks(hooksFile: hooksFile, script: ourScript, home: home, executable: none) == 0, "nothing to trust")
        checkTrust(!requests().contains { $0["method"] as? String == "config/batchWrite" }, "and no write is made")

        // The server refuses.
        let refusing = answeringServer(list: listResult(), batchReply: #"{"jsonrpc":"2.0","id":3,"error":{"code":-32000,"message":"config is read-only"}}"#)
        do {
            _ = try CodexTrust.trustOurHooks(hooksFile: hooksFile, script: ourScript, home: home, executable: refusing)
            checkTrust(false, "an error reply must be an error")
        } catch {
            checkTrust(error.localizedDescription.contains("config is read-only"), "the server's reason is passed on, got \(error)")
        }

        // The server dies, or never answers.
        let dying = fakeCodex(named: "dying-codex", body: "exit 3")
        do {
            _ = try CodexTrust.trustOurHooks(hooksFile: hooksFile, script: ourScript, home: home, executable: dying)
            checkTrust(false, "a server that exits must be an error")
        } catch {
            checkTrust(error.localizedDescription.contains("stopped answering"), "got \(error)")
        }
        let hanging = fakeCodex(named: "hanging-codex", body: "sleep 30")
        let started = Date()
        do {
            _ = try CodexTrust.trustOurHooks(hooksFile: hooksFile, script: ourScript, home: home, executable: hanging, timeout: 1)
            checkTrust(false, "a server that never answers must be an error")
        } catch {
            checkTrust(Date().timeIntervalSince(started) < 4, "gives up after the timeout, took \(Date().timeIntervalSince(started))")
        }

        // Finding codex.
        let bin = sandboxRoot.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        checkTrust(CodexTrust.findCodex(path: "\(bin.path):/usr/bin", home: home) == nil, "no codex on the path")
        let installed = bin.appendingPathComponent("codex")
        try Data("#!/bin/sh\n".utf8).write(to: installed)
        checkTrust(CodexTrust.findCodex(path: "\(bin.path):/usr/bin", home: home) == nil, "a file that isn't executable isn't codex")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path)
        checkTrust(CodexTrust.findCodex(path: "/usr/bin:\(bin.path)", home: home) == installed.path, "codex is found on the path")

        print("✅ CodexTrustTests passed")
    }
}
