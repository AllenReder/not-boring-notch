# Boring Notch Liquid Glass Interactive Prototype

> **Throwaway Code** to evaluate Apple-native Liquid Glass implementations for the entire boring notch surface.

## Question Being Answered

> Which Apple-native Liquid Glass approach provides the strongest refraction and highest transparency across the entire 640×190 boring notch?

## The 3 Engines (All Apple Native QuartzCore/Metal Pipeline)

1. **Variant 1: SwiftUI `.glassEffect` (Official High-Level)**
   - Apple's official SwiftUI modifier (`GlassEffectContainer` + `glassEffect`).
   - Supports `.clear` (high transparency) and `.regular` (standard adaptive blur).
2. **Variant 2: AppKit `NSGlassEffectView` (Official AppKit View)**
   - Direct AppKit `NSGlassEffectView` embedding without SwiftUI container layout side-effects.
   - Cleanest native backdrop sampling.
3. **Variant 3: CoreAnimation `glassBackground` (Official Low-Level GPU Pipeline, Unlocked)**
   - Uses Apple's exact internal `CABackdropLayer` + `CAFilter("glassBackground")` + `CASDFLayer`.
   - Bypasses system fixed defaults:
     - **Refraction Multiplier**: 1.0x (-60) to 4.0x (-240) for massive optical bending.
     - **Lens Band**: 10pt to 60pt wide.
     - **Blur Radius**: 0 to 10 (allows crystal-clear glass without heavy clouding).
     - **Bleed Amount**: 0.0 (removes the 66.5 milky white wash).
     - **Chromatic Aberration**: Optical prism rainbow dispersion along curved edges.

## Visual Additions

- **Black Fade Scrim**: Natural quadratic ease-out decay from the physical camera region (100% black) down to `floor` (0~20%) at the bottom, letting wallpaper colors shine through.
- **3D Caustic Refraction Rim**: Dual-layer specular edge highlight following the `NotchShape` curve.
- **Sunset Reference Backdrop**: Pixel-faithful reproduction of the warm sunset gradient and mountain horizon from the reference screenshot.

## Interactive Controls

- `1` / `2` / `3`: Switch between the 3 engines.
- `S`: Sunset Backdrop (Reference scene).
- `D`: Real Desktop (transparent window sampling real apps).
- `C`: Checkerboard (optical grid to inspect refraction curvature).
- `B`: Busy Shapes.
- `W`: Pure White.
- `V`: Switch `.clear` vs `.regular`.
- `H`: Toggle 3D Caustic Rim.
- `F`: Toggle Black Fade.
- `R`: Step Refraction strength (Variant 3).
- `Q` / `Esc`: Quit prototype.
