# String Predicate Helpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add four public string predicate helpers (`ci::eq`, `ci::ne`, `ci::in`, `ci::not_in`) to the `ci-toolkit` single-file artifact, with matching CLI commands (`eq`, `ne`, `in`, `not-in`), full TDD coverage, and the surrounding release shape (version bump, CHANGELOG, README + bilingual user docs, smoke check, examples install-URL refresh, release-check gates).

**Architecture:** Pure status-code predicates that compare literal Bash strings. No stdout on normal success/failure; usage errors return `64` via `ci::error` (source) or `ci::usage` (CLI). Library functions sit between `ci::is_true` and `ci::find_up`; CLI command wrappers follow the `ci::cmd_strip_prefix` template; dispatch maps the dashed `not-in` command to `ci::not_in`. The current artifact already ships as `v0.1.7` (commit `354c5a2`), so this release ships as **`v0.1.8`** — all `v0.1.7` install-URL pins and CHANGELOG sections move forward accordingly.

**Tech Stack:** Bash 4+, `set -euo pipefail` test harness in `tests/test_*.sh` using `tests/assert.sh` + per-file `run_capture`. ShellCheck for lint. No new dependencies.

---

## Spec reference

- Design spec: `docs/superpowers/specs/2026-05-15-ci-string-predicate-helpers-design.md`
- Note: the spec was drafted as `v0.1.7`. The repo already shipped `v0.1.7` with different content (slack JSON escaping, `sort -V` probe, `release-check examples`), so this plan targets `v0.1.8`.

## File structure

### Created

- `tests/test_string_predicates.sh` — new behavior test file. Single responsibility: exercise `ci::eq`, `ci::ne`, `ci::in`, `ci::not_in` and their `eq`, `ne`, `in`, `not-in` CLI counterparts. Models its `run_capture` and assertion style after `tests/test_strip_prefix.sh`.

### Modified

- `ci-toolkit` — add four library functions in the library section between `ci::is_true` (ends line 174) and `ci::find_up` (starts line 177). Add four `ci::cmd_*` wrappers in the command section near `ci::cmd_strip_prefix` (lines 548–554). Add four `case` arms (`eq`, `ne`, `in`, `not-in`) in `ci::dispatch` (lines 561–605). Add four `ci-toolkit ...` lines in `ci::usage`. Bump `CI_TOOLKIT_VERSION` from `0.1.7` to `0.1.8` (line 7).
- `CHANGELOG.md` — prepend a new `## v0.1.8 - String predicate helpers` entry above the existing `v0.1.7` section.
- `README.md` — add four rows to the CLI reference table (between `strip-prefix` and `trap-err`); add a new "String predicates" subsection (or rows into "Validation") in the Source API reference; refresh the install-URL pin from `v0.1.7` → `v0.1.8`.
- `docs/user/en/index.md`, `docs/user/zh-TW/index.md`, `docs/user/en/index.html`, `docs/user/zh-TW/index.html` — refresh install-URL pin (`v0.1.7` → `v0.1.8`) and document the four new helpers/commands so the bilingual user docs stay aligned with `release-check gates`.
- `examples/bun-deploy/README.md`, `examples/laravel-bluegreen-deploy/README.md`, `examples/vendored-deploy-script/README.md`, `examples/vendored-deploy-script/deploy-prod.sh` — refresh `v0.1.7` pins and `Vendor Gungnir ci-toolkit v0.1.7` commit-message strings to `v0.1.8` so `release-check examples` passes.
- `scripts/smoke` — add one low-cost predicate check (`ci-toolkit eq 0.1.8 0.1.8`).

### Untouched

- `tests/test_source_and_cli.sh` — the existing help/version assertions stay valid; the version assertion already targets `0.1.7` and will need its single-line bump as part of the version task, but no other change is needed.
- `tests/assert.sh` — no harness change required.
- `scripts/release-check`, `scripts/test`, `scripts/lint` — no logic change. They simply pick up the new tests, new CHANGELOG entry, and new install-URL pins.

---

## Task 1: `ci::eq` library function

**Files:**
- Create: `tests/test_string_predicates.sh`
- Modify: `ci-toolkit` (insert between line 174 closing brace of `ci::is_true` and line 175 blank line)

- [x] **Step 1: Create the failing test file with `ci::eq` cases**

Write `tests/test_string_predicates.sh`:

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

# -- Source mode: ci::eq (spec §4.1, §7.1 #1–#4) --------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq foo foo"
assert_status 0 "$RUN_STATUS" "source ci::eq foo foo exits 0"
assert_eq "" "$RUN_STDOUT" "source ci::eq foo foo writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::eq foo foo writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq foo bar"
assert_status 1 "$RUN_STATUS" "source ci::eq foo bar exits 1"
assert_eq "" "$RUN_STDOUT" "source ci::eq foo bar writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::eq foo bar writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq '' ''"
assert_status 0 "$RUN_STATUS" "source ci::eq '' '' exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq '' x"
assert_status 1 "$RUN_STATUS" "source ci::eq '' x exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::eq foo"
assert_status 64 "$RUN_STATUS" "source ci::eq missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::eq" \
  "source ci::eq missing arg prints usage"

