#
# Shared harness for the shell runners that test the gates in scripts/.
#
# Sourced by Tests/BrandingGateTests.sh and Tests/VersionGateTests.sh — which is why it is not
# named *Tests.sh, since scripts/run-tests.sh discovers Tests/*Tests.sh and would otherwise try
# to run this file on its own.
#
# The sourcing file must set:
#
#   WORK       a scratch directory that already exists and is cleaned up by its own trap
#   run_gate   runs the gate under test, takes that gate's own arguments, and leaves the
#              gate's combined output in $WORK/gate-output
#
# and must initialise `passed` and `failed` to 0 and end with report_and_exit.
#

expect_clean() {  # expect_clean <description> [gate arguments...]
  local description="$1"; shift
  run_gate "$@"
  local status=$?
  if [ "$status" -eq 0 ]; then
    printf '✅ %s\n' "$description"
    passed=$((passed + 1))
  else
    printf '❌ %s\n   expected a clean run, got exit %s:\n' "$description" "$status"
    sed 's/^/   /' "$WORK/gate-output"
    failed=$((failed + 1))
  fi
}

expect_failure() {  # expect_failure <description> [gate arguments...]
  local description="$1"; shift
  run_gate "$@"
  local status=$?
  if [ "$status" -eq 1 ]; then
    printf '✅ %s\n' "$description"
    passed=$((passed + 1))
  else
    printf '❌ %s\n   expected exit 1, got %s:\n' "$description" "$status"
    sed 's/^/   /' "$WORK/gate-output"
    failed=$((failed + 1))
  fi
}

# Asserts against the output of the most recent run_gate.
expect_reported() {  # expect_reported <description> <substring>
  if grep -qF -- "$2" "$WORK/gate-output"; then
    printf '✅ %s\n' "$1"
    passed=$((passed + 1))
  else
    printf '❌ %s\n   the report never mentions %s:\n' "$1" "$2"
    sed 's/^/   /' "$WORK/gate-output"
    failed=$((failed + 1))
  fi
}

report_and_exit() {
  printf '\n%d passed, %d failed\n' "$passed" "$failed"
  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
}
