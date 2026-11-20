// Notch Studio: the real notch (ContentView and its Liquid Glass) on a stage window over a
// wallpaper, driven by a scripted timeline, so a screen recorder can capture what the window
// server draws. The driver (record.py) does the recording and the trim; see the README there.
//
// Launch sequence: warm-up, clapperboard (full-stage marker colour for a few frames), then the
// timeline clock starts at the marker's end. Stdout carries STAGE and PLAN lines for the driver.

import AppKit
import SwiftUI

@main
struct NotchStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

let stageSize = NSSize(width: 1280, height: 720)

private func env(_ key: String, _ fallback: Double) -> Double {
    Double(ProcessInfo.processInfo.environment[key] ?? "") ?? fallback
}

@MainActor final class StudioState: ObservableObject {
    let vm: NotchViewModel
    @Published var marker = false
    init(vm: NotchViewModel) { self.vm = vm }

    func flash() {
        marker = true
        Task { try? await Task.sleep(nanoseconds: UInt64(StudioDelegate.markerSeconds * 1e9)); marker = false }
    }
}

/// Keeps the notch out of the camera's per-frame re-evaluation: it never changes from outside.
private struct NotchHost: View, Equatable {
    let vm: NotchViewModel
    static func == (a: NotchHost, b: NotchHost) -> Bool { true }
    var body: some View {
        ContentView().environmentObject(vm).frame(width: windowSize.width, height: windowSize.height)
    }
}

/// Dims the desk, not the notch: it sits between them.
private struct ScrimLayer: View {
    let timeline: Timeline

    var body: some View {
        TimelineView(.animation) { _ in
            Color.black.opacity(timeline.scrim(at: StudioClock.shared.now))
                .frame(width: Wallpaper.size.width, height: Wallpaper.size.height)
                .frame(width: stageSize.width, height: stageSize.height, alignment: .top)
        }
    }
}

private struct StageView: View {
    let timeline: Timeline
    @ObservedObject var state: StudioState

    var body: some View {
        ZStack {
            CameraLayer(timeline: timeline) {
                ZStack(alignment: .top) {
                    // Larger than the stage so the camera can pull back; laid out as the stage's size.
                    Wallpaper().frame(width: stageSize.width, height: stageSize.height, alignment: .top)
                    MenuBar(height: state.vm.closedNotchSize.height)
                    ScrimLayer(timeline: timeline)
                    NotchHost(vm: state.vm).equatable()
                }
                .frame(width: stageSize.width, height: stageSize.height)
            }
            OverlayLayer(timeline: timeline)
            if state.marker { markerColor }
        }
        .frame(width: stageSize.width, height: stageSize.height)
        .clipped()
    }
}

/// Never key, and the app never activates (see `NoActivation`): the studio must not take the
/// keyboard from whoever is working while it records. The launcher's field is typed into
/// through its own field editor instead, see `Seams.type`.
final class StageWindow: NSWindow {}

final class StudioDelegate: NSObject, NSApplicationDelegate {
    static let markerSeconds = 0.2
    static let tailSeconds = 0.5
    var window: NSWindow!
    @MainActor static weak var stage: NSWindow?

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NoActivation.install()
        let launched = CACurrentMediaTime()
        let warmup = env("STUDIO_WARMUP", 2.5)
        let timeline = Scenes.named(ProcessInfo.processInfo.environment["STUDIO_TIMELINE"] ?? "demo")

        Seams.prepare()
        _ = MusicManager.shared  // starts its controller now, so it can be cut loose well before the warm-up ends

