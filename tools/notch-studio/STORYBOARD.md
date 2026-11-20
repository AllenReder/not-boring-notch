# Notch Studio storyboard (v1)

The first plan, kept for its intent and seams. The timings changed: `Studio/Storyboard.swift` is
the source of truth (full cut 42.5 s, each scene with a beat of rest so animations never overlap;
Home also shows the calendar; the outro shows the repository URL).

Two cuts from one timeline: **full** (30 s planned) and **short** (15 s: hook, reveal, agents, outro).
Agents are the climax: they are what 1.5 adds. Placeholder data only.

| # | Full | Scene | What the real notch does | Seam |
|---|---|---|---|---|
| 1 | 0.0–2.5 | Hook | Closed notch, deep zoom, slow push. Caption "Your MacBook's notch has been doing nothing." | camera |
| 2 | 2.5–6.0 | Reveal + track change | Opens to Home on glass, "Night Drive" playing; skip → "Glass Hours", artwork flips, ambient tint changes | `vm.open()`, MusicManager |
| 3 | 6.0–7.2 | Volume HUD | Closed notch, volume sneak peek rising 40 → 70 % | `toggleSneakPeek(.volume)` |
| 4 | 7.2–9.0 | Shelf | Shelf tab: drop zone lights up, three placeholder files land; the Share zone is visible (no system share picker: it lists real contacts) | `ShelfStateViewModel.add`, `dragDetectorTargeting` |
| 5 | 9.0–11.0 | Stats | Stats tab, six live cards (real samples of this Mac: CPU, GPU, memory, temperature, network, disk are not personal) | coordinator `.performance` |
| 6 | 11.0–15.0 | Launcher | ⌥Space keycaps; recents Ghostty, Safari, Telegram, Xcode, Zed; type `t` `te` `tel`; Return keycap shown, notch closes (Telegram is not actually launched) | Defaults `.launcherRecents`, key window + `insertText` |
| 7 | 15.0–25.0 | Agents | Claude + Codex working (marks breathe, count 2) → Claude waits: amber "! 1", banner "Fix login redirect · web-app / Needs your approval" → Inbox opens, cursor clicks the waiting row (no real jump) | `NotchChannel.handle(AgentEnvelope)` |
| 8 | 25.0–30.0 | Outro | Closes to breathing marks; icon, name, `brew install --cask AllenReder/tap/not-boring-notch`, "Free & open source · macOS 14+" | overlay |

Captions, keycaps, cursor and outro cards sit above the camera. Music and SFX are added in post,
cut to the timeline's cue times.
