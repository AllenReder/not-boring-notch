#!/usr/bin/env bash
#
# check-version.sh — fails when the version settings in the Xcode project disagree.
#
# RELEASING.md asks the maintainer to bump MARKETING_VERSION and CURRENT_PROJECT_VERSION by
# hand, in every target and both configurations, and to keep all of them in step. Nothing
# enforced that until this script, and it has already gone wrong once: a Debug build
# reported a version which was not the released one, and there was no way to tell the two
# apart from inside the app. The gate is one grep over the project file — and it is the
# reason that promise no longer lives only in a paragraph.
#
#   ./scripts/check-version.sh                 check the invariant RELEASING.md step 2 asks for
#   ./scripts/check-version.sh --expect-tag    also assert the tag being released matches
#
# --expect-tag belongs to step 6 of RELEASING.md, next to `git tag`. CI runs the plain form:
# a branch is legitimately between a version bump and its tag, so comparing against a tag
# there would fail on a healthy tree.
#
# Exit status: 0 when the copies agree, 1 when they do not, 2 for an unknown argument.
#
# Tested by Tests/VersionGateTests.sh.
#
set -euo pipefail

REPO="${CHECK_VERSION_REPO:-$(git rev-parse --show-toplevel)}"

# shellcheck source=lib/xcode-project.sh
. "$(dirname "$0")/lib/xcode-project.sh"

EXPECT_TAG=0
for argument in "$@"; do
  case "$argument" in
    --expect-tag) EXPECT_TAG=1 ;;
    *) printf 'unknown argument: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

PBXPROJ="$(pbxproject_in "$REPO")" || exit 1

# Values of a build setting, in file order, without the surrounding quotes.
values_of() {
  sed -n "s/^[[:space:]]*$1 = \(.*\);[[:space:]]*$/\1/p" "$PBXPROJ" | tr -d '"'
}

# One line per distinct value, with how many times it occurs.
tally() {
  printf '%s\n' "$1" | sort | uniq -c | sed 's/^ *//'
}

RELEASE_VALUES="$(values_of MARKETING_VERSION)"
BUILD_VALUES="$(values_of CURRENT_PROJECT_VERSION)"

RELEASE_COUNT="$(printf '%s' "$RELEASE_VALUES" | grep -c . || true)"
BUILD_COUNT="$(printf '%s' "$BUILD_VALUES" | grep -c . || true)"
RELEASE_DISTINCT="$(printf '%s\n' "$RELEASE_VALUES" | sort -u | grep -c . || true)"
BUILD_DISTINCT="$(printf '%s\n' "$BUILD_VALUES" | sort -u | grep -c . || true)"

# RELEASING.md: each setting appears once per target per configuration, and this project has
# two targets in two configurations. Adding a target raises this floor; removing a copy is
# exactly what this catches.
MINIMUM_COPIES=4

problems=""

if [ "$RELEASE_COUNT" -lt "$MINIMUM_COPIES" ]; then
  problems="${problems}   MARKETING_VERSION appears ${RELEASE_COUNT} time(s); RELEASING.md expects at least ${MINIMUM_COPIES} — every target in both configurations.
"
fi

if [ "$BUILD_COUNT" -lt "$MINIMUM_COPIES" ]; then
  problems="${problems}   CURRENT_PROJECT_VERSION appears ${BUILD_COUNT} time(s); RELEASING.md expects at least ${MINIMUM_COPIES} — every target in both configurations.
"
fi

if [ "$RELEASE_DISTINCT" -gt 1 ]; then
  problems="${problems}   MARKETING_VERSION does not agree with itself:
$(tally "$RELEASE_VALUES" | sed 's/^/      /')
"
fi

if [ "$BUILD_DISTINCT" -gt 1 ]; then
  problems="${problems}   CURRENT_PROJECT_VERSION does not agree with itself:
$(tally "$BUILD_VALUES" | sed 's/^/      /')
"
fi

if [ "$EXPECT_TAG" -eq 1 ]; then
  TAG="$(git -C "$REPO" describe --tags --exact-match HEAD 2>/dev/null || true)"
  RELEASE_VERSION="$(printf '%s\n' "$RELEASE_VALUES" | head -1)"

  if [ -z "$TAG" ]; then
    problems="${problems}   --expect-tag was asked for, but HEAD is not tagged; step 6 of RELEASING.md tags before it publishes.
"
  elif [ "$TAG" != "v${RELEASE_VERSION}" ]; then
    problems="${problems}   the tag is ${TAG}, but the app was built as v${RELEASE_VERSION}.
"
  fi
fi

if [ -z "$problems" ]; then
  printf '✅ MARKETING_VERSION %s (build %s) in %s places, all in step\n' \
    "$(printf '%s\n' "$RELEASE_VALUES" | head -1)" \
    "$(printf '%s\n' "$BUILD_VALUES" | head -1)" \
    "$RELEASE_COUNT"
  exit 0
fi

printf '❌ the version settings disagree:\n\n%s' "$problems"
printf '\nBump every copy together — see RELEASING.md, step 2.\n'
exit 1
