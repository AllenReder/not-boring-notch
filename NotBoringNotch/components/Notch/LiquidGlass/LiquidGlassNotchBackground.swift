//
//  LiquidGlassNotchBackground.swift
//  NotBoringNotch
//

import Defaults
import SwiftUI

// MARK: - Gradient Layers

/// A gradient clipped to the notch shape. Its stops depend on the surface height,
/// which the layer reads from a `GeometryReader`.
private struct NotchGradientLayer: View {
    let shape: NotchShape
    let stops: (CGFloat) -> [Gradient.Stop]

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: stops(geo.size.height),
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(shape)
        }
    }
}

// MARK: - Layer 4: Specular Glass Rim

struct NotchSpecularRim: View {
    let shape: NotchShape
    let tone: LiquidGlassRimTone
    let intensity: Double

    var body: some View {
        GeometryReader { geo in
            if geo.size.height > 60 && tone != .off && intensity > 0 {
                let mult = intensity
                switch tone {
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

// MARK: - Master Notch Background View

struct LiquidGlassNotchBackground: View {
    let shape: NotchShape
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// Height of the closed notch surface, which the scrim always keeps opaque.
    let closedNotchHeight: CGFloat
    let ambientColor: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Default(.enableLiquidGlass) var enableLiquidGlass
    @Default(.glassRefraction) var glassRefraction
    @Default(.glassBlur) var glassBlur
    @Default(.glassDispersion) var glassDispersion
    @Default(.glassLensHeight) var glassLensHeight
    @Default(.glassFadeStart) var glassFadeStart
    @Default(.glassFadeEndOpacity) var glassFadeEndOpacity
    @Default(.glassRimTone) var glassRimTone
    @Default(.glassRimIntensity) var glassRimIntensity

    /// The glass surface is only drawn when the user enabled it, accessibility
    /// allows transparency, and the host can render the private backdrop.
    private var usesGlassSurface: Bool {
        enableLiquidGlass && !reduceTransparency && LiquidGlassAvailability.isSupported
    }

    var body: some View {
        if usesGlassSurface {
            ZStack {
                // Layer 1: CoreAnimation Physical Refraction Backdrop
                LiquidGlassBackdropRepresentable(
                    refraction: glassRefraction,
                    lensHeight: glassLensHeight,
                    blur: glassBlur,
                    aberration: glassDispersion,
                    topRadius: topRadius,
                    bottomRadius: bottomRadius
                )
                .clipShape(shape)

                // Layer 2: Hardware Scrim (Guaranteed Solid Black Camera Concealment)
                NotchGradientLayer(shape: shape) { height in
                    NotchScrimCalculator.hardwareScrimStops(
                        totalHeight: height,
                        fadeStart: glassFadeStart,
                        solidBlackHeight: closedNotchHeight,
                        fadeEndOpacity: glassFadeEndOpacity
                    )
                }

                // Layer 3: Ambient Music Tint (Subtle Artwork Atmosphere in Mid-Band)
                if let ambient = ambientColor {
                    NotchGradientLayer(shape: shape) { height in
                        NotchScrimCalculator.ambientTintStops(
                            totalHeight: height,
                            fadeStart: glassFadeStart,
                            solidBlackHeight: closedNotchHeight,
                            ambientColor: ambient
                        )
                    }
                }

                // Layer 4: Specular Rim Highlight
                NotchSpecularRim(
                    shape: shape,
                    tone: glassRimTone,
                    intensity: glassRimIntensity
                )
            }
        } else {
            Color.black
        }
    }
}
