//
//  main.swift — PROTOTYPE (throwaway, delete me)
//  prototypes/liquid-glass-prototype/
//
//  Production-Ready Candidate for boring.notch:
//    - User Tuned Configuration:
//        Refraction: 20 (natural, subtle, no distortion)
//        Blur: 0.0 (100% crystal clear glass, zero haze)
//        Dispersion (色散): 4 (sub-pixel prismatic edge flare)
//        LensHeight: 23pt (smooth, continuous transition)
//        Rim Tone: Neutral White @ 0.4x (subtle, elegant glass bevel)
//        CoreHeight: 34pt (100% solid black over camera hardware)
//        FadeSoftness: 45pt (smooth dissolution into glass)
//        Floor: 0% (pure crystal transparency at bottom)
//

import AppKit
import Combine
import Foundation
import QuartzCore
import SwiftUI

// MARK: - Continuous Notch Shape

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 19, bottomCornerRadius: CGFloat = 24) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tr = min(topCornerRadius, rect.height / 2, rect.width / 4)
        let br = min(bottomCornerRadius, rect.height / 2, rect.width / 4)

        // Top-left shoulder starts at screen top
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Concave upper-left shoulder curve inward to notch body
        path.addCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            control1: CGPoint(x: rect.minX + (tr * 0.55), y: rect.minY),
            control2: CGPoint(x: rect.minX + tr, y: rect.minY + (tr * 0.45))
        )

        // Left sidewall
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))

        // Convex bottom-left corner
        path.addArc(
            center: CGPoint(x: rect.minX + tr + br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))

        // Convex bottom-right corner
        path.addArc(
            center: CGPoint(x: rect.maxX - tr - br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )

        // Right sidewall
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))

        // Concave upper-right shoulder curve outward to top bezel
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - tr, y: rect.minY + (tr * 0.45)),
            control2: CGPoint(x: rect.maxX - (tr * 0.55), y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - Model & State

enum GlassEngine: Int, CaseIterable, Identifiable {
    case opticalRefraction = 1
    case appleNative = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .opticalRefraction: return "1 · 物理折射引擎 (当前配置，全边生效)"
        case .appleNative: return "2 · Apple 官方原生 (.glassEffect)"
        }
    }

    var shortLabel: String {
        switch self {
        case .opticalRefraction: return "物理折射 (当前配置)"
        case .appleNative: return "Apple 原生"
        }
    }
}

enum RimTone: Int, CaseIterable, Identifiable {
    case neutralWhite, sunsetGold, siriGlow, off

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .neutralWhite: return "Neutral White (极简银白 - 当前设定)"
        case .sunsetGold: return "Sunset Gold (暖金夕阳)"
        case .siriGlow: return "Siri Glow (AI 霓虹)"
        case .off: return "Off (关闭高光)"
        }
    }

    var shortLabel: String {
        switch self {
        case .neutralWhite: return "Neutral White"
        case .sunsetGold: return "Sunset Gold"
        case .siriGlow: return "Siri Glow"
        case .off: return "Off"
        }
    }
}

enum BackdropKind: Int, CaseIterable, Identifiable {
    case desktop, sunset, checker, busy, white

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .desktop: return "Real Desktop (真实桌面)"
        case .sunset: return "Sunset (晚霞壁纸)"
        case .checker: return "Checkerboard (棋盘格)"
        case .busy: return "Busy Shapes (几何图形)"
        case .white: return "Pure White (纯白高光)"
        }
    }
}

final class AppState: ObservableObject {
    @Published var engine: GlassEngine = .opticalRefraction
    @Published var backdrop: BackdropKind = .desktop
    @Published var rimTone: RimTone = .neutralWhite

