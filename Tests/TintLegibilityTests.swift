//
//  TintLegibilityTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh, which compiles it against the
//  sources declared below. The Tests folder is not part of an Xcode target, so each
//  runner is compiled on its own.
//
// SOURCES: NotBoringNotch/models/TintLegibility.swift
//
//  Helper names are prefixed (`check*`) so they stay distinguishable from the helpers
//  in the other standalone runners in this folder.
//

import Foundation

func checkColor(_ actual: RGBColor, _ expected: RGBColor, tolerance: Double = 0.0005,
                _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    let close = abs(actual.red - expected.red) <= tolerance
        && abs(actual.green - expected.green) <= tolerance
        && abs(actual.blue - expected.blue) <= tolerance
        && abs(actual.alpha - expected.alpha) <= tolerance
    if !close {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func checkCondition(_ condition: Bool, _ message: String = "",
                    file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct TintLegibilityTestsRunner {
    static func main() {
        testFloorLeavesABrightColorAlone()
        testFloorRaisesADarkColorToTheFloor()
        testSaturatedColorReachesTheFloorWithoutClipping()
        testFloorNeverDarkens()
        testFloorIgnoresAnOutOfRangeFactor()
        testFloorLiftsBlackToNeutralGray()
        testPinMovesInBothDirections()
        testPinNormalisesWhereTheFloorDoesNot()
        print("✅ TintLegibilityTests: all passed")
    }

    /// A color that already reaches the floor is drawn as itself — the case the old
    /// `ensureMinimumBrightness` was missing (issue #17).
    static func testFloorLeavesABrightColorAlone() {
        let white = RGBColor(red: 1, green: 1, blue: 1, alpha: 1)
        checkColor(white.withMinimumBrightness(0.8), white, "white is already brighter than 0.8")

        let gray = RGBColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)
        checkColor(gray.withMinimumBrightness(0.6), gray, "0.7 luma is already above the floor")
    }

    /// A dark color is lifted to the floor. `#95292C` is the NeteaseMusic icon average from
    /// issue #17; mixing it toward white by t = (0.6 - L) / (1 - L) gives `#C68D8E`.
    static func testFloorRaisesADarkColorToTheFloor() {
        let netease = RGBColor(red: 149.0 / 255, green: 41.0 / 255, blue: 44.0 / 255, alpha: 1)
        checkCondition(abs(netease.perceivedBrightness - 0.2517) < 0.0005,
                       "fixture luma drifted: \(netease.perceivedBrightness)")

        checkColor(netease.withMinimumBrightness(0.6),
                   RGBColor(red: 0.77780, green: 0.55142, blue: 0.55770, alpha: 1),
                   "t = (0.6 - 0.2517) / (1 - 0.2517) = 0.4655 toward white")

        // A neutral color stays neutral and reaches exactly the floor.
        let gray = RGBColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        checkCondition(abs(gray.withMinimumBrightness(0.6).perceivedBrightness - 0.6) < 0.0005,
                       "a gray must land exactly on the floor")
    }

    /// The old lift scaled every channel and clipped at 1.0, so a saturated color landed
    /// below the floor with its hue shifted (issue #22). Lifting toward white reaches the
    /// floor exactly with no channel at 1.0, and keeps red the dominant channel.
    static func testSaturatedColorReachesTheFloorWithoutClipping() {
        let netease = RGBColor(red: 149.0 / 255, green: 41.0 / 255, blue: 44.0 / 255, alpha: 1)
        let lifted = netease.withMinimumBrightness(0.6)
        for channel in [lifted.red, lifted.green, lifted.blue] {
            checkCondition(channel < 1.0, "no channel clips at 1.0: \(lifted)")
        }
        checkCondition(abs(lifted.perceivedBrightness - 0.6) < 1e-9,
                       "the lift lands on the floor: \(lifted.perceivedBrightness)")
        checkCondition(lifted.red > lifted.blue && lifted.blue > lifted.green,
                       "the channel order, and so the hue region, is kept: \(lifted)")
    }

    /// "Never darkens" is the whole point of a floor, so it holds for every color it lifts.
    static func testFloorNeverDarkens() {
        let colors = [
            RGBColor(red: 0, green: 0, blue: 0, alpha: 1),
            RGBColor(red: 149.0 / 255, green: 41.0 / 255, blue: 44.0 / 255, alpha: 1),
            RGBColor(red: 0, green: 122.0 / 255, blue: 1, alpha: 1),
            RGBColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1),
            RGBColor(red: 0.05, green: 0.4, blue: 0.05, alpha: 1),
            RGBColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]

        for color in colors {
            for factor in [0.2, 0.6, 0.8] {
                let lifted = color.withMinimumBrightness(factor)
                checkCondition(lifted.perceivedBrightness >= color.perceivedBrightness - 1e-9,
                               "floor darkened \(color) at \(factor) into \(lifted)")
                for channel in [lifted.red, lifted.green, lifted.blue] {
                    checkCondition(channel.isFinite && (0...1).contains(channel),
                                   "channel out of range in \(lifted)")
                }
            }
        }
    }

    /// An out-of-bounds factor returns the color untouched, as the old helper did.
    static func testFloorIgnoresAnOutOfRangeFactor() {
        let color = RGBColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        for factor in [-0.1, 1.5, .nan] {
            checkColor(color.withMinimumBrightness(factor), color, "factor \(factor) is out of bounds")
        }
        checkColor(color.withMinimumBrightness(0), color, "a zero floor asks for nothing")
    }

    /// A color with no brightness at all would divide by zero. It has no hue to carry, so it
    /// becomes the neutral gray at the factor instead of NaN channels.
    static func testFloorLiftsBlackToNeutralGray() {
        let black = RGBColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let lifted = black.withMinimumBrightness(0.6)
        checkColor(lifted, RGBColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.5),
                   "black lifts to gray at the floor, keeping its alpha")
        checkCondition(lifted.red.isFinite, "no NaN channels")
    }

    /// The pin moves a color onto a target brightness in both directions, unlike the floor.
    static func testPinMovesInBothDirections() {
        let accent = RGBColor(red: 0, green: 122.0 / 255, blue: 1, alpha: 1)
        checkCondition(abs(accent.perceivedBrightness - 0.4144) < 0.0005,
                       "fixture luma drifted: \(accent.perceivedBrightness)")

        let dimmed = accent.withBrightness(0.2)
        checkColor(dimmed, RGBColor(red: 0, green: 0.23089, blue: 0.48261, alpha: 1),
                   "0.2 / 0.4144 = 0.4826")
        checkCondition(abs(dimmed.perceivedBrightness - 0.2) < 0.0005,
                       "the pin lands on its target: \(dimmed.perceivedBrightness)")

        // Brightening clips the blue channel, which is already at 1.0.
        checkColor(accent.withBrightness(0.7),
                   RGBColor(red: 0, green: 0.80814, blue: 1.0, alpha: 1),
                   "0.7 / 0.4144 = 1.6893, blue clips at 1.0")
    }

    /// The decision this file exists for: the same color is left alone by the
    /// floor and normalised by the pin.
    static func testPinNormalisesWhereTheFloorDoesNot() {
        let white = RGBColor(red: 1, green: 1, blue: 1, alpha: 1)
        checkColor(white.withMinimumBrightness(0.6), white, "the floor has nothing to do")
        checkColor(white.withBrightness(0.6), RGBColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1),
                   "the pin normalises it")
    }
}
