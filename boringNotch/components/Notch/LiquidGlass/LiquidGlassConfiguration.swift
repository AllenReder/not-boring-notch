//
//  LiquidGlassConfiguration.swift
//  boringNotch
//

import AppKit
import Foundation

#if canImport(Defaults)
import Defaults
#endif

// MARK: - Specular Rim Tone

enum LiquidGlassRimTone: String, CaseIterable, Identifiable, Codable {
    case neutralWhite = "Neutral White"
    case sunsetGold = "Sunset Gold"
    case siriGlow = "Siri Glow"
    case off = "Off"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .neutralWhite: return "Neutral White"
        case .sunsetGold: return "Sunset Gold"
        case .siriGlow: return "Siri Glow"
        case .off: return "Off"
        }
    }
}

#if canImport(Defaults)
extension LiquidGlassRimTone: Defaults.Serializable {}
#endif

// MARK: - Liquid Glass Configuration

struct LiquidGlassConfiguration: Equatable, Codable {
    // Bounds Limits (Source of Truth)
    static let refractionRange: ClosedRange<Double> = 0.0...100.0
    static let blurRange: ClosedRange<Double> = 0.0...30.0
    static let dispersionRange: ClosedRange<Double> = 0.0...15.0
    static let lensHeightRange: ClosedRange<Double> = 10.0...60.0
    static let coreHeightRange: ClosedRange<CGFloat> = 20.0...80.0
    static let fadeSoftnessRange: ClosedRange<CGFloat> = 10.0...100.0
    static let floorTransparencyRange: ClosedRange<CGFloat> = 0.0...0.50
    static let rimIntensityRange: ClosedRange<Double> = 0.0...2.0

    // Properties
    var refraction: Double
    var blur: Double
    var dispersion: Double
    var lensHeight: Double
    var coreHeight: CGFloat
    var fadeSoftness: CGFloat
    var floorTransparency: CGFloat
    var rimTone: LiquidGlassRimTone
    var rimIntensity: Double

    // Recommended Golden Configuration
    static let recommended = LiquidGlassConfiguration(
        refraction: 20.0,
        blur: 0.0,
        dispersion: 4.0,
        lensHeight: 23.0,
        coreHeight: 34.0,
        fadeSoftness: 45.0,
        floorTransparency: 0.0,
        rimTone: .neutralWhite,
        rimIntensity: 0.4
    )

    init(
        refraction: Double = 20.0,
        blur: Double = 0.0,
        dispersion: Double = 4.0,
        lensHeight: Double = 23.0,
        coreHeight: CGFloat = 34.0,
        fadeSoftness: CGFloat = 45.0,
        floorTransparency: CGFloat = 0.0,
        rimTone: LiquidGlassRimTone = .neutralWhite,
        rimIntensity: Double = 0.4
    ) {
        self.refraction = refraction
        self.blur = blur
        self.dispersion = dispersion
        self.lensHeight = lensHeight
        self.coreHeight = coreHeight
        self.fadeSoftness = fadeSoftness
        self.floorTransparency = floorTransparency
        self.rimTone = rimTone
        self.rimIntensity = rimIntensity
    }

    mutating func clampToBounds() {
        refraction = min(max(refraction, Self.refractionRange.lowerBound), Self.refractionRange.upperBound)
        blur = min(max(blur, Self.blurRange.lowerBound), Self.blurRange.upperBound)
        dispersion = min(max(dispersion, Self.dispersionRange.lowerBound), Self.dispersionRange.upperBound)
        lensHeight = min(max(lensHeight, Self.lensHeightRange.lowerBound), Self.lensHeightRange.upperBound)
        coreHeight = min(max(coreHeight, Self.coreHeightRange.lowerBound), Self.coreHeightRange.upperBound)
        fadeSoftness = min(max(fadeSoftness, Self.fadeSoftnessRange.lowerBound), Self.fadeSoftnessRange.upperBound)
        floorTransparency = min(max(floorTransparency, Self.floorTransparencyRange.lowerBound), Self.floorTransparencyRange.upperBound)
        rimIntensity = min(max(rimIntensity, Self.rimIntensityRange.lowerBound), Self.rimIntensityRange.upperBound)
    }

    func clamped() -> LiquidGlassConfiguration {
        var copy = self
        copy.clampToBounds()
        return copy
    }

    #if canImport(Defaults)
    static func resetToDefaults() {
        Defaults[.glassRefraction] = recommended.refraction
        Defaults[.glassBlur] = recommended.blur
        Defaults[.glassDispersion] = recommended.dispersion
        Defaults[.glassLensHeight] = recommended.lensHeight
        Defaults[.glassCoreHeight] = recommended.coreHeight
        Defaults[.glassFadeSoftness] = recommended.fadeSoftness
        Defaults[.glassFloorTransparency] = recommended.floorTransparency
        Defaults[.glassRimTone] = recommended.rimTone
        Defaults[.glassRimIntensity] = recommended.rimIntensity
    }
    #endif
}
