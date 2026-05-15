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

# Reparse a joined shell string into "$#\narg1\narg2\n..." inside a controlled
# subshell. NEVER feed untrusted input here; this is for round-trip testing
# against ci::shell_join output only.
reparse_joined() {
  local joined="$1"
  bash -c '
    eval "set -- $1"
    printf "%s\n" "$#"
    for arg; do
      printf "%s\n" "$arg"
    done
  ' _ "$joined"
}

set -e

# -- Source mode: ci::shell_join (spec §5.5, §8.2) ------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join ssh -p 22 host"
assert_status 0 "$RUN_STATUS" "source shell_join simple exits 0"
assert_eq "" "$RUN_STDERR" "source shell_join simple writes no stderr"
assert_contains "$RUN_STDOUT" "ssh" "source shell_join simple contains ssh"
assert_contains "$RUN_STDOUT" "22" "source shell_join simple contains 22"
assert_contains "$RUN_STDOUT" "host" "source shell_join simple contains host"

# Round-trip: simple argv
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join ssh -p 22 host")
reparsed="$(reparse_joined "$joined")"
expected=$'4\nssh\n-p\n22\nhost'
assert_eq "$expected" "$reparsed" "shell_join simple round-trips"

# Round-trip: argv with spaces
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join 'hello world' two")
reparsed="$(reparse_joined "$joined")"
expected=$'2\nhello world\ntwo'
assert_eq "$expected" "$reparsed" "shell_join spaces round-trips"

# Round-trip: argv with quotes and backslash. The outer double-quoted bash -c
# string collapses '\\\\' to '\\' before single-quote parsing, so the input
# argv contains two literal backslashes — expected mirrors that.
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join \"it's\" 'a \"quote\"' 'back\\\\slash'")
reparsed="$(reparse_joined "$joined")"
expected=$'3\nit\'s\na "quote"\nback\\\\slash'
assert_eq "$expected" "$reparsed" "shell_join quotes round-trips"

# Round-trip: argv with glob characters
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join '*.txt' '[abc]?' 'plain'")
reparsed="$(reparse_joined "$joined")"
expected=$'3\n*.txt\n[abc]?\nplain'
assert_eq "$expected" "$reparsed" "shell_join glob round-trips"

# Round-trip: argv with empty string. Place the empty arg in a non-trailing
# position — command substitution strips trailing newlines, so a trailing
# empty arg in reparse output would silently disappear.
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join '' nonempty trailing")
reparsed="$(reparse_joined "$joined")"
expected=$'3\n\nnonempty\ntrailing'
assert_eq "$expected" "$reparsed" "shell_join empty-string round-trips"

# Zero args
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join"
assert_status 64 "$RUN_STATUS" "source shell_join no args exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::shell_join" \
  "source shell_join no args prints usage"

finish_tests