    // User's Validated Sweet-Spot Values:
    @Published var refractionMagnitude: Double = 20.0  // 折射强度: 20 (温润自然，无畸变)
    @Published var customBlurRadius: Double = 0.0     // 模糊度: 0.0 (100% 纯澈透光)
    @Published var chromaticAberration: Double = 4.0  // 边缘色散: 4 (精致边缘分光)
    @Published var lensHeight: Double = 23.0          // 透镜宽度: 23pt (平滑倒角)
    @Published var rimIntensity: Double = 0.4         // 边缘高光: 0.4x (轻柔点缀)

    // Black Fade Controls (Restored & Enhanced):
    @Published var fadeOn: Bool = true
    @Published var coreHeight: CGFloat = 34.0         // 纯黑区域高度 (10pt ~ 80pt, default 34pt for camera)
    @Published var fadeSoftness: CGFloat = 45.0       // 渐变过渡范围 (15pt ~ 90pt, default 45pt)
    @Published var floorTransparency: CGFloat = 0.00  // 底部透光底限 (0% = 100% 纯透晶体!)

    // Notch Geometry
    @Published var topRadius: CGFloat = 19.0
    @Published var bottomRadius: CGFloat = 24.0

    var refractionAmount: Double {
        -refractionMagnitude
    }

    var describe: String {
        "Refraction=\(Int(refractionMagnitude)) | Blur=\(String(format: "%.1f", customBlurRadius)) | Dispersion=\(Int(chromaticAberration)) | LensH=\(Int(lensHeight))pt | Core=\(Int(coreHeight))pt | Softness=\(Int(fadeSoftness))pt | Floor=\(Int(floorTransparency * 100))% | Rim=\(rimTone.shortLabel)(\(String(format: "%.1f", rimIntensity))x)"
    }

    func resetToSweetSpot() {
        engine = .opticalRefraction
        backdrop = .desktop
        rimTone = .neutralWhite
        refractionMagnitude = 20.0
        customBlurRadius = 0.0
        chromaticAberration = 4.0
        lensHeight = 23.0
        rimIntensity = 0.4
        coreHeight = 34.0
        fadeSoftness = 45.0
        floorTransparency = 0.00
        fadeOn = true
    }

    // Optical parameter adjusters
    func adjustRefraction(_ delta: Double) {
        refractionMagnitude = min(max(refractionMagnitude + delta, 5.0), 80.0)
    }

    func adjustBlur(_ delta: Double) {
        customBlurRadius = min(max(customBlurRadius + delta, 0.0), 20.0)
    }

    func adjustAberration(_ delta: Double) {
        chromaticAberration = min(max(chromaticAberration + delta, 0.0), 12.0)
    }

    func adjustLensHeight(_ delta: Double) {
        lensHeight = min(max(lensHeight + delta, 12.0), 45.0)
    }

    func adjustRimIntensity(_ delta: Double) {
        rimIntensity = min(max(rimIntensity + delta, 0.0), 1.5)
    }

    // Black Fade adjusters
    func adjustCoreHeight(_ delta: CGFloat) {
        coreHeight = min(max(coreHeight + delta, 10.0), 90.0)
    }

    func adjustFadeSoftness(_ delta: CGFloat) {
        fadeSoftness = min(max(fadeSoftness + delta, 15.0), 100.0)
    }

    func adjustFloor(_ delta: CGFloat) {
        floorTransparency = min(max(floorTransparency + delta, 0.0), 0.25)
    }

    func cycleRimTone() {
        let all = RimTone.allCases
        guard let idx = all.firstIndex(of: rimTone) else { return }
        rimTone = all[(idx + 1) % all.count]
    }
}

// MARK: - CoreAnimation Optical Refraction Engine

typealias SetDoubleFunc = @convention(c) (AnyObject, Selector, Double) -> Void
typealias SetObjFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Void

final class LiquidGlassBackdropView: NSView {
    var refraction: Double = -20.0
    var lensHeight: Double = 23.0
    var blur: Double = 0.0
    var aberration: Double = 4.0
    var topRadius: CGFloat = 19.0
    var bottomRadius: CGFloat = 24.0

