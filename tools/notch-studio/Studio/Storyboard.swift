// The launch film, from STORYBOARD.md: one function per scene, each returning its duration and
// cues from its own start. `full` lays them out at storyboard times (30 s); `short` is the 15 s cut
// (hook, reveal, agents, outro) with the reveal and agents squeezed.
//
// Cues that mention a camera zoom keep the subject filling the frame: the open notch is 640pt wide
// on a 1280pt stage, so 1.6x makes it 80% of the frame; closed-notch details need 2.5-4x.

import AppKit
import Defaults
import SwiftUI

extension Scenes {
    /// Each scene starts from a closed or settled notch and leaves it settled: nothing opens, closes
    /// or switches tab while the previous move is still fading, which is what made the first cut flicker.
    static let full = Timeline.sequence("full", [
        hook(), reveal(), volume(), shelf(), stats(), launcher(), agents(), outro(),
    ])

    /// 15 s: hook, reveal, agents, outro.
    static let short = Timeline.sequence("short", [
        hook(duration: 2.5), reveal(duration: 2.5), agents(duration: 7.5), outro(duration: 2.5),
    ])

    /// The open notch at 80% of the frame width.
    static let openZoom = 1.6

    static let nightDrive = Track.placeholder("Night Drive", "Placeholder FM", hue: 0.62)
    static let glassHours = Track.placeholder("Glass Hours", "Placeholder FM", hue: 0.04, variant: 1)

    /// A point in the notch's own coordinates (the 640pt-wide window it is drawn in) as stage points
    /// at camera `zoom`. The camera scales about the top centre of the stage.
    static func stagePoint(_ notch: CGPoint, zoom: Double) -> CGPoint {
        CGPoint(x: stageSize.width / 2 + (notch.x - windowSize.width / 2) * zoom, y: notch.y * zoom)
    }

    // MARK: 1. Hook

    /// The closed notch, deep zoom, doing nothing, with a slow push.
    static func hook(duration: Double = 3.0) -> Act {
        Act(name: "hook", duration: duration, cues: [
            .camera(at: 0, zoom: 4.0),
            .camera(at: 0, zoom: 4.5, over: duration, ease: .linear),
            .caption(at: 0.2, "Your MacBook's notch has been doing nothing.", for: duration - 0.4),
        ])
    }

    // MARK: 2. Reveal and track change

    /// Springs open to Home on glass with "Night Drive", the title card under it, then the track skips.
    static func reveal(duration: Double = 5.0) -> Act {
        let long = duration >= 5
        let move = long ? 1.1 : 0.8
        return Act(name: "reveal", duration: duration, cues: [
            .camera(at: 0, zoom: openZoom, over: move),
            .notch(at: 0, .view(.home)),
            .music(at: long ? 0.2 : 0.1, nightDrive),
            .notch(at: long ? 0.2 : 0.1, .open),
            .caption(at: long ? 1.0 : 0.7, "Your music, on real Liquid Glass.", for: long ? 3.3 : 1.7),
            .card(at: long ? 1.2 : 0.8, .title, for: long ? 2.0 : 1.0),
            // Skip: the artwork flips and the tint follows.
            .music(at: long ? 3.4 : 1.7, glassHours),
        ])
    }

    // MARK: 3. Volume HUD

    static func volume() -> Act {
        Act(name: "volume", duration: 3.0, cues: [
            .notch(at: 0, .close),
            .camera(at: 0.2, zoom: 2.8, over: 1.0),
            .caption(at: 0.9, "Volume and brightness, right where you look.", for: 1.9),
            .run(at: 1.1, "volume 40%") { _ in Seams.hud(.volume, 0.40) },
            .run(at: 1.5, "volume 55%") { _ in Seams.hud(.volume, 0.55) },
            .run(at: 1.9, "volume 70%") { _ in Seams.hud(.volume, 0.70) },
            // Gone, and faded, before the shelf opens, or it would ghost over the open header.
            .run(at: 2.5, "hud away") { _ in Seams.hideHUD() },
        ])
    }

    // MARK: 4. Shelf

    /// A drag arrives at the closed notch: it opens on the Shelf with its drop zone lit, and three files land.
    static func shelf() -> Act {
        let files = Seams.shelfFiles
        return Act(name: "shelf", duration: 3.5, cues: [
            .camera(at: 0, zoom: openZoom, over: 1.0),
            .notch(at: 0, .view(.shelf)),
            .run(at: 0.6, "drag in") { Seams.dragIn($0.vm) },
            .caption(at: 0.8, "Drop files in. Share them out.", for: 2.5),
            .run(at: 1.6, "drop 1") { Seams.drop($0.vm, files: [files[0]]) },
            .run(at: 2.0, "drop 2") { Seams.drop($0.vm, files: [files[1]]) },
            .run(at: 2.4, "drop 3") { Seams.drop($0.vm, files: [files[2]]) },
        ])
    }

    // MARK: 5. Stats

    static func stats() -> Act {
        Act(name: "stats", duration: 3.0, cues: [
            .notch(at: 0.3, .view(.performance)),
            .caption(at: 0.6, "Live system stats. Zero privileges.", for: 2.2),
        ])
    }

    // MARK: 6. Launcher

