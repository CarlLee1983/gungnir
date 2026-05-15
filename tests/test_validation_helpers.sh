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

# -- Source mode: ci::require_file (spec §5.1, §8.1) ----------------------

TMP_DIR="$(make_temp_dir)"
EXISTING_FILE="$TMP_DIR/present.txt"
MISSING_FILE="$TMP_DIR/absent.txt"
EXISTING_DIR="$TMP_DIR/some-dir"
printf 'hello\n' >"$EXISTING_FILE"
mkdir -p "$EXISTING_DIR"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG '$EXISTING_FILE'"
assert_status 0 "$RUN_STATUS" "source require_file present exits 0"
assert_eq "" "$RUN_STDOUT" "source require_file present writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_file present writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG '$MISSING_FILE'"
assert_status 1 "$RUN_STATUS" "source require_file missing exits 1"
assert_contains "$RUN_STDERR" "CONFIG" "source require_file missing names CONFIG"
assert_not_contains "$RUN_STDERR" "$MISSING_FILE" \
  "source require_file missing does not echo the path"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG '$MISSING_FILE' 'run build.sh first'"
assert_status 1 "$RUN_STATUS" "source require_file with hint still exits 1"
assert_contains "$RUN_STDERR" "CONFIG" "source require_file hint still names CONFIG"
assert_contains "$RUN_STDERR" "run build.sh first" \
  "source require_file hint appears in stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file DIR_AS_FILE '$EXISTING_DIR'"
assert_status 1 "$RUN_STATUS" "source require_file rejects directory path"
assert_contains "$RUN_STDERR" "DIR_AS_FILE" "source require_file rejects dir, names NAME"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG"
assert_status 64 "$RUN_STATUS" "source require_file missing args exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_file" \
  "source require_file missing args prints usage"

# -- Source mode: ci::require_dir (spec §5.2, §8.1) -----------------------

MISSING_DIR="$TMP_DIR/absent-dir"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING '$EXISTING_DIR'"
assert_status 0 "$RUN_STATUS" "source require_dir present exits 0"
assert_eq "" "$RUN_STDOUT" "source require_dir present writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_dir present writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING '$MISSING_DIR'"
assert_status 1 "$RUN_STATUS" "source require_dir missing exits 1"
assert_contains "$RUN_STDERR" "STAGING" "source require_dir missing names STAGING"
assert_not_contains "$RUN_STDERR" "$MISSING_DIR" \
  "source require_dir missing does not echo the path"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING '$MISSING_DIR' 'run build.sh first'"
assert_status 1 "$RUN_STATUS" "source require_dir with hint still exits 1"
assert_contains "$RUN_STDERR" "run build.sh first" \
  "source require_dir hint appears in stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir FILE_AS_DIR '$EXISTING_FILE'"
assert_status 1 "$RUN_STATUS" "source require_dir rejects regular file"
assert_contains "$RUN_STDERR" "FILE_AS_DIR" "source require_dir rejects file, names NAME"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING"
assert_status 64 "$RUN_STATUS" "source require_dir missing args exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_dir" \
  "source require_dir missing args prints usage"

finish_tests
