# CI Toolkit Release-Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a reproducible release-readiness pass for `ci-toolkit` v0.1.0 — normalize the version constant, add a `scripts/release-check` verification harness, and record evidence in a release-readiness note, without adding any new `ci::` helpers or public CLI commands.

**Architecture:** Add a small verification layer around the existing single-file artifact. One new script (`scripts/release-check`) exposes verifier subcommands (`version`, `boundary`, `copy-smoke`, `gates`, `all`) so each check is independently testable. Behavior tests live alongside the existing harness at `tests/test_release_check.sh`. Evidence is captured to a release-readiness note under `docs/superpowers/release-readiness/`.

**Tech Stack:** Bash 4+, existing `tests/assert.sh` helpers, ShellCheck (optional), no new runtime dependencies.

---

## Decision: Version Normalization

The spec offers two options for resolving the `CI_TOOLKIT_VERSION` vs `CHANGELOG.md` mismatch. **This plan takes the preferred option:** normalize the constant to `0.1.0`. The "experimental" status stays in human-facing prose (README header, CHANGELOG entry title, `ci::usage` text), so machine-readable version output is simple while the experimental warning is preserved in documentation.

## File Structure

Files created or modified by this plan:

- **Modify** `ci-toolkit:7` — change `CI_TOOLKIT_VERSION` to `0.1.0`.
- **Modify** `tests/test_source_and_cli.sh` — add exact-version assertion.
- **Create** `scripts/release-check` — verification harness with five subcommands.
- **Create** `tests/test_release_check.sh` — behavior tests for the harness.
- **Create** `docs/superpowers/release-readiness/2026-05-12-v0.1.0.md` — evidence record.
- **Modify** `README.md` — add a short "Release readiness" pointer to the new script and note.

Each file has one clear responsibility. The release-check script is structured as named functions plus a dispatch so individual checks can be exercised in tests without running the whole pipeline.

---

## Task 1: Normalize `CI_TOOLKIT_VERSION` to `0.1.0`

**Files:**
- Modify: `tests/test_source_and_cli.sh:29-31`
- Modify: `ci-toolkit:7`

- [ ] **Step 1: Add a failing exact-version assertion**

Replace the existing version-command block in `tests/test_source_and_cli.sh` (currently lines 29–31) with the stricter version below. The new line asserts an exact match instead of just a substring.

```bash
run_capture "$ROOT_DIR/ci-toolkit" version
assert_status 0 "$RUN_STATUS" "version command exits zero"
assert_contains "$RUN_STDOUT" "ci-toolkit" "version command prints tool name"
assert_eq "ci-toolkit 0.1.0" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.0"
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `bash tests/test_source_and_cli.sh`

Expected: a `not ok` line for `version command prints normalized 0.1.0` reporting `expected [ci-toolkit 0.1.0], got [ci-toolkit 0.1.0-experimental]`, and a non-zero exit.

- [ ] **Step 3: Normalize the constant**

Edit `ci-toolkit` line 7 from:

```bash
CI_TOOLKIT_VERSION="0.1.0-experimental"
```

to:

```bash
CI_TOOLKIT_VERSION="0.1.0"
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `bash tests/test_source_and_cli.sh`

Expected: all `ok -` lines, exit 0.

- [ ] **Step 5: Run the full quality gates to confirm nothing else regressed**

Run: `./scripts/test && ./scripts/smoke`

Expected: both succeed, exit 0.

- [ ] **Step 6: Commit**

```bash
git add ci-toolkit tests/test_source_and_cli.sh
git commit -m "fix: [ci-toolkit] Normalize CI_TOOLKIT_VERSION to 0.1.0"
```

---

## Task 2: `scripts/release-check` skeleton + `version` subcommand (TDD)

**Files:**
- Create: `tests/test_release_check.sh`
- Create: `scripts/release-check`

- [ ] **Step 1: Write the failing tests for the `version` subcommand**

Create `tests/test_release_check.sh` with this content:

```bash
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

finish_tests
```

- [ ] **Step 2: Run it and confirm it fails because the script does not exist**

Run: `bash tests/test_release_check.sh`

