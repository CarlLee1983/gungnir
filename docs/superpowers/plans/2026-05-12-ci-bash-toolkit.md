# CI Bash Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an experimental, platform-neutral, single-file Bash CI toolkit that can be executed as a CLI or sourced as a `ci::` function library.

**Architecture:** Keep the public artifact as one root-level `ci-toolkit` Bash file split into library, command, and dispatch sections. Add a tiny Bash test harness under `tests/` so each helper is locked by behavior tests before implementation, then add documentation and release checks around the single-file artifact.

**Tech Stack:** Bash 4+, plain Bash test scripts, optional development-time ShellCheck, Git.

---

## File structure

- Create: `ci-toolkit` — single executable/sourceable Bash artifact. Owns version metadata, experimental notice, library functions, CLI command wrappers, and dispatch guard.
- Create: `tests/assert.sh` — minimal reusable Bash assertions and temp-dir helpers for the test suite.
- Create: `tests/test_source_and_cli.sh` — tests source-mode guard, `help`, `version`, and `log` CLI behavior.
- Create: `tests/test_env_and_tools.sh` — tests environment validation and tool detection without leaking values.
- Create: `tests/test_retry_and_paths.sh` — tests retry behavior and path helper behavior.
- Create: `scripts/test` — runs all behavior tests from a clean shell.
- Create: `scripts/lint` — runs ShellCheck when available and reports a clear skip when absent.
- Create: `scripts/smoke` — runs required smoke checks against `ci-toolkit`.
- Create: `README.md` — documents install, execute mode, source mode, experimental status, and platform-neutral scope.
- Create: `CHANGELOG.md` — records `v0.1.0` experimental initial release notes.

---

### Task 1: Add test harness and source/CLI guard tests

**Files:**
- Create: `tests/assert.sh`
- Create: `tests/test_source_and_cli.sh`
- Create: `scripts/test`
- Modify: `.gitignore`

- [ ] **Step 1: Write the assertion helper**

Create `tests/assert.sh`:

```bash
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
```

- [ ] **Step 2: Write failing source/CLI behavior tests**

Create `tests/test_source_and_cli.sh`:

```bash
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
```

- [ ] **Step 3: Add test runner**

Create `scripts/test`:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for test_file in "$ROOT_DIR"/tests/test_*.sh; do
  printf '==> %s\n' "${test_file#$ROOT_DIR/}"
  bash "$test_file"
done
```

- [ ] **Step 4: Update `.gitignore` for test scratch files**

Modify `.gitignore` to contain exactly:

```gitignore
.omx/
.tmp/
```

- [ ] **Step 5: Run tests to verify they fail because `ci-toolkit` does not exist**

Run:

```bash
chmod +x scripts/test tests/test_source_and_cli.sh
./scripts/test
```

Expected: FAIL with messages mentioning `ci-toolkit: No such file or directory` or `source` failure.

- [ ] **Step 6: Commit failing tests**

Run:

```bash
git add .gitignore scripts/test tests/assert.sh tests/test_source_and_cli.sh
git commit -m "Lock the executable and sourceable toolkit contract" -m "Constraint: The public artifact must support both direct CLI execution and Bash source mode.\nConfidence: high\nScope-risk: narrow\nTested: ./scripts/test fails because ci-toolkit is not implemented yet.\nNot-tested: Runtime helper behavior beyond source and CLI guard tests."
```

---

### Task 2: Implement the initial `ci-toolkit` skeleton, logging, help, and version

**Files:**
- Create: `ci-toolkit`
- Test: `tests/test_source_and_cli.sh`

- [ ] **Step 1: Write minimal implementation for source guard, metadata, logging, help, and dispatch**

Create `ci-toolkit`:

```bash
#!/usr/bin/env bash
# ci-toolkit: experimental platform-neutral helpers for CI Bash scripts.
# Usage as CLI:    ./ci-toolkit help
# Usage as source: source ./ci-toolkit && ci::info "message"
# Runtime: Bash 4+

CI_TOOLKIT_VERSION="0.1.0-experimental"
CI_TOOLKIT_NAME="ci-toolkit"

ci::log() {
  local level="$1"
  shift || true
  local message="$*"

  if [[ "$level" == "debug" && "${CI_TOOLKIT_DEBUG:-}" != "1" ]]; then
    return 0
  fi

  printf '[%s] %s\n' "$level" "$message" >&2
}

