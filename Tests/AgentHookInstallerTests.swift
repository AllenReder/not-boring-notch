//
//  AgentHookInstallerTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below.
//
// SOURCES: NotBoringNotchXPCHelper/AgentHooks/AgentHookInstaller.swift NotBoringNotchXPCHelper/AgentHooks/AgentHookEntries.swift NotBoringNotchXPCHelper/AgentHooks/ConfigFile.swift NotBoringNotchXPCHelper/AgentHooks/JSONSurgeon.swift NotBoringNotchXPCHelper/AgentHooks/CodexHooksConfig.swift NotBoringNotchXPCHelper/AgentHooks/AgentHooksModels.swift NotBoringNotch/Agents/Hooks/AgentHookScript.swift NotBoringNotchXPCHelper/AgentHooks/PiExtension.swift NotBoringNotchXPCHelper/AgentHooks/OpenCodePlugin.swift NotBoringNotchXPCHelper/AgentHooks/AgentPluginFile.swift
//
//  Every test runs against a temporary HOME. The files here belong to the user, so the claim
//  that matters is about bytes: whatever the installer did not write, it did not change.
//

import Foundation

func checkInstall(_ condition: Bool, _ message: String = "",
                  file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: \(message) at \(file):\(line)")
        exit(1)
    }
}

let script = AgentHookScript.source

/// A throwaway HOME.
struct InstallHome {
    let url: URL
    let installer: AgentHookInstaller

    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("install-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        installer = AgentHookInstaller(home: url)
    }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }
    var settings: URL { path(".claude/settings.json") }
    var hooks: URL { path(".codex/hooks.json") }
    var toml: URL { path(".codex/config.toml") }

    func write(_ text: String, to file: URL, mode: Int = 0o644) {
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(text.utf8).write(to: file)
        try! FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
    }

    func read(_ file: URL) -> String? { try? String(contentsOf: file, encoding: .utf8) }
    func bytes(_ file: URL) -> Data? { FileManager.default.contents(atPath: file.path) }
    func mode(_ file: URL) -> Int {
        Int((try! FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber).intValue)
    }
    func backups() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path(".not-boring-notch/backups").path)) ?? []
    }

    func install(_ targets: [AgentHookTarget], script: String = script) -> AgentHooksReport {
        installer.install(targets, script: script)
    }
    func uninstall(_ targets: [AgentHookTarget]) -> AgentHooksReport {
        installer.uninstall(targets, bundledScript: script)
    }
    func status(_ target: AgentHookTarget, script: String = script) -> AgentHookState {
        installer.status(of: target, bundledScript: script).state
    }

    func cleanUp() { try? FileManager.default.removeItem(at: url) }
}

/// Whether every byte of `small` appears in `large`, in order.
func isSubsequence(_ small: Data, of large: Data) -> Bool {
    var index = small.startIndex
    for byte in large where index < small.endIndex && byte == small[index] { index += 1 }
    return index == small.endIndex
}

func jsonObject(_ text: String) -> NSDictionary {
    guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary else {
        checkInstall(false, "not a JSON object: \(text.debugDescription)")
        return [:]
    }
    return object
}

// MARK: - Fixtures: files as people actually write them

let userClaudeHooks = """
{
  "model": "opus",
  "permissions": { "allow": ["Bash(git status)", "Read(~/notes/**)"],   "deny": [] },
  "env": {"ANTHROPIC_BASE_URL":"https://example.invalid/\\u00e9"},
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "~/bin/audit-bash.sh" } ]
      }
    ],
    "Stop":[{"hooks":[{"type":"command","command":"echo notch-agent-hook is a nice name"}]}]
  },
  "statusLine": {"type": "command", "command": "~/bin/status"}
}

"""

