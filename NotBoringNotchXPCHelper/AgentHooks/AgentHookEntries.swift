//
//  AgentHookEntries.swift
//  NotBoringNotchXPCHelper
//
//  What we write into an agent's hooks file, how we tell an entry is ours, and the text edits
//  that add or remove exactly those entries. Entry ownership and the remove-then-append install
//  are ported from CodeStatus, Sources/CodeStatusCore/Installation/HookInstaller.swift (MIT).
//

import Foundation

/// Which hook events each agent registers (docs/design/agent-first.md, the adapter table) and
/// where its hooks file is.
struct AgentHookSpec {
    let target: AgentHookTarget
    let events: [String]
    /// Events whose entry carries `"matcher": "*"`. Claude Code reads a matcher on most events;
    /// UserPromptSubmit and Stop ignore it, so they get none.
    let matcherEvents: Set<String>

    /// The hook is on the agent's critical path and the script gives up after a second.
    /// Codex caps SessionEnd and Interrupt at 3.
    static let timeoutSeconds = 3

    static func of(_ target: AgentHookTarget) -> AgentHookSpec {
        switch target {
        case .claudeCode:
            let events = [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd",
            ]
            return AgentHookSpec(
                target: target, events: events,
                matcherEvents: Set(events).subtracting(["UserPromptSubmit", "Stop"]))
        case .codex:
            // No async: Codex 0.138 discards an async hook outright.
            return AgentHookSpec(
                target: target,
                events: [
                    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                    "Stop", "SessionEnd", "Interrupt",
                ],
                matcherEvents: [])
        }
    }

    func hooksFile(home: URL) -> URL {
        switch target {
        case .claudeCode: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        }
    }
}

/// What a text scan of a hooks file finds of ours.
struct AgentHookInspection: Equatable {
    /// Events with at least one entry of ours.
    var present: [String] = []
    /// Events with none, in a file that has entries of ours elsewhere.
    var missing: [String] = []
    /// Events whose entries of ours are not exactly one, as this version would write it.
    var edited: [String] = []
}

struct AgentHookEntries {
    let spec: AgentHookSpec
    let scriptURL: URL
    let filePath: String

    /// The command line of our entry. Claude Code runs it through a shell, Codex splits it on
    /// whitespace and ignores `args`, so the agent name travels as a trailing word and the path
    /// has to be free of anything either would read differently (`AgentHookInstaller.requireSafePath`).
    var command: String { "\(scriptURL.path) \(spec.target.rawValue)" }

    func entryJSON(for event: String) -> String {
        let matcher = spec.matcherEvents.contains(event) ? "\"matcher\":\"*\"," : ""
        return "{\(matcher)\"hooks\":[{\"type\":\"command\",\"command\":\(JSONSurgeon.quoted(command)),"
            + "\"timeout\":\(AgentHookSpec.timeoutSeconds)}]}"
    }

    // MARK: - Ownership

    /// Whether an element of an event's array was written by us: one of its commands runs our
    /// script, decided by resolving paths, never by substring, so a user hook whose command only
    /// mentions our name is left alone.
    func isOurEntry(_ elementText: String) -> Bool {
        guard let element = try? JSONSurgeon(elementText),
              let hooks = element.arrayElements(atPath: ["hooks"]) else { return false }
        return hooks.contains { hookText in
            guard let hook = try? JSONSurgeon(hookText), let command = hook.string(atPath: ["command"]) else {
                return false
            }
            return Self.runs(command, scriptURL)
        }
    }

