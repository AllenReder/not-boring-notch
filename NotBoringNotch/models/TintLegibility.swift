//
//  TintLegibility.swift
//  NotBoringNotch
//
//  The two adjustments the notch applies to a color before it draws it: the Legibility
//  Floor and the Brightness Pin. Pure arithmetic, no AppKit.
//

import Foundation

/// An sRGB color whose components are in `0...1`.
struct RGBColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    /// Perceived Brightness: the Rec.709 luma every legibility rule here is stated in.
    var perceivedBrightness: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// The Legibility Floor: raise a color below `factor` to it, and return a color that
    /// already reaches it unchanged. Never darkens.
    ///
    /// The lift mixes toward white: every channel becomes `c + t(1 - c)` with
    /// `t = (factor - L) / (1 - L)`. Luma is linear in the channels, so the result lands
    /// exactly on `factor`, no channel passes 1.0, and the hue region is kept — the color
    /// only gets paler. Black has no hue, so it becomes the neutral gray at `factor`.
    func withMinimumBrightness(_ factor: Double) -> RGBColor {
        let brightness = perceivedBrightness
        guard Self.isFactor(factor), brightness < factor else { return self }

        // brightness < factor <= 1, so the denominator is positive.
        let t = (factor - brightness) / (1 - brightness)
        return RGBColor(
            red: red + t * (1 - red),
            green: green + t * (1 - green),
            blue: blue + t * (1 - blue),
            alpha: alpha
        )
    }

    /// The Brightness Pin: move a color to exactly `target` Perceived Brightness, lighter
    /// or darker as required. Decoration (a gradient end, a glow) pins; text floors.
    func withBrightness(_ target: Double) -> RGBColor {
        guard Self.isFactor(target) else { return self }
        return scaled(toBrightness: target)
    }

    private static func isFactor(_ value: Double) -> Bool {
        (0...1).contains(value)
    }

    /// Every channel multiplied by `target / perceivedBrightness`, clipped at 1.0. Only the
    /// Brightness Pin uses it, because it must also darken; when brightening, the clip can
    /// leave a saturated color below `target` and shift its hue. A color with no brightness at all has no hue to carry, so it becomes the neutral
    /// gray at `target` — the division would otherwise produce NaN channels.
    private func scaled(toBrightness target: Double) -> RGBColor {
        guard perceivedBrightness > 0 else {
            return RGBColor(red: target, green: target, blue: target, alpha: alpha)
        }

        let scale = target / perceivedBrightness
        return RGBColor(
            red: min(red * scale, 1),
            green: min(green * scale, 1),
            blue: min(blue * scale, 1),
            alpha: alpha
        )
    }
}
