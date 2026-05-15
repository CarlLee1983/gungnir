# ci-toolkit v0.1.6 utility helpers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `ci-toolkit` v0.1.6 with three new public helpers — `ci::version_gt`/`ci::version_ge`, `ci::strip_prefix`, `ci::trap_err` — wired to both source and CLI modes, with full TDD coverage, release-check passing, and aligned user docs.

**Architecture:** All four helpers live inside the single `ci-toolkit` artifact, following the existing three-section layout (library → command wrappers → dispatch). Each helper gets its own `tests/test_*.sh` file using the project's `run_capture` + `assert_*` harness. Version bump (constant, CHANGELOG, README install URL, user-doc install URLs, and one pinned test assertion) is staged as the first commit so subsequent test files can hard-assert `ci-toolkit 0.1.6`.

**Tech Stack:** Bash 4+, ShellCheck (optional), `sort -V` from coreutils, the in-repo `scripts/test` / `scripts/lint` / `scripts/smoke` / `scripts/release-check` harness. `scripts/check-user-docs.ts` runs through `bun` when available.

**Spec reference:** `docs/superpowers/specs/2026-05-14-ci-toolkit-v016-helpers-design.md`

---

## File Structure

Files created in this plan:
- `tests/test_version_compare.sh` — exercises `ci::version_gt`, `ci::version_ge`, and the `version gt`/`version ge` CLI sub-commands (spec §5.1).
- `tests/test_strip_prefix.sh` — exercises `ci::strip_prefix` and the `strip-prefix` CLI command (spec §5.2).
- `tests/test_trap_err.sh` — exercises `ci::trap_err` (source mode) and the CLI stub (spec §5.3).

Files modified in this plan:
- `ci-toolkit` — bumps `CI_TOOLKIT_VERSION`, adds four new library functions + matching `ci::cmd_*` wrappers + dispatch arms, extends `ci::usage`. All library helpers live next to existing peers; CLI wrappers are appended after `ci::cmd_slack`; dispatch arms are appended before the catch-all `*)` arm.
- `CHANGELOG.md` — prepends a `## v0.1.6 - Added utility helpers` entry. Must use the `## v<version>` heading shape because `scripts/release-check`'s `rc::version` parses `^## v`.
- `README.md` — bumps both the `releases/download/v0.1.5/ci-toolkit` install URL and the "Pin to a tag (`v0.1.5` above)" prose to `v0.1.6`. `rc::artifact` enforces URL/constant parity.
- `docs/user/en/index.md`, `docs/user/zh-TW/index.md` — bump the v0.1.5 install URL to v0.1.6 and add helper coverage (one short example per new helper). Add content **inside existing doc-key sections** — do not introduce new `<!-- doc-key: ... -->` markers, because `scripts/check-user-docs.ts` requires the marker list to stay identical across md/html and across locales.
- `docs/user/en/index.html`, `docs/user/zh-TW/index.html` — mirror the markdown additions and bump the URL.
- `tests/test_source_and_cli.sh` — line 32 pins `"ci-toolkit 0.1.5"`; bump to `"ci-toolkit 0.1.6"`.
- `scripts/smoke` — add `strip-prefix v v0.1.6` and `version gt 0.1.6 0.1.5` exercises.

No other files change. `examples/*` retrofits are explicitly out of scope per spec §2 and §8.

---

## Task 1: Stage the v0.1.6 version bump

This task happens first so every subsequent test can assert `ci-toolkit 0.1.6` and the README/install-URL gate stays green. It does **not** introduce any new behavior — the new helpers and dispatch arms are added in Tasks 2–4.

**Files:**
- Modify: `ci-toolkit:7` (single `CI_TOOLKIT_VERSION` line)
- Modify: `CHANGELOG.md` (prepend a new `## v0.1.6` block)
- Modify: `README.md:24` and `README.md:29`
- Modify: `docs/user/en/index.md:16`
- Modify: `docs/user/zh-TW/index.md:16`
- Modify: `docs/user/en/index.html:109`
- Modify: `docs/user/zh-TW/index.html:109`
- Modify: `tests/test_source_and_cli.sh:32`

- [ ] **Step 1: Bump the version constant**

Edit `ci-toolkit:7`:

Before:
```bash
CI_TOOLKIT_VERSION="0.1.5"
```

After:
```bash
CI_TOOLKIT_VERSION="0.1.6"
```

- [ ] **Step 2: Prepend the CHANGELOG entry**

Edit `CHANGELOG.md` — insert immediately after the `# Changelog` header (so the new entry is the first `## v` heading, which is what `rc::version` reads with `grep -E '^## v' | head -1`):

