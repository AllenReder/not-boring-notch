// A scene is data: a duration and a list of cues, each at a time in seconds from the clapperboard
// (timeline t=0). Camera, caption, keycap, cursor, card and scrim cues are pure functions of time,
// read by the views every frame. The rest are actions the runner fires once, when their time comes.
//
// A whole film is a `Timeline` built from `Act`s: each scene has cues relative to its own start,
// and `Timeline.sequence` lays them end to end.

import AppKit
import QuartzCore

enum Ease {
    case linear, inOut, out

    func apply(_ p: Double) -> Double {
        switch self {
        case .linear: return p
        case .inOut: return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
        case .out: return 1 - pow(1 - p, 3)
        }
    }
}

enum NotchCommand {
    case open, close
    case view(NotchViews)
}

/// A full-stage card drawn above the camera.
enum Card {
    /// App icon and name, under the open notch.
    case title
    /// Icon, name, install command and footer, each fading in after the one before.
    case outro
}

enum Cue {
    /// From `at`, move the camera to `zoom` (and `pan`, in stage points) over `over` seconds.
    case camera(at: Double, zoom: Double, pan: CGSize = .zero, over: Double = 0, ease: Ease = .inOut)
    case caption(at: Double, String, for: Double)
    /// Keycaps on screen for `for` seconds. The last key is the one just pressed, or all of them for a chord.
    case keys(at: Double, [String], for: Double, chord: Bool = false)
    /// The fake pointer moves to `to` (stage points) over `over` seconds. The first one after it
    /// was hidden puts it there at once.
    case cursor(at: Double, to: CGPoint, over: Double = 0, ease: Ease = .inOut)
    case cursorOut(at: Double)
    /// A click ripple where the pointer is.
    case click(at: Double)
    case card(at: Double, Card, for: Double)
    /// Dims the desk (not the notch) to `opacity` of black over `over` seconds.
    case scrim(at: Double, opacity: Double, over: Double = 0)
    case notch(at: Double, NotchCommand)
    case music(at: Double, Track?)
    case banner(at: Double, Banner)
    case agent(at: Double, session: String, AgentBeat)
    /// Escape hatch for anything a scene needs that has no cue of its own. The label names it in the cue report.
    case run(at: Double, String, @MainActor (StudioState) -> Void)
    /// Fills the whole stage with the marker colour: only used to measure the sync, see `Scenes.syncTest`.
    case flash(at: Double)

    var at: Double {
        switch self {
        case let .camera(at, _, _, _, _), let .caption(at, _, _), let .keys(at, _, _, _), let .cursor(at, _, _, _),
             let .cursorOut(at), let .click(at), let .card(at, _, _), let .scrim(at, _, _), let .notch(at, _),
             let .music(at, _), let .banner(at, _), let .agent(at, _, _), let .run(at, _, _), let .flash(at):
            return at
        }
    }

    /// The same cue moved to `at * scale + offset`, with its own lengths scaled too.
    func moved(by offset: Double, scale k: Double = 1) -> Cue {
        func t(_ x: Double) -> Double { x * k + offset }
        switch self {
        case let .camera(at, zoom, pan, over, ease): return .camera(at: t(at), zoom: zoom, pan: pan, over: over * k, ease: ease)
        case let .caption(at, text, length): return .caption(at: t(at), text, for: length * k)
        case let .keys(at, keys, length, chord): return .keys(at: t(at), keys, for: length * k, chord: chord)
        case let .cursor(at, to, over, ease): return .cursor(at: t(at), to: to, over: over * k, ease: ease)
        case let .cursorOut(at): return .cursorOut(at: t(at))
        case let .click(at): return .click(at: t(at))
        case let .card(at, card, length): return .card(at: t(at), card, for: length * k)
        case let .scrim(at, opacity, over): return .scrim(at: t(at), opacity: opacity, over: over * k)
        case let .notch(at, command): return .notch(at: t(at), command)
        case let .music(at, track): return .music(at: t(at), track)
        case let .banner(at, banner): return .banner(at: t(at), banner)
        case let .agent(at, session, beat): return .agent(at: t(at), session: session, beat)
        case let .run(at, label, action): return .run(at: t(at), label, action)
        case let .flash(at): return .flash(at: t(at))
        }
    }
}

/// One part of the film: a duration and cues from its own start. A cue may sit before 0 to lead
/// in from the previous scene (a camera move that starts early), but never before the film.
struct Act {
    let name: String
    let duration: Double
    let cues: [Cue]

