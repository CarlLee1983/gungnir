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

# -- Source mode: ci::require_match (spec §5.3, §8.1, §10) ---------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match DEPLOY_USER arcade '^[A-Za-z0-9._-]+$'"
assert_status 0 "$RUN_STATUS" "source require_match valid exits 0"
assert_eq "" "$RUN_STDOUT" "source require_match valid writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_match valid writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match DEPLOY_USER 'SECRET LEAK CANARY' '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'"
assert_status 1 "$RUN_STATUS" "source require_match invalid exits 1"
assert_contains "$RUN_STDERR" "DEPLOY_USER" \
  "source require_match invalid names DEPLOY_USER"
assert_contains "$RUN_STDERR" "[A-Za-z0-9._-]+" \
  "source require_match invalid prints description"
assert_not_contains "$RUN_STDERR" "SECRET LEAK CANARY" \
  "source require_match invalid does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match DEPLOY_USER 'SECRET LEAK CANARY' '^[A-Za-z0-9._-]+$'"
assert_status 1 "$RUN_STATUS" "source require_match invalid (no desc) exits 1"
assert_contains "$RUN_STDERR" "DEPLOY_USER" \
  "source require_match invalid (no desc) names DEPLOY_USER"
assert_contains "$RUN_STDERR" "^[A-Za-z0-9._-]+$" \
  "source require_match invalid (no desc) prints raw regex as rule"
assert_not_contains "$RUN_STDERR" "SECRET LEAK CANARY" \
  "source require_match invalid (no desc) does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match COUNT '0' '^[0-9]+$'"
assert_status 0 "$RUN_STATUS" "source require_match numeric valid exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match NAME value"
assert_status 64 "$RUN_STATUS" "source require_match missing regex exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_match" \
  "source require_match missing regex prints usage"

# -- Source mode: ci::require_uint (spec §5.4, §8.1) ----------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 0"
assert_status 0 "$RUN_STATUS" "source require_uint 0 exits 0"
assert_eq "" "$RUN_STDOUT" "source require_uint 0 writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_uint 0 writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 5"
assert_status 0 "$RUN_STATUS" "source require_uint 5 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 12345"
assert_status 0 "$RUN_STATUS" "source require_uint 12345 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT -1"
assert_status 1 "$RUN_STATUS" "source require_uint negative exits 1"
assert_contains "$RUN_STDERR" "COUNT" "source require_uint negative names COUNT"
assert_not_contains "$RUN_STDERR" "-1" \
  "source require_uint negative does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT +1"
assert_status 1 "$RUN_STATUS" "source require_uint signed exits 1"
assert_contains "$RUN_STDERR" "COUNT" "source require_uint signed names COUNT"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 1.5"
assert_status 1 "$RUN_STATUS" "source require_uint decimal exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT ''"
assert_status 1 "$RUN_STATUS" "source require_uint empty exits 1"
assert_contains "$RUN_STDERR" "COUNT" "source require_uint empty names COUNT"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT abc"
assert_status 1 "$RUN_STATUS" "source require_uint abc exits 1"
assert_not_contains "$RUN_STDERR" "abc" \
  "source require_uint abc does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT"
assert_status 64 "$RUN_STATUS" "source require_uint missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_uint" \
  "source require_uint missing arg prints usage"

# -- CLI mode (spec §8.3) -------------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" file require CONFIG "$EXISTING_FILE"
assert_status 0 "$RUN_STATUS" "CLI file require present exits 0"
assert_eq "" "$RUN_STDOUT" "CLI file require present writes no stdout"
assert_eq "" "$RUN_STDERR" "CLI file require present writes no stderr"

run_capture "$ROOT_DIR/ci-toolkit" file require CONFIG "$MISSING_FILE"
assert_status 1 "$RUN_STATUS" "CLI file require missing exits 1"
assert_contains "$RUN_STDERR" "CONFIG" "CLI file require missing names CONFIG"

run_capture "$ROOT_DIR/ci-toolkit" file require
assert_status 64 "$RUN_STATUS" "CLI file require missing args exits 64"

run_capture "$ROOT_DIR/ci-toolkit" dir require STAGING "$EXISTING_DIR"
assert_status 0 "$RUN_STATUS" "CLI dir require present exits 0"

run_capture "$ROOT_DIR/ci-toolkit" dir require STAGING "$MISSING_DIR"
assert_status 1 "$RUN_STATUS" "CLI dir require missing exits 1"
assert_contains "$RUN_STDERR" "STAGING" "CLI dir require missing names STAGING"

run_capture "$ROOT_DIR/ci-toolkit" match require DEPLOY_USER arcade '^[A-Za-z0-9._-]+$'
assert_status 0 "$RUN_STATUS" "CLI match require valid exits 0"

run_capture "$ROOT_DIR/ci-toolkit" match require DEPLOY_USER 'SECRET LEAK CANARY' '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
assert_status 1 "$RUN_STATUS" "CLI match require invalid exits 1"
assert_contains "$RUN_STDERR" "DEPLOY_USER" "CLI match require invalid names DEPLOY_USER"
assert_contains "$RUN_STDERR" "[A-Za-z0-9._-]+" "CLI match require invalid prints description"
assert_not_contains "$RUN_STDERR" "SECRET LEAK CANARY" \
  "CLI match require invalid does not echo VALUE"

run_capture "$ROOT_DIR/ci-toolkit" uint require COUNT 5
assert_status 0 "$RUN_STATUS" "CLI uint require 5 exits 0"

run_capture "$ROOT_DIR/ci-toolkit" uint require COUNT -1
assert_status 1 "$RUN_STATUS" "CLI uint require -1 exits 1"
assert_contains "$RUN_STDERR" "COUNT" "CLI uint require -1 names COUNT"

run_capture "$ROOT_DIR/ci-toolkit" uint require
assert_status 64 "$RUN_STATUS" "CLI uint require missing args exits 64"

finish_tests
