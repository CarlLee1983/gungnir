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

run_capture "$RELEASE_CHECK" artifact
assert_status 0 "$RUN_STATUS" "release-check artifact: real artifact exits zero"
assert_contains "$RUN_STDOUT" "artifact: ok" "release-check artifact: prints ok line"

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

not_executable_tmp="$(make_temp_dir)"
cat >"$not_executable_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
CI_TOOLKIT_VERSION="0.1.0"
EOF
chmod 0644 "$not_executable_tmp/ci-toolkit"
run_capture "$RELEASE_CHECK" artifact "$not_executable_tmp/ci-toolkit"
assert_status 1 "$RUN_STATUS" "release-check artifact: non-executable artifact exits non-zero"
assert_contains "$RUN_STDERR" "not executable" \
  "release-check artifact: explains executable bit failure"

missing_bash_marker_tmp="$(make_temp_dir)"
cat >"$missing_bash_marker_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
CI_TOOLKIT_VERSION="0.1.0"
EOF
chmod +x "$missing_bash_marker_tmp/ci-toolkit"
run_capture "$RELEASE_CHECK" artifact "$missing_bash_marker_tmp/ci-toolkit"
assert_status 1 "$RUN_STATUS" "release-check artifact: missing bash marker exits non-zero"
assert_contains "$RUN_STDERR" "Bash 4+ marker" \
  "release-check artifact: explains missing bash marker"

readme_tmp="$(make_temp_dir)"
cat >"$readme_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
# Runtime: Bash 4+
CI_TOOLKIT_VERSION="0.1.0"
EOF
chmod +x "$readme_tmp/ci-toolkit"
cat >"$readme_tmp/README.md" <<'EOF'
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v9.9.9/ci-toolkit -o ci-toolkit
EOF
run_capture "$RELEASE_CHECK" artifact "$readme_tmp/ci-toolkit" "$readme_tmp/README.md"
assert_status 1 "$RUN_STATUS" "release-check artifact: README version mismatch exits non-zero"
assert_contains "$RUN_STDERR" "README install URL" \
  "release-check artifact: explains README version mismatch"

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

# descriptions subcommand: real artifact has @description on every public function.
run_capture "$RELEASE_CHECK" descriptions
assert_status 0 "$RUN_STATUS" "release-check descriptions: clean artifact exits zero"
assert_contains "$RUN_STDOUT" "descriptions: ok" \
  "release-check descriptions: prints ok line"

# descriptions subcommand: synthetic artifact with a missing @description must fail.
missing_desc_tmp="$(make_temp_dir)"
cat >"$missing_desc_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
ci::ls() {
  awk '
  /^# @description / { comment = substr($0, 16); next }
  /^ci::.*\(.*\) \{/ {
    func_name = $1; sub(/\(.*\)/, "", func_name)
    if (func_name ~ /^ci::cmd_/ || func_name == "ci::dispatch" || func_name == "ci::usage") { comment=""; next }
    if (comment == "") comment = "(No description)"
    printf "  %-20s %s\n", func_name, comment
    comment = ""; next
  }
  { comment = "" }
  ' "${BASH_SOURCE[0]}" | sort
}
ci::missing_description_fixture() { :; }
[[ "${BASH_SOURCE[0]}" == "$0" ]] && case "${1:-}" in ls) ci::ls;; esac
EOF
chmod +x "$missing_desc_tmp/ci-toolkit"
run_capture "$RELEASE_CHECK" descriptions "$missing_desc_tmp/ci-toolkit"
assert_status 1 "$RUN_STATUS" \
  "release-check descriptions: missing @description exits non-zero"
assert_contains "$RUN_STDERR" "missing # @description" \
  "release-check descriptions: explains missing @description on stderr"
assert_not_contains "$RUN_STDOUT" "descriptions: ok" \
  "release-check descriptions: missing case does not print ok"

# descriptions subcommand: non-executable artifact must surface clear error.
desc_notexec_tmp="$(make_temp_dir)"
cat >"$desc_notexec_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
EOF
chmod 0644 "$desc_notexec_tmp/ci-toolkit"
run_capture "$RELEASE_CHECK" descriptions "$desc_notexec_tmp/ci-toolkit"
assert_status 1 "$RUN_STATUS" \
  "release-check descriptions: non-executable exits non-zero"
assert_contains "$RUN_STDERR" "not executable" \
  "release-check descriptions: explains executable bit failure"

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

