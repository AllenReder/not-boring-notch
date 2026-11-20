// The studio's hands on the app: small helpers that put placeholder data where the real
// controllers would, so a scene can say "music starts" or "an agent is working" in one line.
// Nothing here edits the app; it only calls what the app already exposes.

import AppKit
import Defaults
import SwiftUI

struct Track {
    let title: String
    let artist: String
    let artwork: NSImage
    let playing: Bool
    let duration: TimeInterval
    let elapsed: TimeInterval
    /// Stands in for the colour the app would derive from the artwork.
    let tint: NSColor
}

struct Banner {
    let title: String
    var subtitle: String? = nil
    var body: String? = nil
    var symbol = "bell.fill"
    /// Seconds the banner stays up.
    var duration = 4.0
}

/// A step in an agent's session, in the app's own event vocabulary.
enum AgentBeat {
    case start, prompt, tool(String), toolDone(String), askPermission(String), finish(String? = nil), end
}

/// A placeholder agent session: who it is, where it "runs", and what T3 Code "calls" its thread.
struct AgentSpec {
    let kind: AgentKind
    let cwd: String
    let threadID: String
    let threadTitle: String
    /// How long the turn has "been running" when the prompt arrives, so the Inbox's timer starts mid-flight.
    let ranFor: TimeInterval

    static let fallback = AgentSpec(kind: .claudeCode, cwd: "/Users/demo/atlas", threadID: "demo-thread-atlas", threadTitle: "Atlas", ranFor: 0)
}

@MainActor enum Seams {
    // MARK: Setup

    /// Placeholder sessions by the name a scene gives them. Neither paths nor titles are real.
    static let cast: [String: AgentSpec] = [
        "claude": AgentSpec(kind: .claudeCode, cwd: "/Users/demo/web-app", threadID: "demo-thread-claude",
                            threadTitle: "Fix login redirect", ranFor: 192),
        "codex": AgentSpec(kind: .codex, cwd: "/Users/demo/dashboard", threadID: "demo-thread-codex",
                           threadTitle: "Dark mode for settings", ranFor: 65),
    ]

    /// Real files in the studio's isolated home, for the Shelf.
    static let shelfFiles: [URL] = PlaceholderFiles.make()

    static let launcherRecents = ["com.mitchellh.ghostty", "com.apple.Safari", "ru.keepcoder.Telegram",
                                  "com.apple.dt.Xcode", "dev.zed.Zed"]

    /// Makes the app behave like a finished install on a quiet machine, and keeps the studio's
    /// side effects off the user's real data. Called once, before the stage is built.
    static func prepare() {
        // Not the first launch: skip the hello and onboarding a new user would see.
        UserDefaults.standard.set(false, forKey: "firstLaunch")
        // The stage is not on the display the app would pick.
        Defaults[.showOnAllDisplays] = true
        // Home shows the calendar, on placeholder events (see StageCalendar).
        StageCalendar.install()
        Defaults[.showCalendar] = true
        // `deliver` saves the Inbox to Application Support unless history is off. The driver also
        // points CFFIXED_USER_HOME at a scratch directory, so this is the second lock.
        Defaults[.notchChannelKeepsHistory] = false
        Defaults[.notchChannelEnabled] = false
        // Nothing may open, close or announce itself except the timeline.
        Defaults[.openNotchOnHover] = false
        Defaults[.showPowerStatusNotifications] = false
        // The header's battery is this Mac's real one.
        Defaults[.showBatteryIndicator] = false
        // The Stats tab, and the HUD drawn inside the notch rather than under it.
        Defaults[.performanceTabEnabled] = true
        Defaults[.inlineHUD] = true
        // Before anything touches `LauncherRecents`, which reads this once.
        Defaults[.launcherRecents] = launcherRecents
        // The launcher shows the few apps the film names, not everything installed here.
        StageApps.install()
        _ = shelfFiles
        // T3 Code is not running: the Inbox's thread titles come from here.
        NotchChannel.shared.t3ThreadTitles = { ids in
            Dictionary(uniqueKeysWithValues: cast.values.filter { ids.contains($0.threadID) }.map { ($0.threadID, $0.threadTitle) })
        }
        // The stats sparklines should already have a history when the tab opens.
        SystemMetricsMonitor.shared.start(subscriber: UUID(), interval: 1)
    }

    /// Cuts the real media controller loose, so it cannot overwrite what scenes set. The controller
    /// is created asynchronously after launch, and a track it saw leaves a one-second artwork
    /// fallback running that no `destroy()` cancels, so this runs early and the first music cue
    /// must come after the warm-up.
    static func detachRealMedia() {
        MusicManager.shared.destroy()
    }

