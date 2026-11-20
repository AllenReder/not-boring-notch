//
//  AgentHookInstaller.swift
//  NotBoringNotchXPCHelper
//
//  Installs, repairs, checks and removes the hooks that report an agent's sessions to the notch.
//  Everything is relative to the `home` it is given, so tests run against a temporary one. The
//  sandboxed app cannot do any of this, which is why it lives in the helper.
//
//  Claude Code and Codex get entries in their hooks file that run `notch-agent-hook`. pi and
//  OpenCode get a file of their own instead (`AgentPluginFile`), in the folder they load plugins from.
//
//  The rules, which the tests prove:
//   - Only entries of ours are ever added, replaced or removed (ownership is by resolved script
//     path). Every other byte of the user's file stays as it was. A plugin file is ours by its
//     version marker; a file of that name without one is the user's, and is left alone.
//   - Nothing is written unless the user asked to install, or already had us installed.
//   - A file that can't be parsed, or has an unexpected shape, is refused, not rewritten.
//

import Foundation

struct AgentHookInstaller {
    let home: URL

    private var supportDirectory: URL { home.appendingPathComponent(".not-boring-notch") }
    private var backupsDirectory: URL { supportDirectory.appendingPathComponent("backups") }

    /// Absolute, and without a space: Codex splits a hook's command on whitespace.
    var scriptURL: URL { supportDirectory.appendingPathComponent("bin/notch-agent-hook") }

    private static let versionMarker = "# notch-agent-hook-version: "

