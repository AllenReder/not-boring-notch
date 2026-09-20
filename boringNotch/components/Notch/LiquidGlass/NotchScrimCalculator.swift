//
//  NotchScrimCalculator.swift
//  boringNotch
//

import Foundation
import SwiftUI

struct NotchScrimCalculator {
    /// Computes the precise gradient stops for the Hardware Scrim and Ambient Music Tint.
    ///
    /// - Parameters:
    ///   - totalHeight: Current height of the notch surface (animating or static).
    ///   - coreHeight: Top opaque black camera concealment region (default 34pt).
    ///   - fadeSoftness: Downward transition range into glass (default 45pt).
    ///   - floorTransparency: Bottom opacity floor (default 0.0 = 100% crystal clear).
    ///   - ambientColor: Optional album art dominant color for middle-band tinting.
    static func stops(
        totalHeight: CGFloat,
        coreHeight: CGFloat,
        fadeSoftness: CGFloat,
        floorTransparency: CGFloat,
        ambientColor: Color? = nil
    ) -> [Gradient.Stop] {
        guard totalHeight > 0 else {
            return [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 1.0)
            ]
        }

        let effectiveHeight = max(totalHeight, 1.0)
        let coreLoc = min(max(coreHeight / effectiveHeight, 0.0), 0.60)
        let fadeEndLoc = min(coreLoc + (fadeSoftness / effectiveHeight), 0.95)
        let floor = Double(min(max(floorTransparency, 0.0), 0.50))

        if let ambient = ambientColor {
            // Tiered Ambient Music Tint:
            // 0 ~ coreLoc: 100% solid black over camera
            // mid-band (coreLoc ~ 80pt): soft 14% ambient artwork tint
            // bottom: dissolves back to floor transparency, leaving bottom refraction crystal clear
            let tintLoc = coreLoc + (fadeEndLoc - coreLoc) * 0.35
            let decayLoc = coreLoc + (fadeEndLoc - coreLoc) * 0.70

            return [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: coreLoc),
                .init(color: ambient.opacity(0.14), location: tintLoc),
                .init(color: .black.opacity(0.20), location: decayLoc),
                .init(color: .black.opacity(floor), location: fadeEndLoc),
                .init(color: .black.opacity(floor), location: 1.00)
            ]
        } else {
            // Classic Hardware Scrim (Quadratic ease-out decay into glass)
            let mid1 = coreLoc + (fadeEndLoc - coreLoc) * 0.35
            let mid2 = coreLoc + (fadeEndLoc - coreLoc) * 0.70

            return [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: coreLoc),
                .init(color: .black.opacity(0.65), location: mid1),
                .init(color: .black.opacity(0.18), location: mid2),
                .init(color: .black.opacity(floor), location: fadeEndLoc),
                .init(color: .black.opacity(floor), location: 1.00)
            ]
        }
    }
}
