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
if [[ -L "$skills_dir/ci-toolkit" ]]; then
  pass "happy path: destination is a symlink"
else
  fail "happy path: destination is not a symlink"
fi
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

# Case 3: Refuses to overwrite a regular file at the destination
skills_dir3="$(make_temp_dir)"
printf 'unrelated content\n' >"$skills_dir3/ci-toolkit"
original_content="$(cat "$skills_dir3/ci-toolkit")"
CLAUDE_SKILLS_DIR="$skills_dir3" run_capture "$ROOT_DIR/scripts/install-skill"
if [[ "$RUN_STATUS" -ne 0 ]]; then
  pass "regular-file conflict: non-zero exit"
else
  fail "regular-file conflict: expected non-zero exit, got 0"
fi
assert_contains "$RUN_STDERR" "aborting" "regular-file conflict: stderr mentions aborting"
assert_eq "$original_content" "$(cat "$skills_dir3/ci-toolkit")" \
  "regular-file conflict: existing file untouched"

# Case 4: Refuses to overwrite a symlink pointing elsewhere
skills_dir4="$(make_temp_dir)"
other_target="$(make_temp_dir)"
ln -s "$other_target" "$skills_dir4/ci-toolkit"
CLAUDE_SKILLS_DIR="$skills_dir4" run_capture "$ROOT_DIR/scripts/install-skill"
if [[ "$RUN_STATUS" -ne 0 ]]; then
  pass "wrong-symlink conflict: non-zero exit"
else
  fail "wrong-symlink conflict: expected non-zero exit, got 0"
fi
assert_contains "$RUN_STDERR" "different symlink exists" \
  "wrong-symlink conflict: stderr mentions different symlink"
assert_eq "$other_target" "$(readlink "$skills_dir4/ci-toolkit")" \
  "wrong-symlink conflict: original symlink unchanged"

finish_tests
