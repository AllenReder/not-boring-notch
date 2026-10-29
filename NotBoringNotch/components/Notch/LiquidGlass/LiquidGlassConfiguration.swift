//
//  LiquidGlassConfiguration.swift
//  NotBoringNotch
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

/// The single source of truth for the surface's parameter bounds and shipped
/// values. The renderer and the Appearance pane both read from here, so a slider
/// can never describe a value the surface cannot take.
enum LiquidGlassConfiguration {
    // MARK: Bounds

    static let refractionRange: ClosedRange<Double> = 0.0...100.0
    static let blurRange: ClosedRange<Double> = 0.0...30.0
    static let dispersionRange: ClosedRange<Double> = 0.0...15.0
    static let lensHeightRange: ClosedRange<Double> = 10.0...60.0

    /// The lowest fade start the slider offers. The camera housing pushes the
    /// effective lower bound higher on displays that have a closed notch.
    static let fadeStartLowerBound: Double = 20.0

    static let fadeEndOpacityRange: ClosedRange<Double> = 0.0...0.80
    static let rimIntensityRange: ClosedRange<Double> = 0.0...2.0

    /// Slider range for the fade start on a display whose closed notch is
    /// `closedNotchHeight` points tall and whose open panel is `openNotchHeight`
    /// points tall. The fade never starts above the closed notch, or the camera
    /// housing would let the desktop show through.
    static func fadeStartRange(
        closedNotchHeight: CGFloat,
        openNotchHeight: CGFloat
    ) -> ClosedRange<Double> {
        let upper = max(Double(openNotchHeight), fadeStartLowerBound)
        let lower = min(max(Double(closedNotchHeight), fadeStartLowerBound), upper)
        return lower...upper
    }

    // MARK: Shipped values

    /// The values a fresh install starts with and the Reset button restores.
    /// The persisted keys in `Constants` read their defaults from here.
    enum Recommended {
        static let refraction: Double = 24.0
        static let blur: Double = 0.5
        static let dispersion: Double = 4.0
        static let lensHeight: Double = 23.0
        static let fadeStart: Double = fadeStartLowerBound
        static let fadeEndOpacity: Double = 0.50
        static let rimTone: LiquidGlassRimTone = .neutralWhite
        static let rimIntensity: Double = 0.2
    }

    #if canImport(Defaults)
    static func resetToDefaults() {
        Defaults[.glassRefraction] = Recommended.refraction
        Defaults[.glassBlur] = Recommended.blur
        Defaults[.glassDispersion] = Recommended.dispersion
        Defaults[.glassLensHeight] = Recommended.lensHeight
        Defaults[.glassFadeStart] = Recommended.fadeStart
        Defaults[.glassFadeEndOpacity] = Recommended.fadeEndOpacity
        Defaults[.glassRimTone] = Recommended.rimTone
        Defaults[.glassRimIntensity] = Recommended.rimIntensity
    }
    #endif
}