Expected: a failure for `release-check version: matching versions exit zero` (script not found / non-zero status). Exit non-zero.

- [ ] **Step 3: Create `scripts/release-check` with `version` support**

Create `scripts/release-check` with this content:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rc::version() {
  local target_file="${1:-$ROOT_DIR/ci-toolkit}"
  local changelog_file="${2:-$ROOT_DIR/CHANGELOG.md}"

  local constant
  constant="$(grep -E '^CI_TOOLKIT_VERSION=' "$target_file" \
    | head -1 \
    | sed -E 's/^CI_TOOLKIT_VERSION="([^"]*)".*/\1/')"

  local latest
  latest="$(grep -E '^## v' "$changelog_file" \
    | head -1 \
    | sed -E 's/^## v([^ ]+).*/\1/')"

  if [[ -z "$constant" || -z "$latest" ]]; then
    printf 'version: could not parse versions (constant=%s, changelog=%s)\n' \
      "$constant" "$latest" >&2
    return 1
  fi

  if [[ "$constant" != "$latest" ]]; then
    printf 'version: CI_TOOLKIT_VERSION=%s does not match CHANGELOG v%s\n' \
      "$constant" "$latest" >&2
    return 1
  fi

  printf 'version: ok (%s)\n' "$constant"
}

main() {
  local subcommand="${1:-all}"
  if [[ "$#" -gt 0 ]]; then
    shift
  fi

  case "$subcommand" in
    version)
      rc::version "$@"
      ;;
    *)
      printf 'usage: release-check [version]\n' >&2
      return 64
      ;;
  esac
}

main "$@"
```

Then make it executable:

```bash
chmod +x scripts/release-check
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `bash tests/test_release_check.sh`

Expected: all `ok -` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/release-check tests/test_release_check.sh
git commit -m "feat: [release-check] Add version contract subcommand"
```

---

## Task 3: Add `boundary` subcommand (TDD)

**Files:**
- Modify: `tests/test_release_check.sh`
- Modify: `scripts/release-check`

- [ ] **Step 1: Write failing tests for `boundary`**

Append the following block to `tests/test_release_check.sh` *immediately before* the final `finish_tests` line:

```bash
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
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bash tests/test_release_check.sh`

Expected: the new `boundary` tests fail with status `64` (`usage: release-check [version]`) because the subcommand does not exist yet. Exit non-zero.

- [ ] **Step 3: Add the `boundary` function and wire dispatch**

Edit `scripts/release-check`. Add this function *after* `rc::version` and *before* `main`:

```bash
rc::boundary() {
  local target_file="${1:-$ROOT_DIR/ci-toolkit}"

  local vendor_hits
  vendor_hits="$(grep -nE 'GITHUB_|GITLAB_|CIRCLE_|BUILDKITE_|BITBUCKET_' \
    "$target_file" || true)"
  if [[ -n "$vendor_hits" ]]; then
    printf '%s\n' "$vendor_hits" >&2
    printf 'boundary: CI-vendor markers found in %s\n' "$target_file" >&2
    return 1
  fi

  local forbidden
  forbidden="$(grep -nE '^[[:space:]]*(build|deploy|release|test|lint)\)' \
    "$target_file" || true)"
  if [[ -n "$forbidden" ]]; then
    printf '%s\n' "$forbidden" >&2
    printf 'boundary: forbidden public command names found in dispatch of %s\n' \
      "$target_file" >&2
    return 1
  fi

  printf 'boundary: ok\n'
}
```

Then update the `case` arms inside `main` from:

```bash
  case "$subcommand" in
    version)
      rc::version "$@"
      ;;
    *)
      printf 'usage: release-check [version]\n' >&2
      return 64
      ;;
  esac
```

to:

```bash
  case "$subcommand" in
    version)
      rc::version "$@"
      ;;
    boundary)
      rc::boundary "$@"
      ;;
    *)
      printf 'usage: release-check [version|boundary]\n' >&2
      return 64
      ;;
  esac
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `bash tests/test_release_check.sh`