let claudeFixtures: [(name: String, text: String)] = [
    ("two-space with user hooks and odd spacing", userClaudeHooks),
    ("four-space CRLF", "{\r\n    \"theme\": \"dark\",\r\n    \"hooks\": {\r\n        \"Stop\": [\r\n            {\r\n                \"hooks\": [{\"type\": \"command\", \"command\": \"x\"}]\r\n            }\r\n        ]\r\n    }\r\n}\r\n"),
    ("tabs, no hooks key", "{\n\t\"model\": \"sonnet\",\n\t\"verbose\": true\n}\n"),
    ("minified, no trailing newline", #"{"model":"opus","hooks":{"Notification":[{"hooks":[{"type":"command","command":"y"}]}]}}"#),
    ("empty object", "{}"),
]

/// Files where uninstall can only restore the meaning, not the bytes. With nothing recording
/// what was there before, an emptied `hooks` object is removed whether the user wrote it or the
/// install created it, and the whitespace inside an object that held nothing is not kept.
let claudeEmptyContainerFixtures: [(name: String, text: String)] = [
    ("empty object on two lines", "{\n}\n"),
    ("hooks present but empty", "{\n  \"hooks\": {}\n}\n"),
]

let codexFixtures: [(name: String, text: String)] = [
    ("user hook in a Codex file", """
    {
      "hooks": {
        "SessionStart": [
          { "hooks": [ { "type": "command", "command": "/usr/local/bin/codex-log" } ] }
        ]
      }
    }

    """),
    ("empty object", "{}\n"),
]

// MARK: - Byte preservation

func testInstallChangesOnlyOurEntriesAndUninstallRestoresTheBytes() {
    for (name, original) in claudeFixtures {
        let home = InstallHome()
        defer { home.cleanUp() }
        home.write(original, to: home.settings, mode: 0o640)

        let report = home.install([.claudeCode])
        checkInstall(report.statuses == [AgentHookStatus(agent: .claudeCode, state: .installed)],
                     "\(name): installs cleanly, got \(report)")
        let installed = home.read(home.settings)!

        checkInstall(isSubsequence(Data(original.utf8), of: Data(installed.utf8)),
                     "\(name): install only adds bytes, every original byte is still there in order")
        checkInstall(home.mode(home.settings) == 0o640, "\(name): the file keeps its permissions")
        let installedJSON = jsonObject(installed)
        let originalJSON = jsonObject(original)
        for (key, value) in originalJSON where key as! String != "hooks" {
            checkInstall((installedJSON[key] as AnyObject).isEqual(value), "\(name): \(key) is untouched")
        }
        let hooks = installedJSON["hooks"] as! [String: [[String: Any]]]
        for event in AgentHookSpec.of(.claudeCode).events {
            checkInstall(hooks[event]?.count ?? 0 >= 1, "\(name): \(event) is registered")
        }
        if let userStop = (originalJSON["hooks"] as? [String: Any])?["Stop"] as? [Any] {
            checkInstall(hooks["Stop"]!.count == userStop.count + 1, "\(name): the user's Stop hook is still there")
        }

        checkInstall(home.backups().count == 1, "\(name): the original was backed up once, got \(home.backups())")
        let backup = home.read(home.path(".not-boring-notch/backups/\(home.backups()[0])"))
        checkInstall(backup == original, "\(name): the backup is the original, byte for byte")

        _ = home.uninstall([.claudeCode])
        checkInstall(home.read(home.settings) == original, "\(name): uninstall restores the original bytes")
        checkInstall(home.status(.claudeCode) == .notInstalled, "\(name): and reports not installed")
        checkInstall(!FileManager.default.fileExists(atPath: home.installer.scriptURL.path),
                     "\(name): the script goes when nothing uses it")
    }
}

func testUninstallRestoresTheMeaningWhereBytesCannotBeKept() {
    for (name, original) in claudeEmptyContainerFixtures {
        let home = InstallHome()
        defer { home.cleanUp() }
        home.write(original, to: home.settings)
        _ = home.install([.claudeCode])
        checkInstall(isSubsequence(Data(original.utf8), of: Data(home.bytes(home.settings)!)), "\(name): install only adds bytes")
        _ = home.uninstall([.claudeCode])
        let after = home.read(home.settings)!
        checkInstall(jsonObject(after).count == 0 && !after.contains("notch-agent-hook"), "\(name): nothing of ours is left, got \(after)")
    }
}

func testCodexInstallAndUninstall() {
    for (name, original) in codexFixtures {
        let home = InstallHome()
        defer { home.cleanUp() }
        home.write(original, to: home.hooks)
        let tomlOriginal = "# my codex\nmodel = \"gpt-5\"\n\n[features]\nundo = true # keep\n\n[projects.\"/x\"]\ntrust_level = \"trusted\"\n"
        home.write(tomlOriginal, to: home.toml)

        let report = home.install([.codex])
        checkInstall(report.statuses == [AgentHookStatus(agent: .codex, state: .installed)], "\(name): installs, got \(report)")
        let installed = home.read(home.hooks)!
        checkInstall(isSubsequence(Data(original.utf8), of: Data(installed.utf8)), "\(name): hooks.json only gains bytes")
        let toml = home.read(home.toml)!
        checkInstall(isSubsequence(Data(tomlOriginal.utf8), of: Data(toml.utf8)), "\(name): config.toml only gains bytes")
        checkInstall(toml.contains("hooks = true"), "\(name): features.hooks is on, got \(toml)")

        _ = home.uninstall([.codex])
        checkInstall(home.read(home.hooks) == original, "\(name): uninstall restores hooks.json")
        checkInstall(home.read(home.toml) == toml, "\(name): config.toml keeps hooks on, other hooks may rely on it")
    }
}

func testInstallCreatesMissingFiles() {
    let home = InstallHome()
    defer { home.cleanUp() }
    _ = home.install([.claudeCode, .codex])
    checkInstall(home.status(.claudeCode) == .installed && home.status(.codex) == .installed, "both installed")
    checkInstall(home.read(home.settings)!.hasSuffix("}\n"), "a created file ends with a newline")
    checkInstall(home.mode(home.settings) == 0o600, "a created settings file is private")
    checkInstall(home.read(home.toml) == "features.hooks = true\n", "a created config.toml only turns hooks on, got \(home.read(home.toml) ?? "nil")")
    checkInstall(home.backups().isEmpty, "nothing existed to back up")

    _ = home.uninstall([.claudeCode])
    checkInstall(home.status(.claudeCode) == .notInstalled && home.status(.codex) == .installed, "only Claude Code was removed")
    checkInstall(FileManager.default.fileExists(atPath: home.installer.scriptURL.path), "the script stays while Codex uses it")
    _ = home.uninstall([.codex])
    checkInstall(!FileManager.default.fileExists(atPath: home.installer.scriptURL.path), "the script goes with the last user")
    checkInstall(jsonObject(home.read(home.settings)!).count == 0, "what was created is left as an empty object")
}

func testInstallingOneAgentLeavesTheOtherAlone() {
    let home = InstallHome()
    defer { home.cleanUp() }
    _ = home.install([.claudeCode])
    checkInstall(!FileManager.default.fileExists(atPath: home.path(".codex").path), "Codex's folder is not created")
}

// MARK: - Idempotence and repair

func testReinstallChangesNothing() {
    let home = InstallHome()
    defer { home.cleanUp() }
    home.write(userClaudeHooks, to: home.settings)
    _ = home.install([.claudeCode, .codex])
    let first = home.bytes(home.settings)!
    let firstCodex = home.bytes(home.hooks)!
    let backups = home.backups()
    _ = home.install([.claudeCode, .codex])
    checkInstall(home.bytes(home.settings) == first && home.bytes(home.hooks) == firstCodex, "a second install is a byte-for-byte no-op")
    checkInstall(home.backups() == backups, "and takes no further backup")
}

func testStatusFollowsWhatHappensToOurEntries() throws {
    let home = InstallHome()
    defer { home.cleanUp() }
    checkInstall(home.status(.claudeCode) == .notInstalled && home.status(.codex) == .notInstalled, "fresh home: not installed")
    _ = home.install([.claudeCode, .codex])
    checkInstall(home.status(.claudeCode) == .installed && home.status(.codex) == .installed, "installed")

    // A newer app bundles a newer script.
    let newer = script.replacingOccurrences(of: "notch-agent-hook-version: \(AgentHookScript.version)",
                                            with: "notch-agent-hook-version: \(AgentHookScript.version + 1)")
    checkInstall(home.status(.claudeCode, script: newer) == .outdated, "a newer bundled script makes the install outdated")
    _ = home.install([.claudeCode], script: newer)
    checkInstall(home.status(.claudeCode, script: newer) == .installed, "repairing brings it up to date")
    checkInstall(home.read(home.installer.scriptURL) == newer, "with the new script")

    // The user edits one of our entries.
    let edited = home.read(home.settings)!.replacingOccurrences(of: "\"timeout\": 3", with: "\"timeout\": 99")
        .replacingOccurrences(of: "\"timeout\":3", with: "\"timeout\":99")
    checkInstall(edited != home.read(home.settings)!, "the fixture really changed an entry")
    home.write(edited, to: home.settings)
    let modified = home.installer.status(of: .claudeCode, bundledScript: newer)
    checkInstall(modified.state == .modified && modified.problem != nil, "an edited entry is modified, got \(modified)")
    _ = home.install([.claudeCode], script: newer)
    checkInstall(home.status(.claudeCode, script: newer) == .installed, "repair puts it back")
    // The path in each entry holds a random UUID, so look for the timeout, not the digits.
    let repaired = home.read(home.settings)!
    checkInstall(!repaired.contains("\"timeout\": 99") && !repaired.contains("\"timeout\":99"), "without the edit")

    // A release that registers more events than the installed one.
    let spec = AgentHookSpec.of(.claudeCode)
    var surgeon = try JSONSurgeon(home.read(home.settings)!)
    let entries = AgentHookEntries(spec: spec, scriptURL: home.installer.scriptURL, filePath: "")
    try surgeon.removeFromArray(atPath: ["hooks", "StopFailure"], where: entries.isOurEntry)
    home.write(surgeon.text, to: home.settings)
    checkInstall(home.status(.claudeCode, script: newer) == .outdated, "a missing event means an older install")

    // The script deleted, or edited without a version bump.
    try FileManager.default.removeItem(at: home.installer.scriptURL)
    checkInstall(home.status(.codex, script: newer) == .modified, "a missing script is a broken install")
    _ = home.install([.codex], script: newer)
    try Data((newer + "\necho tampered\n").utf8).write(to: home.installer.scriptURL)
    checkInstall(home.status(.codex, script: newer) == .modified, "an edited script is modified")
    _ = home.install([.codex], script: newer)
    checkInstall(home.read(home.installer.scriptURL) == newer, "repair rewrites it")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: home.installer.scriptURL.path)
    checkInstall(home.status(.codex, script: newer) == .modified, "a script that can't run is modified")
    _ = home.install([.codex], script: newer)
    checkInstall(home.mode(home.installer.scriptURL) == 0o755, "repair makes it executable again")

    // Codex hooks turned off in config.toml: the user's choice.
    home.write("[features]\nhooks = false\n", to: home.toml)
    checkInstall(home.status(.codex, script: newer) == .turnedOff, "Codex hooks turned off are the user's choice")
    checkInstall(!home.installer.report(bundledScript: newer).needingRepair.contains(.codex), "which a launch leaves alone")
    _ = home.install([.codex], script: newer)
    checkInstall(home.status(.codex, script: newer) == .installed, "and the user can turn them on")

    // Never turned on, rather than turned off, is a broken install.
    home.write("model = \"x\"\n", to: home.toml)
    checkInstall(home.status(.codex, script: newer) == .modified, "Codex hooks not turned on is modified")
    checkInstall(home.installer.report(bundledScript: newer).needingRepair.contains(.codex), "which a launch repairs")
    _ = home.install([.codex], script: newer)
    checkInstall(home.status(.codex, script: newer) == .installed, "repair turns them on")
}

