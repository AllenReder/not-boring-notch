//
//  ConfigFile.swift
//  NotBoringNotchXPCHelper
//
//  The disk half of editing a file that belongs to the user: ~/.claude/settings.json,
//  ~/.codex/hooks.json, ~/.codex/config.toml. Ported from CodeStatus,
//  Sources/CodeStatusCore/Installation/HookInstaller.swift (MIT).
//
//  What it guarantees: a backup before the first byte changes; no write over a file that moved
//  since it was read; an atomic replace that keeps the file's mode and follows a symlink to the
//  file it points at (dotfiles repos); and a read-back check that restores the original when the
//  result is not what was planned.
//

import Foundation

enum AgentHookError: Error, Equatable, LocalizedError {
    case notUTF8(path: String)
    /// Something is at the path, but it could not be read, so what a write would destroy is unknown.
    case unreadable(path: String)
    case notJSON(path: String)
    case unexpectedShape(path: String)
    case unsupportedToml(path: String)
    case changedSincePlan(path: String)
    case writeFailed(path: String)
    case backupFailed(path: String)
    case validationFailed(path: String, reason: String)
    case unsafeHome(path: String)
    case scriptHasNoVersion

    var errorDescription: String? {
        switch self {
        case .notUTF8(let path): return "\(path) is not UTF-8 text."
        case .unreadable(let path): return "\(path) could not be read."
        case .notJSON(let path): return "\(path) is not valid JSON, so it was left alone."
        case .unexpectedShape(let path): return "\(path) has hooks in a shape this app doesn't expect, so it was left alone."
        case .unsupportedToml(let path): return "\(path) has a layout this app can't safely edit, so it was left alone."
        case .changedSincePlan(let path): return "\(path) changed while it was being edited. Try again."
        case .writeFailed(let path): return "\(path) could not be written."
        case .backupFailed(let path): return "A backup could not be written to \(path)."
        case .validationFailed(let path, let reason): return "The edit to \(path) was undone: \(reason)."
        case .unsafeHome(let path): return "The hook path \(path) contains characters that hooks can't run."
        case .scriptHasNoVersion: return "The hook script has no version marker."
        }
    }
}

struct ConfigFile {
    let url: URL
    /// Names the backup, e.g. "claude-code-settings.json".
    let backupLabel: String
    let backupsDirectory: URL

    /// The file's text, or nil when there is genuinely nothing there.
    ///
    /// The nil decides whether a backup is taken and whether a failed write removes the file or
    /// restores it, so "absent" has to mean absent. `FileManager.contents(atPath:)` answers nil
    /// for a missing file, an unreadable one, a directory and an I/O error alike; `stat(2)` and
    /// `errno` tell them apart.
    func read() throws -> String? {
        if let data = FileManager.default.contents(atPath: url.path) {
            guard let text = String(data: data, encoding: .utf8) else {
                throw AgentHookError.notUTF8(path: url.path)
            }
            return text
        }
        var info = stat()
        if stat(url.path, &info) == 0 { throw AgentHookError.unreadable(path: url.path) }
        switch errno {
        case ENOENT, ENOTDIR: return nil
        default: throw AgentHookError.unreadable(path: url.path)
        }
    }

    /// Replaces the file's text with `updated`, if the file is still `original`.
    ///
    /// `check` inspects what was read back and returns why it is wrong, if it is.
    func replace(original: String?, with updated: String, check: (String) -> String?) throws {
        guard original != updated else { return }
        guard try read() == original else { throw AgentHookError.changedSincePlan(path: url.path) }

        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        let originalData = original.map { Data($0.utf8) }
        if let originalData { try writeBackup(originalData) }

        // An existing file keeps its permissions: narrowing a config the CLI and an editor
        // extension share is not ours to decide. A file we create gets 0600, since a settings
        // file can hold an API key. Sampled before anything on disk moves.
        let mode = existingMode() ?? 0o600
        let destination = resolvedURL()

        do {
            try Self.atomicallyWrite(Data(updated.utf8), to: destination, mode: mode)
            guard let actual = try read() else {
                throw AgentHookError.validationFailed(path: url.path, reason: "the file is missing after the write")
            }
            guard actual == updated else {
                throw AgentHookError.validationFailed(path: url.path, reason: "the written bytes differ from the plan")
            }
            if let reason = check(actual) {
                throw AgentHookError.validationFailed(path: url.path, reason: reason)
            }
        } catch {
            // Best effort: already unwinding from a failure, and a second error would hide the first.
            if let originalData {
                try? Self.atomicallyWrite(originalData, to: destination, mode: mode)
            } else {
                try? FileManager.default.removeItem(at: destination)
            }
            throw error
        }
    }

    // MARK: - Symlinks

    /// The file a write must land on. `~/.claude/settings.json` is often a symlink into a
    /// dotfiles repo; renaming a temp file over the link would replace the link with a regular
    /// file. The leaf link is followed and the file it points at is edited.
    private func resolvedURL() -> URL {
        var current = url
        // Bounded: a symlink loop must not hang the installer.
        for _ in 0..<8 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            current = Self.joining(destination, onto: current.deletingLastPathComponent())
        }
        return current
    }

    /// A relative destination is interpreted from the link's *real* directory, so `..` steps out
    /// of that directory. `realpath(3)` on the directory is the kernel's own algorithm; only the
    /// directory goes through it, since the leaf is what is being followed one hop at a time.
    private static func joining(_ destination: String, onto directory: URL) -> URL {
        let raw = destination.hasPrefix("/")
            ? destination
            : (directory.path as NSString).appendingPathComponent(destination)
        let leaf = (raw as NSString).lastPathComponent
        guard let resolved = realpath((raw as NSString).deletingLastPathComponent, nil) else {
            return URL(fileURLWithPath: raw).standardizedFileURL
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true).appendingPathComponent(leaf)
    }

    /// `stat`, not `attributesOfItem`: the latter does not follow symlinks, so it would report the
    /// link's own 0755 rather than the target's.
    private func existingMode() -> Int? {
        var info = stat()
        guard stat(resolvedURL().path, &info) == 0 else { return nil }
        return Int(info.st_mode & 0o777)
    }

    // MARK: - Writing

    private func writeBackup(_ data: Data) throws {
        let stamp = Self.stamp.string(from: Date())
        let destination = backupsDirectory.appendingPathComponent("\(backupLabel).\(stamp).bak")
        do {
            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try Self.atomicallyWrite(data, to: destination, mode: 0o600)
        } catch {
            throw AgentHookError.backupFailed(path: destination.path)
        }
    }

    /// A temp file in the *same* directory plus `rename(2)`: rename is only atomic within a
    /// filesystem, and a half-written settings file would break the agent on its next launch. The
    /// mode is set on the temp file first, so the destination is never seen with the wrong one.
    static func atomicallyWrite(_ data: Data, to destination: URL, mode: Int) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: data, attributes: [.posixPermissions: mode])
        else { throw AgentHookError.writeFailed(path: destination.path) }
        // `createFile` applies the umask; the mode asked for is the mode wanted.
        chmod(temporary.path, mode_t(mode))
        guard rename(temporary.path, destination.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw AgentHookError.writeFailed(path: destination.path)
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}
