//
//  ReminderLiveActivity.swift
//  NotBoringNotch
//
//  A Reminder in the closed notch: icon, title, subtitle, and a way out. Mirrors the music live
//  activity's geometry so both occupy the same slot at the same width.
//

import AppKit
import SwiftUI

/// Draws whatever a sender named as an icon, falling back to the notch's own bell rather than
/// leaving a hole when the name means nothing to us.
struct ReminderIconView: View {
    let icon: ReminderIcon?

    var body: some View {
        switch icon {
        case let .symbol(name):
            symbol(named: NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "bell")
        case let .image(data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                symbol(named: "bell")
            }
        case let .appBundle(identifier):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                symbol(named: "app")
            }
        case nil:
            symbol(named: "bell")
        }
    }

    private func symbol(named name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
    }
}

struct ReminderLiveActivity: View {
    @EnvironmentObject var vm: NotchViewModel
    let reminder: Reminder

    private var sideWidth: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    var body: some View {
        HStack(spacing: 0) {
            ReminderIconView(icon: reminder.icon)
                .padding(sideWidth * 0.22)
                .frame(width: sideWidth, height: sideWidth)

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(spacing: 6) {
                        Text(reminder.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let subtitle = reminder.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Button {
                ReminderChannel.shared.dismissVisible()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: sideWidth, height: sideWidth, alignment: .center)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear { ReminderChannel.shared.reminderDidAppear(reminder) }
        .onChange(of: reminder) { _, replacement in
            ReminderChannel.shared.reminderDidAppear(replacement)
        }
    }
}
