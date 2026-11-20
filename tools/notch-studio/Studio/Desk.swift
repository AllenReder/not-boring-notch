// The desk the notch sits on: a dark wallpaper of crisp ribbons and hairlines (so the glass lens
// has edges to bend), and a fake macOS menu bar with the notch in its middle. Everything is
// vector, so the camera can zoom 4-5x and stay sharp.
//
// The ribbons are drawn in the 2320x1280 space of the earlier HTML approximation and scaled to
// the stage; the notch's centre is x=1160 in that space.

import SwiftUI

/// A band between `top(x)` and `top(x) + thickness(x)`.
private struct Ribbon: Shape {
    let top: (Double) -> Double
    let thickness: (Double) -> Double
    let unit: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let xs = Array(stride(from: 0.0, through: 2320.0, by: 6.0))
        for (i, x) in xs.enumerated() {
            let pt = CGPoint(x: x * unit, y: top(x) * unit)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        for x in xs.reversed() { p.addLine(to: CGPoint(x: x * unit, y: (top(x) + thickness(x)) * unit)) }
        p.closeSubpath()
        return p
    }
}

private struct Hairline: Shape {
    let y: (Double) -> Double
    let unit: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, x) in stride(from: 0.0, through: 2320.0, by: 6.0).enumerated() {
            let pt = CGPoint(x: x * unit, y: y(x) * unit)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

struct Wallpaper: View {
    /// Points per unit of the 2320x1280 design space.
    static let unit = stageSize.width / 1920
    static let size = CGSize(width: 2320 * unit, height: 1280 * unit)

    private let u = Wallpaper.unit

    private func glow(_ color: Color, _ w: Double, _ h: Double, _ cx: Double, _ cy: Double) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: 0.5 * w * u * 1.15))
            .frame(width: w * u, height: h * u)
            .position(x: cx * u, y: cy * u)
    }

    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Color(red: 0.102, green: 0.078, blue: 0.251), location: 0),
                                   .init(color: Color(red: 0.043, green: 0.039, blue: 0.118), location: 0.7),
                                   .init(color: Color(red: 0.043, green: 0.039, blue: 0.118), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            glow(Color(red: 0.345, green: 0.251, blue: 0.839).opacity(0.95), 1400, 1280, 520, 480)
            glow(Color(red: 0.871, green: 0.361, blue: 0.549).opacity(0.85), 1050, 1150, 1800, 380)
            glow(Color(red: 0.118, green: 0.549, blue: 0.784).opacity(0.8), 1300, 1500, 1400, 1090)
            glow(Color(red: 1, green: 0.667, blue: 0.353).opacity(0.55), 930, 1000, 1060, 130)

            ribbon(top: { 60 + 70 * sin(($0 - 300) / 340) }, thickness: { 64 + 18 * sin($0 / 200) },
                   colors: [Color(red: 1, green: 0.604, blue: 0.384), Color(red: 1, green: 0.31, blue: 0.545)], opacity: 0.92)
            ribbon(top: { 210 + 60 * sin(($0 + 420) / 290) }, thickness: { 40 + 10 * cos($0 / 170) },
                   colors: [Color(red: 0.333, green: 0.839, blue: 1), Color(red: 0.416, green: 0.361, blue: 1)], opacity: 0.92)
            ribbon(top: { 330 + 90 * sin(($0 - 1100) / 460) }, thickness: { _ in 110 },
                   colors: [Color(red: 1, green: 0.753, blue: 0.42), Color(red: 0.831, green: 0.267, blue: 0.486)], opacity: 0.5)
            ribbon(top: { 470 + 70 * sin(($0 - 200) / 380) }, thickness: { _ in 80 },
                   colors: [Color(red: 0.373, green: 0.482, blue: 1), Color(red: 0.651, green: 0.361, blue: 1)], opacity: 0.5)

            ForEach(0..<9, id: \.self) { k in
                Hairline(y: { 140 + Double(k) * 11 + 46 * sin($0 / 230 + Double(k) * 0.35) }, unit: u)
                    .stroke(.white.opacity(k % 3 == 0 ? 0.5 : 0.22), lineWidth: (k % 3 == 0 ? 1.6 : 1) * u)
            }

            // Darkens toward the bottom of the screen, where nothing happens.
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                   .init(color: Color(red: 0.016, green: 0.012, blue: 0.047).opacity(0.55), location: 0.55),
                                   .init(color: Color(red: 0.016, green: 0.012, blue: 0.047).opacity(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private func ribbon(top: @escaping (Double) -> Double, thickness: @escaping (Double) -> Double,
                        colors: [Color], opacity: Double) -> some View {
        ZStack {
            Ribbon(top: top, thickness: thickness, unit: u)
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .opacity(opacity)
            Hairline(y: top, unit: u).stroke(.white.opacity(0.55), lineWidth: 1.4 * u)
        }
    }
}

/// A macOS menu bar of placeholder items, as tall as the notch, with the notch's own space left in the middle.
struct MenuBar: View {
    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.4))
            HStack(spacing: 18) {
                Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
                Text("Fri 9:41")
            }
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 16)
            .frame(width: stageSize.width)
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5) }
    }
}
