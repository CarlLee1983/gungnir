# `ci::retry --delay SECONDS` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--delay SECONDS` flag to `ci::retry` (source mode) and `ci-toolkit retry` (CLI mode), preserving every existing call site's behavior, and retrofit the laravel-bluegreen example to use it.

**Architecture:** Single-file Bash artifact (`ci-toolkit`). The library function `ci::retry` gains a flag-parse loop *after* the `ATTEMPTS` consumption: `--delay N` and `--` are consumed; an unknown `--*` returns `64`; the first non-`--*` token starts the command. A `sleep "$delay"` runs **between** failed attempts only (never before the first, never after the last, never on `delay == 0`). The CLI wrapper `ci::cmd_retry` forwards `--delay` through to `ci::retry`. Version is bumped `0.1.4 → 0.1.5` with a coordinated update of `CHANGELOG.md`, README install URL, the user-doc install URLs, and the literal in `tests/test_source_and_cli.sh`.

**Tech Stack:** Bash 4+ (Homebrew bash on macOS, system bash on Linux). Tests are plain `bash` scripts using `tests/assert.sh`. ShellCheck (via `./scripts/lint`) and `./scripts/release-check all` gate the release.

**Spec:** [`docs/superpowers/specs/2026-05-14-ci-retry-delay-design.md`](../specs/2026-05-14-ci-retry-delay-design.md)

---

## File map

**Modify:**
- `ci-toolkit` (lines ~7, ~86–115, ~256–277, ~350–375) — version bump, `ci::retry` body, `ci::usage`, `ci::cmd_retry`.
- `CHANGELOG.md` — prepend a new `## v0.1.5` entry.
- `README.md` — install URL (`v0.1.4` → `v0.1.5`), CLI-reference `retry` row, source-API `ci::retry` row, add a `--delay` example near the existing retry copy.
- `docs/user/en/index.md` — install URL bump, add `--delay` example to the Robust Retries section.
- `docs/user/en/index.html` — install URL bump (kept in sync with `.md`; surface-check enforces parity).
- `docs/user/zh-TW/index.md` — install URL bump, add `--delay` example.
- `docs/user/zh-TW/index.html` — install URL bump.
- `tests/test_source_and_cli.sh:32` — literal `ci-toolkit 0.1.4` → `ci-toolkit 0.1.5`.
- `examples/laravel-bluegreen-deploy/deploy-prod.sh:214–228` — replace body of `run_composer_install` with `ci::retry 2 --delay 30 -- ...`; remove the `# proposed:` annotation lines.
- `examples/laravel-bluegreen-deploy/README.md` — line 38 substitution row (mark §5.1 landed), line 69 "proposed APIs" entry.

**Create:**
- `tests/test_retry_delay.sh` — new test file. 12 new + 3 regression assertions per spec §10.

**Untouched (regression coverage):**
- `tests/test_retry_and_paths.sh` — existing tests must continue to pass.

---

## Task 1: New test file scaffold + parse-error tests (RED → GREEN → COMMIT)

This task wires the new test file into `./scripts/test` (it discovers `tests/test_*.sh` automatically — no script change needed) and locks in the four `64`-error cases. The minimum implementation to make these pass is a parse loop that recognizes `--delay`, validates the value, and rejects unknown `--*` flags — but **does not sleep yet**. Sleep behavior is added in Task 2.

**Files:**
- Create: `tests/test_retry_delay.sh`
- Modify: `ci-toolkit` (`ci::retry`, lines 86–115)

### Step 1.1: Create the test file with parse-error assertions

- [ ] **Write `tests/test_retry_delay.sh`:**

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

# -- Parse errors (spec §10 #5–#8, #12) -----------------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay -1 -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay -1"
assert_contains "$RUN_STDERR" "--delay" "source retry --delay -1 mentions --delay"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay abc -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay abc"
assert_contains "$RUN_STDERR" "--delay" "source retry --delay abc mentions --delay"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay"
assert_status 64 "$RUN_STATUS" "source retry rejects --delay with no value"
assert_contains "$RUN_STDERR" "--delay requires a value" "source retry --delay missing-value message"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --bogus -- true"
assert_status 64 "$RUN_STATUS" "source retry rejects unknown --bogus"
assert_contains "$RUN_STDERR" "unknown option: --bogus" "source retry --bogus message"

