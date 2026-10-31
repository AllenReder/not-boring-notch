//
//  LiquidGlassConfigurationTests.swift
//  Tests
//
// SOURCES: NotBoringNotch/components/Notch/LiquidGlass/LiquidGlassConfiguration.swift NotBoringNotch/components/Notch/LiquidGlass/LiquidGlassAvailability.swift
//

import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: condition is false - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct LiquidGlassConfigurationTestsRunner {
    static func main() {
        testRecommendedValues()
        testRecommendedValuesAreInsideTheirRanges()
        testFadeStartRangeForClosedNotch()
        testRimToneCases()
        print("🎉 All LiquidGlassConfigurationTests passed!")
    }

    static func testRecommendedValues() {
        let recommended = LiquidGlassConfiguration.Recommended.self
        assertEqual(recommended.refraction, 24.0, "Recommended refraction should be 24.0")
        assertEqual(recommended.blur, 0.5, "Recommended blur should be 0.5")
        assertEqual(recommended.dispersion, 4.0, "Recommended dispersion should be 4.0")
        assertEqual(recommended.lensHeight, 36.0, "Recommended lensHeight should be 36.0")
        assertEqual(recommended.fadeStart, 20.0, "Recommended fadeStart should be the slider minimum")
        assertEqual(recommended.fadeEndOpacity, 0.50, "Recommended fadeEndOpacity should be 0.50")
        assertEqual(recommended.rimTone, .neutralWhite, "Recommended rimTone should be neutralWhite")
        assertEqual(recommended.rimIntensity, 0.2, "Recommended rimIntensity should be 0.2")
        print("✅ testRecommendedValues passed")
    }

    /// A default outside its own slider range would make the control jump the
    /// first time it is touched, so the two have to agree.
    static func testRecommendedValuesAreInsideTheirRanges() {
        let recommended = LiquidGlassConfiguration.Recommended.self
        assertTrue(LiquidGlassConfiguration.refractionRange.contains(recommended.refraction))
        assertTrue(LiquidGlassConfiguration.blurRange.contains(recommended.blur))
        assertTrue(LiquidGlassConfiguration.dispersionRange.contains(recommended.dispersion))
        assertTrue(LiquidGlassConfiguration.lensHeightRange.contains(recommended.lensHeight))
        assertTrue(LiquidGlassConfiguration.fadeEndOpacityRange.contains(recommended.fadeEndOpacity))
        assertTrue(LiquidGlassConfiguration.rimIntensityRange.contains(recommended.rimIntensity))
        print("✅ testRecommendedValuesAreInsideTheirRanges passed")
    }

    static func testFadeStartRangeForClosedNotch() {
        let notched = LiquidGlassConfiguration.fadeStartRange(
            closedNotchHeight: 32,
            openNotchHeight: 190
        )
        assertEqual(notched.lowerBound, 32.0, "Range should start at the closed notch height")
        assertEqual(notched.upperBound, 190.0, "Range should end at the open notch height")

        let nonNotched = LiquidGlassConfiguration.fadeStartRange(
            closedNotchHeight: 0,
            openNotchHeight: 190
        )
        assertEqual(nonNotched.lowerBound, 20.0, "Range should never start below the control's minimum")
        assertTrue(
            nonNotched.contains(LiquidGlassConfiguration.Recommended.fadeStart),
            "The shipped default must be selectable on a display without a camera housing"
        )

        let tallerThanOpen = LiquidGlassConfiguration.fadeStartRange(
            closedNotchHeight: 500,
            openNotchHeight: 190
        )
        assertEqual(tallerThanOpen.lowerBound, 190.0, "Range lower bound should cap at the open notch height")

        print("✅ testFadeStartRangeForClosedNotch passed")
    }

    static func testRimToneCases() {
        let cases = LiquidGlassRimTone.allCases
        assertEqual(cases.count, 4, "Should have 4 rim tones")
        assertTrue(cases.contains(.neutralWhite))
        assertTrue(cases.contains(.sunsetGold))
        assertTrue(cases.contains(.siriGlow))
        assertTrue(cases.contains(.off))
        print("✅ testRimToneCases passed")
    }
}
