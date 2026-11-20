//
//  AgentReducer.swift
//  NotBoringNotch
//
//  The state machine: one session and one event in, the session and what the notch should do
//  about it out. Pure. The transition table is the design's (docs/design/agent-first.md), which
//  follows Lookout's `SessionReducer` (MIT, LookoutCore/AgentSession.swift) and the behaviour
//  CodeStatus measured (MIT, docs/spikes/07-blocking-questions.md).
//

import Foundation

/// What a transition asks of the rest of the app.
enum AgentEffect: Equatable {
    /// A turn ended. `duration` is how long it ran; a short one is the Inbox's business only.
    case turnFinished(AgentSession, summary: String?, failed: Bool, duration: TimeInterval)
    /// The session cannot go on without the user.
    case needsYou(AgentSession, AgentWait)
    /// Whatever was asked of the user for this session no longer stands: take its notification back.
    case calmed(AgentSessionKey)
}

enum AgentReducer {
    /// A working session no event has touched for this long, and whose process cannot be found,
    /// is taken to have stopped without saying so.
    static let staleAfter: TimeInterval = 15 * 60

    static func reduce(_ session: AgentSession?, _ envelope: AgentEnvelope, now: Date)
        -> (session: AgentSession?, effects: [AgentEffect])
    {
        var s = session ?? AgentSession(key: envelope.key, agent: envelope.agent, sessionID: envelope.sessionID,
                                        host: envelope.host ?? .unknown, cwd: envelope.cwd, process: nil, phase: .idle,
                                        turnStartedAt: nil, updatedAt: now, subagents: [], waitingSubagent: nil,
                                        threadTitle: nil, lastTurn: nil)
        let before = s.phase
        var effects: [AgentEffect] = []

        if case .sessionEnded = envelope.event, envelope.subagentID == nil {
            return (nil, [.calmed(s.key)])
        }

        s.observe(envelope, now: now)

        // A sub-agent's own events say it is alive and nothing about its parent, except that a
        // request of its own has been answered when it carries on. Its permission requests and
        // notifications are the exceptions: they need the user, whoever raised them.
        if let subagent = envelope.subagentID, !envelope.event.concernsParentFromSubagent {
            switch envelope.event {
            case .subagentStopped, .turnEnded: s.subagents.remove(subagent)
            default: s.subagents.insert(subagent)
            }
            if s.waitingSubagent == subagent, before.wait != nil {
                s.phase = .working(tool: nil)
                s.waitingSubagent = nil
                effects.append(.calmed(s.key))
            }
            return (s, effects)
        }

        func wait(_ newWait: AgentWait) {
            enterTurn(&s, now: now)
            s.phase = .waiting(newWait)
            s.waitingSubagent = envelope.subagentID
            if before.wait != newWait { effects.append(.needsYou(s, newWait)) }
        }
        func work(_ tool: String?) {
            enterTurn(&s, now: now)
            s.phase = .working(tool: tool)
            s.waitingSubagent = nil
        }
        func calm() {
            if !effects.contains(.calmed(s.key)) { effects.append(.calmed(s.key)) }
        }

        switch envelope.event {
        case .sessionStarted, .subagentStarted, .subagentStopped:
            break

        case .promptSubmitted:
            s.subagents = []
            // OpenCode starts another execution of the session when a background sub-agent
            // reports back. The turn the user is waiting on began with the first.
            if !s.turnEndHeld { s.turnStartedAt = now }
            s.turnEndHeld = false
            work(nil)
            calm()

        case let .toolStarted(name, asksUser):
            if asksUser {
                wait(.question)
            } else if before.wait == nil {
                // A tool starting while another waits for consent does not end the wait.
                work(name)
            }

        case let .permissionRequested(tool, asksUser):
            wait(asksUser ? .question : .approval(tool: tool))

        case let .needsAttention(newWait):
            // Claude repeats a permission request as a Notification some six seconds later: the
            // same fact, late.
            if before.wait == nil { wait(newWait) }

        case let .toolFinished(name):
            // Another tool, run alongside the one waiting for consent, finishing does not end the
            // wait. Only a wait whose tool is known can tell the two apart.
            if case let .approval(waitingOn?) = before.wait, let name, name != waitingOn { break }
            work(nil)

        case .wentIdle:
            // Claude says so only when nothing is loading and no dialog is on screen, so a session
            // that was waiting is not any more: the user dismissed the prompt with Esc.
            if before != .idle {
                goIdle(&s)
                calm()
            }

        case let .turnEnded(summary, failed):
            // A turn that failed is over, whatever else is running. Otherwise the turn is not over
            // while a sub-agent is still going.
            guard failed || s.subagents.isEmpty else {
                s.turnEndHeld = true
                break
            }
            let duration = s.turnStartedAt.map { now.timeIntervalSince($0) } ?? 0
            // A stray end, from an idle session, leaves the last turn as it was.
            let lastTurn = before == .idle ? s.lastTurn : (failed ? .failed : .finished)
            goIdle(&s)
            s.lastTurn = lastTurn
            if before.isWorking {
                effects.append(.turnFinished(s, summary: summary, failed: failed, duration: duration))
            }

        case .interrupted:
            goIdle(&s)
            calm()

        case .sessionEnded:
            break
        }

        // Whatever the event, leaving a wait takes its notification back.
        if before.wait != nil, s.phase.wait == nil { calm() }
        return (s, effects)
    }

    /// A session that is about to be working, or waiting, is in a turn from now on.
    private static func enterTurn(_ s: inout AgentSession, now: Date) {
        if s.turnStartedAt == nil { s.turnStartedAt = now }
        s.lastTurn = nil
    }

    private static func goIdle(_ s: inout AgentSession) {
        s.lastTurn = nil
        s.phase = .idle
        s.turnStartedAt = nil
        s.turnEndHeld = false
        s.subagents = []
        s.waitingSubagent = nil
    }
}

private extension AgentSession {
    /// Takes in what the event says about where and who the session is.
    mutating func observe(_ envelope: AgentEnvelope, now: Date) {
        updatedAt = now
        if let host = envelope.host { self.host = host }
        if let cwd = envelope.cwd { self.cwd = cwd }
        if let pid = envelope.pid, pid != process?.pid {
            process = AgentProcess(pid: pid, startedAt: nil)
        }
    }
}

private extension AgentEvent {
    /// Events that act on the parent session even when a sub-agent raised them.
    var concernsParentFromSubagent: Bool {
        switch self {
        case .permissionRequested, .needsAttention: return true
        default: return false
        }
    }
}
