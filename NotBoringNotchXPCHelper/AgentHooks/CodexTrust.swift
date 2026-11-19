//
//  CodexTrust.swift
//  NotBoringNotchXPCHelper
//
//  Codex runs a hook only after it is trusted, and records trust as a hash of the entry in
//  config.toml under [hooks.state]. Rather than writing that hash ourselves, this asks
//  `codex app-server` to: it lists the hooks Codex found (`hooks/list`) and writes the hash of
//  each of ours that is not trusted yet (`config/batchWrite`). Ported from Lookout,
//  Sources/LookoutCore/CodexTrust.swift (MIT).
//
//  Only hooks that run our script, from the hooks file we installed into, are trusted. The
//  user's own hooks are never touched, and the button that calls this is the user's consent.
//

import Foundation

enum CodexTrust {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
        static let codexNotFound = Failure(message: "Couldn't find the codex command.")
    }

    /// The `hooks.state` entries that trust the hooks of ours in a `hooks/list` result, keyed by
    /// Codex's own key for each hook. Empty when there is nothing left to trust.
    static func untrustedState(in list: [String: Any], hooksFile: String, script: URL) -> [String: Any] {
        let entries = ((list["data"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]) ?? []
        var state: [String: Any] = [:]
        for hook in entries {
            guard let source = hook["sourcePath"] as? String,
                  AgentHookEntries.sameFile(source, hooksFile),
                  let command = hook["command"] as? String,
                  AgentHookEntries.runs(command, script),
                  hook["trustStatus"] as? String != "trusted",
                  let key = hook["key"] as? String,
                  let hash = hook["currentHash"] as? String else { continue }
            state[key] = ["trusted_hash": hash]
        }
        return state
    }

    /// Trusts every untrusted hook of ours in `hooksFile`, through `executable arguments`.
    /// Returns how many were newly trusted.
    @discardableResult
    static func trustOurHooks(
        hooksFile: URL, script: URL, home: URL,
        executable: String, arguments: [String] = ["app-server"],
        environment: [String: String]? = nil, timeout: TimeInterval = 20
    ) throws -> Int {
        let server = try AppServer(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
        defer { server.close() }
        _ = try server.call("initialize", ["clientInfo": ["name": "not-boring-notch", "version": "1.0"]])
        try server.notify("initialized")

        let list = try server.call("hooks/list", ["cwds": [home.path]])
        let state = untrustedState(in: list, hooksFile: hooksFile.path, script: script)
        guard !state.isEmpty else { return 0 }
        _ = try server.call("config/batchWrite", [
            "edits": [["keyPath": "hooks.state", "mergeStrategy": "upsert", "value": state]],
        ])
        return state.count
    }

    // MARK: - Finding codex

    /// The login shell's PATH. An XPC service gets a minimal PATH, and the npm `codex` launcher is
    /// a `#!/usr/bin/env node` script that needs `node` on it.
    static func loginShellPath() -> String {
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // Markers guard against startup files that print to stdout.
        guard let output = run(shell, ["-lc", "printf '__PATH__%s__END__' \"$PATH\""], timeout: 5),
              let start = output.range(of: "__PATH__"),
              let end = output.range(of: "__END__", range: start.upperBound ..< output.endIndex)
        else { return fallback }
        let path = String(output[start.upperBound ..< end.lowerBound])
        return path.isEmpty ? fallback : path
    }

    static func findCodex(path: String, home: URL) -> String? {
        let directories = path.split(separator: ":").map(String.init) + [home.appendingPathComponent(".local/bin").path]
        return directories.map { ($0 as NSString).appendingPathComponent("codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Finds codex the way the user's terminal does, then trusts our hooks through it.
    static func trustOurHooks(installer: AgentHookInstaller) throws -> Int {
        let path = loginShellPath()
        guard let codex = findCodex(path: path, home: installer.home) else { throw Failure.codexNotFound }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        // The Codex home the hooks were installed into, and no other.
        environment["HOME"] = installer.home.path
        environment["CODEX_HOME"] = installer.home.appendingPathComponent(".codex").path
        return try trustOurHooks(
            hooksFile: AgentHookSpec.of(.codex).hooksFile(home: installer.home), script: installer.scriptURL,
            home: installer.home, executable: codex, environment: environment)
    }

    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - JSON-RPC

    /// A line-delimited JSON-RPC client over a `codex app-server` child. A child that stops
    /// answering is killed after `timeout`, which ends the pending read with an error.
    private final class AppServer {
        private let process = Process()
        private let stdin = Pipe()
        private let stdout = Pipe()
        private var buffer = Data()
        private var nextID = 1

        init(executable: String, arguments: [String], environment: [String: String]?, timeout: TimeInterval) throws {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardInput = stdin
            process.standardOutput = stdout
            // Never read, so anything left in a pipe could fill it and stall the child.
            process.standardError = FileHandle.nullDevice
            try process.run()
            let child = process
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if child.isRunning { child.terminate() } }
        }

        func notify(_ method: String) throws {
            try send(["jsonrpc": "2.0", "method": method])
        }

        func call(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
            let id = nextID
            nextID += 1
            try send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
            while true {
                let message = try readMessage()
                guard message["id"] as? Int == id else { continue }   // a notification, or not ours
                if let error = message["error"] as? [String: Any] {
                    throw Failure(message: "Codex app-server error: \(error["message"] as? String ?? "\(error)")")
                }
                return message["result"] as? [String: Any] ?? [:]
            }
        }

        func close() {
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        private func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
            data.append(0x0A)
            do {
                try stdin.fileHandleForWriting.write(contentsOf: data)
            } catch {
                throw Failure(message: "Codex app-server stopped answering.")
            }
        }

        private func readMessage() throws -> [String: Any] {
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex ..< newline]
                    buffer.removeSubrange(buffer.startIndex ... newline)
                    if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { return object }
                    continue
                }
                let chunk = stdout.fileHandleForReading.availableData
                if chunk.isEmpty { throw Failure(message: "Codex app-server stopped answering.") }
                buffer.append(chunk)
            }
        }
    }
}
