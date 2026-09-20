//
//  LiquidGlassConfigurationTests.swift
//  Tests
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
        testRecommendedConfiguration()
        testClampingOutOfBounds()
        testRimToneCases()
        print("🎉 All LiquidGlassConfigurationTests passed!")
    }

    static func testRecommendedConfiguration() {
        let config = LiquidGlassConfiguration.recommended
        assertEqual(config.refraction, 20.0, "Recommended refraction should be 20.0")
        assertEqual(config.blur, 0.0, "Recommended blur should be 0.0")
        assertEqual(config.dispersion, 4.0, "Recommended dispersion should be 4.0")
        assertEqual(config.lensHeight, 23.0, "Recommended lensHeight should be 23.0")
        assertEqual(config.coreHeight, 34.0, "Recommended coreHeight should be 34.0")
        assertEqual(config.fadeSoftness, 45.0, "Recommended fadeSoftness should be 45.0")
        assertEqual(config.floorTransparency, 0.0, "Recommended floorTransparency should be 0.0")
        assertEqual(config.rimTone, .neutralWhite, "Recommended rimTone should be neutralWhite")
        assertEqual(config.rimIntensity, 0.4, "Recommended rimIntensity should be 0.4")
        print("✅ testRecommendedConfiguration passed")
    }

    static func testClampingOutOfBounds() {
        var config = LiquidGlassConfiguration(
            refraction: 250.0,
            blur: 99.0,
            dispersion: 50.0,
            lensHeight: 120.0,
            coreHeight: 200.0,
            fadeSoftness: 500.0,
            floorTransparency: 1.5,
            rimTone: .neutralWhite,
            rimIntensity: 10.0
        )
        config.clampToBounds()

        assertEqual(config.refraction, 100.0, "Refraction should clamp to 100.0")
        assertEqual(config.blur, 30.0, "Blur should clamp to 30.0")
        assertEqual(config.dispersion, 15.0, "Dispersion should clamp to 15.0")
        assertEqual(config.lensHeight, 60.0, "LensHeight should clamp to 60.0")
        assertEqual(config.coreHeight, 80.0, "CoreHeight should clamp to 80.0")
        assertEqual(config.fadeSoftness, 100.0, "FadeSoftness should clamp to 100.0")
        assertEqual(config.floorTransparency, 0.50, "FloorTransparency should clamp to 0.50")
        assertEqual(config.rimIntensity, 2.0, "RimIntensity should clamp to 2.0")

        var negativeConfig = LiquidGlassConfiguration(
            refraction: -50.0,
            blur: -10.0,
            dispersion: -5.0,
            lensHeight: 2.0,
            coreHeight: 5.0,
            fadeSoftness: 2.0,
            floorTransparency: -0.5,
            rimTone: .off,
            rimIntensity: -1.0
        )
        negativeConfig.clampToBounds()

        assertEqual(negativeConfig.refraction, 0.0, "Refraction should clamp to 0.0")
        assertEqual(negativeConfig.blur, 0.0, "Blur should clamp to 0.0")
        assertEqual(negativeConfig.dispersion, 0.0, "Dispersion should clamp to 0.0")
        assertEqual(negativeConfig.lensHeight, 10.0, "LensHeight should clamp to 10.0")
        assertEqual(negativeConfig.coreHeight, 20.0, "CoreHeight should clamp to 20.0")
        assertEqual(negativeConfig.fadeSoftness, 10.0, "FadeSoftness should clamp to 10.0")
        assertEqual(negativeConfig.floorTransparency, 0.0, "FloorTransparency should clamp to 0.0")
        assertEqual(negativeConfig.rimIntensity, 0.0, "RimIntensity should clamp to 0.0")

        print("✅ testClampingOutOfBounds passed")
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
