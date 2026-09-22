#!/usr/bin/env bash
#
# Tests for scripts/check-version.sh.
#
# The invariant is the one RELEASING.md asks a human to keep by hand: every target, in both
# configurations, carries the same MARKETING_VERSION and the same CURRENT_PROJECT_VERSION.
# That hand-kept promise has already failed once — a build reporting a version which was not
# the released one — so the cases below are the ones that failure would have tripped.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=Support/GateTestHarness.sh
. "$(dirname "$0")/Support/GateTestHarness.sh"
GATE="$ROOT/scripts/check-version.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"

passed=0
failed=0

# write_pbxproj <repo-dir> <"marketing/build" ...>
#
# The settings are written in the shape Xcode writes them, one pair per build configuration.
write_pbxproj() {
  local repo="$1" spec="$2" pair
  mkdir -p "$repo/Any.xcodeproj"
  : > "$repo/Any.xcodeproj/project.pbxproj"
  for pair in $spec; do
    {
      printf '\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
      printf '\t\t\t\tCURRENT_PROJECT_VERSION = %s;\n' "${pair#*/}"
      printf '\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
      printf '\t\t\t\tMARKETING_VERSION = %s;\n' "${pair%%/*}"
    } >> "$repo/Any.xcodeproj/project.pbxproj"
  done
}

# A repository whose name says nothing about the brand: the gate has to find the project
# rather than be told where it is, or the rename would have to edit this script too.
reset_repo() {  # reset_repo <"marketing/build" ...>
  rm -rf "$REPO"
  mkdir -p "$REPO"
  write_pbxproj "$REPO" "$1"
}

commit_and_tag() {  # commit_and_tag [tag]
  git -C "$REPO" init -q
  git -C "$REPO" -c user.email=t@example.com -c user.name=t add -A
  git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -qm fixture
  if [ -n "${1:-}" ]; then git -C "$REPO" tag "$1"; fi
}

run_gate() {  # run_gate [args...]
  CHECK_VERSION_REPO="$REPO" bash "$GATE" "$@" > "$WORK/gate-output" 2>&1
}

printf '\n=== the four copies are in step ===\n'

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/3"
expect_clean "every copy agreeing passes"
expect_reported "the passing report names the version it checked" "1.0.2"

printf '\n=== the four copies disagree ===\n'

reset_repo "1.0.2/3 1.0.2/3 1.0.1/3 1.0.2/3"
expect_failure "a version bumped in only some of the copies"
expect_reported "the failure names the stale version" "1.0.1"
expect_reported "the failure names the version the others carry" "1.0.2"

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/2"
expect_failure "a build number bumped in only some of the copies"

printf '\n=== copies went missing ===\n'

reset_repo "1.0.2/3 1.0.2/3"
expect_failure "fewer copies than the two targets and two configurations RELEASING.md names"

reset_repo ""
expect_failure "no version setting at all"

printf '\n=== usage ===\n'

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/3"
expect_status 2 "an unknown argument is a usage error, not a verdict on the versions" run_gate --wat

printf '\n=== --expect-tag, the release step ===\n'

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/3"
commit_and_tag "v1.0.2"
expect_clean "a tag matching the built version passes" --expect-tag

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/3"
commit_and_tag "v9.9.9"
expect_failure "a tag that does not match the built version" --expect-tag
expect_reported "the failure names the tag" "v9.9.9"
expect_reported "the failure names the built version" "1.0.2"

reset_repo "1.0.2/3 1.0.2/3 1.0.2/3 1.0.2/3"
commit_and_tag
expect_failure "no tag at HEAD, so there is nothing to publish against" --expect-tag

report_and_exit
