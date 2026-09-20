# 0001. Liquid Glass Optical Refraction Pipeline

## Context

Boring Notch requires a modern, crystal-clear visual surface that seamlessly blends the physical camera cutout into the desktop environment. Standard AppKit materials (such as `NSVisualEffectView` and SwiftUI's `.ultraThinMaterial`) produce an opaque, desaturated gray blur fog across large surface areas (190pt+ height) with zero directional optical refraction. Furthermore, Apple's high-level `.glassEffect` API in macOS 26 defaults to high blur opacity and does not expose refraction or dispersion parameters.

## Decision

We use an underlying CoreAnimation hardware pipeline via dynamic runtime reflection:
1. `CABackdropLayer` for zero-copy hardware framebuffer sampling.
2. `CASDFLayer` + `CASDFOutputEffect` to generate GPU signed distance fields aligned with the notch sidewalls.
3. `CAFilter("glassBackground")` configured with zero blur (`inputBlurRadius = 0.0`), negative inner refraction, sub-pixel chromatic dispersion, and high-order smoothness (38.0).
4. An integrated `Hardware Scrim` (quadratic black gradient) layered above the glass to conceal the physical camera housing.

When running on systems prior to macOS 26 or if private CoreAnimation symbols are unavailable, the layout gracefully falls back to classic solid black (`.background(.black)`).

## Consequences

- Crystal-clear visual fidelity with true physical ray-bending around the perimeter of the notch.
- No build breakages or compile-time lock-in on older macOS SDKs (macOS 14/15 target preserved).
- Private symbol invocation is isolated to a self-contained background view without polluting the rest of the codebase.