# all subcommand: end-to-end pipeline must exit zero on a clean repo.
run_capture "$RELEASE_CHECK" all
assert_status 0 "$RUN_STATUS" "release-check all: clean repo exits zero"
assert_contains "$RUN_STDOUT" "version: ok" "release-check all: ran version check"
assert_contains "$RUN_STDOUT" "artifact: ok" "release-check all: ran artifact check"
assert_contains "$RUN_STDOUT" "boundary: ok" "release-check all: ran boundary check"
assert_contains "$RUN_STDOUT" "copy-smoke: ok" "release-check all: ran copy-smoke"
assert_contains "$RUN_STDOUT" "descriptions: ok" \
  "release-check all: ran descriptions check"
assert_contains "$RUN_STDOUT" "examples: ok" \
  "release-check all: ran examples check"
assert_contains "$RUN_STDOUT" "gates:" "release-check all: ran gates check"
assert_contains "$RUN_STDOUT" "docs " \
  "release-check all: gates summary reports docs status"
assert_contains "$RUN_STDOUT" "release-check: all checks passed" \
  "release-check all: prints final summary"

# examples subcommand: matching version pin in synthetic examples must pass.
examples_ok_tmp="$(make_temp_dir)"
cat >"$examples_ok_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
CI_TOOLKIT_VERSION="9.9.9"
EOF
mkdir -p "$examples_ok_tmp/examples/foo"
cat >"$examples_ok_tmp/examples/foo/README.md" <<'EOF'
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v9.9.9/ci-toolkit -o ci-toolkit
git commit -m "chore: [ci] Vendor Gungnir ci-toolkit v9.9.9"
EOF
run_capture "$RELEASE_CHECK" examples "$examples_ok_tmp/ci-toolkit" "$examples_ok_tmp/examples"
assert_status 0 "$RUN_STATUS" "release-check examples: matching pins exit zero"
assert_contains "$RUN_STDOUT" "examples: ok (v9.9.9)" \
  "release-check examples: prints ok with version"

# examples subcommand: stale install URL pin must fail.
examples_stale_tmp="$(make_temp_dir)"
cat >"$examples_stale_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
CI_TOOLKIT_VERSION="9.9.9"
EOF
mkdir -p "$examples_stale_tmp/examples/foo"
cat >"$examples_stale_tmp/examples/foo/README.md" <<'EOF'
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v9.9.8/ci-toolkit -o ci-toolkit
EOF
run_capture "$RELEASE_CHECK" examples "$examples_stale_tmp/ci-toolkit" "$examples_stale_tmp/examples"
assert_status 1 "$RUN_STATUS" "release-check examples: stale install URL exits non-zero"
assert_contains "$RUN_STDERR" "stale version pin" \
  "release-check examples: explains stale pin on stderr"
assert_contains "$RUN_STDERR" "v9.9.8" \
  "release-check examples: stderr names the offending version"

# examples subcommand: stale vendor commit message must also fail.
examples_vendor_tmp="$(make_temp_dir)"
cat >"$examples_vendor_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
CI_TOOLKIT_VERSION="9.9.9"
EOF
mkdir -p "$examples_vendor_tmp/examples/bar"
cat >"$examples_vendor_tmp/examples/bar/README.md" <<'EOF'
git commit -m "chore: [ci] Vendor Gungnir ci-toolkit v9.9.0"
EOF
run_capture "$RELEASE_CHECK" examples "$examples_vendor_tmp/ci-toolkit" "$examples_vendor_tmp/examples"
assert_status 1 "$RUN_STATUS" "release-check examples: stale vendor message exits non-zero"
assert_contains "$RUN_STDERR" "v9.9.0" \
  "release-check examples: stderr names the vendor-message version"

# examples subcommand: missing examples dir is a no-op, not an error.
examples_empty_tmp="$(make_temp_dir)"
cat >"$examples_empty_tmp/ci-toolkit" <<'EOF'
#!/usr/bin/env bash
CI_TOOLKIT_VERSION="9.9.9"
EOF
run_capture "$RELEASE_CHECK" examples "$examples_empty_tmp/ci-toolkit" "$examples_empty_tmp/examples"
assert_status 0 "$RUN_STATUS" "release-check examples: missing dir exits zero"
assert_contains "$RUN_STDOUT" "no examples dir" \
  "release-check examples: explains missing dir on stdout"

# gates subcommand: recursion guard must skip scripts/test when RC_INSIDE_GATES is set.
RC_INSIDE_GATES=1 run_capture "$RELEASE_CHECK" gates
assert_status 0 "$RUN_STATUS" "release-check gates: recursion guard exits zero"
assert_contains "$RUN_STDOUT" "tests skipped (recursive invocation)" \
  "release-check gates: guard reports tests skipped"
assert_contains "$RUN_STDOUT" "docs " \
  "release-check gates: guard still reports docs status"

finish_tests