```markdown
## v0.1.6 - Added utility helpers

- Added `ci::version_gt` and `ci::version_ge` helpers for semver-style comparison, backed by `sort -V`. Accepts `vX.Y.Z`, `X.Y.Z`, `X.Y`, and simple pre-release tags. CLI: `ci-toolkit version gt LHS RHS` / `ci-toolkit version ge LHS RHS` — the no-arg `version` form is preserved.
- Added `ci::strip_prefix PREFIX STRING` and `ci-toolkit strip-prefix` for literal prefix removal. Returns the original string unchanged when the prefix is absent; glob-character prefixes (`*`, `?`, `[abc]`) are treated literally.
- Added `ci::trap_err` (source mode only) which enables `set -E` and installs a default ERR trap printing `exit code`, `file:line`, function, and `BASH_COMMAND`. Leaves `set -e/-u/pipefail` untouched. `ci-toolkit trap-err` (CLI) is an informational stub — see source mode.

### Known limitations

- `set -E` does not propagate `ERR` into every command-substitution subshell in older Bash builds; this is a Bash quirk, not a toolkit issue.
- `ci::trap_err` replaces any previously installed `ERR` trap (standard Bash `trap` semantics).
```

- [ ] **Step 3: Bump the README install URL and prose**

Edit `README.md:24`:

Before:
```
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.5/ci-toolkit -o ci-toolkit
```

After:
```
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.6/ci-toolkit -o ci-toolkit
```

Edit `README.md:29`:

Before:
```
Pin to a tag (`v0.1.5` above). The artifact is a single file with no runtime dependencies beyond Bash 4+.
```

After:
```
Pin to a tag (`v0.1.6` above). The artifact is a single file with no runtime dependencies beyond Bash 4+.
```

- [ ] **Step 4: Bump the user-doc install URLs (md + html, both locales)**

Apply the same `v0.1.5 → v0.1.6` URL substitution to each of:
- `docs/user/en/index.md:16`
- `docs/user/zh-TW/index.md:16`
- `docs/user/en/index.html:109`
- `docs/user/zh-TW/index.html:109`

Each line currently reads:
```
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.5/ci-toolkit -o ci-toolkit
```

And becomes:
```
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.6/ci-toolkit -o ci-toolkit
```

- [ ] **Step 5: Update the pinned version assertion in `tests/test_source_and_cli.sh`**

Edit `tests/test_source_and_cli.sh:32`:

Before:
```bash
assert_eq "ci-toolkit 0.1.5" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.5"
```

After:
```bash
assert_eq "ci-toolkit 0.1.6" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.6"
```

- [ ] **Step 6: Run the existing test suite and release-check**

Run: `./scripts/test`
Expected: every existing test file prints `All tests passed`. The retried `tests/test_release_check.sh` is the relevant gate here — it confirms `CI_TOOLKIT_VERSION` matches the top CHANGELOG entry and that the README install URL matches.

Run: `./scripts/release-check version` then `./scripts/release-check artifact`
Expected stdout:
```
version: ok (0.1.6)
```
```
artifact: ok
```

If either fails, re-check the steps above — the most common slip is forgetting the `## v` (lowercase v) prefix on the CHANGELOG heading.

- [ ] **Step 7: Commit**

```bash
git add ci-toolkit CHANGELOG.md README.md \
  docs/user/en/index.md docs/user/zh-TW/index.md \
  docs/user/en/index.html docs/user/zh-TW/index.html \
  tests/test_source_and_cli.sh
git commit -m "chore: [release] Bump CI_TOOLKIT_VERSION to 0.1.6"
```

---

## Task 2: `ci::version_gt` / `ci::version_ge` + `version gt|ge` CLI

Adds two predicate helpers and extends the existing `version` CLI command to also act as a sub-dispatcher. The no-arg `version` form must keep working — `tests/test_source_and_cli.sh` already asserts that.

**Files:**
- Create: `tests/test_version_compare.sh`
- Modify: `ci-toolkit` — add `ci::version_gt`, `ci::version_ge` after `ci::git_latest_tag`; extend `ci::cmd_version` to handle sub-args; update `ci::usage`.

- [ ] **Step 1: Write the failing test file**

Create `tests/test_version_compare.sh` with the following content (mirrors the `run_capture` pattern of `tests/test_retry_delay.sh`):

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

# -- Source mode: ci::version_gt (spec §5.1 #1, #2, #3, #7, #8) -----------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.4 1.2.3"
assert_status 0 "$RUN_STATUS" "source version_gt 1.2.4 > 1.2.3 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.3 1.2.4"
assert_status 1 "$RUN_STATUS" "source version_gt 1.2.3 > 1.2.4 exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.3 1.2.3"
assert_status 1 "$RUN_STATUS" "source version_gt 1.2.3 > 1.2.3 exits 1 (equal)"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt v1.2.4 v1.2.3"
assert_status 0 "$RUN_STATUS" "source version_gt tolerates v-prefix"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.0.0 1.0.0-rc1"
assert_status 0 "$RUN_STATUS" "source version_gt orders release above pre-release"

