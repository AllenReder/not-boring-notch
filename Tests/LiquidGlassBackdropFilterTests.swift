//
//  LiquidGlassBackdropFilterTests.swift
//  Tests
//
// SOURCES: NotBoringNotch/components/Notch/LiquidGlass/LiquidGlassBackdropView.swift
//

import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct LiquidGlassBackdropFilterTestsRunner {
    static func main() {
        testBlurDrivesOnlyTheFrost()
        testBlurFillPassStaysOffAtEveryBlur()
        testLensHeightDrivesBothRefractivePasses()
        testFaceStaysCrystalClear()
        print("🎉 All LiquidGlassBackdropFilterTests passed!")
    }

    private static let blurFillKeys = [
        "inputBlurFillBlurRadius",
        "inputBlurFillNormalOpacity",
        "inputBlurFillLightenOpacity",
        "inputBlurFillDarkenOpacity",
    ]

    private static func inputs(
        refraction: Double = -24,
        lensHeight: Double = 36,
        blur: Double = 0.5,
        dispersion: Double = 4
    ) -> [String: Double] {
        LiquidGlassBackdropView.glassFilterInputs(
            refraction: refraction,
            lensHeight: lensHeight,
            blur: blur,
            dispersion: dispersion
        )
    }

    static func testBlurDrivesOnlyTheFrost() {
        for blur in [0.0, 0.5, 5.0, 30.0] {
            let values = inputs(blur: blur)
            assertEqual(values["inputBlurRadius"] ?? .nan, blur, "Blur should map onto the frost radius")
        }
        print("✅ testBlurDrivesOnlyTheFrost passed")
    }

    /// Regression: the fill pass used to switch on at any blur above zero and
    /// composited an unrefracted copy of the notch beneath the refracted surface.
    static func testBlurFillPassStaysOffAtEveryBlur() {
        for blur in [0.0, 0.5, 5.0, 30.0] {
            let values = inputs(blur: blur)
            for key in blurFillKeys {
                assertEqual(values[key] ?? .nan, 0.0, "\(key) must stay off at blur \(blur)")
            }
        }
        print("✅ testBlurFillPassStaysOffAtEveryBlur passed")
    }

    static func testLensHeightDrivesBothRefractivePasses() {
        let values = inputs(lensHeight: 36, dispersion: 4)
        assertEqual(values["inputInnerRefractionHeight"] ?? .nan, 36.0, "Refraction should use the lens height")
        assertEqual(values["inputAberrationHeight"] ?? .nan, 36.0, "Dispersion should share the lens height")
        assertEqual(values["inputInnerRefractionAmount"] ?? .nan, -24.0, "Refraction should reach the filter as the caller signed it")
        assertEqual(values["inputAberrationAmount"] ?? .nan, 4.0, "Dispersion should map onto the aberration amount")
        print("✅ testLensHeightDrivesBothRefractivePasses passed")
    }

    static func testFaceStaysCrystalClear() {
        let values = inputs()
        assertEqual(values["inputFaceOpacity"] ?? .nan, 1.0, "The glass face must stay opaque")
        assertEqual(values["inputBleedAmount"] ?? .nan, 0.0, "Nothing may bleed past the glass face")
        print("✅ testFaceStaysCrystalClear passed")
    }
}