// MARK: - What gets written

func testEntriesLookLikeTheDesign() {
    let home = InstallHome()
    defer { home.cleanUp() }
    _ = home.install([.claudeCode, .codex])
    let scriptPath = home.installer.scriptURL.path
    checkInstall(!scriptPath.contains(" "), "the script path has no space")
    checkInstall(home.mode(home.installer.scriptURL) == 0o755, "the script is executable")
    checkInstall(home.read(home.installer.scriptURL) == script, "and is the bundled text")

    let claude = jsonObject(home.read(home.settings)!)["hooks"] as! [String: [[String: Any]]]
    checkInstall(Set(claude.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                      "PermissionRequest", "Notification", "SubagentStart", "SubagentStop", "Stop", "StopFailure",
                                      "SessionEnd"], "Claude's events")
    for (event, list) in claude {
        let entry = list[0]
        let hook = (entry["hooks"] as! [[String: Any]])[0]
        checkInstall(hook["command"] as? String == "\(scriptPath) claude-code", "\(event): command")
        checkInstall(hook["type"] as? String == "command" && hook["timeout"] as? Int == 3, "\(event): type and a short timeout")
        checkInstall(hook["async"] == nil, "\(event): synchronous")
        if event == "Stop" || event == "UserPromptSubmit" {
            checkInstall(entry["matcher"] == nil, "\(event): no matcher on an event that has none")
        } else {
            checkInstall(entry["matcher"] as? String == "*", "\(event): matcher *")
        }
    }

    let codex = jsonObject(home.read(home.hooks)!)["hooks"] as! [String: [[String: Any]]]
    checkInstall(Set(codex.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                                     "SubagentStart", "SubagentStop", "Stop", "SessionEnd", "Interrupt"], "Codex's events")
    for (event, list) in codex {
        let hook = (list[0]["hooks"] as! [[String: Any]])[0]
        checkInstall(hook["command"] as? String == "\(scriptPath) codex", "\(event): command is the path and the agent name")
        checkInstall(hook["async"] == nil && hook["args"] == nil && list[0]["matcher"] == nil, "\(event): no async, no args, no matcher")
    }

    // The two entries, as written, for the report.
    print("   claude PreToolUse: " + (String(data: try! JSONSerialization.data(withJSONObject: claude["PreToolUse"]![0], options: [.sortedKeys]), encoding: .utf8)!)
        .replacingOccurrences(of: home.url.path, with: "$HOME"))
    print("   codex  Stop:       " + (String(data: try! JSONSerialization.data(withJSONObject: codex["Stop"]![0], options: [.sortedKeys]), encoding: .utf8)!)
        .replacingOccurrences(of: home.url.path, with: "$HOME"))
}

