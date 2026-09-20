//
//  SoftwareUpdater.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct CheckForUpdatesView: View {
    var body: some View {
        Button("Check for Updates…") {
            if let url = URL(string: "https://github.com/AllenReder/not-boring-notch/releases") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