ci::info() {
  ci::log info "$@"
}

ci::warn() {
  ci::log warn "$@"
}

ci::error() {
  ci::log error "$@"
}

ci::debug() {
  ci::log debug "$@"
}

ci::die() {
  ci::error "$*"
  return 1
}

ci::usage() {
  cat <<'USAGE'
ci-toolkit - Experimental platform-neutral CI Bash toolkit

Usage:
  ci-toolkit help
  ci-toolkit version
  ci-toolkit log <info|warn|error|debug> <message>

Source mode:
  source ./ci-toolkit
  ci::info "message"

Experimental: CLI and source APIs may change before stabilization.
USAGE
}

ci::cmd_help() {
  ci::usage
}

ci::cmd_version() {
  printf 'ci-toolkit %s\n' "$CI_TOOLKIT_VERSION"
}

ci::cmd_log() {
  local level="${1:-}"
  shift || true

  case "$level" in
    info|warn|error|debug)
      ci::log "$level" "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}

ci::dispatch() {
  local command="${1:-help}"
  if [[ "$#" -gt 0 ]]; then
    shift
  fi

  case "$command" in
    help|-h|--help)
      ci::cmd_help "$@"
      ;;
    version|--version)
      ci::cmd_version "$@"
      ;;
    log)
      ci::cmd_log "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ci::dispatch "$@"
  exit $?
fi
```

- [ ] **Step 2: Make the artifact executable**

Run:

```bash
chmod +x ci-toolkit
```

- [ ] **Step 3: Run source/CLI tests and verify they pass**

Run:

```bash
./scripts/test
```

Expected: PASS for all tests in `tests/test_source_and_cli.sh`.

- [ ] **Step 4: Commit skeleton implementation**

Run:

```bash
git add ci-toolkit
git commit -m "Establish the sourceable executable toolkit shell" -m "Constraint: One public Bash artifact must serve CLI and source API consumers.\nConfidence: high\nScope-risk: narrow\nTested: ./scripts/test\nNot-tested: env, tool, retry, path, lint, and smoke behavior are not implemented yet."
```

---

### Task 3: Add environment validation and tool detection

**Files:**
- Create: `tests/test_env_and_tools.sh`
- Modify: `ci-toolkit`

- [ ] **Step 1: Write failing env/tool tests**

Create `tests/test_env_and_tools.sh`:

```bash
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
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run:

```bash
chmod +x tests/test_env_and_tools.sh
./scripts/test
```

Expected: FAIL with messages indicating `ci::require_env`, `ci::require_tool`, `env`, or `tool` commands are missing.

- [ ] **Step 3: Add env/tool library functions and CLI commands**

Modify `ci-toolkit` by adding these functions after `ci::die`:

```bash
ci::require_env() {
  local name="${1:-}"

  if [[ -z "$name" ]]; then
    ci::error "Usage: ci::require_env VAR_NAME"
    return 64
  fi

  if [[ -z "${!name+x}" || -z "${!name}" ]]; then
    ci::error "Missing required environment variable: $name"
    return 1
  fi

  return 0
}

ci::require_tool() {
  local name="${1:-}"

  if [[ -z "$name" ]]; then
    ci::error "Usage: ci::require_tool TOOL_NAME"
    return 64
  fi

  if ! command -v "$name" >/dev/null 2>&1; then
    ci::error "Missing required tool: $name"
    return 1
  fi

  return 0
}
```

Modify the usage text in `ci::usage` so the `Usage:` block includes:

```text
  ci-toolkit env require VAR_NAME
  ci-toolkit tool require TOOL_NAME
```

Add these command functions after `ci::cmd_log`:

```bash
ci::cmd_env() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    require)
      ci::require_env "${1:-}"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}

ci::cmd_tool() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    require)
      ci::require_tool "${1:-}"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}
```

Add these cases to `ci::dispatch`:

```bash
    env)
      ci::cmd_env "$@"
      ;;
    tool)
      ci::cmd_tool "$@"
      ;;
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
./scripts/test
```

Expected: PASS for source/CLI, env, and tool tests.

- [ ] **Step 5: Commit env/tool support**

Run:

```bash
git add ci-toolkit tests/test_env_and_tools.sh
git commit -m "Protect CI scripts with explicit env and tool checks" -m "Constraint: Helpers must report missing names without leaking secret values.\nConfidence: high\nScope-risk: narrow\nTested: ./scripts/test\nNot-tested: retry, path, lint, and smoke behavior are not implemented yet."
```

