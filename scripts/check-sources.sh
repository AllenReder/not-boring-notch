#!/usr/bin/env bash
#
# check-sources.sh — fails when a source file is in the project's source tree and not in the
# project.
#
# The build cannot tell you. A file that is not registered in project.pbxproj is not compiled, and
# a compiler has nothing to say about a file it never received: no error, no warning, no elapsed
# time. Registering a file is something a person does by hand, in Xcode, and forgetting it stays
# invisible until something calls a name from the missing file — and then the error arrives four
# minutes into a Release build, pointing at a line that looks correct:
#
#     error: cannot find 'Logger' in scope
#
# This has happened here. `ShelfStorage.swift` was written, unit-tested, and green in Debug
# before a Release build reported that it had never been compiled. `utils/Logger.swift` — 76
# lines, a LogCategory enum, a View extension — was committed by upstream and never registered by
# anybody, so no build this project has ever run has seen it. Four more files are in that state,
# and finding them took grepping the project file by hand.
#
# What this checks
#
#   Every tracked .swift file under SOURCE_ROOTS is either named in a Sources build phase of
#   project.pbxproj, or inside a directory Xcode synchronizes wholesale (a
#   PBXFileSystemSynchronizedRootGroup, which registers the directory rather than the files in it).
#
# Untracked-and-not-ignored files count too, so a source file nobody has `git add`ed yet is
# checked while the mistake is still cheap. CI checks out a clean tree, so this changes nothing
# there.
#
# What this does not check
#
#   * Files outside SOURCE_ROOTS. `Tests/*Tests.swift` are standalone runners with their own
#     @main, compiled one at a time by scripts/run-tests.sh; `scripts/*.swift` are tools run
#     through swiftc. Neither belongs to a target, and neither is claimed here. The claim stops at
#     the edge of the source roots.
#   * Resources, entitlements, asset catalogs. Those are reached through build settings
#     (INFOPLIST_FILE, CODE_SIGN_ENTITLEMENTS, ASSETCATALOG_COMPILER_APPICON_NAME) rather than
#     through a build phase, so a rule that covered both would be pretending they work alike.
#   * A registered file that is not on disk. The build does catch that one — "Build input file
#     cannot be found" — which is the asymmetry worth keeping in mind: the build polices what you
#     registered; this polices what you did not.
#
# Exit status: 0 when every source is in the project, 1 otherwise — including when this gate
# cannot read the project file, because a gate that cannot check must not report a clean tree.
#
# Tested by Tests/SourcesGateTests.sh. The environment overrides at the top exist so that test can
# point the gate at a fixture tree.
#
set -euo pipefail

ROOT="${CHECK_SOURCES_ROOT:-$(git rev-parse --show-toplevel)}"
FILELIST="${CHECK_SOURCES_FILES:-}"

# The directories the app is built from. Every tracked .swift file under one of these has to be in
# the project. Adding a source root is a deliberate act — a new target's directory, say — and it
# belongs in this list, where a reviewer will see it.
SOURCE_ROOTS=(
  "NotBoringNotch"
  "NotBoringNotchXPCHelper"
)

# shellcheck source=lib/xcode-project.sh
. "$(dirname "$0")/lib/xcode-project.sh"
PBXPROJ="$(pbxproject_in "$ROOT")"

# The lines between a section's Begin and End markers, which is where a name has to appear for the
# claim about it to be true. Matching the whole file instead would let a name be "in Sources"
# somewhere Xcode never reads.
section_of() {  # section_of <file> <section-name>
  awk -v name="$2" '
    $0 ~ "/\\* Begin " name " section \\*/" { inside = 1 }
    $0 ~ "/\\* End " name " section \\*/"   { inside = 0 }
    inside
  ' "$1"
}

# Directories Xcode registers wholesale. Xcode writes each as `path = <dir>;` relative to the group
# holding it; this matches on the name of a path component, which is what makes
# `NotBoringNotch/private/` and `NotBoringNotchXPCHelper/` work under one rule.
SYNC_GROUP_DIRS="$(section_of "$PBXPROJ" "PBXFileSystemSynchronizedRootGroup" |
  sed -n 's/.*[[:space:]]path = \([^;]*\);.*/\1/p')"

# The names a Sources build phase compiles, taken from the entry Xcode writes for each one:
#
#     AAA000000000000000000001 /* Foo.swift in Sources */ = {isa = PBXBuildFile; ...};
#
# Those `/* ... */` names are Xcode's own output, not something this gate adds. Should a future
# Xcode stop writing them, the guard below fails this gate rather than passing everything.
COMPILED="$(section_of "$PBXPROJ" "PBXSourcesBuildPhase" |
  sed -n 's|.*/\* \(.*\) in Sources \*/.*|\1|p')"