# -- Source mode: ci::version_ge (spec §5.1 #4, #5, #6) -------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.3 1.2.3"
assert_status 0 "$RUN_STATUS" "source version_ge 1.2.3 >= 1.2.3 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.4 1.2.3"
assert_status 0 "$RUN_STATUS" "source version_ge 1.2.4 >= 1.2.3 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_ge 1.2.3 1.2.4"
assert_status 1 "$RUN_STATUS" "source version_ge 1.2.3 >= 1.2.4 exits 1"

# -- Source mode: usage errors (spec §5.1 #9, #10) ------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt 1.2.3"
assert_status 64 "$RUN_STATUS" "source version_gt missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::version_gt LHS RHS" \
  "source version_gt missing arg prints usage"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::version_gt '' 1.0.0"
assert_status 64 "$RUN_STATUS" "source version_gt empty LHS exits 64"

# -- CLI mode (spec §5.1 #11, #12, #13) -----------------------------------

run_capture "$ROOT_DIR/ci-toolkit" version gt 1.2.4 1.2.3
assert_status 0 "$RUN_STATUS" "CLI version gt 1.2.4 1.2.3 exits 0"

run_capture "$ROOT_DIR/ci-toolkit" version
assert_status 0 "$RUN_STATUS" "CLI version (no args) still exits 0"
assert_contains "$RUN_STDOUT" "ci-toolkit 0.1.6" \
  "CLI version (no args) still prints toolkit + version"

run_capture "$ROOT_DIR/ci-toolkit" version gt 1.2.3
assert_status 64 "$RUN_STATUS" "CLI version gt with missing arg exits 64"

finish_tests
```

- [ ] **Step 2: Run the new test file to confirm it fails**

Run: `bash tests/test_version_compare.sh`
Expected: at minimum the source-mode tests fail with `ci::version_gt: command not found`, and `version gt` CLI cases fail because `ci::cmd_version` doesn't accept sub-args yet. `TEST_FAILURES` is non-zero, exit status is 1.

- [ ] **Step 3: Add `ci::version_gt` and `ci::version_ge` to `ci-toolkit`**

Insert the two helpers immediately after the existing `ci::git_latest_tag` function (around `ci-toolkit:220`), keeping the same `# @description` style used elsewhere:

```bash
# @description Compare two version-ish strings; exit 0 iff LHS > RHS (sort -V order).
ci::version_gt() {
  if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
    ci::error "Usage: ci::version_gt LHS RHS"
    return 64
  fi
  [[ "$1" != "$2" ]] || return 1
  local smaller
  smaller=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)
  [[ "$smaller" == "$2" ]]
}

# @description Compare two version-ish strings; exit 0 iff LHS >= RHS (sort -V order).
ci::version_ge() {
  if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
    ci::error "Usage: ci::version_ge LHS RHS"
    return 64
  fi
  [[ "$1" == "$2" ]] || ci::version_gt "$1" "$2"
}
```

The `# @description` comments are mandatory: `scripts/release-check`'s `rc::descriptions` runs `ci-toolkit ls` and fails if any public helper prints `(No description)`.

- [ ] **Step 4: Extend `ci::cmd_version` to dispatch `gt` / `ge` sub-args**

Replace the existing `ci::cmd_version` body (currently at `ci-toolkit:316`) with:

```bash
ci::cmd_version() {
  local subcommand="${1:-}"

  case "$subcommand" in
    "")
      printf '%s %s\n' "$CI_TOOLKIT_NAME" "$CI_TOOLKIT_VERSION"
      ;;
    gt)
      shift
      ci::version_gt "$@"
      ;;
    ge)
      shift
      ci::version_ge "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}
```

This preserves the existing zero-arg behavior (the `""` case prints `ci-toolkit 0.1.6`) and routes `gt`/`ge` to the new library helpers. No change needed to `ci::dispatch`, because `version` already routes here.

- [ ] **Step 5: Extend `ci::usage` to advertise the new sub-commands**

In `ci-toolkit`'s `ci::usage` heredoc (currently at lines 284–306), add two lines under the `ci-toolkit version` line:

Before:
```
  ci-toolkit version
  ci-toolkit log <info|warn|error|debug> <message>
```

After:
```
  ci-toolkit version
  ci-toolkit version gt LHS RHS
  ci-toolkit version ge LHS RHS
  ci-toolkit log <info|warn|error|debug> <message>
```

- [ ] **Step 6: Re-run the new test and the full suite**

Run: `bash tests/test_version_compare.sh`
Expected: every assertion prints `ok - …`, and the file ends with `All tests passed`.

Run: `./scripts/test`
Expected: every test file in the loop ends in `All tests passed`, including the regression check in `tests/test_source_and_cli.sh` (which now expects `0.1.6`).

