//
//  LiquidGlassNotchBackground.swift
//  NotBoringNotch
//

import Defaults
import SwiftUI

// MARK: - Layer 2: Hardware Scrim (Pure Camera Concealment)

struct NotchBlackFadeScrim: View {
    let shape: NotchShape
    let coreHeight: CGFloat
    let fadeSoftness: CGFloat
    let floorTransparency: CGFloat

    var body: some View {
        GeometryReader { geo in
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: geo.size.height,
                coreHeight: coreHeight,
                fadeSoftness: fadeSoftness,
                floorTransparency: floorTransparency
            )

            LinearGradient(
                stops: stops,
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(shape)
        }
    }
}

// MARK: - Layer 3: Ambient Music Tint (Separate Middle-Band Atmosphere)

struct NotchAmbientMusicTint: View {
    let shape: NotchShape
    let coreHeight: CGFloat
    let fadeSoftness: CGFloat
    let ambientColor: Color

    var body: some View {
        GeometryReader { geo in
            let stops = NotchScrimCalculator.ambientTintStops(
                totalHeight: geo.size.height,
                coreHeight: coreHeight,
                fadeSoftness: fadeSoftness,
                ambientColor: ambientColor
            )

            LinearGradient(
                stops: stops,
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
    let ambientColor: Color?

    @Default(.enableLiquidGlass) var enableLiquidGlass
    @Default(.glassRefraction) var glassRefraction
    @Default(.glassBlur) var glassBlur
    @Default(.glassDispersion) var glassDispersion
    @Default(.glassLensHeight) var glassLensHeight
    @Default(.glassCoreHeight) var glassCoreHeight
    @Default(.glassFadeSoftness) var glassFadeSoftness
    @Default(.glassFloorTransparency) var glassFloorTransparency
    @Default(.glassRimTone) var glassRimTone
    @Default(.glassRimIntensity) var glassRimIntensity

    var body: some View {
        if enableLiquidGlass && LiquidGlassAvailability.isSupported {
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
                NotchBlackFadeScrim(
                    shape: shape,
                    coreHeight: glassCoreHeight,
                    fadeSoftness: glassFadeSoftness,
                    floorTransparency: glassFloorTransparency
                )

                // Layer 3: Ambient Music Tint (Subtle Artwork Atmosphere in Mid-Band)
                if let ambient = ambientColor {
                    NotchAmbientMusicTint(
                        shape: shape,
                        coreHeight: glassCoreHeight,
                        fadeSoftness: glassFadeSoftness,
                        ambientColor: ambient
                    )
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