        // The built-in display: it has a real notch, and the main display is someone's desk.
        let screen = NSScreen.screens.first { CGDisplayIsBuiltin($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0) != 0 } ?? NSScreen.main!
        let origin = NSPoint(x: screen.frame.midX - stageSize.width / 2, y: screen.frame.midY - stageSize.height / 2)
        window = StageWindow(contentRect: NSRect(origin: origin, size: stageSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .floating
        window.ignoresMouseEvents = true  // a stray cursor must not hover the notch open

        let state = StudioState(vm: NotchViewModel(screenUUID: screen.displayUUID))
        window.contentView = NSHostingView(rootView: StageView(timeline: timeline, state: state))
        window.setFrame(NSRect(origin: origin, size: stageSize), display: true)
        window.orderFrontRegardless()
        Self.stage = window
        Hitches.watch()

        // The recorder's region, in screencapture's top-left points.
        let f = window.frame
        let primary = NSScreen.screens[0]
        print("STAGE \(Int(f.minX)),\(Int(primary.frame.maxY - f.maxY)),\(Int(f.width)),\(Int(f.height))")
        print("CUES \(timeline.reportJSON())")
        print("PLAN warmup=\(warmup) marker=\(Self.markerSeconds) duration=\(timeline.duration) tail=\(Self.tailSeconds) timeline=\(timeline.name)")
        fflush(stdout)

        Task { @MainActor in
            func sleep(until t: Double) async {
                let wait = t - (CACurrentMediaTime() - launched)
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            }
            // Pre-warm, off the record (everything before the clapperboard is trimmed): the shelf's
            // first open and first drag, and Home's first calendar, stall the main thread for 75–160 ms:
            // visible hitches mid-take.
            // Home is opened on the timeline's own first track (same artwork object, so it is
            // already decoded when the take opens it), and the shelf gets the same files the take
            // drops (their thumbnails are cached by path), then everything is put back.
            let firstTrack = timeline.cues.lazy.compactMap { cue -> Track? in
                if case let .music(_, track) = cue { return track } else { return nil }
            }.first
            await sleep(until: 0.3); if let firstTrack { Seams.music(firstTrack) }; state.vm.open()
            await sleep(until: 0.8); state.vm.coordinator.currentView = .shelf
            await sleep(until: 1.0); Seams.dragIn(state.vm)
            await sleep(until: 1.1); Seams.drop(state.vm, files: Seams.shelfFiles)
            await sleep(until: 1.4); Seams.launcherKey(state.vm)  // the launcher's first open loads apps and icons
            await sleep(until: 1.8); state.vm.close()
            ShelfStateViewModel.shared.items.forEach { ShelfStateViewModel.shared.remove($0) }
            state.vm.coordinator.currentView = .home
            Seams.detachRealMedia()
            await sleep(until: 1.9); Seams.detachRealMedia()
            Seams.music(nil)  // the hook's notch is idle
            await sleep(until: warmup)
            // Clapperboard: the marker's end is timeline zero.
            state.marker = true
            await sleep(until: warmup + Self.markerSeconds)
            StudioClock.shared.start()
            state.marker = false
            Task { await Runner.run(timeline, studio: state) }
            try? await Task.sleep(nanoseconds: UInt64((timeline.duration + Self.tailSeconds) * 1e9))
            NSApp.terminate(nil)
        }
    }
}

/// Logs every main-thread stall long enough to show as a stutter in the recording, with its
/// timeline time, so a take can be checked for hitches without watching it.
@MainActor enum Hitches {
    private static var last = CACurrentMediaTime()
    static func watch() {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                if now - last > 0.07, StudioClock.shared.now >= 0 {
                    StudioLog.log(String(format: "HITCH %.0f ms", (now - last) * 1000))
                }
                last = now
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

/// The studio never takes the keyboard from whoever is working while it records: the app's own
/// `NSApp.activate()` calls (the launcher makes them) do nothing here.
enum NoActivation {
    static func install() {
        let noop: @convention(block) (AnyObject) -> Void = { _ in }
        let noopFlag: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
        if let m = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.activate as (NSApplication) -> () -> Void)) {
            method_setImplementation(m, imp_implementationWithBlock(noop))
        }
        if let m = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.activate(ignoringOtherApps:))) {
            method_setImplementation(m, imp_implementationWithBlock(noopFlag))
        }
    }
}
