//
//  ReminderQueue.swift
//  NotBoringNotch
//
//  Which Reminder the notch is showing, and which ones are waiting for their turn. The
//  policy is deliberately small and sender-driven: the notch never guesses that two
//  Reminders are about the same thing — a sender says so by reusing an id.
//

import Foundation

struct ReminderQueue {
    /// How many Reminders wait behind the one on screen. A sender in a loop cannot grow the
    /// notch's memory without bound, and when the queue overflows the oldest waiter goes, so
    /// what survives is the most recent news.
    static let waitingCapacity = 5

    private(set) var visible: Reminder?
    private(set) var waiting: [Reminder] = []

    /// Adds a Reminder, or updates one already known under the same id.
    ///
    /// A repeated id replaces its Reminder where it stands: the one on screen stays on screen
    /// with its newer content, and a waiter keeps its place in line, so a chatty sender cannot
    /// jump ahead of everyone else.
    mutating func enqueue(_ reminder: Reminder) {
        if visible?.id == reminder.id {
            visible = reminder
            return
        }

        if let waitingIndex = waiting.firstIndex(where: { $0.id == reminder.id }) {
            waiting[waitingIndex] = reminder
            return
        }

        waiting.append(reminder)
        if waiting.count > Self.waitingCapacity {
            waiting.removeFirst()
        }

        if visible == nil {
            visible = waiting.removeFirst()
        }
    }

    /// Ends the current Reminder and gives the display to the next in line, if any.
    mutating func dismissVisible() {
        visible = waiting.isEmpty ? nil : waiting.removeFirst()
    }
}