---

### Task 4: Add retry and path helpers

**Files:**
- Create: `tests/test_retry_and_paths.sh`
- Modify: `ci-toolkit`

- [ ] **Step 1: Write failing retry/path tests**

Create `tests/test_retry_and_paths.sh`:

```bash
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

counter_dir="$(make_temp_dir)"
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 bash -c 'count_file=\"$counter_dir/count\"; count=0; [[ -f \"$counter_dir/count\" ]] && count=\$(cat \"$counter_dir/count\"); count=\$((count + 1)); printf \"%s\" \"\$count\" >\"$counter_dir/count\"; [[ \"\$count\" -ge 2 ]]'"
assert_status 0 "$RUN_STATUS" "source retry succeeds when later attempt passes"
assert_eq "2" "$(cat "$counter_dir/count")" "source retry stops after successful attempt"
assert_contains "$RUN_STDERR" "Attempt 1/3 failed" "source retry reports failed attempt"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 2 bash -c 'printf out; printf err >&2; exit 7'"
assert_status 7 "$RUN_STATUS" "source retry returns final failing status"
assert_contains "$RUN_STDOUT" "out" "source retry preserves stdout"
assert_contains "$RUN_STDERR" "err" "source retry preserves stderr"
assert_contains "$RUN_STDERR" "Attempt 2/2 failed" "source retry reports final attempt"

cli_counter_dir="$(make_temp_dir)"
run_capture "$ROOT_DIR/ci-toolkit" retry -- bash -c "count_file='$cli_counter_dir/count'; count=0; [[ -f \"\$count_file\" ]] && count=\$(cat \"\$count_file\"); count=\$((count + 1)); printf \"%s\" \"\$count\" >\"\$count_file\"; [[ \"\$count\" -ge 2 ]]"
assert_status 0 "$RUN_STATUS" "CLI retry succeeds when later attempt passes"
assert_eq "2" "$(cat "$cli_counter_dir/count")" "CLI retry stops after success"

path_dir="$(make_temp_dir)"
mkdir -p "$path_dir/a/b/c"
touch "$path_dir/.git"
run_capture bash -c "cd '$path_dir/a/b/c'; source '$ROOT_DIR/ci-toolkit'; ci::find_up .git"
assert_status 0 "$RUN_STATUS" "find_up locates marker"
assert_eq "$path_dir" "$RUN_STDOUT" "find_up prints marker directory"

run_capture bash -c "cd '$path_dir/a/b/c'; source '$ROOT_DIR/ci-toolkit'; ci::root"
assert_status 0 "$RUN_STATUS" "root locates repository marker"
assert_eq "$path_dir" "$RUN_STDOUT" "root prints root directory"

run_capture bash -c "cd '$path_dir/a/b/c'; source '$ROOT_DIR/ci-toolkit'; ci::find_up missing.marker"
assert_status 1 "$RUN_STATUS" "find_up fails when marker is missing"
assert_contains "$RUN_STDERR" "Could not find marker: missing.marker" "find_up reports missing marker"

finish_tests
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run:

```bash
chmod +x tests/test_retry_and_paths.sh
./scripts/test
```

Expected: FAIL with messages indicating `ci::retry`, `retry`, `ci::find_up`, or `ci::root` are missing.

- [ ] **Step 3: Add retry and path library functions**

Modify `ci-toolkit` by adding these functions after `ci::require_tool`:

```bash
ci::retry() {
  local attempts="${1:-}"
  shift || true

  if [[ -z "$attempts" || ! "$attempts" =~ ^[0-9]+$ || "$attempts" -lt 1 ]]; then
    ci::error "Usage: ci::retry ATTEMPTS COMMAND..."
    return 64
  fi

  if [[ "$#" -eq 0 ]]; then
    ci::error "Usage: ci::retry ATTEMPTS COMMAND..."
    return 64
  fi

  local attempt status
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    set +e
    "$@"
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
      return 0
    fi

    ci::warn "Attempt $attempt/$attempts failed with status $status: $*"
  done

  return "$status"
}

ci::find_up() {
  local marker="${1:-}"
  local dir

  if [[ -z "$marker" ]]; then
    ci::error "Usage: ci::find_up MARKER"
    return 64
  fi

  dir="$(pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -e "$dir/$marker" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  ci::error "Could not find marker: $marker"
  return 1
}