Expected: all `ok -` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/release-check tests/test_release_check.sh
git commit -m "feat: [release-check] Add boundary check for vendor markers and task commands"
```

---

## Task 4: Add `copy-smoke` subcommand (TDD)

**Files:**
- Modify: `tests/test_release_check.sh`
- Modify: `scripts/release-check`

- [ ] **Step 1: Write a failing test for `copy-smoke`**

Append this block to `tests/test_release_check.sh` immediately before `finish_tests`:

```bash
# copy-smoke subcommand: real artifact copied into a temp dir must work standalone.
run_capture "$RELEASE_CHECK" copy-smoke
assert_status 0 "$RUN_STATUS" "release-check copy-smoke: standalone artifact exits zero"
assert_contains "$RUN_STDOUT" "copy-smoke: ok" "release-check copy-smoke: prints ok line"
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bash tests/test_release_check.sh`

Expected: failure with status `64` (usage error) because `copy-smoke` is not yet a known subcommand. Exit non-zero.

- [ ] **Step 3: Add the `copy_smoke` function and wire dispatch**

In `scripts/release-check`, add this function after `rc::boundary` and before `main`:

```bash
rc::copy_smoke() {
  local target_file="${1:-$ROOT_DIR/ci-toolkit}"
  local tmpdir
  tmpdir="$(mktemp -d)"

  cp "$target_file" "$tmpdir/ci-toolkit"
  chmod +x "$tmpdir/ci-toolkit"

  local rc=0
  (
    cd "$tmpdir"
    ./ci-toolkit help >/dev/null
    ./ci-toolkit version | grep -q 'ci-toolkit'
    bash -c "source './ci-toolkit' && ci::info 'ok'" >/dev/null
  ) || rc=$?

  rm -rf "$tmpdir"

  if [[ "$rc" -ne 0 ]]; then
    printf 'copy-smoke: standalone artifact failed (rc=%s)\n' "$rc" >&2
    return 1
  fi

  printf 'copy-smoke: ok\n'
}
```

Update the `main` dispatch to:

```bash
  case "$subcommand" in
    version)
      rc::version "$@"
      ;;
    boundary)
      rc::boundary "$@"
      ;;
    copy-smoke)
      rc::copy_smoke "$@"
      ;;
    *)
      printf 'usage: release-check [version|boundary|copy-smoke]\n' >&2
      return 64
      ;;
  esac
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `bash tests/test_release_check.sh`

Expected: all `ok -` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/release-check tests/test_release_check.sh
git commit -m "feat: [release-check] Add standalone copy-smoke subcommand"
```

---

## Task 5: Add `gates` and `all` subcommands (TDD)

**Files:**
- Modify: `tests/test_release_check.sh`
- Modify: `scripts/release-check`

- [ ] **Step 1: Write a failing end-to-end test**

Append this block to `tests/test_release_check.sh` immediately before `finish_tests`:

```bash
# all subcommand: end-to-end pipeline must exit zero on a clean repo.
run_capture "$RELEASE_CHECK" all
assert_status 0 "$RUN_STATUS" "release-check all: clean repo exits zero"
assert_contains "$RUN_STDOUT" "version: ok" "release-check all: ran version check"
assert_contains "$RUN_STDOUT" "boundary: ok" "release-check all: ran boundary check"
assert_contains "$RUN_STDOUT" "copy-smoke: ok" "release-check all: ran copy-smoke"
assert_contains "$RUN_STDOUT" "release-check: all checks passed" \
  "release-check all: prints final summary"
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bash tests/test_release_check.sh`

Expected: failure because the default `all` subcommand currently falls through to the usage-error branch. Exit non-zero.

- [ ] **Step 3: Add `gates` and `all` to the dispatch**

In `scripts/release-check`, add this function after `rc::copy_smoke` and before `main`:

```bash
rc::gates() {
  "$ROOT_DIR/scripts/test"

  local lint_status
  "$ROOT_DIR/scripts/lint"
  if command -v shellcheck >/dev/null 2>&1; then
    lint_status="ran"
  else
    lint_status="skipped (shellcheck not installed)"
  fi

  "$ROOT_DIR/scripts/smoke"

  printf 'gates: tests ok; lint %s; smoke ok\n' "$lint_status"
}
```

Update the `main` dispatch — replace the entire `case` block with:

```bash
  case "$subcommand" in
    version)
      rc::version "$@"
      ;;
    boundary)
      rc::boundary "$@"
      ;;
    copy-smoke)
      rc::copy_smoke "$@"
      ;;
    gates)
      rc::gates "$@"
      ;;
    all)
      rc::version
      rc::gates
      rc::boundary
      rc::copy_smoke
      printf 'release-check: all checks passed\n'
      ;;
    *)
      printf 'usage: release-check [version|boundary|copy-smoke|gates|all]\n' >&2
      return 64
      ;;
  esac
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `bash tests/test_release_check.sh`

