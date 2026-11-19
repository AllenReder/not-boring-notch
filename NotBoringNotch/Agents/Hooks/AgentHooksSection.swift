//
//  AgentHooksSection.swift
//  NotBoringNotch
//
//  The settings section for the hooks that report Claude Code, Codex and pi sessions to the notch:
//  a row per agent with where its hooks stand and the button for what the user can do next. It
//  stands on its own, so any settings form can drop it in.
//

import SwiftUI

struct AgentHooksSection: View {
    @ObservedObject private var controller = AgentHooksController.shared

    var body: some View {
        Section {
            ForEach(AgentHookTarget.allCases, id: \.self) { agent in
                AgentHookRow(agent: agent, controller: controller)
            }
            if controller.helperUnreachable {
                Text("Couldn't reach the helper that edits the agents' settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Agent Hooks")
        }
        .task { await controller.refresh() }
    }
}

private struct AgentHookRow: View {
    let agent: AgentHookTarget
    @ObservedObject var controller: AgentHooksController

    private var status: AgentHookStatus? { controller.statuses[agent] }
    private var state: AgentHookState { status?.state ?? .notInstalled }
    private var isBusy: Bool { controller.busy.contains(agent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text(stateText)
                        .font(.caption)
                        .foregroundStyle(state == .modified ? .orange : .secondary)
                    if let problem = status?.problem {
                        // From the helper, in English: what it refused, or what is wrong.
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 20)
                if isBusy { ProgressView().controlSize(.small) }
                if state == .modified || state == .outdated {
                    Button("Repair") { Task { await controller.install(agent) } }
                        .disabled(isBusy)
                }
                if state == .notInstalled {
                    Button("Install") { Task { await controller.install(agent) } }
                        .disabled(isBusy)
                } else {
                    Button("Remove") { Task { await controller.uninstall(agent) } }
                        .disabled(isBusy)
                }
            }

            if agent == .codex, state != .notInstalled {
                codexTrust
            }
        }
    }

    private var codexTrust: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex only runs hooks you have trusted. This asks Codex to trust the ones installed here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let outcome = controller.trustOutcome {
                    switch outcome {
                    case .trusted(let count):
                        Text(count == 0 ? String(localized: "Already trusted.") : String(localized: "Trusted \(count) hooks."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .failed(let problem):
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 20)
            if controller.isTrusting { ProgressView().controlSize(.small) }
            Button("Trust Hooks") { Task { await controller.trustCodex() } }
                .disabled(controller.isTrusting || isBusy)
        }
    }

    private var name: LocalizedStringKey {
        switch agent {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .pi: "Pi"
        }
    }

    private var stateText: LocalizedStringKey {
        switch state {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .modified: "Modified"
        case .outdated: "Outdated"
        }
    }
}