    private var backdrop: CALayer!
    private var sdfLayer: CALayer!
    private var sdfElement: CALayer!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setup() {
        guard let root = layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let sdfLayerClass = NSClassFromString("CASDFLayer") as? CALayer.Type,
              let sdfElementClass = NSClassFromString("CASDFElementLayer") as? CALayer.Type,
              let sdfEffectClass = NSClassFromString("CASDFOutputEffect") as? NSObject.Type else {
            return
        }

        backdrop = backdropClass.init()
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdrop.setValue(true, forKey: "tracksLuma")
        backdrop.setValue(true, forKey: "allowsFilteredLuma")
        backdrop.setValue(true, forKey: "windowServerAware")
        backdrop.allowsGroupOpacity = false

        // Attach CASDFOutputEffect: converts SDF geometry into GPU distance field texture
        let effect = sdfEffectClass.init()
        let selMin = NSSelectorFromString("setMinimum:")
        let selMax = NSSelectorFromString("setMaximum:")
        if let mMin = class_getInstanceMethod(sdfEffectClass, selMin),
           let mMax = class_getInstanceMethod(sdfEffectClass, selMax) {
            let impMin = unsafeBitCast(method_getImplementation(mMin), to: SetDoubleFunc.self)
            let impMax = unsafeBitCast(method_getImplementation(mMax), to: SetDoubleFunc.self)
            impMin(effect, selMin, -1000.0)
            impMax(effect, selMax, 1.0)
        }

        sdfLayer = sdfLayerClass.init()
        sdfLayer.name = "@0"
        sdfLayer.frame = bounds
        sdfLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        let selEffect = NSSelectorFromString("setEffect:")
        if let m = class_getInstanceMethod(sdfLayerClass, selEffect) {
            let imp = unsafeBitCast(method_getImplementation(m), to: SetObjFunc.self)
            imp(sdfLayer, selEffect, effect)
        }

        // Smoothness = 38.0: high-order C1 continuity, eliminating hard boundaries and color blocks
        let selSmooth = NSSelectorFromString("setSmoothness:")
        if let m = class_getInstanceMethod(sdfLayerClass, selSmooth) {
            let imp = unsafeBitCast(method_getImplementation(m), to: SetDoubleFunc.self)
            imp(sdfLayer, selSmooth, 38.0)
        }

        // SDF Shape Element aligned with the vertical sidewalls of NotchShape
        sdfElement = sdfElementClass.init()
        sdfElement.frame = CGRect(x: topRadius, y: 0, width: bounds.width - topRadius * 2, height: bounds.height)
        sdfElement.cornerRadius = bottomRadius
        sdfElement.setValue("bounds", forKey: "mode")
        sdfElement.setValue("union", forKey: "operation")

        sdfLayer.sublayers = [sdfElement]
        backdrop.sublayers = [sdfLayer]
        root.addSublayer(backdrop)

        rebuild()
    }

    func updateGeometry() {
        guard let sdfElement = sdfElement else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sdfElement.frame = CGRect(x: topRadius, y: 0, width: bounds.width - topRadius * 2, height: bounds.height)
        sdfElement.cornerRadius = bottomRadius
        CATransaction.commit()
    }

    func rebuild() {
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol,
              let backdrop = backdrop else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        guard let f = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground")?.takeUnretainedValue() as AnyObject? else {
            CATransaction.commit()
            return
        }

        f.setValue("glassBackground", forKey: "name")
        f.setValue("@0", forKey: "inputSourceSublayerName")

        // 1. Natural optical ray bending (Continuous across left, right, and bottom)
        f.setValue(refraction, forKey: "inputInnerRefractionAmount")
        f.setValue(lensHeight, forKey: "inputInnerRefractionHeight")
        f.setValue(-1.0, forKey: "inputRefractionDistance0")
        f.setValue(0.0, forKey: "inputRefractionDistance1")
        f.setValue(1.0, forKey: "inputRefractionOpacity")

