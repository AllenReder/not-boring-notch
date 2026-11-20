// The timelines. `full` and `short` (Storyboard.swift) are the launch film; `demo` exercises every
// piece of the studio; `syncTest` and `glassTest` are measurement rigs for the driver and for
// checking the camera.

import Foundation

@MainActor enum Scenes {
    static var all: [Timeline] { [full, short, demo, syncTest, glassTest] }

    static func named(_ name: String) -> Timeline {
        guard let t = all.first(where: { $0.name == name }) else {
            fatalError("no timeline named \(name); have \(all.map(\.name))")
        }
        return t
    }

    static var demo: Timeline {
        Timeline(name: "demo", duration: 8, cues: [
            // Closed notch, close up, music already playing behind it.
            .camera(at: 0, zoom: 4),
            .music(at: 0, nightDrive),
            // Pull out while the home view opens.
            .camera(at: 1.0, zoom: 1, over: 1.4),
            .notch(at: 1.2, .view(.home)),
            .notch(at: 1.2, .open),
            .caption(at: 2.0, "Your music, right in the notch", for: 2.0),
            .notch(at: 4.0, .close),
            // A banner, then an agent session.
            .banner(at: 4.3, Banner(title: "Build finished", subtitle: "12s · main",
                                    body: "All 16 tests passed.", symbol: "hammer.fill", duration: 1.5)),
            .agent(at: 5.8, session: "demo", .start),
            .agent(at: 5.9, session: "demo", .prompt),
            .agent(at: 6.1, session: "demo", .tool("Edit")),
            .caption(at: 6.0, "Agents, at a glance", for: 1.6),
            .camera(at: 6.4, zoom: 3, over: 1.4),
        ])
    }

    /// A flash of the marker colour at t=2.0: the trimmed video should show it starting at 2.0.
    static var syncTest: Timeline {
        Timeline(name: "sync-test", duration: 4, cues: [.flash(at: 2.0), .flash(at: 3.0)])
    }

    /// The glass at 1x, 2x (open notch) and 4x (banner), over the wallpaper.
    static var glassTest: Timeline {
        Timeline(name: "glass-test", duration: 7, cues: [
            .music(at: 0, nightDrive),
            .notch(at: 0.2, .view(.home)),
            .notch(at: 0.2, .open),
            .camera(at: 2.0, zoom: 2, over: 0.5),
            .caption(at: 2.0, "caption stays put at 2x", for: 2.0),
            .notch(at: 4.0, .close),
            .camera(at: 4.0, zoom: 4, over: 0.5),
            .banner(at: 4.6, Banner(title: "Glass at 4x", subtitle: "banner", body: "Lens over the wallpaper.", symbol: "hammer.fill", duration: 2.0)),
        ])
    }
}