    // MARK: Notch

    static func notch(_ command: NotchCommand, _ vm: NotchViewModel) {
        switch command {
        case .open: vm.open()
        case .close: vm.close()
        case let .view(view): withAnimation(.smooth) { NotchViewCoordinator.shared.currentView = view }
        }
    }

    // MARK: Music

    /// `nil` clears the player, as when nothing is playing.
    static func music(_ track: Track?) {
        let m = MusicManager.shared
        guard let track else {
            withAnimation(.smooth) {
                m.isPlaying = false
                m.isPlayerIdle = true
            }
            return
        }
        // Animated, as the app animates a new cover: the artwork cross-fades and the tint follows.
        withAnimation(.smooth) {
            m.songTitle = track.title
            m.artistName = track.artist
            m.album = track.title
            m.usingAppIconForArtwork = false
            m.albumArt = track.artwork
            m.avgColor = track.tint
            m.songDuration = track.duration
            m.elapsedTime = track.elapsed
            m.timestampDate = Date()
            m.playbackRate = 1
            m.isPlaying = track.playing
            m.isPlayerIdle = !track.playing
        }
    }

    // MARK: HUD

    /// A volume or brightness HUD at `value`. `toggleSneakPeek` only draws it when the user has
    /// turned on HUD replacement, which asks for Accessibility; the studio sets the same state
    /// directly instead.
    static func hud(_ type: SneakContentType, _ value: CGFloat) {
        withAnimation(.smooth) {
            NotchViewCoordinator.shared.sneakPeek = sneakPeek(show: true, type: type, value: value, icon: "")
        }
    }

    static func hideHUD() {
        withAnimation(.smooth) { NotchViewCoordinator.shared.sneakPeek.show = false }
    }

    // MARK: Shelf

    /// A file dragged toward the closed notch: the notch opens on the Shelf with its drop zone lit.
    static func dragIn(_ vm: NotchViewModel) {
        vm.dragDetectorTargeting = true
    }

    /// The drop: the files land on the shelf, and the notch stays open (`dropEvent` is what tells
    /// it the drag ended in a drop and not in leaving).
    static func drop(_ vm: NotchViewModel, files: [URL]) {
        vm.dropEvent = true
        vm.dragDetectorTargeting = false
        ShelfStateViewModel.shared.add(files.compactMap { url in
            (try? Bookmark(url: url)).map { ShelfItem(kind: .file(bookmark: $0.data)) }
        })
    }

    // MARK: Launcher

    /// The launcher's key: opens the tab, and takes keyboard focus the way it does for a user.
    static func launcherKey(_ vm: NotchViewModel) {
        Defaults[.launcherRecents] = launcherRecents
        vm.toggleLauncher()
    }

    /// Types into the search field the way a keyboard would, through its field editor, without the
    /// stage ever becoming key: the field is made first responder of the stage window directly.
    static func type(_ text: String) {
        guard let window = StudioDelegate.stage, let content = window.contentView else { return }
        if !(window.firstResponder is NSTextView), let field = editableField(in: content) {
            window.makeFirstResponder(field)
        }
        guard let editor = window.firstResponder as? NSTextView else {
            StudioLog.log("type \(text): no field editor")
            return
        }
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    private static func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let found = editableField(in: sub) { return found } }
        return nil
    }

    // MARK: Channel

    /// The banner has had its turn: the closed notch goes back to the agents' counts.
    static func dismissBanner() {
        NotchChannel.shared.dismissVisibleBanner()
    }

    static func banner(_ b: Banner) {
        var json: [String: Any] = [
            "source": "studio",
            "icon": ["kind": "sf_symbol", "value": b.symbol],
            "title": b.title,
            "duration": b.duration,
        ]
        json["subtitle"] = b.subtitle
        json["body"] = b.body
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let n = try? ChannelNotification.decode(data) else {
            fatalError("studio banner did not decode: \(b)")
        }
        NotchChannel.shared.deliver(n)
    }

    /// An agent session in a placeholder project. `session` names it (see `cast`), so a scene can run several.
    static func agent(_ session: String, _ beat: AgentBeat) {
        let spec = cast[session] ?? .fallback
        let event: AgentEvent
        switch beat {
        case .start: event = .sessionStarted
        case .prompt: event = .promptSubmitted
        case let .tool(name): event = .toolStarted(name: name, asksUser: false)
        case let .toolDone(name): event = .toolFinished(name: name)
        case let .askPermission(tool): event = .permissionRequested(tool: tool, asksUser: false)
        case let .finish(summary): event = .turnEnded(summary: summary, failed: false)
        case .end: event = .sessionEnded
        }
        // The prompt arrives `ranFor` seconds "ago", so the turn's timer in the Inbox is already running.
        let now = Date().addingTimeInterval(beat.isPrompt ? -spec.ranFor : 0)
        NotchChannel.shared.handle(AgentEnvelope(
            agent: spec.kind, sessionID: session, subagentID: nil, event: event,
            cwd: spec.cwd, host: .t3Code(threadID: spec.threadID, environmentID: "demo-env"), pid: nil), now: now)
    }
}

