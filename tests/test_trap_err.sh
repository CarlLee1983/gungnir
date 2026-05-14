#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/assert.sh
source "$ROOT_DIR/tests/assert.sh"

run_capture() {
  local stdout_file stderr_file status
  stdout_file="$(make_temp_dir)/stdout"
  stderr_file="$(make_temp_dir)/stderr"
  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  RUN_STDOUT="$(cat "$stdout_file")"
  RUN_STDERR="$(cat "$stderr_file")"
  RUN_STATUS="$status"
}

set -e

# -- Source mode (spec §5.3 #1–#5) ----------------------------------------

# #1, #2: ERR trap fires on `false`, captures exit code and BASH_COMMAND
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; false; true"
assert_contains "$RUN_STDERR" "[error] command failed (exit=1) at" \
  "trap_err prints error prefix and exit code on false"
assert_contains "$RUN_STDERR" "false" \
  "trap_err captures BASH_COMMAND (false)"

# #3: ERR trap fires inside a function and reports the function name
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; f() { false; }; f; true"
assert_contains "$RUN_STDERR" "in f" \
  "trap_err reports FUNCNAME when ERR fires inside a function"

# #4: Without set -e, an echo after the failing command still runs
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; false; echo after-failure"
assert_contains "$RUN_STDOUT" "after-failure" \
  "trap_err does not call exit; subsequent commands run"

# #5: Two consecutive ci::trap_err calls — one error line per failure
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; ci::trap_err; false; true"
error_lines=$(printf '%s\n' "$RUN_STDERR" | grep -c '\[error\] command failed' || true)
if [[ "$error_lines" -eq 1 ]]; then
  pass "trap_err idempotent: second install replaces first (one error line per failure)"
else
  fail "trap_err idempotent: expected 1 error line, got $error_lines"
fi

# -- CLI mode (spec §5.3 #6) ----------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" trap-err
assert_status 64 "$RUN_STATUS" "CLI trap-err exits 64"
assert_contains "$RUN_STDERR" "only effective in source mode" \
  "CLI trap-err explains it is a source-mode helper"

finish_tests
