#!/usr/bin/env bash
#
# Tests for scripts/set-version.sh.
#
# The script exists so that nobody has to count "four places, eight values". The cases below are
# about the two ways that can go wrong: writing a value somewhere it does not belong, and
# reporting success without having written it everywhere.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Support/GateTestHarness.sh
. "$(dirname "$0")/Support/GateTestHarness.sh"
# shellcheck source=Support/PbxprojFixture.sh
. "$(dirname "$0")/Support/PbxprojFixture.sh"
GATE="$ROOT/scripts/set-version.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"

passed=0
failed=0

reset_repo() {  # reset_repo <"marketing/build" ...>
  rm -rf "$REPO"
  mkdir -p "$REPO"
  write_pbxproj "$REPO" "$1"
}

# The harness calls this with the gate's own arguments; here that is the pair the release is
# being cut as.
run_gate() {
  SET_VERSION_REPO="$REPO" bash "$GATE" "$@" > "$WORK/gate-output" 2>&1
}

expect_marketing() {  # expect_marketing <description> <value> <count>
  expect_equal "$1" "$(occurrences_of "$REPO" MARKETING_VERSION "$2")" "$3"
}

expect_build() {  # expect_build <description> <value> <count>
  expect_equal "$1" "$(occurrences_of "$REPO" CURRENT_PROJECT_VERSION "$2")" "$3"
}

printf '\n=== writing the version into every place it appears ===\n'

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/3"
expect_clean "writes both settings" 1.0.3 4
expect_marketing "all four copies carry the new version" 1.0.3 4
expect_marketing "and none still carries the old one" 1.0.2 0
expect_build "the build number moved with it" 4 4
expect_build "and the old build number is gone" 3 0
expect_reported "it ends by running the check that has to pass" "in 4 places, all in step"

printf '\n=== and nowhere else ===\n'

expect_equal "the settings beside them are untouched" \
  "$(occurrences_of "$REPO" CODE_SIGN_STYLE Automatic)" 4
expect_equal "including the ones that look like build settings" \
  "$(occurrences_of "$REPO" GENERATE_INFOPLIST_FILE YES)" 4

printf '\n=== refusing arguments that are not a version ===\n'

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/3"
expect_status 2 "a marketing version that is not digits and dots" run_gate 1.0.x 4
expect_status 2 "a build number that is not a number" run_gate 1.0.3 beta
expect_status 2 "no arguments at all" run_gate
expect_status 2 "only one argument" run_gate 1.0.3
expect_marketing "and nothing was written for any of them" 1.0.3 0

printf '\n=== refusing a project it cannot write completely ===\n'

# A project stating only one of the two settings. The script has to notice before writing
# anything, or it leaves half a new version behind with nothing in the file to say which half.
rm -rf "$REPO"
mkdir -p "$REPO/$PBXPROJ_FIXTURE_PROJECT"
printf '\t\t\t\tMARKETING_VERSION = 1.0.2;\n' > "$(fixture_pbxproj "$REPO")"
expect_status 1 "a setting that is not in the project at all" run_gate 1.0.3 4
expect_marketing "it wrote nothing" 1.0.3 0
expect_marketing "and left the value it found" 1.0.2 1

printf '\n=== the check it runs is the one that has to pass ===\n'

# Two copies rather than four. The script writes what it finds, and then refuses to call that
# done, because the shape it wrote into is not the shape RELEASING.md describes.
reset_repo "1.0.2/3 1.0.2/3"
expect_status 1 "a project without the four copies is not reported as done" run_gate 1.0.3 4
expect_marketing "it still wrote the copies it found" 1.0.3 2

printf '\n=== running it again with the version it already has ===\n'

reset_repo "1.0.3/4 1.0.3/4 1.0.3/4 1.0.3/4"
expect_clean "is not an error" 1.0.3 4
expect_marketing "and leaves the four copies alone" 1.0.3 4

printf '\n=== a value the project quotes ===\n'

# A project file may quote a setting's value, and both scripts that read one have to agree about
# what it says. The writer's report is where the disagreement showed: it echoed the value it had
# replaced back with its quotes still on.
reset_repo '"1.0.2"/"3" "1.0.2"/"3" "1.0.2"/"3" "1.0.2"/"3"'
expect_clean "a quoted value is written like any other" 1.0.3 4
expect_marketing "all four copies carry the new version" 1.0.3 4
expect_build "the build number moved with it" 4 4
expect_not_reported "and the value it replaced is not echoed with its quotes" '"1.0.2" ->'

printf '\n=== the fixture reader compares text, not patterns ===\n'

# This runner reads the fixture itself rather than through the script's reader, so that a wrong
# reader cannot make its own test agree with it — which means this reader has to be right itself.
# Matched as a pattern, `1.0.2` counts as present in `1x0x2`.
reset_repo "1x0x2/3"
expect_equal "a value that is not the one asked for is not counted" \
  "$(occurrences_of "$REPO" MARKETING_VERSION 1.0.2)" 0
expect_equal "and the one that is, is" \
  "$(occurrences_of "$REPO" MARKETING_VERSION 1x0x2)" 1

report_and_exit
