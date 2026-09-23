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
./scripts/check-branding.sh
./scripts/check-version.sh
./scripts/check-sources.sh
```

CI (`cicd.yml`) runs all four plus a Release build on every push and pull request.

## 2. Pick the version and bump it

`MARKETING_VERSION` is what the app reports and what the DMG is named after.
`CURRENT_PROJECT_VERSION` is the build number; bump it by one at the same time. Each appears
**four times** — the app target and the `NotBoringNotchXPCHelper` target, Debug and Release
configurations each — and all four copies have to agree:

```bash
./scripts/set-version.sh X.Y.Z N     # writes all eight values, then checks them
git commit -am "chore(release): bump version to X.Y.Z"
```

Writing one and missing another is not a build error. It is a build that reports a version nobody
released, which is what the About pane did once already. `set-version.sh` writes every copy in one
go and then runs `check-version.sh`, whose predicate is exactly its own postcondition — so the
step either ends with the eight values agreeing or with a named reason it could not make them.
CI runs that same check on every push, so a copy edited by hand afterwards cannot quietly
disagree either.

## 3. Build the release app

```bash
xcodebuild -project NotBoringNotch.xcodeproj -scheme NotBoringNotch \
  -configuration Release -derivedDataPath build/DerivedData build

APP="build/DerivedData/Build/Products/Release/Not Boring Notch.app"
```

## 4. Re-sign the app ad-hoc, without the hardened runtime

The Release configuration enables the hardened runtime, and library validation then refuses to
load the app's own embedded framework, because this build is ad-hoc signed (no Team ID):

```
dyld: Library not loaded: @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
      Referenced from: /Applications/Not Boring Notch.app/Contents/MacOS/Not Boring Notch
      Reason: tried: … (code signature in … not valid for use in process:
              mapping process and mapped file (non-platform) have different Team IDs)
```

The app aborts at launch when this happens. Re-sign without the runtime option, keeping the
entitlements, and check the result:

```bash
codesign --force --deep --sign - --preserve-metadata=entitlements "$APP"
codesign -dv "$APP" 2>&1 | grep flags    # want flags=0x2(adhoc); a `runtime` flag here means a broken DMG
codesign --verify --deep --strict "$APP"
```

Debug builds are unaffected — the hardened runtime is off there — which is why running the app
from Xcode never shows this. A Developer ID certificate would change this step: sign with that
identity, keep the runtime, and notarize.

## 5. Build the DMG

The DMG is produced by `dmgbuild` using the artwork in `Configuration/dmg/` (tracked, so a
fresh clone works). `pip install` into a Homebrew Python is refused (`externally-managed-environment`),
so keep the pinned dependencies in a virtualenv — it lives under the git-ignored `build/` and
survives between releases:

```bash
python3 -m venv build/dmgbuild-venv
build/dmgbuild-venv/bin/pip install --require-hashes -r Configuration/dmg/requirements.txt
```

Then wrap the app:

```bash
PATH="$PWD/build/dmgbuild-venv/bin:$PATH" Configuration/dmg/create_dmg.sh \
  "$APP" "build/release/Not-Boring-Notch-vX.Y.Z.dmg" "Not Boring Notch"
```

The app inside the DMG is ad-hoc signed, so Gatekeeper blocks the first launch and says the
developer cannot be verified. The release notes tell users to clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/Not Boring Notch.app"
```

macOS 15 removed the old right-click → Open shortcut, so that command (or System Settings →
Privacy & Security → Open Anyway) is the way in. With a Developer ID certificate, signing and
notarization (`xcrun notarytool submit --wait`) belong here instead.

## 6. Tag and publish

```bash
git tag -a vX.Y.Z -m "Not Boring Notch X.Y.Z"
./scripts/check-version.sh --expect-tag   # the tag and the built app have to agree
git push origin main --tags
```

`--expect-tag` is checked here rather than in CI because a branch is legitimately between a
version bump and its tag, so on a topic branch that check would fail on a healthy tree.

Then publish the Release for the tag and attach the DMG:

```bash
gh release create vX.Y.Z "build/release/Not-Boring-Notch-vX.Y.Z.dmg" \
  --title "Not Boring Notch vX.Y.Z" --notes-file <body.md>
```

Write the body from [`docs/release-notes-template.md`](docs/release-notes-template.md).
`gh release create --generate-notes` is the alternative: it groups the commit list by the
`.github/release.yml` categories, which is a starting point to edit down rather than something
to publish as-is.

## 7. Confirm the issue form was updated

Publishing the release, or pushing the tag, runs `update-version-dropdown.yml`: it rewrites the
version dropdown in `.github/ISSUE_TEMPLATE/bug-report.yml` with the five most recent
tags. Check that the new version shows up in the form. If that job failed, the dropdown simply
still lists the old tags — nothing else breaks.
