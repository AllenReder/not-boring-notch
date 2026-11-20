#!/usr/bin/env python3
"""Notch Studio driver: build, launch, record the stage, find the clapperboard, trim, encode.

    ./record.py [--timeline full|short|demo|...] [--out out/notch-<timeline>.mp4] [--rebuild] [--measure]

The app shows a full-stage marker colour for a few frames after a warm-up, then starts its
timeline clock at the marker's end. This script records the stage (screencapture, outside the
app, so the ad-hoc-signed build needs no Screen Recording grant of its own), finds the last
marker frame in the recording, and cuts the video so output t=0 is timeline t=0.
Needs Python 3 and ffmpeg. Recording needs Screen Recording permission for the terminal.
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MARKER = (255, 0, 255)       # keep in sync with markerColor in Studio/Overlays.swift
SAMPLE_W, SAMPLE_H = 16, 9   # frames are shrunk to this to look for the marker
TOLERANCE = 80               # per channel, for colour-managed recordings
OUT_SIZE, OUT_FPS = "1920:1080", 30


def sh(cmd, **kw):
    return subprocess.run([str(c) for c in cmd], check=True, **kw)


def app_binary(dd: Path) -> Path:
    return dd / "Build/Products/Release/NotchStudio.app/Contents/MacOS/NotchStudio"


def build_if_needed(dd: Path, force: bool):
    binary = app_binary(dd)
    sources = list((HERE / "Studio").rglob("*.swift")) + list((HERE.parent.parent / "NotBoringNotch").rglob("*.swift")) \
        + [HERE / "NotchStudio.xcodeproj/project.pbxproj"]
    if not force and binary.exists() and binary.stat().st_mtime > max(p.stat().st_mtime for p in sources):
        return
    print("building…", flush=True)
    # Release: a Debug build trips an assertion in NowPlayingController (the mediaremote adapter isn't bundled).
    r = subprocess.run(["xcodebuild", "-project", HERE / "NotchStudio.xcodeproj", "-scheme", "NotchStudio",
                        "-configuration", "Release", "-derivedDataPath", dd, "build"],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode:
        sys.exit("\n".join(l for l in r.stdout.splitlines() if "error:" in l) or r.stdout[-3000:])


def record(binary: Path, timeline: str, raw: Path, home: Path, log: Path):
    env = dict(os.environ, STUDIO_TIMELINE=timeline, STUDIO_LOG=str(log),
               # Foundation resolves ~ and Application Support from this, so the (unsandboxed)
               # studio writes under the scratch dir instead of the user's real Library.
               CFFIXED_USER_HOME=str(home))
    # English UI whatever the Mac's language: the film is in English.
    app = subprocess.Popen([binary, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
    region, plan, cues = None, {}, None
    for line in app.stdout:
        if line.startswith("STAGE "):
            region = line.split()[1]
        elif line.startswith("CUES "):
            cues = json.loads(line[5:])
        elif line.startswith("PLAN "):
            plan = dict(kv.split("=") for kv in line.split()[1:])
            break
    if not region or not plan:
        app.kill(); sys.exit("app printed no STAGE/PLAN line")
    duration = float(plan["duration"])
    total = float(plan["warmup"]) + float(plan["marker"]) + duration + float(plan["tail"]) + 1.0
    print(f"stage {region}, timeline {plan['timeline']} {duration}s, recording {total:.1f}s", flush=True)
    raw.unlink(missing_ok=True)
    cap = subprocess.Popen(["screencapture", "-x", "-v", "-V", str(int(total + 0.999)), "-R", region, raw])
    app.wait()
    cap.wait()
    if not raw.exists():
        sys.exit("screencapture wrote nothing (Screen Recording permission for the terminal?)")
    return duration, float(plan["marker"]), cues


def frames(video: Path):
    """[(pts_seconds, is_marker)] for every frame of the video, in order."""
    r = subprocess.run(["ffmpeg", "-v", "info", "-i", video, "-vf", f"scale={SAMPLE_W}:{SAMPLE_H}:flags=area,showinfo",
                        "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                       capture_output=True, check=True)
    pts = [float(m) for m in re.findall(rb"pts_time:\s*([-\d.]+)", r.stderr)]
    size = SAMPLE_W * SAMPLE_H * 3
    out = []
    for i, t in enumerate(pts):
        px = r.stdout[i * size:(i + 1) * size]
        out.append((t, all(abs(px[j] - MARKER[j % 3]) <= TOLERANCE for j in range(size))))
    return out


def marker_runs(fr):
    """[(first_marker_pts, first_clear_pts_after, frame_count)] for each run of marker frames."""
    runs, i = [], 0
    while i < len(fr):
        if fr[i][1]:
            j = i
            while j < len(fr) and fr[j][1]:
                j += 1
            runs.append((fr[i][0], fr[j][0] if j < len(fr) else None, j - i))
            i = j
        else:
            i += 1
    return runs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeline", default=os.environ.get("STUDIO_TIMELINE", "demo"))
    ap.add_argument("--out", type=Path, help="default: out/notch-<timeline>.mp4 for full and short, else out/notch.mp4")
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--measure", action="store_true", help="report where marker flashes fall after the trim (for the sync-test timeline)")
    a = ap.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg not found")

    if a.out is None:
        a.out = HERE / "out" / (f"notch-{a.timeline}.mp4" if a.timeline in ("full", "short") else "notch.mp4")
    dd = Path(os.environ.get("STUDIO_DD", HERE / "build"))
    build_if_needed(dd, a.rebuild)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    raw = a.out.with_name(f"{a.out.stem}-raw.mov")
    home = a.out.parent / "home"
    shutil.rmtree(home, ignore_errors=True)
    home.mkdir()

    log = a.out.with_name(f"{a.out.stem}-studio.log")
    log.unlink(missing_ok=True)
    duration, marker_len, cues = record(app_binary(dd), a.timeline, raw, home, log)
    if cues:
        # For whoever cuts music and sound to the picture: scene starts, captions, notch, keys, banner, clicks.
        cue_file = a.out.with_name(f"{a.out.stem}-cues.json")
        cue_file.write_text(json.dumps(cues, indent=1, ensure_ascii=False) + "\n")
        print(f"wrote {cue_file}")

    fr = frames(raw)
    runs = marker_runs(fr)
    # screencapture only writes a frame when the screen changes, so the marker may be one frame
    # long; its length is the gap to the next frame.
    if not runs or runs[0][1] is None or runs[0][1] - runs[0][0] < marker_len / 2 or runs[0][0] <= fr[0][0]:
        sys.exit(f"clapperboard not found in {raw} ({len(fr)} frames, runs {runs}): recording started late or colours drifted")
    start, origin, n = runs[0]
    print(f"clapperboard: {n} frame(s) shown {origin - start:.3f}s (asked {marker_len}s), recording began {start - fr[0][0]:.2f}s before it; t0 = {origin:.4f}s")

    # Trim so the first output frame is the first frame after the marker. A hair early so it is kept.
    sh(["ffmpeg", "-y", "-v", "error", "-ss", f"{origin - 0.0005:.4f}", "-i", raw, "-t", f"{duration}",
        "-vf", f"scale={OUT_SIZE}:flags=lanczos,fps={OUT_FPS}:round=near",
        "-c:v", "libx264", "-crf", "12", "-preset", "slow", "-pix_fmt", "yuv420p", "-movflags", "+faststart", a.out])
    print(f"wrote {a.out}")

    if a.measure:
        rel = [(s - origin, e - origin if e else None) for s, e, _ in runs[1:]]
        print("flashes after trim (start, end) s:", [(round(s, 3), round(e, 3) if e else None) for s, e in rel])

    # Nothing but placeholder data should be in the frames; the home dir is checked for strays.
    stray = [p for p in home.rglob("*") if p.is_file() and "notch-channel-inbox" in p.name]
    print("storage:", "inbox written under scratch home" if stray else "no inbox file written")


if __name__ == "__main__":
    main()
