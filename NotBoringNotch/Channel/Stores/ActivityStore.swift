//
//  ActivityStore.swift
//  NotBoringNotch
//
//  The activities in progress, and the rules for how many there may be and how long they last.
//  Pure: the caller supplies the time, so every rule is tested without waiting for it.
//
//  Not kept across restarts. An activity is a claim that something is happening now; after a
//  restart that claim is unverified, and the sender's next update brings it back anyway.
//

import Foundation

struct ActivityStore: Equatable {
    /// How many activities may be in progress at once. The closed notch shows two; the rest wait
    /// in the open notch, and a sender that leaks activities cannot grow the list without bound.
    static let capacity = 8

    /// In the order they started.
    private(set) var activities: [ChannelActivity] = []

    var isEmpty: Bool { activities.isEmpty }

    func activity(id: String) -> ChannelActivity? {
        activities.first { $0.id == id }
    }

    /// What the arbiter ranks them by.
    var standings: [ActivityStanding] {
        activities.map { ActivityStanding(id: $0.id, relevance: $0.relevance, updatedAt: $0.updatedAt) }
    }

    /// Starts the activity or updates it, and returns it as it now stands.
    @discardableResult
    mutating func update(id: String, with update: ActivityUpdate, now: Date) -> ChannelActivity {
        if let index = activities.firstIndex(where: { $0.id == id }) {
            activities[index].apply(update, now: now)
            return activities[index]
        }

        makeRoom()
        var activity = ChannelActivity(id: id, startedAt: now)
        activity.apply(update, now: now)
        activities.append(activity)
        return activity
    }

    /// Ends the activity, applying its last update first, and returns it as it ended.
    ///
    /// Ending an id the store does not have — because the notch restarted while it ran — starts and
    /// ends it in one go, provided the request names it; otherwise there is nothing to show and
    /// nothing is done.
    @discardableResult
    mutating func end(id: String, with update: ActivityUpdate, ending: ActivityEnding,
                      now: Date) -> ChannelActivity? {
        if activity(id: id) == nil {
            guard case .set = update.title else { return nil }
            if ending.dismissAfter == 0 {
                // It would leave as soon as it arrived, so it does not take a place — or push out an
                // activity still running — on the way.
                var ended = ChannelActivity(id: id, startedAt: now)
                ended.apply(update, now: now)
                ended.end(ending, now: now)
                return ended
            }
        }
        self.update(id: id, with: update, now: now)

        guard let index = activities.firstIndex(where: { $0.id == id }) else { return nil }
        activities[index].end(ending, now: now)
        let ended = activities[index]
        if ending.dismissAfter == 0 {
            activities.remove(at: index)
        }
        return ended
    }

    @discardableResult
    mutating func remove(id: String) -> Bool {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return false }
        activities.remove(at: index)
        return true
    }

    mutating func removeAll() {
        activities.removeAll()
    }

    /// Removes what has run its course — an ended activity past its dismissal, anything past the
    /// maximum lifetime — and returns their ids.
    @discardableResult
    mutating func sweep(now: Date) -> [String] {
        let expired = activities.filter { Self.deadline(of: $0) <= now }.map(\.id)
        activities.removeAll { expired.contains($0.id) }
        return expired
    }

    /// The next moment `sweep` would remove something.
    var nextDeadline: Date? {
        activities.map(Self.deadline).min()
    }

    private static func deadline(of activity: ChannelActivity) -> Date {
        let lifetimeEnds = activity.startedAt.addingTimeInterval(ChannelActivity.maximumLifetime)
        guard let dismissAt = activity.dismissAt else { return lifetimeEnds }
        return min(dismissAt, lifetimeEnds)
    }

    /// At capacity, a new arrival takes the place of an activity that has already ended, or failing
    /// that the one its sender has neglected longest.
    private mutating func makeRoom() {
        guard activities.count >= Self.capacity else { return }
        let victim = activities.firstIndex(where: \.isEnded)
            ?? activities.indices.min { activities[$0].updatedAt < activities[$1].updatedAt }
        if let victim { activities.remove(at: victim) }
    }
}
