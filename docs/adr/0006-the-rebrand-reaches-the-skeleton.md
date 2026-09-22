# 0006. The Rebrand Reaches the Skeleton

## Context

[ADR 0004](0004-hard-fork-from-upstream.md) recorded that this project is a hard fork of
`TheBoredTeam/boring.notch`. The rebrand had already happened by then, in a commit that set
`PRODUCT_NAME`, `CFBundleName` and `PRODUCT_BUNDLE_IDENTIFIER`: the app had been called Not
Boring Notch, and shipped as such, for two releases.

What that commit left alone was the skeleton — the Xcode target names, the source directory,
the project file, the scheme, and every file whose name carried the old brand. So the app was
called Not Boring Notch while its source tree was still called `boringNotch`, one
`open boringNotch.xcodeproj` away from confusing anybody new. Behind the name sat 246
occurrences across 137 files, and one of them was a real directory on users' disks:
`~/Library/Application Support/boringNotch/`, holding whatever they had staged on the shelf.

Those leftovers were load-bearing, which is why each earlier pass skipped them. The target name
decides the scheme name, and CI builds by scheme. The directory names are referenced hundreds of
times in `project.pbxproj`, and every standalone runner in `Tests/` declares the source paths it
compiles in a `// SOURCES:` header. The XPC service is looked up by a string literal that has to
match its bundle identifier. Renaming any one of them alone breaks the build, so the rename is
all-or-nothing, and "nothing" was the cheaper answer for two releases.

## Decision

The skeleton is renamed, in one commit, to `NotBoringNotch`.

**The brand boundary.** A bare `Boring` is part of the brand, not a word: under a product named
Not Boring Notch, `BoringHeader` is a truncated brand, and it becomes `NotchHeader`. So
`BoringNotch` and `boringNotch` become `NotBoringNotch`, `Boring Notch` becomes
`Not Boring Notch`, and a bare `Boring` becomes `Notch`.

**The app's identity does not change.** `com.allenreder.notboringnotch` is already the app's
bundle identifier and stays, which is what keeps every user's preferences, TCC grants and login
item working across the upgrade. The Swift module name is `Not_Boring_Notch` — it derives from
`PRODUCT_NAME`, not from the target name — so nothing outside the tree refers to the old name
and no import changes. Only the embedded XPC service is renamed, to
`com.allenreder.notboringnotch.NotBoringNotchXPCHelper`, together with the `serviceName` string
its client looks it up by.

**Four strings that look like the brand are not the brand**, and stay as they are:

- `http://localhost:26538/auth/boringNotch` is the auth route of the local YouTube Music
  companion server. It is that process's contract, and renaming it would break the integration.
- `theboringteam.boringNotch` is upstream's bundle identifier, read to show that app's icon.
- `theboringteam.imageset` and `TheBoringTeam.svg` are upstream's logo, kept for attribution.
- `"boringShelf"` is a persisted `UserDefaults` key. The Swift property is renamed to
  `notchShelf`; the stored string is not, because changing it would silently reset the setting
  for everybody who has one.

**The old name is correct in the record.** The GPL copyright line, the historical ADRs and the
one line in ADR 0004 that names the upstream repository all keep it. So does the Discord
invite's vanity slug, which the server owns.

**Two greps enforce the boundary**, as steps in the existing CI build job:
`scripts/check-branding.sh`, which searches tracked and untracked-but-not-ignored files for the
token and answers with `Configuration/branding-allowlist.txt`, and `scripts/check-version.sh`,
which fails when the project's version settings disagree with each other.

The allowlist is the written answer to "why does this file still say boring?". It holds the
attribution and external-identifier cases above, one entry and one reason each, and nothing may
be added to it without a reason a reviewer can disagree with.

## Considered Options

- **Keep the skeleton as it was.** Rejected: the cost was not zero. Every manual carry-over of an
  upstream fix lands in a tree whose paths and headers disagree with its product name, and the
  question "why is this called boringNotch?" recurs — as a question about whether the rename had
  ever been finished.
- **Change the app's bundle identifier too, so the new name is complete.** Rejected: it buys no
  user-visible change and costs every existing user their settings, their camera, calendar and
  accessibility grants, and the login item. The old identifier is not user-visible.
- **Rewrite the historical ADRs, the GPL copyright line and the version-controlled docs so that
  no `boring` remains anywhere.** Rejected: an ADR is a record of a decision taken under the name
  in force at the time, and the GPL requires the copyright line to name the project it was
  granted for. A repository that says its own history never happened is less trustworthy than one
  that says where it came from.
- **Do the rename carefully without a gate.** Rejected: upstream is still brought in by hand
  (ADR 0004), and upstream's own tree is named `boringNotch`, so the old name arrives again on
  its own. The token is six letters; the check is one grep. The gate also gave the rename its
  acceptance criterion — it is finished when the allowlist has nothing in it but attribution.
- **Move the shelf's directory without migrating it.** Rejected: it would have been the one part
  of this change a user could lose data to. `ShelfStorage` adopts the legacy directory on first
  launch instead.

## Consequences

- Adding a target to the Xcode project means bumping the version in one more place;
  `scripts/check-version.sh` reports the count it found so that drift is visible.
- The `--expect-tag` half of the version check belongs to the release sequence in
  [`RELEASING.md`](../RELEASING.md), not to CI. A branch is legitimately between a version bump
  and its tag, so asserting the tag in CI would fail on a healthy tree.
- The gate searches *tracked* files plus untracked-but-not-ignored ones, so it can fail before
  the mistake is committed. It does not search ignored files, so the old name may persist in
  local build output and in `_refs/`.
- `boring.m4a`, the notification sound, is now `notch.m4a`, and the string that plays it moved
  with it. The file name was the brand; the sound is unchanged.
- Upstream attribution keeps working, but a reader looking for the old project name will find it
  only in the places this ADR lists — which is the point.
