//
//  AgentViews.swift
//  NotBoringNotch
//
//  The agents on the closed notch, in the two sizes the arbiter hands out:
//
//  - compact: both wings — the marks of the kinds at work on the left, stacked, breathing while
//    any of them works, still with an amber dot while somebody waits for the user; on the right,
//    how many wait (`! 1`, amber) and how many work (white), a light rule between.
//  - minimal: the right wing alone, beside the music — the mark of the kind with the most
//    sessions, breathing, with how many are at work on its corner when there is more than one.
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
        case .opencode: return "AgentOpenCode"
        }
    }

    /// The colour a one-colour mark is drawn in. Nil for a mark drawn in its own colours.
    var markTint: Color? {
        switch self {
        case .claudeCode: return Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case .codex: return .white
        case .pi: return nil
        case .opencode: return .white
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

// MARK: - Flying between the closed notch and the Inbox

private struct AgentMarkNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Where the closed notch's marks and the Inbox's rows match up. Nil where nothing flies.
    var agentMarkNamespace: Namespace.ID? {
        get { self[AgentMarkNamespaceKey.self] }
        set { self[AgentMarkNamespaceKey.self] = newValue }
    }
}

private struct AgentMarkMatch: ViewModifier {
    @Environment(\.agentMarkNamespace) private var namespace
    let kind: AgentKind
    let holds: Bool

    func body(content: Content) -> some View {
        if let namespace, holds {
            content.matchedGeometryEffect(id: kind, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Makes this the mark `kind` flies from or to as the notch opens and closes. Only one view of
    /// each side may hold a kind at a time, so a row that is not its kind's first passes `holds: false`.
    func agentMarkMatch(_ kind: AgentKind, holds: Bool = true) -> some View {
        modifier(AgentMarkMatch(kind: kind, holds: holds))
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

/// Dims and shrinks its content a little and back, slowly, while `isActive`. Every breathing mark
/// keeps the same time, so the closed notch and the Inbox breathe together.
struct AgentBreathing: ViewModifier {
    let isActive: Bool

    /// Seconds for one breath, dim and back.
    private static let breath: TimeInterval = 2.4

    func body(content: Content) -> some View {
        // The timeline stops asking for frames while nothing breathes.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let depth = isActive ? Self.depth(at: context.date) : 0
            content
                .opacity(1 - 0.55 * depth)
                .scaleEffect(1 - 0.1 * depth)
        }
    }

    /// 0 at full breath, 1 at the dimmest, easing in and out.
    private static func depth(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: breath) / breath
        return (1 - cos(phase * 2 * .pi)) / 2
    }
}

/// One mark per kind of agent at work, each overlapping the one before it. The stack breathes
/// while something works; while somebody waits it holds still, with an amber dot.
struct AgentMarkStack: View {
    let kinds: [AgentKind]
    let isBreathing: Bool
    let isWaiting: Bool

    static let markSize: CGFloat = 16
    private static let step: CGFloat = 14

    static func width(for count: Int) -> CGFloat {
        markSize + step * CGFloat(max(0, count - 1))
    }

    var body: some View {
        marks
            .overlay(alignment: .bottomTrailing) {
                if isWaiting { AgentBadgeDot(color: agentAttentionColor) }
            }
            .frame(width: Self.width(for: kinds.count), height: Self.markSize, alignment: .leading)
    }

    private var marks: some View {
        HStack(spacing: Self.step - Self.markSize) {
            ForEach(kinds, id: \.self) { kind in
                // Each mark breathes inside its match, so the geometry the match reads is the layout frame.
                AgentMark(kind: kind)
                    .frame(width: Self.markSize, height: Self.markSize)
                    .modifier(AgentBreathing(isActive: isBreathing && !isWaiting))
                    .agentMarkMatch(kind)
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

/// The agents in a single wing. Agents waiting on the user never get here: they take the whole notch.
struct AgentMinimalView: View {
    let summary: AgentSummary

    private var count: Int { summary.working + summary.waiting }

    var body: some View {
        if let kind = summary.leadKind {
            AgentMark(kind: kind)
                .frame(width: AgentMarkStack.markSize, height: AgentMarkStack.markSize)
                .modifier(AgentBreathing(isActive: summary.working > 0))
                .agentMarkMatch(kind)
                .overlay(alignment: .bottomTrailing) {
                    if count > 1 { countBadge }
                }
        }
    }

    /// The count on the mark's corner, ringed in black like the Inbox's dots.
    private var countBadge: some View {
        Text(verbatim: String(count))
            .font(.system(size: 8, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.gray)
            .padding(.horizontal, 1.5)
            .background(RoundedRectangle(cornerRadius: 3).fill(.black))
            .fixedSize()
            .offset(x: 5, y: 4)
    }
}

// MARK: - In the Inbox

/// An agent session in the Inbox: what the closed notch had room to summarise only as a count.
struct AgentRow: View {
    let session: AgentSession
    /// Whether the closed notch's mark of this kind flies to this row. One row per kind.
    let holdsMark: Bool
    let onClick: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentMark(kind: session.agent)
                .modifier(AgentBreathing(isActive: session.phase.isWorking))
                .agentMarkMatch(session.agent, holds: holdsMark)
                .overlay(alignment: .bottomTrailing) {
                    if let badge { AgentBadgeDot(color: badge.color) }
                }
                .padding(5)
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let detail = session.titleDetail {
                        // The folder stays whole; a long title gives way first.
                        Text(verbatim: "· \(detail)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
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

    /// Amber while it waits for the user; once idle, how its last turn ended. A working mark
    /// breathes instead.
    private var badge: AgentBadge? {
        switch session.phase {
        case .waiting: return .waiting
        case .working: return nil
        case .idle:
            switch session.lastTurn {
            case .finished: return .finished
            case .failed: return .failed
            case nil: return nil
            }
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
