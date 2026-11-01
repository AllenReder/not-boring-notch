//
//  LauncherSearch.swift
//  NotBoringNotch
//

import Foundation

/// Ranks applications against what was typed.
///
/// A row has one name, so the ordering is one score: the tighter the query sits in the name, the
/// higher it scores. Ties fall back to the Finder's order, so a list of equal matches still reads
/// as a list instead of as a lottery.
enum LauncherSearch {
    /// Long enough to find what is being looked for, short enough to stay one screen of scrolling.
    static let limit = 60

    /// The best matches, strongest first. An empty query matches nothing — what an empty field
    /// shows is the caller's business, not this function's.
    static func ranked(_ apps: [LauncherApp], query: String) -> [LauncherApp] {
        let needle = matchingForm(query)
        guard !needle.isEmpty else { return [] }

        var scored: [(app: LauncherApp, score: Int)] = []
        for app in apps {
            // A name in another script is matched as the letters it is typed with, so `weixin`
            // reaches 微信 the same way `saf` reaches Safari.
            let haystack = app.latinName ?? fold(app.name)
            if let score = score(needle, in: haystack) {
                scored.append((app, score))
            }
        }
        scored.sort { left, right in
            left.score == right.score
                ? left.app.name.localizedStandardCompare(right.app.name) == .orderedAscending
                : left.score > right.score
        }
        return scored.prefix(limit).map(\.app)
    }

    /// What a query is compared in: the Latin reading when it is written in another script,
    /// folded either way, so both sides of a match fold through the same rule.
    private static func matchingForm(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return LauncherRomanization.latin(trimmed) ?? fold(trimmed)
    }

    /// How well a folded query fits a folded name, or nil when it does not fit at all.
    ///
    /// Each tier owns its own hundred: an exact name, its opening, a word inside it, a stretch
    /// inside it, and finally the letters in order. Bands rather than weights, so no amount of
    /// length or position can lift a weaker kind of match over a stronger one.
    private static func score(_ query: String, in name: String) -> Int? {
        if name == query { return 1_000 }
        if name.hasPrefix(query) { return 900 + quality(offset: 0, length: name.count) }

        if let range = name.range(of: query) {
            let offset = name.distance(from: name.startIndex, to: range.lowerBound)
            let band = isWordStart(name, at: range.lowerBound) ? 800 : 700
            return band + quality(offset: offset, length: name.count)
        }

        return subsequenceScore(query, in: name).map { 600 + min($0, 99) }
    }

    /// Lowercase, accent- and width-blind: `cafe` finds Café, and a full-width `Ａ` finds A.
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Inside one band: earlier and shorter wins. Bounded below 100, so it can never reach the
    /// next band up.
    private static func quality(offset: Int, length: Int) -> Int {
        max(0, 99 - offset - min(length, 99))
    }

    private static func isWordStart(_ text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let before = text[text.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    /// The query's letters in order, scored by how tightly they sit together: a run of adjacent
    /// hits beats the same letters scattered across the name. Nil when a letter is missing.
    private static func subsequenceScore(_ query: String, in name: String) -> Int? {
        let pending = Array(query)
        var matched = 0
        var score = 0
        var run = 0
        var previous: Character?
        var lastHit = -2

        for (position, character) in name.enumerated() {
            guard matched < pending.count else { break }
            defer { previous = character }
            guard character == pending[matched] else { continue }

            run = position == lastHit + 1 ? run + 1 : 0
            score += 1 + run * 3
            if previous.map({ !$0.isLetter && !$0.isNumber }) ?? true { score += 4 }
            lastHit = position
            matched += 1
        }

        return matched == pending.count ? score : nil
    }
}
