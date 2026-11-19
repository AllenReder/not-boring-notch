//
//  AgentReducerTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/Channel/Agents/AgentSession.swift NotBoringNotch/Channel/Agents/AgentEvent.swift NotBoringNotch/Channel/Agents/AgentAdapter.swift NotBoringNotch/Channel/Agents/AgentReducer.swift NotBoringNotch/Channel/Agents/AgentStore.swift
//
//  Hooks go in as the JSON an agent posts and come out as phases and effects, so the adapter
//  tables and the reducer are tested together, the way the app uses them. The two turn fixtures
//  (Tests/Fixtures/agents/claude-turn.jsonl, codex-turn.jsonl) are real hook payloads, from
//  Lookout (MIT, Tests/LookoutCoreTests/Fixtures).
//
//  Helper names are prefixed (`checkAgents*`) so they stay distinguishable from the
//  helpers in the other standalone runners in this folder.
//

import Foundation

func checkAgents(_ condition: Bool, _ message: String = "",
                 file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkAgents<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                               file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

// MARK: - Describing what happened

func agentsDescribe(_ effects: [AgentEffect]) -> [String] {
    effects.map { effect in
        switch effect {
        case let .turnFinished(_, summary, failed, duration):
            return "finished(\(summary ?? "-"),\(failed ? "failed" : "ok"),\(Int(duration))s)"
        case let .needsYou(_, wait):
            return "needs(\(agentsDescribe(wait)))"
        case .calmed:
            return "calmed"
        }
    }
}

func agentsDescribe(_ wait: AgentWait) -> String {
    switch wait {
    case let .approval(tool): return "approval:\(tool ?? "-")"
    case .question: return "question"
    }
}

func agentsDescribe(_ phase: AgentPhase) -> String {
    switch phase {
    case .idle: return "idle"
    case let .working(tool): return tool.map { "working:\($0)" } ?? "working"
    case let .waiting(wait): return "waiting:" + agentsDescribe(wait)
    }
}

// MARK: - A store, a clock, and hooks to feed them

struct AgentsRig {
    var store = AgentStore()
    var now = Date(timeIntervalSince1970: 1_000_000)
    var agent: AgentKind = .claudeCode
    var headers: [String: String] = [:]

    /// Sends a hook and returns what the app would be asked to do about it.
    @discardableResult
    mutating func send(_ name: String, session: String = "s1", after seconds: TimeInterval = 1,
                       _ fields: [String: Any] = [:]) -> [String] {
        now.addTimeInterval(seconds)
        guard let envelope = try! AgentAdapter.envelope(agent: agent, payload: Self.payload(name, session, fields),
                                                        headers: headers) else {
            return ["ignored"]
        }
        return agentsDescribe(store.apply(envelope, now: now))
    }

    static func payload(_ name: String, _ session: String, _ fields: [String: Any]) -> Data {
        var json = fields
        json["hook_event_name"] = name
        json["session_id"] = session
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func phase(_ session: String = "s1") -> String {
        let key = AgentSessionKey(agent: agent, sessionID: session, host: AgentAdapter.host(from: headers))
        return store.sessions[key].map { agentsDescribe($0.phase) } ?? "gone"
    }
}

func agentsRig(_ agent: AgentKind = .claudeCode, headers: [String: String] = [:]) -> AgentsRig {
    var rig = AgentsRig()
    rig.agent = agent
    rig.headers = headers
    return rig
}

// MARK: - The tests

@main
struct AgentReducerTestsRunner {
    static func main() {
        testReplayingAClaudeTurn()
        testReplayingACodexTurn()
        testHooksTheTableDoesNotKnowAreIgnored()
        testPayloadsThatAreNotHooksAreRefused()
        testHeadersSayWhereTheSessionRuns()
        testATurnStartsWorkingAndEndsIdle()
        testAPermissionPromptSixSecondsLateIsTheSameWait()
        testAPermissionPromptAloneStillWaits()
        testAQuestionToolWaitsForAnAnswer()
        testAToolStartingDuringAWaitDoesNotEndIt()
        testFinishingAToolEndsTheWait()
        testIdlePromptRecoversOnlyAWorkingSession()
        testAFailedToolIsStillWorking()
        testStopOnlyAnnouncesATurnThatWasWorking()
        testAFailedTurnIsAnnouncedAsFailed()
        testSubagentsLeaveTheirParentAlone()
        testASubagentsRequestNeedsTheUserAndItsAnswerEndsTheWait()
        testTheTurnIsNotOverWhileASubagentRuns()
        testInterruptAndSessionEnd()
        testAT3ThreadIsOneSessionWhateverTheAgentCallsIt()
        testTurnDurationIsMeasured()
        testTheSummaryCountsWhatIsActive()
        testSweepRemovesWhatHasExited()
        testSweepSettlesAWorkingSessionThatWentQuiet()
        print("✅ AgentReducerTests: all passed")
    }

    // MARK: Replaying real turns

    static func fixture(_ name: String) -> [Data] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/agents/\(name)")
        let text = try! String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map { Data($0.utf8) }
    }

    static func replay(_ agent: AgentKind, _ name: String, tool: String) {
        var rig = agentsRig(agent)
        var phases: [String] = []
        var effects: [[String]] = []
        for line in fixture(name) {
            rig.now.addTimeInterval(2)
            let envelope = try! AgentAdapter.envelope(agent: agent, payload: line, headers: [:])!
            effects.append(agentsDescribe(rig.store.apply(envelope, now: rig.now)))
            phases.append(rig.phase(envelope.sessionID))
        }
        checkAgents(phases, ["idle", "working", "working:\(tool)", "working", "idle", "gone"],
                    "\(name): the phase after each hook")
        checkAgents(effects, [[], ["calmed"], [], [], ["finished(done,ok,6s)"], ["calmed"]],
                    "\(name): only the end of the turn is announced")
        checkAgents(rig.store.summary.isEmpty, "\(name): nothing is left running")
    }

    static func testReplayingAClaudeTurn() { replay(.claudeCode, "claude-turn.jsonl", tool: "Bash") }

    static func testReplayingACodexTurn() { replay(.codex, "codex-turn.jsonl", tool: "Bash") }

    // MARK: The adapter

    static func testHooksTheTableDoesNotKnowAreIgnored() {
        var rig = agentsRig()
        checkAgents(rig.send("PreCompact"), ["ignored"], "a hook nobody registered for")
        // Claude's fleet-view watcher says these about some other agent. Acting on them would mark
        // this session free, or blocked, because a different one changed.
        checkAgents(rig.send("Notification", ["notification_type": "agent_completed"]), ["ignored"],
                    "agent_completed is about another session")
        checkAgents(rig.send("Notification", ["notification_type": "agent_needs_input"]), ["ignored"],
                    "agent_needs_input is about another session")
        checkAgents(rig.send("Notification", ["notification_type": "auth_success"]), ["ignored"],
                    "a subtype the table does not list")
        checkAgents(rig.send("Notification"), ["ignored"], "a notification with no subtype")
        checkAgents(rig.phase(), "gone", "none of them created a session")

        var codex = agentsRig(.codex)
        checkAgents(codex.send("Notification", ["notification_type": "permission_prompt"]), ["ignored"],
                    "Codex has no Notification hook")
        checkAgents(codex.send("StopFailure"), ["ignored"], "nor StopFailure")
    }

    static func testPayloadsThatAreNotHooksAreRefused() {
        func refusal(_ data: Data) -> AgentAdapterError? {
            do {
                _ = try AgentAdapter.envelope(agent: .claudeCode, payload: data, headers: [:])
                return nil
            } catch {
                return error as? AgentAdapterError
            }
        }
        checkAgents(refusal(Data("{ not json".utf8)), .malformed, "not JSON")
        checkAgents(refusal(Data("[1,2]".utf8)), .malformed, "JSON that is not an object")
        checkAgents(refusal(Data(#"{"hook_event_name":"Stop"}"#.utf8)), .missingSessionID,
                    "a hook without its session")
        checkAgents(refusal(Data(#"{"hook_event_name":"Stop","session_id":""}"#.utf8)), .missingSessionID,
                    "an empty session id")
    }

    static func testHeadersSayWhereTheSessionRuns() {
        func host(_ headers: [String: String]) -> AgentHost {
            try! AgentAdapter.envelope(agent: .claudeCode, payload: AgentsRig.payload("Stop", "s1", [:]),
                                       headers: headers)!.host
        }
        checkAgents(host(["X-Agent-T3-Thread": "th-1", "X-Agent-T3-Environment": "env-1", "X-Agent-Host-Bundle": "com.t3tools.t3code"]),
                    .t3Code(threadID: "th-1", environmentID: "env-1"), "a T3 thread, whatever app hosts it")
        checkAgents(host(["x-agent-t3-thread": "th-1"]), .t3Code(threadID: "th-1", environmentID: nil),
                    "a T3 thread whose environment could not be read; header names are case-insensitive")
        checkAgents(host(["X-Agent-Host-Bundle": "com.mitchellh.ghostty", "X-Agent-Term-Program": "ghostty", "X-Agent-Tmux-Pane": "%3"]),
                    .app(bundleID: "com.mitchellh.ghostty", termProgram: "ghostty", tmuxPane: "%3"), "a terminal")
        checkAgents(host(["X-Agent-T3-Thread": "", "X-Agent-Host-Bundle": ""]),
                    .app(bundleID: nil, termProgram: nil, tmuxPane: nil), "empty values are absent values")
        checkAgents(host([:]), .app(bundleID: nil, termProgram: nil, tmuxPane: nil), "no headers at all")

        func pid(_ value: String) -> Int32? {
            try! AgentAdapter.envelope(agent: .codex, payload: AgentsRig.payload("Stop", "s1", [:]),
                                       headers: ["X-Agent-Pid": value])!.pid
        }
        checkAgents(pid("4242"), 4242, "the agent's pid")
        checkAgents(pid("abc"), nil, "a pid that is not a number")
        checkAgents(pid("0"), nil, "pid 0 is nobody")
        checkAgents(pid("-5"), nil, "nor is a negative one")

        let envelope = try! AgentAdapter.envelope(
            agent: .claudeCode, payload: AgentsRig.payload("Stop", "s1", ["cwd": "/Users/dev/project", "agent_id": "sub-1"]),
            headers: [:])!
        checkAgents(envelope.cwd, "/Users/dev/project", "the working directory")
        checkAgents(envelope.subagentID, "sub-1", "a hook that fired inside a sub-agent says so")
        checkAgents(envelope.key.raw, "claude-code:s1", "outside T3 the key is the agent and its session id")
        let t3 = try! AgentAdapter.envelope(agent: .codex, payload: AgentsRig.payload("Stop", "s9", [:]),
                                            headers: ["X-Agent-T3-Thread": "th-7"])!
        checkAgents(t3.key.raw, "t3:th-7", "inside T3 the key is the thread")

        func summary(_ fields: [String: Any]) -> String? {
            let e = try! AgentAdapter.envelope(agent: .claudeCode, payload: AgentsRig.payload("Stop", "s1", fields), headers: [:])!
            if case let .turnEnded(summary, _) = e.event { return summary }
            return nil
        }
        checkAgents(summary(["last_assistant_message": "Fixed it.\nMore detail below."]), "Fixed it.",
                    "the summary is the first line")
        checkAgents(summary(["last_assistant_message": "\n\n  Hello  \nbye"]), "Hello", "leading blank lines do not count")
        checkAgents(summary([:]), nil, "no message, no summary")
        checkAgents(summary(["last_assistant_message": ""]), nil, "an empty message, no summary")
    }

    // MARK: The reducer

    static func testATurnStartsWorkingAndEndsIdle() {
        var rig = agentsRig()
        checkAgents(rig.send("SessionStart"), [], "a session starting says nothing")
        checkAgents(rig.phase(), "idle")
        rig.send("SessionStart")
        checkAgents(rig.phase(), "idle", "starting again changes nothing")

        rig.send("UserPromptSubmit")
        checkAgents(rig.phase(), "working")
        rig.send("SessionStart")
        checkAgents(rig.phase(), "working", "a SessionStart (after /compact, say) does not end a turn")
        rig.send("PreToolUse", ["tool_name": "Edit"])
        checkAgents(rig.phase(), "working:Edit", "the tool at work")
        rig.send("PostToolUse", ["tool_name": "Edit"])
        checkAgents(rig.phase(), "working", "the tool is done")
    }

    static func testAPermissionPromptSixSecondsLateIsTheSameWait() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PreToolUse", ["tool_name": "Bash"])
        checkAgents(rig.send("PermissionRequest", ["tool_name": "Bash"]), ["needs(approval:Bash)"],
                    "the request asks the user")
        checkAgents(rig.phase(), "waiting:approval:Bash")
        checkAgents(rig.send("Notification", after: 6, ["notification_type": "permission_prompt"]), [],
                    "the same fact six seconds later neither notifies again nor changes the wait")
        checkAgents(rig.phase(), "waiting:approval:Bash", "and does not forget which tool")
        checkAgents(rig.send("Notification", ["notification_type": "elicitation_dialog"]), [],
                    "nor does any other notification while it waits")
        checkAgents(rig.phase(), "waiting:approval:Bash")
    }

    static func testAPermissionPromptAloneStillWaits() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        checkAgents(rig.send("Notification", ["notification_type": "permission_prompt"]), ["needs(approval:-)"],
                    "with no request before it, the prompt is news")
        checkAgents(rig.phase(), "waiting:approval:-")

        var dialog = agentsRig()
        dialog.send("UserPromptSubmit")
        checkAgents(dialog.send("Notification", ["notification_type": "elicitation_dialog"]), ["needs(question)"],
                    "an elicitation dialog is a question")
        checkAgents(dialog.phase(), "waiting:question")
    }

    static func testAQuestionToolWaitsForAnAnswer() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        checkAgents(rig.send("PreToolUse", ["tool_name": "AskUserQuestion"]), ["needs(question)"],
                    "the call is the question, not a command awaiting consent")
        checkAgents(rig.phase(), "waiting:question")
        checkAgents(rig.send("PermissionRequest", after: 0.003, ["tool_name": "AskUserQuestion"]), [],
                    "the permission request that follows it is the same wait")
        checkAgents(rig.phase(), "waiting:question")

        var plan = agentsRig()
        plan.send("UserPromptSubmit")
        checkAgents(plan.send("PermissionRequest", ["tool_name": "ExitPlanMode"]), ["needs(question)"],
                    "a plan to review is asked as a question")

        var codex = agentsRig(.codex)
        codex.send("UserPromptSubmit")
        checkAgents(codex.send("PreToolUse", ["tool_name": "request_user_input"]), ["needs(question)"],
                    "Codex's question tool")
        var other = agentsRig(.codex)
        other.send("UserPromptSubmit")
        checkAgents(other.send("PreToolUse", ["tool_name": "AskUserQuestion"]), [],
                    "each agent's table lists its own question tools")
    }

    static func testAToolStartingDuringAWaitDoesNotEndIt() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PermissionRequest", ["tool_name": "Bash"])
        checkAgents(rig.send("PreToolUse", ["tool_name": "Read"]), [], "another tool starting says nothing new")
        checkAgents(rig.phase(), "waiting:approval:Bash", "the session is still waiting for consent")
    }

    static func testFinishingAToolEndsTheWait() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PermissionRequest", ["tool_name": "Bash"])
        checkAgents(rig.send("PostToolUse", ["tool_name": "Bash"]), ["calmed"],
                    "approved in the terminal: the notification is taken back")
        checkAgents(rig.phase(), "working")
        checkAgents(rig.send("PostToolUse", ["tool_name": "Read"]), [], "a tool finishing outside a wait calms nothing")
    }

    static func testIdlePromptRecoversOnlyAWorkingSession() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PreToolUse", ["tool_name": "Bash"])
        checkAgents(rig.send("Notification", after: 60, ["notification_type": "idle_prompt"]), ["calmed"],
                    "an Esc fires no Stop; the idle prompt is how the session is known to be free, and it is not news")
        checkAgents(rig.phase(), "idle")
        checkAgents(rig.send("Notification", ["notification_type": "idle_prompt"]), [], "from idle it changes nothing")
        checkAgents(rig.phase(), "idle")

        var waiting = agentsRig()
        waiting.send("UserPromptSubmit")
        waiting.send("PermissionRequest", ["tool_name": "Bash"])
        checkAgents(waiting.send("Notification", ["notification_type": "idle_prompt"]), [],
                    "a session waiting for consent is not idle")
        checkAgents(waiting.phase(), "waiting:approval:Bash")
    }

    static func testAFailedToolIsStillWorking() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PreToolUse", ["tool_name": "Bash"])
        checkAgents(rig.send("PostToolUseFailure", ["tool_name": "Bash"]), [], "a failing command is not news")
        checkAgents(rig.phase(), "working", "the turn goes on")
    }

    static func testStopOnlyAnnouncesATurnThatWasWorking() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        checkAgents(rig.send("Stop", after: 20, ["last_assistant_message": "All done"]), ["finished(All done,ok,20s)"],
                    "a turn that was working is announced")
        checkAgents(rig.phase(), "idle")
        checkAgents(rig.send("Stop"), [], "a second Stop announces nothing")

        var recovered = agentsRig()
        recovered.send("UserPromptSubmit")
        recovered.send("Notification", ["notification_type": "idle_prompt"])
        checkAgents(recovered.send("Stop"), [], "nor does one after the idle prompt already settled the turn")

        var denied = agentsRig()
        denied.send("UserPromptSubmit")
        denied.send("PermissionRequest", ["tool_name": "Bash"])
        checkAgents(denied.send("Stop"), ["calmed"],
                    "the user refused: no announcement, and the request's notification is taken back")
        checkAgents(denied.phase(), "idle")

        var fresh = agentsRig()
        checkAgents(fresh.send("Stop"), [], "a Stop from a session the notch never saw start")
        checkAgents(fresh.phase(), "idle")
    }

    static func testAFailedTurnIsAnnouncedAsFailed() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        checkAgents(rig.send("StopFailure", after: 15, ["error": "rate_limit", "last_assistant_message": "API Error: rate limited"]),
                    ["finished(API Error: rate limited,failed,15s)"], "a failed turn")
        checkAgents(rig.phase(), "idle")

        var bare = agentsRig()
        bare.send("UserPromptSubmit")
        checkAgents(bare.send("StopFailure", ["error": "rate_limit"]), ["finished(rate_limit,failed,1s)"],
                    "with no message, the error says why")
    }

    static func testSubagentsLeaveTheirParentAlone() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PreToolUse", ["tool_name": "Task"])
        checkAgents(rig.send("PreToolUse", ["tool_name": "Grep", "agent_id": "sub-1"]), [], "a sub-agent's tool")
        checkAgents(rig.phase(), "working:Task", "does not change what the parent is doing")
        checkAgents(rig.send("PostToolUse", ["tool_name": "Grep", "agent_id": "sub-1"]), [], "or finish the parent's")
        checkAgents(rig.phase(), "working:Task")

        rig.send("PermissionRequest", ["tool_name": "Bash"])
        checkAgents(rig.send("PostToolUse", ["tool_name": "Grep", "agent_id": "sub-1"]), [],
                    "a sub-agent carrying on does not answer the parent's own wait")
        checkAgents(rig.phase(), "waiting:approval:Bash")

        var other = agentsRig()
        other.send("UserPromptSubmit")
        other.send("PreToolUse", ["tool_name": "Read", "agent_id": "sub-1"])
        checkAgents(other.send("Stop", ["agent_id": "sub-1"]), [], "a sub-agent's Stop is not the parent's")
        checkAgents(other.phase(), "working")
    }

    static func testASubagentsRequestNeedsTheUserAndItsAnswerEndsTheWait() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PreToolUse", ["tool_name": "Bash", "agent_id": "sub-1"])
        checkAgents(rig.send("PermissionRequest", ["tool_name": "Bash", "agent_id": "sub-1"]), ["needs(approval:Bash)"],
                    "a sub-agent's permission request needs the user as much as the parent's")
        checkAgents(rig.phase(), "waiting:approval:Bash")
        checkAgents(rig.send("Notification", ["notification_type": "permission_prompt", "agent_id": "sub-1"]), [],
                    "and its notification is the same wait")

        checkAgents(rig.send("PostToolUse", ["tool_name": "Bash", "agent_id": "sub-2"]), [],
                    "a different sub-agent working says nothing about it")
        checkAgents(rig.phase(), "waiting:approval:Bash")
        checkAgents(rig.send("PostToolUse", ["tool_name": "Bash", "agent_id": "sub-1"]), ["calmed"],
                    "the sub-agent carries on, so it was answered")
        checkAgents(rig.phase(), "working")
    }

    static func testTheTurnIsNotOverWhileASubagentRuns() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("SubagentStart", ["agent_id": "sub-1", "agent_type": "Explore"])
        checkAgents(rig.send("Stop", after: 30), [], "the parent stopped while a sub-agent goes on")
        checkAgents(rig.phase(), "working", "so it is still working")
        checkAgents(rig.send("SubagentStop", ["agent_id": "sub-1"]), [], "the sub-agent finishing is not a turn ending")
        checkAgents(rig.phase(), "working")
        checkAgents(rig.send("Stop", after: 5, ["last_assistant_message": "Report"]), ["finished(Report,ok,37s)"],
                    "the next Stop, with nothing left running, ends it")
        checkAgents(rig.phase(), "idle")

        var next = agentsRig()
        next.send("UserPromptSubmit")
        next.send("PreToolUse", ["tool_name": "Read", "agent_id": "sub-1"])
        next.send("UserPromptSubmit")
        checkAgents(next.send("Stop"), ["finished(-,ok,1s)"], "a new prompt forgets the sub-agents of the old turn")

        var failed = agentsRig()
        failed.send("UserPromptSubmit")
        failed.send("PreToolUse", ["tool_name": "Read", "agent_id": "sub-1"])
        checkAgents(failed.send("StopFailure", ["error": "server_error"]), ["finished(server_error,failed,2s)"],
                    "a turn that failed is over, whatever else is running")
        checkAgents(failed.phase(), "idle")
    }

    static func testInterruptAndSessionEnd() {
        var rig = agentsRig(.codex)
        rig.send("UserPromptSubmit")
        rig.send("PermissionRequest", ["tool_name": "Bash"])
        checkAgents(rig.send("Interrupt"), ["calmed"], "an interrupt is not a turn finishing")
        checkAgents(rig.phase(), "idle")

        rig.send("UserPromptSubmit")
        checkAgents(rig.send("SessionEnd"), ["calmed"], "the session ended")
        checkAgents(rig.phase(), "gone", "and the notch forgets it")
        checkAgents(rig.send("SessionEnd"), ["calmed"], "ending what is already gone is harmless")

        var again = agentsRig()
        again.send("UserPromptSubmit")
        checkAgents(again.send("UserPromptSubmit"), ["calmed"], "a prompt withdraws any request left over from before a restart")
    }

    static func testAT3ThreadIsOneSessionWhateverTheAgentCallsIt() {
        var rig = agentsRig(.claudeCode, headers: ["X-Agent-T3-Thread": "th-1", "X-Agent-T3-Environment": "env-1"])
        rig.send("SessionStart", session: "first")
        rig.send("UserPromptSubmit", session: "first")
        checkAgents(rig.store.sessions.count, 1)

        // The thread starts a new agent session, as it does after /clear or a resume.
        rig.send("SessionStart", session: "second")
        checkAgents(rig.store.sessions.count, 1, "the new agent session is the same thread")
        checkAgents(rig.phase(), "idle", "and a fresh session begins idle")

        rig.send("UserPromptSubmit", session: "second")
        checkAgents(rig.send("SessionEnd", session: "first"), [],
                    "the old session ending late does not end the thread's new one")
        checkAgents(rig.phase(), "working")

        rig.agent = .codex
        rig.send("UserPromptSubmit", session: "codex-1")
        let session = rig.store.sessions.values.first!
        checkAgents(session.agent, .codex, "the thread now runs Codex")
        checkAgents(session.key.raw, "t3:th-1")
        checkAgents(session.host, .t3Code(threadID: "th-1", environmentID: "env-1"))
        checkAgents(rig.store.sessions.count, 1)

        checkAgents(rig.send("SessionEnd", session: "codex-1"), ["calmed"], "the current session ending ends the thread's")
        checkAgents(rig.store.sessions.count, 0)
    }

    static func testTurnDurationIsMeasured() {
        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        rig.send("PreToolUse", ["tool_name": "Bash"])
        rig.send("PermissionRequest", ["tool_name": "Bash"])
        rig.send("PostToolUse", after: 40, ["tool_name": "Bash"])
        checkAgents(rig.send("Stop", after: 59), ["finished(-,ok,101s)"],
                    "from the prompt to the Stop, a wait included")
        rig.send("UserPromptSubmit", after: 600)
        checkAgents(rig.send("Stop", after: 2), ["finished(-,ok,2s)"], "the next turn is timed from its own prompt")

        // Seen first in the middle of a turn, as after the notch restarted.
        var late = agentsRig()
        late.send("PreToolUse", ["tool_name": "Bash"])
        checkAgents(late.send("Stop", after: 8), ["finished(-,ok,8s)"], "measured from when the notch first heard of it")
    }

    // MARK: The store

    static func testTheSummaryCountsWhatIsActive() {
        var rig = agentsRig(.claudeCode, headers: ["X-Agent-Host-Bundle": "com.apple.Terminal"])
        checkAgents(rig.store.summary.isEmpty, "no sessions, nothing to show")

        rig.send("SessionStart", session: "idle-one")
        rig.send("UserPromptSubmit", session: "a", ["cwd": "/Users/dev/alpha"])
        rig.send("UserPromptSubmit", session: "b", ["cwd": "/Users/dev/beta"])
        rig.agent = .codex
        rig.send("UserPromptSubmit", session: "c", ["cwd": "/Users/dev/gamma"])
        rig.send("PermissionRequest", session: "c", ["tool_name": "Bash"])

        let summary = rig.store.summary
        checkAgents(summary.working, 2, "two are working")
        checkAgents(summary.waiting, 1, "one is waiting")
        checkAgents(summary.kinds, [.claudeCode, .codex], "both agents are at work")
        checkAgents(summary.mostUrgent?.projectName, "gamma", "whoever waits is the one to look at")
        checkAgents(rig.store.ordered.map(\.projectName), ["gamma", "beta", "alpha", ""],
                    "waiting first, then working newest first, then idle")

        var one = agentsRig(.codex)
        one.send("UserPromptSubmit")
        checkAgents(one.store.summary.kinds, [.codex], "a single kind")
        checkAgents(one.store.summary.mostUrgent?.phase, .working(tool: nil), "with nobody waiting, the one at work")
    }

    static func testSweepRemovesWhatHasExited() {
        var rig = agentsRig(.claudeCode, headers: ["X-Agent-Pid": "100"])
        rig.send("UserPromptSubmit", session: "a")
        rig.send("PermissionRequest", session: "a", ["tool_name": "Bash"])
        rig.headers = ["X-Agent-Pid": "200"]
        rig.send("UserPromptSubmit", session: "b")
        rig.headers = [:]
        rig.send("UserPromptSubmit", session: "c")
        checkAgents(rig.store.pids.sorted(), [100, 200], "the pids worth asking about")

        let started100 = Date(timeIntervalSince1970: 500)
        let started200 = Date(timeIntervalSince1970: 600)
        var effects = rig.store.sweep(alive: [100: started100, 200: started200], now: rig.now)
        checkAgents(agentsDescribe(effects), [], "everything is there")
        checkAgents(rig.store.sessions.count, 3)

        effects = rig.store.sweep(alive: [100: started100, 200: started200], now: rig.now)
        checkAgents(rig.store.sessions.count, 3, "and still there on the next look")

        effects = rig.store.sweep(alive: [100: started100], now: rig.now)
        checkAgents(agentsDescribe(effects), ["calmed"], "the process of b exited")
        checkAgents(rig.phase("b"), "gone")
        checkAgents(rig.phase("c"), "working", "a session with no pid is not judged by its process")

        // The pid was reused by an unrelated process that started later.
        effects = rig.store.sweep(alive: [100: Date(timeIntervalSince1970: 9_999)], now: rig.now)
        checkAgents(agentsDescribe(effects), ["calmed"], "a reused pid is not the agent")
        checkAgents(rig.phase("a"), "gone", "even when it was waiting")

        var unknown = agentsRig(.claudeCode, headers: ["X-Agent-Pid": "100"])
        unknown.send("UserPromptSubmit")
        checkAgents(agentsDescribe(unknown.store.sweep(alive: nil, now: unknown.now)), [],
                    "when liveness cannot be told, nothing is removed")
        checkAgents(unknown.phase(), "working")
    }

    static func testSweepSettlesAWorkingSessionThatWentQuiet() {
        let quarterHour: TimeInterval = 15 * 60

        var rig = agentsRig()
        rig.send("UserPromptSubmit")
        checkAgents(agentsDescribe(rig.store.sweep(alive: [:], now: rig.now.addingTimeInterval(quarterHour - 5))), [],
                    "not yet")
        checkAgents(rig.phase(), "working")
        checkAgents(agentsDescribe(rig.store.sweep(alive: [:], now: rig.now.addingTimeInterval(quarterHour + 1))), ["calmed"],
                    "quiet for a quarter of an hour with no process to be found: it stopped, silently")
        checkAgents(rig.phase(), "idle", "idle, and with no turn finished to announce")

        var waiting = agentsRig()
        waiting.send("UserPromptSubmit")
        waiting.send("PermissionRequest", ["tool_name": "Bash"])
        checkAgents(agentsDescribe(waiting.store.sweep(alive: [:], now: waiting.now.addingTimeInterval(3 * quarterHour))), [],
                    "a session waiting for the user waits as long as it takes")
        checkAgents(waiting.phase(), "waiting:approval:Bash")

        var alive = agentsRig(.claudeCode, headers: ["X-Agent-Pid": "100"])
        alive.send("UserPromptSubmit")
        let started = Date(timeIntervalSince1970: 500)
        _ = alive.store.sweep(alive: [100: started], now: alive.now)
        checkAgents(agentsDescribe(alive.store.sweep(alive: [100: started], now: alive.now.addingTimeInterval(2 * quarterHour))), [],
                    "a long command in a process that is still there is not a stall")
        checkAgents(alive.phase(), "working")

        var unknown = agentsRig(.claudeCode, headers: ["X-Agent-Pid": "100"])
        unknown.send("UserPromptSubmit")
        checkAgents(agentsDescribe(unknown.store.sweep(alive: nil, now: unknown.now.addingTimeInterval(quarterHour + 1))), ["calmed"],
                    "with liveness unknown, quiet alone settles it")
    }
}
