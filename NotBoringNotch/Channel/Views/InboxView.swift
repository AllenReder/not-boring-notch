//
//  InboxView.swift
//  NotBoringNotch
//
//  The Inbox tab: the activities in progress, then every notification the user has not cleared,
//  newest first. Clicking one does what its sender said a click should do; a notification with
//  nowhere to go opens up to show its body.
//

import Defaults
import SwiftUI

struct InboxView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var channel = NotchChannel.shared
    @ObservedObject private var coordinator = NotchViewCoordinator.shared

    @State private var expanded: Set<String> = []
    @State private var contentHeight: CGFloat = 0

    private static let headerHeight: CGFloat = 26
    /// Short enough that one notification does not sit in a tall empty surface, tall enough that
    /// the tab does not jump in height as the first few arrive.
    private static let minimumHeight: CGFloat = 110

    private var isEmpty: Bool { channel.inbox.isEmpty && channel.activities.isEmpty }

    /// In the order the closed notch ranks them, so the one on the notch is the one on top.
    private var activities: [ChannelActivity] {
        ClosedNotchArbiter.rank(channel.activities.standings).compactMap { channel.activities.activity(id: $0.id) }
    }

    var body: some View {
        Group {
            if isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    notificationsHeader
                    emptyState
                }
            } else {
                list
            }
        }
        .padding(.horizontal, 6)
        .onAppear { channel.isInboxOnScreen = true }
        .onDisappear {
            channel.isInboxOnScreen = false
            channel.focusedID = nil
        }
        .onChange(of: desiredHeight, initial: true) { _, height in
            coordinator.contentHeight = height
        }
    }

    /// The surface follows what is on it, as the launcher's does; past the tab's declared maximum
    /// the list scrolls.
    private var desiredHeight: CGFloat {
        guard !isEmpty else { return Self.minimumHeight }
        return max(Self.minimumHeight, contentHeight)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.gray)
    }

    private var notificationsHeader: some View {
        HStack {
            sectionHeader("Notifications")
            Spacer()
            if !channel.inbox.isEmpty {
                Button("Clear All") { channel.clearInbox() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray)
            }
        }
        .frame(height: Self.headerHeight)
    }

    private var emptyState: some View {
        Text("No notifications")
            .font(.callout)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: the Inbox holds at most fifty, and the surface is sized from the
                // stack's real height, which a lazy stack only estimates.
                VStack(alignment: .leading, spacing: 4) {
                    if !channel.activities.isEmpty {
                        sectionHeader("In Progress")
                            .frame(height: Self.headerHeight)
                        ForEach(activities) { activity in
                            ActivityRow(
                                activity: activity,
                                onClick: {
                                    channel.open(activity)
                                    if activity.clickTarget != nil { vm.close() }
                                },
                                onDismiss: { channel.dismissActivity(id: activity.id) }
                            )
                            .id("activity-row:" + activity.id)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    notificationsHeader
                    if channel.inbox.isEmpty {
                        Text("No notifications")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                    ForEach(channel.inbox.items) { notification in
                        InboxRow(
                            notification: notification,
                            isFocused: notification.id == channel.focusedID,
                            isExpanded: expanded.contains(notification.id),
                            onClick: { click(notification) },
                            onAction: { action in
                                channel.perform(action, of: notification)
                                vm.close()
                            },
                            onClear: { channel.remove(id: notification.id) }
                        )
                        .id(notification.id)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    contentHeight = height
                }
            }
            .scrollIndicators(.never)
            .onAppear {
                if let focused = channel.focusedID {
                    proxy.scrollTo(focused, anchor: .top)
                }
            }
            .onChange(of: channel.focusedID) { _, focused in
                guard let focused else { return }
                withAnimation(.smooth) { proxy.scrollTo(focused, anchor: .top) }
            }
        }
    }

    private func click(_ notification: ChannelNotification) {
        if notification.clickTarget != nil {
            channel.open(notification)
            vm.close()
        } else {
            withAnimation(.smooth(duration: 0.25)) {
                if expanded.contains(notification.id) {
                    expanded.remove(notification.id)
                } else {
                    expanded.insert(notification.id)
                }
            }
        }
    }
}

/// An activity in the Inbox: everything the closed notch had room for only one of.
private struct ActivityRow: View {
    let activity: ChannelActivity
    let onClick: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let stale = activity.isStale(at: context.date)
            HStack(alignment: .top, spacing: 10) {
                ChannelIconView(icon: activity.icon)
                    .padding(4)
                    .frame(width: 28, height: 28)
                    .opacity(stale ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    titleLine
                    statusLine(stale: stale)
                    if let progress = activity.progress, !activity.isEnded {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .controlSize(.small)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                dismissButton
            }
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

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(activity.displayTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if activity.clickTarget != nil {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.gray)
                    .opacity(isHovering ? 1 : 0)
            }
            Spacer(minLength: 4)
            if let timer = activity.timer, !activity.isEnded {
                ActivityTimerText(timer: timer)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            } else {
                Text(activity.startedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func statusLine(stale: Bool) -> some View {
        HStack(spacing: 4) {
            if activity.isEnded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(activity.state ?? String(localized: "Ended"))
            } else {
                if let state = activity.state {
                    Text(state)
                }
                if stale {
                    Text(activity.state == nil ? "No update for a while" : "· no update for a while")
                        .foregroundStyle(.orange.opacity(0.8))
                }
                if let progress = activity.progress {
                    Spacer(minLength: 4)
                    Text(ActivityDetail.percent(progress))
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.gray)
        .lineLimit(1)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.gray)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .accessibilityLabel(Text("Dismiss"))
    }
}

private struct InboxRow: View {
    let notification: ChannelNotification
    let isFocused: Bool
    let isExpanded: Bool
    let onClick: () -> Void
    let onAction: (ChannelAction) -> Void
    let onClear: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChannelIconView(icon: notification.icon)
                .padding(4)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                if let subtitle = notification.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                if let body = notification.body {
                    Text(Self.markdown(body))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(isExpanded ? nil : 2)
                        // Not selectable: a row is a click target, and selection would take the
                        // click from it.
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !notification.actions.isEmpty {
                    actionButtons
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            clearButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.12 : (isHovering ? 0.09 : 0.06)))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onClick)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.15)) { isHovering = hovering }
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(notification.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if notification.clickTarget != nil {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.gray)
                    .opacity(isHovering ? 1 : 0)
            }
            Spacer(minLength: 4)
            Text(notification.deliveredAt, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            ForEach(Array(notification.actions.enumerated()), id: \.offset) { _, action in
                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: 4) {
                        if case .copy = action.kind {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        Text(action.title)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
    }

    private var clearButton: some View {
        Button(action: onClear) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.gray)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .accessibilityLabel(Text("Clear"))
    }

    /// Inline Markdown — emphasis, code, links — with the sender's line breaks kept. Anything that
    /// does not parse is shown as written.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
