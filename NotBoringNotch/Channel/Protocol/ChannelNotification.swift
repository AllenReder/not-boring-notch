//
//  ChannelNotification.swift
//  NotBoringNotch
//
//  One notification delivered to the notch through the Notch Channel, and the two wire formats
//  that produce it: v1 (`POST /reminder`, kept for existing senders) and v2
//  (`POST /v2/notifications`). Decoding lives here, off AppKit and off the network, so the
//  payload contract can be exercised on its own.
//
//  The split follows iOS: the sender supplies content and intent (an interruption level, where a
//  click should go), and the notch decides how to present it. How long a banner stays is the
//  notch's call, not the sender's — v1's `sticky` survives only as a request to stay until seen.
//

import Foundation

struct ChannelNotification: Codable, Equatable, Hashable, Identifiable {
    /// The largest request body the channel accepts. It bounds memory, not content: a long body
    /// is kept whole and scrolled when drawn, never cut at the door.
    static let maximumPayloadBytes = 64 * 1024

    /// How long a banner stays in the closed notch when its sender does not say.
    static let defaultDuration: TimeInterval = 4

    /// The durations a sender may ask for. A banner is a moment, not a fixture: past a minute it
    /// is the Inbox's job. Asking outside the range gets the nearest end of it, not a refusal.
    static let durationRange: ClosedRange<TimeInterval> = 1 ... 60

    /// A sender's requested duration, or the default, kept within `durationRange`.
    static func duration(_ requested: TimeInterval?) -> TimeInterval {
        guard let requested, requested.isFinite else { return defaultDuration }
        return min(durationRange.upperBound, max(durationRange.lowerBound, requested))
    }

    /// How many buttons a notification may carry besides its default action.
    static let maximumActions = 3

    let id: String
    /// Who sent it, for grouping and, later, per-source settings. Free-form, sender-chosen.
    let source: String?
    /// Notifications from one source that belong together, such as one agent session.
    let thread: String?
    let level: ChannelInterruptionLevel
    let icon: ChannelIcon?
    let title: String
    let subtitle: String?
    /// Markdown. Inline syntax is rendered; anything else is shown as written.
    let body: String?
    /// Seconds the banner stays in the closed notch.
    let duration: TimeInterval
    let banner: ChannelBannerPersistence
    let sound: ChannelSound
    /// What clicking the notification does — iOS's default action.
    let open: ChannelOpenTarget?
    let actions: [ChannelAction]
    /// When the notch received it. A replacement under the same id is a new delivery.
    let deliveredAt: Date

    // MARK: - v1: POST /reminder

    /// Decodes a v1 Reminder Channel request body, the format the channel shipped with.
    ///
    /// Fields the sender omits take their defaults; fields we do not know are ignored, so a newer
    /// sender does not break an older notch. Anything we would have to guess at — an icon kind we
    /// cannot draw, a sound we do not have — is refused rather than drawn blank.
    static func decodeV1(_ data: Data, now: Date = Date()) throws -> ChannelNotification {
        let payload: V1Payload = try decodePayload(data)

        return ChannelNotification(
            id: nonEmpty(payload.id) ?? UUID().uuidString,
            source: nil,
            thread: nil,
            level: .active,
            icon: try payload.icon.map(decodeIcon),
            title: try requireTitle(payload.title),
            subtitle: nonEmpty(payload.subtitle),
            body: nonEmpty(payload.body),
            duration: duration(payload.duration),
            banner: (payload.sticky ?? false) ? .untilSeen : .temporary,
            sound: try decodeSound(payload.sound),
            open: nil,
            actions: try payload.action.map { [try decodeV1Action($0)] } ?? [],
            deliveredAt: now
        )
    }

    // MARK: - v2: POST /v2/notifications