        // 2. Controlled Blur
        f.setValue(blur, forKey: "inputBlurRadius")
        f.setValue(blur * 1.5, forKey: "inputBlurFillBlurRadius")
        f.setValue(0.85, forKey: "inputBlurOpacity0")
        f.setValue(0.85, forKey: "inputBlurOpacity1")
        f.setValue(1.0, forKey: "inputBlurOpacity2")
        f.setValue(1.0, forKey: "inputBlurOpacity3")
        f.setValue(blur > 0 ? 0.60 : 0.0, forKey: "inputBlurFillNormalOpacity")

        // 3. Delicate Chromatic Dispersion along the edges
        if aberration > 0 {
            f.setValue(aberration, forKey: "inputAberrationAmount")
            f.setValue(lensHeight, forKey: "inputAberrationHeight")
            f.setValue(0.0, forKey: "inputAberrationOffset")
            f.setValue(0.0, forKey: "inputAberrationAngle")
        }

        // 4. Clarity: 100% face opacity, 0 bleed = pure crystal clarity!
        f.setValue(0.0, forKey: "inputBleedAmount")
        f.setValue(1.0, forKey: "inputFaceOpacity")
        f.setValue(75.0, forKey: "inputShadowAmount")
        f.setValue(0.50, forKey: "inputKeyFillHighlightAmount")

        backdrop.filters = [f]
        backdrop.setNeedsDisplay()

        CATransaction.commit()
    }
}

struct LiquidGlassBackdropRepresentable: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeNSView(context: Context) -> LiquidGlassBackdropView {
        let view = LiquidGlassBackdropView(frame: NSRect(x: 0, y: 0, width: 640, height: 195))
        view.refraction = state.refractionAmount
        view.lensHeight = state.lensHeight
        view.blur = state.customBlurRadius
        view.aberration = state.chromaticAberration
        view.topRadius = state.topRadius
        view.bottomRadius = state.bottomRadius
        view.rebuild()
        return view
    }

    func updateNSView(_ nsView: LiquidGlassBackdropView, context: Context) {
        nsView.refraction = state.refractionAmount
        nsView.lensHeight = state.lensHeight
        nsView.blur = state.customBlurRadius
        nsView.aberration = state.chromaticAberration
        nsView.topRadius = state.topRadius
        nsView.bottomRadius = state.bottomRadius
        nsView.updateGeometry()
        nsView.rebuild()
    }
}

// MARK: - Black Fade Scrim (Opaque Camera Notch -> Crystal Clear Bottom)

struct NotchBlackFadeScrim: View {
    @ObservedObject var state: AppState
    let shape: NotchShape
    let totalHeight: CGFloat = 195.0

    var body: some View {
        let coreLoc = min(max(state.coreHeight / totalHeight, 0.0), 0.50)
        let fadeEndLoc = min(coreLoc + (state.fadeSoftness / totalHeight), 0.85)

        LinearGradient(
            stops: [
                // 1. Opaque camera notch area (100% solid black)
                .init(color: .black, location: 0.0),
                .init(color: .black, location: coreLoc),

                // 2. Smooth quadratic ease-out decay into glass
                .init(color: .black.opacity(0.65), location: coreLoc + (fadeEndLoc - coreLoc) * 0.35),
                .init(color: .black.opacity(0.18), location: coreLoc + (fadeEndLoc - coreLoc) * 0.70),

                // 3. Bottom transparent floor (default 0.0 = 100% crystal clear!)
                .init(color: .black.opacity(Double(state.floorTransparency)), location: fadeEndLoc),
                .init(color: .black.opacity(Double(state.floorTransparency)), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .clipShape(shape)
    }
}

// MARK: - Specular Glass Rim

struct NotchSpecularRim: View {
    @ObservedObject var state: AppState
    let shape: NotchShape

    var body: some View {
        if state.rimTone != .off && state.rimIntensity > 0 {
            let mult = state.rimIntensity
            ZStack {
                switch state.rimTone {
                case .neutralWhite:
                    shape
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.20 * mult), location: 0.0),
                                    .init(color: .white.opacity(0.05 * mult), location: 0.4),
                                    .init(color: .white.opacity(0.65 * mult), location: 0.85),
                                    .init(color: .white.opacity(0.95 * mult), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )

                case .sunsetGold:
                    shape
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.18 * mult), location: 0.0),
                                    .init(color: .white.opacity(0.04 * mult), location: 0.4),
                                    .init(color: Color(red: 1.0, green: 0.75, blue: 0.40).opacity(0.65 * mult), location: 0.80),
                                    .init(color: Color(red: 1.0, green: 0.58, blue: 0.25).opacity(0.95 * mult), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )

                case .siriGlow:
                    shape
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.15 * mult), location: 0.0),
                                    .init(color: Color(red: 0.3, green: 0.7, blue: 1.0).opacity(0.50 * mult), location: 0.75),
                                    .init(color: Color(red: 0.9, green: 0.4, blue: 0.8).opacity(0.85 * mult), location: 0.92),
                                    .init(color: Color(red: 1.0, green: 0.6, blue: 0.3).opacity(0.95 * mult), location: 1.00),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.4
                        )

