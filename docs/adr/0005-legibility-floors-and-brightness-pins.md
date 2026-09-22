# 0005. Legibility Floors and Brightness Pins

## Context

Two sources of color end up on the notch's near-black surface: the Tint Source, and the Accent. One helper, `ensureMinimumBrightness(factor:)`, adjusted both, and it adjusted them by *scaling every color to exactly* the requested perceived brightness. Colors already bright enough to read were darkened; darker ones were lifted by a per-channel clip that shifted their hue. The name said "minimum"; the behaviour was "exactly" (issue #17).

Its two families of callers wanted different things. Text and the progress track want a floor. The system-event indicator's gradient end (0.2) and glow (0.7) want a *second* color derived from the Accent, and for an accent brighter than 0.2 — which is nearly every accent — "add the missing case" flattens that gradient into one color.

## Decision

1. Two named adjustments, both stated in Perceived Brightness (Rec.709 luma):
   - **Legibility Floor** — `withMinimumBrightness(_:)`: raises a color below the floor to it, and returns a color already at or above it unchanged. Tinted text draws through it at 0.6, the progress track at 0.8.
   - **Brightness Pin** — `withBrightness(_:)`: moves a decorative derivative of the Accent to a target brightness, lightening or darkening as required. The gradient end and the glow are pins.
2. The floor keeps the existing `factor / luma` scaling, including its clip-induced hue shift. A hue-preserving lift is a separate change with its own issue and visual review.
3. The Ambient Music Tint wash and the spectrum fill take no adjustment: a floor would brighten the background layer whose whole job is to be subtle, and the spectrum is a graphic rather than text.
4. The factors stay at their call sites. 0.6 for text and 0.8 for the track are independent choices, not one policy.

## Considered Options

- **Add the missing "already bright enough" case to the one helper.** Rejected: it fixes text and silently flattens the system-event indicator's gradient, whose ends would both become the accent color.
- **Adopt the vendored Droppy implementation** (HSB `max(brightness, factor)`). Rejected: HSB brightness is `max(R,G,B)`, not legibility. `#95292C` raised to 0.6 has a Perceived Brightness near 0.2 — still unreadable, which is the case the floor exists for.
- **Lift toward white instead of scaling.** Deferred: it removes the hue shift, but it changes how every dark cover renders, so it earns its own visual pass.
- **Keep the old helper and its behaviour for the pins.** Rejected: a helper named "minimum" that normalises is the exact ambiguity this defect grew from.

## Consequences

- A cover brighter than the floor now renders as its own color, so covers differ in brightness and not only in hue.
- The gradient and the glow are byte-for-byte unchanged: the pin keeps the old arithmetic.
- The closed-notch inline sneak peek's title and artist are floored like the other tinted text, which removes the inconsistency between panels.
- A fully black tint (Perceived Brightness 0) is drawn as the neutral gray at the floor: it has no hue to carry, and the division would otherwise produce NaN channels.
