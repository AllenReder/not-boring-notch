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

/// Smoothly renders text in the closed reminder slot: static text when it fits, or continuous
/// marquee ticker when the text length exceeds the available frame width.
struct ScrollableReminderText: View {
    let text: String
    let font: Font
    var fontWeight: Font.Weight = .medium
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let frameWidth: CGFloat

    static func measureWidth(_ text: String, size: CGFloat = 11.5, weight: NSFont.Weight = .medium) -> CGFloat {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attributes = [NSAttributedString.Key.font: font]
        return ceil((singleLine as NSString).size(withAttributes: attributes).width)
    }

    private var textWidth: CGFloat {
        Self.measureWidth(
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
        ScrollableReminderText.measureWidth(text, size: size, weight: weight)
    }

    /// Determines the secondary text shown on the right wing:
    /// - Explicit `subtitle` if given;
    /// - Otherwise, the first non-empty line of `body` as an automatic preview;
    /// - Otherwise `nil`.
    static func previewText(for reminder: Reminder) -> String? {
        if let subtitle = reminder.subtitle, !subtitle.isEmpty {
            return subtitle
        }
        if let body = reminder.body {
            let lines = body.components(separatedBy: .newlines)
            if let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return first.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Adapts the wing width dynamically to fit the content without any arbitrary minimum width.
    /// Left wing holds icon + title; right wing holds subtitle (or body preview).
    /// Both wings are kept strictly symmetrical to maintain physical camera alignment.
    static func calculatedWingWidth(for reminder: Reminder) -> CGFloat {
        let maxWidth: CGFloat = 210
        let minPhysicalWidth: CGFloat = 28

        // Left wing has: padding(8) + icon(18) + spacing(6) + title + padding(6) = 38 + titleWidth
        let titleWidth = measureTextWidth(reminder.title, size: 11.5, weight: .medium)
        let leftNeeded = 38 + titleWidth

        // Right wing has: preview text or status
        let rightNeeded: CGFloat
        if let preview = previewText(for: reminder) {
            let previewWidth = measureTextWidth(preview, size: 11.5, weight: .regular)
            rightNeeded = 16 + previewWidth + (reminder.isSticky ? 16 : 0)
        } else {
            rightNeeded = reminder.isSticky ? 26 : minPhysicalWidth
        }

        let needed = max(leftNeeded, rightNeeded)
        return min(maxWidth, max(minPhysicalWidth, needed))
    }

    var wingWidth: CGFloat {
        Self.calculatedWingWidth(for: reminder)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left wing: Icon + Title
            leftWing
                .frame(width: wingWidth, alignment: .leading)

            // Center: Black spacer matching the flat base of the physical camera notch
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            // Right wing: Subtitle / preview / indicator
            rightWing
                .frame(width: wingWidth, alignment: .trailing)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .reminderClock(reminder)
    }

    @ViewBuilder
    private var leftWing: some View {
        HStack(spacing: 6) {
            ReminderIconView(icon: reminder.icon)
                .frame(width: 18, height: 18)

            ScrollableReminderText(
                text: reminder.title,
                font: .subheadline,
                fontWeight: .medium,
                nsFont: .subheadline,
                textColor: .white,
                frameWidth: max(20, wingWidth - 38)
            )
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var rightWing: some View {
        HStack(spacing: 6) {
            if let preview = Self.previewText(for: reminder) {
                ScrollableReminderText(
                    text: preview,
                    font: .subheadline,
                    fontWeight: .regular,
                    nsFont: .subheadline,
                    textColor: .gray,
                    frameWidth: max(20, wingWidth - 16 - (reminder.isSticky ? 16 : 0))
                )
            } else {
                Spacer(minLength: 0)
            }

            if reminder.isSticky {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray.opacity(0.7))
            } else if Self.previewText(for: reminder) == nil {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray.opacity(0.35))
            }
        }
        .padding(.trailing, 10)
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
