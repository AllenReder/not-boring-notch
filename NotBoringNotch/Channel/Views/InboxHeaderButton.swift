//
//  InboxHeaderButton.swift
//  NotBoringNotch
//
//  The way into the Inbox: a bell in the open notch's right-hand cluster, beside Settings.
//
//  It is not one of the tabs on the left, for two reasons. The Inbox is the notch's notification
//  center, and macOS keeps its own in the top-right corner. And the left of the header has room for
//  about four tabs before the camera housing: on a notched MacBook the side is ~188pt, four tabs
//  are ~188pt, and a fifth would slide under the notch.
//

import Defaults
import SwiftUI

struct InboxHeaderButton: View {
    @ObservedObject private var channel = NotchChannel.shared
    @ObservedObject private var coordinator = NotchViewCoordinator.shared
    @Default(.notchChannelEnabled) private var isEnabled

    /// There when the Inbox has something in it, a notification or an agent session, and while it is
    /// open, so clearing the last
    /// notification does not pull the button out from under the pointer.
    static func isShown(enabled: Bool, inboxIsEmpty: Bool, currentView: NotchViews) -> Bool {
        enabled && (!inboxIsEmpty || currentView == .inbox)
    }

    private var isSelected: Bool { coordinator.currentView == .inbox }

    var body: some View {
        if Self.isShown(enabled: isEnabled,
                        inboxIsEmpty: channel.inbox.isEmpty && channel.agents.isEmpty,
                        currentView: coordinator.currentView) {
            Button {
                withAnimation(.smooth) {
                    // A second press goes back where the notch normally opens, like a toggle.
                    coordinator.currentView = isSelected ? .home : .inbox
                }
            } label: {
                Capsule()
                    .fill(isSelected ? Color(nsColor: .secondarySystemFill) : .black)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "bell.fill")
                            .foregroundColor(isSelected ? .white : .gray)
                            .imageScale(.medium)
                    }
                    .overlay(alignment: .topTrailing) {
                        if channel.inbox.unreadCount > 0 {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                                .offset(x: -5, y: 5)
                        }
                    }
            }
            .buttonStyle(PlainButtonStyle())
            .help(Text("Notifications"))
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}
