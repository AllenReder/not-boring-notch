//
//  BannerQueue.swift
//  NotBoringNotch
//
//  Which notification the closed notch is showing as a banner, and which ones are waiting for
//  their turn. Every notification is in the Inbox from the moment it arrives, so this queue only
//  decides presentation: dropping a waiter loses nothing but its banner.
//
//  The notch never guesses that two notifications are about the same thing — a sender says so by
//  reusing an id.
//

import Foundation

struct BannerQueue {
    /// How many banners wait behind the one on screen. When the queue overflows the oldest waiter
    /// goes, so what survives is the most recent news; the dropped one is still in the Inbox.
    static let waitingCapacity = 5

    private(set) var visible: ChannelNotification?
    private(set) var waiting: [ChannelNotification] = []
    /// The visible banner has had its full duration and is staying only because it asked to be
    /// seen. It holds the notch until the user looks, or until anything else wants a turn.
    private(set) var isHolding = false

    /// Adds a banner, or updates one already known under the same id.
    ///
    /// A repeated id replaces its banner where it stands: the one on screen stays on screen with
    /// its newer content, and a waiter keeps its place in line, so a chatty sender cannot jump
    /// ahead of everyone else. A time-sensitive banner is the exception: it goes to the front.
    mutating func enqueue(_ notification: ChannelNotification) {
        if visible?.id == notification.id {
            visible = notification
            isHolding = false
            return
        }

        if let index = waiting.firstIndex(where: { $0.id == notification.id }) {
            waiting[index] = notification
            return
        }

        if notification.level == .timeSensitive {
            // Behind other time-sensitive waiters, ahead of everything else.
            let index = waiting.firstIndex { $0.level != .timeSensitive } ?? waiting.endIndex
            waiting.insert(notification, at: index)
        } else {
            waiting.append(notification)
        }
        if waiting.count > Self.waitingCapacity, let oldest = oldestDroppable() {
            waiting.remove(at: oldest)
        }

        if visible == nil || isHolding {
            advance()
        }
    }

    /// The visible banner's duration is over. A temporary one gives way; one that asked to be
    /// seen stays while nothing waits, and gives way the moment something arrives.
    mutating func turnEnded() {
        guard let visible else { return }
        if visible.banner == .untilSeen, waiting.isEmpty {
            isHolding = true
        } else {
            advance()
        }
    }

    /// The user dismissed the visible banner, or looked at it.
    mutating func dismissVisible() {
        advance()
    }

    /// Withdraws a notification's banner, whether it is on screen or still waiting.
    mutating func remove(id: String) {
        if visible?.id == id {
            advance()
        } else {
            waiting.removeAll { $0.id == id }
        }
    }

    mutating func removeAll() {
        visible = nil
        waiting = []
        isHolding = false
    }

    private mutating func advance() {
        visible = waiting.isEmpty ? nil : waiting.removeFirst()
        isHolding = false
    }

    /// The oldest waiter that is not time-sensitive, or the oldest of all if every one is.
    /// Time-sensitive waiters sit at the front in arrival order, so the first one that is not
    /// time-sensitive is the oldest of the rest.
    private func oldestDroppable() -> Int? {
        waiting.firstIndex { $0.level != .timeSensitive } ?? (waiting.isEmpty ? nil : 0)
    }
}
