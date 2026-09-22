//
//  EstimatedPositionTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: boringNotch/models/EstimatedPosition.swift
//
//  Helper names are prefixed (`check*`) so they stay distinguishable from the helpers
//  in the other standalone runners in this folder.
//

import Foundation

func checkTime(_ actual: Double, _ expected: Double, tolerance: Double = 0.0005,
               _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if abs(actual - expected) > tolerance {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkHolds(_ condition: Bool, _ message: String = "",
                file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct EstimatedPositionTestsRunner {
    /// A fixed frame time, so the tests can talk about offsets from it.
    static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    static func main() {
        testPausedReportsTheLastKnownPosition()
        testPlayingExtrapolatesFromTheReport()
        testEstimateIsClampedToTheTrack()
        testSeekTargetIsDisplayedWhileDragging()
        testSeekTargetIsDisplayedThroughTheSettleWindow()
        testEstimateIsDisplayedAfterTheWindow()
        testASeekTargetFromALongerTrackIsClamped()
        testAStaleReportDoesNotHoldTheSeekTarget()
        print("✅ EstimatedPositionTests: all passed")
    }

    static func playing(elapsed: Double = 10, duration: Double = 100, rate: Double = 1,
                        reportedAt: Date? = nil, isPlaying: Bool = true) -> EstimatedPosition {
        EstimatedPosition(reportedAt: reportedAt ?? now, elapsedTime: elapsed, duration: duration,
                          playbackRate: rate, isPlaying: isPlaying)
    }

    /// A paused player adds nothing to its own report.
    static func testPausedReportsTheLastKnownPosition() {
        let paused = playing(elapsed: 12, isPlaying: false)
        checkTime(paused.at(now.addingTimeInterval(30)), 12, "paused playback does not advance")
        checkTime(playing(elapsed: 120, duration: 100, isPlaying: false).at(now), 100,
                  "a report past the track's end is clamped")
    }

    /// While playing, the report is extrapolated at the current rate.
    static func testPlayingExtrapolatesFromTheReport() {
        checkTime(playing(elapsed: 10, rate: 1).at(now.addingTimeInterval(5)), 15,
                  "one second per second")
        checkTime(playing(elapsed: 10, rate: 2).at(now.addingTimeInterval(5)), 20,
                  "the rate scales the elapsed time")
    }

    /// The estimate never leaves the track, in either direction.
    static func testEstimateIsClampedToTheTrack() {
        checkTime(playing(elapsed: 95, duration: 100).at(now.addingTimeInterval(10)), 100,
                  "clamped at the end")
        checkTime(playing(elapsed: 2, duration: 100).at(now.addingTimeInterval(-10)), 0,
                  "clamped at the start when the report is in the future")
    }

    /// The user owns the displayed value for as long as they hold the slider.
    static func testSeekTargetIsDisplayedWhileDragging() {
        let position = playing(elapsed: 10)
        checkTime(position.displayed(at: now, seekTarget: 42, isDragging: true,
                                     lastSeek: .distantPast), 42,
                  "dragging displays the seek target, not the estimate")
    }

    /// After a release the seek target stays on screen for the Seek Settle Window, so the
    /// slider does not jump back before the player has had a chance to report the new position.
    static func testSeekTargetIsDisplayedThroughTheSettleWindow() {
        let position = playing(elapsed: 10)
        checkTime(position.displayed(at: now, seekTarget: 42, isDragging: false,
                                     lastSeek: now.addingTimeInterval(-0.5)), 42,
                  "half a second after the seek, the target is still displayed")
        checkTime(position.displayed(at: now, seekTarget: 42, isDragging: false,
                                     lastSeek: now.addingTimeInterval(-0.999)), 42,
                  "just inside the window")
    }

    /// Once the window is over, the estimate takes the display back.
    static func testEstimateIsDisplayedAfterTheWindow() {
        let position = playing(elapsed: 10)
        checkTime(position.displayed(at: now, seekTarget: 42, isDragging: false,
                                     lastSeek: now.addingTimeInterval(-1)), 10,
                  "the window is one second wide")
        checkTime(position.displayed(at: now, seekTarget: 42, isDragging: false,
                                     lastSeek: now.addingTimeInterval(-5)), 10,
                  "well after the window")
    }

    /// A seek target can outlive the track it came from: `sliderValue` keeps its value across a
    /// track change, so a position from a longer track must be clamped to the one on display.
    static func testASeekTargetFromALongerTrackIsClamped() {
        let position = playing(elapsed: 10, duration: 100)
        checkTime(position.displayed(at: now, seekTarget: 240, isDragging: true,
                                     lastSeek: .distantPast), 100,
                  "dragging is clamped to the track")
        checkTime(position.displayed(at: now, seekTarget: 240, isDragging: false, lastSeek: now), 100,
                  "and so is a seek target inside the Seek Settle Window")
        checkTime(position.displayed(at: now, seekTarget: -5, isDragging: false, lastSeek: now), 0,
                  "clamped at the start too")
    }

    /// The window is measured against the frame's clock, not against the player's report. The
    /// old guard compared the report's timestamp with the drag time, which is why a stale
    /// report could hold a seek target on screen for longer than intended (issue #19).
    static func testAStaleReportDoesNotHoldTheSeekTarget() {
        let staleReport = now.addingTimeInterval(-30)
        let position = playing(elapsed: 10, reportedAt: staleReport)
        // 10 seconds reported, 30 seconds of playback at rate 1 since then.
        checkTime(position.displayed(at: now, seekTarget: 5, isDragging: false,
                                     lastSeek: now.addingTimeInterval(-5)), 40,
                  "a five-second-old seek is over, however old the report is: the estimate takes the display back")
    }
}
