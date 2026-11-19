//
//  AgentHooksModels.swift
//
//  What the helper reports about the agents' hooks. It travels over XPC as JSON, so the app and
//  the helper each hold a copy of this file, and Tests/AgentHooksModelsSyncTests.sh fails when the
//  two differ:
//
//      NotBoringNotchXPCHelper/AgentHooks/AgentHooksModels.swift
//      NotBoringNotch/Agents/Hooks/AgentHooksModels.swift
//

import Foundation

/// An agent whose hooks the app can install. The raw values are the agent names the bridge
/// script and the Notch Channel route use.
enum AgentHookTarget: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case pi
}

enum AgentHookState: String, Codable, Sendable {
    /// None of our entries are in the agent's config.
    case notInstalled
    /// Every entry is as this version would write it, and the script is current.
    case installed
    /// Entries of ours are there, but the script or the config was changed or is broken.
    case modified
    /// Entries of ours are there and intact, but written by an older version.
    case outdated
    /// Entries of ours are there, but the agent's own switch for hooks is off (Codex's
    /// `features.hooks = false`). The user's choice: a launch leaves it, and only the user turns it on.
    case turnedOff
}

struct AgentHookStatus: Codable, Equatable, Sendable {
    var agent: AgentHookTarget
    var state: AgentHookState
    /// For a person, in English: why the state is `modified`, or what an install, an uninstall or
    /// a status check could not do.
    var problem: String?
}

struct AgentHooksReport: Codable, Equatable, Sendable {
    var statuses: [AgentHookStatus]

    func status(of agent: AgentHookTarget) -> AgentHookStatus? {
        statuses.first { $0.agent == agent }
    }

    /// What a launch repairs: agents that have entries of ours which are not as this version
    /// writes them. An agent that is not installed, or whose hooks the user turned off, is left
    /// alone, since installing is the user's to ask for.
    var needingRepair: [AgentHookTarget] {
        statuses.filter { $0.state == .modified || $0.state == .outdated }.map(\.agent)
    }
}

struct CodexTrustReport: Codable, Equatable, Sendable {
    /// How many hooks were newly trusted.
    var trusted: Int
    /// Why nothing was trusted, if that is because something went wrong.
    var problem: String?
}
