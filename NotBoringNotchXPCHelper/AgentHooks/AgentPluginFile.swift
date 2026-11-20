//
//  AgentPluginFile.swift
//  NotBoringNotchXPCHelper
//
//  An agent that has no command hooks gets one file of ours in a folder it loads plugins from:
//  pi its extension, OpenCode its plugin. The file is ours by the version marker on its first
//  line; a file of the same name without one is the user's. The installer treats every such
//  agent alike, so what differs between them is this value and not a branch.
//

import Foundation

struct AgentPluginFile {
    /// Where the file lives, relative to the home directory.
    let path: String
    /// What it is called in a message to the user.
    let label: String
    /// The text before the version number, on the first line.
    let versionMarker: String
    /// Bump whenever `source` changes, so an installed copy can be told apart from this one.
    let version: Int
    let source: String

    /// The agents installed as a file, and the file. Nil for those installed in a hooks file.
    static func of(_ target: AgentHookTarget) -> AgentPluginFile? {
        switch target {
        case .claudeCode, .codex: return nil
        case .pi: return PiExtension.file
        }
    }

    func url(home: URL) -> URL { home.appendingPathComponent(path) }

    /// The number in a file's version marker, on its first line.
    func version(of text: String) -> Int? {
        guard let first = text.split(separator: "\n", maxSplits: 1).first,
              first.hasPrefix(versionMarker) else { return nil }
        return Int(first.dropFirst(versionMarker.count).trimmingCharacters(in: .whitespaces))
    }
}
