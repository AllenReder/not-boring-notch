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
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
run_gate() {
  run_gate_verbatim "$1
"
}

expect_clean() {  # expect_clean <description> [allowlist]
  run_gate "${2:-}"
  local status=$?
  if [ "$status" -eq 0 ]; then
    printf '✅ %s\n' "$1"
    passed=$((passed + 1))
  else
    printf '❌ %s\n   expected a clean run, got exit %s:\n' "$1" "$status"
    sed 's/^/   /' "$WORK/gate-output"
    failed=$((failed + 1))
  fi
}

expect_violation() {  # expect_violation <description> [allowlist]
  run_gate "${2:-}"
  local status=$?
  if [ "$status" -eq 1 ]; then
    printf '✅ %s\n' "$1"
    passed=$((passed + 1))
  else
    printf '❌ %s\n   expected exit 1, got %s:\n' "$1" "$status"
    sed 's/^/   /' "$WORK/gate-output"
    failed=$((failed + 1))
  fi
}

# Asserts against the output of the most recent run_gate.
expect_reported() {  # expect_reported <description> <substring>
  if grep -qF -- "$2" "$WORK/gate-output"; then
    printf '✅ %s\n' "$1"
    passed=$((passed + 1))
  else
    printf '❌ %s\n   the report never mentions %s:\n' "$1" "$2"
    sed 's/^/   /' "$WORK/gate-output"
    failed=$((failed + 1))
  fi
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
write_file "notBoringNotch/legacy-casing.swift" "//  notBoringNotch"
expect_clean "every spelling of the correct brand passes, including the substrings that contain the old one"

printf '\n=== the old brand in a file is a violation ===\n'

reset_fixture
write_file "boringNotch/models/TintPipeline.swift" "//  boringNotch"
expect_violation "the old directory name in a file header"

reset_fixture
write_file "NotBoringNotch/legacy.swift" "//  created for BoringNotch"
expect_violation "the old target name in prose"

reset_fixture
write_file "docs/agents/issue-tracker.md" "upstream lives at TheBoredTeam/boring.notch"
expect_violation "the upstream repository slug"

reset_fixture
write_file ".github/ISSUE_TEMPLATE/bug-report.yml" "      label: Boring Notch Version"
expect_violation "the old brand as two words"

reset_fixture
write_file "XPCHelper/Protocol.swift" '"theboringteam.boringnotch.BoringNotchXPCHelper"'
expect_violation "the old team prefix"

reset_fixture
write_file "NotBoringNotch/components/Notch/BoringHeader.swift" "struct BoringHeader {}"
expect_violation "a bare Boring type name"

printf '\n=== the old brand in a path is a violation ===\n'

reset_fixture
write_file "BoringNotch/NotBoringNotchApp.swift" "clean"
expect_violation "the old directory in the path itself"
expect_reported "the violation report names the offending path" "BoringNotch/NotBoringNotchApp.swift"

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/theboringteam.imageset/Contents.json" "clean"
expect_violation "an old-brand asset name in the path itself"

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/logo2.imageset/BoringNotch icon.png" "clean"
expect_violation "an old-brand file name containing a space"

printf '\n=== the allowlist exempts what it names, and nothing else ===\n'

reset_fixture
write_file "LICENSE" "Copyright (C) 2024-2025 TheBoredTeam and contributors (boring.notch)"
expect_clean "a line entry exempts the fragment it names" \
  'line|LICENSE|(boring.notch)|upstream copyright notice'

reset_fixture
write_file "AGENTS.md" "issues live on AllenReder/boring.notch"
expect_violation "a line entry for another file does not exempt this one" \
  'line|LICENSE|(boring.notch)|upstream copyright notice'

reset_fixture
write_file "LICENSE" "upstream (boring.notch) — and also boringNotch"
expect_violation "an entry does not swallow a second violation on the same line" \
  'line|LICENSE|(boring.notch)|upstream copyright notice'

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/theboringteam.imageset/Contents.json" "clean"
expect_clean "a path entry exempts the path it names" \
  'path|NotBoringNotch/Assets.xcassets/theboringteam.imageset/*|-|upstream logo, no code references'

reset_fixture
write_file "NotBoringNotch/Assets.xcassets/theboringteam.imageset/Contents.json" "// boringNotch"
expect_violation "a path entry does not exempt the file's contents" \
  'path|NotBoringNotch/Assets.xcassets/theboringteam.imageset/*|-|upstream logo, no code references'

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

printf '\n%d passed, %d failed\n' "$passed" "$failed"

if [ "$failed" -ne 0 ]; then
  exit 1
fi
