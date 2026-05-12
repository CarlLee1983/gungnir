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

# boundary subcommand: real artifact has no vendor markers and no forbidden commands.
run_capture "$RELEASE_CHECK" boundary
assert_status 0 "$RUN_STATUS" "release-check boundary: clean artifact exits zero"
assert_contains "$RUN_STDOUT" "boundary: ok" "release-check boundary: prints ok line"

# boundary subcommand: synthetic artifact with vendor markers must fail.
vendor_tmp="$(make_temp_dir)"
cat >"$vendor_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
echo "GITHUB_TOKEN is sensitive"
EOF
run_capture "$RELEASE_CHECK" boundary "$vendor_tmp/ci-toolkit"
assert_status 1 "$RUN_STATUS" "release-check boundary: vendor marker exits non-zero"
assert_contains "$RUN_STDERR" "CI-vendor markers found" \
  "release-check boundary: explains vendor markers on stderr"
assert_not_contains "$RUN_STDOUT" "boundary: ok" \
  "release-check boundary: vendor marker does not print ok to stdout"

# boundary subcommand: synthetic artifact with a forbidden dispatch command must fail.
cmd_tmp="$(make_temp_dir)"
cat >"$cmd_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    build)
      echo "running build"
      ;;
esac
EOF
run_capture "$RELEASE_CHECK" boundary "$cmd_tmp/ci-toolkit"
assert_status 1 "$RUN_STATUS" "release-check boundary: forbidden command exits non-zero"
assert_contains "$RUN_STDERR" "forbidden public command names" \
  "release-check boundary: explains forbidden command on stderr"
assert_not_contains "$RUN_STDOUT" "boundary: ok" \
  "release-check boundary: forbidden command does not print ok to stdout"

# copy-smoke subcommand: real artifact copied into a temp dir must work standalone.
run_capture "$RELEASE_CHECK" copy-smoke
assert_status 0 "$RUN_STATUS" "release-check copy-smoke: standalone artifact exits zero"
assert_contains "$RUN_STDOUT" "copy-smoke: ok" "release-check copy-smoke: prints ok line"
assert_eq "" "$RUN_STDERR" "release-check copy-smoke: no stderr on success"

# copy-smoke subcommand: broken artifact must fail with a clear error.
broken_tmp="$(make_temp_dir)"
cat >"$broken_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
echo "broken artifact"
exit 1
EOF
chmod +x "$broken_tmp/ci-toolkit"

run_capture "$RELEASE_CHECK" copy-smoke "$broken_tmp/ci-toolkit"
assert_status 1 "$RUN_STATUS" "release-check copy-smoke: broken artifact exits non-zero"
assert_contains "$RUN_STDERR" "standalone artifact failed" \
  "release-check copy-smoke: explains failure on stderr"
assert_not_contains "$RUN_STDOUT" "copy-smoke: ok" \
  "release-check copy-smoke: broken artifact does not print ok to stdout"

finish_tests
