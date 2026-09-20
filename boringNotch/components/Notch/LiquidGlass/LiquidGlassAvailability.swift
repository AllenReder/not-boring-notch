//
//  LiquidGlassAvailability.swift
//  boringNotch
//

import AppKit
import Foundation
import QuartzCore

enum LiquidGlassAvailability {
    /// Cached check for whether the host system supports CoreAnimation Liquid Glass refraction
    private static let _isSupported: Bool = {
        guard NSClassFromString("CABackdropLayer") != nil,
              NSClassFromString("CASDFLayer") != nil,
              NSClassFromString("CASDFElementLayer") != nil,
              NSClassFromString("CASDFOutputEffect") != nil else {
            return false
        }

        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol,
              let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground")?.takeUnretainedValue() else {
            return false
        }

        return true
    }()

    static var isSupported: Bool {
        _isSupported
    }
}
