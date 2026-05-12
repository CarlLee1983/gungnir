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
  # shellcheck disable=SC2034  # consumed by assert_* helpers in calling scope
  RUN_STDOUT="$(cat "$stdout_file")"
  RUN_STDERR="$(cat "$stderr_file")"
  RUN_STATUS="$status"
}

set -e

run_capture env -u SECRET_TOKEN bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_env SECRET_TOKEN"
assert_status 1 "$RUN_STATUS" "source require_env fails for missing variable"
assert_contains "$RUN_STDERR" "Missing required environment variable: SECRET_TOKEN" "missing env names variable"
assert_not_contains "$RUN_STDERR" "super-secret" "missing env does not leak secret value"

run_capture env SECRET_TOKEN=super-secret bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_env SECRET_TOKEN"
assert_status 0 "$RUN_STATUS" "source require_env passes for present variable"
assert_not_contains "$RUN_STDERR" "super-secret" "present env does not print secret value"

run_capture "$ROOT_DIR/ci-toolkit" env require SECRET_TOKEN
assert_status 1 "$RUN_STATUS" "CLI env require fails when variable missing"
assert_contains "$RUN_STDERR" "Missing required environment variable: SECRET_TOKEN" "CLI env require reports missing name"

run_capture env SECRET_TOKEN=super-secret "$ROOT_DIR/ci-toolkit" env require SECRET_TOKEN
assert_status 0 "$RUN_STATUS" "CLI env require passes when variable exists"
assert_not_contains "$RUN_STDERR" "super-secret" "CLI env require does not leak value"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_tool bash"
assert_status 0 "$RUN_STATUS" "source require_tool passes for bash"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_tool definitely-not-a-real-tool-gungnir"
assert_status 1 "$RUN_STATUS" "source require_tool fails for missing tool"
assert_contains "$RUN_STDERR" "Missing required tool: definitely-not-a-real-tool-gungnir" "source require_tool reports tool name"

run_capture "$ROOT_DIR/ci-toolkit" tool require bash
assert_status 0 "$RUN_STATUS" "CLI tool require passes for bash"

run_capture "$ROOT_DIR/ci-toolkit" tool require definitely-not-a-real-tool-gungnir
assert_status 1 "$RUN_STATUS" "CLI tool require fails for missing tool"
assert_contains "$RUN_STDERR" "Missing required tool: definitely-not-a-real-tool-gungnir" "CLI tool require reports tool name"

finish_tests