    /// The number in a script's version marker, within its first lines.
    static func version(of script: String) -> Int? {
        for line in script.split(separator: "\n", maxSplits: 5, omittingEmptySubsequences: false).prefix(5)
        where line.hasPrefix(versionMarker) {
            return Int(line.dropFirst(versionMarker.count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: - Status

    func report(bundledScript: String) -> AgentHooksReport {
        AgentHooksReport(statuses: AgentHookTarget.allCases.map { status(of: $0, bundledScript: bundledScript) })
    }

    func status(of target: AgentHookTarget, bundledScript: String) -> AgentHookStatus {
        do {
            return try inspectStatus(of: target, bundledScript: bundledScript)
        } catch {
            // Nothing of ours can be told from a file that can't be read.
            return AgentHookStatus(agent: target, state: .notInstalled, problem: error.localizedDescription)
        }
    }

    private func inspectStatus(of target: AgentHookTarget, bundledScript: String) throws -> AgentHookStatus {
        if let plugin = AgentPluginFile.of(target) { return try pluginStatus(of: target, plugin) }
        let entries = self.entries(for: target)
        let inspection = try entries.inspect(configFile(for: target).read())
        guard !inspection.present.isEmpty else { return AgentHookStatus(agent: target, state: .notInstalled) }

        var problems: [String] = []
        var outdated = !inspection.missing.isEmpty
        if !inspection.edited.isEmpty {
            problems.append("Hook entries were changed: \(inspection.edited.joined(separator: ", ")).")
        }
        switch scriptState(bundledScript) {
        case .current: break
        case .older: outdated = true
        case .missing: problems.append("The hook script is missing.")
        case .changed: problems.append("The hook script was changed.")
        }
        var turnedOff = false
        if target == .codex, !(try codexHooksEnabled()) {
            turnedOff = CodexHooksConfig.hooksTurnedOff(in: try codexConfig().read() ?? "") == true
            problems.append(turnedOff ? "Hooks are turned off in ~/.codex/config.toml."
                                      : "Hooks are not turned on in ~/.codex/config.toml.")
        }

        if turnedOff {
            return AgentHookStatus(agent: target, state: .turnedOff, problem: problems.joined(separator: " "))
        }
        if !problems.isEmpty {
            return AgentHookStatus(agent: target, state: .modified, problem: problems.joined(separator: " "))
        }
        return AgentHookStatus(agent: target, state: outdated ? .outdated : .installed)
    }

    private enum ScriptState { case current, older, missing, changed }

    private func scriptState(_ bundled: String) -> ScriptState {
        guard let data = FileManager.default.contents(atPath: scriptURL.path) else { return .missing }
        let installed = String(decoding: data, as: UTF8.self)
        let sameVersion = Self.version(of: installed) == Self.version(of: bundled)
        if !sameVersion { return .older }
        let executable = FileManager.default.isExecutableFile(atPath: scriptURL.path)
        return installed == bundled && executable ? .current : .changed
    }

    private func codexHooksEnabled() throws -> Bool {
        let text = try codexConfig().read() ?? ""
        // Turning it on changes nothing in a file where it already is on.
        guard let enabled = CodexHooksConfig.enablingHooks(in: text) else {
            throw AgentHookError.unsupportedToml(path: codexConfig().url.path)
        }
        return enabled == text
    }

    // MARK: - Install

    /// Installs, or repairs, the hooks for each of `targets`. One agent failing does not stop the
    /// other; the report says which did.
    func install(_ targets: [AgentHookTarget], script: String) -> AgentHooksReport {
        let statuses = targets.map { target -> AgentHookStatus in
            do {
                try install(target, script: script)
                return status(of: target, bundledScript: script)
            } catch {
                var failed = status(of: target, bundledScript: script)
                failed.problem = error.localizedDescription
                return failed
            }
        }
        return AgentHooksReport(statuses: statuses)
    }

    private func install(_ target: AgentHookTarget, script: String) throws {
        if let plugin = AgentPluginFile.of(target) { return try installPlugin(plugin) }
        guard Self.version(of: script) != nil else { throw AgentHookError.scriptHasNoVersion }
        try requireSafePath()

        // Plan every edit before any byte moves, so a file that can't be edited stops the install
        // while the machine is still as it was.
        let entries = self.entries(for: target)
        let file = configFile(for: target)
        let original = try file.read()
        let updated = try entries.planInstall(original)

        var toml: (file: ConfigFile, original: String?, updated: String)?
        if target == .codex {
            let config = codexConfig()
            let tomlOriginal = try config.read()
            guard let enabled = CodexHooksConfig.enablingHooks(in: tomlOriginal ?? "") else {
                throw AgentHookError.unsupportedToml(path: config.url.path)
            }
            toml = (config, tomlOriginal, enabled)
        }

        // The script goes first: a registered hook that points at nothing fails on every event.
        try writeScript(script)
        try file.replace(original: original, with: updated) { entries.check($0, expectingOurs: true) }
        if let toml {
            try toml.file.replace(original: toml.original, with: toml.updated) { text in
                CodexHooksConfig.enablingHooks(in: text) == text ? nil : "hooks are still off in config.toml"
            }
        }
    }

    private func writeScript(_ script: String) throws {
        let data = Data(script.utf8)
        if FileManager.default.contents(atPath: scriptURL.path) == data,
           FileManager.default.isExecutableFile(atPath: scriptURL.path) { return }
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
        try ConfigFile.atomicallyWrite(data, to: scriptURL, mode: 0o755)
    }

    /// The command is read by Claude Code through a shell and by Codex as whitespace-separated
    /// words, so a home directory with anything either reads differently can't hold the script.
    private func requireSafePath() throws {
        let unsafe = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'\\$`&|;<>()*?[]{}!#~^%"))
        if scriptURL.path.rangeOfCharacter(from: unsafe) != nil {
            throw AgentHookError.unsafeHome(path: scriptURL.path)
        }
    }

    // MARK: - Uninstall

    /// Removes our entries for each of `targets`, and the script once no agent uses it. Whatever
    /// the user has in those files stays byte for byte. `features.hooks` in Codex's config.toml
    /// is left on: other hooks may rely on it.
    func uninstall(_ targets: [AgentHookTarget], bundledScript: String) -> AgentHooksReport {
        var problems: [AgentHookTarget: String] = [:]
        for target in targets {
            do {
                try uninstall(target)
            } catch {
                problems[target] = error.localizedDescription
            }
        }
        removeScriptIfUnused()
        let statuses = targets.map { target -> AgentHookStatus in
            var current = status(of: target, bundledScript: bundledScript)
            current.problem = problems[target] ?? current.problem
            return current
        }
        return AgentHooksReport(statuses: statuses)
    }

    private func uninstall(_ target: AgentHookTarget) throws {
        if let plugin = AgentPluginFile.of(target) { return try uninstallPlugin(plugin) }
        let entries = self.entries(for: target)
        let file = configFile(for: target)
        guard let original = try file.read() else { return }
        let updated = try entries.planUninstall(original)
        try file.replace(original: original, with: updated) { entries.check($0, expectingOurs: false) }
    }

    /// Kept whenever an agent still has entries of ours, or its file can't be read to tell.
    private func removeScriptIfUnused() {
        for target in AgentHookTarget.allCases where AgentPluginFile.of(target) == nil {
            guard let inspection = try? entries(for: target).inspect(configFile(for: target).read()),
                  inspection.present.isEmpty else { return }
        }
        try? FileManager.default.removeItem(at: scriptURL)
        // Only if empty: the backups live next to it.
        for directory in [scriptURL.deletingLastPathComponent(), supportDirectory] {
            rmdir(directory.path)
        }
    }

    // MARK: - Plugin files

    private func pluginStatus(of target: AgentHookTarget, _ plugin: AgentPluginFile) throws -> AgentHookStatus {
        guard let installed = try readPlugin(plugin) else { return AgentHookStatus(agent: target, state: .notInstalled) }
        guard let version = plugin.version(of: installed) else {
            // Somebody else's file under our name: not ours to report on, or to touch.
            return AgentHookStatus(agent: target, state: .notInstalled,
                                   problem: AgentHookError.notOurs(path: plugin.url(home: home).path).localizedDescription)
        }
        if version != plugin.version { return AgentHookStatus(agent: target, state: .outdated) }
        if installed != plugin.source {
            return AgentHookStatus(agent: target, state: .modified, problem: "The \(plugin.label) was changed.")
        }
        return AgentHookStatus(agent: target, state: .installed)
    }

    private func installPlugin(_ plugin: AgentPluginFile) throws {
        let url = plugin.url(home: home)
        if let installed = try readPlugin(plugin), plugin.version(of: installed) == nil {
            throw AgentHookError.notOurs(path: url.path)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigFile.atomicallyWrite(Data(plugin.source.utf8), to: url, mode: 0o644)
    }

    private func uninstallPlugin(_ plugin: AgentPluginFile) throws {
        guard let installed = try readPlugin(plugin) else { return }
        let url = plugin.url(home: home)
        guard plugin.version(of: installed) != nil else { throw AgentHookError.notOurs(path: url.path) }
        try FileManager.default.removeItem(at: url)
    }

    private func readPlugin(_ plugin: AgentPluginFile) throws -> String? {
        let url = plugin.url(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    // MARK: - Files

    private func entries(for target: AgentHookTarget) -> AgentHookEntries {
        let spec = AgentHookSpec.of(target)
        return AgentHookEntries(spec: spec, scriptURL: scriptURL, filePath: spec.hooksFile(home: home).path)
    }

    private func configFile(for target: AgentHookTarget) -> ConfigFile {
        let url = AgentHookSpec.of(target).hooksFile(home: home)
        return ConfigFile(url: url, backupLabel: "\(target.rawValue)-\(url.lastPathComponent)",
                          backupsDirectory: backupsDirectory)
    }

    private func codexConfig() -> ConfigFile {
        ConfigFile(url: home.appendingPathComponent(".codex/config.toml"), backupLabel: "codex-config.toml",
                   backupsDirectory: backupsDirectory)
    }
}
