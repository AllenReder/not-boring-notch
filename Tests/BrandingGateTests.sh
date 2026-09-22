#!/usr/bin/env bash
#
# Tests for scripts/check-branding.sh.
#
# The gate decides two things: which occurrences of the old brand are violations, and
# which occurrences are legitimately exempt. Both are pinned here, because the token
# "boring" lives inside strings this repository is *allowed* to contain:
#
#   NotBoringNotch      contains  BoringNotch
#   Not Boring Notch    contains  Boring Notch
#   not-boring-notch    contains  boring-notch
#
# A gate that flagged those would be worse than no gate, so they are the first thing
# this file asserts. The allowlist cases come last: an exemption that leaks into a
# neighbouring file, or that swallows a second violation on the same line, is a gate
# that has quietly stopped working.
#
# The assertion helpers are in Tests/Support/GateTestHarness.sh, shared with the other gate's
# runner so that "expect a violation" means one thing in both.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Support/GateTestHarness.sh
. "$(dirname "$0")/Support/GateTestHarness.sh"
GATE="$ROOT/scripts/check-branding.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0

reset_fixture() {
  rm -rf "$WORK/tree"
  mkdir -p "$WORK/tree"
  : > "$WORK/files"
}

# write_file <repo-relative-path> <contents>
write_file() {
  mkdir -p "$WORK/tree/$(dirname "$1")"
  printf '%s\n' "$2" > "$WORK/tree/$1"
  printf '%s\n' "$1" >> "$WORK/files"
}

# run_gate_verbatim <allowlist-bytes>
#
# The allowlist is written into the fixture tree rather than beside it, so that every case
# also exercises the gate's refusal to scan its own allowlist file.
run_gate_verbatim() {
  mkdir -p "$WORK/tree/Configuration"
  printf '%s' "$1" > "$WORK/tree/Configuration/branding-allowlist.txt"
  printf '%s\n' "Configuration/branding-allowlist.txt" >> "$WORK/files"
  CHECK_BRANDING_ROOT="$WORK/tree" \
  CHECK_BRANDING_FILES="$WORK/files" \
  CHECK_BRANDING_ALLOWLIST="$WORK/tree/Configuration/branding-allowlist.txt" \
    bash "$GATE" > "$WORK/gate-output" 2>&1
}

# run_gate <allowlist-contents> — with the trailing newline an editor would leave.
#
# This is the seam the shared harness calls: expect_clean/expect_failure pass their trailing
# arguments straight through, and for this gate the only argument is the allowlist. Cases that
# name no allowlist get an empty one.
run_gate() {
  run_gate_verbatim "${1:-}
"
}

printf '\n=== the correct brand is never a violation ===\n'

reset_fixture
write_file "NotBoringNotch/NotBoringNotchApp.swift" "//  NotBoringNotch"
write_file "NotBoringNotch/XPCHelper/NotBoringNotchXPCHelperProtocol.swift" \
  "struct NotBoringNotchXPCHelperProtocol {}"
write_file "NotBoringNotch/models/Constants.swift" 'let module = "Not_Boring_Notch"'
write_file "NotBoringNotch/XPCHelper/XPCHelperClient.swift" \
  'private let serviceName = "com.allenreder.notboringnotch.NotBoringNotchXPCHelper"'
write_file "README.md" "Not Boring Notch, cloned from not-boring-notch"
write_file "RELEASING.md" 'gh release create vX.Y.Z "build/release/Not-Boring-Notch-vX.Y.Z.dmg"'
expect_clean "every spelling of the correct brand passes, including the substrings that contain the old one"

printf '\n=== the old brand in a file is a violation ===\n'

reset_fixture
write_file "boringNotch/models/TintPipeline.swift" "//  boringNotch"
expect_failure "the old directory name in a file header"

reset_fixture
write_file "NotBoringNotch/legacy.swift" "//  created for BoringNotch"
expect_failure "the old target name in prose"

reset_fixture
write_file "docs/agents/issue-tracker.md" "upstream lives at TheBoredTeam/boring.notch"
expect_failure "the upstream repository slug"

reset_fixture
write_file ".github/ISSUE_TEMPLATE/bug-report.yml" "      label: Boring Notch Version"
expect_failure "the old brand as two words"

reset_fixture
write_file "XPCHelper/Protocol.swift" '"theboringteam.boringnotch.BoringNotchXPCHelper"'
expect_failure "the old team prefix"

reset_fixture
write_file "NotBoringNotch/components/Notch/BoringHeader.swift" "struct BoringHeader {}"
expect_failure "a bare Boring type name"

# The correct brand is PascalCase. The old lowerCamel casing is not a spelling to tolerate:
# a `notBoringNotch/` directory would be the only one in the tree shaped that way.
reset_fixture
write_file "notBoringNotch/legacy-casing.swift" "//  notBoringNotch"
expect_failure "the old lowerCamel casing, which would leave an inconsistently-cased directory"

