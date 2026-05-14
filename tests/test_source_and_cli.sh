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

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; printf 'sourced:%s' \"\${CI_TOOLKIT_VERSION:-missing}\""
assert_status 0 "$RUN_STATUS" "source mode succeeds without dispatch"
assert_contains "$RUN_STDOUT" "sourced:" "source mode exposes version variable"
assert_not_contains "$RUN_STDOUT$RUN_STDERR" "Usage:" "source mode does not print usage"

run_capture "$ROOT_DIR/ci-toolkit" version
assert_status 0 "$RUN_STATUS" "version command exits zero"
assert_contains "$RUN_STDOUT" "ci-toolkit" "version command prints tool name"
assert_eq "ci-toolkit 0.1.3" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.3"

run_capture "$ROOT_DIR/ci-toolkit" help
assert_status 0 "$RUN_STATUS" "help command exits zero"
assert_contains "$RUN_STDOUT" "Usage:" "help command prints usage"
assert_contains "$RUN_STDOUT" "Experimental" "help command states experimental status"

run_capture "$ROOT_DIR/ci-toolkit" log info "hello ci"
assert_status 0 "$RUN_STATUS" "log info exits zero"
assert_contains "$RUN_STDERR" "[info] hello ci" "log info writes to stderr"

run_capture "$ROOT_DIR/ci-toolkit" log debug "hidden"
assert_status 0 "$RUN_STATUS" "log debug without debug flag exits zero"
assert_eq "" "$RUN_STDERR" "debug log is hidden by default"

run_capture env CI_TOOLKIT_DEBUG=1 "$ROOT_DIR/ci-toolkit" log debug "visible"
assert_status 0 "$RUN_STATUS" "log debug with debug flag exits zero"
assert_contains "$RUN_STDERR" "[debug] visible" "debug log is visible when enabled"

finish_tests
