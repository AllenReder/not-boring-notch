//
//  AgentNotifications.swift
//  NotBoringNotch
//
//  What the reducer's effects look like to the rest of the notch: ordinary notifications, through
//  the pipeline every sender's notifications take, and the place a click on one goes.
//
//  The rhythm — a turn that ends is news, one that ended in seconds is only filed — follows
//  CodeIsland's AttentionPolicy (MIT, CodeIslandCore/AttentionPolicy.swift).
//

import Foundation

extension AgentSession {
    /// Where a click on the session goes: its T3 thread, or the app that holds it.
    var jumpTarget: ChannelOpenTarget? {
        switch host {
        case let .t3Code(threadID, environmentID):
            // Without the environment the thread cannot be named, so the app has to do.
            guard let environmentID, let url = Self.t3CodeURL(environmentID: environmentID, threadID: threadID) else {
                return .app(AgentNotifications.t3CodeBundleID)
            }
            return .url(url)
        case let .app(bundleID, _, _):
            return bundleID.map(ChannelOpenTarget.app)
        }
    }

    static func t3CodeURL(environmentID: String, threadID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "t3code"
        components.host = "threads"
        components.percentEncodedPath = "/" + [environmentID, threadID].map(Self.encodeSegment).joined(separator: "/")
        return components.url
    }

    private static func encodeSegment(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? segment
    }
}

enum AgentNotifications {
    static let t3CodeBundleID = "com.t3tools.t3code"

    /// A turn that ran shorter than this goes to the Inbox without a banner: the user was
    /// probably still looking.
    static let shortTurn: TimeInterval = 10

    enum Outcome: Equatable {
        case deliver(ChannelNotification)
        case withdraw(id: String)
    }

    /// One notification per session for a wait, one for a finished turn; a newer one of the same
    /// kind replaces the older in place.
    static func waitID(_ key: AgentSessionKey) -> String { "agent-wait:" + key.raw }
    static func doneID(_ key: AgentSessionKey) -> String { "agent-done:" + key.raw }

    static func outcome(for effect: AgentEffect, now: Date) -> Outcome {
        switch effect {
        case let .turnFinished(session, summary, failed, duration):
            return .deliver(ChannelNotification(
                id: doneID(session.key),
                source: session.agent.rawValue,
                thread: session.key.raw,
                level: duration < shortTurn ? .passive : .active,
                icon: .agent(session.agent, failed ? .failed : .finished),
                title: title(of: session),
                subtitle: failed ? String(localized: "Failed") : String(localized: "Finished"),
                body: summary,
                duration: ChannelNotification.defaultDuration,
                banner: .temporary,
                sound: .none,
                open: session.jumpTarget,
                actions: [],
                deliveredAt: now))

        case let .needsYou(session, wait):
            let subtitle: String
            var body: String?
            switch wait {
            case let .approval(tool):
                subtitle = String(localized: "Needs your approval")
                body = tool
            case .question:
                subtitle = String(localized: "Has a question for you")
            }
            return .deliver(ChannelNotification(
                id: waitID(session.key),
                source: session.agent.rawValue,
                thread: session.key.raw,
                level: .timeSensitive,
                icon: .agent(session.agent, .waiting),
                title: title(of: session),
                subtitle: subtitle,
                body: body,
                duration: ChannelNotification.defaultDuration,
                banner: .untilSeen,
                sound: .none,
                open: session.jumpTarget,
                actions: [],
                deliveredAt: now))

        case let .calmed(key):
            return .withdraw(id: waitID(key))
        }
    }

    /// The project's name; the agent's when the directory is not known.
    private static func title(of session: AgentSession) -> String {
        session.projectName.isEmpty ? session.agent.displayName : session.projectName
    }
}

extension AgentKind {
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}