printf '\n=== the old brand in a path is a violation ===\n'

reset_fixture
write_file "BoringNotch/NotBoringNotchApp.swift" "clean"
expect_failure "the old directory in the path itself"
expect_reported "the violation report names the offending path" "BoringNotch/NotBoringNotchApp.swift"

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/theboringteam.imageset/Contents.json" "clean"
expect_failure "an old-brand asset name in the path itself"

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/logo2.imageset/BoringNotch icon.png" "clean"
expect_failure "an old-brand file name containing a space"

printf '\n=== the allowlist exempts what it names, and nothing else ===\n'

reset_fixture
write_file "LICENSE" "Copyright (C) 2024-2025 TheBoredTeam and contributors (boring.notch)"
expect_clean "a line entry exempts the fragment it names" \
  'line|LICENSE|(boring.notch)|upstream copyright notice'

reset_fixture
write_file "AGENTS.md" "issues live on AllenReder/boring.notch"
expect_failure "a line entry for another file does not exempt this one" \
  'line|LICENSE|(boring.notch)|upstream copyright notice'

reset_fixture
write_file "LICENSE" "upstream (boring.notch) — and also boringNotch"
expect_failure "an entry does not swallow a second violation on the same line" \
  'line|LICENSE|(boring.notch)|upstream copyright notice'

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/theboringteam.imageset/Contents.json" "clean"
expect_clean "a path entry exempts the path it names" \
  'path|NotBoringNotch/Assets.xcassets/theboringteam.imageset/*|-|upstream logo, no code references'

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/theboringteam.imageset/Contents.json" "// boringNotch"
expect_failure "a path entry does not exempt the file's contents" \
  'path|NotBoringNotch/Assets.xcassets/theboringteam.imageset/*|-|upstream logo, no code references'

# `file` entries are for the handful of files made of the token itself — the gate's own
# patterns and its fixtures — so that they are excused in the allowlist, with a reason, rather
# than by a list hidden in the script.
reset_fixture
write_file "scripts/check-branding.sh" "the token, by construction: boringNotch"
write_file "NotBoringNotch/models/Constants.swift" "//  boringNotch"
expect_failure "a file entry for one path does not exempt another" \
  'file|scripts/check-branding.sh|-|defines the token'

reset_fixture
write_file "scripts/check-branding.sh" "the token, by construction: boringNotch"
expect_clean "a file entry exempts the contents of the file it names" \
  'file|scripts/check-branding.sh|-|defines the token'

reset_fixture
write_file "boringNotch/Old.swift" "//  boringNotch"
expect_clean "a file entry exempts a path that carries the token too" \
  'file|boringNotch/*|-|a directory made of the token'

reset_fixture
write_file "NotBoringNotch/models/Constants.swift" "//  boringNotch"
expect_clean "comments and blank lines in the allowlist are ignored" \
  '# this line explains the next one
line|NotBoringNotch/models/Constants.swift|//  boringNotch|still on the old path in this commit

'

reset_fixture
write_file "LICENSE" "Copyright (C) 2024-2025 TheBoredTeam and contributors (boring.notch)"
run_gate_verbatim 'line|LICENSE|(boring.notch)|upstream copyright notice'
status=$?
if [ "$status" -eq 0 ]; then
  printf '✅ an allowlist whose last line has no newline is still honoured\n'
  passed=$((passed + 1))
else
  printf '❌ an allowlist whose last line has no newline is still honoured\n'
  printf '   expected a clean run, got exit %s:\n' "$status"
  sed 's/^/   /' "$WORK/gate-output"
  failed=$((failed + 1))
fi

printf '\n=== the gate sees files that are not committed yet ===\n'

# Every case above hands the gate its file list. This one does not: it is about how the gate
# builds that list, so it needs a repository of its own to build it from.
UNTRACKED_REPO="$WORK/untracked-repo"
rm -rf "$UNTRACKED_REPO"
mkdir -p "$UNTRACKED_REPO"
git -C "$UNTRACKED_REPO" init -q
printf 'clean\n' > "$UNTRACKED_REPO/committed.md"
git -C "$UNTRACKED_REPO" add committed.md
printf '//  boringNotch\n' > "$UNTRACKED_REPO/not-added-yet.swift"

CHECK_BRANDING_ROOT="$UNTRACKED_REPO" bash "$GATE" > "$WORK/gate-output" 2>&1
status=$?
if [ "$status" -eq 1 ]; then
  printf '✅ a file that has not been git added is still scanned\n'
  passed=$((passed + 1))
else
  printf '❌ a file that has not been git added is still scanned\n'
  printf '   expected exit 1, got %s:\n' "$status"
  sed 's/^/   /' "$WORK/gate-output"
  failed=$((failed + 1))
fi
expect_reported "the report names the file that is not committed yet" "not-added-yet.swift"

report_and_exit
