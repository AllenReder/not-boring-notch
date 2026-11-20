//
//  AgentAdapter.swift
//  NotBoringNotch
//
//  Turns what an agent's hook posted into an `AgentEnvelope`: the hook's JSON, untouched, plus the
//  headers the hook script added about its environment. One table per agent says which hook means
//  what; a new agent, or a change to how one names its hooks, is a change to a table and not to
//  anything downstream.
//
//  The Notification subtypes that matter, the tools that ask the user a question, and the traps
//  around them come from CodeStatus (MIT, CodeStatusCore/Domain/AgentEvent.swift) and its spikes.
//

import Foundation

enum AgentAdapterError: Error, Equatable {
    /// The body is not a JSON object.
    case malformed
    /// A hook we understand, without the session it belongs to.
    case missingSessionID
}

enum AgentAdapter {
    /// Nil for a hook the table does not know: a newer agent version may add hooks, and ignoring
    /// them is not an error.
    static func envelope(agent: AgentKind, payload: Data, headers: [String: String]) throws -> AgentEnvelope? {
        guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else {
            throw AgentAdapterError.malformed
        }
        let dialect = dialect(of: agent)
        let hook = Hook(json: json, askUserTools: dialect.askUserTools)

        guard let name = hook.string("hook_event_name"),
              let translate = dialect.events[name],
              let event = translate(hook) else {
            return nil
        }
        guard let sessionID = hook.string("session_id") else {
            throw AgentAdapterError.missingSessionID
        }

        return AgentEnvelope(agent: agent,
                             sessionID: sessionID,
                             subagentID: hook.string("agent_id"),
                             event: event,
                             cwd: hook.string("cwd"),
                             host: host(from: headers),
                             pid: pid(from: headers))
    }

