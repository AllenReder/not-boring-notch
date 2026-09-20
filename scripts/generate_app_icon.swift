#!/usr/bin/env swift
//
//  generate_app_icon.swift
//  Not Boring Notch — Icon Generator
//
//  Renders the official Not Boring Notch app icon using the real macOS CoreAnimation
//  Liquid Glass GPU optical refraction pipeline (CABackdropLayer + CASDFLayer + glassBackground filter),
//  then exports all required resolutions into AppIcon.appiconset and logo assets.
//

import AppKit
import Foundation
import QuartzCore
import SwiftUI

private typealias SetDoubleFunc = @convention(c) (AnyObject, Selector, Double) -> Void
private typealias SetObjFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Void

// MARK: - Authentic MacBook Screen Bezel & Notch Path

func makeMasterNotchPath(size: CGFloat, notchW: CGFloat, notchH: CGFloat, topR: CGFloat, botR: CGFloat) -> Path {
    var p = Path()
    let midX = size / 2
    let notchLeft = midX - notchW / 2
    let notchRight = midX + notchW / 2
    let shoulderLeft = notchLeft - topR
    let shoulderRight = notchRight + topR
    let topY: CGFloat = 0

    p.move(to: CGPoint(x: 0, y: topY))
    p.addLine(to: CGPoint(x: shoulderLeft, y: topY))

    // Smooth G2 Concave shoulder down into notch
    p.addCurve(
        to: CGPoint(x: notchLeft, y: topY + topR),
        control1: CGPoint(x: notchLeft - topR * 0.45, y: topY),
        control2: CGPoint(x: notchLeft, y: topY + topR * 0.45)
    )

    // Left vertical sidewall
    p.addLine(to: CGPoint(x: notchLeft, y: topY + notchH - botR))

    // Silky Smooth G2 Convex Bottom-Left Corner
    let k = botR * 0.5522847
    p.addCurve(
        to: CGPoint(x: notchLeft + botR, y: topY + notchH),
        control1: CGPoint(x: notchLeft, y: topY + notchH - botR + k),
        control2: CGPoint(x: notchLeft + botR - k, y: topY + notchH)
    )

    // Bottom horizontal edge
    p.addLine(to: CGPoint(x: notchRight - botR, y: topY + notchH))

    // Silky Smooth G2 Convex Bottom-Right Corner
    p.addCurve(
        to: CGPoint(x: notchRight, y: topY + notchH - botR),
        control1: CGPoint(x: notchRight - botR + k, y: topY + notchH),
        control2: CGPoint(x: notchRight, y: topY + notchH - botR + k)
    )

    // Right vertical sidewall
    p.addLine(to: CGPoint(x: notchRight, y: topY + topR))

    // Smooth G2 Concave shoulder up to top bezel
    p.addCurve(
        to: CGPoint(x: shoulderRight, y: topY),
        control1: CGPoint(x: notchRight, y: topY + topR * 0.45),
        control2: CGPoint(x: notchRight + topR * 0.45, y: topY)
    )

    // Line along top bezel to right
    p.addLine(to: CGPoint(x: size, y: topY))
    p.closeSubpath()
    return p
}

// Continuous Rim Path running from mid-wall around the bottom and up the other wall
func makeContinuousRimPath(size: CGFloat, notchW: CGFloat, notchH: CGFloat, botR: CGFloat) -> Path {
    var p = Path()
    let midX = size / 2
    let notchLeft = midX - notchW / 2
    let notchRight = midX + notchW / 2
    let topY: CGFloat = 0
    let k = botR * 0.5522847

    // Start midway up the left wall
    p.move(to: CGPoint(x: notchLeft, y: topY + notchH * 0.45))
    p.addLine(to: CGPoint(x: notchLeft, y: topY + notchH - botR))

    // Bottom-left curve
    p.addCurve(
        to: CGPoint(x: notchLeft + botR, y: topY + notchH),
        control1: CGPoint(x: notchLeft, y: topY + notchH - botR + k),
        control2: CGPoint(x: notchLeft + botR - k, y: topY + notchH)
    )

    // Bottom edge
    p.addLine(to: CGPoint(x: notchRight - botR, y: topY + notchH))

    // Bottom-right curve
    p.addCurve(
        to: CGPoint(x: notchRight, y: topY + notchH - botR),
        control1: CGPoint(x: notchRight - botR + k, y: topY + notchH),
        control2: CGPoint(x: notchRight, y: topY + notchH - botR + k)
    )

    // End midway up the right wall
    p.addLine(to: CGPoint(x: notchRight, y: topY + notchH * 0.45))

    return p
}

// MARK: - CoreAnimation Real Optical Glass View

