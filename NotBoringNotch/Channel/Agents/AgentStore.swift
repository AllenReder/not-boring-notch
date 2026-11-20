//
//  AgentStore.swift
//  NotBoringNotch
//
//  The sessions the notch knows about, in the same style as `BannerQueue` and `NotificationInbox`:
//  a value, changed by `mutating` calls that take the time as an argument, so every rule is tested
//  without waiting for it.
//
//  Not kept across restarts. A session is a claim that something is running now; after a restart
//  that claim is unverified, and the next hook from the session brings it back.
//

import Foundation

struct AgentStore: Equatable {
    private(set) var sessions: [AgentSessionKey: AgentSession] = [:]
    /// T3 thread id -> its title, as T3 Code last gave it.
    private(set) var threadTitles: [String: String] = [:]
    /// T3 thread id -> when its title was last asked for.
    private var titlesAskedAt: [String: Date] = [:]

    /// How often the title of a thread in a turn is asked for again: T3 Code names a thread after
    /// its first message, and may rename it later.
    static let titleRefresh: TimeInterval = 30

    var isEmpty: Bool { sessions.isEmpty }

    /// Applies what a hook said, and returns what the rest of the app should do about it.
    @discardableResult
    mutating func apply(_ envelope: AgentEnvelope, now: Date) -> [AgentEffect] {
        var result = AgentReducer.reduce(sessions[envelope.key], envelope, now: now)
        if let thread = result.session?.t3ThreadID {
            result.session?.threadTitle = threadTitles[thread]
        }
        sessions[envelope.key] = result.session
        return result.effects
    }

    /// The T3 threads whose title should be asked for now: one never asked about, and one with a
    /// session in a turn that was last asked about a while ago. They count as asked from now.
    mutating func takeThreadsDueForTitles(now: Date) -> [String] {
        var due: Set<String> = []
        for session in sessions.values {
            guard let thread = session.t3ThreadID else { continue }
            if let asked = titlesAskedAt[thread] {
                guard session.phase != .idle, now.timeIntervalSince(asked) >= Self.titleRefresh else { continue }
            }
            due.insert(thread)
        }
        for thread in due { titlesAskedAt[thread] = now }
        return due.sorted()
    }

    mutating func setThreadTitles(_ titles: [String: String]) {
        threadTitles.merge(titles) { _, new in new }
        for (key, session) in sessions {
            guard let thread = session.t3ThreadID, let title = titles[thread] else { continue }
            sessions[key]?.threadTitle = title
        }
    }

    /// Takes away sessions whose process has gone, and settles working ones that have gone quiet.
    ///
    /// `alive` answers for the pids in `asked`: it maps each process that still exists to when it
    /// started; an asked pid that is absent has exited, and one that started at a different time
    /// has been reused. A session whose pid was not asked about (it arrived, or changed process,
    /// while the answer was on its way) is not judged by it. Nil means liveness cannot be known
    /// right now, in which case only the quiet-for-too-long rule applies.
    @discardableResult
    mutating func sweep(asked: [Int32], alive: [Int32: Date]?, now: Date) -> [AgentEffect] {
        var effects: [AgentEffect] = []
        let asked = Set(asked)

        for (key, var session) in sessions {
            let isAlive = Self.confirmAlive(&session, asked: asked, in: alive)
            if isAlive == false {
                sessions[key] = nil
                effects.append(.calmed(key))
                continue
            }
            sessions[key] = session

            // Working, silent for a quarter of an hour, and nothing says the process is still
            // there: it stopped without saying so. Quietly, because nothing happened that the user
            // needs to hear about.
            if isAlive != true, session.phase.isWorking,
               now.timeIntervalSince(session.updatedAt) >= AgentReducer.staleAfter {
                session.phase = .idle
                session.turnStartedAt = nil
                session.subagents = []
                sessions[key] = session
                effects.append(.calmed(key))
            }
        }
        return effects
    }

    /// Whether the session's process is there: true, false, or nil when it cannot be told. Learns
    /// the process's start time the first time it is seen.
    private static func confirmAlive(_ session: inout AgentSession, asked: Set<Int32>,
                                     in alive: [Int32: Date]?) -> Bool? {
        guard let alive, var process = session.process, asked.contains(process.pid) else { return nil }
        guard let startedAt = alive[process.pid] else { return false }

        if let known = process.startedAt {
            // Readings of the same start time can differ in the last bits.
            guard abs(known.timeIntervalSince(startedAt)) < 1 else { return false }
        } else {
            process.startedAt = startedAt
            session.process = process
        }
        return true
    }

    /// Every pid worth asking about.
    var pids: [Int32] {
        sessions.values.compactMap { $0.process?.pid }
    }

    /// For the Inbox: sessions that need the user first, then those at work, then the rest, each
    /// group newest first.
    var ordered: [AgentSession] {
        func rank(_ session: AgentSession) -> Int {
            switch session.phase {
            case .waiting: return 0
            case .working: return 1
            case .idle: return 2
            }
        }
        return sessions.values.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return a.key.raw < b.key.raw
        }
    }

    /// The one session per kind whose Inbox row holds the kind's mark, the one the closed notch's
    /// mark flies to: the first of its kind in `ordered`, which is the topmost active one.
    var markHolders: Set<AgentSessionKey> {
        var seen: Set<AgentKind> = []
        return Set(ordered.filter { seen.insert($0.agent).inserted }.map(\.key))
    }

    var summary: AgentSummary {
        var summary = AgentSummary()
        var perKind: [AgentKind: Int] = [:]
        for session in sessions.values {
            switch session.phase {
            case .idle: continue
            case .working: summary.working += 1
            case .waiting: summary.waiting += 1
            }
            perKind[session.agent, default: 0] += 1
        }
        summary.kinds = AgentKind.allCases.filter { perKind[$0] != nil }
        // `max(by:)` keeps the first of equals.
        summary.leadKind = summary.kinds.max { perKind[$0]! < perKind[$1]! }
        return summary
    }
}
