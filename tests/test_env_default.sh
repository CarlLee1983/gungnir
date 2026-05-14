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
  # shellcheck disable=SC2034
  RUN_STDOUT="$(cat "$stdout_file")"
  # shellcheck disable=SC2034
  RUN_STDERR="$(cat "$stderr_file")"
  RUN_STATUS="$status"
}

set -e

# source mode
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::env_default"
assert_status 64 "$RUN_STATUS" "env_default requires args"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::env_default TEST_VAR_1 'default-val'; echo \"val:\$TEST_VAR_1\""
assert_status 0 "$RUN_STATUS" "env_default succeeds"
assert_contains "$RUN_STDOUT" "val:default-val" "env_default sets value if unset"

run_capture bash -c "export TEST_VAR_2='original'; source '$ROOT_DIR/ci-toolkit'; ci::env_default TEST_VAR_2 'new'; echo \"val:\$TEST_VAR_2\""
assert_status 0 "$RUN_STATUS" "env_default succeeds when set"
assert_contains "$RUN_STDOUT" "val:original" "env_default preserves existing value"

run_capture bash -c "TEST_VAR_3=''; source '$ROOT_DIR/ci-toolkit'; ci::env_default TEST_VAR_3 'default'; echo \"val:\$TEST_VAR_3\""
assert_status 0 "$RUN_STATUS" "env_default succeeds when empty"
assert_contains "$RUN_STDOUT" "val:default" "env_default overrides empty string"

# CLI mode
run_capture "$ROOT_DIR/ci-toolkit" env default
assert_status 64 "$RUN_STATUS" "CLI env default requires args"

run_capture "$ROOT_DIR/ci-toolkit" env default MISSING_VAR 'fallback'
assert_status 0 "$RUN_STATUS" "CLI env default succeeds"
assert_eq "fallback" "$RUN_STDOUT" "CLI env default prints fallback when missing"

run_capture bash -c "export EXISTING_VAR='present'; '$ROOT_DIR/ci-toolkit' env default EXISTING_VAR 'ignored'"
assert_status 0 "$RUN_STATUS" "CLI env default succeeds with existing"
assert_eq "present" "$RUN_STDOUT" "CLI env default prints existing value"

finish_tests
