//
//  BannerView.swift
//  NotBoringNotch
//
//  A notification as a banner in the closed notch: icon and title on the left wing, subtitle on
//  the right. Mirrors the music live activity's geometry so both occupy the same slot.
//

import AppKit
import SwiftUI

/// Draws whatever a sender named as an icon, falling back to the notch's own bell rather than
/// leaving a hole when the name means nothing to us.
struct ChannelIconView: View {
    let icon: ChannelIcon?

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

/// Text in a banner's wing: static when it fits, a marquee when it does not.
struct ScrollableBannerText: View {
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
        Self.measureWidth(text, size: 11.5, weight: fontWeight == .medium ? .medium : .regular)
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

struct BannerView: View {
    @EnvironmentObject var vm: NotchViewModel
    let notification: ChannelNotification

    /// The secondary text on the right wing: the subtitle if given, otherwise the first non-empty
    /// line of the body as a preview, otherwise nothing.
    static func previewText(for notification: ChannelNotification) -> String? {
        if let subtitle = notification.subtitle, !subtitle.isEmpty {
            return subtitle
        }
        guard let body = notification.body else { return nil }
        return body.components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The line under the notch, as a sneak peek has: the body's first line, when the subtitle
    /// already holds the right wing. Without a subtitle the right wing previews the body itself.
    static func peekText(for notification: ChannelNotification) -> String? {
        guard let subtitle = notification.subtitle, !subtitle.isEmpty, let body = notification.body else { return nil }
        return body.components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func showsPin(_ notification: ChannelNotification) -> Bool {
        notification.banner == .untilSeen
    }

    /// Fits the wings to the content, with no arbitrary minimum. Both wings are the same width so
    /// the content stays centred on the camera housing.
    static func wingWidth(for notification: ChannelNotification) -> CGFloat {
        let maxWidth: CGFloat = 210
        let minPhysicalWidth: CGFloat = 28
        let pin: CGFloat = showsPin(notification) ? 16 : 0

        // padding(8) + icon(18) + spacing(6) + title + padding(6)
        let leftNeeded = 38 + ScrollableBannerText.measureWidth(notification.title, weight: .medium)

        let rightNeeded: CGFloat
        if let preview = previewText(for: notification) {
            rightNeeded = 16 + ScrollableBannerText.measureWidth(preview, weight: .regular) + pin
        } else {
            rightNeeded = showsPin(notification) ? 26 : minPhysicalWidth
        }

        return min(maxWidth, max(minPhysicalWidth, leftNeeded, rightNeeded))
    }

    private var wingWidth: CGFloat { Self.wingWidth(for: notification) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftWing
                    .frame(width: wingWidth, alignment: .leading)

                // The flat base of the physical camera housing.
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchGap)

                rightWing
                    .frame(width: wingWidth, alignment: .trailing)
            }
            .fixedSize(horizontal: true, vertical: false)
            // The closed notch's own height, not the effective one: a time-sensitive banner is
            // drawn even while fullscreen has collapsed the notch to nothing.
            .frame(height: vm.closedNotchSize.height, alignment: .center)

            if let peek = Self.peekText(for: notification) {
                peekLine(peek)
            }
        }
        .bannerClock(notification)
    }

    /// Spans the banner, scrolling when the line is longer than that.
    private func peekLine(_ text: String) -> some View {
        let width = 2 * wingWidth + vm.closedNotchGap - 2 * Self.peekInset
        return ScrollableBannerText(
            text: text,
            font: .subheadline,
            fontWeight: .regular,
            nsFont: .subheadline,
            textColor: .gray,
            frameWidth: width
        )
        .frame(width: width)
        .padding(.horizontal, Self.peekInset)
        .padding(.bottom, 10)
    }

    private static let peekInset: CGFloat = 12

    private var leftWing: some View {
        HStack(spacing: 6) {
            ChannelIconView(icon: notification.icon)
                .frame(width: 18, height: 18)

            ScrollableBannerText(
                text: notification.title,
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

    private var rightWing: some View {
        let preview = Self.previewText(for: notification)
        let pin = Self.showsPin(notification)
        return HStack(spacing: 6) {
            if let preview {
                ScrollableBannerText(
                    text: preview,
                    font: .subheadline,
                    fontWeight: .regular,
                    nsFont: .subheadline,
                    textColor: .gray,
                    frameWidth: max(20, wingWidth - 16 - (pin ? 16 : 0))
                )
            } else {
                Spacer(minLength: 0)
            }

            if pin {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray.opacity(0.7))
            } else if preview == nil {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.gray.opacity(0.35))
            }
        }
        .padding(.trailing, 10)
    }
}

/// Starts a banner's clock when it is drawn, so a banner that arrives while the notch cannot show
/// it keeps its whole duration for when it can.
private struct BannerClock: ViewModifier {
    let notification: ChannelNotification

    func body(content: Content) -> some View {
        content
            .onAppear { NotchChannel.shared.startShowing(notification) }
            .onChange(of: notification) { _, replacement in
                NotchChannel.shared.startShowing(replacement)
            }
    }
}

extension View {
    func bannerClock(_ notification: ChannelNotification) -> some View {
        modifier(BannerClock(notification: notification))
    }
}
