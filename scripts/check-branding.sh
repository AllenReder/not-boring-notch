#!/usr/bin/env bash
#
# check-branding.sh — fails when the old brand is still in the tree.
#
# This project used to be `boring.notch`. It is now Not Boring Notch, and the rename has to
# stay done: upstream is still brought in by hand (ADR 0004), so an old-name reference can
# arrive in a cherry-picked commit at any time, quietly.
#
# The token is searched case-insensitively for the six letters "boring", but the correct
# brand contains that token three different ways:
#
#   NotBoringNotch      contains      BoringNotch
#   Not Boring Notch    contains      Boring Notch
#   not-boring-notch    contains      boring-notch
#
# So those spellings are removed from each line before it is tested (see LEGIT_FORMS).
# Without that step the gate would fail on the brand it exists to protect.
#
# Both contents and paths are checked, because `boring.m4a` and
# `Assets.xcassets/theboringteam.imageset/` carry the old name in the file name alone.
#
# An occurrence is a violation unless Configuration/branding-allowlist.txt exempts it.
#
# Exit status: 0 when clean, 1 when the old brand was found.
#
# Tested by Tests/BrandingGateTests.sh. The environment overrides at the top of this file
# exist so that test can point the gate at a fixture tree.
#
set -euo pipefail

ROOT="${CHECK_BRANDING_ROOT:-$(git rev-parse --show-toplevel)}"
ALLOWLIST="${CHECK_BRANDING_ALLOWLIST:-$ROOT/Configuration/branding-allowlist.txt}"
FILELIST="${CHECK_BRANDING_FILES:-}"

# Files that must contain the forbidden token by construction: the gate's own patterns, its
# fixtures, and the allowlist. Exempting them here rather than in the allowlist keeps the
# allowlist about the repository instead of about the gate.
SELF_EXEMPT=(
  "scripts/check-branding.sh"
  "Tests/BrandingGateTests.sh"
  "Configuration/branding-allowlist.txt"
)

# The brand this repository renames *to*. Each is stripped before a line is tested.
# `Not-Boring-Notch` is the DMG file name RELEASING.md builds, and it contains `Boring`.
LEGIT_FORMS=(
  "Not_Boring_Notch"
  "Not-Boring-Notch"
  "NotBoringNotch"
  "notBoringNotch"
  "notboringnotch"
  "not-boring-notch"
  "Not Boring Notch"
)

# 0 when the string still carries the token, with any casing.
has_brand() {
  case "$1" in
    *[Bb][Oo][Rr][Ii][Nn][Gg]*) return 0 ;;
  esac
  return 1
}

# Echo the string with every spelling of the correct brand removed.
strip_legit_forms() {
  local s="$1" form
  for form in "${LEGIT_FORMS[@]}"; do
    s="${s//"$form"/}"
  done
  printf '%s' "$s"
}

TMP_FILELIST="$(mktemp)"
trap 'rm -f "$TMP_FILELIST"' EXIT

if [ -n "$FILELIST" ]; then
  cp "$FILELIST" "$TMP_FILELIST"
else
  ( cd "$ROOT" && git ls-files ) > "$TMP_FILELIST"
fi

# Allowlist entries, split by kind. `path` entries exempt a path; `line` entries exempt
# occurrences of a fragment in files whose path matches the glob.
PATH_GLOBS=()
LINE_GLOBS=()
LINE_FRAGMENTS=()

if [ -f "$ALLOWLIST" ]; then
  # The trailing `|| [ -n "$kind" ]` matters: `read` returns non-zero when the last line
  # has no terminating newline, and without it that line would be silently dropped —
  # turning an exemption into a violation for anybody whose editor omits the final `\n`.
  while IFS='|' read -r kind glob fragment reason || [ -n "$kind" ]; do
    case "$kind" in
      ''|\#*) continue ;;
      path) PATH_GLOBS+=("${glob:-}") ;;
      line)
        if [ -z "${fragment:-}" ] || [ "$fragment" = "-" ]; then
          printf '⚠️  allowlist entry needs a fragment: %s|%s\n' "$kind" "$glob" >&2
          continue
        fi
        LINE_GLOBS+=("${glob:-}")
        LINE_FRAGMENTS+=("$fragment")
        ;;
      *)
        printf '⚠️  unknown allowlist kind "%s" for %s\n' "$kind" "${glob:-}" >&2
        ;;
    esac
  done < "$ALLOWLIST"
fi

is_self_exempt() {
  local p="$1" exempt
  for exempt in "${SELF_EXEMPT[@]}"; do
    [ "$p" = "$exempt" ] && return 0
  done
  return 1
}

path_is_allowlisted() {
  local p="$1" i=0
  while [ "$i" -lt "${#PATH_GLOBS[@]}" ]; do
    case "$p" in ${PATH_GLOBS[$i]}) return 0 ;; esac
    i=$((i + 1))
  done
  return 1
}

# The fragments this path is allowed to contain, joined by 0x1C for awk. Always starts with
# a separator, which awk's split turns into a leading empty field that is then ignored.
fragments_allowlisted_for() {
  local p="$1" i=0 out=""
  while [ "$i" -lt "${#LINE_GLOBS[@]}" ]; do
    case "$p" in ${LINE_GLOBS[$i]}) out="${out}$(printf '\034')${LINE_FRAGMENTS[$i]}" ;; esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

VIOLATIONS="$(mktemp)"
trap 'rm -f "$TMP_FILELIST" "$VIOLATIONS"' EXIT

while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ -d "$path" ] && continue
  is_self_exempt "$path" && continue

  # The path itself: `BoringNotch/App.swift`, `Assets.xcassets/theboringteam.imageset/…`
  if has_brand "$(strip_legit_forms "$path")" && ! path_is_allowlisted "$path"; then
    printf '%s:1:%s\n' "$path" "the path itself still carries the old brand" >> "$VIOLATIONS"
  fi

  [ -f "$ROOT/$path" ] || continue
  # `-I` makes grep treat a binary file as having no match, which is how we detect one.
  grep -Iq '' "$ROOT/$path" || continue

  awk -v path="$path" \
      -v legit="$(printf '%s' "${LEGIT_FORMS[0]}"; printf '\034%s' "${LEGIT_FORMS[@]:1}")" \
      -v exempt="$(fragments_allowlisted_for "$path")" '
    function strip(s, lit,    i) {
      while ((i = index(s, lit)) > 0) s = substr(s, 1, i - 1) substr(s, i + length(lit))
      return s
    }
    BEGIN {
      n_legit = split(legit, L, "\034")
      n_exempt = split(exempt, E, "\034")
    }
    {
      line = $0
      for (i = 1; i <= n_legit; i++) if (L[i] != "") line = strip(line, L[i])
      for (i = 1; i <= n_exempt; i++) if (E[i] != "") line = strip(line, E[i])
      if (tolower(line) ~ /boring/) printf "%s:%d:%s\n", path, FNR, $0
    }
  ' "$ROOT/$path" >> "$VIOLATIONS"
done < "$TMP_FILELIST"

if [ ! -s "$VIOLATIONS" ]; then
  printf '✅ no occurrences of the old brand outside Configuration/branding-allowlist.txt\n'
  exit 0
fi

printf '❌ the old brand is still in the tree:\n\n'
sed 's/^/   /' "$VIOLATIONS"
printf '\nEach of these is either a rename that has not happened yet, or an exemption that\n'
printf 'belongs in Configuration/branding-allowlist.txt with a reason.\n'
exit 1
