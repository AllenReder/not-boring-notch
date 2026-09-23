//
//  LiquidGlassAvailabilityAndScrimTests.swift
//  Tests
//
// SOURCES: NotBoringNotch/components/Notch/LiquidGlass/LiquidGlassAvailability.swift NotBoringNotch/components/Notch/LiquidGlass/NotchScrimCalculator.swift
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
        testHardwareScrimStopsOpened()
        testHardwareScrimStopsClosedHeight()
        testAmbientTintStopsOpened()
        testAmbientTintStopsClosedHeight()
        testScrimStopsDegenerateHeight()
        print("🎉 All LiquidGlassAvailabilityAndScrimTests passed!")
    }

    static func testAvailabilityCheck() {
        let supported = LiquidGlassAvailability.isSupported
        print("ℹ️ LiquidGlassAvailability.isSupported on current system = \(supported)")
        assertEqual(LiquidGlassAvailability.isSupported, supported, "Cached availability must match")
        print("✅ testAvailabilityCheck passed")
    }

    static func testHardwareScrimStopsOpened() {
        let totalHeight: CGFloat = 195.0
        let coreHeight: CGFloat = 80.0
        let softness: CGFloat = 100.0
        let floor: CGFloat = 0.23

        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: totalHeight,
            coreHeight: coreHeight,
            fadeSoftness: softness,
            floorTransparency: floor
        )

        assertTrue(stops.count >= 4, "Should have at least 4 gradient stops")
        assertEqual(stops[0].location, 0.0, "First stop at top (0.0)")
        let coreLoc = coreHeight / totalHeight
        assertTrue(abs(stops[1].location - coreLoc) < 0.01, "Second stop at coreLoc (~0.41)")
        assertEqual(stops.last?.location, 1.0, "Last stop at bottom (1.0)")
        print("✅ testHardwareScrimStopsOpened passed")
    }

    static func testHardwareScrimStopsClosedHeight() {
        // When height (32pt) <= coreHeight (80pt), must return 100% solid black to eliminate transparent transition
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 32.0,
            coreHeight: 80.0,
            fadeSoftness: 100.0,
            floorTransparency: 0.23
        )
        assertEqual(stops.count, 2, "Closed notch returns simple solid black stops")
        assertEqual(stops[0].location, 0.0)
        assertEqual(stops[1].location, 1.0)
        print("✅ testHardwareScrimStopsClosedHeight passed")
    }

    static func testAmbientTintStopsOpened() {
        let totalHeight: CGFloat = 195.0
        let coreHeight: CGFloat = 80.0
        let softness: CGFloat = 100.0
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
        print("✅ testAmbientTintStopsOpened passed")
    }

    static func testAmbientTintStopsClosedHeight() {
        // When closed, ambient tint stops should be completely clear
        let stops = NotchScrimCalculator.ambientTintStops(
            totalHeight: 32.0,
            coreHeight: 80.0,
            fadeSoftness: 100.0,
            ambientColor: Color.red
        )
        assertEqual(stops.count, 2)
        print("✅ testAmbientTintStopsClosedHeight passed")
    }

    static func testScrimStopsDegenerateHeight() {
        let stopsZero = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 0.0,
            coreHeight: 80.0,
            fadeSoftness: 100.0,
            floorTransparency: 0.23
        )
        assertTrue(!stopsZero.isEmpty)

        let stopsNegative = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: -100.0,
            coreHeight: 80.0,
            fadeSoftness: 100.0,
            floorTransparency: 0.23
        )
        assertTrue(!stopsNegative.isEmpty)
        print("✅ testScrimStopsDegenerateHeight passed")
    }
}