private extension AgentBeat {
    var isPrompt: Bool { if case .prompt = self { return true } else { return false } }
}

// MARK: - Log

/// Lines for STUDIO_LOG, stamped with timeline time.
@MainActor enum StudioLog {
    private static var logURL: URL? = ProcessInfo.processInfo.environment["STUDIO_LOG"].map(URL.init(fileURLWithPath:))

    static func log(_ line: String) {
        guard let logURL else { return }
        let text = String(format: "%.2f ", StudioClock.shared.now) + line + "\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? Data(text.utf8).write(to: logURL)
        }
    }
}

// MARK: - Placeholder artwork

extension Track {
    /// A generated cover: a gradient and a few big shapes, so it reads as artwork at 300pt and at 30pt.
    /// `variant` changes the drawing, not only the colours, so a track change shows a different cover.
    @MainActor static func placeholder(_ title: String, _ artist: String, hue: Double, variant: Int = 0, playing: Bool = true) -> Track {
        let a = Color(hue: hue, saturation: 0.85, brightness: 0.95)
        let b = Color(hue: (hue + (variant == 0 ? 0.18 : -0.12) + 1).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 0.55)
        let cover = ZStack {
            LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
            if variant == 0 {
                Circle().fill(.white.opacity(0.9)).frame(width: 120).offset(x: 50, y: -50)
                Circle().stroke(.white.opacity(0.5), lineWidth: 6).frame(width: 220).offset(x: 50, y: -50)
                Rectangle().fill(.black.opacity(0.35)).frame(height: 90).offset(y: 105)
            } else {
                // Rising sun over stripes.
                VStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        Rectangle().fill(.black.opacity(0.18 + 0.05 * Double(i))).frame(height: 8 + CGFloat(i) * 3)
                    }
                }.frame(height: 150).offset(y: 80)
                Circle().fill(.white.opacity(0.92)).frame(width: 150).offset(x: -40, y: -20)
                Rectangle().fill(.white.opacity(0.4)).frame(width: 8, height: 300).rotationEffect(.degrees(35)).offset(x: 70)
            }
        }.frame(width: 300, height: 300).clipped()
        let renderer = ImageRenderer(content: cover)
        renderer.scale = 2
        return Track(title: title, artist: artist, artwork: renderer.nsImage ?? NSImage(),
                     playing: playing, duration: 214, elapsed: 62,
                     tint: NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1))
    }
}

// MARK: - Placeholder files

enum PlaceholderFiles {
    /// Three real files in the studio's isolated home, so the Shelf draws real thumbnails.
    @MainActor static func make() -> [URL] {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Launch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdf = dir.appendingPathComponent("Launch-Plan.pdf")
        let png = dir.appendingPathComponent("hero.png")
        let md = dir.appendingPathComponent("notes.md")
        try? plan().write(to: pdf)
        try? hero().write(to: png)
        try? Data("# Launch notes\n\n- Draft the announcement\n- Record the demo\n- Ship it\n".utf8).write(to: md)
        return [pdf, png, md]
    }

    /// A one-page PDF: a heading and a few lines, enough for a page thumbnail.
    private static func plan() -> Data {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSColor.white.setFill(); box.fill()
        NSColor(hue: 0.62, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
        CGRect(x: 48, y: 690, width: 516, height: 6).fill()
        ("Launch Plan" as NSString).draw(at: NSPoint(x: 48, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor.black])
        for i in 0..<9 {
            NSColor(white: 0.82, alpha: 1).setFill()
            CGRect(x: 48, y: 640 - CGFloat(i) * 34, width: i % 3 == 2 ? 300 : 516, height: 12).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    @MainActor private static func hero() -> Data {
        let image = ZStack {
            LinearGradient(colors: [Color(hue: 0.85, saturation: 0.7, brightness: 0.95), Color(hue: 0.6, saturation: 0.8, brightness: 0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.85)).frame(width: 200).offset(x: -60, y: -30)
            Rectangle().fill(.black.opacity(0.3)).frame(height: 120).offset(y: 140)
        }.frame(width: 640, height: 400)
        let renderer = ImageRenderer(content: image)
        renderer.scale = 1
        guard let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
