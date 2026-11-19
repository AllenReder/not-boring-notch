//
//  AgentSession.swift
//  NotBoringNotch
//
//  What the notch knows about one Claude Code, Codex or pi session: where it runs, what it is doing,
//  and since when. Plain values; the rules that change them live in `AgentReducer`.
//
//  The shape follows Lookout's `AgentSession` (MIT, LookoutCore/AgentSession.swift), narrowed to
//  what the notch shows.
//

import Foundation

enum AgentKind: String, Codable, CaseIterable {
    case claudeCode = "claude-code"
    case codex
    case pi

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .pi: return "Pi"
        }
    }
}

/// How a session's last turn ended, when it ran to the end.
enum AgentTurnOutcome: Equatable {
    case finished
    case failed
}

/// How a session's turn came out, as the dot on its mark in a banner or the Inbox.
enum AgentBadge: String, Codable {
    case finished
    case failed
    case waiting
}

/// Where a session runs. It decides the session's identity, where a click goes, and what it is
/// called. The hook script reports facts about its environment; this is what they add up to.
enum AgentHost: Equatable {
    /// A thread of T3 Code. `environmentID` is what `t3code://threads/<env>/<thread>` needs, and
    /// is absent when the script could not read it.
    case t3Code(threadID: String, environmentID: String?)
    /// Anything else: a terminal, an editor. `bundleID` is the app that holds it.
    case app(bundleID: String?, termProgram: String?, tmuxPane: String?)
}

/// The agent and its own session id. Not the T3 thread: an agent started from inside a thread (a
/// Claude session that runs `codex exec`, say) inherits the thread's environment, and keyed by the
/// thread it would take over the thread's own session. A thread that moves on to a new agent
/// session leaves the old one to its SessionEnd, or to its process exiting.
struct AgentSessionKey: Hashable {
    let raw: String   // "claude-code:<session_id>"

    init(raw: String) {
        self.raw = raw
    }

    init(agent: AgentKind, sessionID: String) {
        raw = "\(agent.rawValue):\(sessionID)"
    }
}

enum AgentWait: Equatable {
    /// It wants permission to run a tool.
    case approval(tool: String?)
    /// It asked the user something, or wants a plan reviewed.
    case question
}

enum AgentPhase: Equatable {
    case idle
    case working(tool: String?)
    case waiting(AgentWait)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var wait: AgentWait? {
        if case let .waiting(wait) = self { return wait }
        return nil
    }
}

/// The agent's process, for noticing that it has gone.
struct AgentProcess: Equatable {
    let pid: Int32
    /// When the process started, learned the first time it is seen alive. A later reading that
    /// differs means the pid now belongs to someone else.
    var startedAt: Date?
}

struct AgentSession: Equatable {
    let key: AgentSessionKey
    let agent: AgentKind
    /// The agent's own id. For a T3 thread it changes when the thread starts a new agent session.
    let sessionID: String
    var host: AgentHost
    var cwd: String?
    var process: AgentProcess?
    var phase: AgentPhase
    /// Set while the session is not idle.
    var turnStartedAt: Date?
    /// The last time any hook reported on this session.
    var updatedAt: Date
    /// Sub-agents seen working. They never change the phase of their parent.
    var subagents: Set<String>
    /// The sub-agent whose permission request or question the session is waiting on, so that its
    /// carrying on can end the wait.
    var waitingSubagent: String?
    /// The title of the T3 thread it runs in, once T3 Code has said.
    var threadTitle: String?
    /// How the last turn ended, while the session is idle after it. Nil after an interrupt, and
    /// before the first turn.
    var lastTurn: AgentTurnOutcome?

    /// The last segment of the working directory.
    var projectName: String {
        guard let cwd else { return "" }
        return cwd.split(separator: "/").last.map(String.init) ?? cwd
    }

    var t3ThreadID: String? {
        if case let .t3Code(threadID, _) = host { return threadID }
        return nil
    }

    /// What the session is called: its T3 thread's title, else its folder, else its agent.
    var title: String {
        threadTitle ?? (projectName.isEmpty ? agent.displayName : projectName)
    }

    /// The folder, after a thread's title. Nil when the title is the folder already.
    var titleDetail: String? {
        threadTitle != nil && !projectName.isEmpty ? projectName : nil
    }
}

/// What the closed notch and its arbiter need to know, in one value.
struct AgentSummary: Equatable {
    var working = 0
    var waiting = 0
    /// The kinds of agent that are working or waiting, in a stable order.
    var kinds: [AgentKind] = []
    /// The kind with the most sessions working or waiting, the first in `kinds` on a tie. Unlike
    /// `mostUrgent`, it does not change hands each time another session is heard from.
    var leadKind: AgentKind?
    /// The session most worth the user's glance: one that is waiting, else one at work, the most
    /// recently heard from first.
    var mostUrgent: AgentSession?

    var isEmpty: Bool { working + waiting == 0 }
}