    /// ⌥Space, `t` `te` `tel`, Return. The notch closes without launching Telegram.
    static func launcher() -> Act {
        Act(name: "launcher", duration: 6.5, cues: [
            // Closed and still for a moment before the key, so the Stats tab has gone.
            .notch(at: 0, .close),
            // The launcher is tall: a little wider than the open notch's 80%, so the keycaps clear it.
            .camera(at: 0.1, zoom: 1.4, over: 0.9),
            .keys(at: 1.0, ["⌥", "Space"], for: 1.1, chord: true),
            .run(at: 1.2, "launcher key") { Seams.launcherKey($0.vm) },
            .caption(at: 1.8, "Type a few letters. Hit Return.", for: 3.9),
            .run(at: 2.5, "type t") { _ in Seams.type("t") },
            .keys(at: 2.5, ["T"], for: 0.4),
            .run(at: 2.9, "type e") { _ in Seams.type("e") },
            .keys(at: 2.9, ["T", "E"], for: 0.4),
            .run(at: 3.3, "type l") { _ in Seams.type("l") },
            .keys(at: 3.3, ["T", "E", "L"], for: 0.8),
            .keys(at: 4.3, ["⏎"], for: 0.8),
            // Return would launch Telegram; the film only closes the notch.
            .notch(at: 4.6, .close),
            .camera(at: 5.0, zoom: 3.5, over: 1.0),
        ])
    }

    // MARK: 7. Agents

    /// Where the waiting agent's row sits in the Inbox, in the notch's own coordinates.
    static let waitingRow = CGPoint(x: 300, y: 112)

    /// Times of the agents scene, in seconds from its start, for the full and the short cut.
    private struct AgentTimes {
        let push, startClaude, startCodex, caption1, bannerZoom, ask, caption2, bannerAway, countZoom: Double
        let inboxZoom, inbox, caption3, cursorIn, cursorMove, click, cursorOut: Double

        static let long = AgentTimes(push: 1.0, startClaude: 0.5, startCodex: 0.8, caption1: 1.0, bannerZoom: 4.3, ask: 5.0,
                                     caption2: 5.2, bannerAway: 7.2, countZoom: 7.2, inboxZoom: 8.6, inbox: 8.9, caption3: 9.6,
                                     cursorIn: 9.7, cursorMove: 9.8, click: 11.1, cursorOut: 12.0)
        static let short = AgentTimes(push: 0.7, startClaude: 0.3, startCodex: 0.5, caption1: 0.6, bannerZoom: 2.5, ask: 3.0,
                                      caption2: 3.2, bannerAway: 4.3, countZoom: 4.3, inboxZoom: 5.2, inbox: 5.4, caption3: 5.7,
                                      cursorIn: 5.8, cursorMove: 5.9, click: 6.8, cursorOut: 7.3)
    }

    static func agents(duration: Double = 13) -> Act {
        let t = duration >= 13 ? AgentTimes.long : AgentTimes.short
        let rowAt = stagePoint(waitingRow, zoom: openZoom)
        return Act(name: "agents", duration: duration, cues: [
            .notch(at: 0, .close),
            .camera(at: 0, zoom: 3.5, over: t.push),
            // Claude and Codex at work: both marks breathe, count 2.
            .agent(at: t.startClaude, session: "claude", .start),
            .agent(at: t.startClaude + 0.05, session: "claude", .prompt),
            .agent(at: t.startCodex, session: "codex", .start),
            .agent(at: t.startCodex + 0.05, session: "codex", .prompt),
            .agent(at: t.startCodex + 0.5, session: "claude", .tool("Edit")),
            .agent(at: t.startCodex + 0.9, session: "codex", .tool("Bash")),
            .caption(at: t.caption1, "Now it watches your AI agents.", for: t.bannerZoom - t.caption1 - 0.3),
            // Claude cannot go on without the user: the banner, then the amber "! 1" beside the 1 still working.
            .camera(at: t.bannerZoom, zoom: 1.85, over: 0.9),
            .agent(at: t.ask, session: "claude", .askPermission("Bash: npm test")),
            .caption(at: t.caption2, "It tells you when one needs you.", for: t.bannerAway - t.caption2 + 0.6),
            .run(at: t.bannerAway, "banner away") { _ in Seams.dismissBanner() },
            .camera(at: t.countZoom, zoom: 3.2, over: 0.8),
            // The notch opens on the Inbox: both agents, the waiting one marked.
            .camera(at: t.inboxZoom, zoom: openZoom, over: 0.9),
            .notch(at: t.inbox, .view(.inbox)),
            .notch(at: t.inbox, .open),
            .caption(at: t.caption3, "One click jumps back.", for: t.cursorOut - t.caption3 + 0.9),
            // The click is a picture of one: nothing is activated.
            .cursor(at: t.cursorIn, to: CGPoint(x: rowAt.x + 330, y: rowAt.y + 230)),
            .cursor(at: t.cursorMove, to: rowAt, over: t.click - t.cursorMove - 0.2),
            .click(at: t.click),
            .cursorOut(at: t.cursorOut),
        ])
    }

    // MARK: 8. Outro

    /// Claude is let through and goes back to work; the notch closes to the breathing marks, the
    /// camera eases out, and the card comes up.
    static func outro(duration: Double = 5.5) -> Act {
        let long = duration >= 5
        let easeAt = long ? 1.8 : 0.55
        let cardAt = long ? 2.4 : 0.95
        return Act(name: "outro", duration: duration, cues: [
            .agent(at: 0, session: "claude", .toolDone("Bash: npm test")),
            .notch(at: 0.2, .close),
            .camera(at: 0.2, zoom: 3.0, over: 1.0),
            .camera(at: easeAt, zoom: 1.9, over: 1.6),
            .scrim(at: easeAt, opacity: 0.55, over: 1.0),
            .card(at: cardAt, .outro, for: duration - cardAt),
        ])
    }
}
