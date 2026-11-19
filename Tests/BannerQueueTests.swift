//
//  BannerQueueTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/Channel/Stores/BannerQueue.swift NotBoringNotch/Channel/Stores/NotificationInbox.swift NotBoringNotch/Channel/Protocol/ChannelNotification.swift
//
//  Helper names are prefixed (`checkQueue*`) so they stay distinguishable from the
//  helpers in the other standalone runners in this folder.
//

import Foundation

func checkQueue(_ condition: Bool, _ message: String = "",
                file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkQueue(_ actual: String, _ expected: String, _ message: String = "",
                file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkQueue(_ actual: [String], _ expected: [String], _ message: String = "",
                file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct BannerQueueTestsRunner {
    static func main() {
        testTheFirstReminderIsShownAndNothingWaits()
        testLaterRemindersWaitInArrivalOrder()
        testDismissingShowsTheNextInLine()
        testAnArrivalWithTheVisibleIDReplacesItInPlace()
        testAnArrivalWithAWaitingIDTakesThatPlace()
        testAnOverflowingQueueDropsItsOldestWaiter()
        testDismissingTheLastReminderLeavesNothingShown()
        testATemporaryBannerGivesWayWhenItsTurnEnds()
        testABannerThatAskedToBeSeenHoldsOnlyWhileNothingWaits()
        testAnArrivalEndsAHoldImmediately()
        testTimeSensitiveGoesAheadOfActiveButBehindEarlierTimeSensitive()
        testOverflowDropsActiveBeforeTimeSensitive()
        testRemovingWithdrawsVisibleOrWaiting()
        testTheInboxKeepsNewestFirstAndReplacesByID()
        testTheInboxForgetsPastCapacity()
        print("✅ BannerQueueTests: all passed")
    }

    static func reminder(_ id: String, _ title: String? = nil,
                         level: ChannelInterruptionLevel = .active,
                         banner: ChannelBannerPersistence = .temporary) -> ChannelNotification {
        ChannelNotification(id: id, source: nil, thread: nil, level: level, icon: nil,
                            title: title ?? id, subtitle: nil, body: nil,
                            duration: ChannelNotification.defaultDuration, banner: banner,
                            sound: .none, open: nil, actions: [], deliveredAt: Date())
    }

    static func visibleAndWaiting(_ queue: BannerQueue) -> ([String], [String]) {
        (queue.visible.map { [$0.id] } ?? [], queue.waiting.map(\.id))
    }

    /// Nothing to wait behind, so the first arrival is shown straight away.
    static func testTheFirstReminderIsShownAndNothingWaits() {
        var queue = BannerQueue()
        queue.enqueue(reminder("a"))

        checkQueue(visibleAndWaiting(queue).0, ["a"], "the first arrival is visible")
        checkQueue(visibleAndWaiting(queue).1, [], "and nothing is waiting")
    }

    /// One at a time, in the order they arrived.
    static func testLaterRemindersWaitInArrivalOrder() {
        var queue = BannerQueue()
        "abc".forEach { queue.enqueue(reminder(String($0))) }

        checkQueue(visibleAndWaiting(queue).0, ["a"], "the first arrival keeps the display")
        checkQueue(visibleAndWaiting(queue).1, ["b", "c"], "the rest queue up behind it, oldest first")
    }

    /// The display passes down the line, not back to the start.
    static func testDismissingShowsTheNextInLine() {
        var queue = BannerQueue()
        "abc".forEach { queue.enqueue(reminder(String($0))) }

        queue.dismissVisible()
        checkQueue(visibleAndWaiting(queue).0, ["b"], "the next waiter takes the display")
        checkQueue(visibleAndWaiting(queue).1, ["c"], "and leaves the rest queued")

        queue.dismissVisible()
        checkQueue(visibleAndWaiting(queue).0, ["c"], "and again")
        checkQueue(visibleAndWaiting(queue).1, [], "the queue drains")

        queue.dismissVisible()
        checkQueue(visibleAndWaiting(queue).0, [], "dismissing with nothing left shows nothing")
    }

    /// A sender that names its reminder can update the one on screen — the case a console
    /// showing "session 42: building" then "session 42: done" depends on.
    static func testAnArrivalWithTheVisibleIDReplacesItInPlace() {
        var queue = BannerQueue()
        queue.enqueue(reminder("build", "building"))
        queue.enqueue(reminder("build", "done"))

        let (visible, waiting) = visibleAndWaiting(queue)
        checkQueue(visible, ["build"], "the same reminder is still the one on screen")
        checkQueue(waiting, [], "and it did not also queue itself")
        checkQueue(queue.visible?.title ?? "", "done", "with the newer content")
    }

    /// Replacing a waiter keeps its place, so a chatty sender cannot jump the line.
    static func testAnArrivalWithAWaitingIDTakesThatPlace() {
        var queue = BannerQueue()
        "abc".forEach { queue.enqueue(reminder(String($0))) }
        queue.enqueue(reminder("b", "b again"))

        checkQueue(visibleAndWaiting(queue).1, ["b", "c"], "b keeps its position")
        checkQueue(queue.waiting.first?.title ?? "", "b again", "with the newer content")
    }

    /// The queue has a floor as well as a ceiling: a sender in a loop must not grow it
    /// without bound, and the news that survives is the newest.
    static func testAnOverflowingQueueDropsItsOldestWaiter() {
        var queue = BannerQueue()
        let ids = ["a", "b", "c", "d", "e", "f", "g"]
        ids.forEach { queue.enqueue(reminder($0)) }

        let (visible, waiting) = visibleAndWaiting(queue)
        checkQueue(visible, ["a"], "the displayed reminder is never dropped")
        checkQueue(waiting, ["c", "d", "e", "f", "g"],
                   "the queue holds \(BannerQueue.waitingCapacity) and drops the oldest waiter, b")
    }

    /// Dismissing the only reminder empties the notch rather than leaving a stale one behind.
    static func testDismissingTheLastReminderLeavesNothingShown() {
        var queue = BannerQueue()
        queue.enqueue(reminder("a"))
        queue.dismissVisible()

        checkQueue(queue.visible == nil, "nothing is shown")
        checkQueue(queue.waiting.isEmpty, "nothing is waiting")
    }

    // MARK: - Turns

    static func testATemporaryBannerGivesWayWhenItsTurnEnds() {
        var queue = BannerQueue()
        queue.enqueue(reminder("a"))
        queue.turnEnded()
        checkQueue(queue.visible == nil, "a temporary banner leaves when its time is up")
    }

    /// The bug this design exists for: a sticky Reminder held the notch and everyone behind it
    /// waited until the user clicked Dismiss.
    static func testABannerThatAskedToBeSeenHoldsOnlyWhileNothingWaits() {
        var queue = BannerQueue()
        queue.enqueue(reminder("sticky", banner: .untilSeen))
        queue.turnEnded()
        checkQueue(visibleAndWaiting(queue).0, ["sticky"], "with nothing waiting it stays")
        checkQueue(queue.isHolding, "and is holding rather than on the clock")

        var busy = BannerQueue()
        busy.enqueue(reminder("sticky", banner: .untilSeen))
        busy.enqueue(reminder("b"))
        busy.turnEnded()
        checkQueue(visibleAndWaiting(busy).0, ["b"], "with someone waiting it gives way at the end of its turn")
    }

    static func testAnArrivalEndsAHoldImmediately() {
        var queue = BannerQueue()
        queue.enqueue(reminder("sticky", banner: .untilSeen))
        queue.turnEnded()
        queue.enqueue(reminder("b"))
        checkQueue(visibleAndWaiting(queue).0, ["b"], "a holding banner yields the moment something arrives")
        checkQueue(!queue.isHolding, "and the newcomer is on the clock")
    }

    static func testTimeSensitiveGoesAheadOfActiveButBehindEarlierTimeSensitive() {
        var queue = BannerQueue()
        queue.enqueue(reminder("a"))
        queue.enqueue(reminder("b"))
        queue.enqueue(reminder("t1", level: .timeSensitive))
        queue.enqueue(reminder("t2", level: .timeSensitive))
        checkQueue(visibleAndWaiting(queue).0, ["a"], "the visible banner finishes its turn")
        checkQueue(visibleAndWaiting(queue).1, ["t1", "t2", "b"], "time-sensitive first, in arrival order")
    }

    static func testOverflowDropsActiveBeforeTimeSensitive() {
        var queue = BannerQueue()
        queue.enqueue(reminder("v"))
        ["a", "b", "c", "d"].forEach { queue.enqueue(reminder($0)) }
        queue.enqueue(reminder("t", level: .timeSensitive))
        queue.enqueue(reminder("e"))
        checkQueue(visibleAndWaiting(queue).1, ["t", "b", "c", "d", "e"],
                   "the oldest active waiter, a, goes rather than the time-sensitive one")
    }

    static func testRemovingWithdrawsVisibleOrWaiting() {
        var queue = BannerQueue()
        "abc".forEach { queue.enqueue(reminder(String($0))) }
        queue.remove(id: "b")
        checkQueue(visibleAndWaiting(queue).1, ["c"], "a waiter is withdrawn")
        queue.remove(id: "a")
        checkQueue(visibleAndWaiting(queue).0, ["c"], "the visible one is withdrawn and the next takes over")
        queue.remove(id: "nope")
        checkQueue(visibleAndWaiting(queue).0, ["c"], "withdrawing an unknown id changes nothing")
    }

    // MARK: - Inbox

    static func testTheInboxKeepsNewestFirstAndReplacesByID() {
        var inbox = NotificationInbox()
        inbox.deliver(reminder("a"))
        inbox.deliver(reminder("b"))
        inbox.deliver(reminder("a", "a again"))
        checkQueue(inbox.items.map(\.id), ["a", "b"], "a replacement moves to the top")
        checkQueue(inbox.items.first?.title ?? "", "a again", "with its new content")
        checkQueue(inbox.unreadCount == 2, "both unread")

        inbox.markAllRead()
        inbox.deliver(reminder("c"), read: true)
        checkQueue(inbox.unreadCount == 0, "delivered while the Inbox is on screen is read")

        inbox.remove(id: "b")
        checkQueue(inbox.items.map(\.id), ["c", "a"], "removed")
    }

    static func testTheInboxForgetsPastCapacity() {
        var inbox = NotificationInbox()
        (0 ... NotificationInbox.capacity).forEach { inbox.deliver(reminder("n\($0)")) }
        checkQueue(inbox.items.count == NotificationInbox.capacity, "capped")
        checkQueue(inbox.notification(id: "n0") == nil, "the oldest is forgotten")
        checkQueue(inbox.unreadCount == NotificationInbox.capacity, "and so is its unread mark")
    }
}
