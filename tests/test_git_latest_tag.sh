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

git_dir="$(make_temp_dir)"
# Set up a fake git repo
(
  cd "$git_dir"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo "test" > test.txt
  git add test.txt
  git commit -m "initial" -q
  git tag release-v1.0.0
  git tag release-v1.0.1
  git tag release-v2.0.0
  git tag other-tag-1.0
)

run_capture bash -c "cd '$git_dir'; source '$ROOT_DIR/ci-toolkit'; ci::git_latest_tag release-v"
assert_status 0 "$RUN_STATUS" "git_latest_tag succeeds when matching tags exist"
assert_eq "release-v2.0.0" "$RUN_STDOUT" "git_latest_tag returns latest sorted tag"

run_capture bash -c "cd '$git_dir'; source '$ROOT_DIR/ci-toolkit'; ci::git_latest_tag non-existent"
assert_status 1 "$RUN_STATUS" "git_latest_tag fails when no matching tags"
assert_contains "$RUN_STDERR" "no tag matches non-existent*" "git_latest_tag logs error on no match"

run_capture bash -c "cd '$git_dir'; source '$ROOT_DIR/ci-toolkit'; ci::git_latest_tag"
assert_status 0 "$RUN_STATUS" "git_latest_tag succeeds without prefix"
assert_eq "release-v2.0.0" "$RUN_STDOUT" "git_latest_tag returns latest absolute tag"

# CLI tests
run_capture bash -c "cd '$git_dir'; '$ROOT_DIR/ci-toolkit' git latest-tag release-v1"
assert_status 0 "$RUN_STATUS" "CLI git latest-tag succeeds"
assert_eq "release-v1.0.1" "$RUN_STDOUT" "CLI git latest-tag returns correct tag"

run_capture bash -c "cd '$git_dir'; '$ROOT_DIR/ci-toolkit' git latest-tag missing"
assert_status 1 "$RUN_STATUS" "CLI git latest-tag fails for missing"

finish_tests