finish_tests
```

Then make it executable:

```bash
chmod +x tests/test_string_predicates.sh
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_string_predicates.sh`

Expected: FAIL. The first `run_capture` will trip on `ci::eq: command not found` and the script will exit non-zero before reaching `finish_tests`.

- [x] **Step 3: Implement `ci::eq` in `ci-toolkit`**

Edit `ci-toolkit`. Find the closing brace of `ci::is_true` (line 174) and the blank line that precedes `ci::find_up` (line 175–176). Insert the following block immediately after the closing brace of `ci::is_true`, keeping one blank line before and after:

```bash
# @description Return 0 iff ACTUAL string-equals EXPECTED. Never prints values.
ci::eq() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::eq ACTUAL EXPECTED"
    return 64
  fi
  [[ "$1" == "$2" ]]
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_string_predicates.sh`

Expected: PASS. All `ok - ...` lines and `All tests passed`.

- [x] **Step 5: Commit**

```bash
git add tests/test_string_predicates.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::eq string predicate"
```

---

## Task 2: `ci::ne` library function

**Files:**
- Modify: `tests/test_string_predicates.sh` (append before `finish_tests`)
- Modify: `ci-toolkit` (insert directly after the `ci::eq` block from Task 1)

- [x] **Step 1: Append failing tests for `ci::ne`**

Edit `tests/test_string_predicates.sh`. Insert the following block immediately above the `finish_tests` line (keep `finish_tests` last):

```bash
# -- Source mode: ci::ne (spec §4.2, §7.1 #5–#8) --------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne foo bar"
assert_status 0 "$RUN_STATUS" "source ci::ne foo bar exits 0"
assert_eq "" "$RUN_STDOUT" "source ci::ne foo bar writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::ne foo bar writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne foo foo"
assert_status 1 "$RUN_STATUS" "source ci::ne foo foo exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne '' foo"
assert_status 0 "$RUN_STATUS" "source ci::ne '' foo exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne '' ''"
assert_status 1 "$RUN_STATUS" "source ci::ne '' '' exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::ne foo"
assert_status 64 "$RUN_STATUS" "source ci::ne missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::ne" \
  "source ci::ne missing arg prints usage"
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_string_predicates.sh`

Expected: FAIL. The first new `run_capture` block reports `ci::ne: command not found`.

- [x] **Step 3: Implement `ci::ne` in `ci-toolkit`**

Edit `ci-toolkit`. Insert the following block immediately after the closing brace of `ci::eq` (which Task 1 added). Keep one blank line before and after:

```bash
# @description Return 0 iff ACTUAL string-differs from EXPECTED. Never prints values.
ci::ne() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::ne ACTUAL EXPECTED"
    return 64
  fi
  [[ "$1" != "$2" ]]
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_string_predicates.sh`

Expected: PASS for all `ci::eq` and `ci::ne` cases, ending in `All tests passed`.

- [x] **Step 5: Commit**

```bash
git add tests/test_string_predicates.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::ne string predicate"
```

---

## Task 3: `ci::in` library function

**Files:**
- Modify: `tests/test_string_predicates.sh` (append before `finish_tests`)
- Modify: `ci-toolkit` (insert directly after the `ci::ne` block from Task 2)

- [x] **Step 1: Append failing tests for `ci::in`**

Edit `tests/test_string_predicates.sh`. Insert the following block immediately above `finish_tests`:

```bash
# -- Source mode: ci::in (spec §4.3, §7.1 #9–#12) -------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in staging dev staging prod"
assert_status 0 "$RUN_STATUS" "source ci::in match exits 0"
assert_eq "" "$RUN_STDOUT" "source ci::in match writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::in match writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in qa dev staging prod"
assert_status 1 "$RUN_STATUS" "source ci::in no-match exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in '' dev '' prod"
assert_status 0 "$RUN_STATUS" "source ci::in empty-value matches empty candidate"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::in staging"
assert_status 64 "$RUN_STATUS" "source ci::in missing candidates exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::in" \
  "source ci::in missing candidates prints usage"
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_string_predicates.sh`

Expected: FAIL. The first new `run_capture` reports `ci::in: command not found`.

- [x] **Step 3: Implement `ci::in` in `ci-toolkit`**

Edit `ci-toolkit`. Insert the following block immediately after the closing brace of `ci::ne` (added in Task 2). Keep one blank line before and after:

```bash
# @description Return 0 iff VALUE string-equals any of the CANDIDATE arguments.
ci::in() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::in VALUE CANDIDATE..."
    return 64
  fi
  local value="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ "$value" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_string_predicates.sh`

Expected: PASS for all `ci::eq`, `ci::ne`, and `ci::in` cases, ending in `All tests passed`.

- [x] **Step 5: Commit**

```bash
git add tests/test_string_predicates.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::in string predicate"
```

---

## Task 4: `ci::not_in` library function

**Files:**
- Modify: `tests/test_string_predicates.sh` (append before `finish_tests`)
- Modify: `ci-toolkit` (insert directly after the `ci::in` block from Task 3)

- [x] **Step 1: Append failing tests for `ci::not_in`**

Edit `tests/test_string_predicates.sh`. Insert the following block immediately above `finish_tests`:

