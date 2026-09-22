//
//  NotchScrimCalculator.swift
//  NotBoringNotch
//

import Foundation
import SwiftUI

struct NotchScrimCalculator {
    /// Computes the precise gradient stops for the Hardware Scrim (100% camera concealment).
    ///
    /// - Parameters:
    ///   - totalHeight: Current height of the notch surface (animating or static).
    ///   - coreHeight: Top opaque black camera concealment region (default 80pt).
    ///   - fadeSoftness: Downward transition range into glass (default 100pt).
    ///   - floorTransparency: Bottom opacity floor (default 0.23).
    static func hardwareScrimStops(
        totalHeight: CGFloat,
        coreHeight: CGFloat,
        fadeSoftness: CGFloat,
        floorTransparency: CGFloat
    ) -> [Gradient.Stop] {
        // When the notch is closed or in early expansion (totalHeight <= coreHeight),
        // the entire area is within the hardware camera cutout, so it is 100% solid black!
        guard totalHeight > coreHeight else {
            return [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 1.0)
            ]
        }

        let coreLoc = coreHeight / totalHeight
        let fadeEndLoc = min(coreLoc + (fadeSoftness / totalHeight), 1.0)
        let floor = Double(min(max(floorTransparency, 0.0), 0.50))

        // Pure quadratic ease-out decay into glass.
        // Guarantees camera cutout remains 100% solid black above coreLoc!
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

    /// Computes dedicated gradient stops for the middle-band Ambient Music Tint.
    ///
    /// Layered on top of the Hardware Scrim so it adds subtle artwork color without
    /// weakening the black camera concealment.
    static func ambientTintStops(
        totalHeight: CGFloat,
        coreHeight: CGFloat,
        fadeSoftness: CGFloat,
        ambientColor: Color
    ) -> [Gradient.Stop] {
        guard totalHeight > coreHeight else {
            return [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 1.0)
            ]
        }

        let coreLoc = coreHeight / totalHeight
        let fadeEndLoc = min(coreLoc + (fadeSoftness / totalHeight), 1.0)
        let midLoc = coreLoc + (fadeEndLoc - coreLoc) * 0.40

        return [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: coreLoc),
            .init(color: ambientColor.opacity(0.14), location: midLoc),
            .init(color: .clear, location: fadeEndLoc),
            .init(color: .clear, location: 1.00)
        ]
    }
}
