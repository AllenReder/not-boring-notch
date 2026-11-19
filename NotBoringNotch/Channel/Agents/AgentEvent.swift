//
//  AgentEvent.swift
//  NotBoringNotch
//
//  What an agent's hook said, in the vocabulary the reducer works in. Each agent names its hooks
//  differently; `AgentAdapter` translates, and what is left is this.
//

import Foundation

enum AgentEvent: Equatable {
    case sessionStarted
    case promptSubmitted
    case toolStarted(name: String?, asksUser: Bool)
    case toolFinished
    case permissionRequested(tool: String?, asksUser: Bool)
    /// Claude's `Notification`: permission_prompt, elicitation_dialog.
    case needsAttention(AgentWait)
    /// Claude's `Notification(idle_prompt)`: the recovery signal after an Esc, which fires no Stop.
    case wentIdle
    case turnEnded(summary: String?, failed: Bool)
    /// Codex's `Interrupt`.
    case interrupted
    case sessionEnded
    /// A sub-agent began, or stopped. The envelope's `subagentID` says which.
    case subagentStarted
    case subagentStopped
}

/// An event with the facts the reducer needs about where it came from.
struct AgentEnvelope: Equatable {
    let agent: AgentKind
    let sessionID: String
    /// Set when the hook fired inside a sub-agent.
    let subagentID: String?
    let event: AgentEvent
    let cwd: String?
    let host: AgentHost
    let pid: Int32?

    var key: AgentSessionKey {
        AgentSessionKey(agent: agent, sessionID: sessionID, host: host)
    }
}