final class AwardWinningGlassView: NSView {
    var refraction: Double = -90.0      // Deep lens displacement
    var lensHeight: Double = 50.0      // Wide silky bevel
    var aberration: Double = 12.0      // Prismatic dispersion
    var notchWidth: CGFloat = 360.0
    var notchHeight: CGFloat = 280.0
    var bottomRadius: CGFloat = 58.0

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

        let selSmooth = NSSelectorFromString("setSmoothness:")
        if let m = class_getInstanceMethod(sdfLayerClass, selSmooth) {
            let imp = unsafeBitCast(method_getImplementation(m), to: SetDoubleFunc.self)
            imp(sdfLayer, selSmooth, 52.0)
        }

        let midX = bounds.width / 2
        let notchLeft = midX - notchWidth / 2
        let yFromBottom = bounds.height - notchHeight
        sdfElement = sdfElementClass.init()
        sdfElement.frame = CGRect(x: notchLeft, y: yFromBottom, width: notchWidth, height: notchHeight)
        sdfElement.cornerRadius = bottomRadius
        sdfElement.setValue("bounds", forKey: "mode")
        sdfElement.setValue("union", forKey: "operation")

        sdfLayer.sublayers = [sdfElement]
        backdrop.sublayers = [sdfLayer]
        root.addSublayer(backdrop)

        rebuild()
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
        f.setValue(refraction, forKey: "inputInnerRefractionAmount")
        f.setValue(lensHeight, forKey: "inputInnerRefractionHeight")
        f.setValue(-1.0, forKey: "inputRefractionDistance0")
        f.setValue(0.0, forKey: "inputRefractionDistance1")
        f.setValue(1.0, forKey: "inputRefractionOpacity")

        f.setValue(0.0, forKey: "inputBlurRadius")
        f.setValue(0.0, forKey: "inputBlurFillBlurRadius")

        // Chromatic Dispersion
        f.setValue(aberration, forKey: "inputAberrationAmount")
        f.setValue(lensHeight, forKey: "inputAberrationHeight")
        f.setValue(0.0, forKey: "inputAberrationOffset")
        f.setValue(0.0, forKey: "inputAberrationAngle")

        f.setValue(0.0, forKey: "inputBleedAmount")
        f.setValue(1.0, forKey: "inputFaceOpacity")
        f.setValue(65.0, forKey: "inputShadowAmount")
        f.setValue(0.70, forKey: "inputKeyFillHighlightAmount")

        backdrop.filters = [f]
        backdrop.setNeedsDisplay()

        CATransaction.commit()
    }
}

struct AwardWinningGlassRepresentable: NSViewRepresentable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var bottomRadius: CGFloat

    func makeNSView(context: Context) -> AwardWinningGlassView {
        let v = AwardWinningGlassView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        v.notchWidth = notchWidth
        v.notchHeight = notchHeight
        v.bottomRadius = bottomRadius
        v.setup()
        return v
    }

    func updateNSView(_ nsView: AwardWinningGlassView, context: Context) {}
}

// MARK: - Master Icon View (Official Liquid Glass Design)

struct NotBoringNotchOfficialIconView: View {
    let size: CGFloat = 512