Expected: all `ok -` lines, exit 0.

- [ ] **Step 5: Run the full repo test suite to confirm nothing else regressed**

Run: `./scripts/test`

Expected: all test files print only `ok -` lines, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/release-check tests/test_release_check.sh
git commit -m "feat: [release-check] Add gates and all subcommands"
```

---

## Task 6: Generate the release-readiness note

**Files:**
- Create: `docs/superpowers/release-readiness/2026-05-12-v0.1.0.md`

- [ ] **Step 1: Create the release-readiness folder**

Run:

```bash
mkdir -p docs/superpowers/release-readiness
```

- [ ] **Step 2: Run the full release-check pipeline and capture evidence**

Run:

```bash
./scripts/release-check all 2>&1 | tee /tmp/ci-toolkit-release-evidence.log
```

Expected: exit 0, with lines containing `version: ok`, `gates: tests ok`, `boundary: ok`, `copy-smoke: ok`, and the final `release-check: all checks passed`.

- [ ] **Step 3: Determine ShellCheck status**

Run:

```bash
if command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck: ran ($(shellcheck --version | head -2 | tail -1))"
else
  echo "shellcheck: skipped (not installed)"
fi
```

Record the printed line — it determines whether the note treats `scripts/lint` as a real pass or as a known gap.

- [ ] **Step 4: Write the release-readiness note**

Create `docs/superpowers/release-readiness/2026-05-12-v0.1.0.md` with this content. Substitute the bracketed values with the actual values from Steps 2 and 3 — these brackets are intentional and exist because the values come from running the script, not from authoring decisions:

```markdown
# ci-toolkit v0.1.0 release-readiness record

Date: 2026-05-12
Release candidate: v0.1.0
Spec: docs/superpowers/specs/2026-05-12-ci-toolkit-release-readiness-design.md
Plan: docs/superpowers/plans/2026-05-12-ci-toolkit-release-readiness.md

## Summary

The release-readiness pass for ci-toolkit v0.1.0 was executed on 2026-05-12 with
the following decisions and results.

## Decisions

- `CI_TOOLKIT_VERSION` normalized to `0.1.0` to match the latest CHANGELOG entry
  `v0.1.0`. The experimental status remains in the README and CHANGELOG prose
  and in `ci::usage` help text.

## Commands run

```bash
./scripts/release-check all
./scripts/lint   # also exercised indirectly via release-check gates
```

## Results

| Gate                                                | Status                                                                              |
| --------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Version contract (`release-check version`)          | pass                                                                                |
| `./scripts/test`                                    | pass                                                                                |
| `./scripts/lint`                                    | <pass — ShellCheck ran / skipped — see ShellCheck row below>                        |
| `./scripts/smoke`                                   | pass                                                                                |
| Boundary (`release-check boundary`)                 | pass                                                                                |
| Standalone copy-smoke (`release-check copy-smoke`)  | pass                                                                                |
| ShellCheck actually ran                             | <yes — version X.Y.Z / no — re-run `./scripts/lint` on a host with ShellCheck>      |

## Evidence excerpt

Truncated output from `./scripts/release-check all` on 2026-05-12:

```
<paste version/gates/boundary/copy-smoke summary lines from /tmp/ci-toolkit-release-evidence.log>
```

## Known gaps