    /// The scene stretched or squeezed to `length` seconds: every cue time and length scales with it.
    func scaled(to length: Double) -> Act {
        let k = length / duration
        return Act(name: name, duration: length, cues: cues.map { $0.moved(by: 0, scale: k) })
    }
}

struct SceneMark {
    let name: String
    let start: Double
    let end: Double
}

struct Timeline {
    let name: String
    let duration: Double
    /// In time order; cues at the same time keep the order they were written in.
    let cues: [Cue]
    let marks: [SceneMark]

    init(name: String, duration: Double, cues: [Cue], marks: [SceneMark] = []) {
        self.name = name
        self.duration = duration
        self.cues = cues.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        self.marks = marks
    }

    /// Scenes laid end to end.
    static func sequence(_ name: String, _ scenes: [Act]) -> Timeline {
        var start = 0.0
        var cues: [Cue] = []
        var marks: [SceneMark] = []
        for scene in scenes {
            cues += scene.cues.map { $0.moved(by: start) }
            marks.append(SceneMark(name: scene.name, start: start, end: start + scene.duration))
            start += scene.duration
        }
        return Timeline(name: name, duration: start, cues: cues, marks: marks)
    }

    // MARK: Camera

    struct CameraState { var zoom = 1.0; var pan = CGSize.zero }

    /// The camera at `t`: the last camera cue started, eased from where the one before it ended.
    func camera(at t: Double) -> CameraState {
        var from = CameraState()
        for cue in cues {
            guard case let .camera(start, zoom, pan, over, ease) = cue, start <= t else { continue }
            let to = CameraState(zoom: zoom, pan: pan)
            if over <= 0 || t >= start + over { from = to; continue }
            let p = ease.apply((t - start) / over)
            return CameraState(zoom: from.zoom + (to.zoom - from.zoom) * p,
                               pan: CGSize(width: from.pan.width + (to.pan.width - from.pan.width) * p,
                                           height: from.pan.height + (to.pan.height - from.pan.height) * p))
        }
        return from
    }

    // MARK: Captions

    static let captionFade = 0.3

    /// The caption showing at `t` and its opacity, fading in and out at its edges.
    func caption(at t: Double) -> (text: String, opacity: Double)? {
        for cue in cues {
            guard case let .caption(start, text, length) = cue, t >= start, t <= start + length else { continue }
            let opacity = min((t - start) / Self.captionFade, (start + length - t) / Self.captionFade, 1)
            return (text, max(opacity, 0))
        }
        return nil
    }

    // MARK: Keycaps

    struct KeysState {
        let keys: [String]
        /// How many of the trailing keys were just pressed.
        let pressed: Int
        /// Seconds since the press.
        let age: Double
        let opacity: Double
    }

    /// The keycaps showing at `t`: the latest cue started and not yet over.
    func keys(at t: Double) -> KeysState? {
        var found: KeysState?
        for cue in cues {
            guard case let .keys(start, keys, length, chord) = cue, t >= start, t <= start + length else { continue }
            let opacity = min((t - start) / 0.12, (start + length - t) / 0.18, 1)
            found = KeysState(keys: keys, pressed: chord ? keys.count : 1, age: t - start, opacity: max(opacity, 0))
        }
        return found
    }

    // MARK: Cursor

    struct CursorState {
        let position: CGPoint
        let opacity: Double
        /// 1 at rest, dipping to 0.88 for the moment of a click.
        let press: Double
    }

    static let clickLength = 0.5

    /// The fake pointer at `t`, in stage points.
    func cursor(at t: Double) -> CursorState? {
        // The move in flight (or finished): from, to, when it began, how long, how eased.
        var from = CGPoint.zero, to = CGPoint.zero
        var began = 0.0, length = 0.0, ease = Ease.inOut
        var shownAt: Double?, hiddenAt: Double?
        func place(_ time: Double) -> CGPoint {
            guard length > 0, time < began + length else { return to }
            let p = ease.apply(max(time - began, 0) / length)
            return CGPoint(x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p)
        }
        for cue in cues {
            switch cue {
            case let .cursor(start, target, over, easing) where start <= t:
                if shownAt == nil || hiddenAt != nil {
                    shownAt = start; hiddenAt = nil
                    from = target; to = target; began = start; length = 0
                } else {
                    from = place(start); to = target; began = start; length = over; ease = easing
                }
            case let .cursorOut(start) where start <= t:
                hiddenAt = start
            default: break
            }
        }
        guard let shownAt else { return nil }
        var opacity = min((t - shownAt) / 0.2, 1)
        if let hiddenAt { opacity = min(opacity, 1 - (t - hiddenAt) / 0.25) }
        guard opacity > 0 else { return nil }
        var press = 1.0
        for cue in cues {
            if case let .click(at) = cue, t >= at - 0.06, t <= at + 0.14 { press = 0.86 }
        }
        return CursorState(position: place(t), opacity: opacity, press: press)
    }