- [ ] **Step 7: Lint**

Run: `./scripts/lint`
Expected: either `lint ok` or a clean `shellcheck not installed; skipping` notice — never a real warning on the new helpers.

- [ ] **Step 8: Commit**

```bash
git add ci-toolkit tests/test_version_compare.sh
git commit -m "feat: [toolkit] Add ci::version_gt / ci::version_ge with CLI sub-commands"
```

---

## Task 3: `ci::strip_prefix` + `strip-prefix` CLI

Adds a single source helper plus a CLI wrapper. The library form prints to stdout; the CLI form is a thin pass-through.

**Files:**
- Create: `tests/test_strip_prefix.sh`
- Modify: `ci-toolkit` — add `ci::strip_prefix` library function, `ci::cmd_strip_prefix` wrapper, `strip-prefix` arm in `ci::dispatch`, plus a `ci::usage` line.

- [ ] **Step 1: Write the failing test file**

Create `tests/test_strip_prefix.sh`:

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

# -- Source mode (spec §5.2 #1–#6) ----------------------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v v1.2.3"
assert_status 0 "$RUN_STATUS" "source strip_prefix v v1.2.3 exits 0"
assert_eq "1.2.3" "${RUN_STDOUT%$'\n'}" "source strip_prefix v v1.2.3 strips the v"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v 1.2.3"
assert_status 0 "$RUN_STATUS" "source strip_prefix no-match exits 0"
assert_eq "1.2.3" "${RUN_STDOUT%$'\n'}" "source strip_prefix no-match returns original"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix '' v1.2.3"
assert_status 0 "$RUN_STATUS" "source strip_prefix empty prefix exits 0"
assert_eq "v1.2.3" "${RUN_STDOUT%$'\n'}" "source strip_prefix empty prefix is a no-op"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v ''"
assert_status 0 "$RUN_STATUS" "source strip_prefix empty string exits 0"
assert_eq "" "${RUN_STDOUT%$'\n'}" "source strip_prefix empty string returns empty"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix '*' '*foo'"
assert_status 0 "$RUN_STATUS" "source strip_prefix glob-char prefix exits 0"
assert_eq "foo" "${RUN_STDOUT%$'\n'}" "source strip_prefix treats * literally"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::strip_prefix v"
assert_status 64 "$RUN_STATUS" "source strip_prefix missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::strip_prefix PREFIX STRING" \
  "source strip_prefix missing arg prints usage"

# -- CLI mode (spec §5.2 #7) ----------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" strip-prefix v v1.2.3
assert_status 0 "$RUN_STATUS" "CLI strip-prefix v v1.2.3 exits 0"
assert_eq "1.2.3" "${RUN_STDOUT%$'\n'}" "CLI strip-prefix v v1.2.3 prints stripped value"