if [ -z "$COMPILED" ]; then
  printf '❌ could not read any sources out of %s\n\n' "${PBXPROJ#$ROOT/}"
  printf 'This gate looks for the names in a PBXSourcesBuildPhase section, where Xcode writes them as\n'
  printf '"/* <name> in Sources */". It found none, so it cannot tell a registered file from an\n'
  printf 'unregistered one. Fix this gate before trusting its silence.\n'
  exit 1
fi

# A source root that is not there means the gate is watching nothing, and would go on reporting a
# clean tree while the app moved somewhere else.
MISSING_ROOTS=""
for root in "${SOURCE_ROOTS[@]}"; do
  [ -d "$ROOT/$root" ] || MISSING_ROOTS="${MISSING_ROOTS}   ${root}"$'\n'
done

if [ -n "$MISSING_ROOTS" ]; then
  printf '❌ these source roots are not there:\n\n%s\n' "$MISSING_ROOTS"
  printf 'The app is not built from these directories any more, so nothing under them was checked.\n'
  printf 'Point SOURCE_ROOTS at where the sources went.\n'
  exit 1
fi

TMP_FILELIST="$(mktemp)"
trap 'rm -f "$TMP_FILELIST"' EXIT

if [ -n "$FILELIST" ]; then
  cp "$FILELIST" "$TMP_FILELIST"
else
  (
    cd "$ROOT"
    git ls-files '*.swift'
    git ls-files --others --exclude-standard '*.swift'
  ) | LC_ALL=C sort -u > "$TMP_FILELIST"
fi

# True when some component of the path names a synchronized directory.
in_sync_group() {  # in_sync_group <repo-relative-path>
  local path="$1" dir component
  local IFS='/'
  # shellcheck disable=SC2086
  for component in $path; do
    while IFS= read -r dir; do
      [ -n "$dir" ] && [ "$component" = "$dir" ] && return 0
    done <<< "$SYNC_GROUP_DIRS"
  done
  return 1
}

VIOLATIONS=""
CHECKED="$(mktemp)"
trap 'rm -f "$TMP_FILELIST" "$CHECKED"' EXIT

# The files this gate makes a claim about: tracked, under a source root, and not inside a
# directory Xcode registers wholesale.
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in *.swift) ;; *) continue ;; esac

  relative="${path#"$ROOT"/}"
  in_root=1
  for root in "${SOURCE_ROOTS[@]}"; do
    case "$relative" in "$root"/*) in_root=0 ;; esac
  done
  [ "$in_root" -eq 0 ] || continue
  in_sync_group "$relative" && continue

  printf '%s\n' "$relative" >> "$CHECKED"
 done < "$TMP_FILELIST"

count_named() {  # count_named <newline-separated-paths> <basename>
  awk -v b="$2" '{ n = split($0, parts, "/"); if (parts[n] == b) c++ } END { print c + 0 }' <<< "$1"
}

# Compared per basename, not per path. The project records basenames: one
# `Constants.swift in Sources` entry accounts for one file called Constants.swift, and there can be
# more than one file with that name — this repository has two `NotBoringNotchXPCHelperProtocol.swift`
# today. A plain "does this name appear" test would let a second file pass on the strength of the
# first one's entry, which is the quietest way for a gate like this to stop working.
while IFS= read -r basename; do
  [ -n "$basename" ] || continue
  n_checked="$(count_named "$(cat "$CHECKED")" "$basename")"
  n_compiled="$(count_named "$COMPILED" "$basename")"
  [ "$n_checked" -gt "$n_compiled" ] || continue

  while IFS= read -r path; do
    [ "$(basename "$path")" = "$basename" ] && VIOLATIONS="${VIOLATIONS}   ${path}"$'\n'
  done < "$CHECKED"

  if [ "$n_compiled" -eq 0 ]; then
    VIOLATIONS="${VIOLATIONS}       the project lists nothing called ${basename}"$'\n\n'
  else
    VIOLATIONS="${VIOLATIONS}       the project lists ${n_compiled} called ${basename}; ${n_checked} are here"$'\n\n'
  fi
done < <(while IFS= read -r p; do basename "$p"; done < "$CHECKED" | LC_ALL=C sort -u)

if [ -z "$VIOLATIONS" ]; then
  ROOT_LIST="$(printf '%s, ' "${SOURCE_ROOTS[@]}")"
  printf '✅ every tracked source under %s is in the project\n' "${ROOT_LIST%, }"
  exit 0
fi

printf '❌ source files that no build compiles:\n\n%s\n' "$VIOLATIONS"
printf 'These are inside the project'"'"'s source roots and not inside the project, so no build has\n'
printf 'ever compiled them. Nothing has complained, and nothing will: a compiler has no complaint\n'
printf 'about a file it never received.\n\n'
printf 'In Xcode, add each file to the target (File > Add Files to "NotBoringNotch"). If a file is\n'
printf 'not part of the app, move it out of %s/ so that it stops looking like one.\n' "${SOURCE_ROOTS[0]}"
exit 1