                case .off:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Reference Music Content Mock

struct VisualizerBars: View {
    private let heights: [CGFloat] = [5, 12, 17, 9, 14, 7, 10]
    private let colors: [Color] = [
        Color(red: 0.95, green: 0.45, blue: 0.35), Color(red: 0.95, green: 0.70, blue: 0.30),
        Color(red: 0.55, green: 0.85, blue: 0.45), Color(red: 0.35, green: 0.70, blue: 0.95),
        Color(red: 0.65, green: 0.45, blue: 0.95), Color(red: 0.95, green: 0.40, blue: 0.65),
        Color(red: 0.40, green: 0.85, blue: 0.85),
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 2.2) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(colors[i]).frame(width: 2.5, height: heights[i])
            }
        }
        .frame(height: 18)
    }
}

struct MockAlbumArt: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.52, blue: 0.68),
                            Color(red: 0.12, green: 0.18, blue: 0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                )
                .frame(width: 76, height: 76)

            Circle()
                .fill(Color(red: 0.98, green: 0.18, blue: 0.38))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
                .offset(x: 3, y: 3)
        }
    }
}

struct PlayingNextRow: View {
    let title: String
    let artist: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

struct MockNotchContent: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    MockAlbumArt()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Come to Life").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        Text("Refuzion & Serzo").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 0)
                        VisualizerBars()
                    }
                    .frame(height: 76, alignment: .top)
                }
                .frame(width: 300, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Playing Next")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    PlayingNextRow(title: "Blue Skies", artist: "Revelation", color: Color(red: 0.3, green: 0.5, blue: 0.8))
                    PlayingNextRow(title: "Stop Crying", artist: "The Straikerz & TOZA", color: Color(red: 0.85, green: 0.3, blue: 0.2))
                    PlayingNextRow(title: "Superstar", artist: "Kasablanca", color: Color(red: 0.2, green: 0.6, blue: 0.7))
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 8)

            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Text("2:16")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).padding(.trailing, 118)
                    }
                    .frame(height: 4)
                    Text("-0:46")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                            )
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)

                    Spacer()

                    Image(systemName: "backward.fill").font(.system(size: 16)).foregroundStyle(.white)
                    Image(systemName: "pause.fill").font(.system(size: 20)).foregroundStyle(.white)
                    Image(systemName: "forward.fill").font(.system(size: 16)).foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "laptopcomputer").font(.system(size: 15)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

// MARK: - Master Notch View (Production Integration Shape)

struct MasterNotchView: View {
    @ObservedObject var state: AppState

    private var currentShape: NotchShape {
        NotchShape(topCornerRadius: state.topRadius, bottomCornerRadius: state.bottomRadius)
    }

    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer {
                ZStack(alignment: .top) {
                    // Layer 1: The Selected Liquid Glass Engine
                    Group {
                        switch state.engine {
                        case .opticalRefraction:
                            // The Tuned Optical Refraction Engine (Refracts smoothly on left, right, and bottom!)
                            LiquidGlassBackdropRepresentable(state: state)
                                .clipShape(currentShape)

                        case .appleNative:
                            // Apple Official Native Liquid Glass (.glassEffect)
                            Color.clear
                                .frame(width: 640, height: 195)
                                .glassEffect(.clear, in: currentShape)
                        }
                    }

                    // Layer 2: Precision Black Fade Scrim (Hardware cam pure black -> 0% floor at bottom)
                    if state.fadeOn {
                        NotchBlackFadeScrim(state: state, shape: currentShape)
                    }

                    // Layer 3: Specular Edge Rim (Neutral White @ 0.4x)
                    NotchSpecularRim(state: state, shape: currentShape)

                    // Layer 4: Foreground Interactive Music Content
                    MockNotchContent()
                        .frame(width: 640, height: 195)
                }
                .frame(width: 640, height: 195)
                .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 8)
            }

            // Transparent bottom safety padding (never cut off by window edge)
            Spacer(minLength: 0)
        }
        .frame(width: 680, height: 235, alignment: .top)
    }
}

