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

# expect_status <expected-status> <description> <runner> [runner arguments...]
#
# A `runner` is a function the sourcing file defines. `run_gate` is the ordinary one; a case that
# needs a different invocation — a fixture tree the usual one cannot reach — names its own, which
# is why this exists rather than the two wrappers below being the whole interface. Without it,
# such a case has to re-implement the pass/fail bookkeeping, and that is how the two runners
# drifted apart the first time.
expect_status() {
  local expected="$1" description="$2" runner="$3"
  shift 3
  "$runner" "$@"
  local status=$?
  if [ "$status" -eq "$expected" ]; then
    printf '✅ %s\n' "$description"
    passed=$((passed + 1))
  else
    printf '❌ %s\n   expected exit %s, got %s:\n' "$description" "$expected" "$status"
    sed 's/^/   /' "$WORK/gate-output"
    failed=$((failed + 1))
  fi
}

expect_clean() {  # expect_clean <description> [gate arguments...]
  local description="$1"; shift
  expect_status 0 "$description" run_gate "$@"
}

expect_failure() {  # expect_failure <description> [gate arguments...]
  local description="$1"; shift
  expect_status 1 "$description" run_gate "$@"
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
