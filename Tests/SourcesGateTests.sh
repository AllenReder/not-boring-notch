#!/usr/bin/env bash
#
# Tests for scripts/check-sources.sh.
#
# The gate answers one question — is every tracked source under the app's source roots in the
# project? — and the cases here are the ways that answer can be wrong. Two directions:
#
#   * a violation it does not report: a file inside a directory Xcode synchronizes wholesale, a
#     file outside the source roots, a second file whose basename the project has already seen;
#   * a clean tree it does not report: a source root that moved, a project file it cannot read.
#
# The second group matters most. A gate whose silence is load-bearing must fail when it cannot
# check, rather than report a clean tree it never established.
#
# The assertion helpers are in Tests/Support/GateTestHarness.sh, shared with the other gate
# runners so that "expect a violation" means one thing in all of them.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Support/GateTestHarness.sh
. "$(dirname "$0")/Support/GateTestHarness.sh"
# shellcheck source=Support/PbxprojFixture.sh
. "$(dirname "$0")/Support/PbxprojFixture.sh"
GATE="$ROOT/scripts/check-sources.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0

# The two source roots exist in every fixture, empty, so that only the case about a missing root
# fails for that reason. The gate lists them itself and refuses to run when one is not there.
reset_fixture() {
  rm -rf "$WORK/tree"
  mkdir -p "$WORK/tree/NotBoringNotch" "$WORK/tree/NotBoringNotchXPCHelper"
  : > "$WORK/files"
}

# write_source <repo-relative-path>
write_source() {
  mkdir -p "$WORK/tree/$(dirname "$1")"
  printf '// %s\n' "$1" > "$WORK/tree/$1"
  printf '%s\n' "$1" >> "$WORK/files"
}

run_gate() {
  CHECK_SOURCES_ROOT="$WORK/tree" CHECK_SOURCES_FILES="$WORK/files" \
    bash "$GATE" > "$WORK/gate-output" 2>&1
}

# For the one case about how the gate builds its own file list, which cannot be handed one.
run_gate_without_filelist() {
  ( cd "$1" && CHECK_SOURCES_ROOT="$1" bash "$GATE" > "$WORK/gate-output" 2>&1 )
}

printf '\n=== a source the project lists is clean ===\n'

reset_fixture
write_source "NotBoringNotch/NotBoringNotchApp.swift"
register_sources "$WORK/tree" NotBoringNotchApp.swift
expect_clean "one source, registered"
expect_reported "and the gate says what it checked" "every tracked source under"

printf '\n=== a source the project does not list is a violation ===\n'

reset_fixture
write_source "NotBoringNotch/NotBoringNotchApp.swift"
write_source "NotBoringNotch/utils/Logger.swift"
register_sources "$WORK/tree" NotBoringNotchApp.swift
expect_failure "a file nothing registers"
expect_reported "the violation names the file" "NotBoringNotch/utils/Logger.swift"
expect_reported "and says why it is a violation" "the project lists nothing called Logger.swift"

printf '\n=== a synchronized directory needs no per-file entry ===\n'

reset_fixture
write_source "NotBoringNotch/NotBoringNotchApp.swift"
write_source "NotBoringNotch/private/CGSSpace.swift"
register_sources "$WORK/tree" NotBoringNotchApp.swift
synchronize_directory "$WORK/tree" private
expect_clean "a file in a directory Xcode registers wholesale"

reset_fixture
write_source "NotBoringNotch/NotBoringNotchApp.swift"
write_source "NotBoringNotchXPCHelper/main.swift"
register_sources "$WORK/tree" NotBoringNotchApp.swift
synchronize_directory "$WORK/tree" NotBoringNotchXPCHelper
expect_clean "and a whole source root registered that way"

printf '\n=== files outside the source roots are not the gate'"'"'s business ===\n'

reset_fixture
write_source "NotBoringNotch/NotBoringNotchApp.swift"
write_source "Tests/SomeTests.swift"
write_source "scripts/some-tool.swift"
register_sources "$WORK/tree" NotBoringNotchApp.swift
expect_clean "a standalone test runner and a standalone script"

printf '\n=== a basename the project has already seen is counted, not assumed ===\n'

reset_fixture
write_source "NotBoringNotch/models/Constants.swift"
write_source "NotBoringNotch/other/Constants.swift"
register_sources "$WORK/tree" Constants.swift
expect_failure "two files with one registered basename"
expect_reported "the report names both files" "NotBoringNotch/models/Constants.swift"
expect_reported "the report names both files" "NotBoringNotch/other/Constants.swift"
expect_reported "and gives the count it compared" "the project lists 1 called Constants.swift; 2 are here"

reset_fixture
write_source "NotBoringNotch/models/Constants.swift"
write_source "NotBoringNotch/other/Constants.swift"
register_sources "$WORK/tree" Constants.swift Constants.swift
expect_clean "and the same two files registered twice"

printf '\n=== a source root that is not there ===\n'

reset_fixture
write_source "NotBoringNotch/NotBoringNotchApp.swift"
register_sources "$WORK/tree" NotBoringNotchApp.swift
rm -rf "$WORK/tree/NotBoringNotchXPCHelper"
expect_failure "a source root that moved"
expect_reported "the report names the root" "NotBoringNotchXPCHelper"

printf '\n=== a project file the gate cannot read ===\n'

reset_fixture
write_source "NotBoringNotch/NotBoringNotchApp.swift"
register_sources "$WORK/tree"
expect_failure "a sources phase with nothing in it"
expect_reported "the report says it could not read the project" "could not read any sources"

printf '\n=== a file nobody has added to git yet ===\n'

reset_fixture
write_pbxproj "$WORK/tree" "1.0.0/1"
write_source "NotBoringNotch/NotBoringNotchApp.swift"
register_sources "$WORK/tree" NotBoringNotchApp.swift
git -c init.defaultBranch=main init -q "$WORK/tree"
( cd "$WORK/tree" && git add -A )
mkdir -p "$WORK/tree/NotBoringNotch/utils"
printf '// NotBoringNotch/utils/Logger.swift\n' > "$WORK/tree/NotBoringNotch/utils/Logger.swift"
expect_status 1 "an untracked source is checked before it is committed" run_gate_without_filelist "$WORK/tree"
expect_reported "the violation names it" "NotBoringNotch/utils/Logger.swift"

report_and_exit
