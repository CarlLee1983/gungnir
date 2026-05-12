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

# Case 1: Happy path — symlink is created
skills_dir="$(make_temp_dir)"
CLAUDE_SKILLS_DIR="$skills_dir" run_capture "$ROOT_DIR/scripts/install-skill"
assert_status 0 "$RUN_STATUS" "happy path: installer exits 0"
[[ -L "$skills_dir/ci-toolkit" ]] && pass "happy path: destination is a symlink" \
  || fail "happy path: destination is not a symlink"
assert_eq "$ROOT_DIR/skills/ci-toolkit" "$(readlink "$skills_dir/ci-toolkit")" \
  "happy path: symlink target equals skills/ci-toolkit"
assert_contains "$RUN_STDOUT" "linked" "happy path: stdout reports linked"

# Case 2: Idempotent — running twice is a no-op
skills_dir2="$(make_temp_dir)"
CLAUDE_SKILLS_DIR="$skills_dir2" "$ROOT_DIR/scripts/install-skill" >/dev/null
CLAUDE_SKILLS_DIR="$skills_dir2" run_capture "$ROOT_DIR/scripts/install-skill"
assert_status 0 "$RUN_STATUS" "idempotent: second run exits 0"
assert_contains "$RUN_STDOUT" "already linked" "idempotent: stdout says already linked"
assert_eq "$ROOT_DIR/skills/ci-toolkit" "$(readlink "$skills_dir2/ci-toolkit")" \
  "idempotent: symlink target unchanged"

finish_tests
