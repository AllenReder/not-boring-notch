#
# Finding the Xcode project, and reading settings out of it, for the scripts that need it.
#
# Sourced by scripts/check-version.sh and scripts/set-version.sh. It exists because both need
# the same answer to the same question, and because neither may hardcode the project's name:
# renaming the project is a thing that happens in this repository, and the scripts that police
# the version numbers should not have to be edited when it does.
#

# Echoes the path to the single project.pbxproj under <repo>, or explains why there isn't one.
pbxproject_in() {
  local repo="$1" candidate
  local projects=()

  for candidate in "$repo"/*.xcodeproj; do
    [ -d "$candidate" ] && projects+=("$candidate")
  done

  if [ "${#projects[@]}" -ne 1 ]; then
    printf '❌ expected exactly one .xcodeproj in %s, found %s\n' "$repo" "${#projects[@]}" >&2
    return 1
  fi

  if [ ! -f "${projects[0]}/project.pbxproj" ]; then
    printf '❌ no project.pbxproj in %s\n' "${projects[0]}" >&2
    return 1
  fi

  printf '%s' "${projects[0]}/project.pbxproj"
}

# Echoes the values <project.pbxproj> states for <setting>, one per line, in file order, with the
# surrounding quotes removed.
#
# Both scripts read their settings through this rather than each carrying its own sed, because two
# readers of one line format drift. These had: one matched a value only on a line ending in `;`,
# the other took everything up to the first `;`, and only one removed the quotes a project file is
# allowed to put around a value. Neither difference had bitten — both were waiting to, and the
# second one already reached the release report, which echoed a value back with its quotes on.
# This is the union: up to the first `;`, quotes off. `pbxproject_in` resolves a repository and
# this takes the file it resolved, so a caller that has already checked the project is there does
# not have to find it twice.
values_of() {  # values_of <project.pbxproj> <setting>
  sed -n "s|^[[:space:]]*$2 = \([^;]*\);.*|\1|p" "$1" | tr -d '"'
}
