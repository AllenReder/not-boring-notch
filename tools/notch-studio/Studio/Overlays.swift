// Everything drawn above the camera: captions, keycaps, the fake pointer and its click ripple,
// the title and outro cards, and the clapperboard marker. Overlays do not zoom.
//
// All sizes are stage points (the stage is 1280x720pt and is scaled to 1920x1080 in post).

import SwiftUI

/// A colour nothing in a scene uses; the driver looks for a frame of it.
let markerColor = Color(red: 1, green: 0, blue: 1)

/// The captions, keycaps, pointer and cards for the timeline at the current clock time.
struct OverlayLayer: View {
    let timeline: Timeline

    var body: some View {
        TimelineView(.animation) { _ in
            let t = StudioClock.shared.now
            ZStack {
                if let card = timeline.card(at: t) { CardView(card: card.card, age: card.age, remaining: card.remaining) }
                if let keys = timeline.keys(at: t) { KeycapRow(state: keys) }
                if let caption = timeline.caption(at: t) { CaptionView(text: caption.text, opacity: caption.opacity) }
                ForEach(Array(timeline.ripples(at: t).enumerated()), id: \.offset) { _, ripple in
                    Circle()
                        .stroke(.white.opacity(0.9 * (1 - ripple.progress)), lineWidth: 3)
                        .frame(width: 18 + 70 * ripple.progress, height: 18 + 70 * ripple.progress)
                        .position(ripple.position)
                }
                if let cursor = timeline.cursor(at: t) {
                    Pointer()
                        .scaleEffect(cursor.press, anchor: .topLeading)
                        .opacity(cursor.opacity)
                        .position(x: cursor.position.x + Pointer.size.width / 2, y: cursor.position.y + Pointer.size.height / 2)
                }
            }
            .frame(width: stageSize.width, height: stageSize.height)
        }
    }
}

struct CaptionView: View {
    let text: String
    let opacity: Double

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 36, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 26).padding(.vertical, 11)
                .background(.black.opacity(0.58), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                .opacity(opacity)
                .offset(y: (1 - opacity) * 8)
                .padding(.bottom, 44)
        }
    }
}

struct KeycapRow: View {
    let state: Timeline.KeysState

    /// Where the keycaps sit: under the open notch, above the caption.
    static let centerY: CGFloat = 556

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(state.keys.enumerated()), id: \.offset) { i, key in
                let fresh = i >= state.keys.count - state.pressed
                let pop = fresh ? min(state.age / 0.14, 1) : 1
                Text(key)
                    .font(.system(size: key.count > 1 ? 26 : 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 62)
                    .padding(.horizontal, key.count > 1 ? 18 : 6)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(white: 0.23), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
                    // The key travels down and back as it is pressed.
                    .scaleEffect(fresh ? 0.9 + 0.1 * pop : 1)
                    .offset(y: fresh ? 4 * (1 - pop) : 0)
            }
        }
        .opacity(state.opacity)
        .position(x: stageSize.width / 2, y: Self.centerY)
    }
}

/// The macOS arrow, drawn as the earlier HTML approximation drew it.
struct Pointer: View {
    static let size = CGSize(width: 23, height: 34)

    var body: some View {
        PointerShape()
            .fill(.black)
            .overlay(PointerShape().stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round)))
            .frame(width: Self.size.width, height: Self.size.height)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }
}

private struct PointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        // M3 2 L3 38 L12 29.5 L18.5 44 L24.5 41.3 L18.2 27.4 L30 27.4 Z in a 34x50 box.
        let k = rect.width / 34
        let pts = [(3, 2), (3, 38), (12, 29.5), (18.5, 44), (24.5, 41.3), (18.2, 27.4), (30, 27.4)]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let c = CGPoint(x: rect.minX + pt.0 * k, y: rect.minY + pt.1 * k)
            i == 0 ? p.move(to: c) : p.addLine(to: c)
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Cards

/// The app icon, from the repository's `assets/`.
let appIcon: NSImage = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/app-icon.png")
    return NSImage(contentsOf: url) ?? NSImage(named: "AppIcon") ?? NSImage()
}()

struct CardView: View {
    let card: Card
    let age: Double
    let remaining: Double

    /// 0...1 as an item that starts at `delay` seconds comes up over 0.4 s.
    private func rise(_ delay: Double) -> Double { Ease.out.apply(min(max((age - delay) / 0.4, 0), 1)) }

    var body: some View {
        switch card {
        case .title:
            let fade = min(rise(0), max(remaining / 0.3, 0))
            HStack(spacing: 18) {
                Image(nsImage: appIcon).resizable().frame(width: 74, height: 74)
                Text("Not Boring Notch").font(.system(size: 56, weight: .bold)).tracking(-1.2)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 16, y: 4)
            .opacity(fade)
            .offset(y: (1 - fade) * 14)
            .position(x: stageSize.width / 2, y: 446)

        case .outro:
            ZStack {
                Image(nsImage: appIcon).resizable().frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
                    .modifier(Rise(p: rise(0.0)))
                    .position(x: stageSize.width / 2, y: 262)
                Text("Not Boring Notch").font(.system(size: 78, weight: .bold)).tracking(-2)
                    .foregroundStyle(.white)
                    .modifier(Rise(p: rise(0.25)))
                    .position(x: stageSize.width / 2, y: 392)
                Text("github.com/AllenReder/not-boring-notch")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 13)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.8))
                    .modifier(Rise(p: rise(0.5)))
                    .position(x: stageSize.width / 2, y: 478)
                Text("Free & open source")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .modifier(Rise(p: rise(0.75)))
                    .position(x: stageSize.width / 2, y: 556)
            }
        }
    }
}

private struct Rise: ViewModifier {
    let p: Double
    func body(content: Content) -> some View { content.opacity(p).offset(y: (1 - p) * 20) }
}