run_capture "$ROOT_DIR/ci-toolkit" retry 2 --delay foo -- true
assert_status 64 "$RUN_STATUS" "CLI retry rejects --delay foo"

# -- Regression: no flags, no `--` (spec §10 #13) -------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 false"
assert_status 1 "$RUN_STATUS" "source retry without flags or -- returns command status"
assert_contains "$RUN_STDERR" "Attempt 1/3 failed" "source retry without flags still warns on attempt 1"

# -- Regression: explicit `--`, no flags (spec §10 #9) --------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 -- false"
assert_status 1 "$RUN_STATUS" "source retry with bare -- returns command status"
assert_contains "$RUN_STDERR" "Attempt 3/3 failed" "source retry with bare -- attempts all three"

finish_tests
```

- [ ] **Make it executable:**

```bash
chmod +x tests/test_retry_delay.sh
```

### Step 1.2: Run the new tests to confirm they FAIL

- [ ] Run: `bash tests/test_retry_delay.sh`
- [ ] Expected: tests fail. Specifically, `ci::retry 3 --delay -1 -- true` will currently invoke `--delay` as a command (`--delay: command not found`, status `127`), not return `64`. The unknown-flag and missing-value cases will similarly fail.

### Step 1.3: Implement flag parsing in `ci::retry` (no sleep yet)

- [ ] Replace lines 86–115 of `ci-toolkit` (the current `ci::retry` body) with:

```bash
# Retry a command N times, with an optional delay between attempts.
ci::retry() {
  local attempts="${1:-}"
  shift || true

  if [[ -z "$attempts" || ! "$attempts" =~ ^[0-9]+$ || "$attempts" -lt 1 ]]; then
    ci::error "Usage: ci::retry ATTEMPTS [--delay SECONDS] [--] COMMAND..."
    return 64
  fi

  local delay=0
  while (( $# > 0 )); do
    case "$1" in
      --delay)
        if [[ $# -lt 2 ]]; then
          ci::error "ci::retry: --delay requires a value"
          return 64
        fi
        if [[ ! "$2" =~ ^[0-9]+$ ]]; then
          ci::error "ci::retry: --delay value must be a non-negative integer, got: $2"
          return 64
        fi
        delay="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      --*)
        ci::error "ci::retry: unknown option: $1"
        return 64
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ "$#" -eq 0 ]]; then
    ci::error "Usage: ci::retry ATTEMPTS [--delay SECONDS] [--] COMMAND..."
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
```

Note: `delay` is parsed and validated but **not yet used**. The `for` loop is byte-identical to today's. Sleep is added in Task 2. ShellCheck note: if `./scripts/lint` flags `delay` as unused (SC2034), add a `: "$delay"` no-op line just above the `for` loop and remove it again in Task 2.

### Step 1.4: Run all tests to confirm GREEN

- [ ] Run: `bash tests/test_retry_delay.sh`
- [ ] Expected: PASS — all 9 assertions in this task pass.
- [ ] Run: `bash tests/test_retry_and_paths.sh`
- [ ] Expected: PASS — every existing assertion still passes. This proves the parse loop is back-compatible.
- [ ] Run: `./scripts/test`
- [ ] Expected: every `tests/test_*.sh` exits `0`, final line `All tests passed`.

### Step 1.5: ShellCheck

- [ ] Run: `./scripts/lint`
- [ ] Expected: ShellCheck clean, or skipped with notice. If a `delay` unused warning appears, follow the no-op workaround in Step 1.3.

### Step 1.6: Commit

- [ ] Stage and commit:

```bash
git add ci-toolkit tests/test_retry_delay.sh
git commit -m "feat: [ci-toolkit] Parse --delay flag in ci::retry (validation only)"
```

---

## Task 2: Sleep between attempts + wall-clock tests (RED → GREEN → COMMIT)

Adds the actual `sleep "$delay"` between failed attempts and the wall-clock assertions that lock it in.

**Files:**
- Modify: `tests/test_retry_delay.sh` (append)
- Modify: `ci-toolkit` (`ci::retry` body)

### Step 2.1: Append wall-clock tests to `tests/test_retry_delay.sh`

- [ ] Add the following block **before** `finish_tests` in `tests/test_retry_delay.sh`:

```bash
# -- Wall-clock behavior (spec §10 #1–#4) ---------------------------------

# #1: --delay 0 behaves like no delay (no sleep, command still fails twice)
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 2 --delay 0 false"
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "source retry --delay 0 returns command status"
[[ "$elapsed" -lt 1 ]] && pass "source retry --delay 0 does not sleep (elapsed=${elapsed}s)" \
  || fail "source retry --delay 0 should not sleep, elapsed=${elapsed}s"

# #2: --delay 1, succeeds on 2nd attempt → wall-clock ≥ 1s
counter_dir="$(make_temp_dir)"
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 2 --delay 1 -- bash -c 'f=\"$counter_dir/c\"; n=0; [[ -f \$f ]] && n=\$(cat \$f); n=\$((n+1)); printf %s \$n >\$f; [[ \$n -ge 2 ]]'"
elapsed=$(( SECONDS - start ))
assert_status 0 "$RUN_STATUS" "source retry --delay 1 succeeds on 2nd attempt"
[[ "$elapsed" -ge 1 ]] && pass "source retry --delay 1 sleeps before retry (elapsed=${elapsed}s)" \
  || fail "source retry --delay 1 should sleep ≥1s, elapsed=${elapsed}s"

# #3: --delay 1, 3 attempts all fail → 2 sleeps → wall-clock ≥ 2s
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 3 --delay 1 false"
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "source retry 3 --delay 1 returns final status"
[[ "$elapsed" -ge 2 ]] && pass "source retry 3 --delay 1 sleeps twice (elapsed=${elapsed}s)" \
  || fail "source retry 3 --delay 1 should sleep ≥2s, elapsed=${elapsed}s"

# #4: --delay 5 with ATTEMPTS=1 → no "between", no sleep
start=$SECONDS
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::retry 1 --delay 5 false"
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "source retry 1 --delay 5 returns command status"
[[ "$elapsed" -lt 1 ]] && pass "source retry 1 --delay 5 never sleeps (elapsed=${elapsed}s)" \
  || fail "source retry 1 --delay 5 should not sleep, elapsed=${elapsed}s"
```

### Step 2.2: Run the new tests to confirm they FAIL

- [ ] Run: `bash tests/test_retry_delay.sh`
- [ ] Expected: tests #2 and #3 fail (wall-clock = 0s because no sleep is wired up). Tests #1 and #4 still pass (no sleep is the correct behavior there).

### Step 2.3: Add the sleep between attempts

- [ ] In `ci-toolkit`, inside `ci::retry`, replace the `for ((...))` loop with:

```bash
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

    if (( attempt < attempts && delay > 0 )); then
      sleep "$delay"
    fi
  done

  return "$status"
```

Invariants this preserves (spec §6):
- Sleep is **only between attempts** — never before attempt 1, never after the last.
- `delay == 0` short-circuits the `sleep` call — identical syscalls to today.
- `ATTEMPTS=1` never enters the `delay > 0` branch.

### Step 2.4: Verify GREEN

- [ ] Run: `bash tests/test_retry_delay.sh`
- [ ] Expected: all assertions pass. Wall-clock #1 and #4 should be ~0s; #2 should be ~1s; #3 should be ~2s.
- [ ] Run: `./scripts/test`
- [ ] Expected: every test file passes.
- [ ] Run: `./scripts/lint`
- [ ] Expected: ShellCheck clean.

### Step 2.5: Commit

```bash
git add ci-toolkit tests/test_retry_delay.sh
git commit -m "feat: [ci-toolkit] Sleep between attempts when ci::retry --delay > 0"
```

---

## Task 3: CLI mode `ci-toolkit retry --delay` (RED → GREEN → COMMIT)

**Files:**
- Modify: `tests/test_retry_delay.sh` (append)
- Modify: `ci-toolkit` (`ci::cmd_retry`, lines ~350–375)

### Step 3.1: Append CLI tests

- [ ] Add the following block **before** `finish_tests` in `tests/test_retry_delay.sh`:

```bash
# -- CLI mode (spec §10 #10, #11, #14, #15) -------------------------------

# #10: CLI retry 2 --delay 1 -- succeeds on 2nd → ≥1s
counter_dir="$(make_temp_dir)"
start=$SECONDS
run_capture "$ROOT_DIR/ci-toolkit" retry 2 --delay 1 -- bash -c "f='$counter_dir/c'; n=0; [[ -f \$f ]] && n=\$(cat \$f); n=\$((n+1)); printf %s \$n >\$f; [[ \$n -ge 2 ]]"
elapsed=$(( SECONDS - start ))
assert_status 0 "$RUN_STATUS" "CLI retry --delay 1 succeeds on 2nd attempt"
[[ "$elapsed" -ge 1 ]] && pass "CLI retry --delay 1 sleeps before retry (elapsed=${elapsed}s)" \
  || fail "CLI retry --delay 1 should sleep ≥1s, elapsed=${elapsed}s"

# #11: CLI retry --delay 1 -- false (default ATTEMPTS=3) → ≥2s
start=$SECONDS
run_capture "$ROOT_DIR/ci-toolkit" retry --delay 1 -- false
elapsed=$(( SECONDS - start ))
assert_status 1 "$RUN_STATUS" "CLI retry --delay 1 (default attempts) returns command status"
[[ "$elapsed" -ge 2 ]] && pass "CLI retry --delay 1 default attempts sleeps twice (elapsed=${elapsed}s)" \
  || fail "CLI retry --delay 1 default attempts should sleep ≥2s, elapsed=${elapsed}s"

# #14: CLI retry 2 -- cmd (regression, no flag) — unchanged behavior
run_capture "$ROOT_DIR/ci-toolkit" retry 2 -- false
assert_status 1 "$RUN_STATUS" "CLI retry 2 -- false (regression) returns command status"
assert_contains "$RUN_STDERR" "Attempt 2/2 failed" "CLI retry 2 -- false (regression) attempts twice"

# #15: CLI retry -- cmd (regression, no ATTEMPTS) — default 3
run_capture "$ROOT_DIR/ci-toolkit" retry -- false
assert_status 1 "$RUN_STATUS" "CLI retry -- false (regression) returns command status"
assert_contains "$RUN_STDERR" "Attempt 3/3 failed" "CLI retry -- false (regression) defaults to 3 attempts"
```

### Step 3.2: Run to confirm FAIL

- [ ] Run: `bash tests/test_retry_delay.sh`
- [ ] Expected: #10 and #11 fail. The current `ci::cmd_retry` rejects `--delay` because it insists the token after `ATTEMPTS` is `--`. Tests #14 and #15 already pass (regressions of current behavior).

### Step 3.3: Rewrite `ci::cmd_retry`

- [ ] Replace `ci::cmd_retry` (lines ~350–375) with:

```bash
ci::cmd_retry() {
  local attempts=3
  local -a forwarded=()

  if [[ "${1:-}" != "--" && "${1:-}" != "--delay" ]]; then
    attempts="${1:-}"
    shift || true
  fi

  if [[ -z "$attempts" || ! "$attempts" =~ ^[0-9]+$ || "$attempts" -lt 1 ]]; then
    ci::usage >&2
    return 64
  fi

  while (( $# > 0 )); do
    case "$1" in
      --delay)
        if [[ $# -lt 2 ]]; then
          ci::usage >&2
          return 64
        fi
        forwarded+=(--delay "$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        ci::usage >&2
        return 64
        ;;
    esac
  done

  if [[ "$#" -eq 0 ]]; then
    ci::usage >&2
    return 64
  fi

  ci::retry "$attempts" "${forwarded[@]}" -- "$@"
}
```

Notes:
- CLI mode keeps the **required `--`** between flags and command (spec §8). Anything that isn't `--delay` or `--` after `ATTEMPTS` is a usage error.
- The first-arg check now allows `--delay` (as well as `--`) before consuming `ATTEMPTS`, so `ci-toolkit retry --delay 1 -- false` defaults to `ATTEMPTS=3`.
- `forwarded` is passed verbatim to `ci::retry`, which re-validates the `--delay` value. The explicit `--` lets the underlying command's argv start with `--` safely.
- `local -a forwarded=()` declares the array explicitly so `"${forwarded[@]}"` is safe under `set -u` even when empty.

### Step 3.4: Confirm GREEN

- [ ] Run: `bash tests/test_retry_delay.sh`
- [ ] Expected: every assertion in the file passes.
- [ ] Run: `bash tests/test_retry_and_paths.sh`
- [ ] Expected: every existing CLI-mode retry assertion still passes (including the "CLI retry requires separator before command" case at line 58 — `ci-toolkit retry 2 true` still fails with `64` because `true` is not `--` or `--delay`).
- [ ] Run: `./scripts/test`
- [ ] Expected: every test file passes.
- [ ] Run: `./scripts/lint`
- [ ] Expected: clean.

### Step 3.5: Commit

```bash
git add ci-toolkit tests/test_retry_delay.sh
git commit -m "feat: [ci-toolkit] Forward --delay through ci-toolkit retry CLI"
```

---

## Task 4: Update `ci::usage` for the new signature (GREEN → COMMIT)

**Files:**
- Modify: `ci-toolkit` (`ci::usage`, lines ~256–277)
- Modify: `tests/test_retry_and_paths.sh:55,59` — update the usage-substring assertion

### Step 4.1: Update the usage block

- [ ] In `ci-toolkit` `ci::usage` heredoc, change the retry line from:

```
  ci-toolkit retry [ATTEMPTS] -- COMMAND [ARGS...]
```

to:

```
  ci-toolkit retry [ATTEMPTS] [--delay SECONDS] -- COMMAND [ARGS...]
```

### Step 4.2: Fix the now-broken substring in the existing test

The current test asserts `assert_contains "$RUN_STDERR" "ci-toolkit retry [ATTEMPTS] -- COMMAND"` (substring match) on usage output. After Step 4.1, that substring is broken by the inserted `[--delay SECONDS]`. Update both occurrences.

- [ ] In `tests/test_retry_and_paths.sh`, change the needle in both `assert_contains` calls (lines 55 and 59) from:

```
"ci-toolkit retry [ATTEMPTS] -- COMMAND"
```

to:

```
"ci-toolkit retry [ATTEMPTS] [--delay SECONDS] -- COMMAND"
```

### Step 4.3: Verify

- [ ] Run: `./ci-toolkit help`
- [ ] Expected: the `retry` line now shows `[--delay SECONDS]`.
- [ ] Run: `./scripts/test`
- [ ] Expected: all tests pass.
- [ ] Run: `./scripts/lint`
- [ ] Expected: clean.

### Step 4.4: Commit

```bash
git add ci-toolkit tests/test_retry_and_paths.sh
git commit -m "docs: [ci-toolkit] Show --delay SECONDS in ci-toolkit help"
```

---

## Task 5: Version bump 0.1.4 → 0.1.5 (GREEN → COMMIT)

**Files:**
- Modify: `ci-toolkit:7` (`CI_TOOLKIT_VERSION`)
- Modify: `CHANGELOG.md`
- Modify: `tests/test_source_and_cli.sh:32`
- Modify: `README.md:24` (install URL)
- Modify: `docs/user/en/index.md:16`
- Modify: `docs/user/en/index.html:109`
- Modify: `docs/user/zh-TW/index.md:16`
- Modify: `docs/user/zh-TW/index.html:109`

### Step 5.1: Bump `CI_TOOLKIT_VERSION`

- [ ] In `ci-toolkit:7`, change:

```bash
CI_TOOLKIT_VERSION="0.1.4"
```

to:

```bash
CI_TOOLKIT_VERSION="0.1.5"
```

### Step 5.2: Prepend a CHANGELOG entry

- [ ] In `CHANGELOG.md`, insert a new entry immediately after the `# Changelog` heading and before `## v0.1.4`:

```markdown
## v0.1.5 - Added retry delay

- Added `--delay SECONDS` flag to `ci::retry` (source mode) and `ci-toolkit retry` (CLI mode). Sleeps between failed attempts only; never before the first attempt and never after the last.
- Preserves every existing call site's behavior. `--delay 0` and the omit-`--delay` path emit identical syscalls.
- Retrofitted `examples/laravel-bluegreen-deploy/run_composer_install` to use `ci::retry 2 --delay 30 -- composer install ...`.

```

### Step 5.3: Sync the version literal in the test

- [ ] In `tests/test_source_and_cli.sh:32`, change:

```bash
assert_eq "ci-toolkit 0.1.4" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.4"
```

to:

```bash
assert_eq "ci-toolkit 0.1.5" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.5"
```

### Step 5.4: Sync install URLs across README and user docs

- [ ] In `README.md:24`, change `releases/download/v0.1.4/ci-toolkit` → `releases/download/v0.1.5/ci-toolkit`.
- [ ] In `docs/user/en/index.md:16`, same substitution.
- [ ] In `docs/user/en/index.html:109`, same substitution.
- [ ] In `docs/user/zh-TW/index.md:16`, same substitution.
- [ ] In `docs/user/zh-TW/index.html:109`, same substitution.

(`./scripts/release-check artifact` greps the README install URL against `CI_TOOLKIT_VERSION`; the user-doc URLs are kept in sync as a project convention even though release-check does not enforce them.)

### Step 5.5: Verify

- [ ] Run: `./ci-toolkit version`
- [ ] Expected: `ci-toolkit 0.1.5`.
- [ ] Run: `./scripts/test`
- [ ] Expected: all tests pass (the new literal in `test_source_and_cli.sh:32` now matches).
- [ ] Run: `./scripts/release-check version`
- [ ] Expected: `version: ok (0.1.5)`.
- [ ] Run: `./scripts/release-check artifact`
- [ ] Expected: passes (README install URL matches version).
- [ ] Run: `./scripts/lint`
- [ ] Expected: clean.

### Step 5.6: Commit

```bash
git add ci-toolkit CHANGELOG.md tests/test_source_and_cli.sh README.md docs/user/en/index.md docs/user/en/index.html docs/user/zh-TW/index.md docs/user/zh-TW/index.html
git commit -m "chore: [release] Bump ci-toolkit version to 0.1.5"
```

---

## Task 6: README + user-docs `--delay` documentation (GREEN → COMMIT)

**Files:**
- Modify: `README.md` (CLI reference table, source-API reference table, narrative)
- Modify: `docs/user/en/index.md` (Robust Retries section)
- Modify: `docs/user/zh-TW/index.md` (穩健的重試機制 section)

### Step 6.1: Update `README.md` CLI reference table

- [ ] In `README.md` (lines around 110–112), replace the two retry rows:

```
| `retry -- COMMAND [ARGS...]` | Run `COMMAND` up to 3 times until it returns `0`. Returns the last attempt's exit status. |
| `retry ATTEMPTS -- COMMAND [ARGS...]` | Run `COMMAND` up to `ATTEMPTS` times. `ATTEMPTS` must be a positive integer. |
```

with:

```
| `retry [ATTEMPTS] [--delay SECONDS] -- COMMAND [ARGS...]` | Run `COMMAND` up to `ATTEMPTS` times (default `3`). `--delay` sleeps `SECONDS` between failed attempts; defaults to `0`. Returns the last attempt's exit status. |
```

### Step 6.2: Update the source-API row for `ci::retry`

- [ ] In `README.md` (line around 146), replace:

```
| `ci::retry ATTEMPTS COMMAND...` | Run `COMMAND` up to `ATTEMPTS` times. Returns `0` on first success, otherwise returns the final attempt's exit status. Failed attempts log a `warn` line. |
```

with:

```
| `ci::retry ATTEMPTS [--delay SECONDS] [--] COMMAND...` | Run `COMMAND` up to `ATTEMPTS` times. `--delay` sleeps `SECONDS` between failed attempts (default `0`). Returns `0` on first success, otherwise returns the final attempt's exit status. Failed attempts log a `warn` line. |
```

### Step 6.3: Add a CLI `--delay` example

- [ ] In `README.md` CLI quickstart block (lines around 41–43), append after `./ci-toolkit retry 5 -- curl -fsS https://example.com/health`:

```bash
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

### Step 6.4: Add a source-mode `--delay` example

- [ ] In `README.md` source-mode quickstart block (lines around 47–54), append after `ci::retry 3 make test`:

```bash
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

### Step 6.5: Update `docs/user/en/index.md` Robust Retries section

- [ ] In `docs/user/en/index.md`, replace lines 63–79 (the `<!-- doc-key: writes-mutations -->` section through the closing fence of the `ci::retry 3 curl ...` example) with:

````markdown
<!-- doc-key: writes-mutations -->
## Writes / mutations

### Robust Retries
Gungnir's `ci::retry` is more powerful than a simple loop. It preserves the exit status of the final attempt and logs failures to stderr. Use `--delay SECONDS` to sleep between failed attempts — useful for upstreams that need a moment to recover (package registries, deploy targets).

**Example: Flaky Network Call**
```bash
# Raw Bash (verbose and easy to get wrong)
n=0; until [ "$n" -ge 3 ]; do
  curl -fsS https://api.example.com && break
  n=$((n+1)); sleep 1
done

# Gungnir
ci::retry 3 curl -fsS https://api.example.com

# With a 30s gap between attempts (good for registries / package managers)
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```
````

### Step 6.6: Update `docs/user/zh-TW/index.md`

- [ ] In `docs/user/zh-TW/index.md`, replace lines 63–79 with:

````markdown
<!-- doc-key: writes-mutations -->
## 寫入與變更

### 穩健的重試機制
Gungnir 的 `ci::retry` 比簡單的迴圈更強大。它會保留最後一次嘗試的退出狀態，並將失敗記錄到 stderr。可加上 `--delay SECONDS` 在失敗的嘗試之間 sleep — 適用於 package registry、deploy target 等需要喘息的上游服務。

**範例：不穩定的網路呼叫**
```bash
# 原始 Bash (冗長且容易寫錯)
n=0; until [ "$n" -ge 3 ]; do
  curl -fsS https://api.example.com && break
  n=$((n+1)); sleep 1
done

# Gungnir
ci::retry 3 curl -fsS https://api.example.com

# 兩次嘗試之間相隔 30 秒（適合 registry / package manager）
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```
````

### Step 6.7: Verify

- [ ] Run: `./scripts/test`
- [ ] Expected: all tests pass (doc changes don't affect tests).
- [ ] Run: `./scripts/lint`
- [ ] Expected: clean.
- [ ] If `scripts/check-user-docs.ts` exists, run: `bun run scripts/check-user-docs.ts`. If it fails because `index.html` no longer mirrors `index.md` (the new `--delay` snippet is missing from the HTML surface), add the same example to both `index.html` files in this commit and re-run.

### Step 6.8: Commit

```bash
git add README.md docs/user/en/index.md docs/user/zh-TW/index.md
git commit -m "docs: [docs] Document ci::retry --delay SECONDS"
```

If you also had to update `index.html` files in Step 6.7, include them:

```bash
git add docs/user/en/index.html docs/user/zh-TW/index.html
```

---

## Task 7: Retrofit `examples/laravel-bluegreen-deploy` (GREEN → COMMIT)

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh:214–228` (`run_composer_install`)
- Modify: `examples/laravel-bluegreen-deploy/README.md` (line ~38 substitution row, line ~69 proposed-APIs entry)

### Step 7.1: Replace `run_composer_install` body

- [ ] In `examples/laravel-bluegreen-deploy/deploy-prod.sh`, replace lines 214–228 (the function plus its `# proposed:` annotation):

```bash
# run_composer_install — composer install with one-shot retry-with-delay.
#
# proposed: ci::retry --delay SECONDS (see spec §5.1, plan TBD)
# After §5.1 lands, replace the body with:
#     ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
run_composer_install() {
    ci::require_tool composer || exit 1
    export COMPOSER_ALLOW_SUPERUSER=1

    if ! composer install --no-dev --optimize-autoloader; then
        ci::warn "first composer install attempt failed; sleeping 30s before retry"
        sleep 30
        composer install --no-dev --optimize-autoloader
    fi
}
```

with:

```bash
# run_composer_install — composer install with a 30s gap between attempts.
run_composer_install() {
    ci::require_tool composer || exit 1
    export COMPOSER_ALLOW_SUPERUSER=1

    ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
}
```

The `# proposed:` annotation is removed because the proposal has landed.

### Step 7.2: Update the substitution table row in the example README

- [ ] In `examples/laravel-bluegreen-deploy/README.md` (around line 38), replace:

```
| L132-136 composer install + `sleep 30` + retry | inline `if ! ...; then sleep 30; ...; fi`; annotated `# proposed: ci::retry --delay` |
```

with:

```
| L132-136 composer install + `sleep 30` + retry | `ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader` (landed in v0.1.5) |
```

### Step 7.3: Mark §5.1 as landed in the proposed-APIs section

- [ ] In `examples/laravel-bluegreen-deploy/README.md` (around line 69), replace:

```
1. **`ci::retry --delay SECONDS`** (spec §5.1) — adds a backoff to the existing `ci::retry`; covers packagist/npm-registry transient failures.
```

with:

```
1. **`ci::retry --delay SECONDS`** (spec §5.1) — **landed in v0.1.5.** Adds an inter-attempt sleep to `ci::retry`; covers packagist/npm-registry transient failures. `run_composer_install` was updated to use it.
```

### Step 7.4: Verify

- [ ] Run: `./scripts/lint`
- [ ] Expected: ShellCheck clean (the example was made ShellCheck-clean in commit `99b6ae5` — preserve that).
- [ ] Run: `./scripts/test`
- [ ] Expected: clean (the example is not wired into the test loop).

### Step 7.5: Commit

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh examples/laravel-bluegreen-deploy/README.md
git commit -m "refactor: [examples] Retrofit run_composer_install to ci::retry --delay"
```

---

## Task 8: Full release-readiness pass (NO COMMIT)

This task does not produce a commit — it confirms the branch is releasable end-to-end.

### Step 8.1: Run the full test suite

- [ ] Run: `./scripts/test`
- [ ] Expected: every `tests/test_*.sh` exits `0`. Final line: `All tests passed`.

### Step 8.2: Run lint

- [ ] Run: `./scripts/lint`
- [ ] Expected: ShellCheck clean (or skip notice).

### Step 8.3: Run smoke

- [ ] Run: `./scripts/smoke`
- [ ] Expected: smoke checks pass — CLI and source mode both work against the real artifact.

### Step 8.4: Run release-check

- [ ] Run: `./scripts/release-check all`
- [ ] Expected: every sub-check passes. Specifically:
  - `version: ok (0.1.5)` (CHANGELOG and constant match).
  - `artifact` passes (README install URL matches `0.1.5`).
  - `boundary` passes (no platform-specific env vars introduced).
  - `copy-smoke` passes (standalone distribution works).
  - `gates` passes (tests + lint + smoke).

### Step 8.5: Spot-check live behavior

- [ ] Run: `./ci-toolkit version`
- [ ] Expected: `ci-toolkit 0.1.5`.
- [ ] Run: `./ci-toolkit help`
- [ ] Expected: usage shows `retry [ATTEMPTS] [--delay SECONDS] -- COMMAND [ARGS...]`.
- [ ] Run: `./ci-toolkit retry 2 --delay 1 -- false`
- [ ] Expected: command runs ~1s, exits `1`, prints `Attempt 1/2 failed ...` then `Attempt 2/2 failed ...` on stderr.
- [ ] Run: `./ci-toolkit retry 2 --foo bar -- true`
- [ ] Expected: exits `64`, prints usage on stderr.

If every check passes, the branch is ready for PR.

---

## Out-of-scope (track separately, per spec §11)

These do **not** belong in this plan's PR:

1. Reading `CI_TOOLKIT_VERSION` dynamically in `test_source_and_cli.sh` — separate spec.
2. Migrating `bun-deploy` / `vendored-deploy-script` examples to `--delay`.
3. Adding `--delay` to the internal `ci::slack_webhook` retry call site (`ci-toolkit:213`).