// MARK: - Backdrops

struct SunsetBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.12, green: 0.18, blue: 0.28), location: 0.0),
                    .init(color: Color(red: 0.35, green: 0.30, blue: 0.35), location: 0.35),
                    .init(color: Color(red: 0.85, green: 0.48, blue: 0.28), location: 0.65),
                    .init(color: Color(red: 0.98, green: 0.72, blue: 0.42), location: 0.88),
                    .init(color: Color(red: 0.95, green: 0.62, blue: 0.32), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer()
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 150))
                    p.addCurve(to: CGPoint(x: 400, y: 100), control1: CGPoint(x: 150, y: 80), control2: CGPoint(x: 250, y: 140))
                    p.addCurve(to: CGPoint(x: 900, y: 120), control1: CGPoint(x: 550, y: 60), control2: CGPoint(x: 750, y: 160))
                    p.addCurve(to: CGPoint(x: 1600, y: 90), control1: CGPoint(x: 1100, y: 80), control2: CGPoint(x: 1350, y: 110))
                    p.addLine(to: CGPoint(x: 1600, y: 300))
                    p.addLine(to: CGPoint(x: 0, y: 300))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.18, green: 0.14, blue: 0.18).opacity(0.85))
                .frame(height: 250)
            }
        }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 50
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let dark = (row + col) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: side, height: side)),
                        with: .color(dark ? Color(white: 0.08) : Color(white: 0.95))
                    )
                    x += side
                    col += 1
                }
                y += side
                row += 1
            }
        }
    }
}

struct BackdropHost: View {
    let kind: BackdropKind

