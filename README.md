<h1 align="center">
  <br>
  <a href="https://github.com/AllenReder/not-boring-notch"><img src="assets/app-icon.png" alt="Not Boring Notch" width="140"></a>
  <br>
  Not Boring Notch
  <br>
</h1>

<p align="center">
  <em>A heavily modernized, high-performance notch companion for macOS.</em><br>
  <strong>Forked from <a href="https://github.com/TheBoredTeam/boring.notch">TheBoredTeam/boring.notch</a> · Maintained by Allen Reder</strong>
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_zh.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/AllenReder/not-boring-notch/actions/workflows/cicd.yml"><img src="https://github.com/AllenReder/not-boring-notch/actions/workflows/cicd.yml/badge.svg" alt="Build Status" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" alt="License" /></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.0-orange?logo=swift" alt="Swift 5" />
</p>

---

Say hello to **Not Boring Notch**, the coolest way to make your MacBook’s notch the star of the show! 

Forget about static black cutouts: with Not Boring Notch, your notch transforms into a dynamic control center with native **macOS 26 Liquid Glass optical refraction**, vibrant visualizers, lyrics, calendar integration, a handy file shelf with AirDrop support, sleek system HUD replacements, and upcoming intelligent workflow companions.

<p align="center">
  <img src="assets/demo.gif" alt="Demo GIF" width="85%" />
</p>

---

## ✨ Features

- 💎 **Liquid Glass Surface**: Native CoreAnimation GPU ray-bending refraction, sub-pixel chromatic dispersion, and crystal-clear transparency with zero blur.
- 🔔 **Custom Reminder Channel**: Let command-line scripts, automated hooks, and AI agents raise glanceable, dynamic notifications in the notch over a local HTTP port (`127.0.0.1:45999`). Supports auto-adaptive wings, smooth marquee scrolling, in-place status updates without spam, and interactive action buttons. See [docs/reminder-channel.md](docs/reminder-channel.md).
- 🎵 **Media Powerhouse**: Deep integration with Apple Music, Spotify, and YouTube Music. Features real-time lyrics, high-frame-rate spectrogram visualizers, and album art ambient color tinting.
- 📆 **Calendar & Reminders**: Full monthly calendar view, upcoming events, and checkable system Reminders built directly into the notch.
- 📚 **File Shelf**: Drop files into the notch to stage them, quick-look previews, and drag them out anywhere or share via AirDrop.
- 🎚️ **System HUDs**: Sleek Dynamic Island replacements for volume, brightness, backlight, and battery charging animations.
- 🪞 **Notch Mirror & Face**: Built-in camera mirror for quick appearance checks and playful animated notch expressions.

---

### 🔔 Quick Start: Sending a Notch Reminder

With Not Boring Notch running, any script or tool can trigger a glanceable notification in your notch via a single `curl`:

```bash
# Read the auto-generated local token
TOKEN=$(cat "$HOME/Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/reminder-channel.json" | grep -o '"token" *: *"[^"]*"' | cut -d'"' -f4)

# Raise a reminder
curl -X POST http://127.0.0.1:45999/reminder \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"icon":{"kind":"sf_symbol","value":"hammer.fill"},"title":"Build Finished","subtitle":"12s"}'
```

For detailed API documentation, custom icon support, and queue behavior, check out the [Reminder Channel Guide](docs/reminder-channel.md).

---

## 🚀 Installation

**System Requirements:**
- macOS **14 Sonoma** or later (macOS 26+ for full Liquid Glass hardware refraction)
- Apple Silicon or Intel Mac

### Download from GitHub Releases

1. Download the latest `.dmg` from [**Releases**](https://github.com/AllenReder/not-boring-notch/releases/latest);
2. Open the `.dmg` and drag **Not Boring Notch** into your `/Applications` folder;
3. On first launch, if macOS Gatekeeper prompts an unidentified developer notice, run this command once in Terminal:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Not Boring Notch.app"
   ```
4. Launch and enjoy!

---

## 🛠️ Building from Source

### Prerequisites

- macOS 15.0 or later
- Xcode 16.0 or later

### Build Instructions

1. Clone the repository:
   ```bash
   git clone https://github.com/AllenReder/not-boring-notch.git
   cd not-boring-notch
   ```

2. Open the project in Xcode:
   ```bash
   open NotBoringNotch.xcodeproj
   ```

3. Press `Cmd + R` to build and run.

---

## 💖 Acknowledgments & Heritage

This project is open-source under the [GNU General Public License v3.0](LICENSE). We gratefully acknowledge the foundations laid by upstream and community projects:

- **[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)** – The originating open-source project created by Harsh Vardhan Goswami and contributors.
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** – High-performance Now Playing source for macOS.
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** – Inspired the initial concept of the shelf drag-and-drop mechanics.
- **[SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)** – macOS SkyLight window management.
