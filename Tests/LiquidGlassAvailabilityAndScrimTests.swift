//
//  LiquidGlassAvailabilityAndScrimTests.swift
//  Tests
//
// SOURCES: NotBoringNotch/components/Notch/LiquidGlass/LiquidGlassAvailability.swift NotBoringNotch/components/Notch/LiquidGlass/NotchScrimCalculator.swift
//

import AppKit
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

func assertClose(_ actual: Double, _ expected: Double, _ message: String = "", accuracy: Double = 0.0001, file: StaticString = #file, line: UInt = #line) {
    if abs(actual - expected) > accuracy {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct LiquidGlassAvailabilityAndScrimTestsRunner {
    static func main() {
        testAvailabilityCheck()
        testOpenedNotchStaysOpaqueToTheFadeStartThenFadesToTheBottomEdge()
        testRampLandsOnFadeEndOpacityAtTheBottomEdge()
        testLaterFadeStartLeavesLessRoomForTheRamp()
        testClosedNotchStaysSolidBlack()
        testFadeNeverStartsAboveTheClosedNotchHeight()
        testDegenerateHeightStillReturnsStops()
        testFadeEndOpacityIsClampedToValidRange()
        testAmbientTintStaysOutOfTheSolidBlackBand()
        testAmbientTintIsClearWhileClosed()
        print("🎉 All LiquidGlassAvailabilityAndScrimTests passed!")
    }

    private static func opacities(_ stops: [Gradient.Stop]) -> [Double] {
        stops.map { Double(NSColor($0.color).alphaComponent) }
    }

    /// The scrim is one ramp: locations ascend, opacity only ever falls, and it
    /// starts fully opaque in the solid band and ends on `bottom` at the
    /// bottom edge of the surface.
    private static func assertSingleRamp(
        _ stops: [Gradient.Stop],
        endingAt bottom: Double,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let alphas = opacities(stops)

        assertClose(Double(stops.first?.location ?? -1), 0, "First stop must be at the top", file: file, line: line)
        assertClose(Double(stops.last?.location ?? -1), 1, "Last stop must be at the bottom", file: file, line: line)
        assertClose(alphas.first ?? -1, 1, "The top must be fully opaque", file: file, line: line)
        assertClose(alphas.last ?? -1, bottom, "The bottom must land on fadeEndOpacity", file: file, line: line)

        for (previous, next) in zip(stops, stops.dropFirst()) {
            assertTrue(previous.location <= next.location, "Stop locations must ascend", file: file, line: line)
        }
        for (previous, next) in zip(alphas, alphas.dropFirst()) {
            assertTrue(next <= previous + 0.0001, "Opacity must never increase", file: file, line: line)
        }
    }

    static func testAvailabilityCheck() {
        let supported = LiquidGlassAvailability.isSupported
        print("ℹ️ LiquidGlassAvailability.isSupported on current system = \(supported)")
        assertEqual(LiquidGlassAvailability.isSupported, supported, "Cached availability must match")
        print("✅ testAvailabilityCheck passed")
    }

    static func testOpenedNotchStaysOpaqueToTheFadeStartThenFadesToTheBottomEdge() {
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            fadeStart: 80,
            solidBlackHeight: 32,
            fadeEndOpacity: 0.23
        )

        // Everything above the fade start is fully opaque, and the fade into the
        // glass is one monotonic ramp from there to the bottom edge of the surface.
        assertClose(opacities(stops)[0], 1.0)
        assertClose(opacities(stops)[1], 1.0)
        assertClose(Double(stops[1].location), 80.0 / 190.0)
        assertSingleRamp(stops, endingAt: 0.23)
        print("✅ testOpenedNotchStaysOpaqueToTheFadeStartThenFadesToTheBottomEdge passed")
    }

    static func testRampLandsOnFadeEndOpacityAtTheBottomEdge() {
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            fadeStart: 80,
            solidBlackHeight: 32,
            fadeEndOpacity: 0.23
        )

        assertClose(opacities(stops).last ?? -1, 0.23)
        assertClose(Double(stops.last?.location ?? -1), 1.0)
        print("✅ testRampLandsOnFadeEndOpacityAtTheBottomEdge passed")
    }

    static func testLaterFadeStartLeavesLessRoomForTheRamp() {
        let shallow = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: 40, solidBlackHeight: 32, fadeEndOpacity: 0.23
        )
        let deep = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: 140, solidBlackHeight: 32, fadeEndOpacity: 0.23
        )

        // Both ramps end at the bottom edge; a later fade start just gets there
        // faster, which is the whole point of splitting the two controls.
        assertClose(Double(shallow[1].location), 40.0 / 190.0)
        assertClose(Double(deep[1].location), 140.0 / 190.0)
        assertSingleRamp(shallow, endingAt: 0.23)
        assertSingleRamp(deep, endingAt: 0.23)
        print("✅ testLaterFadeStartLeavesLessRoomForTheRamp passed")
    }

    static func testClosedNotchStaysSolidBlack() {
        // The shipped default fade start is shorter than every closed notch
        // height, so the surface has to clamp it: without that the closed notch
        // renders a ramp and the desktop shows through the camera housing.
        for closedHeight in [CGFloat(32), CGFloat(38), CGFloat(45)] {
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: closedHeight,
                fadeStart: 20,
                solidBlackHeight: closedHeight,
                fadeEndOpacity: 0.50
            )

            assertEqual(stops.count, 2, "closed height \(closedHeight) with the default fade start must stay solid black")
            assertClose(opacities(stops)[0], 1.0)
            assertClose(opacities(stops)[1], 1.0)
        }
        print("✅ testClosedNotchStaysSolidBlack passed")
    }

    static func testFadeNeverStartsAboveTheClosedNotchHeight() {
        let stops = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190,
            fadeStart: 20,
            solidBlackHeight: 38,
            fadeEndOpacity: 0.23
        )

        assertClose(Double(stops[1].location), 38.0 / 190.0)
        assertSingleRamp(stops, endingAt: 0.23)
        print("✅ testFadeNeverStartsAboveTheClosedNotchHeight passed")
    }

    static func testDegenerateHeightStillReturnsStops() {
        for totalHeight in [CGFloat(0), CGFloat(-100)] {
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: totalHeight,
                fadeStart: 80,
                solidBlackHeight: 32,
                fadeEndOpacity: 0.23
            )

            assertEqual(stops.count, 2)
        }
        print("✅ testDegenerateHeightStillReturnsStops passed")
    }

    static func testFadeEndOpacityIsClampedToValidRange() {
        let opaque = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: 80, solidBlackHeight: 32, fadeEndOpacity: 2
        )
        assertSingleRamp(opaque, endingAt: 1)

        let clear = NotchScrimCalculator.hardwareScrimStops(
            totalHeight: 190, fadeStart: 80, solidBlackHeight: 32, fadeEndOpacity: -1
        )
        assertSingleRamp(clear, endingAt: 0)
        print("✅ testFadeEndOpacityIsClampedToValidRange passed")
    }

    static func testAmbientTintStaysOutOfTheSolidBlackBand() {
        let stops = NotchScrimCalculator.ambientTintStops(
            totalHeight: 190,
            fadeStart: 80,
            solidBlackHeight: 32,
            ambientColor: .red
        )

        // The tint starts where the glass starts and peaks in the middle of the
        // ramp, so it never weakens the camera concealment.
        assertClose(opacities(stops)[0], 0.0)
        assertClose(opacities(stops)[1], 0.0)
        assertClose(Double(stops[1].location), 80.0 / 190.0)
        assertClose(opacities(stops)[2], 0.14)
        assertTrue(stops[2].location > stops[1].location)
        assertTrue(stops[2].location < stops[3].location)
        assertClose(opacities(stops)[3], 0.0)
        print("✅ testAmbientTintStaysOutOfTheSolidBlackBand passed")
    }

    static func testAmbientTintIsClearWhileClosed() {
        let stops = NotchScrimCalculator.ambientTintStops(
            totalHeight: 32,
            fadeStart: 80,
            solidBlackHeight: 32,
            ambientColor: .red
        )

        assertEqual(stops.count, 2)
        assertClose(opacities(stops)[0], 0.0)
        assertClose(opacities(stops)[1], 0.0)
        print("✅ testAmbientTintIsClearWhileClosed passed")
    }
}