    var body: some View {
        switch kind {
        case .desktop:
            Color.clear
        case .sunset:
            SunsetBackdrop()
        case .checker:
            Checkerboard()
        case .busy:
            ZStack {
                LinearGradient(
                    colors: [Color.blue, Color.purple, Color.orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle().fill(Color.white.opacity(0.6)).frame(width: 400).offset(x: -200, y: -60)
                Circle().fill(Color.black.opacity(0.4)).frame(width: 320).offset(x: 200, y: 40)
            }
        case .white:
            Color.white
        }
    }
}

// MARK: - Control Switcher Panel (Spacious 3-Row Parameter Console)

struct ParameterCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(subtitle).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
            content
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ControlSwitcherPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1: Global Engine Switcher + Environment Pickers
            HStack(spacing: 12) {
                Text("ENGINE:")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                ForEach(GlassEngine.allCases) { eng in
                    Button {
                        state.engine = eng
                    } label: {
                        Text(eng.shortLabel)
                            .font(.system(size: 12, weight: state.engine == eng ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(state.engine == eng ? Color.accentColor : Color.primary.opacity(0.08))
                            )
                            .foregroundStyle(state.engine == eng ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Backdrop Segmented (Spacious 480pt, zero overlap!)
                Picker("场景选择", selection: $state.backdrop) {
                    ForEach(BackdropKind.allCases) { b in Text(b.label).tag(b) }
                }
                .pickerStyle(.segmented)
                .frame(width: 480)

                Button("Quit") { NSApp.terminate(nil) }
            }

            Divider()

            // Row 2: Black Fade Mask Controls (Restored & Enhanced!)
            HStack(spacing: 12) {
                // Black Fade Toggle
                Toggle("启用黑色渐变 (Black Fade)", isOn: $state.fadeOn)
                    .font(.system(size: 12, weight: .semibold))
                    .toggleStyle(.switch)

                Divider().frame(height: 18)

                // Card: Core Height
                ParameterCard(title: "纯黑高度 CoreHeight", subtitle: "硬件默认: 34pt") {
                    HStack {
                        Button("−") { state.adjustCoreHeight(-4) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text("\(Int(state.coreHeight))pt")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustCoreHeight(4) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }

                // Card: Fade Softness
                ParameterCard(title: "羽化软度 FadeSoftness", subtitle: "推荐: 45pt") {
                    HStack {
                        Button("−") { state.adjustFadeSoftness(-5) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text("\(Int(state.fadeSoftness))pt")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustFadeSoftness(5) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }

                // Card: Floor Transparency
                ParameterCard(title: "底部底限 Floor", subtitle: "推荐: 0% 纯透") {
                    HStack {
                        Button("−") { state.adjustFloor(-0.02) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text("\(Int(state.floorTransparency * 100))%")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustFloor(0.02) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }
            }

            // Row 3: Precision Optical Parameters Deck (User's Validated Sweet Spot)
            HStack(spacing: 10) {
                // Card 1: Refraction (折射强度)
                ParameterCard(title: "物理折射 Refraction", subtitle: "设定: 20") {
                    HStack {
                        Button("−") { state.adjustRefraction(-5) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text("\(Int(state.refractionMagnitude))")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustRefraction(5) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }

                // Card 2: Blur (模糊度)
                ParameterCard(title: "模糊度 Blur", subtitle: "设定: 0.0") {
                    HStack {
                        Button("−") { state.adjustBlur(-1) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text("\(String(format: "%.1f", state.customBlurRadius))")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustBlur(1) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }

                // Card 3: Chromatic Dispersion (色散)
                ParameterCard(title: "边缘色散 Dispersion", subtitle: "设定: 4") {
                    HStack {
                        Button("−") { state.adjustAberration(-1) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text("\(Int(state.chromaticAberration))")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustAberration(1) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }

                // Card 4: Lens Height (透镜宽度)
                ParameterCard(title: "透镜宽度 LensHeight", subtitle: "设定: 23pt") {
                    HStack {
                        Button("−") { state.adjustLensHeight(-2) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text("\(Int(state.lensHeight))pt")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustLensHeight(2) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }

                // Card 5: Specular Rim (边缘高光 & 色调)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("边缘高光 Rim").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $state.rimTone) {
                            ForEach(RimTone.allCases) { t in Text(t.shortLabel).tag(t) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                    HStack {
                        Button("−") { state.adjustRimIntensity(-0.1) }.buttonStyle(.bordered).frame(width: 30)
                        Spacer()
                        Text(state.rimTone == .off ? "OFF" : "\(String(format: "%.1f", state.rimIntensity))x")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("+") { state.adjustRimIntensity(0.1) }.buttonStyle(.bordered).frame(width: 30)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                // Reset Button
                Button {
                    state.resetToSweetSpot()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("重置配置").font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.bordered)
            }

            // Row 4: Realtime Status & Keys Help
            VStack(alignment: .leading, spacing: 4) {
                Text(state.describe)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary)

                Text("Keys · 1/2 Engine · S Sunset · D Desktop · C Checker · B Busy · W White · [ / ] Blur · - / = Refraction · , / . Dispersion · 9 / 0 CoreHeight · R Rim · Q Quit")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - App Bootstrap

final class PrototypeController: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var notchPanel: NSPanel!
    private var backdropWindow: NSWindow!
    private var controlWindow: NSWindow!
    private var keyMonitor: Any?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let notchWidth: CGFloat = 680
        let notchHeight: CGFloat = 195
        let bottomSafetyMargin: CGFloat = 40

        // 1. Fullscreen Backdrop Window
        backdropWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backdropWindow.isOpaque = false
        backdropWindow.backgroundColor = .clear
        backdropWindow.hasShadow = false
        backdropWindow.ignoresMouseEvents = true
        backdropWindow.level = .floating
        backdropWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        backdropWindow.contentView = NSHostingView(rootView: BackdropHost(kind: state.backdrop).ignoresSafeArea())
        backdropWindow.orderFrontRegardless()

        // 2. Boring Notch Top Floating Panel
        let totalPanelHeight = notchHeight + bottomSafetyMargin
        notchPanel = NSPanel(
            contentRect: NSRect(
                x: frame.midX - notchWidth / 2,
                y: frame.maxY - totalPanelHeight,
                width: notchWidth,
                height: totalPanelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        notchPanel.isOpaque = false
        notchPanel.backgroundColor = .clear
        notchPanel.hasShadow = false
        notchPanel.isMovable = false
        notchPanel.level = .mainMenu + 3
        notchPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: MasterNotchView(state: state))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        notchPanel.contentView = hosting
        notchPanel.orderFrontRegardless()

        // 3. Floating Bottom Control Switcher Window (Spacious 1260x340)
        let ctrlWidth: CGFloat = 1260
        let ctrlHeight: CGFloat = 340
        controlWindow = NSWindow(
            contentRect: NSRect(
                x: frame.midX - ctrlWidth / 2,
                y: frame.minY + 25,
                width: ctrlWidth,
                height: ctrlHeight
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        controlWindow.title = "Boring Notch Liquid Glass — Candidate for boring.notch Integration"
        controlWindow.isReleasedWhenClosed = false
        controlWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        controlWindow.contentView = NSHostingView(rootView: ControlSwitcherPanel(state: state))
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Reactive subscriptions
        state.$backdrop
            .sink { [weak self] kind in
                guard let self = self else { return }
                self.backdropWindow.contentView = NSHostingView(rootView: BackdropHost(kind: kind).ignoresSafeArea())
            }
            .store(in: &bag)

        state.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    print(self.state.describe)
                }
            }
            .store(in: &bag)

        // Keyboard navigation
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
            switch key {
            case "1": self.state.engine = .opticalRefraction
            case "2": self.state.engine = .appleNative
            case "s": self.state.backdrop = .sunset
            case "d": self.state.backdrop = .desktop
            case "c": self.state.backdrop = .checker
            case "b": self.state.backdrop = .busy
            case "w": self.state.backdrop = .white
            case "r": self.state.cycleRimTone()
            case "9": self.state.adjustCoreHeight(-4.0)
            case "0": self.state.adjustCoreHeight(4.0)
            case "[": self.state.adjustBlur(-1.0)
            case "]": self.state.adjustBlur(1.0)
            case "-": self.state.adjustRefraction(-5.0)
            case "=": self.state.adjustRefraction(5.0)
            case ",": self.state.adjustAberration(-1.0)
            case ".": self.state.adjustAberration(1.0)
            case "q", "\u{1b}": NSApp.terminate(nil)
            default: return event
            }
            return nil
        }

        print("""
        ================================================================================
        Boring Notch Liquid Glass — Candidate for boring.notch Integration
        Active Configuration: Refraction 20, Blur 0.0, Dispersion 4, LensHeight 23pt, Rim 0.4x
        Controls: S/D/C/B/W backdrop, 9/0 coreHeight, [ / ] blur, - / = refraction, Q quit.
        ================================================================================
        """)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = PrototypeController()
application.delegate = controller
application.run()
