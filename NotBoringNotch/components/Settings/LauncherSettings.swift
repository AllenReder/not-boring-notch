//
//  LauncherSettings.swift
//  NotBoringNotch
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct LauncherSettings: View {
    @Default(.launcherRowHeight) private var rowHeight: CGFloat
    @Default(.launcherRecentsLimit) private var recentsLimit: Int

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle the launcher:", name: .toggleLauncher)
            } header: {
                Text("Launcher")
            } footer: {
                footer(
                    """
                    Opens the notch on the launcher, ready to type in, and closes it again when \
                    pressed a second time.
                    """)
            }

            Section {
                Slider(value: $rowHeight, in: 24...44, step: 2) {
                    HStack {
                        Text("Row height")
                        Spacer()
                        Text("\(rowHeight, specifier: "%.0f") pt")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $recentsLimit, in: 0...LauncherRecents.kept) {
                    HStack {
                        Text("Recent apps")
                        Spacer()
                        Text("\(recentsLimit)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("List")
            } footer: {
                footer(
                    """
                    The icon and the name grow with the row. Recent apps are the ones you switched \
                    to last, newest first; setting it to zero leaves them out.
                    """)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Launcher")
    }

    private func footer(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}
