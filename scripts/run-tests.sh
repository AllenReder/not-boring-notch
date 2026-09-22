#!/usr/bin/env bash
#
# Runs the standalone test runners in Tests/.
#
# Those runners are not part of an Xcode target (each has its own @main entry point),
# so every one of them is compiled on its own against just the sources it exercises.
#
# Adding a runner: create Tests/<Name>Tests.swift and give it a first-line declaration
# of the sources it needs, e.g.
#
#   // SOURCES: boringNotch/models/TintPipeline.swift
#
# No change to this script is needed. A runner without a SOURCES line is reported and
# skipped rather than failing the suite, so adding a test in one branch cannot break
# another branch's build.
#
#   ./scripts/run-tests.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

passed=0
failed=0
skipped=0

for test_file in Tests/*Tests.swift; do
  name="$(basename "$test_file" .swift)"

  # Everything after the "SOURCES:" marker on the first matching line.
  read -r -a sources <<< "$(sed -n 's|^// SOURCES: *||p' "$test_file" | head -1)"

  printf '\n=== %s ===\n' "$name"

  if [ "${#sources[@]}" -eq 0 ]; then
    printf '⚠️  no "// SOURCES:" declaration; skipping\n'
    skipped=$((skipped + 1))
    continue
  fi

  missing=0
  for source in "${sources[@]}"; do
    if [ ! -f "$source" ]; then
      printf '❌ declared source is missing: %s\n' "$source"
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    failed=$((failed + 1))
    continue
  fi

  printf 'swiftc -o %s %s %s\n' "$name" "$test_file" "${sources[*]}"

  if ! swiftc -o "$BUILD_DIR/$name" "$test_file" "${sources[@]}"; then
    printf '❌ did not compile\n'
    failed=$((failed + 1))
    continue
  fi

  if "$BUILD_DIR/$name"; then
    printf '✅ %s passed\n' "$name"
    passed=$((passed + 1))
  else
    printf '❌ assertions failed\n'
    failed=$((failed + 1))
  fi
done

printf '\n%d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"

if [ "$failed" -ne 0 ]; then
  exit 1
fi
