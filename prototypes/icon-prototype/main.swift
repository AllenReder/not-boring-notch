//
//  main.swift — PROTOTYPE (throwaway, delete me)
//  prototypes/icon-prototype/
//
//  Question: "What should the Not Boring Notch app icon look like with Liquid Glass?"
//  Three radically different variants:
//    - Variant A: Liquid Prism Notch (Crystal glass notch with rainbow dispersion rim)
//    - Variant B: Mercury Aurora Pulse (Fluid mercury notch with vibrant aurora neon)
//    - Variant C: Frosted Glass Bevel (Matte industrial deep black with beveled lens)
//

import AppKit
import Combine
import Foundation
import QuartzCore
import SwiftUI

// MARK: - Notch Path Generator for Icons

func makeNotchIconPath(in rect: CGRect, topCorner: CGFloat, bottomCorner: CGFloat, notchWidth: CGFloat, notchHeight: CGFloat) -> Path {
    var path = Path()
    let minX = rect.midX - notchWidth / 2
    let maxX = rect.midX + notchWidth / 2
    let minY = rect.minY
    let maxY = rect.minY + notchHeight
    let tr = min(topCorner, notchHeight / 2, notchWidth / 4)
    let br = min(bottomCorner, notchHeight / 2, notchWidth / 4)

    path.move(to: CGPoint(x: minX, y: minY))
    path.addCurve(
        to: CGPoint(x: minX + tr, y: minY + tr),
        control1: CGPoint(x: minX + tr * 0.55, y: minY),
        control2: CGPoint(x: minX + tr, y: minY + tr * 0.45)
    )
    path.addLine(to: CGPoint(x: minX + tr, y: maxY - br))
    path.addArc(
        center: CGPoint(x: minX + tr + br, y: maxY - br),
        radius: br,
        startAngle: .degrees(180),
        endAngle: .degrees(90),
        clockwise: true
    )
    path.addLine(to: CGPoint(x: maxX - tr - br, y: maxY))
    path.addArc(
        center: CGPoint(x: maxX - tr - br, y: maxY - br),
        radius: br,
        startAngle: .degrees(90),
        endAngle: .degrees(0),
        clockwise: true
    )
    path.addLine(to: CGPoint(x: maxX - tr, y: minY + tr))
    path.addCurve(
        to: CGPoint(x: maxX, y: minY),
        control1: CGPoint(x: maxX - tr, y: minY + tr * 0.45),
        control2: CGPoint(x: maxX - tr * 0.55, y: minY)
    )
    path.closeSubpath()
    return path
}

// MARK: - Variant A: Liquid Prism Notch (Crystal Glass with Rainbow Dispersion)

struct VariantA_LiquidPrism: View {
    var size: CGFloat = 512

    var body: some View {
        let squircleRadius = size * 0.225
        let notchW = size * 0.62
        let notchH = size * 0.40
        let topR = size * 0.05
        let botR = size * 0.07

        ZStack {
            // 1. macOS Icon Base Plate (Dark Space Obsidian)
            RoundedRectangle(cornerRadius: squircleRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.16, green: 0.17, blue: 0.22), location: 0.0),
                            .init(color: Color(red: 0.08, green: 0.09, blue: 0.12), location: 0.6),
                            .init(color: Color(red: 0.04, green: 0.04, blue: 0.06), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Subtle outer squircle rim highlight
                    RoundedRectangle(cornerRadius: squircleRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.35), location: 0.0),
                                    .init(color: .white.opacity(0.08), location: 0.3),
                                    .init(color: .white.opacity(0.02), location: 0.8),
                                    .init(color: .white.opacity(0.15), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: size * 0.008
                        )
                )

