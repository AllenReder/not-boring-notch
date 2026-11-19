//
//  ActivityViews.swift
//  NotBoringNotch
//
//  An activity in the closed notch, in the two sizes the arbiter hands out:
//
//  - compact: both wings — icon and title on the left, the one thing worth a glance on the right
//    (progress, a timer, its state) — or, when another resident holds the right wing, that
//    resident's minimal view there instead.
//  - minimal: the right wing alone — its icon, ringed by its progress.
//
//  The geometry follows the banner's: both wings the same width, so the content stays centred on
//  the camera housing.
//

import Defaults
import SwiftUI

/// Who holds the right wing beside a compact activity.
enum ActivityAccessory: Equatable {
    /// Nobody: the activity's own detail.
    case none
    case music
    case activity(ChannelActivity)
}

struct ActivityCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    let activity: ChannelActivity
    let accessory: ActivityAccessory

    /// Narrower than a banner's: an activity can sit on the notch for hours.
    static let maximumWingWidth: CGFloat = 150

    static func wingWidth(for activity: ChannelActivity, accessory: ActivityAccessory) -> CGFloat {
        // padding(8) + icon(18) + spacing(6) + title + padding(6)
        let leftNeeded = 38 + ScrollableBannerText.measureWidth(activity.displayTitle, weight: .medium)

        let rightNeeded: CGFloat
        switch accessory {
        case .music, .activity:
            rightNeeded = 36
        case .none:
            rightNeeded = 16 + ActivityDetail.width(for: activity, now: Date())
        }
        return min(maximumWingWidth, max(28, leftNeeded, rightNeeded))
    }

    private var wingWidth: CGFloat { Self.wingWidth(for: activity, accessory: accessory) }

    var body: some View {
        // Often enough to notice that a sender has gone quiet, and for a timer's width to follow
        // it past the hour.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let stale = activity.isStale(at: context.date)
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    ChannelIconView(icon: activity.icon)
                        .frame(width: 18, height: 18)
                    Text(activity.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .frame(width: wingWidth, alignment: .leading)
                .opacity(stale ? 0.5 : 1)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)

                rightWing(stale: stale)
                    .frame(width: wingWidth, alignment: .trailing)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    private func rightWing(stale: Bool) -> some View {
        switch accessory {
        case .music:
            MusicMinimalView()
                .frame(width: 20, height: 20)
                .padding(.trailing, 10)
        case let .activity(other):
            ActivityMinimalView(activity: other)
                .frame(width: 20, height: 20)
                .padding(.trailing, 10)
        case .none:
            ActivityDetail(activity: activity, stale: stale)
                .padding(.trailing, 10)
        }
    }
}

/// The right wing of a compact activity with the wing to itself: the one detail most worth a
/// glance, in this order — how it ended, that it has gone stale, its progress, its timer, its
/// state.
struct ActivityDetail: View {
    let activity: ChannelActivity
    let stale: Bool

    static func width(for activity: ChannelActivity, now: Date) -> CGFloat {
        if activity.isEnded {
            return 16 + (activity.state.map { 4 + measure($0) } ?? 0)
        }
        if let progress = activity.progress {
            return 14 + 4 + measure(percent(progress))
        }
        if let timer = activity.timer {
            return measure(timerPlaceholder(timer, now: now))
        }
        if let state = activity.state {
            return measure(state)
        }
        return 12
    }

    private static func measure(_ text: String) -> CGFloat {
        ScrollableBannerText.measureWidth(text, weight: .regular)
    }

    static func percent(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    /// As wide as the timer will read: digits are monospaced, so only the number of them matters.
    private static func timerPlaceholder(_ timer: ActivityTimer, now: Date) -> String {
        let seconds: TimeInterval
        switch timer {
        case let .since(start): seconds = now.timeIntervalSince(start)
        case let .until(end): seconds = end.timeIntervalSince(now)
        }
        return abs(seconds) >= 3600 ? "0:00:00" : "00:00"
    }

    var body: some View {
        HStack(spacing: 4) {
            if activity.isEnded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                if let state = activity.state {
                    secondary(state)
                }
            } else if stale {
                // What it last said may no longer be true, so it is not repeated.
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .help(Text("No update for a while"))
            } else if let progress = activity.progress {
                ActivityProgressRing(progress: progress)
                    .frame(width: 14, height: 14)
                secondary(Self.percent(progress))
            } else if let timer = activity.timer {
                ActivityTimerText(timer: timer)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            } else if let state = activity.state {
                secondary(state)
            } else {
                Circle()
                    .fill(.gray.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.gray)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// An activity in a single wing: its icon, ringed by its progress when it has one.
struct ActivityMinimalView: View {
    let activity: ChannelActivity

    var body: some View {
        ZStack {
            if let progress = activity.progress, !activity.isEnded {
                ActivityProgressRing(progress: progress)
                ChannelIconView(icon: activity.icon)
                    .padding(5)
            } else {
                ChannelIconView(icon: activity.icon)
                    .padding(2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if activity.isEnded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
                    .background(Circle().fill(.black))
            }
        }
    }
}

/// The music in a single wing: the spectrum alone. The user already knows what is playing; that
/// something is, is enough.
struct MusicMinimalView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.useMusicVisualizer) private var useMusicVisualizer
    @Default(.coloredSpectrogram) private var coloredSpectrogram

    var body: some View {
        if useMusicVisualizer {
            Rectangle()
                .fill(coloredSpectrogram
                    ? (music.avgColor.map { Color(nsColor: $0) } ?? Color.gray).gradient
                    : Color.gray.gradient)
                .mask {
                    AudioSpectrumView(isPlaying: $music.isPlaying)
                        .frame(width: 16, height: 12)
                }
        } else {
            LottieAnimationContainer()
        }
    }
}

struct ActivityProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
        }
    }
}

/// A timer the system keeps running: no sender has to post an update every second.
struct ActivityTimerText: View {
    let timer: ActivityTimer

    var body: some View {
        Group {
            switch timer {
            case let .since(start):
                Text(start, style: .timer)
            case let .until(end):
                // One reading of the clock for both the check and the range: two could straddle
                // the deadline and build a range that ends before it starts.
                let now = Date()
                if end > now {
                    Text(timerInterval: now ... end, countsDown: true)
                } else {
                    Text(verbatim: "0:00")
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}