```bash
# -- Source mode: ci::not_in (spec §4.4, §7.1 #13–#16) --------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::not_in qa dev staging prod"
assert_status 0 "$RUN_STATUS" "source ci::not_in no-match exits 0"
assert_eq "" "$RUN_STDOUT" "source ci::not_in no-match writes no stdout"
assert_eq "" "$RUN_STDERR" "source ci::not_in no-match writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::not_in staging dev staging prod"
assert_status 1 "$RUN_STATUS" "source ci::not_in match exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::not_in '' dev staging"
assert_status 0 "$RUN_STATUS" "source ci::not_in empty-value no-match exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::not_in staging"
assert_status 64 "$RUN_STATUS" "source ci::not_in missing candidates exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::not_in" \
  "source ci::not_in missing candidates prints usage"
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_string_predicates.sh`

Expected: FAIL. The first new `run_capture` reports `ci::not_in: command not found`.

- [x] **Step 3: Implement `ci::not_in` in `ci-toolkit`**

Edit `ci-toolkit`. Insert the following block immediately after the closing brace of `ci::in` (added in Task 3). Keep one blank line before and after:

```bash
# @description Return 0 iff VALUE matches none of the CANDIDATE arguments.
ci::not_in() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::not_in VALUE CANDIDATE..."
    return 64
  fi
  if ci::in "$@"; then
    return 1
  fi
  return 0
}
```

Note: the local `$# -lt 2` guard runs before delegating to `ci::in`, which preserves the usage-error status `64` rather than collapsing it into a boolean outcome (per spec §4.4).

- [x] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_string_predicates.sh`

Expected: PASS for all four source-mode predicates, ending in `All tests passed`.

- [x] **Step 5: Commit**

```bash
git add tests/test_string_predicates.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::not_in string predicate"
```

---

## Task 5: CLI commands, dispatch, and usage text

**Files:**
- Modify: `tests/test_string_predicates.sh` (append before `finish_tests`)
- Modify: `ci-toolkit` (add four `ci::cmd_*` wrappers near `ci::cmd_strip_prefix` at lines 548–554; add four `case` arms in `ci::dispatch` lines 561–605; add four `ci-toolkit ...` lines inside the `ci::usage` heredoc at lines 359–384)

- [x] **Step 1: Append failing CLI tests**

Edit `tests/test_string_predicates.sh`. Insert the following block immediately above `finish_tests`:

```bash
# -- CLI mode (spec §7.2) -------------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" eq foo foo
assert_status 0 "$RUN_STATUS" "CLI eq foo foo exits 0"
assert_eq "" "$RUN_STDOUT" "CLI eq foo foo writes no stdout"
assert_eq "" "$RUN_STDERR" "CLI eq foo foo writes no stderr"

run_capture "$ROOT_DIR/ci-toolkit" eq foo bar
assert_status 1 "$RUN_STATUS" "CLI eq foo bar exits 1"
assert_eq "" "$RUN_STDOUT" "CLI eq foo bar writes no stdout"
assert_eq "" "$RUN_STDERR" "CLI eq foo bar writes no stderr"

run_capture "$ROOT_DIR/ci-toolkit" eq foo
assert_status 64 "$RUN_STATUS" "CLI eq missing arg exits 64"

run_capture "$ROOT_DIR/ci-toolkit" ne foo bar
assert_status 0 "$RUN_STATUS" "CLI ne foo bar exits 0"

run_capture "$ROOT_DIR/ci-toolkit" in staging dev staging prod
assert_status 0 "$RUN_STATUS" "CLI in match exits 0"

run_capture "$ROOT_DIR/ci-toolkit" in qa dev staging prod
assert_status 1 "$RUN_STATUS" "CLI in no-match exits 1"

run_capture "$ROOT_DIR/ci-toolkit" not-in qa dev staging prod
assert_status 0 "$RUN_STATUS" "CLI not-in no-match exits 0"