            // 2. Ambient Desktop Backing Glow under the Notch
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.3, green: 0.5, blue: 0.9).opacity(0.35),
                            Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.20),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: size * 0.4
                    )
                )
                .offset(y: size * 0.08)

            // 3. The Liquid Glass Notch Body
            GeometryReader { geo in
                let notchPath = makeNotchIconPath(
                    in: CGRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height),
                    topCorner: topR,
                    bottomCorner: botR,
                    notchWidth: notchW,
                    notchHeight: notchH
                )

                ZStack {
                    // Refraction simulation (blurred colored background refraction)
                    notchPath
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.black, location: 0.0),
                                    .init(color: Color.black.opacity(0.95), location: 0.25),
                                    .init(color: Color(red: 0.2, green: 0.3, blue: 0.5).opacity(0.35), location: 0.60),
                                    .init(color: Color(red: 0.5, green: 0.4, blue: 0.7).opacity(0.18), location: 0.85),
                                    .init(color: Color.white.opacity(0.08), location: 1.00)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Rainbow Chromatic Dispersion Bevel
                    notchPath
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.4), location: 0.0),
                                    .init(color: Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.7), location: 0.70),
                                    .init(color: Color(red: 0.9, green: 0.4, blue: 0.9).opacity(0.85), location: 0.88),
                                    .init(color: Color(red: 1.0, green: 0.7, blue: 0.3).opacity(0.9), location: 1.00)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: size * 0.016
                        )

                    // Liquid Gloss Specular Arc
                    Path { p in
                        let y = notchH * 0.96
                        p.move(to: CGPoint(x: geo.size.width * 0.32, y: y))
                        p.addQuadCurve(
                            to: CGPoint(x: geo.size.width * 0.68, y: y),
                            control: CGPoint(x: geo.size.width * 0.50, y: y + size * 0.015)
                        )
                    }
                    .stroke(
                        Color.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: size * 0.012, lineCap: .round)
                    )

                    // Hardware camera dot (concealed in black core)
                    Circle()
                        .fill(Color(red: 0.05, green: 0.08, blue: 0.12))
                        .frame(width: size * 0.045, height: size * 0.045)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .overlay(
                            Circle().fill(Color(red: 0.2, green: 0.4, blue: 0.8).opacity(0.6)).frame(width: size * 0.015)
                        )
                        .position(x: geo.size.width * 0.5, y: size * 0.07)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: squircleRadius, style: .continuous))
    }
}

// MARK: - Variant B: Mercury Aurora Pulse (Fluid Metal & Vibrant Neon)

struct VariantB_MercuryPulse: View {
    var size: CGFloat = 512

    var body: some View {
        let squircleRadius = size * 0.225
        let notchW = size * 0.64
        let notchH = size * 0.44

        ZStack {
            // 1. Deep Midnight Base Plate
            RoundedRectangle(cornerRadius: squircleRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.07, blue: 0.12),
                            Color(red: 0.02, green: 0.03, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 2. Swirling Aurora Light Tube
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [.blue, .purple, .pink, .orange, .cyan, .blue],
                        center: .center
                    ),
                    lineWidth: size * 0.06
                )
                .blur(radius: size * 0.04)
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(y: size * 0.08)

            // 3. Fluid Droplet Silhouette
            GeometryReader { geo in
                let notchPath = makeNotchIconPath(
                    in: CGRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height),
                    topCorner: size * 0.06,
                    bottomCorner: size * 0.09,
                    notchWidth: notchW,
                    notchHeight: notchH
                )

                ZStack {
                    // Liquid glass body
                    notchPath
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black.opacity(0.85), location: 0.35),
                                    .init(color: Color(red: 0.1, green: 0.15, blue: 0.25).opacity(0.3), location: 0.7),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Neon Pulse Rim
                    notchPath
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.cyan.opacity(0.8),
                                    Color.pink.opacity(0.9),
                                    Color.orange.opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: size * 0.018
                        )
                        .blur(radius: 0.8)

                    // Water Droplet highlight
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size * 0.08, height: size * 0.04)
                        .rotationEffect(.degrees(-25))
                        .position(x: geo.size.width * 0.36, y: notchH * 0.88)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: squircleRadius, style: .continuous))
    }
}

// MARK: - Variant C: Frosted Glass Bevel (Precision Dark Industrial Lens)

struct VariantC_FrostedBevel: View {
    var size: CGFloat = 512

