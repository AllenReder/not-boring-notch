//
//  AgentViews.swift
//  NotBoringNotch
//
//  The agents on the closed notch, in the two sizes the arbiter hands out:
//
//  - compact: both wings — the marks of the kinds at work on the left, stacked, breathing while
//    any of them works, still with an amber dot while somebody waits for the user; on the right,
//    how many wait (`! 1`, amber) and how many work (white), a light rule between.
//  - minimal: the right wing alone — the spinner with the count in it — beside the music.
//
//  The geometry follows the banner's: both wings the same width, so the content stays centred on
//  the camera housing.
//

import SwiftUI

extension AgentSummary {
    /// What the arbiter ranks the agents by.
    var presence: AgentPresence {
        isWaiting ? .waiting : (working > 0 ? .working : .none)
    }

    var isWaiting: Bool { waiting > 0 }

    /// "! 1" when somebody is waiting for the user.
    var waitingLabel: String? { isWaiting ? "! \(waiting)" : nil }

    /// How many are at work. Left out when everybody who is not idle is waiting.
    var workingLabel: String? { isWaiting && working == 0 ? nil : String(working) }
}

/// Amber, as the system uses for "this needs you".
private let agentAttentionColor = Color.orange

extension AgentKind {
    var markAsset: String {
        switch self {
        case .claudeCode: return "AgentClaudeCode"
        case .codex: return "AgentCodex"
        case .pi: return "AgentPi"
        }
    }

    /// The colour a one-colour mark is drawn in. Nil for a mark drawn in its own colours.
    var markTint: Color? {
        switch self {
        case .claudeCode: return Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case .codex: return .white
        case .pi: return nil
        }
    }
}

extension AgentBadge {
    var color: Color {
        switch self {
        case .finished: return .green
        case .failed: return .red
        case .waiting: return agentAttentionColor
        }
    }
}

/// The agent's own mark, in its own colour.
struct AgentMark: View {
    let kind: AgentKind

    var body: some View {
        Image(kind.markAsset)
            .renderingMode(kind.markTint == nil ? .original : .template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(kind.markTint ?? .primary)
    }
}

/// A mark with a dot on its corner for how the turn came out.
struct AgentBadgedMark: View {
    let kind: AgentKind
    let badge: AgentBadge

    var body: some View {
        AgentMark(kind: kind)
            .overlay(alignment: .bottomTrailing) { AgentBadgeDot(color: badge.color) }
    }
}

/// The dot on a mark's corner, ringed in black so it reads against the mark.
struct AgentBadgeDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background(Circle().fill(.black).padding(-1.5))
            .offset(x: 2, y: 2)
    }
}

/// One mark per kind of agent at work, each overlapping the one before it. The stack breathes
/// while something works; while somebody waits it holds still, with an amber dot.
struct AgentMarkStack: View {
    let kinds: [AgentKind]
    let isBreathing: Bool
    let isWaiting: Bool

    /// Seconds for one breath, dim and back.
    private static let breath: TimeInterval = 2.4

    static let markSize: CGFloat = 16
    private static let step: CGFloat = 14

    static func width(for count: Int) -> CGFloat {
        markSize + step * CGFloat(max(0, count - 1))
    }

    var body: some View {
        // The timeline stops asking for frames when the stack is not breathing.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !breathes)) { context in
            let depth = breathes ? Self.depth(at: context.date) : 0
            marks
                .opacity(1 - 0.55 * depth)
                .scaleEffect(1 - 0.1 * depth)
        }
        .overlay(alignment: .bottomTrailing) {
            if isWaiting { AgentBadgeDot(color: agentAttentionColor) }
        }
        .frame(width: Self.width(for: kinds.count), height: Self.markSize, alignment: .leading)
    }

    private var breathes: Bool { isBreathing && !isWaiting }

    /// 0 at full breath, 1 at the dimmest, easing in and out.
    private static func depth(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: breath) / breath
        return (1 - cos(phase * 2 * .pi)) / 2
    }

    private var marks: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                AgentMark(kind: kind)
                    .frame(width: Self.markSize, height: Self.markSize)
                    .offset(x: CGFloat(index) * Self.step)
            }
        }
        .frame(width: Self.width(for: kinds.count), height: Self.markSize, alignment: .leading)
    }
}

