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

# -- Source mode (spec §5.2 #1–#6) ----------------------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v v1.2.3"
assert_status 0 "$RUN_STATUS" "source strip_prefix v v1.2.3 exits 0"
assert_eq "1.2.3" "${RUN_STDOUT%$'\n'}" "source strip_prefix v v1.2.3 strips the v"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v 1.2.3"
assert_status 0 "$RUN_STATUS" "source strip_prefix no-match exits 0"
assert_eq "1.2.3" "${RUN_STDOUT%$'\n'}" "source strip_prefix no-match returns original"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix '' v1.2.3"
assert_status 0 "$RUN_STATUS" "source strip_prefix empty prefix exits 0"
assert_eq "v1.2.3" "${RUN_STDOUT%$'\n'}" "source strip_prefix empty prefix is a no-op"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v ''"
assert_status 0 "$RUN_STATUS" "source strip_prefix empty string exits 0"
assert_eq "" "${RUN_STDOUT%$'\n'}" "source strip_prefix empty string returns empty"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix '*' '*foo'"
assert_status 0 "$RUN_STATUS" "source strip_prefix glob-char prefix exits 0"
assert_eq "foo" "${RUN_STDOUT%$'\n'}" "source strip_prefix treats * literally"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v"
assert_status 64 "$RUN_STATUS" "source strip_prefix missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::strip_prefix PREFIX STRING" \
  "source strip_prefix missing arg prints usage"

# -- CLI mode (spec §5.2 #7) ----------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" strip-prefix v v1.2.3
assert_status 0 "$RUN_STATUS" "CLI strip-prefix v v1.2.3 exits 0"
assert_eq "1.2.3" "${RUN_STDOUT%$'\n'}" "CLI strip-prefix v v1.2.3 prints stripped value"

finish_tests
