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

/// Smoothly renders notification text: static text when it fits, or continuous marquee ticker
/// when the text length exceeds the available frame width.
struct ScrollableNotificationText: View {
    let text: String
    let font: Font
    var fontWeight: Font.Weight = .medium
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let frameWidth: CGFloat

    private var textWidth: CGFloat {
        ReminderLiveActivity.measureTextWidth(
            text,
            size: 11.5,
            weight: fontWeight == .medium ? .medium : .regular
        )
    }

    var body: some View {
        if textWidth > frameWidth {
            MarqueeText(
                .constant(text),
                font: font.weight(fontWeight),
                nsFont: nsFont,
                textColor: textColor,
                minDuration: 1.5,
                frameWidth: frameWidth
            )
            .frame(width: frameWidth, height: 18)
        } else {
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
    }
}

struct ReminderLiveActivity: View {
    @EnvironmentObject var vm: NotchViewModel
    let reminder: Reminder

    static func measureTextWidth(_ text: String, size: CGFloat = 11.5, weight: NSFont.Weight = .medium) -> CGFloat {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributes = [NSAttributedString.Key.font: font]
        return ceil((singleLine as NSString).size(withAttributes: attributes).width)
    }

    /// Adapts the wing width dynamically to fit the content:
    /// - With subtitle: left wing holds icon + title, right wing holds subtitle.
    /// - Without subtitle: left wing holds icon only, right wing holds the main title.
    /// Both wings are kept strictly symmetrical to maintain physical camera alignment.
    static func calculatedWingWidth(for reminder: Reminder) -> CGFloat {
        let maxWidth: CGFloat = 210

        if let subtitle = reminder.subtitle {
            let titleWidth = measureTextWidth(reminder.title, size: 11.5, weight: .medium)
            let leftNeeded = 38 + titleWidth

            let subtitleWidth = measureTextWidth(subtitle, size: 11.5, weight: .regular)
            let rightNeeded = 16 + subtitleWidth + (reminder.isSticky ? 16 : 0)

            let needed = max(leftNeeded, rightNeeded)
            return min(maxWidth, max(110, needed))
        } else {
            let titleWidth = measureTextWidth(reminder.title, size: 11.5, weight: .medium)
            let rightNeeded = 20 + titleWidth + (reminder.isSticky ? 16 : 0)

            return min(maxWidth, max(75, rightNeeded))
        }
    }

    var wingWidth: CGFloat {
        Self.calculatedWingWidth(for: reminder)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left wing
            leftWing
                .frame(width: wingWidth, alignment: reminder.subtitle != nil ? .leading : .center)

            // Center: Black spacer matching the flat base of the physical camera notch
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            // Right wing
            rightWing
                .frame(width: wingWidth, alignment: reminder.subtitle != nil ? .trailing : .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .reminderClock(reminder)
    }

    @ViewBuilder
    private var leftWing: some View {
        if reminder.subtitle != nil {
            HStack(spacing: 6) {
                ReminderIconView(icon: reminder.icon)
                    .frame(width: 18, height: 18)

                ScrollableNotificationText(
                    text: reminder.title,
                    font: .subheadline,
                    fontWeight: .medium,
                    nsFont: .subheadline,
                    textColor: .white,
                    frameWidth: max(30, wingWidth - 32)
                )
            }
            .padding(.leading, 8)
        } else {
            // No subtitle: icon sits cleanly centered in the left wing
            ReminderIconView(icon: reminder.icon)
                .frame(width: 20, height: 20)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if let subtitle = reminder.subtitle {
            HStack(spacing: 6) {
                ScrollableNotificationText(
                    text: subtitle,
                    font: .subheadline,
                    fontWeight: .regular,
                    nsFont: .subheadline,
                    textColor: .gray,
                    frameWidth: max(30, wingWidth - 16 - (reminder.isSticky ? 16 : 0))
                )

                if reminder.isSticky {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray.opacity(0.7))
                }
            }
            .padding(.trailing, 10)
        } else {
            // No subtitle: main title takes the right wing
            HStack(spacing: 6) {
                ScrollableNotificationText(
                    text: reminder.title,
                    font: .subheadline,
                    fontWeight: .medium,
                    nsFont: .subheadline,
                    textColor: .white,
                    frameWidth: max(30, wingWidth - 18 - (reminder.isSticky ? 16 : 0))
                )

                if reminder.isSticky {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray.opacity(0.7))
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
        }
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