    /// Click ripples alive at `t`: where, and how far along (0...1).
    func ripples(at t: Double) -> [(position: CGPoint, progress: Double)] {
        cues.compactMap { cue in
            guard case let .click(at) = cue, t >= at, t <= at + Self.clickLength, let c = cursor(at: at) else { return nil }
            return (c.position, (t - at) / Self.clickLength)
        }
    }

    // MARK: Cards and scrim

    /// The card showing at `t`: which, and seconds since it came up.
    func card(at t: Double) -> (card: Card, age: Double, remaining: Double)? {
        for cue in cues {
            guard case let .card(start, card, length) = cue, t >= start, t <= start + length else { continue }
            return (card, t - start, start + length - t)
        }
        return nil
    }

    /// The scrim over the desk at `t`, as the opacity of black.
    func scrim(at t: Double) -> Double {
        var value = 0.0
        for cue in cues {
            guard case let .scrim(start, opacity, over) = cue, start <= t else { continue }
            if over <= 0 || t >= start + over { value = opacity; continue }
            return value + (opacity - value) * Ease.inOut.apply((t - start) / over)
        }
        return value
    }

    // MARK: Report

    /// What happens when, for whoever cuts music and sound to the picture. One line of JSON.
    func reportJSON() -> String {
        func r(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
        var events: [[String: Any]] = []
        func add(_ at: Double, _ kind: String, _ label: String, length: Double? = nil) {
            var e: [String: Any] = ["t": r(at), "kind": kind, "label": label]
            if let length { e["for"] = r(length) }
            events.append(e)
        }
        for cue in cues {
            switch cue {
            case let .caption(at, text, length): add(at, "caption", text, length: length)
            case let .keys(at, keys, length, _): add(at, "keys", keys.joined(separator: " "), length: length)
            case let .click(at): add(at, "click", "")
            case let .card(at, card, length): add(at, "card", "\(card)", length: length)
            case let .notch(at, command):
                switch command {
                case .open: add(at, "notch", "open")
                case .close: add(at, "notch", "close")
                case let .view(view): add(at, "view", "\(view)")
                }
            case let .music(at, track): add(at, "music", track?.title ?? "none")
            case let .banner(at, banner): add(at, "banner", banner.title)
            case let .agent(at, session, beat): add(at, "agent", "\(session) \(beat)")
            case let .run(at, label, _) where !label.isEmpty: add(at, "action", label)
            case let .camera(at, zoom, _, over, _): add(at, "camera", "zoom \(zoom)", length: over)
            default: break
            }
        }
        let scenes = marks.map { ["name": $0.name, "start": r($0.start), "end": r($0.end)] as [String: Any] }
        let report: [String: Any] = ["timeline": name, "duration": r(duration), "scenes": scenes, "events": events]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

/// Timeline seconds. Zero is the end of the clapperboard; `now` is negative until then.
@MainActor final class StudioClock {
    static let shared = StudioClock()
    private(set) var origin: CFTimeInterval?
    var now: Double { origin.map { CACurrentMediaTime() - $0 } ?? -1 }
    func start() { origin = CACurrentMediaTime() }
}

/// Fires the action cues at their times. The rest have no action: the views read them.
@MainActor enum Runner {
    static func run(_ timeline: Timeline, studio: StudioState) async {
        for cue in timeline.cues {
            let wait = cue.at - StudioClock.shared.now
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            switch cue {
            case let .notch(_, command): Seams.notch(command, studio.vm)
            case let .music(_, track): Seams.music(track)
            case let .banner(_, banner): Seams.banner(banner)
            case let .agent(_, session, beat): Seams.agent(session, beat)
            case let .run(_, _, action): action(studio)
            case .flash: studio.flash()
            case .camera, .caption, .keys, .cursor, .cursorOut, .click, .card, .scrim: break
            }
        }
    }
}
