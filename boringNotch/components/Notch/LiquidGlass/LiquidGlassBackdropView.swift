//
//  LiquidGlassBackdropView.swift
//  boringNotch
//

import AppKit
import Foundation
import QuartzCore
import SwiftUI

private typealias SetDoubleFunc = @convention(c) (AnyObject, Selector, Double) -> Void
private typealias SetObjFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Void

final class LiquidGlassBackdropView: NSView {
    var refraction: Double = -20.0
    var lensHeight: Double = 23.0
    var blur: Double = 0.0
    var aberration: Double = 4.0
    var topRadius: CGFloat = 19.0
    var bottomRadius: CGFloat = 24.0

    private var backdrop: CALayer?
    private var sdfLayer: CALayer?
    private var sdfElement: CALayer?

    override var isFlipped: Bool {
        true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    private func setup() {
        guard let root = layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let sdfLayerClass = NSClassFromString("CASDFLayer") as? CALayer.Type,
              let sdfElementClass = NSClassFromString("CASDFElementLayer") as? CALayer.Type,
              let sdfEffectClass = NSClassFromString("CASDFOutputEffect") as? NSObject.Type else {
            return
        }

        let backdropInstance = backdropClass.init()
        backdropInstance.frame = bounds
        backdropInstance.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdropInstance.setValue(true, forKey: "tracksLuma")
        backdropInstance.setValue(true, forKey: "allowsFilteredLuma")
        backdropInstance.setValue(true, forKey: "windowServerAware")
        backdropInstance.allowsGroupOpacity = false

        // 1. CASDFOutputEffect converts distance field to normals
        let effect = sdfEffectClass.init()
        let selMin = NSSelectorFromString("setMinimum:")
        let selMax = NSSelectorFromString("setMaximum:")
        if let methodMin = class_getInstanceMethod(sdfEffectClass, selMin),
           let methodMax = class_getInstanceMethod(sdfEffectClass, selMax) {
            let impMin = unsafeBitCast(method_getImplementation(methodMin), to: SetDoubleFunc.self)
            let impMax = unsafeBitCast(method_getImplementation(methodMax), to: SetDoubleFunc.self)
            impMin(effect, selMin, -1000.0)
            impMax(effect, selMax, 1.0)
        }

        let sdfLayerInstance = sdfLayerClass.init()
        sdfLayerInstance.name = "@0"
        sdfLayerInstance.frame = bounds
        sdfLayerInstance.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        let selEffect = NSSelectorFromString("setEffect:")
        if let methodEffect = class_getInstanceMethod(sdfLayerClass, selEffect) {
            let imp = unsafeBitCast(method_getImplementation(methodEffect), to: SetObjFunc.self)
            imp(sdfLayerInstance, selEffect, effect)
        }

        // C1 Hermite Smoothness: eliminates hard step boundaries and color blocks
        let selSmooth = NSSelectorFromString("setSmoothness:")
        if let methodSmooth = class_getInstanceMethod(sdfLayerClass, selSmooth) {
            let imp = unsafeBitCast(method_getImplementation(methodSmooth), to: SetDoubleFunc.self)
            imp(sdfLayerInstance, selSmooth, 38.0)
        }

        // 2. SDF Shape Element: Inset by topRadius on both sides to align with NotchShape vertical walls.
        // In flipped coordinates, MaxY is the bottom of the view: round ONLY the bottom corners!
        let sdfElementInstance = sdfElementClass.init()
        let contentWidth = max(bounds.width - topRadius * 2, 0)
        sdfElementInstance.frame = CGRect(x: topRadius, y: 0, width: contentWidth, height: bounds.height)
        sdfElementInstance.cornerRadius = bottomRadius
        sdfElementInstance.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        sdfElementInstance.setValue("bounds", forKey: "mode")
        sdfElementInstance.setValue("union", forKey: "operation")

        sdfLayerInstance.sublayers = [sdfElementInstance]
        backdropInstance.sublayers = [sdfLayerInstance]
        root.addSublayer(backdropInstance)

        self.backdrop = backdropInstance
        self.sdfLayer = sdfLayerInstance
        self.sdfElement = sdfElementInstance

        rebuild()
    }

    func updateGeometry() {
        guard let backdrop = backdrop,
              let sdfLayer = sdfLayer,
              let sdfElement = sdfElement else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        sdfLayer.frame = bounds
        let contentWidth = max(bounds.width - topRadius * 2, 0)
        sdfElement.frame = CGRect(x: topRadius, y: 0, width: contentWidth, height: bounds.height)
        sdfElement.cornerRadius = bottomRadius
        sdfElement.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        CATransaction.commit()
    }

    func rebuild() {
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol,
              let backdrop = backdrop else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        guard let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground")?.takeUnretainedValue() as AnyObject? else {
            CATransaction.commit()
            return
        }

        filter.setValue("glassBackground", forKey: "name")
        filter.setValue("@0", forKey: "inputSourceSublayerName")

        // 1. Natural optical ray-bending refraction (continuous across left, right, and bottom)
        filter.setValue(refraction, forKey: "inputInnerRefractionAmount")
        filter.setValue(lensHeight, forKey: "inputInnerRefractionHeight")
        filter.setValue(-1.0, forKey: "inputRefractionDistance0")
        filter.setValue(0.0, forKey: "inputRefractionDistance1")
        filter.setValue(1.0, forKey: "inputRefractionOpacity")

        // 2. Controlled Blur
        filter.setValue(blur, forKey: "inputBlurRadius")
        filter.setValue(blur * 1.5, forKey: "inputBlurFillBlurRadius")
        filter.setValue(0.85, forKey: "inputBlurOpacity0")
        filter.setValue(0.85, forKey: "inputBlurOpacity1")
        filter.setValue(1.0, forKey: "inputBlurOpacity2")
        filter.setValue(1.0, forKey: "inputBlurOpacity3")
        filter.setValue(blur > 0 ? 0.60 : 0.0, forKey: "inputBlurFillNormalOpacity")

        // 3. Delicate sub-pixel chromatic dispersion along refractive perimeter
        if aberration > 0 {
            filter.setValue(aberration, forKey: "inputAberrationAmount")
            filter.setValue(lensHeight, forKey: "inputAberrationHeight")
            filter.setValue(0.0, forKey: "inputAberrationOffset")
            filter.setValue(0.0, forKey: "inputAberrationAngle")
        }

        // 4. Clarity: 100% face opacity, 0 bleed = crystal clear!
        filter.setValue(0.0, forKey: "inputBleedAmount")
        filter.setValue(1.0, forKey: "inputFaceOpacity")
        filter.setValue(75.0, forKey: "inputShadowAmount")
        filter.setValue(0.50, forKey: "inputKeyFillHighlightAmount")

        backdrop.filters = [filter]
        backdrop.setNeedsDisplay()

        CATransaction.commit()
    }
}

// MARK: - SwiftUI Representable

struct LiquidGlassBackdropRepresentable: NSViewRepresentable {
    var refraction: Double
    var lensHeight: Double
    var blur: Double
    var aberration: Double
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func makeNSView(context: Context) -> LiquidGlassBackdropView {
        let view = LiquidGlassBackdropView()
        view.refraction = -refraction
        view.lensHeight = lensHeight
        view.blur = blur
        view.aberration = aberration
        view.topRadius = topRadius
        view.bottomRadius = bottomRadius
        view.rebuild()
        return view
    }

    func updateNSView(_ nsView: LiquidGlassBackdropView, context: Context) {
        nsView.refraction = -refraction
        nsView.lensHeight = lensHeight
        nsView.blur = blur
        nsView.aberration = aberration
        nsView.topRadius = topRadius
        nsView.bottomRadius = bottomRadius
        nsView.updateGeometry()
        nsView.rebuild()
    }
}
