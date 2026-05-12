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

counter_dir="$(make_temp_dir)"
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 bash -c 'count_file=\"$counter_dir/count\"; count=0; [[ -f \"$counter_dir/count\" ]] && count=\$(cat \"$counter_dir/count\"); count=\$((count + 1)); printf \"%s\" \"\$count\" >\"$counter_dir/count\"; [[ \"\$count\" -ge 2 ]]'"
assert_status 0 "$RUN_STATUS" "source retry succeeds when later attempt passes"
assert_eq "2" "$(cat "$counter_dir/count")" "source retry stops after successful attempt"
assert_contains "$RUN_STDERR" "Attempt 1/3 failed" "source retry reports failed attempt"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 2 bash -c 'printf out; printf err >&2; exit 7'"
assert_status 7 "$RUN_STATUS" "source retry returns final failing status"
assert_contains "$RUN_STDOUT" "out" "source retry preserves stdout"
assert_contains "$RUN_STDERR" "err" "source retry preserves stderr"
assert_contains "$RUN_STDERR" "Attempt 2/2 failed" "source retry reports final attempt"

cli_counter_dir="$(make_temp_dir)"
run_capture "$ROOT_DIR/ci-toolkit" retry -- bash -c "count_file='$cli_counter_dir/count'; count=0; [[ -f \"\$count_file\" ]] && count=\$(cat \"\$count_file\"); count=\$((count + 1)); printf \"%s\" \"\$count\" >\"\$count_file\"; [[ \"\$count\" -ge 2 ]]"
assert_status 0 "$RUN_STATUS" "CLI retry succeeds when later attempt passes"
assert_eq "2" "$(cat "$cli_counter_dir/count")" "CLI retry stops after success"

path_dir="$(make_temp_dir)"
mkdir -p "$path_dir/a/b/c"
touch "$path_dir/.git"
run_capture bash -c "cd '$path_dir/a/b/c'; source '$ROOT_DIR/ci-toolkit'; ci::find_up .git"
assert_status 0 "$RUN_STATUS" "find_up locates marker"
assert_eq "$path_dir" "$RUN_STDOUT" "find_up prints marker directory"

run_capture bash -c "cd '$path_dir/a/b/c'; source '$ROOT_DIR/ci-toolkit'; ci::root"
assert_status 0 "$RUN_STATUS" "root locates repository marker"
assert_eq "$path_dir" "$RUN_STDOUT" "root prints root directory"

run_capture bash -c "cd '$path_dir/a/b/c'; source '$ROOT_DIR/ci-toolkit'; ci::find_up missing.marker"
assert_status 1 "$RUN_STATUS" "find_up fails when marker is missing"
assert_contains "$RUN_STDERR" "Could not find marker: missing.marker" "find_up reports missing marker"

finish_tests
