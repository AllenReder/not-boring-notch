//
//  ChannelActivity.swift
//  NotBoringNotch
//
//  Something in progress that a sender keeps the notch informed about — an agent session, a build,
//  a download, a timer — and the wire format that updates it. iOS's Live Activity, on a loopback
//  port.
//
//  A notification says something happened; an activity says something is happening. So an
//  activity stays on the closed notch while it lasts, changes in place and silently when it is
//  updated, and only leaves a notification behind — in the Inbox — when it ends. An update that
//  should get the user's attention says so with an `alert`, which is delivered as a notification
//  of its own.
//
//      PUT    /v2/activities/{id}        start it, or update it
//      POST   /v2/activities/{id}/end    end it: show how it ended, then leave a notification
//      DELETE /v2/activities/{id}        remove it at once, leaving nothing behind
//
//  Updates are merges, not replacements: a field left out keeps its value and `null` clears it.
//  That is what lets a stateless sender — a shell hook that runs once per event — say only what
//  changed ("now waiting for input") without knowing what it said before. And starting and
//  updating are the same request, so a sender never has to know whether the notch already has the
//  activity, and an activity lost to a restart comes back on the sender's next update.
//
//  Decoding lives here, off AppKit and off the network, like `ChannelNotification`'s.
//

import Foundation

struct ChannelActivity: Equatable, Identifiable {
    /// Where an activity ranks among the others when its sender does not say.
    static let defaultRelevance = 0.5
    /// How long an activity may go without an update before it is drawn as stale: its sender may
    /// have died without ending it, and what it shows may no longer be true.
    static let defaultStaleAfter: TimeInterval = 15 * 60
    /// How long an activity may last at all. Past this it is removed whatever its sender thinks.
    static let maximumLifetime: TimeInterval = 8 * 60 * 60
    /// How long an ended activity stays on the closed notch, showing how it ended.
    static let defaultDismissAfter: TimeInterval = 4

    let id: String
    var source: String?
    var icon: ChannelIcon?
    var title: String?
    /// What it is doing right now: "Editing 3 files", "Waiting for input".
    var state: String?
    /// 0...1, or nil when the sender has no measure of it.
    var progress: Double?
    var timer: ActivityTimer?
    /// 0...1. Decides which activity gets the closed notch when there are several.
    var relevance: Double = defaultRelevance
    var staleAfter: TimeInterval = defaultStaleAfter
    var open: ChannelOpenTarget?
    private(set) var startedAt: Date
    var updatedAt: Date
    var endedAt: Date?
    /// When an ended activity leaves the closed notch.
    var dismissAt: Date?

    init(id: String, startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = startedAt
    }

    /// What it is called on screen. A sender that never gave a title is still named.
    var displayTitle: String { title ?? source ?? id }

    var isEnded: Bool { endedAt != nil }

    /// Not updated for longer than its sender said it would go without one.
    func isStale(at now: Date) -> Bool {
        !isEnded && now.timeIntervalSince(updatedAt) > staleAfter
    }

    /// What clicking it does: its `open`, or the app its icon names.
    var clickTarget: ChannelOpenTarget? {
        if let open { return open }
        if case let .appBundle(identifier) = icon { return .app(identifier) }
        return nil
    }

    /// The id of the notification an activity's alerts and its outcome are filed under. One per
    /// activity: each alert replaces the last, and the outcome replaces the last alert.
    static func notificationID(for id: String) -> String { "activity:\(id)" }

    mutating func apply(_ update: ActivityUpdate, now: Date) {
        update.source.apply(to: &source)
        update.icon.apply(to: &icon)
        update.title.apply(to: &title)
        update.state.apply(to: &state)
        update.progress.apply(to: &progress)
        update.timer.apply(to: &timer)
        update.open.apply(to: &open)
        switch update.relevance {
        case .keep: break
        case .clear: relevance = Self.defaultRelevance
        case let .set(value): relevance = value
        }
        switch update.staleAfter {
        case .keep: break
        case .clear: staleAfter = Self.defaultStaleAfter
        case let .set(value): staleAfter = value
        }
        updatedAt = now
        // An update after the end is the id being used again: it is in progress once more, with a
        // lifetime of its own rather than whatever was left of the last one's.
        if isEnded { startedAt = now }
        endedAt = nil
        dismissAt = nil
    }

