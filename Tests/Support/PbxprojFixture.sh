#
# A project.pbxproj fixture, for the runners that test the version and source scripts.
#
# Sourced by Tests/VersionGateTests.sh, Tests/SetVersionTests.sh and Tests/SourcesGateTests.sh —
# which is why it is not named *Tests.sh, since scripts/run-tests.sh discovers Tests/*Tests.sh and
# would otherwise try to run this file on its own.
#
# The shape matters. scripts/check-version.sh reads these settings out of the file, and
# scripts/set-version.sh writes them back into it, so a fixture that does not look like what
# Xcode emits would let both pass while neither worked. The same goes for the sources phase that
# scripts/check-sources.sh reads, which register_sources below writes in Xcode's own shape.
#

# The project is called `Any.xcodeproj` on purpose: both scripts have to find it rather than be
# told where it is, or renaming the real project would mean editing the tests too.
PBXPROJ_FIXTURE_PROJECT="Any.xcodeproj"

# ensure_pbxproj <repo-dir>
#
# The project directory, without the file: the writers below append to project.pbxproj and cannot
# create a directory on the way, so a fixture that only registers sources would otherwise be
# written to a path that is not there and quietly never read.
ensure_pbxproj() {
  mkdir -p "$1/$PBXPROJ_FIXTURE_PROJECT"
}

# write_pbxproj <repo-dir> <"marketing/build" ...>
write_pbxproj() {
  local repo="$1" spec="$2" pair
  ensure_pbxproj "$repo"
  : > "$(fixture_pbxproj "$repo")"
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

# register_sources <repo-dir> <swift-basename>...
#
# The part of project.pbxproj that says which files a target compiles, in the shape Xcode emits: a
# PBXBuildFile and a PBXFileReference per file, and one PBXSourcesBuildPhase listing the build
# files. scripts/check-sources.sh reads the names out of that phase, so a fixture without it would
# let the gate pass while reading nothing at all.
#
# Called with no names it writes the phase empty, which is the shape of a project file the gate
# cannot get an answer out of.
register_sources() {
  local repo="$1"; shift
  local name n=0
  ensure_pbxproj "$repo"
  {
    printf '/* Begin PBXBuildFile section */\n'
    for name in "$@"; do
      n=$((n + 1))
      printf '\t\tBBBB0000000000000000%04d /* %s in Sources */ = {isa = PBXBuildFile; fileRef = CCCC0000000000000000%04d /* %s */; };\n' \
        "$n" "$name" "$n" "$name"
    done
    printf '/* End PBXBuildFile section */\n'

    printf '/* Begin PBXFileReference section */\n'
    n=0
    for name in "$@"; do
      n=$((n + 1))
      printf '\t\tCCCC0000000000000000%04d /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = "<group>"; };\n' \
        "$n" "$name" "$name"
    done
    printf '/* End PBXFileReference section */\n'

    printf '/* Begin PBXSourcesBuildPhase section */\n'
    printf '\t\tDDDD00000000000000000001 /* Sources */ = {\n'
    printf '\t\t\tisa = PBXSourcesBuildPhase;\n'
    printf '\t\t\tbuildActionMask = 2147483647;\n'
    printf '\t\t\tfiles = (\n'
    n=0
    for name in "$@"; do
      n=$((n + 1))
      printf '\t\t\t\tBBBB0000000000000000%04d /* %s in Sources */,\n' "$n" "$name"
    done
    printf '\t\t\t);\n'
    printf '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
    printf '\t\t};\n'
    printf '/* End PBXSourcesBuildPhase section */\n'
  } >> "$(fixture_pbxproj "$repo")"
}

# synchronize_directory <repo-dir> <directory-name>
#
# A PBXFileSystemSynchronizedRootGroup: how Xcode registers a directory rather than the files in it,
# so that adding a file to that directory needs no project edit.
synchronize_directory() {
  local repo="$1" dir="$2"
  ensure_pbxproj "$repo"
  {
    printf '/* Begin PBXFileSystemSynchronizedRootGroup section */\n'
    printf '\t\tDDDD00000000000000000002 /* %s */ = {isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {}; explicitFolders = (); path = %s; sourceTree = "<group>"; };\n' \
      "$dir" "$dir"
    printf '/* End PBXFileSystemSynchronizedRootGroup section */\n'
  } >> "$(fixture_pbxproj "$repo")"
}

# How many times the fixture states a setting with a given value.
#
# Read straight out of the file rather than through a script's own reader: a wrong reader would
# otherwise make its own test agree with it. Compared as text, not as a pattern — `grep -E` would
# let the value `1.0.2` match `1x0x2`, which is exactly the sort of agreement this file exists to
# rule out.
occurrences_of() {  # occurrences_of <repo-dir> <setting> <value>
  awk -v setting="$2" -v value="$3" '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (index(line, setting " = ") != 1) next
      line = substr(line, length(setting) + 4)
      sub(/;.*$/, "", line)
      if (line == value) count++
    }
    END { print count + 0 }
  ' "$(fixture_pbxproj "$1")"
}