    var body: some View {
        let squircleRadius = size * 0.225
        let notchW = size * 0.60
        let notchH = size * 0.38

        ZStack {
            // 1. Matte Anodized Aluminum Plate
            RoundedRectangle(cornerRadius: squircleRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.18),
                            Color(white: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: squircleRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: size * 0.006)
                )

            // 2. Beveled Glass Lens
            GeometryReader { geo in
                let notchPath = makeNotchIconPath(
                    in: CGRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height),
                    topCorner: size * 0.04,
                    bottomCorner: size * 0.06,
                    notchWidth: notchW,
                    notchHeight: notchH
                )

                ZStack {
                    // Deep Black Inset
                    notchPath
                        .fill(Color(white: 0.02))
                        .shadow(color: .black.opacity(0.6), radius: size * 0.03, x: 0, y: size * 0.02)

                    // Frosted Glass Lens Gradient
                    notchPath
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black.opacity(0.8), location: 0.35),
                                    .init(color: Color(white: 0.2).opacity(0.3), location: 0.70),
                                    .init(color: Color.white.opacity(0.12), location: 1.00)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Razor Sharp Silver Bevel Stroke
                    notchPath
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.2), location: 0.0),
                                    .init(color: .white.opacity(0.05), location: 0.4),
                                    .init(color: .white.opacity(0.8), location: 0.85),
                                    .init(color: .white.opacity(0.95), location: 1.00)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: size * 0.012
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: squircleRadius, style: .continuous))
    }
}

// MARK: - Interactive Prototype Harness

enum IconVariant: Int, CaseIterable, Identifiable {
    case prism = 1
    case mercury = 2
    case frosted = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .prism: return "1 · Liquid Prism Notch (液态水晶棱镜 - 推荐)"
        case .mercury: return "2 · Mercury Aurora Pulse (流体水银与极光)"
        case .frosted: return "3 · Frosted Glass Bevel (极简金属与倒角)"
        }
    }

    var shortTitle: String {
        switch self {
        case .prism: return "Liquid Prism"
        case .mercury: return "Mercury Pulse"
        case .frosted: return "Frosted Bevel"
        }
    }
}

final class IconPrototypeState: ObservableObject {
    @Published var selectedVariant: IconVariant = .prism
    @Published var appliedMessage: String? = nil

    func applyCurrentIcon() {
        let size: CGFloat = 1024
        let view: AnyView
        switch selectedVariant {
        case .prism: view = AnyView(VariantA_LiquidPrism(size: size))
        case .mercury: view = AnyView(VariantB_MercuryPulse(size: size))
        case .frosted: view = AnyView(VariantC_FrostedBevel(size: size))
        }

        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: size, height: size)
        hosting.layoutSubtreeIfNeeded()

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            hosting.layer?.render(in: ctx)
        }
        image.unlockFocus()

        // Export PNG
        let targetDir = "/Users/allen/code/project/boring.notch/boringNotch/Assets.xcassets/AppIcon.appiconset"
        let logo2Dir = "/Users/allen/code/project/boring.notch/boringNotch/Assets.xcassets/logo2.imageset"

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            appliedMessage = "❌ Export failed: could not encode PNG"
            return
        }

        let masterPngPath = "/tmp/not_boring_notch_icon_1024.png"
        do {
            try png.write(to: URL(fileURLWithPath: masterPngPath))

            // Use sips to generate all Xcode resolutions
            let sizes = [
                ("notch-stage-icon2 2.png", 16),
                ("notch-stage-icon2 5.png", 32),
                ("notch-stage-icon2 6.png", 32),
                ("notch-stage-icon2 11.png", 64),
                ("notch-stage-icon2 12.png", 128),
                ("notch-stage-icon2 13.png", 256),
                ("notch-stage-icon2 7.png", 256),
                ("notch-stage-icon2 8.png", 512),
                ("notch-stage-icon2 9.png", 512),
                ("notch-stage-icon2 10.png", 1024)
            ]

            for (filename, px) in sizes {
                let dest = "\(targetDir)/\(filename)"
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                task.arguments = ["-z", "\(px)", "\(px)", masterPngPath, "--out", dest]
                try task.run()
                task.waitUntilExit()
            }

            // Also copy to logo2 (welcome screen)
            let logoDest = "\(logo2Dir)/BoringNotch icon.png"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            task.arguments = ["-z", "256", "256", masterPngPath, "--out", logoDest]
            try task.run()
            task.waitUntilExit()

            appliedMessage = "✅ Successfully applied \(selectedVariant.shortTitle) to AppIcon & WelcomeView!"
        } catch {
            appliedMessage = "❌ Error: \(error.localizedDescription)"
        }
    }
}

struct IconPrototypeView: View {
    @ObservedObject var state: IconPrototypeState

