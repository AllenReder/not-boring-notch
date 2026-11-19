//
//  ClosedNotchArbiterTests.swift
//  Tests
//
//  Standalone runner, discovered by scripts/run-tests.sh.
//
// SOURCES: NotBoringNotch/Channel/Arbiter/ClosedNotchArbiter.swift NotBoringNotch/Channel/Protocol/ChannelNotification.swift NotBoringNotch/Channel/Agents/AgentSession.swift
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
        testAgentsWorkingGoAheadOfTheMusic()
        testAgentsWaitingAlwaysGoAheadOfTheMusic()
        testTheMusicComesForwardOnlyForAgentsThatAreWorking()
        testAgentsReplaceTheFaceAndFollowTheSameRulesAsTheMusic()
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
        case .agents: return "agents"
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

    // MARK: - Agents

    static func testAgentsWorkingGoAheadOfTheMusic() {
        var s = playing
        s.agents = .working
        checkArbiter(resolve(s), "residents:agents,music", "the agents take compact, the music minimal")

        var silent = ClosedNotchSituation()
        silent.faceEnabled = true
        silent.agents = .working
        checkArbiter(resolve(silent), "residents:agents", "agents instead of the face")
    }

    static func testAgentsWaitingAlwaysGoAheadOfTheMusic() {
        var s = playing
        s.agents = .waiting
        checkArbiter(resolve(s), "residents:agents,music", "somebody is waiting for the user")

        s.musicFirst = true
        checkArbiter(resolve(s), "residents:agents,music", "even when the music is first for good")
        s.musicFirst = false
        s.musicExpansion = true
        checkArbiter(resolve(s), "residents:agents,music", "even over a new track being announced")
        s.musicExpansion = false
        s.musicAnnounced = true
        checkArbiter(resolve(s), "residents:agents,music", "in either style")
    }

    static func testTheMusicComesForwardOnlyForAgentsThatAreWorking() {
        var s = playing
        s.agents = .working
        s.musicFirst = true
        checkArbiter(resolve(s), "residents:music,agents", "the user put the music first")

        s.musicFirst = false
        s.musicExpansion = true
        checkArbiter(resolve(s), "residents:music,agents", "a new track is announced in compact")
        s.musicExpansion = false
        s.musicAnnounced = true
        checkArbiter(resolve(s), "residents:music,agents", "and so is one announced in the standard style")

        var quiet = playing
        quiet.musicFirst = true
        checkArbiter(resolve(quiet), "residents:music", "with no agents at work it is the music alone")
    }

    static func testAgentsReplaceTheFaceAndFollowTheSameRulesAsTheMusic() {
        var s = playing
        s.agents = .waiting
        s.hideOnClosed = true
        checkArbiter(resolve(s), "nothing", "agents hide in fullscreen, as the music does")
        s.banner = banner("t")
        checkArbiter(resolve(s), "banner:t", "the banner announcing a wait still shows")

        var expansion = playing
        expansion.agents = .waiting
        expansion.otherExpansion = true
        checkArbiter(resolve(expansion), "nothing", "a download's expansion owns the notch while it lasts")
        checkArbiter(ClosedNotchArbiter.rankedResidents(playing).map(name).joined(separator: ","), "music",
                     "no agents, no agents resident")
    }
}