    /// Decodes a v2 notification. The same leniency as v1: unknown fields are ignored, unknown
    /// values for known fields are refused.
    static func decode(_ data: Data, now: Date = Date()) throws -> ChannelNotification {
        let payload: V2Payload = try decodePayload(data)

        let actions = payload.actions ?? []
        guard actions.count <= maximumActions else { throw ChannelPayloadError.tooManyActions }

        return ChannelNotification(
            id: nonEmpty(payload.id) ?? UUID().uuidString,
            source: nonEmpty(payload.source),
            thread: nonEmpty(payload.thread),
            level: try decodeLevel(payload.level),
            icon: try payload.icon.map(decodeIcon),
            title: try requireTitle(payload.title),
            subtitle: nonEmpty(payload.subtitle),
            body: nonEmpty(payload.body),
            duration: duration(payload.duration),
            banner: .temporary,
            sound: try decodeSound(payload.sound),
            open: try payload.open.map(decodeOpen),
            actions: try actions.map(decodeAction),
            deliveredAt: now
        )
    }

    // MARK: - Shared decoding

    static func decodePayload<Payload: Decodable>(_ data: Data) throws -> Payload {
        guard data.count <= maximumPayloadBytes else { throw ChannelPayloadError.tooLarge }
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ChannelPayloadError.malformed
        }
    }

    static func requireTitle(_ title: String?) throws -> String {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw ChannelPayloadError.missingTitle
        }
        return title
    }

    static func decodeIcon(_ icon: WireIcon) throws -> ChannelIcon {
        switch icon.kind {
        case "sf_symbol":
            return .symbol(icon.value)
        case "png_base64":
            guard let data = Data(base64Encoded: icon.value), !data.isEmpty else {
                throw ChannelPayloadError.invalidIconData
            }
            return .image(data)
        case "app_bundle":
            return .appBundle(icon.value)
        case let kind:
            throw ChannelPayloadError.unknownIconKind(kind)
        }
    }

    static func decodeSound(_ sound: String?) throws -> ChannelSound {
        switch sound {
        case nil, "none":
            return .none
        case "default":
            return .standard
        case let sound?:
            throw ChannelPayloadError.unknownSound(sound)
        }
    }

    static func decodeLevel(_ level: String?) throws -> ChannelInterruptionLevel {
        switch level {
        case nil:
            return .active
        case let level?:
            guard let known = ChannelInterruptionLevel(rawValue: level) else {
                throw ChannelPayloadError.unknownLevel(level)
            }
            return known
        }
    }

    /// A URL the system can hand to something: it has a scheme. `URL(string: "://nope")` is not
    /// nil, it is a URL with an empty scheme, so parsing alone does not prove that.
    static func openableURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme, !scheme.isEmpty else {
            return nil
        }
        return url
    }

    static func decodeOpen(_ open: WireOpen) throws -> ChannelOpenTarget {
        switch (nonEmpty(open.url), nonEmpty(open.app)) {
        case let (url?, nil):
            guard let url = openableURL(url) else { throw ChannelPayloadError.invalidOpen }
            return .url(url)
        case let (nil, app?):
            return .app(app)
        default:
            // Neither, or both: either way we would be guessing which one the sender meant.
            throw ChannelPayloadError.invalidOpen
        }
    }

    private static func decodeAction(_ action: WireAction) throws -> ChannelAction {
        guard let title = nonEmpty(action.title?.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ChannelPayloadError.invalidAction
        }
        switch (action.url, action.copy) {
        case let (url?, nil):
            guard let url = openableURL(url) else { throw ChannelPayloadError.invalidAction }
            return ChannelAction(title: title, kind: .url(url))
        case let (nil, text?):
            return ChannelAction(title: title, kind: .copy(text))
        default:
            throw ChannelPayloadError.invalidAction
        }
    }

    private static func decodeV1Action(_ action: V1Payload.Action) throws -> ChannelAction {
        guard !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = openableURL(action.url) else {
            throw ChannelPayloadError.invalidAction
        }
        return ChannelAction(title: action.title, kind: .url(url))
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Wire shapes

    struct WireIcon: Decodable, Equatable {
        let kind: String
        let value: String
    }

    struct WireOpen: Decodable, Equatable {
        let url: String?
        let app: String?
    }

    private struct WireAction: Decodable {
        let title: String?
        let url: String?
        let copy: String?
    }

    private struct V1Payload: Decodable {
        struct Action: Decodable {
            let title: String
            let url: String
        }

        let id: String?
        let icon: WireIcon?
        let title: String?
        let subtitle: String?
        let body: String?
        let duration: TimeInterval?
        let sticky: Bool?
        let sound: String?
        let action: Action?
    }

    private struct V2Payload: Decodable {
        let id: String?
        let source: String?
        let thread: String?
        let level: String?
        let icon: WireIcon?
        let title: String?
        let subtitle: String?
        let body: String?
        let duration: TimeInterval?
        let sound: String?
        let open: WireOpen?
        let actions: [WireAction]?
    }
}

