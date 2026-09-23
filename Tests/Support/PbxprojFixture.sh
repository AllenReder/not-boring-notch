#
# A project.pbxproj fixture, for the runners that test the version scripts.
#
# Sourced by Tests/VersionGateTests.sh and Tests/SetVersionTests.sh — which is why it is not named
# *Tests.sh, since scripts/run-tests.sh discovers Tests/*Tests.sh and would otherwise try to run
# this file on its own.
#
# The shape matters. scripts/check-version.sh reads these settings out of the file and
# scripts/set-version.sh writes them back into it, so a fixture that does not look like what
# Xcode emits would let both pass while neither worked.
#

# The project is called `Any.xcodeproj` on purpose: both scripts have to find it rather than be
# told where it is, or renaming the real project would mean editing the tests too.
PBXPROJ_FIXTURE_PROJECT="Any.xcodeproj"

# write_pbxproj <repo-dir> <"marketing/build" ...>
write_pbxproj() {
  local repo="$1" spec="$2" pair
  mkdir -p "$repo/$PBXPROJ_FIXTURE_PROJECT"
  : > "$repo/$PBXPROJ_FIXTURE_PROJECT/project.pbxproj"
  for pair in $spec; do
    {
      printf '\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
      printf '\t\t\t\tCURRENT_PROJECT_VERSION = %s;\n' "${pair#*/}"
      printf '\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
      printf '\t\t\t\tMARKETING_VERSION = %s;\n' "${pair%%/*}"
    } >> "$repo/$PBXPROJ_FIXTURE_PROJECT/project.pbxproj"
  done
}

fixture_pbxproj() {  # fixture_pbxproj <repo-dir>
  printf '%s/%s/project.pbxproj' "$1" "$PBXPROJ_FIXTURE_PROJECT"
}

# How many times the fixture states a setting with a given value.
#
# Read straight out of the file rather than through a script's own reader: a wrong reader would
# otherwise make its own test agree with it.
occurrences_of() {  # occurrences_of <repo-dir> <setting> <value>
  grep -cE "^[[:space:]]*$2 = $3;" "$(fixture_pbxproj "$1")" || true
}
