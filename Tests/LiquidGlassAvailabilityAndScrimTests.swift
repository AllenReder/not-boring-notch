//
//  LiquidGlassAvailabilityAndScrimTests.swift
//  Tests
//

import Foundation
import SwiftUI

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
struct LiquidGlassAvailabilityAndScrimTestsRunner {
    static func main() {
        testAvailabilityCheck()
        testHardwareScrimStops()
        testAmbientTintStops()
        testScrimStopsDegenerateHeight()
        print("🎉 All LiquidGlassAvailabilityAndScrimTests passed!")
    }

    static func testAvailabilityCheck() {
        // Must execute safely and return a boolean
        let supported = LiquidGlassAvailability.isSupported
        print("ℹ️ LiquidGlassAvailability.isSupported on current system = \(supported)")
        assertEqual(LiquidGlassAvailability.isSupported, supported, "Cached availability must match")
        print("✅ testAvailabilityCheck passed")
    }

    static func testHardwareScrimStops() {
        let totalHeight: CGFloat = 195.0
        let coreHeight: CGFloat = 34.0
        let softness: CGFloat = 45.0
        let floor: CGFloat = 0.0

        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: totalHeight,
            coreHeight: coreHeight,
            fadeSoftness: softness,
            floorTransparency: floor
        )

        assertTrue(stops.count >= 4, "Should have at least 4 gradient stops")
        assertEqual(stops[0].location, 0.0, "First stop at top (0.0)")
        let coreLoc = coreHeight / totalHeight
        assertTrue(abs(stops[1].location - coreLoc) < 0.01, "Second stop at coreLoc (~0.174)")
        assertEqual(stops.last?.location, 1.0, "Last stop at bottom (1.0)")
        print("✅ testHardwareScrimStops passed")
    }

    static func testAmbientTintStops() {
        let totalHeight: CGFloat = 195.0
        let coreHeight: CGFloat = 34.0
        let softness: CGFloat = 45.0
        let testColor = Color.red

        let stops = NotchScrimCalculator.ambientTintStops(
            totalHeight: totalHeight,
            coreHeight: coreHeight,
            fadeSoftness: softness,
            ambientColor: testColor
        )

        assertTrue(stops.count >= 5, "Ambient tint has clear boundaries and middle tint peak")
        assertEqual(stops[0].location, 0.0, "First stop at top is clear")
        assertEqual(stops.last?.location, 1.0, "Last stop at bottom is clear")
        print("✅ testAmbientTintStops passed")
    }

    static func testScrimStopsDegenerateHeight() {
        // Zero or negative height should not cause NaN or crash
        let stopsZero = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 0.0,
            coreHeight: 34.0,
            fadeSoftness: 45.0,
            floorTransparency: 0.0
        )
        assertTrue(!stopsZero.isEmpty, "Degenerate zero height returns safe fallback stops")

        let stopsNegative = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: -100.0,
            coreHeight: 34.0,
            fadeSoftness: 45.0,
            floorTransparency: 0.0
        )
        assertTrue(!stopsNegative.isEmpty, "Degenerate negative height returns safe fallback stops")
        print("✅ testScrimStopsDegenerateHeight passed")
    }
}
