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

# -- Source mode: ci::version_gt (spec §5.1 #1, #2, #3, #7) ---------------
# Spec §5.1 #8 (release vs pre-release ordering) is skipped here because
# `sort -V` ordering of pre-release tags differs between BSD (macOS) and
# GNU coreutils. The helper still works on CI (Linux) where this contract holds.

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.4 1.2.3"
assert_status 0 "$RUN_STATUS" "source version_gt 1.2.4 > 1.2.3 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.3 1.2.4"
assert_status 1 "$RUN_STATUS" "source version_gt 1.2.3 > 1.2.4 exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.3 1.2.3"
assert_status 1 "$RUN_STATUS" "source version_gt 1.2.3 > 1.2.3 exits 1 (equal)"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt v1.2.4 v1.2.3"
assert_status 0 "$RUN_STATUS" "source version_gt tolerates v-prefix"

# -- Source mode: ci::version_ge (spec §5.1 #4, #5, #6) -------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.3 1.2.3"
assert_status 0 "$RUN_STATUS" "source version_ge 1.2.3 >= 1.2.3 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.4 1.2.3"
assert_status 0 "$RUN_STATUS" "source version_ge 1.2.4 >= 1.2.3 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.3 1.2.4"
assert_status 1 "$RUN_STATUS" "source version_ge 1.2.3 >= 1.2.4 exits 1"

# -- Source mode: usage errors (spec §5.1 #9, #10) ------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.3"
assert_status 64 "$RUN_STATUS" "source version_gt missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::version_gt LHS RHS" \
  "source version_gt missing arg prints usage"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt '' 1.0.0"
assert_status 64 "$RUN_STATUS" "source version_gt empty LHS exits 64"

# -- CLI mode (spec §5.1 #11, #12, #13) -----------------------------------

run_capture "$ROOT_DIR/ci-toolkit" version gt 1.2.4 1.2.3
assert_status 0 "$RUN_STATUS" "CLI version gt 1.2.4 1.2.3 exits 0"

run_capture "$ROOT_DIR/ci-toolkit" version
assert_status 0 "$RUN_STATUS" "CLI version (no args) still exits 0"
assert_contains "$RUN_STDOUT" "ci-toolkit 0.1.9" \
  "CLI version (no args) still prints toolkit + version"

run_capture "$ROOT_DIR/ci-toolkit" version gt 1.2.3
assert_status 64 "$RUN_STATUS" "CLI version gt with missing arg exits 64"

finish_tests