    var body: some View {
        VStack(spacing: 24) {
            // Top: Variant Picker
            HStack(spacing: 16) {
                Text("ICON VARIANTS:")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                ForEach(IconVariant.allCases) { v in
                    Button {
                        state.selectedVariant = v
                        state.appliedMessage = nil
                    } label: {
                        Text(v.shortTitle)
                            .font(.system(size: 13, weight: state.selectedVariant == v ? .bold : .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(state.selectedVariant == v ? Color.accentColor : Color.primary.opacity(0.08))
                            )
                            .foregroundStyle(state.selectedVariant == v ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal)

            Divider()

            // Middle: Side by side previews
            HStack(spacing: 40) {
                // Large Master Preview (340x340)
                VStack(spacing: 12) {
                    Text("Master Icon (340pt Preview)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ZStack {
                        // Desktop wallpaper background
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                        Group {
                            switch state.selectedVariant {
                            case .prism: VariantA_LiquidPrism(size: 300)
                            case .mercury: VariantB_MercuryPulse(size: 300)
                            case .frosted: VariantC_FrostedBevel(size: 300)
                            }
                        }
                        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                    }
                    .frame(width: 340, height: 340)
                }

                // Dock / Launchpad Scales
                VStack(alignment: .leading, spacing: 18) {
                    Text("Dock & Launchpad Density Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 24) {
                        VStack {
                            Group {
                                switch state.selectedVariant {
                                case .prism: VariantA_LiquidPrism(size: 128)
                                case .mercury: VariantB_MercuryPulse(size: 128)
                                case .frosted: VariantC_FrostedBevel(size: 128)
                                }
                            }
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                            Text("128px (Dock)").font(.caption).foregroundStyle(.tertiary)
                        }

                        VStack {
                            Group {
                                switch state.selectedVariant {
                                case .prism: VariantA_LiquidPrism(size: 64)
                                case .mercury: VariantB_MercuryPulse(size: 64)
                                case .frosted: VariantC_FrostedBevel(size: 64)
                                }
                            }
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            Text("64px (Launchpad)").font(.caption).foregroundStyle(.tertiary)
                        }

                        VStack {
                            Group {
                                switch state.selectedVariant {
                                case .prism: VariantA_LiquidPrism(size: 32)
                                case .mercury: VariantB_MercuryPulse(size: 32)
                                case .frosted: VariantC_FrostedBevel(size: 32)
                                }
                            }
                            Text("32px (Menu/List)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(16)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.selectedVariant.title)
                            .font(.system(size: 14, weight: .bold))

                        switch state.selectedVariant {
                        case .prism:
                            Text("Apple 液态玻璃风格。深色铝合金基盘嵌入通透水晶刘海，底边环绕亚像素彩虹色散倒角（Prismatic Dispersion），光影纯澈高阶。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        case .mercury:
                            Text("未来流体风格。水银流动水滴与极光流光霓虹管结合，象征未来即将加入的 AI Agent 智能脉冲心跳，充满科技活力。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        case .frosted:
                            Text("极简深空黑工业设计。磨砂物理透镜，搭配高精度微光银边与纯黑倒角，极度冷静、低调奢华。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 380)

                    // One-Click Apply Button
                    Button {
                        state.applyCurrentIcon()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                            Text("一键应用此图标到项目 (Apply to AppIcon)")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let msg = state.appliedMessage {
                        Text(msg)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(msg.contains("✅") ? .green : .red)
                    }
                }
            }

            Spacer(minLength: 0)

            // Bottom bar: Keys hint
            Text("Keys: 1, 2, 3 Switch Variant · Q Quit")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 820, height: 520)
    }
}

// MARK: - App Bootstrap

final class IconPrototypeController: NSObject, NSApplicationDelegate {
    private let state = IconPrototypeState()
    private var window: NSWindow!
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 820
        let height: CGFloat = 520

        window = NSWindow(
            contentRect: NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.midY - height / 2,
                width: width,
                height: height
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Not Boring Notch — App Icon Design Prototype"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: IconPrototypeView(state: state))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
            switch key {
            case "1": self.state.selectedVariant = .prism; self.state.appliedMessage = nil
            case "2": self.state.selectedVariant = .mercury; self.state.appliedMessage = nil
            case "3": self.state.selectedVariant = .frosted; self.state.appliedMessage = nil
            case "q", "\u{1b}": NSApp.terminate(nil)
            default: return event
            }
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = IconPrototypeController()
app.delegate = delegate
app.run()