    mutating func end(_ ending: ActivityEnding, now: Date) {
        endedAt = now
        dismissAt = now.addingTimeInterval(ending.dismissAfter)
    }

    /// An alert, as the notification it is delivered as.
    func notification(for alert: ActivityAlert, now: Date) -> ChannelNotification {
        ChannelNotification(
            id: Self.notificationID(for: id),
            source: source,
            thread: id,
            level: alert.level,
            icon: icon,
            title: alert.title,
            // The banner's right wing names the activity the alert is about, unless the alert
            // says something more specific.
            subtitle: alert.subtitle ?? displayTitle,
            body: alert.body,
            duration: alert.duration,
            banner: .temporary,
            sound: alert.sound,
            open: open,
            actions: [],
            deliveredAt: now
        )
    }

    /// What the Inbox keeps of an activity that ended without an alert: how it ended, quietly.
    func outcome(now: Date) -> ChannelNotification {
        ChannelNotification(
            id: Self.notificationID(for: id),
            source: source,
            thread: id,
            level: .passive,
            icon: icon,
            title: displayTitle,
            subtitle: state,
            body: nil,
            duration: ChannelNotification.defaultDuration,
            banner: .temporary,
            sound: .none,
            open: open,
            actions: [],
            deliveredAt: now
        )
    }
}

enum ActivityTimer: Equatable {
    /// Counting up from a moment: how long it has been running.
    case since(Date)
    /// Counting down to a moment: how long is left.
    case until(Date)
}

/// One field of an update: left as it was, cleared, or set.
enum ActivityField<Value: Equatable>: Equatable {
    case keep
    case clear
    case set(Value)

    func apply(to value: inout Value?) {
        switch self {
        case .keep: break
        case .clear: value = nil
        case let .set(new): value = new
        }
    }
}

/// An update's request for the user's attention, delivered as a notification.
struct ActivityAlert: Equatable {
    var title: String
    var subtitle: String?
    var body: String?
    var level: ChannelInterruptionLevel = .active
    var sound: ChannelSound = .none
    var duration: TimeInterval = ChannelNotification.defaultDuration
}

/// How an activity ends.
struct ActivityEnding: Equatable {
    /// Seconds it stays on the closed notch, showing how it ended. 0 removes it at once.
    var dismissAfter: TimeInterval = ChannelActivity.defaultDismissAfter
    /// Whether it leaves a notification in the Inbox.
    var leavesNotification = true
}

/// A `PUT /v2/activities/{id}` body, or the content part of an `/end` body.
struct ActivityUpdate: Equatable {
    var source: ActivityField<String> = .keep
    var icon: ActivityField<ChannelIcon> = .keep
    var title: ActivityField<String> = .keep
    var state: ActivityField<String> = .keep
    var progress: ActivityField<Double> = .keep
    var timer: ActivityField<ActivityTimer> = .keep
    var relevance: ActivityField<Double> = .keep
    var staleAfter: ActivityField<TimeInterval> = .keep
    var open: ActivityField<ChannelOpenTarget> = .keep
    var alert: ActivityAlert?

    // MARK: - Decoding

    /// Decodes an update. Unknown fields are ignored and unknown values for known fields refused,
    /// as for notifications. Numbers out of range are clamped where there is an obvious nearest
    /// value (`progress` past 1 is done) and refused where there is not (a negative timeout).
    static func decode(_ data: Data) throws -> ActivityUpdate {
        try decodeBody(data).update
    }

    /// Decodes an `/end` body: an update — the activity's last state — and how it should end. An
    /// empty body is an end with nothing more to say.
    static func decodeEnd(_ data: Data) throws -> (update: ActivityUpdate, ending: ActivityEnding) {
        guard !data.isEmpty else { return (ActivityUpdate(), ActivityEnding()) }
        let body = try decodeBody(data)

        var ending = ActivityEnding()
        if let dismissAfter = body.wire.dismissAfter {
            guard dismissAfter >= 0 else { throw ChannelPayloadError.invalidNumber("dismiss_after") }
            ending.dismissAfter = dismissAfter
        }
        if let inbox = body.wire.inbox {
            ending.leavesNotification = inbox
        }
        return (body.update, ending)
    }

