# Not Boring Notch

A modern, high-performance macOS menu bar and notch companion application that enhances the camera cutout with dynamic visual elements, Liquid Glass optical refraction, media controls, and intelligent status indicators.

## Language

### Visual Surface

**Liquid Glass**:
A dynamic, transparent surface material combining optical refraction, sub-pixel chromatic dispersion, and an opaque hardware-concealing scrim.
_Avoid_: Frosted glass, acrylic material, vibrance, blur effect

**Hardware Scrim**:
An opaque gradient mask covering the top hardware camera cutout before smoothly dissolving into transparent glass.
_Avoid_: Header overlay, black border, cutout mask, camera cover

**Notch Material**:
The visual surface substrate applied to the background of the notch layout.
_Avoid_: Theme, skin, backdrop style, surface texture

**Specular Rim**:
A delicate edge highlight along the perimeter of the notch mimicking physical light reflection on beveled glass.
_Avoid_: Border, stroke, outline, glow

**Ambient Music Tint**:
A subtle, localized color wash derived from the current playing media artwork, layered between the hardware scrim and the transparent glass.
_Avoid_: Background color, player tint, album overlay

### Media Color

**Tint Source**:
The single color that the ambient music tint, the progress slider, and tinted text all render. It is derived from the current track's artwork, and from nothing else.
_Avoid_: Album color, player tint, dominant color, accent color

**Accent**:
The user's accent color — the system default or the one chosen in settings. The notch's second source of color after the Tint Source, and the source that decoration derives from.
_Avoid_: Highlight color, theme color, tint

**Artwork Fallback**:
The playback app's icon, displayed in place of artwork when a track has none of its own. It is a display fallback only and never becomes a Tint Source.
_Avoid_: Album art, placeholder artwork, app icon color

**Colorless**:
The tint state of a track that offers no artwork to derive a Tint Source from. It renders as no tint, rather than as a neutral or borrowed color.
_Avoid_: White tint, default color, gray tint, transparent tint

**Tint Settle Window**:
The grace period after the notch learns of a new track, during which it waits for artwork before declaring that track Colorless.
_Avoid_: Debounce, fallback delay, loading timeout

**Perceived Brightness**:
The Rec.709 luma of a color — `0.2126 R + 0.7152 G + 0.0722 B` — and the only quantity this project states its legibility rules in.
_Avoid_: Brightness, HSB brightness, lightness, luminance

**Legibility Floor**:
The minimum Perceived Brightness a color must reach before the notch draws it as text or as the progress track. The floor never darkens a color that already reaches it.
_Avoid_: Contrast boost, auto-contrast

**Brightness Pin**:
A decorative derivative of the Accent set to a target Perceived Brightness, lighter or darker as required. Decoration pins; text and the progress track floor.
_Avoid_: Brightness adjustment, darken, lighten

### Playback

**Estimated Position**:
The playback position the notch computes for now, from the player's last report plus the time elapsed since it at the current playback rate, rather than a position the player has confirmed.
_Avoid_: Current time, elapsed time

**Seek Settle Window**:
The grace period after a seek during which the notch keeps displaying the seek target instead of the Estimated Position, covering the gap before the player reports the new position.
_Avoid_: Drag delay, debounce, seek timeout
