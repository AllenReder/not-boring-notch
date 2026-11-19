//
//  ActivityTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh.
//
// SOURCES: NotBoringNotch/Channel/Protocol/ChannelActivity.swift NotBoringNotch/Channel/Stores/ActivityStore.swift NotBoringNotch/Channel/Arbiter/ClosedNotchArbiter.swift NotBoringNotch/Channel/Protocol/ChannelNotification.swift
//
//  Helper names are prefixed (`checkActivity*`) so they stay distinguishable from the
//  helpers in the other standalone runners in this folder.
//

import Foundation

func checkActivity(_ condition: Bool, _ message: String = "",
                   file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkActivity<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                                 file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkActivityRefused(_ json: String, _ expected: ChannelPayloadError, _ message: String = "",
                          file: StaticString = #file, line: UInt = #line) {
    do {
        _ = try ActivityUpdate.decode(Data(json.utf8))
        print("❌ Assertion Failed: accepted \(json) - \(message) at \(file):\(line)")
        exit(1)
    } catch let error as ChannelPayloadError {
        checkActivity(error, expected, message, file: file, line: line)
    } catch {
        print("❌ Assertion Failed: unexpected \(error) - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct ActivityTests {
    static func main() {
        testAFullUpdateDecodes()
        testAbsentKeepsAndNullClears()
        testNumbersAreClampedOrRefused()
        testTheTimerIsExactlyOneOfSinceAndUntil()
        testAnAlertNeedsATitle()
        testAnEndBody()
        testUpdatesMerge()
        testAnUpdateAfterTheEndRestarts()
        testEndingAnUnknownActivity()
        testSweepingAndDeadlines()
        testCapacityEvictsTheEndedThenTheNeglected()
        testStalenessAndTitles()
        testAlertsAndOutcomesShareOneNotification()
        print("✅ ActivityTests: all passed")
    }

    static let t0 = Date(timeIntervalSince1970: 1_000_000)

    static func update(_ json: String) -> ActivityUpdate {
        do {
            return try ActivityUpdate.decode(Data(json.utf8))
        } catch {
            print("❌ refused \(json): \(error)")
            exit(1)
        }
    }

    // MARK: - Decoding

    static func testAFullUpdateDecodes() {
        let u = update("""
        {"source":"claude-code","icon":{"kind":"sf_symbol","value":"sparkle"},
         "title":" Refactor ","state":"Editing 3 files","progress":0.4,
         "timer":{"since":1000},"relevance":0.7,"stale_after":60,
         "open":{"app":"com.mitchellh.ghostty"},"unknown":true}
        """)
        checkActivity(u.source, .set("claude-code"))
        checkActivity(u.icon, .set(.symbol("sparkle")))
        checkActivity(u.title, .set("Refactor"), "text is trimmed")
        checkActivity(u.state, .set("Editing 3 files"))
        checkActivity(u.progress, .set(0.4))
        checkActivity(u.timer, .set(.since(Date(timeIntervalSince1970: 1000))))
        checkActivity(u.relevance, .set(0.7))
        checkActivity(u.staleAfter, .set(60))
        checkActivity(u.open, .set(.app("com.mitchellh.ghostty")))
        checkActivity(u.alert == nil, "no alert")
    }

    static func testAbsentKeepsAndNullClears() {
        let u = update(#"{"state":null,"progress":null,"title":"   "}"#)
        checkActivity(u.state, .clear, "null clears")
        checkActivity(u.progress, .clear)
        checkActivity(u.title, .clear, "blank text means nothing to show")
        checkActivity(u.source, .keep, "absent keeps")
        checkActivity(update("{}"), ActivityUpdate(), "an empty object changes nothing")
    }

    static func testNumbersAreClampedOrRefused() {
        checkActivity(update(#"{"progress":1.5}"#).progress, .set(1), "past done is done")
        checkActivity(update(#"{"progress":-1}"#).progress, .set(0))
        checkActivity(update(#"{"relevance":9}"#).relevance, .set(1))
        checkActivityRefused(#"{"stale_after":0}"#, .invalidNumber("stale_after"))
        checkActivityRefused(#"{"progress":"half"}"#, .malformed, "wrong type")
    }

    static func testTheTimerIsExactlyOneOfSinceAndUntil() {
        checkActivity(update(#"{"timer":{"until":2000}}"#).timer, .set(.until(Date(timeIntervalSince1970: 2000))))
        checkActivityRefused(#"{"timer":{}}"#, .invalidTimer, "neither")
        checkActivityRefused(#"{"timer":{"since":1,"until":2}}"#, .invalidTimer, "both")
    }

    static func testAnAlertNeedsATitle() {
        let u = update(#"{"alert":{"title":"Needs you","level":"time-sensitive","sound":"default"}}"#)
        checkActivity(u.alert?.title, "Needs you")
        checkActivity(u.alert?.level, .timeSensitive)
        checkActivity(u.alert?.sound, .standard)
        checkActivityRefused(#"{"alert":{}}"#, .missingTitle)
        checkActivityRefused(#"{"alert":{"title":"x","level":"loud"}}"#, .unknownLevel("loud"))
    }

    static func testAnEndBody() {
        let (u, e) = try! ActivityUpdate.decodeEnd(Data(#"{"state":"Done","dismiss_after":0,"inbox":false}"#.utf8))
        checkActivity(u.state, .set("Done"))
        checkActivity(e, ActivityEnding(dismissAfter: 0, leavesNotification: false))

        let (_, defaults) = try! ActivityUpdate.decodeEnd(Data())
        checkActivity(defaults, ActivityEnding(), "an empty body ends with the defaults")

        do {
            _ = try ActivityUpdate.decodeEnd(Data(#"{"dismiss_after":-1}"#.utf8))
            checkActivity(false, "a negative dismissal is refused")
        } catch {
            checkActivity(error as? ChannelPayloadError, .invalidNumber("dismiss_after"))
        }
    }

    // MARK: - The store

    static func testUpdatesMerge() {
        var store = ActivityStore()
        store.update(id: "a", with: update(#"{"title":"Build","state":"Compiling","progress":0.2}"#), now: t0)
        let a = store.update(id: "a", with: update(#"{"progress":0.6}"#), now: t0 + 5)
        checkActivity(a.title, "Build", "untouched fields keep their value")
        checkActivity(a.state, "Compiling")
        checkActivity(a.progress, 0.6)
        checkActivity(a.startedAt, t0)
        checkActivity(a.updatedAt, t0 + 5)

        let b = store.update(id: "a", with: update(#"{"relevance":null}"#), now: t0 + 6)
        checkActivity(b.relevance, ChannelActivity.defaultRelevance, "clearing a number restores its default")
    }

    static func testAnUpdateAfterTheEndRestarts() {
        var store = ActivityStore()
        store.update(id: "a", with: update(#"{"title":"x"}"#), now: t0)
        store.end(id: "a", with: ActivityUpdate(), ending: ActivityEnding(), now: t0 + 1)
        checkActivity(store.activity(id: "a")?.isEnded == true, "ended, still on screen")
        store.update(id: "a", with: update(#"{"state":"again"}"#), now: t0 + 2)
        checkActivity(store.activity(id: "a")?.isEnded == false, "in progress again")
        checkActivity(store.activity(id: "a")?.dismissAt == nil, "and no longer due to leave")
    }

    static func testEndingAnUnknownActivity() {
        var store = ActivityStore()
        checkActivity(store.end(id: "ghost", with: ActivityUpdate(), ending: ActivityEnding(), now: t0) == nil,
                      "nothing to end, nothing to show")
        checkActivity(store.isEmpty)

        let ended = store.end(id: "lost", with: update(#"{"title":"Build","state":"Done"}"#),
                              ending: ActivityEnding(), now: t0)
        checkActivity(ended?.isEnded == true, "named: started and ended in one go")

        let gone = store.end(id: "quick", with: update(#"{"title":"x"}"#),
                             ending: ActivityEnding(dismissAfter: 0), now: t0)
        checkActivity(gone != nil, "the ended activity is still returned")
        checkActivity(store.activity(id: "quick") == nil, "but dismissing at once leaves nothing")
    }

    static func testSweepingAndDeadlines() {
        var store = ActivityStore()
        store.update(id: "long", with: update(#"{"title":"long"}"#), now: t0)
        store.update(id: "done", with: update(#"{"title":"done"}"#), now: t0)
        store.end(id: "done", with: ActivityUpdate(), ending: ActivityEnding(dismissAfter: 4), now: t0 + 10)

        checkActivity(store.nextDeadline, t0 + 14, "the ended one leaves first")
        checkActivity(store.sweep(now: t0 + 13), [], "not yet")
        checkActivity(store.sweep(now: t0 + 14), ["done"])
        checkActivity(store.nextDeadline, t0 + ChannelActivity.maximumLifetime, "then the lifetime cap")
        checkActivity(store.sweep(now: t0 + ChannelActivity.maximumLifetime), ["long"])
        checkActivity(store.nextDeadline == nil)
    }

    static func testCapacityEvictsTheEndedThenTheNeglected() {
        var store = ActivityStore()
        for i in 0 ..< ActivityStore.capacity {
            store.update(id: "a\(i)", with: update(#"{"title":"x"}"#), now: t0 + Double(i))
        }
        store.update(id: "a0", with: update(#"{"state":"fresh"}"#), now: t0 + 100)
        store.end(id: "a5", with: ActivityUpdate(), ending: ActivityEnding(), now: t0 + 101)

        store.update(id: "new1", with: update(#"{"title":"x"}"#), now: t0 + 102)
        checkActivity(store.activity(id: "a5") == nil, "an ended activity makes room first")
        store.update(id: "new2", with: update(#"{"title":"x"}"#), now: t0 + 103)
        checkActivity(store.activity(id: "a1") == nil, "then the one neglected longest")
        checkActivity(store.activity(id: "a0") != nil, "not the oldest, which was updated recently")
        checkActivity(store.activities.count, ActivityStore.capacity)
    }

    static func testStalenessAndTitles() {
        var store = ActivityStore()
        let a = store.update(id: "id-1", with: update(#"{"source":"ci","stale_after":60}"#), now: t0)
        checkActivity(a.displayTitle, "ci", "no title: named by its source")
        checkActivity(ChannelActivity(id: "bare", startedAt: t0).displayTitle, "bare", "or its id")
        checkActivity(!a.isStale(at: t0 + 60))
        checkActivity(a.isStale(at: t0 + 61), "past stale_after without an update")

        let ended = store.end(id: "id-1", with: ActivityUpdate(), ending: ActivityEnding(), now: t0 + 1)!
        checkActivity(!ended.isStale(at: t0 + 1000), "an ended activity is not stale, it is over")
    }

    static func testAlertsAndOutcomesShareOneNotification() {
        var activity = ChannelActivity(id: "s1", startedAt: t0)
        activity.apply(update(#"{"title":"Session","state":"Done","icon":{"kind":"app_bundle","value":"com.apple.Terminal"}}"#), now: t0)

        let alert = activity.notification(for: ActivityAlert(title: "Needs you"), now: t0)
        let outcome = activity.outcome(now: t0)
        checkActivity(alert.id, "activity:s1")
        checkActivity(outcome.id, alert.id, "the outcome replaces the last alert")
        checkActivity(alert.subtitle, "Session", "an alert names its activity")
        checkActivity(outcome.level, .passive, "an outcome arrives quietly")
        checkActivity(outcome.subtitle, "Done")
        checkActivity(activity.clickTarget, .app("com.apple.Terminal"), "an app icon is a click target")
    }
}

extension ChannelPayloadError: CustomStringConvertible {
    public var description: String { code }
}

