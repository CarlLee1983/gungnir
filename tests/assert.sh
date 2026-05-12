#!/usr/bin/env bash

set -u

TEST_FAILURES=0
TEST_TMP_DIRS=()

fail() {
  printf 'not ok - %s\n' "$*" >&2
  TEST_FAILURES=$((TEST_FAILURES + 1))
}

pass() {
  printf 'ok - %s\n' "$*"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label: expected [$expected], got [$actual]"
  fi
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label"
  else
    fail "$label: expected status $expected, got $actual"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label: expected output to contain [$needle], got [$haystack]"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$label: expected output not to contain [$needle], got [$haystack]"
  else
    pass "$label"
  fi
}

make_temp_dir() {
  local tmp
  tmp="$(mktemp -d)"
  TEST_TMP_DIRS+=("$tmp")
  printf '%s\n' "$tmp"
}

finish_tests() {
  local dir
  for dir in "${TEST_TMP_DIRS[@]}"; do
    rm -rf "$dir"
  done

  if [[ "$TEST_FAILURES" -eq 0 ]]; then
    printf 'All tests passed\n'
    return 0
  fi

  printf '%s test(s) failed\n' "$TEST_FAILURES" >&2
  return 1
}
