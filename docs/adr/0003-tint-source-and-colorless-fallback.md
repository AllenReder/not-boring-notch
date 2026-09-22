# 0003. Tint Source Derivation and the Colorless Fallback

## Context

The notch renders its ambient music tint, progress slider, and tinted text from one color, `avgColor`, derived from the artwork currently on display. Two properties of the now-playing stream make "the artwork currently on display" an unsafe derivation source: a new track's metadata usually arrives in an event that carries no artwork, and the notch substitutes the playback app's icon when a track has no artwork of its own. The tint could therefore be derived from the app icon — measured in practice as the average color of the NeteaseMusic icon — and, because the derivation carries no ordering guarantee, that stale color could outlive the real artwork and persist for the whole track.

## Decision

1. **The Tint Source is the track's artwork, exclusively.** The app icon is an Artwork Fallback for display only; it never becomes a Tint Source.
2. **Every derived tint carries a generation.** Only the derivation belonging to the newest applied artwork may publish a tint, so an older derivation can never win a race against a newer one.
3. **A track that offers no artwork after the Tint Settle Window becomes Colorless.** The notch renders no tint, rather than borrowing the previous track's color or the app icon's color. The window is one second, measured from the moment the notch learns of the new track.
4. **The Artwork Fallback waits for the same window.** A late-arriving artwork therefore never produces a visible icon flash, and the displayed image and the tint advance on one timeline.

## Considered Options

- **Keep the previous track's tint indefinitely when a track offers no artwork.** Rejected: it makes a broken derivation indistinguishable from a track that simply has no artwork — the exact confusion this decision removes.
- **Fall back to the app icon's color after the window.** Rejected: the app icon is not artwork, and this is the path that produced a stuck tint in practice.
- **Derive the tint from the displayed image at render time.** Rejected: the displayed image can be the Artwork Fallback, which relocates the same defect into the view layer.

## Consequences

- A track without artwork renders no tint at all. This is a deliberate, visible absence and not a defect.
- Within the Tint Settle Window the tint still shows the previous track's color; after it, the tint can never describe the previous track.
- The tint becomes optional in the model, so "no tint" is representable instead of approximated by a color.
- Consumers that already have an untinted rendering are the defined rendering for Colorless: gray text, an uncolored spectrum, an absent ambient layer, and the white progress-slider track.
- A transport that cannot distinguish unchanged artwork from removed artwork inherits the artwork it already has, so such a track keeps the previous cover and its tint instead of settling Colorless. Transports that report absent artwork explicitly still settle Colorless.