run_capture "$ROOT_DIR/ci-toolkit" not-in staging dev staging prod
assert_status 1 "$RUN_STATUS" "CLI not-in match exits 1"
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_string_predicates.sh`

Expected: FAIL. The new CLI cases hit the dispatch `*)` arm and exit `64`, so the success cases (e.g. `eq foo foo`) trip the first `assert_status 0` and the file aborts.

- [x] **Step 3: Add the four command wrappers, dispatch arms, and usage lines**

**3a. Add command wrappers in `ci-toolkit`.** Open `ci-toolkit` and find `ci::cmd_strip_prefix` (around line 548). Insert the following block immediately above it (so the four predicate wrappers sit grouped together before the existing strip-prefix wrapper):

```bash
ci::cmd_eq() {
  if [[ $# -lt 2 ]]; then
    ci::usage >&2
    return 64
  fi
  ci::eq "$1" "$2"
}

ci::cmd_ne() {
  if [[ $# -lt 2 ]]; then
    ci::usage >&2
    return 64
  fi
  ci::ne "$1" "$2"
}

ci::cmd_in() {
  if [[ $# -lt 2 ]]; then
    ci::usage >&2
    return 64
  fi
  ci::in "$@"
}

ci::cmd_not_in() {
  if [[ $# -lt 2 ]]; then
    ci::usage >&2
    return 64
  fi
  ci::not_in "$@"
}
```

**3b. Add dispatch arms in `ci-toolkit`.** Find the `case "$command" in` block inside `ci::dispatch` (around lines 567–605). Insert the four new arms immediately above the `strip-prefix)` arm (so they are grouped with related string helpers):

```bash
    eq)
      ci::cmd_eq "$@"
      ;;
    ne)
      ci::cmd_ne "$@"
      ;;
    in)
      ci::cmd_in "$@"
      ;;
    not-in)
      ci::cmd_not_in "$@"
      ;;
```

**3c. Update `ci::usage` heredoc in `ci-toolkit`.** Inside the `ci::usage` heredoc (lines 359–384), add four new lines immediately above `  ci-toolkit strip-prefix PREFIX STRING`:

```
  ci-toolkit eq ACTUAL EXPECTED
  ci-toolkit ne ACTUAL EXPECTED
  ci-toolkit in VALUE CANDIDATE...
  ci-toolkit not-in VALUE CANDIDATE...
```

- [x] **Step 4: Run the full test file to verify it passes**

Run: `bash tests/test_string_predicates.sh`

Expected: PASS. All source-mode and CLI cases succeed, ending in `All tests passed`.

Also run the existing source-and-cli help test, which inspects the usage output:

Run: `bash tests/test_source_and_cli.sh`

Expected: PASS — the existing assertions check for `Usage:` and `Experimental` substrings, both still present.

- [x] **Step 5: Commit**

```bash
git add tests/test_string_predicates.sh ci-toolkit
git commit -m "feat: [toolkit] Add eq/ne/in/not-in CLI commands"
```

---

## Task 6: Update README CLI and Source API reference

**Files:**
- Modify: `README.md` (CLI reference table around lines 103–122; Source API reference around lines 124–171)

- [x] **Step 1: Add CLI rows to the README table**

Open `README.md`. In the CLI reference table, find the `strip-prefix PREFIX STRING` row (around line 116). Insert four new rows immediately above it, preserving table alignment:

```markdown
| `eq ACTUAL EXPECTED` | Exit `0` iff `ACTUAL` string-equals `EXPECTED`. Never prints compared values. |
| `ne ACTUAL EXPECTED` | Exit `0` iff `ACTUAL` string-differs from `EXPECTED`. Never prints compared values. |
| `in VALUE CANDIDATE...` | Exit `0` iff `VALUE` string-equals any `CANDIDATE`. Literal comparison; no glob/regex. |
| `not-in VALUE CANDIDATE...` | Exit `0` iff `VALUE` matches no `CANDIDATE`. Literal comparison; no glob/regex. |
```

- [x] **Step 2: Add a "String predicates" subsection to the Source API reference**

In `README.md`, find the `### Strings & versions` section (around line 155–161). Insert a new subsection immediately above it:

```markdown
### String predicates

| Function | Description |
| --- | --- |
| `ci::eq ACTUAL EXPECTED` | Return `0` iff `ACTUAL == EXPECTED` (literal Bash string equality). Never prints compared values; usage error returns `64`. |
| `ci::ne ACTUAL EXPECTED` | Return `0` iff `ACTUAL != EXPECTED`. Never prints compared values; usage error returns `64`. |
| `ci::in VALUE CANDIDATE...` | Return `0` iff `VALUE` string-equals any `CANDIDATE`. Literal comparison; no glob/regex. Usage error (fewer than 2 args) returns `64`. |
| `ci::not_in VALUE CANDIDATE...` | Return `0` iff `VALUE` matches none of the `CANDIDATE` arguments. Literal comparison; no glob/regex. Usage error returns `64`. |
```

- [x] **Step 3: Verify rendered table by inspecting the file**

Run: `grep -nE '\| \`(eq|ne|in|not-in|ci::eq|ci::ne|ci::in|ci::not_in)' README.md`

Expected: Eight matching lines — four from the CLI table, four from the Source API table.

- [x] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: [readme] Document string predicate helpers"
```

---

## Task 7: Update bilingual user docs

**Files:**
- Modify: `docs/user/en/index.md`, `docs/user/zh-TW/index.md`, `docs/user/en/index.html`, `docs/user/zh-TW/index.html`

The user docs are **prose-style**, organized by `<!-- doc-key: ... -->` sections. They are not tabular CLI/Source-API references like `README.md`. The natural home for these helpers is a new subsection under `<!-- doc-key: advanced-tools -->`, parallel to the existing **"Version-style Comparison"**, **"Prefix stripping"**, and **"Default ERR trap"** subsections.

`scripts/check-user-docs.ts` enforces that every locale carries the same set of required `doc-key` markers, but it does not validate content. Adding a new subsection inside an existing `doc-key` section is safe and does not require updating the checker.

- [x] **Step 1: Add a "String predicates" subsection to `docs/user/en/index.md`**

Open `docs/user/en/index.md`. Find the `### Prefix stripping` subsection (line 122–135) inside `<!-- doc-key: advanced-tools -->`. Insert the following block immediately after the `### Prefix stripping` block (i.e. after `If the prefix is absent, the original string is returned unchanged.`) and **before** the `### Default ERR trap` heading at line 137:

```markdown
### String predicates

Lightweight status-code helpers for the most common CI conditional: "does this string equal that string?" / "is this value in this allowed list?" They compare literal Bash strings — no glob, regex, or case folding — and never print compared values, which keeps them safe for inputs that may be sensitive.

```bash
# Source mode
branch=$(git branch --show-current)
if ci::eq "$branch" main; then
  ci::info "running main-branch checks"
fi

target_env="${TARGET_ENV:-}"
if ci::in "$target_env" staging production preview; then
  ci::info "accepted deploy target: $target_env"
else
  ci::die "unsupported deploy target: $target_env" || exit 1
fi

# CLI mode
./ci-toolkit eq "$TARGET_ENV" production
./ci-toolkit in  "$TARGET_ENV" staging production preview
./ci-toolkit not-in "$TARGET_ENV" dev experimental
```

| Helper | CLI | Behavior |
| --- | --- | --- |
| `ci::eq ACTUAL EXPECTED` | `eq` | Exit `0` iff `ACTUAL == EXPECTED`. |
| `ci::ne ACTUAL EXPECTED` | `ne` | Exit `0` iff `ACTUAL != EXPECTED`. |
| `ci::in VALUE CANDIDATE...` | `in` | Exit `0` iff `VALUE` matches any `CANDIDATE`. |
| `ci::not_in VALUE CANDIDATE...` | `not-in` | Exit `0` iff `VALUE` matches no `CANDIDATE`. |

Fewer than 2 arguments returns `64` (usage error) without printing values.
```

(Note: the inner triple-backtick fence in the example will need to be escaped or copied carefully — the engineer should copy from this plan's raw source.)

- [x] **Step 2: Add the same subsection (translated) to `docs/user/zh-TW/index.md`**

Open `docs/user/zh-TW/index.md`. Find `### 字串前綴移除` (line 122 region) inside `<!-- doc-key: advanced-tools -->`. Insert the following block immediately after that subsection's closing line (`若前綴不存在，原字串會原封不動回傳。` at line 135) and **before** the `### 預設 ERR 陷阱` heading at line 137:

```markdown
### 字串述詞

CI 條件判斷最常出現的需求 — 「這個字串等於那個字串嗎？」、「這個值是否在允許清單裡？」— 都收斂到四個輕量的狀態碼輔助函式。它們以字面字串比對為基礎，不支援萬用字元、正則或大小寫忽略，且**永遠不會印出比較的值**，因此對可能含有敏感資訊的輸入也安全。

```bash
# Source 模式
branch=$(git branch --show-current)
if ci::eq "$branch" main; then
  ci::info "running main-branch checks"
fi

target_env="${TARGET_ENV:-}"
if ci::in "$target_env" staging production preview; then
  ci::info "accepted deploy target: $target_env"
else
  ci::die "unsupported deploy target: $target_env" || exit 1
fi

# CLI 模式
./ci-toolkit eq "$TARGET_ENV" production
./ci-toolkit in  "$TARGET_ENV" staging production preview
./ci-toolkit not-in "$TARGET_ENV" dev experimental
```

| 輔助函式 | CLI | 行為 |
| --- | --- | --- |
| `ci::eq ACTUAL EXPECTED` | `eq` | `ACTUAL == EXPECTED` 時離開碼 `0`。 |
| `ci::ne ACTUAL EXPECTED` | `ne` | `ACTUAL != EXPECTED` 時離開碼 `0`。 |
| `ci::in VALUE CANDIDATE...` | `in` | `VALUE` 與任一 `CANDIDATE` 字面相等時離開碼 `0`。 |
| `ci::not_in VALUE CANDIDATE...` | `not-in` | `VALUE` 與所有 `CANDIDATE` 都不相等時離開碼 `0`。 |

少於 2 個參數視為使用方式錯誤，回傳 `64`，且不會印出任何值。
```

- [x] **Step 3: Mirror the new subsection into `docs/user/en/index.html`**

Open `docs/user/en/index.html`. Find the `<h3 class="mt-12">Prefix stripping</h3>` block (around line 239) and the paragraph ending `If the prefix is absent, the original string is returned unchanged.` (around line 247). Insert the following block immediately after that closing `</p>` and **before** `<h3 class="mt-12">Default ERR trap</h3>` (around line 249):

```html
            <h3 class="mt-12">String predicates</h3>
            <p>Lightweight status-code helpers for the most common CI conditional: "does this string equal that string?" / "is this value in this allowed list?" They compare literal Bash strings — no glob, regex, or case folding — and never print compared values, which keeps them safe for inputs that may be sensitive.</p>
            <pre><code># Source mode
branch=$(git branch --show-current)
if ci::eq "$branch" main; then
  ci::info "running main-branch checks"
fi

target_env="${TARGET_ENV:-}"
if ci::in "$target_env" staging production preview; then
  ci::info "accepted deploy target: $target_env"
else
  ci::die "unsupported deploy target: $target_env" || exit 1
fi

# CLI mode
./ci-toolkit eq "$TARGET_ENV" production
./ci-toolkit in  "$TARGET_ENV" staging production preview
./ci-toolkit not-in "$TARGET_ENV" dev experimental</code></pre>
            <table>
              <thead><tr><th>Helper</th><th>CLI</th><th>Behavior</th></tr></thead>
              <tbody>
                <tr><td><code>ci::eq ACTUAL EXPECTED</code></td><td><code>eq</code></td><td>Exit <code>0</code> iff <code>ACTUAL == EXPECTED</code>.</td></tr>
                <tr><td><code>ci::ne ACTUAL EXPECTED</code></td><td><code>ne</code></td><td>Exit <code>0</code> iff <code>ACTUAL != EXPECTED</code>.</td></tr>
                <tr><td><code>ci::in VALUE CANDIDATE...</code></td><td><code>in</code></td><td>Exit <code>0</code> iff <code>VALUE</code> matches any <code>CANDIDATE</code>.</td></tr>
                <tr><td><code>ci::not_in VALUE CANDIDATE...</code></td><td><code>not-in</code></td><td>Exit <code>0</code> iff <code>VALUE</code> matches no <code>CANDIDATE</code>.</td></tr>
              </tbody>
            </table>
            <p>Fewer than 2 arguments returns <code>64</code> (usage error) without printing values.</p>
```

If the surrounding HTML uses a different table class or wrapping `<div>`, match that local convention exactly — open `docs/user/en/index.html` first and copy the surrounding markup template.

- [x] **Step 4: Mirror the same translated subsection into `docs/user/zh-TW/index.html`**

Open `docs/user/zh-TW/index.html`. Find `<h3 class="mt-12">字串前綴移除</h3>` (around line 239) and the paragraph that closes that subsection. Insert the following block immediately after that closing `</p>` and **before** the `<h3 class="mt-12">預設 ERR 陷阱</h3>` heading:

```html
            <h3 class="mt-12">字串述詞</h3>
            <p>CI 條件判斷最常出現的需求 — 「這個字串等於那個字串嗎？」、「這個值是否在允許清單裡？」— 都收斂到四個輕量的狀態碼輔助函式。它們以字面字串比對為基礎，不支援萬用字元、正則或大小寫忽略，且<strong>永遠不會印出比較的值</strong>，因此對可能含有敏感資訊的輸入也安全。</p>
            <pre><code># Source 模式
branch=$(git branch --show-current)
if ci::eq "$branch" main; then
  ci::info "running main-branch checks"
fi

target_env="${TARGET_ENV:-}"
if ci::in "$target_env" staging production preview; then
  ci::info "accepted deploy target: $target_env"
else
  ci::die "unsupported deploy target: $target_env" || exit 1
fi

# CLI 模式
./ci-toolkit eq "$TARGET_ENV" production
./ci-toolkit in  "$TARGET_ENV" staging production preview
./ci-toolkit not-in "$TARGET_ENV" dev experimental</code></pre>
            <table>
              <thead><tr><th>輔助函式</th><th>CLI</th><th>行為</th></tr></thead>
              <tbody>
                <tr><td><code>ci::eq ACTUAL EXPECTED</code></td><td><code>eq</code></td><td><code>ACTUAL == EXPECTED</code> 時離開碼 <code>0</code>。</td></tr>
                <tr><td><code>ci::ne ACTUAL EXPECTED</code></td><td><code>ne</code></td><td><code>ACTUAL != EXPECTED</code> 時離開碼 <code>0</code>。</td></tr>
                <tr><td><code>ci::in VALUE CANDIDATE...</code></td><td><code>in</code></td><td><code>VALUE</code> 與任一 <code>CANDIDATE</code> 字面相等時離開碼 <code>0</code>。</td></tr>
                <tr><td><code>ci::not_in VALUE CANDIDATE...</code></td><td><code>not-in</code></td><td><code>VALUE</code> 與所有 <code>CANDIDATE</code> 都不相等時離開碼 <code>0</code>。</td></tr>
              </tbody>
            </table>
            <p>少於 2 個參數視為使用方式錯誤，回傳 <code>64</code>，且不會印出任何值。</p>
```

- [x] **Step 5: Run the user-docs parity checker**

Run: `bun run scripts/check-user-docs.ts`

Expected: PASS — the script verifies every required `<!-- doc-key: ... -->` marker exists in both locales and across `.md` + `.html`. Since this task adds content **inside** an existing `advanced-tools` section without introducing new doc-key markers, the checker stays green.

If `bun` is not installed locally, the checker can be skipped at this point and will run again as part of `./scripts/release-check gates` in Task 11.

- [x] **Step 6: Verify the new subsection is present in every doc file**

Run:

```bash
grep -c 'ci::eq\|ci::ne\|ci::in\|ci::not_in' \
  docs/user/en/index.md docs/user/zh-TW/index.md \
  docs/user/en/index.html docs/user/zh-TW/index.html
```

Expected: each of the four files reports `4` or more (one mention per helper, plus any extras in code blocks).

- [x] **Step 7: Commit**

```bash
git add docs/user/en/index.md docs/user/zh-TW/index.md docs/user/en/index.html docs/user/zh-TW/index.html
git commit -m "docs: [user-docs] Add string predicate helpers in en + zh-TW"
```

---

## Task 8: Update `scripts/smoke` with predicate checks

**Files:**
- Modify: `scripts/smoke` (line 11 region)

- [x] **Step 1: Read the current smoke script**

Run: `cat scripts/smoke`

Expected: The file already runs `help`, `version`, source-mode `ci::info`, `strip-prefix v v0.1.6`, and `version gt 0.1.6 0.1.5`.

- [x] **Step 2: Append predicate smoke checks**

Edit `scripts/smoke`. Insert three lines immediately after `"$ROOT_DIR/ci-toolkit" version gt 0.1.6 0.1.5` and immediately before the final `printf 'Smoke checks passed\n'`:

```bash
"$ROOT_DIR/ci-toolkit" eq 0.1.8 0.1.8
"$ROOT_DIR/ci-toolkit" in staging dev staging prod
"$ROOT_DIR/ci-toolkit" not-in qa dev staging prod
```

Each command exits `0` on success; the script's `set -euo pipefail` fails the smoke run on regression.

- [x] **Step 3: Run the smoke script**

Run: `./scripts/smoke`

Expected: `Smoke checks passed`.

- [x] **Step 4: Commit**

```bash
git add scripts/smoke
git commit -m "test: [smoke] Cover eq/in/not-in CLI predicates"
```

---

## Task 9: Bump `CI_TOOLKIT_VERSION` to `0.1.8` and add CHANGELOG entry

**Files:**
- Modify: `ci-toolkit` (line 7)
- Modify: `CHANGELOG.md` (prepend a new section above the existing `## v0.1.7` block at line 3)
- Modify: `tests/test_source_and_cli.sh` (line 32 hard-codes `ci-toolkit 0.1.7`)

- [x] **Step 1: Bump the version constant**

Edit `ci-toolkit`. Change line 7 from:

```bash
CI_TOOLKIT_VERSION="0.1.7"
```

to:

```bash
CI_TOOLKIT_VERSION="0.1.8"
```

- [x] **Step 2: Prepend the v0.1.8 CHANGELOG entry**

Edit `CHANGELOG.md`. Insert the following block immediately after line 1 (`# Changelog`) and one blank line before the existing `## v0.1.7 - Hardened helpers and release-check` section:

```markdown
## v0.1.8 - String predicate helpers

- Added four public string predicate helpers: `ci::eq ACTUAL EXPECTED`, `ci::ne ACTUAL EXPECTED`, `ci::in VALUE CANDIDATE...`, and `ci::not_in VALUE CANDIDATE...`. All four return status codes only; they never `exit`, never print compared values (safe for sensitive inputs), and never write to stdout on normal predicate evaluation. Usage errors return `64` via `ci::error` and print only the helper name in the usage line.
- Added matching CLI commands `ci-toolkit eq`, `ci-toolkit ne`, `ci-toolkit in`, and `ci-toolkit not-in` as thin wrappers over the source-mode helpers. Dispatch maps the dashed `not-in` command to `ci::not_in`. CLI commands return the same status codes (`0`, `1`, `64`) and emit no stdout on predicate success or failure.
- Behavior contract: comparisons are literal Bash string equality with no glob, regex, or case folding. Empty strings are valid values for all four helpers (`ci::eq "" ""` exits `0`, `ci::in "" "" x` exits `0`).
- Added `tests/test_string_predicates.sh` covering source mode (eq/ne/in/not_in success, failure, empty-string, usage error) and CLI mode (eq/ne/in/not-in success, failure, usage error). `scripts/smoke` now also runs one `eq`, one `in`, and one `not-in` check against the real artifact.
```

- [x] **Step 3: Bump the hard-coded version assertion in the source-and-CLI test**

Edit `tests/test_source_and_cli.sh`. Change line 32 from:

```bash
assert_eq "ci-toolkit 0.1.7" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.7"
```

to:

```bash
assert_eq "ci-toolkit 0.1.8" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.8"
```

- [x] **Step 4: Verify the version gate**

Run: `./scripts/release-check version`

Expected: `version: ok (0.1.8)`.

Run: `bash tests/test_source_and_cli.sh`

Expected: All `ok - ...` lines including the bumped `version command prints normalized 0.1.8` line.

- [x] **Step 5: Commit**

```bash
git add ci-toolkit CHANGELOG.md tests/test_source_and_cli.sh
git commit -m "feat: [release] Bump ci-toolkit to v0.1.8"
```

---

## Task 10: Refresh install-URL pins across README, user docs, and examples

**Files:**
- Modify: `README.md` (lines 25, 30 mention `v0.1.7`)
- Modify: `docs/user/en/index.md`, `docs/user/zh-TW/index.md`, `docs/user/en/index.html`, `docs/user/zh-TW/index.html` (each has one `releases/download/v0.1.7/ci-toolkit` line)
- Modify: `examples/bun-deploy/README.md`, `examples/laravel-bluegreen-deploy/README.md`, `examples/vendored-deploy-script/README.md`, `examples/vendored-deploy-script/deploy-prod.sh` (carry both `releases/download/v0.1.7/ci-toolkit` install URLs and `Vendor Gungnir ci-toolkit v0.1.7` commit-message strings)

`scripts/release-check examples` enforces that every install URL and `Vendor Gungnir ci-toolkit v…` commit-message string under `examples/` matches `CI_TOOLKIT_VERSION`. This task makes the find/replace explicit.

- [x] **Step 1: List every `v0.1.7` reference to be bumped**

Run:

```bash
grep -rn "v0.1.7" README.md docs/user/ examples/
```

Expected output: a small set of lines spanning `README.md` (2 lines), `docs/user/en/index.md` (1), `docs/user/zh-TW/index.md` (1), `docs/user/en/index.html` (1), `docs/user/zh-TW/index.html` (1), and the example files. Record the exact line numbers; every one of them gets bumped to `v0.1.8` in this task.

- [x] **Step 2: Bump `v0.1.7` → `v0.1.8` in `README.md`**

Edit `README.md`:

- Line 25: `curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.7/ci-toolkit -o ci-toolkit` → replace `v0.1.7` with `v0.1.8`.
- Line 30: `Pin to a tag (`v0.1.7` above).` → replace `v0.1.7` with `v0.1.8`.

- [x] **Step 3: Bump `v0.1.7` → `v0.1.8` in the four user-doc files**

Edit each of these files and replace `releases/download/v0.1.7/ci-toolkit` with `releases/download/v0.1.8/ci-toolkit` (one occurrence each):

- `docs/user/en/index.md`
- `docs/user/zh-TW/index.md`
- `docs/user/en/index.html`
- `docs/user/zh-TW/index.html`

- [x] **Step 4: Bump `v0.1.7` → `v0.1.8` in the example files**

Edit each of these files and replace every `v0.1.7` token with `v0.1.8`. This covers both the `releases/download/v0.1.7/ci-toolkit` install URLs and the `Vendor Gungnir ci-toolkit v0.1.7` commit-message strings:

- `examples/bun-deploy/README.md`
- `examples/laravel-bluegreen-deploy/README.md`
- `examples/vendored-deploy-script/README.md`
- `examples/vendored-deploy-script/deploy-prod.sh`

- [x] **Step 5: Verify nothing references the old version anymore**

Run:

```bash
grep -rn "v0.1.7" README.md docs/user/ examples/
```

Expected: empty output (no lines). If anything remains, replace it.

Then verify the new version is present everywhere it was expected to be:

Run:

```bash
grep -rcn "v0.1.8" README.md docs/user/ examples/
```

Expected: each file reports at least `1` (matching the bumped pin); some files may report higher counts.

- [x] **Step 6: Run the artifact + examples release-checks**

Run: `./scripts/release-check artifact`

Expected: `artifact: ok` (or equivalent success line). It also checks the README install URL matches the version constant.

Run: `./scripts/release-check examples`

Expected: success — the examples scan finds no diverging pin under `examples/`.

- [x] **Step 7: Commit**

```bash
git add README.md docs/user/ examples/
git commit -m "docs: [release] Bump install URL pins to v0.1.8"
```

---

## Task 11: Final release-readiness gates

**Files:**
- No file edits in this task. Run the full release-check pipeline and the standard local gates.

- [x] **Step 1: Run the full test suite**

Run: `./scripts/test`

Expected: every `tests/test_*.sh` passes; final aggregate line is `All tests passed` (or equivalent success message).

- [x] **Step 2: Run ShellCheck lint**

Run: `./scripts/lint`

Expected: PASS — either ShellCheck reports clean, or the script prints the "ShellCheck not installed; skipping" notice with exit `0`. Address any real warnings ShellCheck raises on the four new functions or wrappers.

- [x] **Step 3: Run smoke**

Run: `./scripts/smoke`

Expected: `Smoke checks passed`.

- [x] **Step 4: Run the full release-check pipeline**

Run: `./scripts/release-check all`

Expected: every step in the pipeline (`version`, `artifact`, `boundary`, `descriptions`, `copy-smoke`, `gates`, `examples`) reports success. The `descriptions` step in particular verifies that every public `ci::` function — including the four new predicates — has a `# @description` comment.

- [x] **Step 5: Verify discovery output lists the new helpers**

Run: `./ci-toolkit ls`

Expected: the output contains four new lines (sorted alphabetically by `ci::ls`):

```
  ci::eq               Return 0 iff ACTUAL string-equals EXPECTED. Never prints values.
  ci::in               Return 0 iff VALUE string-equals any of the CANDIDATE arguments.
  ci::ne               Return 0 iff ACTUAL string-differs from EXPECTED. Never prints values.
  ci::not_in           Return 0 iff VALUE matches none of the CANDIDATE arguments.
```

- [x] **Step 6: Verify CLI help lists the new commands**

Run: `./ci-toolkit help`

Expected: the printed usage block contains the four new lines:

```
  ci-toolkit eq ACTUAL EXPECTED
  ci-toolkit ne ACTUAL EXPECTED
  ci-toolkit in VALUE CANDIDATE...
  ci-toolkit not-in VALUE CANDIDATE...
```

- [x] **Step 7: No commit required**

Task 11 is a verification pass over commits already made in Tasks 1–10. If any gate fails, fix the underlying issue and add a follow-up commit before tagging.

---

## Summary of commits

By the end of this plan you should have a clean linear history that looks like:

```
feat: [toolkit] Add ci::eq string predicate
feat: [toolkit] Add ci::ne string predicate
feat: [toolkit] Add ci::in string predicate
feat: [toolkit] Add ci::not_in string predicate
feat: [toolkit] Add eq/ne/in/not-in CLI commands
docs: [readme] Document string predicate helpers
docs: [user-docs] Add string predicate helpers in en + zh-TW
test: [smoke] Cover eq/in/not-in CLI predicates
feat: [release] Bump ci-toolkit to v0.1.8
docs: [release] Bump install URL pins to v0.1.8
```

Each commit is independently testable. The release is ready to tag once `./scripts/release-check all` passes after Task 11.
---

## Completion status

Completed in v0.1.8. The implemented artifact includes the four source-mode helpers (`ci::eq`, `ci::ne`, `ci::in`, `ci::not_in`), matching CLI commands (`eq`, `ne`, `in`, `not-in`), README/CHANGELOG/user-doc updates, smoke coverage, and release-check pin refreshes.

