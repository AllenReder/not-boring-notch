//
//  EstimatedPosition.swift
//  NotBoringNotch
//
//  The notch's own estimate of where playback is, and what the progress slider displays.
//  Pure arithmetic, no AppKit — see CONTEXT.md (Estimated Position, Seek Settle Window).
//

import Foundation

/// The player's last position report, and the notch's reading of it.
struct EstimatedPosition: Equatable {
    /// When the player reported `elapsedTime`.
    var reportedAt: Date
    /// The position the player reported.
    var elapsedTime: Double
    /// The track's length, which the estimate is clamped to.
    var duration: Double
    /// How fast playback runs. Only meaningful while `isPlaying`.
    var playbackRate: Double
    var isPlaying: Bool

    /// How long after a seek the notch keeps displaying the seek target while it waits for the
    /// player to report the new position (CONTEXT.md, Seek Settle Window).
    static let seekSettleWindow: TimeInterval = 1

    /// The Estimated Position at `date`: the player's report plus the time elapsed since it at
    /// the current rate, clamped to the track. A paused player has no elapsed time to add, so
    /// the report is the answer.
    func at(_ date: Date) -> Double {
        guard isPlaying else { return min(elapsedTime, duration) }
        let estimated = elapsedTime + date.timeIntervalSince(reportedAt) * playbackRate
        return min(max(0, estimated), duration)
    }

    /// The position the progress slider displays. While the user drags, and for the Seek
    /// Settle Window after a release, that is the seek target; afterwards it is the Estimated
    /// Position. Deriving it here, rather than storing it, is what keeps the slider from
    /// writing state on every timeline tick (issue #19).
    func displayed(at date: Date, seekTarget: Double, isDragging: Bool, lastSeek: Date) -> Double {
        // A seek target can outlive the track it came from — the slider keeps its value when the
        // next track is shorter — so it is clamped the way the estimate is.
        let target = min(max(seekTarget, 0), duration)
        guard !isDragging else { return target }
        guard date.timeIntervalSince(lastSeek) >= Self.seekSettleWindow else { return target }
        return at(date)
    }
}
