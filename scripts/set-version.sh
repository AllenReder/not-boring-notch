#!/usr/bin/env bash
#
# set-version.sh — write the version a release is being cut as.
#
# RELEASING.md asks for MARKETING_VERSION and CURRENT_PROJECT_VERSION to be bumped together, in
# every target and both configurations: four places each, eight values. Nothing used to be able
# to tell whether all of them had been written. check-version.sh only tells you *afterwards*, and
# the failure it catches is a build that reports a version nobody released.
#
# This writes them, and then runs that check, because the check's predicate is exactly this
# script's postcondition.
#
#   ./scripts/set-version.sh 1.0.3 4
#
# Exit status: 0 when the version was written and the copies agree, 1 when the project does not
# look the way this expects, 2 for bad arguments.
#
# Tested by Tests/SetVersionTests.sh. SET_VERSION_REPO exists so that test can point this script
# and its self-check at a fixture tree.
#
set -euo pipefail

REPO="${SET_VERSION_REPO:-$(git rev-parse --show-toplevel)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/xcode-project.sh
. "$SCRIPT_DIR/lib/xcode-project.sh"

usage() {
  printf 'usage: %s <marketing-version> <build-number>\n' "$(basename "$0")" >&2
  printf '   eg: %s 1.0.3 4\n' "$(basename "$0")" >&2
  printf '\nWrites every copy of both settings in project.pbxproj, then checks them.\n' >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
MARKETING="$1"
BUILD="$2"

# A version the DMG is named after, and a build number that goes up. Refusing these here costs
# nothing; finding out from a tagged release does not.
case "$MARKETING" in
  ''|*[!0-9.]*) printf '❌ marketing version must be digits and dots, got "%s"\n' "$MARKETING" >&2; exit 2 ;;
esac
case "$BUILD" in
  ''|*[!0-9]*) printf '❌ build number must be digits, got "%s"\n' "$BUILD" >&2; exit 2 ;;
esac

PBXPROJ="$(pbxproject_in "$REPO")" || exit 1

values_of() {  # values_of <setting>
  sed -n "s|^[[:space:]]*$1 = \([^;]*\);.*|\1|p" "$PBXPROJ"
}

count_values() {  # count_values <setting>
  values_of "$1" | grep -c . || true
}

count_equal_to() {  # count_equal_to <setting> <value> — fixed string, so a "." in a version is a dot
  values_of "$1" | grep -Fxc -- "$2" || true
}

# Both settings are checked before either is written. Writing one and then discovering the other
# is nowhere would leave the project worse than it started: half a new version, and nothing in
# the file to say which half.
for setting in MARKETING_VERSION CURRENT_PROJECT_VERSION; do
  if [ "$(count_values "$setting")" -eq 0 ]; then
    printf '❌ %s appears nowhere in %s\n' "$setting" "$PBXPROJ" >&2
    printf '   Nothing was written; the project is unchanged.\n' >&2
    exit 1
  fi
done

write() {  # write <setting> <value> <how-many-expected>
  local setting="$1" value="$2" expected="$3" previous written
  previous="$(values_of "$setting" | head -1)"

  # A temp file rather than `sed -i`: the two dialects of that flag disagree about whether it
  # takes an argument, and this script runs wherever the release is cut.
  sed "s|^\([[:space:]]*$setting = \)[^;]*;|\1$value;|" "$PBXPROJ" > "$PBXPROJ.set-version"
  mv "$PBXPROJ.set-version" "$PBXPROJ"

  written="$(count_equal_to "$setting" "$value")"
  printf '   %-24s %s -> %s   (%s of %s place(s))\n' "$setting" "$previous" "$value" "$written" "$expected"
}

printf 'writing %s into %s\n' "$MARKETING" "$(basename "$(dirname "$PBXPROJ")")/project.pbxproj"
write MARKETING_VERSION "$MARKETING" "$(count_values MARKETING_VERSION)"
write CURRENT_PROJECT_VERSION "$BUILD" "$(count_values CURRENT_PROJECT_VERSION)"

printf '\n'
CHECK_VERSION_REPO="$REPO" "$SCRIPT_DIR/check-version.sh"

printf '\nNow: git commit -am "chore(release): bump version to %s"\n' "$MARKETING"