    /// Header names are case-insensitive, and empty values are read as absent.
    private static func value(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.lowercased() == name }.flatMap { $0.value.isEmpty ? nil : $0.value }
    }

    static func pid(from headers: [String: String]) -> Int32? {
        value("x-agent-pid", in: headers).flatMap { Int32($0) }.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The header contract with the hook script: where the session runs. Nil when the poster
    /// named no place at all, as OpenCode's shared service does: it hosts sessions of many
    /// terminals, and says nothing that would be true of them all.
    static func host(from headers: [String: String]) -> AgentHost? {
        func value(_ name: String) -> String? { Self.value(name, in: headers) }
        if let thread = value("x-agent-t3-thread") {
            return .t3Code(threadID: thread, environmentID: value("x-agent-t3-environment"))
        }
        let (bundleID, termProgram, tmuxPane) = (value("x-agent-host-bundle"), value("x-agent-term-program"), value("x-agent-tmux-pane"))
        guard bundleID != nil || termProgram != nil || tmuxPane != nil else { return nil }
        return .app(bundleID: bundleID, termProgram: termProgram, tmuxPane: tmuxPane)
    }

    // MARK: - The tables

    /// How one agent names its hooks.
    private struct Dialect {
        /// Tools whose call is the question itself. Claude Code routes them through the ordinary
        /// permission pipeline, so without this they would read as a command awaiting consent.
        let askUserTools: Set<String>
        let events: [String: (Hook) -> AgentEvent?]
    }

    private static func dialect(of agent: AgentKind) -> Dialect {
        switch agent {
        case .claudeCode: return claudeCode
        case .codex: return codex
        case .pi: return pi
        case .opencode: return opencode
        }
    }

    private static let claudeCode = Dialect(
        askUserTools: ["AskUserQuestion", "ExitPlanMode"],
        events: [
            "SessionStart": { _ in .sessionStarted },
            "UserPromptSubmit": { _ in .promptSubmitted },
            "PreToolUse": { .toolStarted(name: $0.toolName, asksUser: $0.asksUser) },
            "PostToolUse": { .toolFinished(name: $0.toolName) },
            // A tool that failed is still a tool that finished: the turn goes on.
            "PostToolUseFailure": { .toolFinished(name: $0.toolName) },
            "PermissionRequest": { .permissionRequested(tool: $0.toolName, asksUser: $0.asksUser) },
            "Notification": { hook in
                // Only the subtypes that describe this session. `agent_completed` and
                // `agent_needs_input` are about some other agent, and acting on them would mark
                // this session free, or blocked, because a different one changed.
                switch hook.string("notification_type") {
                case "permission_prompt": return .needsAttention(.approval(tool: nil))
                case "elicitation_dialog": return .needsAttention(.question)
                case "idle_prompt": return .wentIdle
                default: return nil
                }
            },
            "Stop": { .turnEnded(summary: $0.summary, failed: false) },
            "StopFailure": { .turnEnded(summary: $0.summary ?? $0.string("error"), failed: true) },
            "SubagentStart": { _ in .subagentStarted },
            "SubagentStop": { _ in .subagentStopped },
            "SessionEnd": { _ in .sessionEnded },
        ])

    private static let codex = Dialect(
        askUserTools: ["request_user_input"],
        events: [
            "SessionStart": { _ in .sessionStarted },
            "UserPromptSubmit": { _ in .promptSubmitted },
            "PreToolUse": { .toolStarted(name: $0.toolName, asksUser: $0.asksUser) },
            "PostToolUse": { .toolFinished(name: $0.toolName) },
            "PermissionRequest": { .permissionRequested(tool: $0.toolName, asksUser: $0.asksUser) },
            "Stop": { .turnEnded(summary: $0.summary, failed: false) },
            "SubagentStart": { _ in .subagentStarted },
            "SubagentStop": { _ in .subagentStopped },
            "Interrupt": { _ in .interrupted },
            "SessionEnd": { _ in .sessionEnded },
        ])

    /// pi's own event names, as `PiExtension` forwards them. pi asks for approval through an
    /// extension's confirm dialog (T3 Code's, in a T3 thread), and for an answer through a select
    /// or an input; `ui_prompt_end` is the user having replied.
    private static let pi = Dialect(
        askUserTools: ["ask_user_question"],
        events: [
            "session_start": { _ in .sessionStarted },
            "agent_start": { _ in .promptSubmitted },
            "tool_execution_start": { .toolStarted(name: $0.toolName, asksUser: $0.asksUser) },
            "tool_execution_end": { .toolFinished(name: $0.toolName) },
            "ui_prompt_start": { hook in
                hook.string("prompt_kind") == "confirm"
                    ? .permissionRequested(tool: hook.toolName, asksUser: hook.asksUser)
                    : .needsAttention(.question)
            },
            "ui_prompt_end": { _ in .toolFinished(name: nil) },
            "agent_settled": { hook in
                if hook.json["aborted"] as? Bool == true { return .interrupted }
                let failed = hook.string("stop_reason") == "error"
                return .turnEnded(summary: failed ? hook.string("error") ?? hook.summary : hook.summary, failed: failed)
            },
            "session_shutdown": { _ in .sessionEnded },
        ])

    /// OpenCode's own event names, as `OpenCodePlugin` forwards them. A sub-agent is a session of
    /// its own: the plugin posts its events under its root's id, with `agent_id` set, and its end
    /// is the sub-agent's, not the turn's. OpenCode asks for approval with `permission.asked`
    /// (answered by `permission.replied`, or by nothing when the turn is interrupted), and for an
    /// answer with a `question` tool, which opens a form.
    private static let opencode = Dialect(
        askUserTools: ["question"],
        events: [
            "session.created": { $0.isSubagent ? .subagentStarted : .sessionStarted },
            "session.execution.started": { _ in .promptSubmitted },
            "tool.execute.before": { .toolStarted(name: $0.toolName, asksUser: $0.asksUser) },
            "tool.execute.after": { .toolFinished(name: $0.toolName) },
            "permission.asked": { .permissionRequested(tool: $0.toolName, asksUser: $0.asksUser) },
            "permission.replied": { _ in .toolFinished(name: nil) },
            "form.created": { $0.string("form_kind") == "question" ? .needsAttention(.question) : nil },
            "form.replied": { _ in .toolFinished(name: nil) },
            "form.cancelled": { _ in .toolFinished(name: nil) },
            "session.execution.succeeded": { $0.isSubagent ? .subagentStopped : .turnEnded(summary: $0.summary, failed: false) },
            "session.execution.failed": { hook in
                hook.isSubagent ? .subagentStopped : .turnEnded(summary: hook.string("error") ?? hook.summary, failed: true)
            },
            "session.execution.interrupted": { $0.isSubagent ? .subagentStopped : .interrupted },
            "session.deleted": { $0.isSubagent ? .subagentStopped : .sessionEnded },
        ])

    // MARK: - Reading a hook

    private struct Hook {
        let json: [String: Any]
        let askUserTools: Set<String>

        /// A non-empty string field.
        func string(_ key: String) -> String? {
            guard let value = json[key] as? String, !value.isEmpty else { return nil }
            return value
        }

        var toolName: String? { string("tool_name") }

        /// Set when the hook fired inside a sub-agent.
        var isSubagent: Bool { string("agent_id") != nil }

        var asksUser: Bool { toolName.map(askUserTools.contains) ?? false }

        /// The first line of what the agent last said: the banner's body.
        var summary: String? {
            guard let message = string("last_assistant_message") else { return nil }
            let line = message.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return line.map { String($0.prefix(300)) }
        }
    }
}
