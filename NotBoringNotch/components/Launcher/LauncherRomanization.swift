//
//  LauncherRomanization.swift
//  NotBoringNotch
//

import Foundation

/// What a name written in another script is typed as, so `weixin` finds 微信.
///
/// ICU serves Han, kana and Hangul well, and each is routed to the reading people actually type
/// rather than the one the generic transform would pick. A Latin name costs one scalar scan and is
/// left alone.
///
/// shortcut: Cyrillic reads through ICU, which turns `Яндекс` into `andeks`; give it a table of its
/// own when a Russian-named app matters.
enum LauncherRomanization {
    /// The Latin reading, folded and single-spaced; nil when the name is Latin already.
    static func latin(_ name: String) -> String? {
        guard let script = script(of: name) else { return nil }

        let reading: String?
        switch script {
        case .han:
            reading = name.applyingTransform(.mandarinToLatin, reverse: false)
        case .japanese:
            // Only the kana: ICU would read the kanji as Mandarin, which is a different word.
            reading = dropping(name, in: Script.hanRanges)
                .applyingTransform(.toLatin, reverse: false)
        case .hangul, .other:
            reading = name.applyingTransform(.toLatin, reverse: false)
        }
        guard let reading else { return nil }

        let folded = LauncherSearch.fold(reading).split(separator: " ").joined(separator: " ")
        // A reading that says nothing the name did not is not worth matching against.
        return folded.isEmpty || folded == LauncherSearch.fold(name) ? nil : folded
    }

    private enum Script {
        case han
        case japanese
        case hangul
        case other

        static let hanRanges: [ClosedRange<UInt32>] = [0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF]
        static let kanaRanges: [ClosedRange<UInt32>] = [0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF]
        static let hangulRanges: [ClosedRange<UInt32>] = [
            0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7AF,
        ]
    }

    /// The script with a rule of its own, if the name has one. Kana is decided first and Han
    /// last, so a Japanese title is not read as Mandarin.
    private static func script(of name: String) -> Script? {
        var found: Script?
        for scalar in name.unicodeScalars {
            if contains(Script.kanaRanges, scalar) { return .japanese }
            if contains(Script.hanRanges, scalar) {
                found = .han
            } else if contains(Script.hangulRanges, scalar), found == nil {
                found = .hangul
            } else if scalar.value > 0x24F, scalar.properties.isAlphabetic, found == nil {
                found = .other
            }
        }
        return found
    }

    private static func dropping(_ value: String, in ranges: [ClosedRange<UInt32>]) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { !contains(ranges, $0) }))
    }

    private static func contains(_ ranges: [ClosedRange<UInt32>], _ scalar: Unicode.Scalar) -> Bool {
        ranges.contains { $0.contains(scalar.value) }
    }
}
