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

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::is_true"
assert_status 64 "$RUN_STATUS" "is_true requires args"

run_capture bash -c "export T1=1; source '$ROOT_DIR/ci-toolkit'; ci::is_true T1"
assert_status 0 "$RUN_STATUS" "is_true succeeds for 1"

run_capture bash -c "export T2=true; source '$ROOT_DIR/ci-toolkit'; ci::is_true T2"
assert_status 0 "$RUN_STATUS" "is_true succeeds for true"

run_capture bash -c "export F1=0; source '$ROOT_DIR/ci-toolkit'; ci::is_true F1"
assert_status 1 "$RUN_STATUS" "is_true fails for 0"

run_capture bash -c "export F2=false; source '$ROOT_DIR/ci-toolkit'; ci::is_true F2"
assert_status 1 "$RUN_STATUS" "is_true fails for false"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::is_true MISSING"
assert_status 1 "$RUN_STATUS" "is_true fails for missing var"

finish_tests