ci::root() {
  ci::find_up .git
}
```

Modify the usage text so the `Usage:` block includes:

```text
  ci-toolkit retry -- COMMAND [ARGS...]
```

Add this command function after `ci::cmd_tool`:

```bash
ci::cmd_retry() {
  if [[ "${1:-}" != "--" ]]; then
    ci::usage >&2
    return 64
  fi
  shift

  ci::retry 3 "$@"
}
```

Add this case to `ci::dispatch`:

```bash
    retry)
      ci::cmd_retry "$@"
      ;;
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
./scripts/test
```

Expected: PASS for all test files.

- [ ] **Step 5: Commit retry/path support**

Run:

```bash
git add ci-toolkit tests/test_retry_and_paths.sh
git commit -m "Make flaky CI commands and root discovery reusable" -m "Constraint: Retry must preserve wrapped command output and return the final command status.\nConfidence: high\nScope-risk: narrow\nTested: ./scripts/test\nNot-tested: ShellCheck and release smoke scripts are not in place yet."
```

---

### Task 5: Add lint and smoke scripts

**Files:**
- Create: `scripts/lint`
- Create: `scripts/smoke`
- Modify: `README.md` if it exists from parallel work; otherwise leave README creation to Task 6.

- [ ] **Step 1: Add ShellCheck wrapper**

Create `scripts/lint`:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'shellcheck not found; skipping lint. Install shellcheck for full validation.\n' >&2
  exit 0
fi

shellcheck \
  "$ROOT_DIR/ci-toolkit" \
  "$ROOT_DIR"/scripts/test \
  "$ROOT_DIR"/scripts/lint \
  "$ROOT_DIR"/scripts/smoke \
  "$ROOT_DIR"/tests/assert.sh \
  "$ROOT_DIR"/tests/test_*.sh
```

- [ ] **Step 2: Add required smoke checks**

Create `scripts/smoke`:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/ci-toolkit" help >/dev/null
"$ROOT_DIR/ci-toolkit" version | grep -q 'ci-toolkit'
bash -c "source '$ROOT_DIR/ci-toolkit' && ci::info 'ok'" >/dev/null

printf 'Smoke checks passed\n'
```

- [ ] **Step 3: Make scripts executable**

Run:

```bash
chmod +x scripts/lint scripts/smoke
```

- [ ] **Step 4: Run test, lint, and smoke checks**

Run:

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

Expected:

- `./scripts/test` passes.
- `./scripts/lint` either passes ShellCheck or prints `shellcheck not found; skipping lint.` and exits zero.
- `./scripts/smoke` prints `Smoke checks passed`.

- [ ] **Step 5: Commit validation scripts**

Run:

```bash
git add scripts/lint scripts/smoke
git commit -m "Define local quality gates for the Bash toolkit" -m "Constraint: Release readiness needs behavior tests, optional ShellCheck, and direct smoke checks.\nConfidence: high\nScope-risk: narrow\nTested: ./scripts/test && ./scripts/lint && ./scripts/smoke\nNot-tested: Documentation has not been written yet."
```

---

### Task 6: Add README and changelog for experimental release contract

**Files:**
- Create: `README.md`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write README**

Create `README.md`:

````markdown
# Gungnir CI Toolkit

Experimental platform-neutral Bash helpers for CI scripts.

## Status

This project is experimental. CLI commands and `ci::` source APIs may change before stabilization. Pin a release tag in CI instead of tracking `main`.

## Install in CI

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.0/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

## CLI usage

```bash
./ci-toolkit help
./ci-toolkit version
./ci-toolkit log info "starting checks"
./ci-toolkit env require DEPLOY_TOKEN
./ci-toolkit tool require git
./ci-toolkit retry -- make test
```

## Source API usage

```bash
source ./ci-toolkit

ci::info "starting checks"
ci::require_env DEPLOY_TOKEN
ci::require_tool git
ci::retry 3 make test
```

## Runtime boundary

- Bash 4+ is required.
- Core behavior is platform-neutral and does not depend on a specific CI vendor.
- Optional external tools must be checked with `ci::require_tool` before use.
- Secret values must not be printed by validation helpers.

## Development checks

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

`scripts/lint` uses ShellCheck when installed and exits zero with a clear skip message when ShellCheck is unavailable.
````

- [ ] **Step 2: Write changelog**

Create `CHANGELOG.md`:

```markdown
# Changelog

