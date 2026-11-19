//
//  AgentNotificationsTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/Channel/Agents/AgentSession.swift NotBoringNotch/Channel/Agents/AgentEvent.swift NotBoringNotch/Channel/Agents/AgentAdapter.swift NotBoringNotch/Channel/Agents/AgentReducer.swift NotBoringNotch/Channel/Agents/AgentStore.swift NotBoringNotch/Channel/Agents/AgentNotifications.swift NotBoringNotch/Channel/Protocol/ChannelNotification.swift
//
//  Helper names are prefixed (`checkAgentNotes*`) so they stay distinguishable from the
//  helpers in the other standalone runners in this folder.
//

import Foundation

func checkAgentNotes<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                                   file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct AgentNotificationsTestsRunner {
    static let now = Date(timeIntervalSince1970: 2_000_000)

    /// Sends hooks through the adapter and the store, and returns the notifications the effects
    /// ask for, in the order they would be delivered.
    static func outcomes(_ hooks: [(name: String, after: TimeInterval, fields: [String: Any])],
                         headers: [String: String] = [:], agent: AgentKind = .claudeCode)
        -> [AgentNotifications.Outcome]
    {
        var store = AgentStore()
        var clock = now
        var result: [AgentNotifications.Outcome] = []
        for hook in hooks {
            clock.addTimeInterval(hook.after)
            var json = hook.fields
            json["hook_event_name"] = hook.name
            json["session_id"] = json["session_id"] ?? "s1"
            json["cwd"] = json["cwd"] ?? "/Users/dev/not-boring-notch"
            let payload = try! JSONSerialization.data(withJSONObject: json)
            guard let envelope = try! AgentAdapter.envelope(agent: agent, payload: payload, headers: headers) else { continue }
            result += store.apply(envelope, now: clock).map { AgentNotifications.outcome(for: $0, now: clock) }
        }
        return result
    }

    static func delivered(_ outcome: AgentNotifications.Outcome) -> ChannelNotification {
        guard case let .deliver(notification) = outcome else {
            print("❌ expected a delivery, got \(outcome)")
            exit(1)
        }
        return notification
    }

    static func main() {
        testAFinishedTurnIsABannerAndAnInboxRow()
        testAShortTurnIsOnlyFiled()
        testAFailedTurnSaysSo()
        testAWaitIsTimeSensitiveAndTakenBackWhenItEnds()
        testAClickGoesToTheSession()
        print("✅ AgentNotificationsTests: all passed")
    }

    static func testAFinishedTurnIsABannerAndAnInboxRow() {
        let result = outcomes([
            ("UserPromptSubmit", 0, [:]),
            ("Stop", 45, ["last_assistant_message": "Added the arbiter.\nDetails follow."]),
        ], headers: ["X-Agent-Host-Bundle": "com.mitchellh.ghostty"])
        checkAgentNotes(result.count, 2, "the prompt takes back any old wait; the Stop announces")
        let note = delivered(result[1])
        checkAgentNotes(note.level, .active, "a turn of 45 seconds earns a banner")
        checkAgentNotes(note.title, "not-boring-notch", "titled with the project")
        checkAgentNotes(note.body, "Added the arbiter.", "the body is the summary")
        checkAgentNotes(note.thread, "claude-code:s1", "threaded by session")
        checkAgentNotes(note.source, "claude-code")
        checkAgentNotes(note.banner, .temporary)
        checkAgentNotes(note.open, .app("com.mitchellh.ghostty"), "a click returns to the terminal's app")
    }

    static func testAShortTurnIsOnlyFiled() {
        let result = outcomes([("UserPromptSubmit", 0, [:]), ("Stop", 9, [:])])
        checkAgentNotes(delivered(result[1]).level, .passive, "nine seconds goes to the Inbox without a banner")
        let atTheLine = outcomes([("UserPromptSubmit", 0, [:]), ("Stop", 10, [:])])
        checkAgentNotes(delivered(atTheLine[1]).level, .active, "ten seconds is long enough")
    }

    static func testAFailedTurnSaysSo() {
        let result = outcomes([("UserPromptSubmit", 0, [:]), ("StopFailure", 30, ["error": "rate_limit"])])
        let note = delivered(result[1])
        checkAgentNotes(note.level, .active)
        checkAgentNotes(note.body, "rate_limit")
        checkAgentNotes(note.icon, .symbol("exclamationmark.triangle.fill"), "and does not wear the success icon")
    }

    static func testAWaitIsTimeSensitiveAndTakenBackWhenItEnds() {
        let result = outcomes([
            ("UserPromptSubmit", 0, [:]),
            ("PermissionRequest", 5, ["tool_name": "Bash"]),
            ("PostToolUse", 20, ["tool_name": "Bash"]),
        ])
        let wait = delivered(result[1])
        checkAgentNotes(wait.id, "agent-wait:claude-code:s1")
        checkAgentNotes(wait.level, .timeSensitive, "the user is needed")
        checkAgentNotes(wait.banner, .untilSeen, "and the banner stays until seen")
        checkAgentNotes(wait.sound, .standard)
        checkAgentNotes(wait.body, "Bash", "which tool wants consent")
        checkAgentNotes(result[2], .withdraw(id: "agent-wait:claude-code:s1"),
                        "approved in the terminal: the same notification is taken back")

        let question = outcomes([("UserPromptSubmit", 0, [:]), ("PreToolUse", 1, ["tool_name": "AskUserQuestion"])])
        checkAgentNotes(delivered(question[1]).body, nil, "a question has no tool to name")
    }

    static func testAClickGoesToTheSession() {
        func target(_ headers: [String: String], agent: AgentKind = .codex) -> ChannelOpenTarget? {
            let result = outcomes([("UserPromptSubmit", 0, [:]), ("Stop", 20, [:])], headers: headers, agent: agent)
            return delivered(result[1]).open
        }
        checkAgentNotes(target(["X-Agent-T3-Thread": "th 1", "X-Agent-T3-Environment": "env-1"]),
                        .url(URL(string: "t3code://threads/env-1/th%201")!), "a T3 thread opens in T3 Code")
        checkAgentNotes(target(["X-Agent-T3-Thread": "th-1"]), .app("com.t3tools.t3code"),
                        "without the environment, the app alone is brought forward")
        checkAgentNotes(target(["X-Agent-Host-Bundle": "com.apple.Terminal"]), .app("com.apple.Terminal"))
        checkAgentNotes(target([:]), nil, "nowhere to go when the host is unknown")
    }
}
