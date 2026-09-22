# 0002. Liquid Glass Layering Hierarchy and State Boundary

> Partially superseded by [ADR-0003](0003-tint-source-and-colorless-fallback.md): the Ambient Music Tint’s source is now the Tint Source (the track’s artwork only), which replaces the “album dominant color” wording in Decision 3.

## Context

Integrating Liquid Glass into Boring Notch requires defining its interaction with multiple window states (closed notch vs opened card), dynamic resize animations, and media playback color tinting. Applying glass refraction to the closed notch (~32pt height) causes severe optical distortion directly over the physical camera aperture. Furthermore, applying full-bleed album art color across transparent glass results in a muddy, desaturated appearance that destroys optical refraction.

## Decision

1. **State Boundary**: Liquid Glass is active strictly when `vm.notchState == .open`. The closed notch remains solid black (`.black`).
2. **Animation Tracking**: The CoreAnimation backdrop and signed distance field (SDF) element track layout bounds dynamically during spring open/close animations and drag gestures.
3. **Layering Hierarchy**:
   - Layer 1 (Base): `LiquidGlassBackdropView` (CoreAnimation `CABackdropLayer` + `CASDFLayer` + `CAFilter("glassBackground")` with zero blur and directional refraction).
   - Layer 2 (Hardware Scrim): Quadratic black gradient with a 34pt solid top core, 45pt softness, and 0% bottom floor.
   - Layer 3 (Ambient Music Tint): When `Defaults[.playerColorTinting]` is active, the album dominant color is blended softly (12%–15% opacity) only within the middle band (34pt–80pt), keeping the bottom refractive edge crystal clear.
   - Layer 4 (Specular Rim): Subtle neutral white edge stroke (0.4x intensity).
   - Layer 5 (Content): Interactive controls, waveforms, and text.
4. **Display Consistency**: Non-notch displays retain the 34pt top scrim anchor to ensure identical foreground contrast.
5. **Default State**: Enabled by default (`Defaults[.enableLiquidGlass] = true`) on supported macOS 26+ systems with runtime reflection fallback.

## Consequences

- Completely eliminates optical distortion over the camera cutout.
- Preserves high-frequency wallpaper clarity and optical edge refraction while still supporting album color tinting.
- Provides a unified visual experience across both built-in notch displays and external monitors.
