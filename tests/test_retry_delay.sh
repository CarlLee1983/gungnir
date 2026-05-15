#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/assert.sh
source "$ROOT_DIR/tests/assert.sh"

# shellcheck disable=SC2034
# Reason: RUN_STDOUT/RUN_STDERR/RUN_STATUS are read by assert_* helpers in
# the calling scope; ShellCheck cannot follow that across files. This file
# only happens to read RUN_STDERR + RUN_STATUS, but we keep the trio so the
# capture helper matches the other tests in this directory.
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

# -- Parse errors (spec §10 #5–#8, #12) -----------------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay -1 -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay -1"
assert_contains "$RUN_STDERR" "--delay" "source retry --delay -1 mentions --delay"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay abc -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay abc"
assert_contains "$RUN_STDERR" "--delay" "source retry --delay abc mentions --delay"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay with no value"
assert_contains "$RUN_STDERR" "--delay requires a value" "source retry --delay missing-value message"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --bogus -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects unknown --bogus"
assert_contains "$RUN_STDERR" "unknown option: --bogus" "source retry --bogus message"

run_capture "$ROOT_DIR/ci-toolkit" retry 2 --delay foo -- true
assert_status 64 "$RUN_STATUS" "CLI retry rejects --delay foo"

# -- Regression: no flags, no `--` (spec §10 #13) -------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 false"
assert_status 1 "$RUN_STATUS" "source retry without flags or -- returns command status"
assert_contains "$RUN_STDERR" "Attempt 1/3 failed" "source retry without flags still warns on attempt 1"

# -- Regression: explicit `--`, no flags (spec §10 #9) --------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 -- false"
assert_status 1 "$RUN_STATUS" "source retry with bare -- returns command status"
assert_contains "$RUN_STDERR" "Attempt 3/3 failed" "source retry with bare -- attempts all three"

# -- Wall-clock behavior (spec §10 #1–#4) ---------------------------------

# #1: --delay 0 behaves like no delay (no sleep, command still fails twice)
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 2 --delay 0 false"
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "source retry --delay 0 returns command status"
if [[ "$elapsed" -lt 1 ]]; then
  pass "source retry --delay 0 does not sleep (elapsed=${elapsed}s)"
else
  fail "source retry --delay 0 should not sleep, elapsed=${elapsed}s"
fi

# #2: --delay 1, succeeds on 2nd attempt → wall-clock ≥ 1s
counter_dir="$(make_temp_dir)"
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 2 --delay 1 -- bash -c 'f=\"$counter_dir/c\"; n=0; [[ -f \$f ]] && n=\$(cat \$f); n=\$((n+1)); printf %s \$n >\$f; [[ \$n -ge 2 ]]'"
elapsed=$(( SECONDS - start ))
assert_status 0 "$RUN_STATUS" "source retry --delay 1 succeeds on 2nd attempt"
if [[ "$elapsed" -ge 1 ]]; then
  pass "source retry --delay 1 sleeps before retry (elapsed=${elapsed}s)"
else
  fail "source retry --delay 1 should sleep ≥1s, elapsed=${elapsed}s"
fi

# #3: --delay 1, 3 attempts all fail → 2 sleeps → wall-clock ≥ 2s
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay 1 false"
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "source retry 3 --delay 1 returns final status"
if [[ "$elapsed" -ge 2 ]]; then
  pass "source retry 3 --delay 1 sleeps twice (elapsed=${elapsed}s)"
else
  fail "source retry 3 --delay 1 should sleep ≥2s, elapsed=${elapsed}s"
fi

# #4: --delay 5 with ATTEMPTS=1 → no "between", no sleep.
# The < 3 ceiling tolerates wall-clock drift under heavy parallel load while
# still detecting any real `sleep 5` execution.
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 1 --delay 5 false"
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "source retry 1 --delay 5 returns command status"
if [[ "$elapsed" -lt 3 ]]; then
  pass "source retry 1 --delay 5 never sleeps (elapsed=${elapsed}s)"
else
  fail "source retry 1 --delay 5 should not sleep, elapsed=${elapsed}s"
fi

# -- CLI mode (spec §10 #10, #11, #14, #15) -------------------------------

# #10: CLI retry 2 --delay 1 -- succeeds on 2nd → ≥1s
counter_dir="$(make_temp_dir)"
start=$SECONDS
run_capture "$ROOT_DIR/ci-toolkit" retry 2 --delay 1 -- bash -c "f='$counter_dir/c'; n=0; [[ -f \$f ]] && n=\$(cat \$f); n=\$((n+1)); printf %s \$n >\$f; [[ \$n -ge 2 ]]"
elapsed=$(( SECONDS - start ))
assert_status 0 "$RUN_STATUS" "CLI retry --delay 1 succeeds on 2nd attempt"
if [[ "$elapsed" -ge 1 ]]; then
  pass "CLI retry --delay 1 sleeps before retry (elapsed=${elapsed}s)"
else
  fail "CLI retry --delay 1 should sleep ≥1s, elapsed=${elapsed}s"
fi

# #11: CLI retry --delay 1 -- false (default ATTEMPTS=3) → ≥2s
start=$SECONDS
run_capture "$ROOT_DIR/ci-toolkit" retry --delay 1 -- false
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "CLI retry --delay 1 (default attempts) returns command status"
if [[ "$elapsed" -ge 2 ]]; then
  pass "CLI retry --delay 1 default attempts sleeps twice (elapsed=${elapsed}s)"
else
  fail "CLI retry --delay 1 default attempts should sleep ≥2s, elapsed=${elapsed}s"
fi

# #14: CLI retry 2 -- cmd (regression, no flag) — unchanged behavior
run_capture "$ROOT_DIR/ci-toolkit" retry 2 -- false
assert_status 1 "$RUN_STATUS" "CLI retry 2 -- false (regression) returns command status"
assert_contains "$RUN_STDERR" "Attempt 2/2 failed" "CLI retry 2 -- false (regression) attempts twice"

# #15: CLI retry -- cmd (regression, no ATTEMPTS) — default 3
run_capture "$ROOT_DIR/ci-toolkit" retry -- false
assert_status 1 "$RUN_STATUS" "CLI retry -- false (regression) returns command status"
assert_contains "$RUN_STDERR" "Attempt 3/3 failed" "CLI retry -- false (regression) defaults to 3 attempts"

finish_tests