enum ChannelPayloadError: Error, Equatable {
    /// The request body is larger than `ChannelNotification.maximumPayloadBytes`.
    case tooLarge
    /// The body is not JSON, or a known field has the wrong type.
    case malformed
    /// No non-empty title, which is the one field a notification cannot do without.
    case missingTitle
    case unknownIconKind(String)
    /// A `png_base64` icon whose value is not decodable base64.
    case invalidIconData
    case unknownSound(String)
    case unknownLevel(String)
    /// An action missing a title, or not exactly one of a usable URL and text to copy.
    case invalidAction
    case tooManyActions
    /// An `open` that is not exactly one of a usable URL and an app's bundle identifier.
    case invalidOpen

    /// The code a sender is told, stable across releases.
    var code: String {
        switch self {
        case .tooLarge: return "too_large"
        case .malformed: return "malformed"
        case .missingTitle: return "missing_title"
        case .unknownIconKind: return "unknown_icon_kind"
        case .invalidIconData: return "invalid_icon_data"
        case .unknownSound: return "unknown_sound"
        case .unknownLevel: return "unknown_level"
        case .invalidAction: return "invalid_action"
        case .tooManyActions: return "too_many_actions"
        case .invalidOpen: return "invalid_open"
        }
    }
}

/// How much a notification may interrupt — iOS's `UNNotificationInterruptionLevel`, without
/// `critical`, which no script has a claim to.
enum ChannelInterruptionLevel: String, Codable, Equatable, Hashable {
    /// Straight to the Inbox. No banner, no sound.
    case passive
    /// A banner in turn.
    case active
    /// A banner ahead of everything waiting, shown even while fullscreen hides the notch.
    case timeSensitive = "time-sensitive"
}

/// How long a banner holds the closed notch.
enum ChannelBannerPersistence: String, Codable, Equatable, Hashable {
    /// Its duration, then it gives way.
    case temporary
    /// Past its duration for as long as nothing else is waiting, until the user has seen it.
    case untilSeen
}

enum ChannelIcon: Codable, Equatable, Hashable {
    /// An SF Symbol name. An unresolvable name falls back to the notch's own bell.
    case symbol(String)
    /// PNG bytes carried in the request, because a sandboxed notch cannot read the sender's path.
    case image(Data)
    /// An installed application's bundle identifier, whose icon the notch looks up itself.
    case appBundle(String)
    /// An agent's mark with a dot for how its turn came out. Only the notch's own agent
    /// notifications wear it: the wire has no kind that decodes to it.
    case agent(AgentKind, AgentBadge)
}

enum ChannelSound: String, Codable, Equatable, Hashable {
    case none
    /// The notch's own alert sound, `notch.m4a`.
    case standard
}

/// Where a click takes the user.
enum ChannelOpenTarget: Codable, Equatable, Hashable {
    case url(URL)
    /// An application, brought forward or launched, by bundle identifier.
    case app(String)
}

struct ChannelAction: Codable, Equatable, Hashable {
    enum Kind: Codable, Equatable, Hashable {
        case url(URL)
        /// Text placed on the pasteboard, such as a command or a commit hash.
        case copy(String)
    }

    let title: String
    let kind: Kind
}

extension ChannelNotification {
    /// What a click on the notification does: the sender's `open`, or, when it named none but its
    /// icon is an app, that app. Nil when a click has nowhere to go.
    var clickTarget: ChannelOpenTarget? {
        if let open { return open }
        if case let .appBundle(identifier) = icon { return .app(identifier) }
        return nil
    }
}
