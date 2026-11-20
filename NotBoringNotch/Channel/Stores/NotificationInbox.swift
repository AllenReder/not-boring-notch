//
//  NotificationInbox.swift
//  NotBoringNotch
//
//  Every notification the notch has delivered and the user has not cleared — iOS's Notification
//  Center. A banner is only how a notification first appears; this is where it stays.
//

import Foundation

struct NotificationInbox: Codable, Equatable {
    /// How many notifications are kept. Past this the oldest is forgotten.
    static let capacity = 50

    /// Newest first.
    private(set) var items: [ChannelNotification] = []
    /// Ids delivered since the user last looked at the Inbox.
    private(set) var unread: Set<String> = []

    var isEmpty: Bool { items.isEmpty }
    var unreadCount: Int { unread.count }

    /// Files a notification. One that reuses an id replaces its predecessor and moves to the top,
    /// unread again: it is news, even if it is news about the same thing.
    mutating func deliver(_ notification: ChannelNotification, read: Bool = false) {
        items.removeAll { $0.id == notification.id }
        items.insert(notification, at: 0)
        if read {
            unread.remove(notification.id)
        } else {
            unread.insert(notification.id)
        }

        while items.count > Self.capacity {
            let dropped = items.removeLast()
            unread.remove(dropped.id)
        }
    }

    mutating func remove(id: String) {
        items.removeAll { $0.id == id }
        unread.remove(id)
    }

    mutating func removeAll() {
        items = []
        unread = []
    }

    mutating func markAllRead() {
        unread = []
    }

    func notification(id: String) -> ChannelNotification? {
        items.first { $0.id == id }
    }
}
