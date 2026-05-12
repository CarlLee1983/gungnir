#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/assert.sh
source "$ROOT_DIR/tests/assert.sh"

RELEASE_CHECK="$ROOT_DIR/scripts/release-check"

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

# version subcommand: match against the real artifact and CHANGELOG.
run_capture "$RELEASE_CHECK" version
assert_status 0 "$RUN_STATUS" "release-check version: matching versions exit zero"
assert_contains "$RUN_STDOUT" "version: ok" "release-check version: prints ok line"

# version subcommand: synthetic ci-toolkit with mismatched constant must fail.
tmp_root="$(make_temp_dir)"
cat >"$tmp_root/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
CI_TOOLKIT_VERSION="9.9.9"
EOF
cat >"$tmp_root/CHANGELOG.md" <<'EOF'
# Changelog

## v0.1.0 - Experimental initial release

- placeholder
EOF

run_capture "$RELEASE_CHECK" version "$tmp_root/ci-toolkit" "$tmp_root/CHANGELOG.md"
assert_status 1 "$RUN_STATUS" "release-check version: mismatch exits non-zero"
assert_contains "$RUN_STDERR" "does not match" "release-check version: explains mismatch on stderr"

# version subcommand: empty ci-toolkit fixture must surface a parse error.
parse_tmp="$(make_temp_dir)"
: >"$parse_tmp/ci-toolkit"
cat >"$parse_tmp/CHANGELOG.md" <<'EOF'
# Changelog

## v0.1.0 - Experimental initial release
EOF

run_capture "$RELEASE_CHECK" version "$parse_tmp/ci-toolkit" "$parse_tmp/CHANGELOG.md"
assert_status 1 "$RUN_STATUS" "release-check version: unparseable artifact exits non-zero"
assert_contains "$RUN_STDERR" "could not parse" \
  "release-check version: explains parse failure on stderr"

finish_tests
