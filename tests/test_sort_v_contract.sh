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
  # shellcheck disable=SC2034
  RUN_STDOUT="$(cat "$stdout_file")"
  RUN_STDERR="$(cat "$stderr_file")"
  RUN_STATUS="$status"
}

set -e

# -- Happy path: probe succeeds where sort -V is available ----------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::_require_sort_v"
assert_status 0 "$RUN_STATUS" "sort -V probe succeeds on this host"
assert_eq "" "$RUN_STDERR" "sort -V probe is silent on success"

# -- Failure path: stub sort that does not implement -V -------------------

stub_dir="$(make_temp_dir)"
cat <<'EOF' >"$stub_dir/sort"
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    -V|*V*)
      echo "sort: invalid option -- V" >&2
      exit 2
      ;;
  esac
done
exec /usr/bin/sort "$@"
EOF
chmod +x "$stub_dir/sort"

run_capture bash -c "export PATH='$stub_dir:/usr/bin:/bin'; unset CI_TOOLKIT_SORT_V_OK; source '$ROOT_DIR/ci-toolkit'; ci::_require_sort_v"
assert_status 1 "$RUN_STATUS" "sort -V probe fails when sort lacks -V"
assert_contains "$RUN_STDERR" "requires 'sort -V'" "probe error names the missing feature"
assert_contains "$RUN_STDERR" "brew install coreutils" "probe error points to remediation"

run_capture bash -c "export PATH='$stub_dir:/usr/bin:/bin'; unset CI_TOOLKIT_SORT_V_OK; source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.4 1.2.3"
assert_status 1 "$RUN_STATUS" "ci::version_gt aborts when sort -V missing"

run_capture bash -c "export PATH='$stub_dir:/usr/bin:/bin'; unset CI_TOOLKIT_SORT_V_OK; source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.3 1.2.3"
assert_status 0 "$RUN_STATUS" "ci::version_ge equal-case short-circuits before probe"

run_capture bash -c "export PATH='$stub_dir:/usr/bin:/bin'; unset CI_TOOLKIT_SORT_V_OK; source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.4 1.2.3"
assert_status 1 "$RUN_STATUS" "ci::version_ge aborts when sort -V missing (non-equal)"

# -- Memoization: a successful probe is not re-run ------------------------

run_capture bash -c "
  source '$ROOT_DIR/ci-toolkit'
  ci::_require_sort_v
  # Break sort after first probe; memoized result should still let this pass.
  PATH='$stub_dir:/usr/bin:/bin' ci::_require_sort_v
"
assert_status 0 "$RUN_STATUS" "memoized probe survives a later broken sort"

finish_tests