    var body: some View {
        let squircleR = size * 0.225
        let notchW = size * 0.68
        let notchH = size * 0.52
        let topR: CGFloat = size * 0.065
        let botR: CGFloat = size * 0.115

        let notchPath = makeMasterNotchPath(
            size: size,
            notchW: notchW,
            notchH: notchH,
            topR: topR,
            botR: botR
        )

        let continuousRim = makeContinuousRimPath(
            size: size,
            notchW: notchW,
            notchH: notchH,
            botR: botR
        )

        ZStack(alignment: .top) {
            // 1. Base Plate: Dark Space Obsidian
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.06)

                // Rainbow Donut Ring (Rich glowing colors)
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.22, blue: 0.45), // Hot Pink
                                Color(red: 1.0, green: 0.55, blue: 0.12), // Orange
                                Color(red: 1.0, green: 0.88, blue: 0.10), // Sunburst
                                Color(red: 0.15, green: 0.90, blue: 0.50), // Mint Green
                                Color(red: 0.10, green: 0.75, blue: 1.00), // Cyan Blue
                                Color(red: 0.65, green: 0.30, blue: 0.95), // Neon Purple
                                Color(red: 1.0, green: 0.22, blue: 0.45)  // Back to Pink
                            ],
                            center: .center
                        ),
                        lineWidth: size * 0.095
                    )
                    .frame(width: size * 0.56, height: size * 0.56)
                    .offset(y: size * 0.16)
                    .shadow(color: Color.purple.opacity(0.60), radius: 28, y: 8)
                    .shadow(color: Color.blue.opacity(0.50), radius: 38, y: 6)

                // Soft glowing radial disc inside the donut hole
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.35, green: 0.55, blue: 0.95).opacity(0.55),
                                Color(red: 0.20, green: 0.15, blue: 0.45).opacity(0.30),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: size * 0.22
                        )
                    )
                    .frame(width: size * 0.46, height: size * 0.46)
                    .offset(y: size * 0.16)

                // Dark Vignette
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.75)],
                    center: .center,
                    startRadius: size * 0.26,
                    endRadius: size * 0.55
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: squircleR, style: .continuous))

            // 2. THE REAL OPTICAL LIQUID GLASS NOTCH
            ZStack(alignment: .top) {
                // Real GPU Physical Refraction Layer
                AwardWinningGlassRepresentable(
                    notchWidth: notchW,
                    notchHeight: notchH,
                    bottomRadius: botR
                )
                .frame(width: size, height: size)
                .clipShape(notchPath)

                // Precision Hardware Camera Scrim (Top pure black core fading seamlessly into glass)
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.26),
                        .init(color: .black.opacity(0.70), location: 0.42),
                        .init(color: .black.opacity(0.20), location: 0.65),
                        .init(color: .clear, location: 0.88),
                        .init(color: .clear, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: size, height: notchH)
                .position(x: size / 2, y: notchH / 2)
                .clipShape(notchPath)

                // Bottom Continuous Rim: Dissolves softly at both ends
                continuousRim
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: Color.clear, location: 0.15),
                                .init(color: Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.75), location: 0.30),
                                .init(color: Color.white.opacity(0.95), location: 0.50),
                                .init(color: Color(red: 1.0, green: 0.7, blue: 0.3).opacity(0.85), location: 0.70),
                                .init(color: Color.clear, location: 0.85),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: size * 0.012, lineCap: .round, lineJoin: .round)
                    )

                // Brilliant Specular Accent on Bottom Center Edge
                continuousRim
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.0), location: 0.0),
                                .init(color: .white.opacity(0.0), location: 0.35),
                                .init(color: .white.opacity(0.95), location: 0.50),
                                .init(color: .white.opacity(0.0), location: 0.65),
                                .init(color: .white.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: size * 0.008, lineCap: .round)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: squircleR, style: .continuous))

            // 3. Squircle Outer Metallic Bevel Stroke
            RoundedRectangle(cornerRadius: squircleR, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.45), location: 0.0),
                            .init(color: .white.opacity(0.12), location: 0.35),
                            .init(color: .white.opacity(0.02), location: 0.70),
                            .init(color: .white.opacity(0.25), location: 1.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: size * 0.008
                )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Generator Runner

let masterTempPath = "/tmp/not_boring_notch_master_1024.png"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 512, height: 512),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.contentView = NSHostingView(rootView: NotBoringNotchOfficialIconView())
window.orderFrontRegardless()

DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-l", "\(window.windowNumber)", masterTempPath]
    try? task.run()
    task.waitUntilExit()

    guard FileManager.default.fileExists(atPath: masterTempPath) else {
        print("❌ Error: Failed to capture master icon")
        exit(1)
    }

    print("✅ Master 1024x1024 icon rendered successfully at \(masterTempPath)")

    let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
    let appIconDir = "\(projectDir)/boringNotch/Assets.xcassets/AppIcon.appiconset"
    let logo2Dir = "\(projectDir)/boringNotch/Assets.xcassets/logo2.imageset"
    let logoDir = "\(projectDir)/boringNotch/Assets.xcassets/logo.imageset"

    // Target sizes for AppIcon.appiconset
    let appIconSizes = [
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

    for (name, px) in appIconSizes {
        let dest = "\(appIconDir)/\(name)"
        let resize = Process()
        resize.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        resize.arguments = ["-z", "\(px)", "\(px)", masterTempPath, "--out", dest]
        try? resize.run()
        resize.waitUntilExit()
        print("  → Generated \(name) (\(px)x\(px))")
    }

    // Logo2 (Welcome screen)
    let logo2Dest = "\(logo2Dir)/BoringNotch icon.png"
    let resizeLogo2 = Process()
    resizeLogo2.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    resizeLogo2.arguments = ["-z", "512", "512", masterTempPath, "--out", logo2Dest]
    try? resizeLogo2.run()
    resizeLogo2.waitUntilExit()
    print("  → Generated logo2/BoringNotch icon.png (512x512)")

    // Logo (General 256-mac)
    let logoDest = "\(logoDir)/256-mac 1.png"
    let resizeLogo = Process()
    resizeLogo.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    resizeLogo.arguments = ["-z", "256", "256", masterTempPath, "--out", logoDest]
    try? resizeLogo.run()
    resizeLogo.waitUntilExit()
    print("  → Generated logo/256-mac 1.png (256x256)")

    print("🎉 All product icons updated successfully!")
    NSApp.terminate(nil)
}

app.run()
