//
//  SelfLabeling.swift
//  NotBoringNotch
//

import SwiftUI

/// A settings enum whose cases are their own user-visible text, so the raw value
/// doubles as the catalogue key for the case's label.
///
/// Both couplings are load-bearing: `Defaults` persists the raw value, and the
/// string catalog translates it. Renaming a case therefore resets the saved
/// setting *and* retires its translation. And `Text(someEnum.rawValue)` — a
/// `String`, not a key — renders the case in English in every language, which is
/// why the case is shown through `label`.
protocol SelfLabeling: RawRepresentable where RawValue == String {}

extension SelfLabeling {
    var label: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
