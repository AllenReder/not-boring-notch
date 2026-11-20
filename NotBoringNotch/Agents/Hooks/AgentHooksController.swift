//
//  AgentHooksController.swift
//  NotBoringNotch
//
//  What the settings section shows and does about the hooks (and the pi extension and the
//  OpenCode plugin) that report agent sessions to the notch. The sandboxed app can't touch
//  ~/.claude, ~/.codex, ~/.pi, ~/.config/opencode or ~/.not-boring-notch, so every action goes to
//  the XPC helper; this holds the answer.
//

import Combine
import Foundation

@MainActor
final class AgentHooksController: ObservableObject {
    static let shared = AgentHooksController()

    /// The last status the helper reported, per agent. Empty until the first answer.
    @Published private(set) var statuses: [AgentHookTarget: AgentHookStatus] = [:]
    /// Agents with an install, a removal or a status check in flight.
    @Published private(set) var busy: Set<AgentHookTarget> = []
    @Published private(set) var isTrusting = false
    @Published private(set) var trustOutcome: TrustOutcome?
    /// Set when the helper could not be reached at all.
    @Published private(set) var helperUnreachable = false

    enum TrustOutcome: Equatable {
        case trusted(Int)
        case failed(String)
    }

    /// Set once the user has trusted our Codex hooks, so a repair that rewrites them asks Codex
    /// to trust the new entries too: trust is a hash of the entry, and a repair changes it.
    private static let codexTrustedKey = "agentHooks.codexTrusted"

    private let client = XPCHelperClient.shared

    // MARK: - Actions

    func refresh() async {
        guard let report = await client.agentHooksStatus(hookScript: AgentHookScript.source) else {
            helperUnreachable = true
            return
        }
        apply(report)
    }

    func install(_ agent: AgentHookTarget) async {
        await run(agent) {
            await self.client.installAgentHooks([agent], hookScript: AgentHookScript.source)
        }
    }

    func uninstall(_ agent: AgentHookTarget) async {
        await run(agent) {
            await self.client.uninstallAgentHooks([agent], hookScript: AgentHookScript.source)
        }
        if agent == .codex { trustOutcome = nil }
    }

    func trustCodex() async {
        isTrusting = true
        defer { isTrusting = false }
        guard let report = await client.trustCodexHooks() else {
            helperUnreachable = true
            return
        }
        helperUnreachable = false
        if let problem = report.problem {
            trustOutcome = .failed(problem)
        } else {
            trustOutcome = .trusted(report.trusted)
            UserDefaults.standard.set(true, forKey: Self.codexTrustedKey)
        }
    }

    /// At launch: brings the agents that are already installed up to date, and leaves every
    /// other agent alone. Installing is something the user asks for, never something launch does.
    func repairInstalledAgents() {
        Task {
            guard let report = await client.agentHooksStatus(hookScript: AgentHookScript.source) else { return }
            apply(report)
            let stale = report.needingRepair
            guard !stale.isEmpty,
                  let repaired = await client.installAgentHooks(stale, hookScript: AgentHookScript.source)
            else { return }
            apply(repaired)
            if stale.contains(.codex), UserDefaults.standard.bool(forKey: Self.codexTrustedKey) {
                await trustCodex()
            }
        }
    }

    // MARK: - Private

    private func run(_ agent: AgentHookTarget, _ action: () async -> AgentHooksReport?) async {
        busy.insert(agent)
        defer { busy.remove(agent) }
        guard let report = await action() else {
            helperUnreachable = true
            return
        }
        apply(report)
    }

    private func apply(_ report: AgentHooksReport) {
        helperUnreachable = false
        for status in report.statuses { statuses[status.agent] = status }
    }
}
