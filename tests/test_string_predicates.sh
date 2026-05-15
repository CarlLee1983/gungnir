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

# -- Source mode: ci::eq (spec §4.1, §7.1 #1–#4) --------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq foo foo"
assert_status 0 "$RUN_STATUS" "source ci::eq foo foo exits 0"
assert_eq "" "$RUN_STDOUT" "source ci::eq foo foo writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::eq foo foo writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq foo bar"
assert_status 1 "$RUN_STATUS" "source ci::eq foo bar exits 1"
assert_eq "" "$RUN_STDOUT" "source ci::eq foo bar writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::eq foo bar writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq '' ''"
assert_status 0 "$RUN_STATUS" "source ci::eq '' '' exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq '' x"
assert_status 1 "$RUN_STATUS" "source ci::eq '' x exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq foo"
assert_status 64 "$RUN_STATUS" "source ci::eq missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::eq" \
  "source ci::eq missing arg prints usage"

# -- Source mode: ci::ne (spec §4.2, §7.1 #5–#8) --------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne foo bar"
assert_status 0 "$RUN_STATUS" "source ci::ne foo bar exits 0"
assert_eq "" "$RUN_STDOUT" "source ci::ne foo bar writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::ne foo bar writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne foo foo"
assert_status 1 "$RUN_STATUS" "source ci::ne foo foo exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne '' foo"
assert_status 0 "$RUN_STATUS" "source ci::ne '' foo exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne '' ''"
assert_status 1 "$RUN_STATUS" "source ci::ne '' '' exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne foo"
assert_status 64 "$RUN_STATUS" "source ci::ne missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::ne" \
  "source ci::ne missing arg prints usage"

# -- Source mode: ci::in (spec §4.3, §7.1 #9–#12) -------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in staging dev staging prod"
assert_status 0 "$RUN_STATUS" "source ci::in match exits 0"
assert_eq "" "$RUN_STDOUT" "source ci::in match writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::in match writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in qa dev staging prod"
assert_status 1 "$RUN_STATUS" "source ci::in no-match exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in '' dev '' prod"
assert_status 0 "$RUN_STATUS" "source ci::in empty-value matches empty candidate"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in staging"
assert_status 64 "$RUN_STATUS" "source ci::in missing candidates exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::in" \
  "source ci::in missing candidates prints usage"

finish_tests