finish_tests
```

- [ ] **Step 2: Run the new test to confirm it fails**

Run: `bash tests/test_strip_prefix.sh`
Expected: source-mode assertions fail with `ci::strip_prefix: command not found`; CLI assertions fail with usage on stderr because the dispatch arm doesn't exist yet. Exit status non-zero.

- [ ] **Step 3: Add `ci::strip_prefix` library function**

Insert immediately after `ci::version_ge` (added in Task 2):

```bash
# @description Strip a literal prefix from a string; pass through unchanged if absent.
ci::strip_prefix() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::strip_prefix PREFIX STRING"
    return 64
  fi
  local prefix="$1"
  local value="$2"
  printf '%s\n' "${value#"$prefix"}"
}
```

The quotes around `"$prefix"` inside `${value#"$prefix"}` are load-bearing — they disable glob interpretation so callers can strip `*`, `?`, `[abc]` literally. Do not remove them.

- [ ] **Step 4: Add the `ci::cmd_strip_prefix` wrapper**

Append after `ci::cmd_slack` (currently around `ci-toolkit:450`), before `ci::dispatch`:

```bash
ci::cmd_strip_prefix() {
  if [[ $# -lt 2 ]]; then
    ci::usage >&2
    return 64
  fi
  ci::strip_prefix "$1" "$2"
}
```

- [ ] **Step 5: Add the `strip-prefix` arm in `ci::dispatch`**

In `ci::dispatch`'s `case` statement, add a new arm immediately before the final `*)` catch-all:

```bash
    strip-prefix)
      ci::cmd_strip_prefix "$@"
      ;;
```

- [ ] **Step 6: Advertise it in `ci::usage`**

In the `ci::usage` heredoc, add a line near the other helper commands (e.g., after `ci-toolkit env default VAR_NAME DEFAULT_VALUE`):

```
  ci-toolkit strip-prefix PREFIX STRING
```

- [ ] **Step 7: Re-run the focused test and the full suite**

Run: `bash tests/test_strip_prefix.sh`
Expected: ends in `All tests passed`.

Run: `./scripts/test`
Expected: every test file passes.

- [ ] **Step 8: Lint**

Run: `./scripts/lint`
Expected: no warnings.

- [ ] **Step 9: Commit**

```bash
git add ci-toolkit tests/test_strip_prefix.sh
git commit -m "feat: [toolkit] Add ci::strip_prefix helper and CLI command"
```

---

## Task 4: `ci::trap_err` + CLI stub

Adds a single source-only helper. The CLI form deliberately refuses to do anything because an `ERR` trap installed inside the dispatch shell would fire immediately when the toolkit process exits — it is documented as an informational stub.

**Files:**
- Create: `tests/test_trap_err.sh`
- Modify: `ci-toolkit` — add `ci::trap_err` library function, `ci::cmd_trap_err` informational stub, `trap-err` arm in `ci::dispatch`, plus a `ci::usage` line.

- [ ] **Step 1: Write the failing test file**

Create `tests/test_trap_err.sh`. All source-mode cases run inside `bash -c` subshells to keep the test harness clean:

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

# -- Source mode (spec §5.3 #1–#5) ----------------------------------------

# #1, #2: ERR trap fires on `false`, captures exit code and BASH_COMMAND
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; false; true"
assert_contains "$RUN_STDERR" "[error] command failed (exit=1) at" \
  "trap_err prints error prefix and exit code on false"
assert_contains "$RUN_STDERR" "false" \
  "trap_err captures BASH_COMMAND (false)"

# #3: ERR trap fires inside a function and reports the function name
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; f() { false; }; f; true"
assert_contains "$RUN_STDERR" "in f" \
  "trap_err reports FUNCNAME when ERR fires inside a function"

# #4: Without set -e, an echo after the failing command still runs
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; false; echo after-failure"
assert_contains "$RUN_STDOUT" "after-failure" \
  "trap_err does not call exit; subsequent commands run"

# #5: Two consecutive ci::trap_err calls — one error line per failure
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::trap_err; ci::trap_err; false; true"
error_lines=$(printf '%s\n' "$RUN_STDERR" | grep -c '\[error\] command failed' || true)
if [[ "$error_lines" -eq 1 ]]; then
  pass "trap_err idempotent: second install replaces first (one error line per failure)"
else
  fail "trap_err idempotent: expected 1 error line, got $error_lines"
fi

# -- CLI mode (spec §5.3 #6) ----------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" trap-err
assert_status 64 "$RUN_STATUS" "CLI trap-err exits 64"
assert_contains "$RUN_STDERR" "only effective in source mode" \
  "CLI trap-err explains it is a source-mode helper"

finish_tests
```

- [ ] **Step 2: Run the new test to confirm it fails**

Run: `bash tests/test_trap_err.sh`
Expected: source-mode tests fail with `ci::trap_err: command not found`; CLI test fails because the dispatch arm doesn't exist yet. Exit status non-zero.

- [ ] **Step 3: Add `ci::trap_err` library function**

Insert immediately after `ci::strip_prefix` (added in Task 3):

```bash
# @description Install a default ERR trap that prints exit code, file:line, function, and BASH_COMMAND.
ci::trap_err() {
  set -E
  # shellcheck disable=SC2016  # variables expand at trap time, not now
  trap 'printf "[error] command failed (exit=%s) at %s:%s in %s: %s\n" \
    "$?" "${BASH_SOURCE[0]}" "${LINENO}" "${FUNCNAME[0]:-main}" "${BASH_COMMAND}" >&2' ERR
}
```

Critical: the outer single quotes on the `trap` argument defer all five expansions until trap-fire time. Do not rewrite the trap body with double quotes — `$?`, `${BASH_SOURCE[0]}`, `${LINENO}`, `${FUNCNAME[0]}`, and `${BASH_COMMAND}` must all evaluate inside the trap, not at install time. The `# shellcheck disable=SC2016` comment is required to silence ShellCheck's "variables don't expand in single quotes" hint.

- [ ] **Step 4: Add the `ci::cmd_trap_err` informational stub**

Append after `ci::cmd_strip_prefix` (added in Task 3), before `ci::dispatch`:

```bash
ci::cmd_trap_err() {
  ci::error "ci::trap_err: only effective in source mode (use: source ci-toolkit && ci::trap_err)"
  return 64
}
```

Do **not** call `ci::trap_err` from this CLI wrapper. Installing an `ERR` trap inside the short-lived CLI dispatch shell would either be a no-op (no error fires before exit) or worse, double-print on the exiting shell. The CLI form is informational only.

- [ ] **Step 5: Add the `trap-err` arm in `ci::dispatch`**

Add an arm immediately after the `strip-prefix` arm added in Task 3, still before the final `*)`:

```bash
    trap-err)
      ci::cmd_trap_err "$@"
      ;;
```

- [ ] **Step 6: Advertise it in `ci::usage`**

In the `ci::usage` heredoc, add a line near the other commands (e.g., after `ci-toolkit strip-prefix PREFIX STRING`):

```
  ci-toolkit trap-err
```

- [ ] **Step 7: Re-run the focused test and the full suite**

Run: `bash tests/test_trap_err.sh`
Expected: ends in `All tests passed`.

Run: `./scripts/test`
Expected: every test file passes.

- [ ] **Step 8: Lint**

Run: `./scripts/lint`
Expected: no warnings.

- [ ] **Step 9: Commit**

```bash
git add ci-toolkit tests/test_trap_err.sh
git commit -m "feat: [toolkit] Add ci::trap_err source helper and CLI stub"
```

---

## Task 5: User docs, smoke checks, release-check

Closes the release loop: add helper coverage to user docs (both locales × md/html), exercise the new CLI shapes in `scripts/smoke`, and run the full `./scripts/release-check all` gate.

**Files:**
- Modify: `docs/user/en/index.md` — extend the "Advanced tools" doc-key section.
- Modify: `docs/user/zh-TW/index.md` — mirror.
- Modify: `docs/user/en/index.html` — mirror under `<!-- doc-key: advanced-tools -->`.
- Modify: `docs/user/zh-TW/index.html` — mirror.
- Modify: `scripts/smoke` — add two CLI exercises.

Do not introduce any new `<!-- doc-key: ... -->` markers — `scripts/check-user-docs.ts` enforces marker parity across md/html and across locales. Add the new helpers inside the existing `advanced-tools` section.

- [ ] **Step 1: Extend `docs/user/en/index.md` under the Advanced tools section**

Append to the `<!-- doc-key: advanced-tools -->` section (after the current "Path Discovery" subsection, before the next `<!-- doc-key: -->` marker):

````markdown
### Version-style Comparison

For comparing semver-ish strings (tool versions, git tags) without writing brittle lexicographic `[[ "$a" > "$b" ]]` checks. Backed by `sort -V`.

```bash
# Source mode
if ci::version_ge "$BUN_VERSION" "1.1.0"; then
  ci::info "bun is new enough"
fi

# CLI mode
./ci-toolkit version gt 1.2.4 1.2.3   # exits 0
./ci-toolkit version ge 1.2.3 1.2.3   # exits 0
```

The helpers accept `vX.Y.Z`, `X.Y.Z`, `X.Y`, and simple pre-release tags. Build metadata (`1.0.0+build42`) sorts lexicographically by the tail — fine for CI, not a SemVer-2.0 promise.

### Prefix stripping

A small wrapper around Bash's `${var#prefix}` that also works from CLI pipelines and treats glob characters literally.

```bash
# Source mode
TAG=$(ci::git_latest_tag v)
VERSION=$(ci::strip_prefix v "$TAG")   # v1.2.3 -> 1.2.3

# CLI mode
./ci-toolkit strip-prefix v v1.2.3     # -> 1.2.3
```

If the prefix is absent, the original string is returned unchanged.

### Default ERR trap

`ci::trap_err` installs a one-line ERR trap so failures inside CI scripts report `exit code`, `file:line`, function name, and the failing `BASH_COMMAND`. Source mode only — the CLI form is informational.

```bash
source ./ci-toolkit
ci::trap_err

# Anywhere below, a failing command prints:
# [error] command failed (exit=1) at deploy.sh:42 in run_migrations: psql -c "..."
```

It enables `set -E` (errtrace) so the trap propagates into functions, but leaves `set -e/-u/pipefail` alone — your script keeps its existing flow control. A second `ci::trap_err` call replaces the first (standard Bash `trap` semantics).
````

- [ ] **Step 2: Mirror the additions in `docs/user/zh-TW/index.md`**

Append the following Traditional Chinese (Taiwan usage) content to the `<!-- doc-key: advanced-tools -->` section of `docs/user/zh-TW/index.md`, placed after the existing 路徑發現 subsection. Code blocks stay identical to the English version — only prose is translated.

````markdown
### 版本字串比較

用於比較類 semver 字串（工具版本、git tag）時，無須再手刻容易出錯的字典序檢查 `[[ "$a" > "$b" ]]`。底層使用 `sort -V`。

```bash
# Source 模式
if ci::version_ge "$BUN_VERSION" "1.1.0"; then
  ci::info "bun is new enough"
fi

# CLI 模式
./ci-toolkit version gt 1.2.4 1.2.3   # exits 0
./ci-toolkit version ge 1.2.3 1.2.3   # exits 0
```

這兩個輔助函式可接受 `vX.Y.Z`、`X.Y.Z`、`X.Y` 以及簡單的 pre-release tag。build metadata（如 `1.0.0+build42`）會以字典序比較其尾段 — 對 CI 場景已夠用，但不等同於 SemVer 2.0 嚴格規範。

### 字串前綴移除

`${var#prefix}` 的小型包裝，CLI 模式同樣可用，且會將 glob 字元視為字面值。

```bash
# Source 模式
TAG=$(ci::git_latest_tag v)
VERSION=$(ci::strip_prefix v "$TAG")   # v1.2.3 -> 1.2.3

# CLI 模式
./ci-toolkit strip-prefix v v1.2.3     # -> 1.2.3
```

若前綴不存在，原字串會原封不動回傳。

### 預設 ERR 陷阱

`ci::trap_err` 安裝一條精簡的 ERR trap，CI 腳本中任何失敗的指令都會印出 `exit code`、`file:line`、函式名稱與失敗的 `BASH_COMMAND`。僅在 source 模式生效 — CLI 形式只是說明用途。

```bash
source ./ci-toolkit
ci::trap_err

# 之後任何失敗的指令都會印出：
# [error] command failed (exit=1) at deploy.sh:42 in run_migrations: psql -c "..."
```

它會啟用 `set -E`（errtrace），讓 trap 可傳播進入函式內部，但不會動 `set -e/-u/pipefail` — 您原本的流程控制完全保留。第二次呼叫 `ci::trap_err` 會直接取代前一次（Bash `trap` 標準語意）。
````

- [ ] **Step 3: Mirror the additions in `docs/user/en/index.html`**

Inside `<!-- doc-key: advanced-tools -->`'s `<section id="advanced-tools">` (around line 209), append three new `<h3>` blocks after the Path Discovery block. Wrap code in `<pre><code>...</code></pre>` matching the surrounding house style:

```html
<h3 class="mt-12">Version-style Comparison</h3>
<p>For comparing semver-ish strings (tool versions, git tags) without writing brittle lexicographic <code>[[ "$a" &gt; "$b" ]]</code> checks. Backed by <code>sort -V</code>.</p>
<pre><code># Source mode
if ci::version_ge "$BUN_VERSION" "1.1.0"; then
  ci::info "bun is new enough"
fi

# CLI mode
./ci-toolkit version gt 1.2.4 1.2.3   # exits 0
./ci-toolkit version ge 1.2.3 1.2.3   # exits 0</code></pre>
<p>The helpers accept <code>vX.Y.Z</code>, <code>X.Y.Z</code>, <code>X.Y</code>, and simple pre-release tags. Build metadata (<code>1.0.0+build42</code>) sorts lexicographically by the tail — fine for CI, not a SemVer-2.0 promise.</p>

<h3 class="mt-12">Prefix stripping</h3>
<p>A small wrapper around Bash's <code>${var#prefix}</code> that also works from CLI pipelines and treats glob characters literally.</p>
<pre><code># Source mode
TAG=$(ci::git_latest_tag v)
VERSION=$(ci::strip_prefix v "$TAG")   # v1.2.3 -> 1.2.3

# CLI mode
./ci-toolkit strip-prefix v v1.2.3     # -> 1.2.3</code></pre>
<p>If the prefix is absent, the original string is returned unchanged.</p>

<h3 class="mt-12">Default ERR trap</h3>
<p><code>ci::trap_err</code> installs a one-line ERR trap so failures inside CI scripts report exit code, <code>file:line</code>, function name, and the failing <code>BASH_COMMAND</code>. Source mode only — the CLI form is informational.</p>
<pre><code>source ./ci-toolkit
ci::trap_err

# Anywhere below, a failing command prints:
# [error] command failed (exit=1) at deploy.sh:42 in run_migrations: psql -c "..."</code></pre>
<p>It enables <code>set -E</code> (errtrace) so the trap propagates into functions, but leaves <code>set -e/-u/pipefail</code> alone — your script keeps its existing flow control. A second <code>ci::trap_err</code> call replaces the first (standard Bash <code>trap</code> semantics).</p>
```

- [ ] **Step 4: Mirror the additions in `docs/user/zh-TW/index.html`**

Inside `<!-- doc-key: advanced-tools -->`'s `<section id="advanced-tools">` (around line 209 of `docs/user/zh-TW/index.html`), append three new `<h3>` blocks after the existing 路徑發現 block:

```html
<h3 class="mt-12">版本字串比較</h3>
<p>用於比較類 semver 字串（工具版本、git tag）時，無須再手刻容易出錯的字典序檢查 <code>[[ "$a" &gt; "$b" ]]</code>。底層使用 <code>sort -V</code>。</p>
<pre><code># Source 模式
if ci::version_ge "$BUN_VERSION" "1.1.0"; then
  ci::info "bun is new enough"
fi

# CLI 模式
./ci-toolkit version gt 1.2.4 1.2.3   # exits 0
./ci-toolkit version ge 1.2.3 1.2.3   # exits 0</code></pre>
<p>這兩個輔助函式可接受 <code>vX.Y.Z</code>、<code>X.Y.Z</code>、<code>X.Y</code> 以及簡單的 pre-release tag。build metadata（如 <code>1.0.0+build42</code>）會以字典序比較其尾段 — 對 CI 場景已夠用，但不等同於 SemVer 2.0 嚴格規範。</p>

<h3 class="mt-12">字串前綴移除</h3>
<p><code>${var#prefix}</code> 的小型包裝，CLI 模式同樣可用，且會將 glob 字元視為字面值。</p>
<pre><code># Source 模式
TAG=$(ci::git_latest_tag v)
VERSION=$(ci::strip_prefix v "$TAG")   # v1.2.3 -> 1.2.3

# CLI 模式
./ci-toolkit strip-prefix v v1.2.3     # -> 1.2.3</code></pre>
<p>若前綴不存在，原字串會原封不動回傳。</p>

<h3 class="mt-12">預設 ERR 陷阱</h3>
<p><code>ci::trap_err</code> 安裝一條精簡的 ERR trap，CI 腳本中任何失敗的指令都會印出 <code>exit code</code>、<code>file:line</code>、函式名稱與失敗的 <code>BASH_COMMAND</code>。僅在 source 模式生效 — CLI 形式只是說明用途。</p>
<pre><code>source ./ci-toolkit
ci::trap_err

# 之後任何失敗的指令都會印出：
# [error] command failed (exit=1) at deploy.sh:42 in run_migrations: psql -c "..."</code></pre>
<p>它會啟用 <code>set -E</code>（errtrace），讓 trap 可傳播進入函式內部，但不會動 <code>set -e/-u/pipefail</code> — 您原本的流程控制完全保留。第二次呼叫 <code>ci::trap_err</code> 會直接取代前一次（Bash <code>trap</code> 標準語意）。</p>
```

- [ ] **Step 5: Extend `scripts/smoke` with new CLI exercises**

Edit `scripts/smoke`. Before the final `printf 'Smoke checks passed\n'` line, add:

```bash
"$ROOT_DIR/ci-toolkit" strip-prefix v v0.1.6 | grep -q '^0\.1\.6$'
"$ROOT_DIR/ci-toolkit" version gt 0.1.6 0.1.5
```

The first asserts `strip-prefix` produces the expected stripped value; the second asserts the predicate exits 0. Both abort the script with `set -euo pipefail` if they regress.

After the edit, `scripts/smoke` looks like:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/ci-toolkit" help >/dev/null
"$ROOT_DIR/ci-toolkit" version | grep -q 'ci-toolkit'
bash -c "source '$ROOT_DIR/ci-toolkit' && ci::info 'ok'" >/dev/null
"$ROOT_DIR/ci-toolkit" strip-prefix v v0.1.6 | grep -q '^0\.1\.6$'
"$ROOT_DIR/ci-toolkit" version gt 0.1.6 0.1.5

printf 'Smoke checks passed\n'
```

- [ ] **Step 6: Run smoke + docs-alignment + the full release-check gate**

Run: `./scripts/smoke`
Expected stdout: `Smoke checks passed`.

Run: `bun run scripts/check-user-docs.ts` (skip if `bun` is not installed — the same fall-through happens in `release-check`)
Expected output:
```
✓ docs/user/en: 9 Markdown/HTML topics aligned
✓ docs/user/zh-TW: 9 Markdown/HTML topics aligned
```

If alignment fails, the most likely cause is accidentally adding a new `<!-- doc-key: ... -->` marker in one surface but not the other. Re-check Steps 1–4 — no new markers should appear.

Run: `./scripts/release-check all`
Expected stdout ends with: `release-check: all checks passed`.

The gate covers: version constant ↔ CHANGELOG match, README URL match, every public `ci::` helper has a `# @description`, the boundary grep finds no CI-vendor / forbidden command names, the standalone artifact still smoke-passes, the test suite passes, lint passes, smoke passes, and `check-user-docs.ts` (if `bun` is installed) is green.

- [ ] **Step 7: Commit**

```bash
git add docs/user/en/index.md docs/user/zh-TW/index.md \
  docs/user/en/index.html docs/user/zh-TW/index.html \
  scripts/smoke
git commit -m "docs: [user-docs] Document v0.1.6 helpers and exercise them in smoke"
```

- [ ] **Step 8: Final verification**

Run: `git log --oneline -6`
Expected: five new commits in order — version bump, version_gt/ge, strip_prefix, trap_err, docs/smoke.

Run: `./scripts/release-check all` once more from a clean tree (no staged or unstaged changes).
Expected: `release-check: all checks passed`.

The branch is now ready for the v0.1.6 release — no further code changes are in scope per spec §2 / §8 (no example retrofits, no `strip_suffix` / `version_eq`, no EXIT-cleanup helper).
