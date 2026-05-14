#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/assert.sh
source "$ROOT_DIR/tests/assert.sh"

# shellcheck disable=SC2034
# Reason: RUN_STDOUT/RUN_STDERR/RUN_STATUS are read by assert_* helpers in
# the calling scope; ShellCheck cannot follow that across files. This file
# only happens to read RUN_STDERR + RUN_STATUS, but we keep the trio so the
# capture helper matches the other tests in this directory.
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

# -- Parse errors (spec §10 #5–#8, #12) -----------------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay -1 -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay -1"
assert_contains "$RUN_STDERR" "--delay" "source retry --delay -1 mentions --delay"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay abc -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay abc"
assert_contains "$RUN_STDERR" "--delay" "source retry --delay abc mentions --delay"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay with no value"
assert_contains "$RUN_STDERR" "--delay requires a value" "source retry --delay missing-value message"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --bogus -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects unknown --bogus"
assert_contains "$RUN_STDERR" "unknown option: --bogus" "source retry --bogus message"

run_capture "$ROOT_DIR/ci-toolkit" retry 2 --delay foo -- true
assert_status 64 "$RUN_STATUS" "CLI retry rejects --delay foo"

# -- Regression: no flags, no `--` (spec §10 #13) -------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 false"
assert_status 1 "$RUN_STATUS" "source retry without flags or -- returns command status"
assert_contains "$RUN_STDERR" "Attempt 1/3 failed" "source retry without flags still warns on attempt 1"

# -- Regression: explicit `--`, no flags (spec §10 #9) --------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 -- false"
assert_status 1 "$RUN_STATUS" "source retry with bare -- returns command status"
assert_contains "$RUN_STDERR" "Attempt 3/3 failed" "source retry with bare -- attempts all three"

finish_tests