struct AgentCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    let summary: AgentSummary

    private static let minimumWingWidth: CGFloat = 28

    private static let countSpacing: CGFloat = 6

    static func wingWidth(for summary: AgentSummary) -> CGFloat {
        // padding(8) + marks + padding(8)
        let leftNeeded = 16 + AgentMarkStack.width(for: summary.kinds.count)
        let labels = [summary.waitingLabel, summary.workingLabel].compactMap { $0 }
        let text = labels.map { ScrollableBannerText.measureWidth($0, weight: .semibold) }.reduce(0, +)
        let rule = labels.count == 2 ? 1 + 2 * countSpacing : 0
        // the count + padding(10) on the right, and a little air on the left of it
        let rightNeeded = 16 + text + rule
        return max(minimumWingWidth, leftNeeded, rightNeeded)
    }

    private var wingWidth: CGFloat { Self.wingWidth(for: summary) }

    var body: some View {
        HStack(spacing: 0) {
            AgentMarkStack(kinds: summary.kinds, isBreathing: summary.working > 0, isWaiting: summary.isWaiting)
                .padding(.leading, 8)
                .frame(width: wingWidth, alignment: .leading)

            // The flat base of the physical camera housing.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchGap)

            count
                .padding(.trailing, 10)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    /// Amber for those waiting on the user, grey for those at work, a light rule between.
    private var count: some View {
        HStack(spacing: Self.countSpacing) {
            if let waiting = summary.waitingLabel {
                Text(verbatim: waiting).foregroundStyle(agentAttentionColor)
            }
            if summary.waitingLabel != nil, summary.workingLabel != nil {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 1, height: 11)
            }
            if let working = summary.workingLabel {
                Text(verbatim: working).foregroundStyle(Color.gray)
            }
        }
        .font(.subheadline)
        .fontWeight(.semibold)
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// The agents in a single wing: the spinner with the count inside it.
struct AgentMinimalView: View {
    let summary: AgentSummary

    var body: some View {
        ZStack {
            AgentSpinner(isSpinning: summary.working > 0,
                         tint: summary.isWaiting ? agentAttentionColor : .white)
            Text(summary.isWaiting ? "!" : String(summary.working))
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(summary.isWaiting ? agentAttentionColor : Color.white)
        }
        .frame(width: 18, height: 18)
    }
}

/// A ring that turns while something is at work, and stands still when nothing is.
struct AgentSpinner: View {
    let isSpinning: Bool
    let tint: Color

    var body: some View {
        // The timeline stops asking for frames when the ring is not turning.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isSpinning)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(isSpinning ? turn * 360 : -90))
        }
    }
}

// MARK: - In the Inbox

/// An agent session in the Inbox: what the closed notch had room to summarise only as a count.
struct AgentRow: View {
    let session: AgentSession
    let onClick: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if case .waiting = session.phase {
                    AgentBadgedMark(kind: session.agent, badge: .waiting)
                } else {
                    AgentMark(kind: session.agent)
                }
            }
            .padding(5)
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.projectName.isEmpty ? session.agent.displayName : session.projectName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if session.jumpTarget != nil {
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.gray)
                            .opacity(isHovering ? 1 : 0)
                    }
                    Spacer(minLength: 4)
                    elapsed
                }
                phaseLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.09 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onClick)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { isHovering = hovering }
        }
    }

    /// How long this turn has run, or how long ago the session was last heard from.
    @ViewBuilder
    private var elapsed: some View {
        Group {
            if let started = session.turnStartedAt {
                Text(started, style: .timer)
                    .monospacedDigit()
            } else {
                Text(session.updatedAt, format: .relative(presentation: .named))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.gray)
        .lineLimit(1)
    }

    private var phaseLine: some View {
        HStack(spacing: 4) {
            switch session.phase {
            case let .working(tool):
                Text("Working")
                if let tool { Text(verbatim: "· \(tool)") }
            case let .waiting(.approval(tool)):
                Text("Waiting for approval").foregroundStyle(agentAttentionColor)
                if let tool { Text(verbatim: "· \(tool)") }
            case .waiting(.question):
                Text("Has a question").foregroundStyle(agentAttentionColor)
            case .idle:
                Text("Idle")
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.gray)
        .lineLimit(1)
    }
}
