//
//  NotchScrimCalculator.swift
//  NotBoringNotch
//

import Foundation
import SwiftUI

struct NotchScrimCalculator {
    /// Gradient stops for the scrim that hides the physical camera housing: solid
    /// black down to the fade start, then a smoothstep ramp that reaches
    /// `fadeEndOpacity` exactly at the bottom edge of the surface.
    ///
    /// - Parameters:
    ///   - totalHeight: Height of the notch surface right now, animating or static.
    ///   - fadeStart: Where the user wants the fade to begin, in points.
    ///   - solidBlackHeight: Height of the closed notch. The fade never starts
    ///     above it, or the closed notch would stop being black and let the
    ///     desktop show through the camera housing.
    ///   - fadeEndOpacity: Opacity the ramp ends on, so the lowest band keeps a
    ///     black wash under the content instead of going fully clear.
    static func hardwareScrimStops(
        totalHeight: CGFloat,
        fadeStart: CGFloat,
        solidBlackHeight: CGFloat,
        fadeEndOpacity: CGFloat
    ) -> [Gradient.Stop] {
        let rampStart = max(fadeStart, solidBlackHeight)

        // Up to the fade start the whole surface sits over the hardware cutout,
        // so it is solid black — this is also the closed notch.
        guard totalHeight > rampStart else {
            return [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 1.0)
            ]
        }

        let rampStartLoc = min(rampStart / totalHeight, 1.0)
        let bottom = Double(min(max(fadeEndOpacity, 0.0), 1.0))

        // The ramp always spans everything below the fade start, so the slider can
        // never describe a transition the surface has no room for. Sampling a
        // smoothstep keeps the slope at zero on both ends, which is what stops
        // the scrim showing a band edge where it leaves the solid band or lands
        // on the bottom edge.
        var stops: [Gradient.Stop] = [
            .init(color: .black, location: 0.0),
            .init(color: .black, location: rampStartLoc)
        ]
        for step in 1...fadeSampleCount {
            let t = Double(step) / Double(fadeSampleCount)
            let eased = t * t * (3 - 2 * t)
            stops.append(
                .init(
                    color: .black.opacity(1 + (bottom - 1) * eased),
                    location: rampStartLoc + (1 - rampStartLoc) * CGFloat(t)
                )
            )
        }
        return stops
    }

    /// Gradient stops for the ambient music tint that sits above the scrim. The
    /// tint only covers the band that is already glass — it never reaches into the
    /// solid black camera concealment — so it cannot weaken the housing cover.
    static func ambientTintStops(
        totalHeight: CGFloat,
        fadeStart: CGFloat,
        solidBlackHeight: CGFloat,
        ambientColor: Color
    ) -> [Gradient.Stop] {
        let rampStart = max(fadeStart, solidBlackHeight)

        guard totalHeight > rampStart else {
            return [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 1.0)
            ]
        }

        let rampStartLoc = min(rampStart / totalHeight, 1.0)
        let midLoc = rampStartLoc + (1 - rampStartLoc) * 0.40

        return [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: rampStartLoc),
            .init(color: ambientColor.opacity(0.14), location: midLoc),
            .init(color: .clear, location: 1.00)
        ]
    }

    /// Enough samples that the linear interpolation between them reads as a curve.
    private static let fadeSampleCount = 8
}