- No `v0.1.0` GitHub Release has been published from this work. Tagging and
  publishing is out of scope for this stabilization pass and is left to a
  future spec.
- ShellCheck status above defines whether `scripts/lint` is fully verified.
  If ShellCheck was skipped locally, re-run `./scripts/lint` on a machine with
  ShellCheck installed before tagging.

## Acceptance criteria coverage

- Version metadata and changelog relationship: resolved (`0.1.0` on both).
- Behavior tests pass: yes.
- Smoke checks pass: yes.
- Standalone copy-smoke passes: yes.
- Boundary check passes: yes.
- ShellCheck status: recorded above.
- No new public toolkit features added: confirmed (only `scripts/release-check`,
  which is a verification script, was added).
- No external release action performed: confirmed.
```

- [ ] **Step 5: Sanity-check the note**

Run:

```bash
grep -n '<' docs/superpowers/release-readiness/2026-05-12-v0.1.0.md
```

Expected: no remaining `<…>` placeholder markers. If any remain (especially `<paste …>`, `<pass — ShellCheck ran / skipped …>`, or `<yes — version X.Y.Z …>`), finish substituting them with the captured values before committing.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/release-readiness/2026-05-12-v0.1.0.md
git commit -m "docs: [release] Record v0.1.0 release-readiness evidence"
```

---

## Task 7: Cross-reference `scripts/release-check` in the README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Identify the insertion point**

Run:

```bash
grep -n '^## ' README.md
```

Pick the section heading that documents quality gates (it currently mentions `scripts/test`, `scripts/lint`, `scripts/smoke`). The new section should appear *after* that section so contributors discover it once they already know about the existing gates.

- [ ] **Step 2: Add a "Release readiness" section**

Insert this block immediately after the existing quality-gates section:

````markdown
## Release readiness

`scripts/release-check` runs the verification pass used before tagging a
release. It exposes individual checks plus an aggregate pipeline:

```bash
./scripts/release-check version      # CI_TOOLKIT_VERSION vs CHANGELOG.md
./scripts/release-check boundary     # platform-neutral guardrails
./scripts/release-check copy-smoke   # standalone single-file distribution
./scripts/release-check gates        # tests, lint, smoke
./scripts/release-check all          # everything above
```

The most recent release-readiness record lives under
`docs/superpowers/release-readiness/`.
````

- [ ] **Step 3: Verify markdown structure**

Run:

```bash
grep -n '^## ' README.md
```

Expected: the new `## Release readiness` heading appears in the section list and other headings are unchanged.

- [ ] **Step 4: Run all gates one final time to confirm a green tree**

Run:

```bash
./scripts/release-check all
```

Expected: exit 0 with the same `release-check: all checks passed` summary.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: [readme] Document scripts/release-check"
```

---

## Self-Review Notes

- **Spec coverage.** Every numbered item in the spec's Release-readiness definition is implemented:
  1. Version metadata aligned with changelog — Task 1.
  2. `./scripts/test` passes — exercised in Task 1 Step 5, Task 5 Step 5, Task 6 Step 2 (via `gates`).
  3. `./scripts/lint` result with ShellCheck status — Task 5 (gates captures status), Task 6 (note records it).
  4. `./scripts/smoke` passes — exercised in Task 1 Step 5 and Task 5/6 via `gates`.
  5. Standalone copy-smoke passes — Task 4.
  6. Boundary check — Task 3 (vendor markers and forbidden public command names).
  7. Release-readiness documentation — Task 6, with README cross-reference in Task 7.

- **Placeholder scan.** The only intentional placeholders in this plan live inside the *note template* in Task 6, marked with `<…>` so they're obvious. Step 5 of Task 6 explicitly greps for `<` to verify no placeholder leaks past the engineer's substitution pass. Every other step contains complete, copy-pasteable content.

- **Type consistency.** Subcommand names match across all tasks: `version`, `boundary`, `copy-smoke`, `gates`, `all`. Function names match across all tasks: `rc::version`, `rc::boundary`, `rc::copy_smoke`, `rc::gates`. The dispatch `case` block is rewritten in full each time it changes, so later tasks don't drift from earlier ones.
