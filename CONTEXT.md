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

**Artwork Fallback**:
The playback app's icon, displayed in place of artwork when a track has none of its own. It is a display fallback only and never becomes a Tint Source.
_Avoid_: Album art, placeholder artwork, app icon color

**Colorless**:
The tint state of a track that offers no artwork to derive a Tint Source from. It renders as no tint, rather than as a neutral or borrowed color.
_Avoid_: White tint, default color, gray tint, transparent tint

**Tint Settle Window**:
The grace period after the notch learns of a new track, during which it waits for artwork before declaring that track Colorless.
_Avoid_: Debounce, fallback delay, loading timeout
