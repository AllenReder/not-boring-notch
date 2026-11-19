//
//  ClosedNotchArbiterTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh.
//
// SOURCES: NotBoringNotch/Channel/Arbiter/ClosedNotchArbiter.swift NotBoringNotch/Channel/Protocol/ChannelNotification.swift
//
//  Helper names are prefixed (`checkArbiter*`) so they stay distinguishable from the
//  helpers in the other standalone runners in this folder.
//

import Foundation

func checkArbiter(_ actual: String, _ expected: String, _ message: String = "",
                  file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("❌ Assertion Failed: [\(actual)] != expected [\(expected)] - \(message) at \(file):\(line)")
        exit(1)
    }
}

@main
struct ClosedNotchArbiterTests {
    static func main() {
        testInterruptionsWinInOrder()
        testTheMusicAndTheFaceAsBefore()
        testAnExpansionKeepsResidentsAway()
        testFullscreenHidesResidents()
        print("✅ ClosedNotchArbiterTests: all passed")
    }

    static func show(_ content: ClosedNotchContent) -> String {
        switch content {
        case .hello: return "hello"
        case .batteryNotice: return "battery"
        case .inlineHUD: return "hud"
        case .banner(let n): return "banner:\(n.id)"
        case .residents(let p, let s): return "residents:" + ([p] + (s.map { [$0] } ?? [])).map(name).joined(separator: ",")
        case .face: return "face"
        case .nothing: return "nothing"
        }
    }

    static func name(_ r: NotchResident) -> String {
        switch r {
        case .music: return "music"
        }
    }

    static func resolve(_ s: ClosedNotchSituation) -> String { show(ClosedNotchArbiter.resolve(s)) }

    static func banner(_ id: String) -> ChannelNotification {
        ChannelNotification(id: id, source: nil, thread: nil, level: .active, icon: nil,
                            title: id, subtitle: nil, body: nil,
                            duration: ChannelNotification.defaultDuration, banner: .temporary,
                            sound: .none, open: nil, actions: [], deliveredAt: Date())
    }

    static var playing: ClosedNotchSituation {
        var s = ClosedNotchSituation()
        s.musicPresent = true
        s.playerIdle = false
        s.faceEnabled = true
        return s
    }

    // MARK: - What the notch does

    static func testInterruptionsWinInOrder() {
        var s = playing
        s.banner = banner("b")
        checkArbiter(resolve(s), "banner:b", "a banner interrupts every resident")
        s.inlineHUD = true
        checkArbiter(resolve(s), "hud", "a HUD goes ahead of a banner")
        s.batteryNotice = true
        checkArbiter(resolve(s), "battery", "the battery notice goes ahead of a HUD")
        s.helloRunning = true
        checkArbiter(resolve(s), "hello", "the hello animation goes ahead of everything")
    }

    static func testTheMusicAndTheFaceAsBefore() {
        checkArbiter(resolve(playing), "residents:music", "playing music")

        var idle = ClosedNotchSituation()
        idle.faceEnabled = true
        checkArbiter(resolve(idle), "face", "nothing playing, the face")
        idle.faceEnabled = false
        checkArbiter(resolve(idle), "nothing", "and without the face, nothing")

        var paused = playing
        paused.musicPresent = false
        checkArbiter(resolve(paused), "nothing",
                     "music not idle but its live activity off: neither the music nor the face")
    }

    static func testAnExpansionKeepsResidentsAway() {
        var s = playing
        s.otherExpansion = true
        checkArbiter(resolve(s), "nothing", "a download's expansion owns the notch while it lasts")

        var idle = ClosedNotchSituation()
        idle.faceEnabled = true
        idle.musicExpansion = true
        checkArbiter(resolve(idle), "nothing", "no face during any expansion")
    }

    static func testFullscreenHidesResidents() {
        var s = playing
        s.hideOnClosed = true
        checkArbiter(resolve(s), "nothing", "residents hide in fullscreen")
        s.banner = banner("t")
        checkArbiter(resolve(s), "banner:t", "a banner that got through its own filter still shows")
    }
}
