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
                    .clipShape(RoundedRectangle(cornerRadius: 3.5))
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

    private var wingWidth: CGFloat { 110 }

    var body: some View {
        HStack(spacing: 0) {
            // Left wing: Icon + Title flanking the physical notch
            HStack(spacing: 6) {
                ReminderIconView(icon: reminder.icon)
                    .frame(width: 18, height: 18)

                Text(reminder.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 8)
            .frame(width: wingWidth, alignment: .leading)

            // Center: Black spacer matching the flat base of the physical camera notch
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            // Right wing: Subtitle or indicator flanking the physical notch
            HStack(spacing: 6) {
                if let subtitle = reminder.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if reminder.isSticky {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray.opacity(0.7))
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }
            .padding(.trailing, 10)
            .frame(width: wingWidth, alignment: .trailing)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .reminderClock(reminder)
    }
}

/// Starts a Reminder's clock when the Reminder is drawn — the closed notch and the open detail
/// both use this, so which one is on screen can never change how long a Reminder is given.
private struct ReminderClock: ViewModifier {
    let reminder: Reminder

    func body(content: Content) -> some View {
        content
            .onAppear { ReminderChannel.shared.startShowing(reminder) }
            .onChange(of: reminder) { _, replacement in
                ReminderChannel.shared.startShowing(replacement)
            }
    }
}

extension View {
    func reminderClock(_ reminder: Reminder) -> some View {
        modifier(ReminderClock(reminder: reminder))
    }
}
