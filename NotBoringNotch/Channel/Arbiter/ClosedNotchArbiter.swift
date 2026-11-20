//
//  ClosedNotchArbiter.swift
//  NotBoringNotch
//
//  Decides what the closed notch shows. Everything that wants the closed notch — the hello
//  animation, the battery notice, a HUD, a banner, the music, the face — asks here, and the
//  drawing and the width it claims both read the one answer, so the two cannot disagree.
//
//  Two kinds of claim, as on iOS's Dynamic Island:
//
//  - **Interruptions** last seconds and take the whole notch: the hello animation, the battery
//    notice, an inline HUD, a banner. The first one present wins, in that order.
//  - **Residents** stay for as long as they last: the music, and the agents. Two can be seen at
//    once — the first takes both wings (compact), the second shrinks to the right one (minimal).
//
//  Ranking the residents is one question: is anyone waiting on the user? If so, the agents go
//  first, always — an agent that cannot go on is worth more of a glance than the music, which
//  the user already knows is playing. If agents are only working, they go ahead of the music
//  unless the user has put the music first for good. The music comes forward for the seconds a
//  new track is announced.
//
//  Pure: no SwiftUI, no singletons, so it is tested on its own.
//

import Foundation

/// A claim that stays on the closed notch for as long as it lasts.
enum NotchResident: Hashable {
    case music
    /// The agent sessions working or waiting on the user.
    case agents
}

/// What the agents are up to, as far as the closed notch goes.
enum AgentPresence: Equatable {
    /// Nothing is working or waiting.
    case none
    case working
    /// Somebody cannot go on without the user.
    case waiting
}

/// What the closed notch shows.
enum ClosedNotchContent: Equatable {
    case hello
    case batteryNotice
    case inlineHUD
    case banner(ChannelNotification)
    /// `primary` takes both wings. `secondary`, when there is one, takes the right wing instead of
    /// the primary's own right side.
    case residents(primary: NotchResident, secondary: NotchResident?)
    case face
    case nothing

    var residents: [NotchResident] {
        guard case let .residents(primary, secondary) = self else { return [] }
        return [primary] + (secondary.map { [$0] } ?? [])
    }
}

/// Everything the closed notch's content depends on, gathered by the caller.
struct ClosedNotchSituation {
    var helloRunning = false
    /// The battery's own notice (plugged in, charged) is on screen and allowed.
    var batteryNotice = false
    /// A volume, brightness or similar HUD drawn inside the notch.
    var inlineHUD = false
    /// A banner that may be drawn now — already filtered for the screen and for fullscreen.
    var banner: ChannelNotification?

    /// One of the notch's system expansions other than the music's (a download, the battery) is
    /// on screen. It keeps the residents and the face away while it lasts.
    var otherExpansion = false
    /// The music's own expansion — a new track being announced in the inline style — is on screen.
    var musicExpansion = false
    /// A new track is being announced in the standard style, below the notch.
    var musicAnnounced = false

    /// Something is playing, or paused but not idle, and the music's live activity is turned on.
    var musicPresent = false
    /// Nothing is playing and the player is idle: the face's condition.
    var playerIdle = true
    var faceEnabled = false

    /// The notch hides its content while closed (fullscreen). Residents and the face go;
    /// interruptions have been filtered by their own rules already.
    var hideOnClosed = false

    var agents = AgentPresence.none
    /// The user has put the music ahead of agents that are only working.
    var musicFirst = false
}

enum ClosedNotchArbiter {
    static func resolve(_ s: ClosedNotchSituation) -> ClosedNotchContent {
        if s.helloRunning { return .hello }
        if s.batteryNotice { return .batteryNotice }
        if s.inlineHUD { return .inlineHUD }
        if let banner = s.banner { return .banner(banner) }

        let ranked = rankedResidents(s)
        if let primary = ranked.first {
            return .residents(primary: primary, secondary: ranked.dropFirst().first)
        }

        if s.faceEnabled && s.playerIdle && !s.otherExpansion && !s.musicExpansion && !s.hideOnClosed {
            return .face
        }
        return .nothing
    }

    /// Every resident that may be on the closed notch now, most deserving first.
    static func rankedResidents(_ s: ClosedNotchSituation) -> [NotchResident] {
        guard !s.hideOnClosed, !s.otherExpansion else { return [] }

        let musicComesForward = s.musicFirst || s.musicExpansion || s.musicAnnounced

        switch (s.agents, s.musicPresent) {
        case (.none, false): return []
        case (.none, true): return [.music]
        case (.waiting, false), (.working, false): return [.agents]
        case (.waiting, true): return [.agents, .music]
        case (.working, true): return musicComesForward ? [.music, .agents] : [.agents, .music]
        }
    }
}
