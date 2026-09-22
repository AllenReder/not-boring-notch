# Releasing

This project is distributed as a GitHub Release carrying a DMG that the maintainer builds
locally. There is no CI signing or notarization pipeline — see
[ADR 0004](docs/adr/0004-hard-fork-from-upstream.md) — so a release is a short manual sequence
run from a clean `main`.

## 1. Make sure `main` is healthy

```bash
git switch main
git pull
./scripts/run-tests.sh
```

CI (`cicd.yml`) runs the same tests plus a Release build on every push and pull request.

## 2. Pick the version and bump it

`MARKETING_VERSION` is what the app reports and what the DMG is named after.
`CURRENT_PROJECT_VERSION` is the build number; bump it by one at the same time. Each appears
**four times** — the app target and the `BoringNotchXPCHelper` target, Debug and Release
configurations each — and all four copies are kept in step:

```bash
grep -nE "MARKETING_VERSION|CURRENT_PROJECT_VERSION" boringNotch.xcodeproj/project.pbxproj
git commit -am "chore(release): bump version to X.Y.Z"
```

## 3. Build the release app

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -derivedDataPath build/DerivedData build

APP="build/DerivedData/Build/Products/Release/Not Boring Notch.app"
```

## 4. Build the DMG

The DMG is produced by `dmgbuild` using the artwork in `Configuration/dmg/` (tracked, so a
fresh clone works). Install the pinned dependencies once:

```bash
python3 -m pip install --require-hashes -r Configuration/dmg/requirements.txt
```

Then wrap the app:

```bash
Configuration/dmg/create_dmg.sh \
  "$APP" "build/release/Not-Boring-Notch-vX.Y.Z.dmg" "Not Boring Notch"
```

The DMG is **not code signed**, so macOS warns the first time it is opened; users can start it
with right-click → Open. If a Developer ID certificate is ever added, code signing and
notarization (`xcrun notarytool submit --wait`) belong here.

## 5. Tag and publish

```bash
git tag -a vX.Y.Z -m "Not Boring Notch X.Y.Z"
git push origin main --tags
```

Then publish the Release for the tag and attach the DMG:

```bash
gh release create vX.Y.Z "build/release/Not-Boring-Notch-vX.Y.Z.dmg" \
  --title "Not Boring Notch vX.Y.Z" --notes-file <body.md>
```

Write the body from [`docs/release-notes-template.md`](docs/release-notes-template.md).
`gh release create --generate-notes` is the alternative: it groups the commit list by the
`.github/release.yml` categories, which is a starting point to edit down rather than something
to publish as-is.

## 6. Confirm the issue form was updated

Publishing the release, or pushing the tag, runs `update-version-dropdown.yml`: it rewrites the
version dropdown in `.github/ISSUE_TEMPLATE/1-bug-report-form.yml` with the five most recent
tags. Check that the new version shows up in the form. If that job failed, the dropdown simply
still lists the old tags — nothing else breaks.
