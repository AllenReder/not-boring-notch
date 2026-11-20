# Notch Studio

Records the app's real notch for launch video footage. The notch's Liquid Glass is drawn by the
window server, so it only exists in a screen recording of a real on-screen window. Studio compiles
the app's own sources (`NotBoringNotch/`, minus its `@main`), shows the notch on a 1280x720pt stage
window on the **built-in display** over a wallpaper, drives it from a timeline, and `record.py`
records and trims it.

    ./record.py --timeline full              # the film: out/notch-full.mp4 (~42 s) + out/notch-full-cues.json
    ./record.py --timeline short             # the 15 s cut: out/notch-short.mp4 + cues
    ./record.py                              # builds if needed, records `demo`, writes out/notch.mp4 (1920x1080, 30 fps)
    ./record.py --timeline glass-test        # also: sync-test (add --measure)
    STUDIO_DD=<dir> ./record.py              # DerivedData elsewhere (default: ./build)

Hands off the Mac while it records: the stage floats over the built-in display for ~12 s.

## How a take works

1. App launches, waits 2.5 s (recorder warm-up), fills the stage with magenta for 0.2 s (the
   clapperboard), and starts the timeline clock the moment it clears.
2. `record.py` records the stage with `screencapture` (outside the app, so no Screen Recording
   grant is needed for the ad-hoc build), finds the marker, cuts so output t=0 is timeline t=0,
   scales to 1920x1080 and resamples to a constant 30 fps. The raw take is kept as `out/notch-raw.mov`.
3. `CFFIXED_USER_HOME=out/home` makes the app's `~`/Application Support point at scratch; the
   real `~/Library/Application Support/NotBoringNotch` is not touched.

## Writing a scene (`Studio/Scenes.swift`)

A `Timeline` is a duration plus `[Cue]`, every cue at seconds from t=0:
`.camera(at:zoom:pan:over:ease:)` (zoom about the notch's top centre; wallpaper and notch zoom,
overlays do not), `.caption`, `.notch(.open/.close/.view(_))`, `.music(Track?)`, `.banner`,
`.agent(session:_)`, `.run` (escape hatch), `.flash` (sync measurement). Add the timeline to
`Scenes.all`. Placeholder data only; `Track.placeholder` generates artwork.

Seams live in `Studio/Seams.swift`. Gotcha: the app's real media controller must be cut loose
(`MusicManager.destroy()`) before the first music cue, or its artwork fallback overwrites the cover.
