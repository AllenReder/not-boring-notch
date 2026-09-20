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
        testScrimStopsWithoutAmbient()
        testScrimStopsWithAmbient()
        testScrimStopsDegenerateHeight()
        print("🎉 All LiquidGlassAvailabilityAndScrimTests passed!")
    }

    static func testAvailabilityCheck() {
        // Must execute safely and return a boolean
        let supported = LiquidGlassAvailability.isSupported
        print("ℹ️ LiquidGlassAvailability.isSupported on current system = \(supported)")
        // Verify caching: subsequent calls return same value without re-querying
        assertEqual(LiquidGlassAvailability.isSupported, supported, "Cached availability must match")
        print("✅ testAvailabilityCheck passed")
    }

    static func testScrimStopsWithoutAmbient() {
        let totalHeight: CGFloat = 195.0
        let coreHeight: CGFloat = 34.0
        let softness: CGFloat = 45.0
        let floor: CGFloat = 0.0

        let stops = NotchScrimCalculator.stops(
            totalHeight: totalHeight,
            coreHeight: coreHeight,
            fadeSoftness: softness,
            floorTransparency: floor,
            ambientColor: nil
        )

        assertTrue(stops.count >= 4, "Should have at least 4 gradient stops")
        assertEqual(stops[0].location, 0.0, "First stop at top (0.0)")
        let coreLoc = coreHeight / totalHeight
        assertTrue(abs(stops[1].location - coreLoc) < 0.01, "Second stop at coreLoc (~0.174)")
        assertEqual(stops.last?.location, 1.0, "Last stop at bottom (1.0)")
        print("✅ testScrimStopsWithoutAmbient passed")
    }

    static func testScrimStopsWithAmbient() {
        let totalHeight: CGFloat = 195.0
        let coreHeight: CGFloat = 34.0
        let softness: CGFloat = 45.0
        let floor: CGFloat = 0.05
        let testColor = Color.red

        let stops = NotchScrimCalculator.stops(
            totalHeight: totalHeight,
            coreHeight: coreHeight,
            fadeSoftness: softness,
            floorTransparency: floor,
            ambientColor: testColor
        )

        assertTrue(stops.count >= 5, "With ambient color, should have tiered intermediate stops")
        assertEqual(stops[0].location, 0.0, "First stop at top")
        assertEqual(stops.last?.location, 1.0, "Last stop at bottom")
        print("✅ testScrimStopsWithAmbient passed")
    }

    static func testScrimStopsDegenerateHeight() {
        // Zero or negative height should not cause NaN or crash
        let stopsZero = NotchScrimCalculator.stops(
            totalHeight: 0.0,
            coreHeight: 34.0,
            fadeSoftness: 45.0,
            floorTransparency: 0.0,
            ambientColor: nil
        )
        assertTrue(!stopsZero.isEmpty, "Degenerate zero height returns safe fallback stops")

        let stopsNegative = NotchScrimCalculator.stops(
            totalHeight: -100.0,
            coreHeight: 34.0,
            fadeSoftness: 45.0,
            floorTransparency: 0.0,
            ambientColor: nil
        )
        assertTrue(!stopsNegative.isEmpty, "Degenerate negative height returns safe fallback stops")
        print("✅ testScrimStopsDegenerateHeight passed")
    }
}
