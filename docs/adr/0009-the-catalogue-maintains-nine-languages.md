# 0009. The Catalogue Maintains Nine Languages

## Context

`Localizable.xcstrings` shipped sixteen languages, and counting the cells that had *something* in
them said 78% of it was translated. Counting the cells that said something other than the English
said much less. Of 3446 non-English cells, 1531 were the English key, copied across and marked
`translated` or `needs_review`. In `ar` 209 of 230 cells were copies, in `hu` 210, in `en-GB` 193,
in `ru` 181, in `pt-BR` 167. A copy and a translation were the same thing on screen and in Xcode,
so no translator was ever offered the work, and the number that said "78% done" was the reason
nobody looked.

Coverage also skipped features rather than words. The Launcher and Performance tabs and the Liquid
Glass tuning panel shipped UI text the catalogue never saw: the enums behind the settings pickers
were shown as `option.rawValue`, the Launcher footers and the Beta badges went through helpers
that took a `String`, and `Defaults.Toggle("Player tinting", key:)` sits on an overload that takes
`some StringProtocol` and renders it verbatim. `Text` localizes a literal and passes a `String`
through, so each of these rendered in English in every language, catalogue or no catalogue.

## Decision

Nine languages are maintained: zh-Hans, de, fr, es, it, ko, cs, pl and tr. All nine cover all 342
keys. zh-Hans is marked `translated`; the other eight are marked `needs_review`, because they were
written in one pass without a native reader and Xcode should keep saying so.

The other six — ar, hu, ru, uk, pt-BR and en-GB — keep only the values somebody actually wrote and
fall back to English for everything else. Their copies are deleted rather than flagged: they
rendered English anyway, and leaving them in place keeps Xcode from ever offering the work.

A value identical to its key now means one of three things: a format-only string, a brand, or a
word the language spells as English does. Anything else is a missing translation.

A label reaches the catalogue by being a literal or a `LocalizedStringKey`. Where a `String` is
unavoidable — text composed into a longer sentence, the label closure of a third-party toggle, a
property that is also interpolated into an accessibility label — it is translated where it is
written, with `String(localized:)`. Enum cases that are their own label conform to `SelfLabeling`,
which states the coupling once: a case's raw value is both the setting `Defaults` persists and the
key the catalogue translates.

## Considered Options

- **Retranslate all sixteen languages.** Rejected: roughly 1200 cells for six languages nobody on
  the branch reads, in scripts nobody opened, including RTL layout that was never run. A confident
  wrong translation is worse than English, because it hides that the string still needs work.
- **Flag the English copies `needs_review` and leave them.** Rejected: they would look like work
  somebody started, and the next audit would have to make the same judgement call again to find
  out they are not.
- **Keep the enum labels as `rawValue` and translate the raw values.** Rejected: `Text(option.rawValue)`
  is a `String`, so it never asks the catalogue at all.

## Consequences

- Xcode's "needs review" count is honest: eight machine-written locales. A native reader can work
  through them without first finding out what is real.
- Adding a language now means authoring 342 cells, not 295, and the pane somebody forgets is
  visible as English rather than as a copy marked done.
- Renaming a `SelfLabeling` case resets the saved setting *and* retires that case's translation.
  The protocol's documentation says so; add a case instead of renaming one.
- `en-GB` inherits `en` by fallback and now holds 37 values, the ones where British spelling
  actually differs.
- The Launcher, Liquid Glass and Reminder Channel panes read as English in the six languages that
  fall back, until someone retranslates them.