## v0.1.0 - Experimental initial release

- Added single-file `ci-toolkit` artifact for CLI and source API usage.
- Added logging helpers: `ci::info`, `ci::warn`, `ci::error`, and `ci::debug`.
- Added `ci::die` failure helper.
- Added environment validation through `ci::require_env` and `ci-toolkit env require`.
- Added tool validation through `ci::require_tool` and `ci-toolkit tool require`.
- Added retry support through `ci::retry` and `ci-toolkit retry --`.
- Added path helpers `ci::find_up` and `ci::root`.
- Added Bash behavior tests, optional ShellCheck linting, and smoke checks.

### Breaking changes

None. This is the first experimental release.
```

- [ ] **Step 3: Run validation checks**

Run:

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

Expected: all commands exit zero, with ShellCheck allowed to skip if unavailable.

- [ ] **Step 4: Commit documentation**

Run:

```bash
git add README.md CHANGELOG.md
git commit -m "Explain how to consume the experimental CI toolkit" -m "Constraint: CI consumers need a pinned curl install path and explicit experimental API warning.\nConfidence: high\nScope-risk: narrow\nTested: ./scripts/test && ./scripts/lint && ./scripts/smoke\nNot-tested: No GitHub release artifact has been published."
```

---

### Task 7: Final verification and release-readiness cleanup

**Files:**
- Modify: `ci-toolkit` only if validation finds a concrete issue.
- Modify: `README.md` or `CHANGELOG.md` only if commands or wording disagree with implementation.

- [ ] **Step 1: Run full verification**

Run:

```bash
./scripts/test
./scripts/lint
./scripts/smoke
git status --short
```

Expected:

- Tests pass.
- Lint passes or skips with the documented ShellCheck message.
- Smoke passes.
- `git status --short` is empty.

- [ ] **Step 2: Verify artifact can be copied and executed from a temp directory**

Run:

```bash
tmp_dir="$(mktemp -d)"
cp ci-toolkit "$tmp_dir/ci-toolkit"
chmod +x "$tmp_dir/ci-toolkit"
"$tmp_dir/ci-toolkit" version
bash -c "source '$tmp_dir/ci-toolkit' && ci::info copied-ok"
rm -rf "$tmp_dir"
```

Expected: version prints `ci-toolkit 0.1.0-experimental`; source smoke prints `[info] copied-ok` to stderr and exits zero.

- [ ] **Step 3: Confirm scope boundaries remain intact**

Run:

```bash
grep -R "GITHUB_\|GITLAB_\|CIRCLE_\|build)\|deploy)" ci-toolkit README.md tests scripts || true
```

Expected: no output containing CI-vendor-specific behavior or stable build/deploy command dispatch. The README release URL may contain `github.com` as a distribution host only; that is not a CI runtime dependency.

- [ ] **Step 4: Commit any verification fixes if needed**

If Step 1, 2, or 3 required changes, run:

```bash
git add ci-toolkit README.md CHANGELOG.md tests scripts
git commit -m "Tighten the experimental toolkit release checks" -m "Constraint: The artifact must remain executable, sourceable, and platform-neutral after copying.\nConfidence: high\nScope-risk: narrow\nTested: ./scripts/test && ./scripts/lint && ./scripts/smoke plus temp-dir copy smoke.\nNot-tested: Published release download path."
```

If no files changed, do not create an empty commit.

---

## Self-review

- Spec coverage: The plan covers single-file CLI/source artifact, experimental status, logging, `ci::die`, environment validation, tool detection, retry, path helpers, help/version, platform neutrality, Bash 4+ boundary, tests, optional ShellCheck, smoke checks, README, changelog, and release-readiness verification.
- Scope check: This is one focused implementation plan for the first experimental toolkit. Task command abstractions and CI-vendor adapters remain outside scope.
- Placeholder scan: This plan contains no placeholder implementation steps; code-bearing steps include concrete file contents or exact insertion snippets.
- Type/name consistency: Function and command names match the approved spec: `ci::info`, `ci::warn`, `ci::error`, `ci::debug`, `ci::die`, `ci::require_env`, `ci::require_tool`, `ci::retry`, `ci::find_up`, `ci::root`, `help`, `version`, `log`, `env require`, `tool require`, and `retry --`.
