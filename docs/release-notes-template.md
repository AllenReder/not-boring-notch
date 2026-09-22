<!--
Release notes body template.

Copy this into the GitHub Release body — or into a file passed to
`gh release create --notes-file` — and replace every placeholder. Everything
inside HTML comments is invisible in the published notes, so the guidance below
does not leak to users.

Before publishing (see RELEASING.md for the full sequence):
  - `MARKETING_VERSION` bumped to X.Y.Z in all four places in the project file
  - Release build succeeded and the DMG is named `Not-Boring-Notch-vX.Y.Z.dmg`
  - the tag is `vX.Y.Z`, and `vPREVIOUS` is the tag before it

House style:
  - Lead with what changed *for someone using the app*, not with the commit list.
  - Bold the conclusion of a bullet, then explain it. One idea per bullet.
  - No commit hashes, no PR numbers, no author names — link the compare view for
    the detail instead.
  - Drop any section that would be empty (a one-fix patch does not need a
    "New features" heading).
-->
## ✨ What's New in vX.Y.Z

<One or two sentences: what this release changes for a person using the app.>

---

### 💎 <Headline of the change>

- **<Conclusion first.>** <Then the explanation.>
- **<Second point.>** <Then the explanation.>

---

## 🚀 Installation

1. Download **`Not-Boring-Notch-vX.Y.Z.dmg`** below.
2. Open the disk image and drag **Not Boring Notch** into your `/Applications` folder.
3. **First-launch Gatekeeper Notice:**
   As an open-source community release, macOS may show an unidentified developer
   warning on first launch. Run this single command in Terminal:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Not Boring Notch.app"
   ```

---
**Full Changelog**: https://github.com/AllenReder/not-boring-notch/compare/vPREVIOUS...vX.Y.Z
