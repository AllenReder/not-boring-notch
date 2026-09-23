//
//  ReminderQueueTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/models/ReminderQueue.swift NotBoringNotch/models/Reminder.swift
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
struct ReminderQueueTestsRunner {
    static func main() {
        testTheFirstReminderIsShownAndNothingWaits()
        testLaterRemindersWaitInArrivalOrder()
        testDismissingShowsTheNextInLine()
        testAnArrivalWithTheVisibleIDReplacesItInPlace()
        testAnArrivalWithAWaitingIDTakesThatPlace()
        testAnOverflowingQueueDropsItsOldestWaiter()
        testDismissingTheLastReminderLeavesNothingShown()
        print("✅ ReminderQueueTests: all passed")
    }

    static func reminder(_ id: String, _ title: String? = nil) -> Reminder {
        Reminder(id: id, icon: nil, title: title ?? id, subtitle: nil, body: nil,
                 duration: Reminder.defaultDuration, isSticky: false, sound: .none, action: nil)
    }

    static func visibleAndWaiting(_ queue: ReminderQueue) -> ([String], [String]) {
        (queue.visible.map { [$0.id] } ?? [], queue.waiting.map(\.id))
    }

    /// Nothing to wait behind, so the first arrival is shown straight away.
    static func testTheFirstReminderIsShownAndNothingWaits() {
        var queue = ReminderQueue()
        queue.enqueue(reminder("a"))

        checkQueue(visibleAndWaiting(queue).0, ["a"], "the first arrival is visible")
        checkQueue(visibleAndWaiting(queue).1, [], "and nothing is waiting")
    }

    /// One at a time, in the order they arrived.
    static func testLaterRemindersWaitInArrivalOrder() {
        var queue = ReminderQueue()
        "abc".forEach { queue.enqueue(reminder(String($0))) }

        checkQueue(visibleAndWaiting(queue).0, ["a"], "the first arrival keeps the display")
        checkQueue(visibleAndWaiting(queue).1, ["b", "c"], "the rest queue up behind it, oldest first")
    }

    /// The display passes down the line, not back to the start.
    static func testDismissingShowsTheNextInLine() {
        var queue = ReminderQueue()
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
        var queue = ReminderQueue()
        queue.enqueue(reminder("build", "building"))
        queue.enqueue(reminder("build", "done"))

        let (visible, waiting) = visibleAndWaiting(queue)
        checkQueue(visible, ["build"], "the same reminder is still the one on screen")
        checkQueue(waiting, [], "and it did not also queue itself")
        checkQueue(queue.visible?.title ?? "", "done", "with the newer content")
    }

    /// Replacing a waiter keeps its place, so a chatty sender cannot jump the line.
    static func testAnArrivalWithAWaitingIDTakesThatPlace() {
        var queue = ReminderQueue()
        "abc".forEach { queue.enqueue(reminder(String($0))) }
        queue.enqueue(reminder("b", "b again"))

        checkQueue(visibleAndWaiting(queue).1, ["b", "c"], "b keeps its position")
        checkQueue(queue.waiting.first?.title ?? "", "b again", "with the newer content")
    }

    /// The queue has a floor as well as a ceiling: a sender in a loop must not grow it
    /// without bound, and the news that survives is the newest.
    static func testAnOverflowingQueueDropsItsOldestWaiter() {
        var queue = ReminderQueue()
        let ids = ["a", "b", "c", "d", "e", "f", "g"]
        ids.forEach { queue.enqueue(reminder($0)) }

        let (visible, waiting) = visibleAndWaiting(queue)
        checkQueue(visible, ["a"], "the displayed reminder is never dropped")
        checkQueue(waiting, ["c", "d", "e", "f", "g"],
                   "the queue holds \(ReminderQueue.waitingCapacity) and drops the oldest waiter, b")
    }

    /// Dismissing the only reminder empties the notch rather than leaving a stale one behind.
    static func testDismissingTheLastReminderLeavesNothingShown() {
        var queue = ReminderQueue()
        queue.enqueue(reminder("a"))
        queue.dismissVisible()

        checkQueue(queue.visible == nil, "nothing is shown")
        checkQueue(queue.waiting.isEmpty, "nothing is waiting")
    }
}