    /// The program a command line starts: a quoted path up to its closing quote, otherwise the
    /// first word.
    static func program(of command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), let close = trimmed.dropFirst().firstIndex(of: "\"") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex) ..< close])
        }
        return String(trimmed.prefix { !$0.isWhitespace })
    }

    static func runs(_ command: String, _ script: URL) -> Bool {
        let program = program(of: command)
        guard program.hasPrefix("/") || program.hasPrefix("~") else { return false }
        return !paths(program).isDisjoint(with: paths(script.path))
    }

    /// Both the standardized and the symlink-resolved spelling of a path, because `/tmp/x` and
    /// `/private/tmp/x` are the same file on macOS.
    private static func paths(_ raw: String) -> Set<String> {
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
        return [url.path, realPath(of: url)]
    }

    /// Symlink resolution applied to the deepest ancestor that exists, with the rest appended,
    /// since the script itself may not exist yet.
    private static func realPath(of url: URL) -> String {
        var missing: [String] = []
        var current = url
        while true {
            if FileManager.default.fileExists(atPath: current.path) {
                var resolved = current.resolvingSymlinksInPath()
                for component in missing.reversed() { resolved.appendPathComponent(component) }
                return resolved.path
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return url.path }
            missing.append(current.lastPathComponent)
            current = parent
        }
    }

    // MARK: - Reading

    func inspect(_ text: String?) throws -> AgentHookInspection {
        let surgeon = try parse(text)
        var result = AgentHookInspection()
        for event in spec.events {
            let ours = (surgeon.arrayElements(atPath: ["hooks", event]) ?? []).filter(isOurEntry)
            if ours.isEmpty {
                result.missing.append(event)
                continue
            }
            result.present.append(event)
            if ours.count != 1 || Self.canonical(ours[0]) != Self.canonical(entryJSON(for: event)) {
                result.edited.append(event)
            }
        }
        if result.present.isEmpty { result.missing = [] }
        return result
    }

    /// Two spellings of one entry compare equal on this: whitespace and key order gone, every
    /// value as written. The entry in the file is rendered in the user's layout, so it is never
    /// byte-equal to `entryJSON`. `JSONSerialization` is safe here because nothing is written back.
    private static func canonical(_ text: String) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: - Editing

    /// The file's text with exactly one current entry of ours under each event.
    ///
    /// An event that already has exactly that is left untouched, so installing twice changes
    /// nothing, and the user's hooks that come after ours do not get reordered. Any other state
    /// of ours (an old entry, a duplicate, an edited one) is removed and one fresh entry is
    /// appended.
    func planInstall(_ original: String?) throws -> String {
        var surgeon = try parse(original)
        for event in spec.events {
            let expected = Self.canonical(entryJSON(for: event))
            let ours = (surgeon.arrayElements(atPath: ["hooks", event]) ?? []).filter(isOurEntry)
            if ours.count == 1, Self.canonical(ours[0]) == expected { continue }
            _ = try edit { try surgeon.removeFromArray(atPath: ["hooks", event], where: isOurEntry) }
            try edit { try surgeon.appendToArray(atPath: ["hooks", event], element: entryJSON(for: event)) }
        }
        var text = surgeon.text
        if surgeon.wasSynthesized, !text.hasSuffix("\n") { text += "\n" }
        return text
    }

    /// The file's text without our entries, and without the containers they leave empty. A
    /// container is removed only when this removal emptied it, so an empty list the user wrote
    /// stays.
    func planUninstall(_ original: String) throws -> String {
        var surgeon = try parse(original)
        var removedAny = false
        for event in spec.events {
            // A `hooks` of the wrong shape cannot hold anything of ours.
            let removed = (try? surgeon.removeFromArray(atPath: ["hooks", event], where: isOurEntry)) ?? 0
            guard removed > 0 else { continue }
            removedAny = true
            if surgeon.isEmptyContainer(atPath: ["hooks", event]) {
                try edit { _ = try surgeon.removeKey(atPath: ["hooks", event]) }
            }
        }
        if removedAny, surgeon.isEmptyContainer(atPath: ["hooks"]) {
            try edit { _ = try surgeon.removeKey(atPath: ["hooks"]) }
        }
        return surgeon.text
    }

    /// Why a written file is wrong for an install (`expectingOurs`) or an uninstall, if it is.
    func check(_ text: String, expectingOurs: Bool) -> String? {
        guard (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil else {
            return "the result is not valid JSON"
        }
        guard let surgeon = try? JSONSurgeon(text) else { return "the result can't be read back" }
        for event in spec.events {
            let count = (surgeon.arrayElements(atPath: ["hooks", event]) ?? []).filter(isOurEntry).count
            if expectingOurs, count != 1 { return "\(event) has \(count) entries of this app, expected 1" }
            if !expectingOurs, count != 0 { return "\(event) still has \(count) entries of this app" }
        }
        return nil
    }

    private func parse(_ text: String?) throws -> JSONSurgeon {
        try edit { try JSONSurgeon(text ?? "") }
    }

    /// Surgeon failures, as the errors a person reads.
    private func edit<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let failure as JSONSurgeon.Failure {
            switch failure {
            case .notAnObject, .notAnArray, .rootIsNotAnObject:
                throw AgentHookError.unexpectedShape(path: filePath)
            default:
                throw AgentHookError.notJSON(path: filePath)
            }
        }
    }
}