// MARK: - Refusals

func testRefusesFilesItCannotEditSafely() {
    let broken: [(String, String)] = [
        ("a trailing comma", "{\"a\": 1,}"),
        ("text that is not JSON", "not json"),
        ("an array at the root", "[]"),
        ("hooks that is a string", "{\"hooks\": \"x\"}"),
        ("an event that is an object", "{\"hooks\": {\"Stop\": {}}}"),
        ("a truncated file", "{\"hooks\": {\"Stop\": ["),
    ]
    for (name, text) in broken {
        let home = InstallHome()
        defer { home.cleanUp() }
        home.write(text, to: home.settings)
        let report = home.install([.claudeCode])
        let status = report.statuses[0]
        checkInstall(status.problem != nil, "\(name): says why it refused")
        checkInstall(status.state != .installed, "\(name): is not reported installed")
        checkInstall(home.read(home.settings) == text, "\(name): the file is untouched")
        checkInstall(!FileManager.default.fileExists(atPath: home.path(".not-boring-notch").path),
                     "\(name): nothing else was written either")
        let removal = home.uninstall([.claudeCode])
        checkInstall(home.read(home.settings) == text, "\(name): uninstall leaves it alone too, \(removal)")
    }

    let home = InstallHome()
    defer { home.cleanUp() }
    try! FileManager.default.createDirectory(at: home.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    let latin1 = Data([0x7B, 0x22, 0xE9, 0x22, 0x3A, 0x31, 0x7D])   // {"é":1} in Latin-1, not UTF-8
    try! latin1.write(to: home.settings)
    let report = home.install([.claudeCode])
    checkInstall(report.statuses[0].problem != nil && home.bytes(home.settings) == latin1, "a file that is not UTF-8 is refused untouched")

    // A Codex config.toml this app can't edit safely stops the Codex install before hooks.json is written.
    let codexHome = InstallHome()
    defer { codexHome.cleanUp() }
    codexHome.write("{}\n", to: codexHome.hooks)
    codexHome.write("features = 5\n", to: codexHome.toml)
    let codexReport = codexHome.install([.codex])
    checkInstall(codexReport.statuses[0].problem != nil, "an unsupported config.toml is refused")
    checkInstall(codexHome.read(codexHome.hooks) == "{}\n" && codexHome.read(codexHome.toml) == "features = 5\n", "and nothing changed")

    // One agent failing does not stop the other.
    let both = InstallHome()
    defer { both.cleanUp() }
    both.write("garbage", to: both.settings)
    let mixed = both.install([.claudeCode, .codex])
    checkInstall(mixed.status(of: .claudeCode)?.problem != nil && mixed.status(of: .codex)?.state == .installed,
                 "Codex installs although Claude's file was refused, got \(mixed)")
}

func testRefusesAHomeThatHooksCannotRun() {
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("with space-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let installer = AgentHookInstaller(home: base)
    let report = installer.install([.claudeCode, .codex], script: script)
    checkInstall(report.statuses.allSatisfy { $0.problem != nil && $0.state == .notInstalled }, "a path with a space is refused for both agents")
    checkInstall((try? FileManager.default.contentsOfDirectory(atPath: base.path))?.isEmpty == true, "and nothing is written")
}

func testRefusesAScriptWithoutAVersion() {
    let home = InstallHome()
    defer { home.cleanUp() }
    let report = home.install([.claudeCode], script: "#!/bin/sh\nexit 0\n")
    checkInstall(report.statuses[0].problem != nil && !FileManager.default.fileExists(atPath: home.settings.path), "no version marker, no install")
}

// MARK: - Ownership

func testOnlyOurOwnEntriesAreTouched() {
    let home = InstallHome()
    defer { home.cleanUp() }
    // Entries that mention the name, or run a script of the same name elsewhere, are the user's.
    let others = """
    {
      "hooks": {
        "Stop": [
          { "hooks": [ { "type": "command", "command": "/elsewhere/notch-agent-hook claude-code" } ] },
          { "hooks": [ { "type": "command", "command": "echo \(home.installer.scriptURL.path)" } ] },
          { "hooks": [ { "type": "command", "command": "sh -c 'notch-agent-hook'" } ] }
        ]
      }
    }

    """
    home.write(others, to: home.settings)
    _ = home.install([.claudeCode])
    let stop = (jsonObject(home.read(home.settings)!)["hooks"] as! [String: [Any]])["Stop"]!
    checkInstall(stop.count == 4, "three of the user's and one of ours, got \(stop.count)")
    _ = home.uninstall([.claudeCode])
    checkInstall(home.read(home.settings) == others, "uninstall takes only ours")

    // A stale entry of ours, spelled through /private, is recognised and replaced, not duplicated.
    _ = home.install([.claudeCode])
    let resolved = realpath(home.installer.scriptURL.path, nil)!
    let real = String(cString: resolved)
    free(resolved)
    checkInstall(real != home.installer.scriptURL.path, "the temporary directory is reached through a symlink, so this test means something")
    var text = home.read(home.settings)!
    text = text.replacingOccurrences(of: home.installer.scriptURL.path + " claude-code", with: "\\\"" + real + "\\\" claude-code")
    home.write(text, to: home.settings)
    _ = home.install([.claudeCode])
    let hooks = jsonObject(home.read(home.settings)!)["hooks"] as! [String: [Any]]
    checkInstall(hooks["PreToolUse"]!.count == 1, "no duplicate of ours after a repair")
}

func testAUserCommandInOurGroupIsKept() {
    let home = InstallHome()
    defer { home.cleanUp() }
    _ = home.install([.claudeCode])
    // The user files a command of their own under our Stop group.
    let ours = "{\"type\":\"command\",\"command\":\(JSONSurgeon.quoted(home.installer.scriptURL.path + " claude-code")),\"timeout\":3}"
    let mine = "{ \"type\": \"command\", \"command\": \"say done\" }"
    var text = home.read(home.settings)!
    var surgeon = try! JSONSurgeon(text)
    _ = try! surgeon.removeKey(atPath: ["hooks", "Stop"])
    text = surgeon.text
    surgeon = try! JSONSurgeon(text)
    try! surgeon.appendToArray(atPath: ["hooks", "Stop"], element: "{\"hooks\":[\(ours),\(mine)]}")
    home.write(surgeon.text, to: home.settings)
    checkInstall(home.status(.claudeCode) == .modified, "a group shared with the user's is not ours as written")

    let report = home.installer.report(bundledScript: script)
    _ = home.install(report.needingRepair)
    var stop = (jsonObject(home.read(home.settings)!)["hooks"] as! [String: [[String: Any]]])["Stop"]!
    let commands = stop.flatMap { ($0["hooks"] as! [[String: Any]]).map { $0["command"] as! String } }
    checkInstall(commands.filter { $0 == "say done" }.count == 1, "the repair keeps the user's command, got \(commands)")
    checkInstall(commands.filter { $0.hasSuffix(" claude-code") }.count == 1, "and ours, once, got \(commands)")
    checkInstall(home.status(.claudeCode) == .installed, "and settles")

    _ = home.uninstall([.claudeCode])
    stop = (jsonObject(home.read(home.settings)!)["hooks"] as! [String: [[String: Any]]])["Stop"]!
    let left = stop.flatMap { ($0["hooks"] as! [[String: Any]]).map { $0["command"] as! String } }
    checkInstall(left == ["say done"], "remove takes ours and leaves the user's, got \(left)")
}

// MARK: - Writing safely

func testFollowsASymlinkAndKeepsItsTargetsMode() {
    let home = InstallHome()
    defer { home.cleanUp() }
    let dotfiles = home.path("dotfiles/claude-settings.json")
    home.write("{\n  \"model\": \"opus\"\n}\n", to: dotfiles, mode: 0o600)
    try! FileManager.default.createDirectory(at: home.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! FileManager.default.createSymbolicLink(atPath: home.settings.path, withDestinationPath: "../dotfiles/claude-settings.json")

    _ = home.install([.claudeCode])
    checkInstall((try? FileManager.default.destinationOfSymbolicLink(atPath: home.settings.path)) == "../dotfiles/claude-settings.json",
                 "the symlink is still a symlink")
    checkInstall(home.read(dotfiles)!.contains("notch-agent-hook"), "the file it points at was edited")
    checkInstall(home.mode(dotfiles) == 0o600, "and keeps its mode")
    _ = home.uninstall([.claudeCode])
    checkInstall(home.read(dotfiles) == "{\n  \"model\": \"opus\"\n}\n", "uninstall restores the target's bytes")
}

func testRefusesToWriteOverAFileThatMovedAndUndoesABadWrite() throws {
    let home = InstallHome()
    defer { home.cleanUp() }
    home.write("{\"a\": 1}\n", to: home.settings, mode: 0o640)
    let file = ConfigFile(url: home.settings, backupLabel: "t", backupsDirectory: home.path("b"))

    do {
        try file.replace(original: "{\"a\": 2}\n", with: "{}") { _ in nil }
        checkInstall(false, "a plan made against a different file must not be applied")
    } catch let error as AgentHookError {
        checkInstall(error == .changedSincePlan(path: home.settings.path), "reports that the file moved, got \(error)")
    }
    checkInstall(home.read(home.settings) == "{\"a\": 1}\n", "the file that moved is untouched")

    do {
        try file.replace(original: "{\"a\": 1}\n", with: "{\"a\": 3}\n") { _ in "it looked wrong" }
        checkInstall(false, "a failed check must fail the write")
    } catch let error as AgentHookError {
        checkInstall(error == .validationFailed(path: home.settings.path, reason: "it looked wrong"), "says why, got \(error)")
    }
    checkInstall(home.read(home.settings) == "{\"a\": 1}\n" && home.mode(home.settings) == 0o640,
                 "the original bytes and mode are back after a failed check")
}

func testLaunchRepairsOnlyWhatIsAlreadyInstalled() {
    let home = InstallHome()
    defer { home.cleanUp() }
    checkInstall(home.installer.report(bundledScript: script).needingRepair.isEmpty, "a fresh machine has nothing to repair")

    _ = home.install([.claudeCode])
    checkInstall(home.installer.report(bundledScript: script).needingRepair.isEmpty, "an up-to-date install has nothing to repair")

    let newer = script.replacingOccurrences(of: "notch-agent-hook-version: \(AgentHookScript.version)",
                                            with: "notch-agent-hook-version: \(AgentHookScript.version + 1)")
    let stale = home.installer.report(bundledScript: newer)
    checkInstall(stale.needingRepair == [.claudeCode], "after an app update only the installed agent needs repair, got \(stale.needingRepair)")
    _ = home.install(stale.needingRepair, script: newer)
    checkInstall(home.installer.report(bundledScript: newer).needingRepair.isEmpty, "and the repair settles it")
    checkInstall(!FileManager.default.fileExists(atPath: home.path(".codex").path), "Codex, never installed, was never touched")
}

func testVersionMarkerParsing() {
    checkInstall(AgentHookInstaller.version(of: script) == AgentHookScript.version, "the bundled script's version is read")
    checkInstall(AgentHookInstaller.version(of: "#!/bin/sh\n# notch-agent-hook-version: 12\n") == 12, "a two-digit version")
    checkInstall(AgentHookInstaller.version(of: "#!/bin/sh\necho hi\n") == nil, "no marker, no version")
    checkInstall(AgentHookInstaller.version(of: "#!/bin/sh\n# notch-agent-hook-version: x\n") == nil, "a garbled marker, no version")
}

// MARK: - Agents installed as a file: pi, OpenCode

/// Each agent installed as a file of ours, with a plugin of the user's own beside it.
let pluginTargets: [(target: AgentHookTarget, folder: String, ours: String)] = [
    (.pi, ".pi/agent/extensions", "not-boring-notch.ts"),
    (.opencode, ".config/opencode/plugins", "not-boring-notch.js"),
]

func testAPluginFileIsOneFileOfOurs() {
    for (target, folder, name) in pluginTargets {
        let plugin = AgentPluginFile.of(target)!
        let home = InstallHome()
        defer { home.cleanUp() }
        let file = home.path("\(folder)/\(name)")
        let neighbour = home.path("\(folder)/bark-notify.js")
        home.write("export default function () {}\n", to: neighbour)
        let others = AgentHookTarget.allCases.filter { $0 != target }

        checkInstall(home.installer.status(of: target, bundledScript: script).state == .notInstalled, "\(target): nothing there yet")
        let report = home.install([target])
        checkInstall(report.status(of: target)?.state == .installed, "\(target): installed, got \(String(describing: report.status(of: target)))")
        checkInstall(plugin.path == "\(folder)/\(name)", "\(target): where the user's agent loads it from")
        checkInstall(home.read(file) == plugin.source, "\(target): the file is written as bundled")
        checkInstall(plugin.version(of: plugin.source) == plugin.version, "\(target): and carries its version")
        checkInstall(home.read(file)?.hasPrefix(plugin.versionMarker) == true, "\(target): on its first line")
        checkInstall(!FileManager.default.fileExists(atPath: home.installer.scriptURL.path), "\(target) needs no hook script")
        checkInstall(!FileManager.default.fileExists(atPath: home.path(".claude").path), "Claude Code was not touched")
        for other in others {
            checkInstall(home.installer.status(of: other, bundledScript: script).state == .notInstalled, "\(target) installed does not install \(other)")
        }

        home.write(plugin.source + "// mine\n", to: file)
        checkInstall(home.installer.status(of: target, bundledScript: script).state == .modified, "\(target): an edit is seen")
        home.write(plugin.source.replacingOccurrences(of: "version: \(plugin.version)\n",
                                                      with: "version: \(plugin.version - 1)\n"), to: file)
        let stale = home.installer.report(bundledScript: script)
        checkInstall(stale.status(of: target)?.state == .outdated, "\(target): an older version is seen")
        checkInstall(stale.needingRepair == [target], "\(target): and a launch repairs it")
        _ = home.install([target])
        checkInstall(home.read(file) == plugin.source, "\(target): repaired")

        let removed = home.installer.uninstall([target], bundledScript: script)
        checkInstall(removed.status(of: target)?.state == .notInstalled, "\(target): removed")
        checkInstall(!FileManager.default.fileExists(atPath: file.path), "\(target): the file is gone")
        checkInstall(home.read(neighbour) == "export default function () {}\n", "\(target): the user's own plugin stays")
    }
}

func testAPluginFileLeavesAFileThatIsNotOurs() {
    for (target, folder, name) in pluginTargets {
        let home = InstallHome()
        defer { home.cleanUp() }
        let file = home.path("\(folder)/\(name)")
        let theirs = "// my own notch bridge\nexport default function () {}\n"
        home.write(theirs, to: file)

        let status = home.installer.status(of: target, bundledScript: script)
        checkInstall(status.state == .notInstalled && status.problem != nil, "\(target): not ours, and says so: \(status)")
        let report = home.install([target])
        checkInstall(report.status(of: target)?.problem != nil, "\(target): install refuses")
        _ = home.installer.uninstall([target], bundledScript: script)
        checkInstall(home.read(file) == theirs, "\(target): neither install nor uninstall touched it")
    }
}

func testAPluginFileIsFoundByItsOwnMarkerOnly() {
    // Each agent's marker is its own: pi's file is not mistaken for OpenCode's, nor the reverse.
    let pi = AgentPluginFile.of(.pi)!
    let opencode = AgentPluginFile.of(.opencode)!
    checkInstall(opencode.version(of: pi.source) == nil, "pi's extension is not OpenCode's plugin")
    checkInstall(pi.version(of: opencode.source) == nil, "nor the reverse")
    checkInstall(AgentPluginFile.of(.claudeCode) == nil && AgentPluginFile.of(.codex) == nil,
                 "the agents with a hooks file have no plugin file")
}

@main
enum AgentHookInstallerTests {
    static func main() {
        testVersionMarkerParsing()
        testAPluginFileIsOneFileOfOurs()
        testAPluginFileLeavesAFileThatIsNotOurs()
        testAPluginFileIsFoundByItsOwnMarkerOnly()
        testInstallChangesOnlyOurEntriesAndUninstallRestoresTheBytes()
        testUninstallRestoresTheMeaningWhereBytesCannotBeKept()
        testCodexInstallAndUninstall()
        testInstallCreatesMissingFiles()
        testInstallingOneAgentLeavesTheOtherAlone()
        testReinstallChangesNothing()
        testLaunchRepairsOnlyWhatIsAlreadyInstalled()
        do { try testStatusFollowsWhatHappensToOurEntries() } catch { print("❌ \(error)"); exit(1) }
        testEntriesLookLikeTheDesign()
        testRefusesFilesItCannotEditSafely()
        testRefusesAHomeThatHooksCannotRun()
        testRefusesAScriptWithoutAVersion()
        testOnlyOurOwnEntriesAreTouched()
        testAUserCommandInOurGroupIsKept()
        testFollowsASymlinkAndKeepsItsTargetsMode()
        do { try testRefusesToWriteOverAFileThatMovedAndUndoesABadWrite() } catch { print("❌ \(error)"); exit(1) }
        print("✅ AgentHookInstallerTests passed")
    }
}
