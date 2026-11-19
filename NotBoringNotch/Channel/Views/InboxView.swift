//
//  InboxView.swift
//  NotBoringNotch
//
//  The Inbox tab: every notification the user has not cleared, newest first. Clicking one does
//  what its sender said a click should do; one with nowhere to go opens up to show its body.
//

import Defaults
import SwiftUI

struct InboxView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var channel = NotchChannel.shared
    @ObservedObject private var coordinator = NotchViewCoordinator.shared

    @State private var expanded: Set<String> = []
    @State private var listHeight: CGFloat = 0

    private static let headerHeight: CGFloat = 26
    /// Short enough that one notification does not sit in a tall empty surface, tall enough that
    /// the tab does not jump in height as the first few arrive.
    private static let minimumHeight: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if channel.inbox.isEmpty {
                emptyState
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
        guard !channel.inbox.isEmpty else { return Self.minimumHeight }
        return max(Self.minimumHeight, Self.headerHeight + 6 + listHeight)
    }

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.gray)
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
                    listHeight = height
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
