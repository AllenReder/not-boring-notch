//
//  sizeMatters.swift
//  NotBoringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let shadowPadding: CGFloat = 20
/// The room the open notch leaves below whatever its tab draws.
let openNotchBottomPadding: CGFloat = 12
let openNotchSize: CGSize = .init(width: 640, height: 190)
/// The most the launcher ever asks for: a search field and a screenful of rows, which the standard
/// surface has no room for. It reports the height it actually needs as the list changes; this is
/// the ceiling the window is sized for.
let launcherNotchSize: CGSize = .init(width: openNotchSize.width, height: 440)
/// The most the Inbox ever asks for. Like the launcher, it reports the height its notifications
/// need, and scrolls past this.
let inboxNotchSize: CGSize = .init(width: openNotchSize.width, height: 340)
/// The tallest surface any tab asks for, read from the tabs themselves so a new tab cannot be
/// forgotten here. The window is sized to it, so a tab growing taller never clips.
let maxOpenNotchSize: CGSize = NotchViews.allCases
    .map(\.expandedSize)
    .reduce(.zero) { largest, size in
        CGSize(width: max(largest.width, size.width), height: max(largest.height, size.height))
    }
let windowSize: CGSize = .init(
    width: maxOpenNotchSize.width, height: maxOpenNotchSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

extension NotchViews {
    /// The surface the notch grows to while this tab is open. Every tab shares the width for
    /// now; the launcher and the Inbox ask for a different height.
    var expandedSize: CGSize {
        switch self {
        case .home, .shelf, .performance:
            return openNotchSize
        case .launcher:
            return launcherNotchSize
        case .inbox:
            return inboxNotchSize
        }
    }
}

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

/// How far the closed notch's content keeps from the camera housing's reported edge. The panel's
/// mask reaches a few points past that edge, and content drawn right up to it is cut.
let closedNotchHousingMargin: CGFloat = 8

/// The width the closed notch keeps clear in its middle, for the camera housing. On a screen with
/// one it is the housing as macOS reports it, a margin either side; on a screen without, the drawn
/// notch's own middle, as it has always been.
@MainActor func getClosedNotchGap(screenUUID: String? = nil) -> CGFloat {
    let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
    if let screen,
       let left = screen.auxiliaryTopLeftArea?.width,
       let right = screen.auxiliaryTopRightArea?.width
    {
        return screen.frame.width - left - right + 2 * closedNotchHousingMargin
    }
    return getClosedNotchSize(screenUUID: screenUUID).width - 20
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
