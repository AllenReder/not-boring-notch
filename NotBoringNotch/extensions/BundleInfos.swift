//
//  BundleInfos.swift
//  NotBoringNotch
//
//  Created by Richard Kunkli on 08/08/2024.
//

import AppKit

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

func isExtensionRunning(_ bundleID: String) -> Bool {
    if let _ = NSWorkspace.shared.runningApplications.first(where: {$0.bundleIdentifier == bundleID}) {
        return true
    }
    
    return false
}