    private static func decodeBody(_ data: Data) throws -> (update: ActivityUpdate, wire: WireActivity) {
        let wire: WireActivity = try ChannelNotification.decodePayload(data)
        var update = ActivityUpdate()

        update.source = text(wire.source)
        update.title = text(wire.title)
        update.state = text(wire.state)
        update.icon = try wire.icon.map(ChannelNotification.decodeIcon)
        update.open = try wire.open.map(ChannelNotification.decodeOpen)
        update.progress = wire.progress.map { min(1, max(0, $0)) }
        update.relevance = wire.relevance.map { min(1, max(0, $0)) }
        update.staleAfter = try wire.staleAfter.map { seconds in
            guard seconds > 0 else { throw ChannelPayloadError.invalidNumber("stale_after") }
            return seconds
        }
        update.timer = try wire.timer.map { timer in
            switch (timer.since, timer.until) {
            case let (since?, nil): return .since(Date(timeIntervalSince1970: since))
            case let (nil, until?): return .until(Date(timeIntervalSince1970: until))
            default: throw ChannelPayloadError.invalidTimer
            }
        }
        update.alert = try wire.alert.map { alert in
            var decoded = ActivityAlert(title: try ChannelNotification.requireTitle(alert.title))
            decoded.subtitle = ChannelNotification.nonEmpty(alert.subtitle)
            decoded.body = ChannelNotification.nonEmpty(alert.body)
            decoded.level = try ChannelNotification.decodeLevel(alert.level)
            decoded.sound = try ChannelNotification.decodeSound(alert.sound)
            decoded.duration = ChannelNotification.duration(alert.duration)
            return decoded
        }
        return (update, wire)
    }

    /// Text, where an empty or blank string means the same as `null`: nothing to show.
    private static func text(_ field: ActivityField<String>) -> ActivityField<String> {
        guard case let .set(value) = field else { return field }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .clear : .set(trimmed)
    }

    // MARK: - Wire shapes

    private struct WireTimer: Decodable, Equatable {
        let since: TimeInterval?
        let until: TimeInterval?
    }

    private struct WireAlert: Decodable {
        let title: String?
        let subtitle: String?
        let body: String?
        let level: String?
        let sound: String?
        let duration: TimeInterval?
    }

    private struct WireActivity: Decodable {
        let source: ActivityField<String>
        let icon: ActivityField<ChannelNotification.WireIcon>
        let title: ActivityField<String>
        let state: ActivityField<String>
        let progress: ActivityField<Double>
        let timer: ActivityField<WireTimer>
        let relevance: ActivityField<Double>
        let staleAfter: ActivityField<TimeInterval>
        let open: ActivityField<ChannelNotification.WireOpen>
        let alert: WireAlert?
        let dismissAfter: TimeInterval?
        let inbox: Bool?

        enum CodingKeys: String, CodingKey {
            case source, icon, title, state, progress, timer, relevance, open, alert, inbox
            case staleAfter = "stale_after"
            case dismissAfter = "dismiss_after"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            source = try c.field(.source)
            icon = try c.field(.icon)
            title = try c.field(.title)
            state = try c.field(.state)
            progress = try c.field(.progress)
            timer = try c.field(.timer)
            relevance = try c.field(.relevance)
            staleAfter = try c.field(.staleAfter)
            open = try c.field(.open)
            alert = try c.decodeIfPresent(WireAlert.self, forKey: .alert)
            dismissAfter = try c.decodeIfPresent(TimeInterval.self, forKey: .dismissAfter)
            inbox = try c.decodeIfPresent(Bool.self, forKey: .inbox)
        }
    }
}

extension ActivityField {
    /// The same field with its value transformed, where there is one.
    func map<New: Equatable>(_ transform: (Value) throws -> New) rethrows -> ActivityField<New> {
        switch self {
        case .keep: return .keep
        case .clear: return .clear
        case let .set(value): return .set(try transform(value))
        }
    }
}


private extension KeyedDecodingContainer {
    /// Absent, `null`, or a value — the three things a merge has to tell apart.
    func field<Value: Decodable & Equatable>(_ key: Key) throws -> ActivityField<Value> {
        guard contains(key) else { return .keep }
        if try decodeNil(forKey: key) { return .clear }
        return .set(try decode(Value.self, forKey: key))
    }
}
