#
# Finding the Xcode project, for the scripts that need it.
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
