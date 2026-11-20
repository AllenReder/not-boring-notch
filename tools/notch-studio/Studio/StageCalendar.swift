// The Home view's calendar, on placeholder events. The app reads EventKit through its own
// CalendarService, so the studio answers EventKit itself: it reports calendar access as granted
// (the studio never asks, so no permission prompt), and hands back one local calendar and a few
// events built in memory. Nothing from the user's real calendars is ever read.

import AppKit
import EventKit
import ObjectiveC

enum StageCalendar {
    /// Titles and offsets from the last half hour, in minutes, so the list always has an event in progress and
    /// two coming up, whatever time the take is recorded.
    static let plan: [(title: String, from: Double, minutes: Double, color: NSColor)] = [
        ("Design review", -30, 60, .systemBlue),
        ("Launch sync · v1.5", 60, 30, .systemOrange),
        ("Ship it", 150, 60, .systemGreen),
    ]

    private static let store = EKEventStore()
    private static let source = EKSource()
    private static let calendar: EKCalendar = {
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = "Work"
        c.color = .systemBlue
        return c
    }()

    private static func events() -> [EKEvent] {
        plan.map { p in
            let e = EKEvent(eventStore: store)
            e.title = p.title
            // On the half hour, as real meetings are.
            let half = (Date().timeIntervalSinceReferenceDate / 1800).rounded(.down) * 1800
            e.startDate = Date(timeIntervalSinceReferenceDate: half + p.from * 60)
            e.endDate = e.startDate.addingTimeInterval(p.minutes * 60)
            e.timeZone = nil
            // One calendar per colour, so each event keeps its own colour bar.
            let c = EKCalendar(for: .event, eventStore: store)
            c.title = "Work"
            c.color = p.color
            e.calendar = c
            return e
        }
    }

    static func install() {
        // +authorizationStatusForEntityType: events granted, reminders denied (no reminder list).
        let meta: AnyClass = object_getClass(EKEventStore.self)!
        if let m = class_getInstanceMethod(meta, NSSelectorFromString("authorizationStatusForEntityType:")) {
            let block: @convention(block) (AnyObject, UInt) -> Int = { _, type in
                type == EKEntityType.event.rawValue ? EKAuthorizationStatus.fullAccess.rawValue : EKAuthorizationStatus.denied.rawValue
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
        }
        let calendars: @convention(block) (AnyObject, UInt) -> NSArray = { _, type in
            type == EKEntityType.event.rawValue ? [calendar] : []
        }
        set(EKEventStore.self, "calendarsForEntityType:", calendars)
        let matching: @convention(block) (AnyObject, AnyObject?) -> NSArray = { _, _ in events() as NSArray }
        set(EKEventStore.self, "eventsMatchingPredicate:", matching)
        // A calendar made in memory has no account; the app asks for one when it labels it.
        let sourceBlock: @convention(block) (AnyObject) -> EKSource = { _ in source }
        if let m = class_getInstanceMethod(EKCalendar.self, #selector(getter: EKCalendar.source)) {
            method_setImplementation(m, imp_implementationWithBlock(sourceBlock))
        }
    }

    private static func set(_ cls: AnyClass, _ name: String, _ block: Any) {
        guard let m = class_getInstanceMethod(cls, NSSelectorFromString(name)) else { fatalError("no \(name)") }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }
}
