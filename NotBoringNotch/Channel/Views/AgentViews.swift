//
//  AgentViews.swift
//  NotBoringNotch
//
//  The agents on the closed notch, in the two sizes the arbiter hands out:
//
//  - compact: both wings — the agent's mark and a spinner on the left, how many are at work on
//    the right, or `! waiting · working` in amber when somebody is waiting for the user.
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

    /// The mark of the agents at work: their own when they are all one kind, a generic one when
    /// the kinds are mixed.
    var symbolName: String {
        kinds.count == 1 ? kinds[0].symbolName : "sparkles"
    }

    var isWaiting: Bool { waiting > 0 }

    /// "3", or "! 1 · 2" when somebody is waiting; without the second number when nobody is at work.
    var countText: String {
        guard isWaiting else { return String(working) }
        return working == 0 ? "! \(waiting)" : "! \(waiting) · \(working)"
    }
}

/// Amber, as the system uses for "this needs you".
private let agentAttentionColor = Color.orange

struct AgentCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    let summary: AgentSummary

    /// padding(8) + mark(16) + spacing(6) + spinner(14) + padding(6)
    private static let leftNeeded: CGFloat = 50
    private static let minimumWingWidth: CGFloat = 28

    static func wingWidth(for summary: AgentSummary) -> CGFloat {
        // text + padding(10) on the right, and a little air on the left of it
        let rightNeeded = 16 + ScrollableBannerText.measureWidth(summary.countText, weight: .semibold)
        return max(minimumWingWidth, leftNeeded, rightNeeded)
    }

    private var wingWidth: CGFloat { Self.wingWidth(for: summary) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: summary.symbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                AgentSpinner(isSpinning: summary.working > 0,
                             tint: summary.isWaiting ? agentAttentionColor : .white)
                    .frame(width: 14, height: 14)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(width: wingWidth, alignment: .leading)

            // The flat base of the physical camera housing.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchGap)

            Text(summary.countText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(summary.isWaiting ? agentAttentionColor : Color.gray)
                .lineLimit(1)
                .padding(.trailing, 10)
                .frame(width: wingWidth, alignment: .trailing)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
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
            Image(systemName: session.agent.symbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .padding(7)
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
