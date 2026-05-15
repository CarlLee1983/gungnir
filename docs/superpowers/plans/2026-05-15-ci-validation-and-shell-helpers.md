# Validation & Shell Helpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four platform-neutral validation helpers (`ci::require_file`, `ci::require_dir`, `ci::require_match`, `ci::require_uint`) and one shell-escape data helper (`ci::shell_join`) to the `ci-toolkit` single-file artifact, with matching nested CLI commands (`file require`, `dir require`, `match require`, `uint require`, `shell join`), full TDD coverage, and the surrounding release shape (version bump to **`v0.1.9`**, CHANGELOG, README + bilingual user docs, smoke check, examples install-URL refresh, release-check gates).

**Architecture:** Status-code helpers that return `0` on success, `1` on validation failure, and `64` on usage error. Validation helpers report logical `NAME` (never `VALUE`) so secrets never leak into stderr. The four `ci::require_*` helpers sit in the validation block between `ci::is_true` and the predicate cluster; `ci::shell_join` sits with the other data helpers next to `ci::strip_prefix`. CLI commands follow the nested-subcommand convention already used by `env require` and `tool require`. `ci::shell_join` uses Bash's built-in `printf '%q'` escaping, which is Bash-specific (acceptable since the toolkit already targets Bash 4+).

**Tech Stack:** Bash 4+, `set -euo pipefail` test harness in `tests/test_*.sh` using `tests/assert.sh` + per-file `run_capture`. ShellCheck for lint. No new dependencies.

---

## Spec reference

- Design spec: `docs/superpowers/specs/2026-05-15-ci-validation-and-shell-helpers-design.md`
- The repo currently ships **`v0.1.8`** (`CI_TOOLKIT_VERSION="0.1.8"` at `ci-toolkit:7`; latest `CHANGELOG.md` entry is `## v0.1.8 - String predicate helpers`). This plan targets **`v0.1.9`**.

## Implementation decisions (resolves spec §11)

1. **`ci::shell_join` placement:** group it with the data helpers next to `ci::strip_prefix`. Rationale: it primarily transforms argv into a string, mirroring `strip_prefix`'s "string in, string out" shape, and the spec lists data helpers as group 4 in the preferred grouping (§7).
2. **CLI naming:** use nested commands (`file require`, `dir require`, `match require`, `uint require`, `shell join`) — consistent with the existing `env require`, `tool require`, `version gt`, `git latest-tag`, `slack webhook` shape.
3. **`require_match` error text when no `DESCRIPTION` is given:** print the raw regex pattern (the pattern is the rule, not the sensitive value). Spec §5.3 explicitly permits this and tests assert that `VALUE` itself never appears in stderr.

## File structure

### Created

- `tests/test_validation_helpers.sh` — new behavior test file covering all four `ci::require_*` source-mode helpers plus their CLI counterparts. Models `run_capture` and assertion style after `tests/test_string_predicates.sh` and `tests/test_env_and_tools.sh` (especially the secret-leak assertions in the latter).
- `tests/test_shell_join.sh` — new behavior test file. Splitting it out keeps the round-trip test rig isolated from the file/dir/regex/uint test rigs; the round-trip needs a small controlled-`eval` helper that doesn't belong in the validation test file.

### Modified

- `ci-toolkit`:
  - Insert four `ci::require_*` library functions immediately after `ci::is_true` (closing brace at line 174) and immediately before `ci::eq` (starts line 177).
  - Insert `ci::shell_join` immediately after `ci::strip_prefix` (closing brace at line 317) and immediately before `ci::trap_err` (starts line 320).
  - Add five `ci::cmd_*` wrappers in the command-wrapper section near the existing `ci::cmd_strip_prefix` (line 631) and `ci::cmd_tool` (line 511) wrappers. Wrappers using nested subcommands (`file require`, `dir require`, `match require`, `uint require`, `shell join`) mirror the `ci::cmd_env` / `ci::cmd_tool` style.
  - Add five `case` arms (`file`, `dir`, `match`, `uint`, `shell`) in `ci::dispatch` (case block lines 650–700).
  - Add five `ci-toolkit ...` lines inside the `ci::usage` heredoc (lines 406–435).
  - Bump `CI_TOOLKIT_VERSION` from `"0.1.8"` to `"0.1.9"` (line 7).
- `CHANGELOG.md` — prepend a new `## v0.1.9 - Validation and shell-join helpers` section above the existing `## v0.1.8 - String predicate helpers` block at line 3.
- `README.md`:
  - Add five rows to the CLI reference table (between `not-in` and `strip-prefix`, plus one `shell join` row after `strip-prefix`).
  - Add new rows to the Source API "Validation" subsection (four `ci::require_*` helpers) and a new row in "Strings & versions" (or a new "Shell escaping" subsection) for `ci::shell_join`.
  - Refresh the install-URL pin from `v0.1.8` → `v0.1.9` (line 25 and the surrounding prose at line 30).
- `docs/user/en/index.md`, `docs/user/zh-TW/index.md`, `docs/user/en/index.html`, `docs/user/zh-TW/index.html`:
  - Refresh install-URL pin (`v0.1.8` → `v0.1.9`).
  - Add a new "Validation helpers" subsection (en + 驗證輔助函式 zh-TW) and a new "Shell argument escaping" subsection (en + Shell 參數逃逸 zh-TW) under `<!-- doc-key: advanced-tools -->`, parallel to the existing **String predicates** / **Prefix stripping** / **Default ERR trap** subsections.
- `examples/bun-deploy/README.md`, `examples/laravel-bluegreen-deploy/README.md`, `examples/vendored-deploy-script/README.md`, `examples/vendored-deploy-script/deploy-prod.sh` — refresh `v0.1.8` pins and `Vendor Gungnir ci-toolkit v0.1.8` commit-message strings to `v0.1.9` so `release-check examples` stays green.
- `scripts/smoke` — add two low-cost checks: one validation helper (e.g. `ci-toolkit uint require COUNT 5`) and one shell-join check.
- `tests/test_source_and_cli.sh` — bump the single hard-coded version assertion from `"ci-toolkit 0.1.8"` to `"ci-toolkit 0.1.9"` (current location: line 32).

### Untouched

- `tests/test_string_predicates.sh`, `tests/test_strip_prefix.sh`, `tests/test_env_and_tools.sh`, all other existing `tests/test_*.sh` — no changes needed; the new helpers do not alter existing behavior.
- `tests/assert.sh` — no harness change required.
- `scripts/test`, `scripts/lint`, `scripts/release-check` — no logic change. They simply pick up the new tests, new CHANGELOG entry, and new install-URL pins.

---

## Task 1: `ci::require_file` library function

**Files:**
- Create: `tests/test_validation_helpers.sh`
- Modify: `ci-toolkit` (insert immediately after the closing brace of `ci::is_true` at line 174, before `ci::eq` at line 177)

- [ ] **Step 1: Create the failing test file with `ci::require_file` cases**

Write `tests/test_validation_helpers.sh`:

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

# -- Source mode: ci::require_file (spec §5.1, §8.1) ----------------------

TMP_DIR="$(make_temp_dir)"
EXISTING_FILE="$TMP_DIR/present.txt"
MISSING_FILE="$TMP_DIR/absent.txt"
EXISTING_DIR="$TMP_DIR/some-dir"
printf 'hello\n' >"$EXISTING_FILE"
mkdir -p "$EXISTING_DIR"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG '$EXISTING_FILE'"
assert_status 0 "$RUN_STATUS" "source require_file present exits 0"
assert_eq "" "$RUN_STDOUT" "source require_file present writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_file present writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG '$MISSING_FILE'"
assert_status 1 "$RUN_STATUS" "source require_file missing exits 1"
assert_contains "$RUN_STDERR" "CONFIG" "source require_file missing names CONFIG"
assert_not_contains "$RUN_STDERR" "$MISSING_FILE" \
  "source require_file missing does not echo the path"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG '$MISSING_FILE' 'run build.sh first'"
assert_status 1 "$RUN_STATUS" "source require_file with hint still exits 1"
assert_contains "$RUN_STDERR" "CONFIG" "source require_file hint still names CONFIG"
assert_contains "$RUN_STDERR" "run build.sh first" \
  "source require_file hint appears in stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file DIR_AS_FILE '$EXISTING_DIR'"
assert_status 1 "$RUN_STATUS" "source require_file rejects directory path"
assert_contains "$RUN_STDERR" "DIR_AS_FILE" "source require_file rejects dir, names NAME"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_file CONFIG"
assert_status 64 "$RUN_STATUS" "source require_file missing args exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_file" \
  "source require_file missing args prints usage"

finish_tests
```

Make it executable:

```bash
chmod +x tests/test_validation_helpers.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_validation_helpers.sh`

Expected: FAIL. The first `run_capture` trips on `ci::require_file: command not found`; the script aborts before `finish_tests`.

- [ ] **Step 3: Implement `ci::require_file` in `ci-toolkit`**

Edit `ci-toolkit`. Find the closing brace of `ci::is_true` (line 174). Insert the following block on the blank line that follows it (i.e. so the new function sits between `ci::is_true` and the predicate block starting with `ci::eq`):

```bash
# @description Require PATH to exist and be a regular file. Reports NAME, never PATH.
ci::require_file() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::require_file NAME PATH [HINT]"
    return 64
  fi
  local name="$1"
  local path="$2"
  local hint="${3:-}"
  if [[ -f "$path" ]]; then
    return 0
  fi
  if [[ -n "$hint" ]]; then
    ci::error "required file missing: $name ($hint)"
  else
    ci::error "required file missing: $name"
  fi
  return 1
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_validation_helpers.sh`

Expected: PASS. Every `ok - ...` line, ending in `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_validation_helpers.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::require_file validation helper"
```

---

## Task 2: `ci::require_dir` library function

**Files:**
- Modify: `tests/test_validation_helpers.sh` (append before `finish_tests`)
- Modify: `ci-toolkit` (insert directly after the `ci::require_file` block from Task 1)

- [ ] **Step 1: Append failing tests for `ci::require_dir`**

Edit `tests/test_validation_helpers.sh`. Insert the following block immediately above the `finish_tests` line (keep `finish_tests` last). The block reuses the `TMP_DIR`, `EXISTING_FILE`, `EXISTING_DIR` paths created in Task 1.

```bash
# -- Source mode: ci::require_dir (spec §5.2, §8.1) -----------------------

MISSING_DIR="$TMP_DIR/absent-dir"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING '$EXISTING_DIR'"
assert_status 0 "$RUN_STATUS" "source require_dir present exits 0"
assert_eq "" "$RUN_STDOUT" "source require_dir present writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_dir present writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING '$MISSING_DIR'"
assert_status 1 "$RUN_STATUS" "source require_dir missing exits 1"
assert_contains "$RUN_STDERR" "STAGING" "source require_dir missing names STAGING"
assert_not_contains "$RUN_STDERR" "$MISSING_DIR" \
  "source require_dir missing does not echo the path"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING '$MISSING_DIR' 'run build.sh first'"
assert_status 1 "$RUN_STATUS" "source require_dir with hint still exits 1"
assert_contains "$RUN_STDERR" "run build.sh first" \
  "source require_dir hint appears in stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir FILE_AS_DIR '$EXISTING_FILE'"
assert_status 1 "$RUN_STATUS" "source require_dir rejects regular file"
assert_contains "$RUN_STDERR" "FILE_AS_DIR" "source require_dir rejects file, names NAME"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_dir STAGING"
assert_status 64 "$RUN_STATUS" "source require_dir missing args exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_dir" \
  "source require_dir missing args prints usage"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_validation_helpers.sh`

Expected: FAIL. The first new `run_capture` reports `ci::require_dir: command not found`.

- [ ] **Step 3: Implement `ci::require_dir` in `ci-toolkit`**

Edit `ci-toolkit`. Insert the following block immediately after the closing brace of `ci::require_file` (added in Task 1):

```bash
# @description Require PATH to exist and be a directory. Reports NAME, never PATH.
ci::require_dir() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::require_dir NAME PATH [HINT]"
    return 64
  fi
  local name="$1"
  local path="$2"
  local hint="${3:-}"
  if [[ -d "$path" ]]; then
    return 0
  fi
  if [[ -n "$hint" ]]; then
    ci::error "required directory missing: $name ($hint)"
  else
    ci::error "required directory missing: $name"
  fi
  return 1
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_validation_helpers.sh`

Expected: PASS for all `ci::require_file` and `ci::require_dir` cases, ending in `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_validation_helpers.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::require_dir validation helper"
```

---

## Task 3: `ci::require_match` library function (regex allowlist with no value leakage)

**Files:**
- Modify: `tests/test_validation_helpers.sh` (append before `finish_tests`)
- Modify: `ci-toolkit` (insert directly after the `ci::require_dir` block from Task 2)

- [ ] **Step 1: Append failing tests for `ci::require_match`**

Edit `tests/test_validation_helpers.sh`. Insert the following block immediately above `finish_tests`. The "SECRET-LIKE-VALUE-DO-NOT-LEAK" string is the canary: it must never appear in stderr.

```bash
# -- Source mode: ci::require_match (spec §5.3, §8.1, §10) ---------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match DEPLOY_USER arcade '^[A-Za-z0-9._-]+$'"
assert_status 0 "$RUN_STATUS" "source require_match valid exits 0"
assert_eq "" "$RUN_STDOUT" "source require_match valid writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_match valid writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match DEPLOY_USER 'SECRET-LIKE-VALUE-DO-NOT-LEAK' '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'"
assert_status 1 "$RUN_STATUS" "source require_match invalid exits 1"
assert_contains "$RUN_STDERR" "DEPLOY_USER" \
  "source require_match invalid names DEPLOY_USER"
assert_contains "$RUN_STDERR" "[A-Za-z0-9._-]+" \
  "source require_match invalid prints description"
assert_not_contains "$RUN_STDERR" "SECRET-LIKE-VALUE-DO-NOT-LEAK" \
  "source require_match invalid does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match DEPLOY_USER 'SECRET-LIKE-VALUE-DO-NOT-LEAK' '^[A-Za-z0-9._-]+$'"
assert_status 1 "$RUN_STATUS" "source require_match invalid (no desc) exits 1"
assert_contains "$RUN_STDERR" "DEPLOY_USER" \
  "source require_match invalid (no desc) names DEPLOY_USER"
assert_contains "$RUN_STDERR" "^[A-Za-z0-9._-]+$" \
  "source require_match invalid (no desc) prints raw regex as rule"
assert_not_contains "$RUN_STDERR" "SECRET-LIKE-VALUE-DO-NOT-LEAK" \
  "source require_match invalid (no desc) does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match COUNT '0' '^[0-9]+$'"
assert_status 0 "$RUN_STATUS" "source require_match numeric valid exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_match NAME value"
assert_status 64 "$RUN_STATUS" "source require_match missing regex exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_match" \
  "source require_match missing regex prints usage"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_validation_helpers.sh`

Expected: FAIL. The first new `run_capture` reports `ci::require_match: command not found`.

- [ ] **Step 3: Implement `ci::require_match` in `ci-toolkit`**

Edit `ci-toolkit`. Insert the following block immediately after the closing brace of `ci::require_dir` (added in Task 2):

```bash
# @description Require VALUE to match the Bash extended regex REGEX. Reports NAME and rule, never VALUE.
ci::require_match() {
  if [[ $# -lt 3 ]]; then
    ci::error "Usage: ci::require_match NAME VALUE REGEX [DESCRIPTION]"
    return 64
  fi
  local name="$1"
  local value="$2"
  local regex="$3"
  local description="${4:-$regex}"
  if [[ "$value" =~ $regex ]]; then
    return 0
  fi
  ci::error "invalid $name (expected $description)"
  return 1
}
```

Note: `[[ "$value" =~ $regex ]]` uses Bash's built-in extended regex matcher. The right-hand side must be **unquoted** — quoting the regex literalizes it. This is the standard Bash idiom; ShellCheck is fine with it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_validation_helpers.sh`

Expected: PASS for all `ci::require_file`, `ci::require_dir`, and `ci::require_match` cases. The secret-leak canary assertions confirm `SECRET-LIKE-VALUE-DO-NOT-LEAK` does not appear in stderr.

- [ ] **Step 5: Commit**

```bash
git add tests/test_validation_helpers.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::require_match regex validation helper"
```

---

## Task 4: `ci::require_uint` library function

**Files:**
- Modify: `tests/test_validation_helpers.sh` (append before `finish_tests`)
- Modify: `ci-toolkit` (insert directly after the `ci::require_match` block from Task 3)

- [ ] **Step 1: Append failing tests for `ci::require_uint`**

Edit `tests/test_validation_helpers.sh`. Insert the following block immediately above `finish_tests`:

```bash
# -- Source mode: ci::require_uint (spec §5.4, §8.1) ----------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 0"
assert_status 0 "$RUN_STATUS" "source require_uint 0 exits 0"
assert_eq "" "$RUN_STDOUT" "source require_uint 0 writes no stdout"
assert_eq "" "$RUN_STDERR" "source require_uint 0 writes no stderr"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 5"
assert_status 0 "$RUN_STATUS" "source require_uint 5 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 12345"
assert_status 0 "$RUN_STATUS" "source require_uint 12345 exits 0"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT -1"
assert_status 1 "$RUN_STATUS" "source require_uint negative exits 1"
assert_contains "$RUN_STDERR" "COUNT" "source require_uint negative names COUNT"
assert_not_contains "$RUN_STDERR" "-1" \
  "source require_uint negative does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT +1"
assert_status 1 "$RUN_STATUS" "source require_uint signed exits 1"
assert_contains "$RUN_STDERR" "COUNT" "source require_uint signed names COUNT"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT 1.5"
assert_status 1 "$RUN_STATUS" "source require_uint decimal exits 1"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT ''"
assert_status 1 "$RUN_STATUS" "source require_uint empty exits 1"
assert_contains "$RUN_STDERR" "COUNT" "source require_uint empty names COUNT"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT abc"
assert_status 1 "$RUN_STATUS" "source require_uint abc exits 1"
assert_not_contains "$RUN_STDERR" "abc" \
  "source require_uint abc does not echo VALUE"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::require_uint COUNT"
assert_status 64 "$RUN_STATUS" "source require_uint missing arg exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::require_uint" \
  "source require_uint missing arg prints usage"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_validation_helpers.sh`

Expected: FAIL. The first new `run_capture` reports `ci::require_uint: command not found`.

- [ ] **Step 3: Implement `ci::require_uint` in `ci-toolkit`**

Edit `ci-toolkit`. Insert the following block immediately after the closing brace of `ci::require_match` (added in Task 3):

```bash
# @description Require VALUE to be a non-negative base-10 integer (0 or digits, no sign). Reports NAME, never VALUE.
ci::require_uint() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::require_uint NAME VALUE"
    return 64
  fi
  local name="$1"
  local value="$2"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  ci::error "invalid $name (non-negative integer required)"
  return 1
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_validation_helpers.sh`

Expected: PASS for all four `ci::require_*` helpers' source-mode cases, ending in `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_validation_helpers.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::require_uint validation helper"
```

---

## Task 5: `ci::shell_join` data helper

**Files:**
- Create: `tests/test_shell_join.sh`
- Modify: `ci-toolkit` (insert immediately after the closing brace of `ci::strip_prefix` at line 317, before `ci::trap_err` at line 320)

- [ ] **Step 1: Create the failing test file**

Write `tests/test_shell_join.sh`. The round-trip helper reparses the joined string inside a controlled `bash -c` and writes each argv element on its own line so we can compare counts and contents without executing any of them.

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

# Reparse a joined shell string into "$#\narg1\narg2\n..." inside a controlled
# subshell. NEVER feed untrusted input here; this is for round-trip testing
# against ci::shell_join output only.
reparse_joined() {
  local joined="$1"
  bash -c '
    eval "set -- $1"
    printf "%s\n" "$#"
    for arg; do
      printf "%s\n" "$arg"
    done
  ' _ "$joined"
}

set -e

# -- Source mode: ci::shell_join (spec §5.5, §8.2) ------------------------

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join ssh -p 22 host"
assert_status 0 "$RUN_STATUS" "source shell_join simple exits 0"
assert_eq "" "$RUN_STDERR" "source shell_join simple writes no stderr"
assert_contains "$RUN_STDOUT" "ssh" "source shell_join simple contains ssh"
assert_contains "$RUN_STDOUT" "22" "source shell_join simple contains 22"
assert_contains "$RUN_STDOUT" "host" "source shell_join simple contains host"

# Round-trip: simple argv
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join ssh -p 22 host")
reparsed="$(reparse_joined "$joined")"
expected=$'4\nssh\n-p\n22\nhost'
assert_eq "$expected" "$reparsed" "shell_join simple round-trips"

# Round-trip: argv with spaces
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join 'hello world' two")
reparsed="$(reparse_joined "$joined")"
expected=$'2\nhello world\ntwo'
assert_eq "$expected" "$reparsed" "shell_join spaces round-trips"

# Round-trip: argv with quotes and backslash
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join \"it's\" 'a \"quote\"' 'back\\\\slash'")
reparsed="$(reparse_joined "$joined")"
expected=$'3\nit\'s\na "quote"\nback\\slash'
assert_eq "$expected" "$reparsed" "shell_join quotes round-trips"

# Round-trip: argv with glob characters
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join '*.txt' '[abc]?' 'plain'")
reparsed="$(reparse_joined "$joined")"
expected=$'3\n*.txt\n[abc]?\nplain'
assert_eq "$expected" "$reparsed" "shell_join glob round-trips"

# Round-trip: argv with empty string. Place the empty arg in a non-trailing
# position — command substitution strips trailing newlines, so a trailing
# empty arg in reparse output would silently disappear.
joined=$(bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join '' nonempty trailing")
reparsed="$(reparse_joined "$joined")"
expected=$'3\n\nnonempty\ntrailing'
assert_eq "$expected" "$reparsed" "shell_join empty-string round-trips"

# Zero args
run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::shell_join"
assert_status 64 "$RUN_STATUS" "source shell_join no args exits 64"
assert_contains "$RUN_STDERR" "Usage: ci::shell_join" \
  "source shell_join no args prints usage"

finish_tests
```

(Note: command substitution `$(...)` already strips the trailing newline from `ci::shell_join`, so `joined` does not need extra trimming before being passed to `reparse_joined`.)

Make it executable:

```bash
chmod +x tests/test_shell_join.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_shell_join.sh`

Expected: FAIL. The first `run_capture` reports `ci::shell_join: command not found` and the script aborts.

- [ ] **Step 3: Implement `ci::shell_join` in `ci-toolkit`**

Edit `ci-toolkit`. Find the closing brace of `ci::strip_prefix` (line 317). Insert the following block immediately after it (before `ci::trap_err` at line 320). Keep one blank line before and after:

```bash
# @description Print argv as a Bash-escaped command string suitable for re-parsing by Bash (e.g. rsync -e).
ci::shell_join() {
  if [[ $# -lt 1 ]]; then
    ci::error "Usage: ci::shell_join ARG..."
    return 64
  fi
  local joined
  printf -v joined '%q ' "$@"
  printf '%s\n' "${joined% }"
}
```

Notes on the implementation:
- `printf -v joined '%q ' "$@"` collects each `%q`-escaped argument followed by a single space into the variable `joined`. With three args `a 'b c' d`, `joined` ends up as `a b\ c d ` (or `a 'b c' d ` depending on the Bash build's preferred escape — both are valid `%q` output).
- `${joined% }` strips exactly one trailing space, leaving the final argument's escaping intact.
- `printf '%s\n' "${joined% }"` writes the joined string plus a single trailing newline to stdout, matching `ci::strip_prefix`'s output shape so command substitution (`$(...)`) drops the newline cleanly.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_shell_join.sh`

Expected: PASS for every case (simple argv, spaces, quotes/backslash, glob chars, empty string, zero-arg usage error), ending in `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_shell_join.sh ci-toolkit
git commit -m "feat: [toolkit] Add ci::shell_join data helper"
```

---

## Task 6: CLI commands, dispatch, and usage text

**Files:**
- Modify: `tests/test_validation_helpers.sh` (append before `finish_tests`)
- Modify: `tests/test_shell_join.sh` (append before `finish_tests`)
- Modify: `ci-toolkit`:
  - Add five `ci::cmd_*` wrappers in the command-wrapper section. Place them grouped together immediately above `ci::cmd_strip_prefix` (currently at line 631) — they follow the nested-subcommand style used by `ci::cmd_env` (line 482) and `ci::cmd_tool` (line 511).
  - Add five `case` arms (`file`, `dir`, `match`, `uint`, `shell`) inside `ci::dispatch` (case block at lines 650–700). Place them immediately above the existing `strip-prefix)` arm to keep validation-related dispatch arms together.
  - Add five `ci-toolkit ...` lines inside the `ci::usage` heredoc (lines 406–435), immediately above the existing `ci-toolkit strip-prefix PREFIX STRING` line.

- [ ] **Step 1: Append failing CLI tests to `tests/test_validation_helpers.sh`**

Edit `tests/test_validation_helpers.sh`. Insert the following block immediately above `finish_tests`:

```bash
# -- CLI mode (spec §8.3) -------------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" file require CONFIG "$EXISTING_FILE"
assert_status 0 "$RUN_STATUS" "CLI file require present exits 0"
assert_eq "" "$RUN_STDOUT" "CLI file require present writes no stdout"
assert_eq "" "$RUN_STDERR" "CLI file require present writes no stderr"

run_capture "$ROOT_DIR/ci-toolkit" file require CONFIG "$MISSING_FILE"
assert_status 1 "$RUN_STATUS" "CLI file require missing exits 1"
assert_contains "$RUN_STDERR" "CONFIG" "CLI file require missing names CONFIG"

run_capture "$ROOT_DIR/ci-toolkit" file require
assert_status 64 "$RUN_STATUS" "CLI file require missing args exits 64"

run_capture "$ROOT_DIR/ci-toolkit" dir require STAGING "$EXISTING_DIR"
assert_status 0 "$RUN_STATUS" "CLI dir require present exits 0"

run_capture "$ROOT_DIR/ci-toolkit" dir require STAGING "$MISSING_DIR"
assert_status 1 "$RUN_STATUS" "CLI dir require missing exits 1"
assert_contains "$RUN_STDERR" "STAGING" "CLI dir require missing names STAGING"

run_capture "$ROOT_DIR/ci-toolkit" match require DEPLOY_USER arcade '^[A-Za-z0-9._-]+$'
assert_status 0 "$RUN_STATUS" "CLI match require valid exits 0"

run_capture "$ROOT_DIR/ci-toolkit" match require DEPLOY_USER 'SECRET-LIKE-VALUE-DO-NOT-LEAK' '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
assert_status 1 "$RUN_STATUS" "CLI match require invalid exits 1"
assert_contains "$RUN_STDERR" "DEPLOY_USER" "CLI match require invalid names DEPLOY_USER"
assert_contains "$RUN_STDERR" "[A-Za-z0-9._-]+" "CLI match require invalid prints description"
assert_not_contains "$RUN_STDERR" "SECRET-LIKE-VALUE-DO-NOT-LEAK" \
  "CLI match require invalid does not echo VALUE"

run_capture "$ROOT_DIR/ci-toolkit" uint require COUNT 5
assert_status 0 "$RUN_STATUS" "CLI uint require 5 exits 0"

run_capture "$ROOT_DIR/ci-toolkit" uint require COUNT -1
assert_status 1 "$RUN_STATUS" "CLI uint require -1 exits 1"
assert_contains "$RUN_STDERR" "COUNT" "CLI uint require -1 names COUNT"

run_capture "$ROOT_DIR/ci-toolkit" uint require
assert_status 64 "$RUN_STATUS" "CLI uint require missing args exits 64"
```

- [ ] **Step 2: Append failing CLI tests to `tests/test_shell_join.sh`**

Edit `tests/test_shell_join.sh`. Insert the following block immediately above `finish_tests`:

```bash
# -- CLI mode (spec §8.3) -------------------------------------------------

run_capture "$ROOT_DIR/ci-toolkit" shell join ssh -p 22 host
assert_status 0 "$RUN_STATUS" "CLI shell join simple exits 0"
assert_contains "$RUN_STDOUT" "ssh" "CLI shell join contains ssh"
assert_contains "$RUN_STDOUT" "22" "CLI shell join contains 22"
assert_contains "$RUN_STDOUT" "host" "CLI shell join contains host"

# CLI round-trip with spaces
joined_cli=$("$ROOT_DIR/ci-toolkit" shell join 'hello world' two)
reparsed_cli="$(reparse_joined "$joined_cli")"
expected_cli=$'2\nhello world\ntwo'
assert_eq "$expected_cli" "$reparsed_cli" "CLI shell join spaces round-trips"

run_capture "$ROOT_DIR/ci-toolkit" shell join
assert_status 64 "$RUN_STATUS" "CLI shell join no args exits 64"
```

- [ ] **Step 3: Run both test files to verify they fail**

Run:

```bash
bash tests/test_validation_helpers.sh
bash tests/test_shell_join.sh
```

Expected: FAIL — the new CLI cases hit the dispatch `*)` arm and exit `64`, so the `assert_status 0` lines (e.g. `CLI file require present exits 0`) abort the script.

- [ ] **Step 4: Add the five command wrappers in `ci-toolkit`**

Open `ci-toolkit` and find `ci::cmd_strip_prefix` (line 631). Insert the following block immediately above it (so the five new wrappers sit grouped together):

```bash
ci::cmd_file() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    require)
      if [[ $# -lt 2 ]]; then
        ci::usage >&2
        return 64
      fi
      ci::require_file "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}

ci::cmd_dir() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    require)
      if [[ $# -lt 2 ]]; then
        ci::usage >&2
        return 64
      fi
      ci::require_dir "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}

ci::cmd_match() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    require)
      if [[ $# -lt 3 ]]; then
        ci::usage >&2
        return 64
      fi
      ci::require_match "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}

ci::cmd_uint() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    require)
      if [[ $# -lt 2 ]]; then
        ci::usage >&2
        return 64
      fi
      ci::require_uint "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}

ci::cmd_shell() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    join)
      if [[ $# -lt 1 ]]; then
        ci::usage >&2
        return 64
      fi
      ci::shell_join "$@"
      ;;
    *)
      ci::usage >&2
      return 64
      ;;
  esac
}
```

- [ ] **Step 5: Add five `case` arms inside `ci::dispatch`**

Find the `case "$command" in` block inside `ci::dispatch` (around lines 650–700). Insert the five new arms immediately above the existing `strip-prefix)` arm:

```bash
    file)
      ci::cmd_file "$@"
      ;;
    dir)
      ci::cmd_dir "$@"
      ;;
    match)
      ci::cmd_match "$@"
      ;;
    uint)
      ci::cmd_uint "$@"
      ;;
    shell)
      ci::cmd_shell "$@"
      ;;
```

- [ ] **Step 6: Update `ci::usage` heredoc in `ci-toolkit`**

Inside the `ci::usage` heredoc (lines 406–435), add five new lines immediately above `  ci-toolkit strip-prefix PREFIX STRING`:

```
  ci-toolkit file require NAME PATH [HINT]
  ci-toolkit dir require NAME PATH [HINT]
  ci-toolkit match require NAME VALUE REGEX [DESCRIPTION]
  ci-toolkit uint require NAME VALUE
  ci-toolkit shell join ARG...
```

- [ ] **Step 7: Run both test files to verify they pass**

Run:

```bash
bash tests/test_validation_helpers.sh
bash tests/test_shell_join.sh
```

Expected: PASS — every source-mode and CLI case succeeds, both files end in `All tests passed`.

Also run the existing source-and-cli help test, which inspects the usage output:

Run: `bash tests/test_source_and_cli.sh`

Expected: PASS — the existing assertions check for `Usage:` and `Experimental` substrings, both still present. The version assertion still reads `0.1.8` against an artifact that still reports `0.1.8`, so this test is green at this point. (It gets bumped in Task 10.)

- [ ] **Step 8: Commit**

```bash
git add tests/test_validation_helpers.sh tests/test_shell_join.sh ci-toolkit
git commit -m "feat: [toolkit] Add file/dir/match/uint/shell-join CLI commands"
```

---

## Task 7: Update README CLI and Source API reference

**Files:**
- Modify: `README.md` (CLI reference table around lines 105–125; Source API reference around lines 128–185)

- [ ] **Step 1: Add CLI rows to the README table**

Open `README.md`. In the CLI reference table, find the `strip-prefix PREFIX STRING` row (currently around line 120). Insert five new rows immediately above it (so they group with related validation commands and the data helper), preserving table alignment:

```markdown
| `file require NAME PATH [HINT]` | Exit `1` if `PATH` does not exist or is not a regular file. Reports `NAME`, never the path. |
| `dir require NAME PATH [HINT]` | Exit `1` if `PATH` does not exist or is not a directory. Reports `NAME`, never the path. |
| `match require NAME VALUE REGEX [DESCRIPTION]` | Exit `1` if `VALUE` does not match the Bash extended `REGEX`. Reports `NAME` and `DESCRIPTION` (or the raw regex if omitted), never `VALUE`. |
| `uint require NAME VALUE` | Exit `1` if `VALUE` is not a non-negative base-10 integer. Reports `NAME`, never `VALUE`. |
| `shell join ARG...` | Print `ARG...` as a Bash-escaped command string suitable for re-parsing by Bash (e.g. `rsync -e`). |
```

- [ ] **Step 2: Extend the Source API "Validation" subsection**

In `README.md`, find the existing **`### Validation`** subsection (around line 143). Append four new rows to its table so the row list reads:

```markdown
| Function | Description |
| --- | --- |
| `ci::require_env VAR_NAME` | Return `1` if `VAR_NAME` is unset or empty. The value is never printed; only the name appears in the error message. |
| `ci::env_default VAR_NAME DEFAULT` | Set `VAR_NAME` to `DEFAULT` in the current shell if it is unset or empty. |
| `ci::is_true VAR_NAME` | Return `0` if variable is `1` or `true`. |
| `ci::require_tool TOOL_NAME` | Return `1` if `TOOL_NAME` is not resolvable via `command -v`. |
| `ci::require_file NAME PATH [HINT]` | Return `1` if `PATH` does not exist or is not a regular file. Reports `NAME`, never `PATH`. Usage error returns `64`. |
| `ci::require_dir NAME PATH [HINT]` | Return `1` if `PATH` does not exist or is not a directory. Reports `NAME`, never `PATH`. Usage error returns `64`. |
| `ci::require_match NAME VALUE REGEX [DESCRIPTION]` | Return `1` if `VALUE` does not match Bash extended `REGEX`. Reports `NAME` and `DESCRIPTION` (or the raw regex), never `VALUE`. Usage error returns `64`. |
| `ci::require_uint NAME VALUE` | Return `1` if `VALUE` is not a non-negative base-10 integer (no sign, no decimal). Reports `NAME`, never `VALUE`. Usage error returns `64`. |
```

- [ ] **Step 3: Add a "Shell escaping" subsection to the Source API reference**

In `README.md`, find the `### Strings & versions` section. Insert a new subsection **immediately above it**, between `### String predicates` and `### Strings & versions`:

```markdown
### Shell escaping

| Function | Description |
| --- | --- |
| `ci::shell_join ARG...` | Print `ARG...` as a Bash-escaped command string suitable for re-parsing by Bash (e.g. as the value of `rsync -e`). Uses `printf '%q'`; the output is Bash-escaped, not POSIX-sh portable. Zero args returns `64`. |
```

- [ ] **Step 4: Verify the new rows are present**

Run:

```bash
grep -nE '\| `(file require|dir require|match require|uint require|shell join|ci::require_file|ci::require_dir|ci::require_match|ci::require_uint|ci::shell_join)' README.md
```

Expected: ten matching lines — five from the CLI table, four from the extended Validation table, one from the new Shell escaping subsection.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: [readme] Document validation and shell_join helpers"
```

---

## Task 8: Update bilingual user docs (md + html in en + zh-TW)

**Files:**
- Modify: `docs/user/en/index.md`, `docs/user/zh-TW/index.md`, `docs/user/en/index.html`, `docs/user/zh-TW/index.html`

The user docs are prose-style, organized by `<!-- doc-key: ... -->` sections. The natural home for the new helpers is two new subsections under `<!-- doc-key: advanced-tools -->`, parallel to the existing **Version-style Comparison** / **Prefix stripping** / **String predicates** / **Default ERR trap** subsections. `scripts/check-user-docs.ts` enforces the same `doc-key` marker set in every locale and across `.md` + `.html`; adding content **inside** an existing `advanced-tools` section without introducing new doc-keys is safe.

- [ ] **Step 1: Add a "Validation helpers" subsection to `docs/user/en/index.md`**

Open `docs/user/en/index.md`. Find the `### String predicates` subsection (around lines 137–168) inside `<!-- doc-key: advanced-tools -->`. Insert the following block immediately after that subsection's closing line (the one reading `Fewer than 2 arguments returns ` `64` ` (usage error) without printing values.`) and **before** the `### Default ERR trap` heading:

````markdown
### Validation helpers

Four short helpers that turn repeated guard blocks into named contracts. They all report the **logical name** of the failing field, never the value or path — safe for secrets and avoidable PII.

```bash
# Source mode
ci::require_file LATEST_NAME_FILE "$DIST_DIR/.latest-name" "run build.sh first" || exit $?
ci::require_dir  STAGING_DIR       "$STAGING_DIR" "run build.sh first" || exit $?
ci::require_match DEPLOY_USER     "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint  DEPLOY_RETAIN   "$DEPLOY_RETAIN" || exit $?

# CLI mode
./ci-toolkit file  require LATEST_NAME_FILE "$DIST_DIR/.latest-name"
./ci-toolkit dir   require STAGING_DIR      "$STAGING_DIR"
./ci-toolkit match require DEPLOY_USER      "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint  require DEPLOY_RETAIN    "$DEPLOY_RETAIN"
```

| Helper | CLI | Behavior |
| --- | --- | --- |
| `ci::require_file NAME PATH [HINT]` | `file require` | Exit `1` if `PATH` is missing or not a regular file. |
| `ci::require_dir NAME PATH [HINT]` | `dir require` | Exit `1` if `PATH` is missing or not a directory. |
| `ci::require_match NAME VALUE REGEX [DESCRIPTION]` | `match require` | Exit `1` if `VALUE` does not match the Bash extended `REGEX`. |
| `ci::require_uint NAME VALUE` | `uint require` | Exit `1` if `VALUE` is not `^[0-9]+$`. |

Every helper returns `64` on usage error and never echoes the rejected value into stderr.

### Shell argument escaping

`ci::shell_join` (CLI: `shell join`) turns an argv array into a single shell-escaped command string that survives re-parsing by Bash. Useful when an external tool insists on a command string instead of an argv array — `rsync -e` is the canonical example.

```bash
source ./ci-toolkit

SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
rsync -e "$RSYNC_SSH" "$STAGING_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"
```

The output uses Bash's `printf '%q'`, so the escaping is Bash-specific (not POSIX-sh portable). The toolkit already targets Bash 4+, so this is intentional. Do not use the result as input to `eval` on untrusted data.

````

- [ ] **Step 2: Add the same subsections (translated) to `docs/user/zh-TW/index.md`**

Open `docs/user/zh-TW/index.md`. Find the `### 字串述詞` subsection (the zh-TW counterpart of "String predicates" inside `<!-- doc-key: advanced-tools -->`). Insert the following block immediately after that subsection's closing line and **before** the `### 預設 ERR 陷阱` heading:

````markdown
### 驗證輔助函式

四個短小的驗證函式，把腳本裡重複的 guard 區塊收斂成具名契約。失敗時只報「邏輯欄位名稱」，**不會印出 VALUE 或 PATH 的內容**，因此可以安全用於敏感輸入。

```bash
# Source 模式
ci::require_file LATEST_NAME_FILE "$DIST_DIR/.latest-name" "run build.sh first" || exit $?
ci::require_dir  STAGING_DIR       "$STAGING_DIR" "run build.sh first" || exit $?
ci::require_match DEPLOY_USER     "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint  DEPLOY_RETAIN   "$DEPLOY_RETAIN" || exit $?

# CLI 模式
./ci-toolkit file  require LATEST_NAME_FILE "$DIST_DIR/.latest-name"
./ci-toolkit dir   require STAGING_DIR      "$STAGING_DIR"
./ci-toolkit match require DEPLOY_USER      "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint  require DEPLOY_RETAIN    "$DEPLOY_RETAIN"
```

| 輔助函式 | CLI | 行為 |
| --- | --- | --- |
| `ci::require_file NAME PATH [HINT]` | `file require` | `PATH` 不存在或不是檔案時離開碼 `1`。 |
| `ci::require_dir NAME PATH [HINT]` | `dir require` | `PATH` 不存在或不是目錄時離開碼 `1`。 |
| `ci::require_match NAME VALUE REGEX [DESCRIPTION]` | `match require` | `VALUE` 不符 Bash 延伸正則 `REGEX` 時離開碼 `1`。 |
| `ci::require_uint NAME VALUE` | `uint require` | `VALUE` 不是 `^[0-9]+$` 時離開碼 `1`。 |

使用方式錯誤一律回傳 `64`，並且**不會**將被拒絕的值寫入 stderr。

### Shell 參數逃逸

`ci::shell_join`（CLI：`shell join`）把 argv 陣列展開成單一的 shell-escaped 字串，可被 Bash 重新解析。典型用途是把命令字串塞進 `rsync -e` 之類只接受字串、不接受 argv 陣列的旗標。

```bash
source ./ci-toolkit

SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
rsync -e "$RSYNC_SSH" "$STAGING_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"
```

輸出使用 Bash 內建的 `printf '%q'`，所以逃逸結果是 Bash-specific，不保證在 POSIX sh 下可移植。本工具鏈目標就是 Bash 4+，這是有意為之的。**不要**將其結果交給未驗證資料的 `eval`。

````

- [ ] **Step 3: Mirror the new subsections into `docs/user/en/index.html`**

Open `docs/user/en/index.html`. Find `<h3 class="mt-12">String predicates</h3>` (around line 249) and trace forward to find the closing `</p>` that ends the **String predicates** subsection (immediately before `<h3 class="mt-12">Default ERR trap</h3>` around line 279). Insert the following block at that boundary — between the String predicates block's closing `</p>` and the `<h3 class="mt-12">Default ERR trap</h3>` heading. If the surrounding HTML uses a different table class, wrapping `<div>`, or `<pre>` markup, copy the local convention exactly (open the file first and inspect the String predicates block as the template).

```html
            <h3 class="mt-12">Validation helpers</h3>
            <p>Four short helpers that turn repeated guard blocks into named contracts. They all report the <strong>logical name</strong> of the failing field, never the value or path — safe for secrets and avoidable PII.</p>
            <pre><code># Source mode
ci::require_file LATEST_NAME_FILE "$DIST_DIR/.latest-name" "run build.sh first" || exit $?
ci::require_dir  STAGING_DIR       "$STAGING_DIR" "run build.sh first" || exit $?
ci::require_match DEPLOY_USER     "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint  DEPLOY_RETAIN   "$DEPLOY_RETAIN" || exit $?

# CLI mode
./ci-toolkit file  require LATEST_NAME_FILE "$DIST_DIR/.latest-name"
./ci-toolkit dir   require STAGING_DIR      "$STAGING_DIR"
./ci-toolkit match require DEPLOY_USER      "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint  require DEPLOY_RETAIN    "$DEPLOY_RETAIN"</code></pre>
            <table>
              <thead><tr><th>Helper</th><th>CLI</th><th>Behavior</th></tr></thead>
              <tbody>
                <tr><td><code>ci::require_file NAME PATH [HINT]</code></td><td><code>file require</code></td><td>Exit <code>1</code> if <code>PATH</code> is missing or not a regular file.</td></tr>
                <tr><td><code>ci::require_dir NAME PATH [HINT]</code></td><td><code>dir require</code></td><td>Exit <code>1</code> if <code>PATH</code> is missing or not a directory.</td></tr>
                <tr><td><code>ci::require_match NAME VALUE REGEX [DESCRIPTION]</code></td><td><code>match require</code></td><td>Exit <code>1</code> if <code>VALUE</code> does not match the Bash extended <code>REGEX</code>.</td></tr>
                <tr><td><code>ci::require_uint NAME VALUE</code></td><td><code>uint require</code></td><td>Exit <code>1</code> if <code>VALUE</code> is not <code>^[0-9]+$</code>.</td></tr>
              </tbody>
            </table>
            <p>Every helper returns <code>64</code> on usage error and never echoes the rejected value into stderr.</p>

            <h3 class="mt-12">Shell argument escaping</h3>
            <p><code>ci::shell_join</code> (CLI: <code>shell join</code>) turns an argv array into a single shell-escaped command string that survives re-parsing by Bash. Useful when an external tool insists on a command string instead of an argv array — <code>rsync -e</code> is the canonical example.</p>
            <pre><code>source ./ci-toolkit

SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
rsync -e "$RSYNC_SSH" "$STAGING_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"</code></pre>
            <p>The output uses Bash's <code>printf '%q'</code>, so the escaping is Bash-specific (not POSIX-sh portable). The toolkit already targets Bash 4+, so this is intentional. Do not use the result as input to <code>eval</code> on untrusted data.</p>
```

- [ ] **Step 4: Mirror the translated subsections into `docs/user/zh-TW/index.html`**

Open `docs/user/zh-TW/index.html`. Find `<h3 class="mt-12">字串述詞</h3>` and trace forward to the closing `</p>` of that subsection (immediately before the `<h3 class="mt-12">預設 ERR 陷阱</h3>` heading). Insert the following block at that boundary:

```html
            <h3 class="mt-12">驗證輔助函式</h3>
            <p>四個短小的驗證函式，把腳本裡重複的 guard 區塊收斂成具名契約。失敗時只報「邏輯欄位名稱」，<strong>不會印出 VALUE 或 PATH 的內容</strong>，因此可以安全用於敏感輸入。</p>
            <pre><code># Source 模式
ci::require_file LATEST_NAME_FILE "$DIST_DIR/.latest-name" "run build.sh first" || exit $?
ci::require_dir  STAGING_DIR       "$STAGING_DIR" "run build.sh first" || exit $?
ci::require_match DEPLOY_USER     "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint  DEPLOY_RETAIN   "$DEPLOY_RETAIN" || exit $?

# CLI 模式
./ci-toolkit file  require LATEST_NAME_FILE "$DIST_DIR/.latest-name"
./ci-toolkit dir   require STAGING_DIR      "$STAGING_DIR"
./ci-toolkit match require DEPLOY_USER      "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint  require DEPLOY_RETAIN    "$DEPLOY_RETAIN"</code></pre>
            <table>
              <thead><tr><th>輔助函式</th><th>CLI</th><th>行為</th></tr></thead>
              <tbody>
                <tr><td><code>ci::require_file NAME PATH [HINT]</code></td><td><code>file require</code></td><td><code>PATH</code> 不存在或不是檔案時離開碼 <code>1</code>。</td></tr>
                <tr><td><code>ci::require_dir NAME PATH [HINT]</code></td><td><code>dir require</code></td><td><code>PATH</code> 不存在或不是目錄時離開碼 <code>1</code>。</td></tr>
                <tr><td><code>ci::require_match NAME VALUE REGEX [DESCRIPTION]</code></td><td><code>match require</code></td><td><code>VALUE</code> 不符 Bash 延伸正則 <code>REGEX</code> 時離開碼 <code>1</code>。</td></tr>
                <tr><td><code>ci::require_uint NAME VALUE</code></td><td><code>uint require</code></td><td><code>VALUE</code> 不是 <code>^[0-9]+$</code> 時離開碼 <code>1</code>。</td></tr>
              </tbody>
            </table>
            <p>使用方式錯誤一律回傳 <code>64</code>，並且<strong>不會</strong>將被拒絕的值寫入 stderr。</p>

            <h3 class="mt-12">Shell 參數逃逸</h3>
            <p><code>ci::shell_join</code>（CLI：<code>shell join</code>）把 argv 陣列展開成單一的 shell-escaped 字串，可被 Bash 重新解析。典型用途是把命令字串塞進 <code>rsync -e</code> 之類只接受字串、不接受 argv 陣列的旗標。</p>
            <pre><code>source ./ci-toolkit

SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
rsync -e "$RSYNC_SSH" "$STAGING_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"</code></pre>
            <p>輸出使用 Bash 內建的 <code>printf '%q'</code>，所以逃逸結果是 Bash-specific，不保證在 POSIX sh 下可移植。本工具鏈目標就是 Bash 4+，這是有意為之的。<strong>不要</strong>將其結果交給未驗證資料的 <code>eval</code>。</p>
```

- [ ] **Step 5: Run the user-docs parity checker**

Run: `bun run scripts/check-user-docs.ts`

Expected: PASS — the script verifies every required `<!-- doc-key: ... -->` marker exists in both locales and across `.md` + `.html`. This task adds content **inside** an existing `advanced-tools` section without introducing new doc-key markers, so the checker stays green.

If `bun` is not installed locally, skip this step here; it will run again as part of `./scripts/release-check gates` in Task 12.

- [ ] **Step 6: Verify the new subsections are present in every doc file**

Run:

```bash
grep -c 'ci::require_file\|ci::require_dir\|ci::require_match\|ci::require_uint\|ci::shell_join' \
  docs/user/en/index.md docs/user/zh-TW/index.md \
  docs/user/en/index.html docs/user/zh-TW/index.html
```

Expected: each of the four files reports `5` or more (one mention per helper plus code-block usages).

- [ ] **Step 7: Commit**

```bash
git add docs/user/en/index.md docs/user/zh-TW/index.md docs/user/en/index.html docs/user/zh-TW/index.html
git commit -m "docs: [user-docs] Add validation + shell_join helpers in en + zh-TW"
```

---

## Task 9: Update `scripts/smoke` with validation and shell-join checks

**Files:**
- Modify: `scripts/smoke`

- [ ] **Step 1: Read the current smoke script**

Run: `cat scripts/smoke`

Expected: The script currently runs `help`, `version`, source-mode `ci::info`, `strip-prefix`, `version gt`, `eq`, `in`, and `not-in` against the real artifact.

- [ ] **Step 2: Append validation + shell-join smoke checks**

Edit `scripts/smoke`. Insert two lines immediately after the existing `"$ROOT_DIR/ci-toolkit" not-in qa dev staging prod` line and immediately before the final `printf 'Smoke checks passed\n'`:

```bash
"$ROOT_DIR/ci-toolkit" uint require COUNT 5
"$ROOT_DIR/ci-toolkit" shell join ssh -p 22 host | grep -q 'ssh'
```

Each command exits `0` on success; `set -euo pipefail` fails the smoke run on regression. The grep guard sanity-checks that `shell join` emits the expected leading token.

- [ ] **Step 3: Run the smoke script**

Run: `./scripts/smoke`

Expected: `Smoke checks passed`.

- [ ] **Step 4: Commit**

```bash
git add scripts/smoke
git commit -m "test: [smoke] Cover uint require and shell join CLI commands"
```

---

## Task 10: Bump `CI_TOOLKIT_VERSION` to `0.1.9` and add CHANGELOG entry

**Files:**
- Modify: `ci-toolkit` (line 7)
- Modify: `CHANGELOG.md` (prepend a new section above the existing `## v0.1.8` block at line 3)
- Modify: `tests/test_source_and_cli.sh` (line 32 hard-codes `ci-toolkit 0.1.8`)

- [ ] **Step 1: Bump the version constant**

Edit `ci-toolkit`. Change line 7 from:

```bash
CI_TOOLKIT_VERSION="0.1.8"
```

to:

```bash
CI_TOOLKIT_VERSION="0.1.9"
```

- [ ] **Step 2: Prepend the v0.1.9 CHANGELOG entry**

Edit `CHANGELOG.md`. Insert the following block immediately after line 1 (`# Changelog`) and one blank line before the existing `## v0.1.8 - String predicate helpers` section:

```markdown
## v0.1.9 - Validation and shell-join helpers

- Added four public validation helpers: `ci::require_file NAME PATH [HINT]`, `ci::require_dir NAME PATH [HINT]`, `ci::require_match NAME VALUE REGEX [DESCRIPTION]`, and `ci::require_uint NAME VALUE`. All four return `0` on success, `1` on validation failure (stderr names `NAME` and, for `require_match`, the rule description or raw regex), and `64` on usage error. They never echo `VALUE` or `PATH` into stderr, which keeps them safe for sensitive inputs.
- Added `ci::shell_join ARG...` data helper that prints argv as a Bash-escaped command string via `printf '%q'`. Stdout is shell-escaped (Bash-specific, not POSIX-sh portable) and ends in a single trailing newline. Zero args returns `64`. Intended for adapters like `rsync -e` that require a command string instead of an argv array.
- Added matching nested CLI commands `ci-toolkit file require`, `ci-toolkit dir require`, `ci-toolkit match require`, `ci-toolkit uint require`, and `ci-toolkit shell join` as thin wrappers over the source-mode helpers. All preserve source-mode status codes and never leak rejected values.
- Added `tests/test_validation_helpers.sh` covering source mode and CLI mode for all four `require_*` helpers, including no-leak assertions for `require_match` and `require_uint`. Added `tests/test_shell_join.sh` covering source/CLI round-trip of argv containing spaces, quotes, backslashes, glob characters, and empty strings, plus zero-arg usage error. `scripts/smoke` now also runs one `uint require` and one `shell join` check against the real artifact.
```

- [ ] **Step 3: Bump the hard-coded version assertion in the source-and-CLI test**

Edit `tests/test_source_and_cli.sh`. Change line 32 from:

```bash
assert_eq "ci-toolkit 0.1.8" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.8"
```

to:

```bash
assert_eq "ci-toolkit 0.1.9" "${RUN_STDOUT%$'\n'}" "version command prints normalized 0.1.9"
```

- [ ] **Step 4: Verify the version gate**

Run: `./scripts/release-check version`

Expected: `version: ok (0.1.9)`.

Run: `bash tests/test_source_and_cli.sh`

Expected: all `ok - ...` lines, including the bumped `version command prints normalized 0.1.9` line.

- [ ] **Step 5: Commit**

```bash
git add ci-toolkit CHANGELOG.md tests/test_source_and_cli.sh
git commit -m "feat: [release] Bump ci-toolkit to v0.1.9"
```

---

## Task 11: Refresh install-URL pins across README, user docs, and examples

**Files:**
- Modify: `README.md` (lines 25, 30 mention `v0.1.8`)
- Modify: `docs/user/en/index.md`, `docs/user/zh-TW/index.md`, `docs/user/en/index.html`, `docs/user/zh-TW/index.html` (each has one `releases/download/v0.1.8/ci-toolkit` line)
- Modify: `examples/bun-deploy/README.md`, `examples/laravel-bluegreen-deploy/README.md`, `examples/vendored-deploy-script/README.md`, `examples/vendored-deploy-script/deploy-prod.sh` (carry both `releases/download/v0.1.8/ci-toolkit` install URLs and `Vendor Gungnir ci-toolkit v0.1.8` commit-message strings)

`scripts/release-check examples` enforces that every install URL and `Vendor Gungnir ci-toolkit v…` commit-message string under `examples/` matches `CI_TOOLKIT_VERSION`. This task makes the find/replace explicit.

- [ ] **Step 1: List every `v0.1.8` reference to be bumped**

Run:

```bash
grep -rn "v0.1.8" README.md docs/user/ examples/
```

Expected output: roughly a dozen lines spanning `README.md` (2 lines), `docs/user/en/index.md` (1), `docs/user/zh-TW/index.md` (1), `docs/user/en/index.html` (1), `docs/user/zh-TW/index.html` (1), `examples/bun-deploy/README.md` (1), `examples/laravel-bluegreen-deploy/README.md` (2 — install URL + commit-message), `examples/vendored-deploy-script/README.md` (3 — install URLs + commit-message), `examples/vendored-deploy-script/deploy-prod.sh` (1). Record the exact line numbers; every one of them gets bumped to `v0.1.9` in this task.

- [ ] **Step 2: Bump `v0.1.8` → `v0.1.9` in `README.md`**

Edit `README.md`:

- Line 25: `curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.8/ci-toolkit -o ci-toolkit` → replace `v0.1.8` with `v0.1.9`.
- Line 30: `Pin to a tag (`v0.1.8` above).` → replace `v0.1.8` with `v0.1.9`.

- [ ] **Step 3: Bump `v0.1.8` → `v0.1.9` in the four user-doc files**

Edit each of these files and replace `releases/download/v0.1.8/ci-toolkit` with `releases/download/v0.1.9/ci-toolkit` (one occurrence each):

- `docs/user/en/index.md`
- `docs/user/zh-TW/index.md`
- `docs/user/en/index.html`
- `docs/user/zh-TW/index.html`

- [ ] **Step 4: Bump `v0.1.8` → `v0.1.9` in the example files**

Edit each of these files and replace every `v0.1.8` token with `v0.1.9`. This covers both the `releases/download/v0.1.8/ci-toolkit` install URLs and the `Vendor Gungnir ci-toolkit v0.1.8` commit-message strings:

- `examples/bun-deploy/README.md`
- `examples/laravel-bluegreen-deploy/README.md`
- `examples/vendored-deploy-script/README.md`
- `examples/vendored-deploy-script/deploy-prod.sh`

- [ ] **Step 5: Verify nothing references the old version anymore**

Run:

```bash
grep -rn "v0.1.8" README.md docs/user/ examples/
```

Expected: empty output (no lines). If anything remains, replace it.

Then verify the new version is present everywhere it was expected to be:

```bash
grep -rcn "v0.1.9" README.md docs/user/ examples/
```

Expected: each file reports at least `1` (matching the bumped pin); some files may report higher counts.

- [ ] **Step 6: Run the artifact + examples release-checks**

Run: `./scripts/release-check artifact`

Expected: `artifact: ok` (or equivalent success line). It also checks the README install URL matches the version constant.

Run: `./scripts/release-check examples`

Expected: success — the examples scan finds no diverging pin under `examples/`.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/user/ examples/
git commit -m "docs: [release] Bump install URL pins to v0.1.9"
```

---

## Task 12: Final release-readiness gates

**Files:**
- No file edits in this task. Run the full release-check pipeline and the standard local gates.

- [ ] **Step 1: Run the full test suite**

Run: `./scripts/test`

Expected: every `tests/test_*.sh` passes — including the two new files (`test_validation_helpers.sh`, `test_shell_join.sh`) and the bumped version assertion in `test_source_and_cli.sh`. Final aggregate line is `All tests passed` (or equivalent success message).

- [ ] **Step 2: Run ShellCheck lint**

Run: `./scripts/lint`

Expected: PASS — either ShellCheck reports clean, or the script prints the "ShellCheck not installed; skipping" notice with exit `0`. Address any real warnings ShellCheck raises on the five new functions or wrappers.

If ShellCheck flags `[[ "$value" =~ $regex ]]` in `ci::require_match` (SC2076), the **unquoted** RHS is intentional and correct — it's the standard Bash idiom for regex match. Add an inline `# shellcheck disable=SC2076` comment immediately above the line if needed, with a one-line explanation.

- [ ] **Step 3: Run smoke**

Run: `./scripts/smoke`

Expected: `Smoke checks passed`.

- [ ] **Step 4: Run the full release-check pipeline**

Run: `./scripts/release-check all`

Expected: every step in the pipeline (`version`, `artifact`, `boundary`, `descriptions`, `copy-smoke`, `gates`, `examples`) reports success. The `descriptions` step in particular verifies that every public `ci::` function — including the five new helpers — has a `# @description` comment. The `boundary` step verifies no CI-vendor markers (`GITHUB_`, `GITLAB_`, `CIRCLE_`, `BUILDKITE_`, `BITBUCKET_`) and no forbidden dispatch arms (`build|deploy|release|test|lint`); none of the new commands (`file`, `dir`, `match`, `uint`, `shell`) trip either check.

- [ ] **Step 5: Verify discovery output lists the new helpers**

Run: `./ci-toolkit ls`

Expected: the output contains five new lines (sorted alphabetically by `ci::ls`):

```
  ci::require_dir      Require PATH to exist and be a directory. Reports NAME, never PATH.
  ci::require_file     Require PATH to exist and be a regular file. Reports NAME, never PATH.
  ci::require_match    Require VALUE to match the Bash extended regex REGEX. Reports NAME and rule, never VALUE.
  ci::require_uint     Require VALUE to be a non-negative base-10 integer (0 or digits, no sign). Reports NAME, never VALUE.
  ci::shell_join       Print argv as a Bash-escaped command string suitable for re-parsing by Bash (e.g. rsync -e).
```

(Exact spacing depends on the `ci::ls` `printf` width — five rows starting with the listed function names is the contract.)

- [ ] **Step 6: Verify CLI help lists the new commands**

Run: `./ci-toolkit help`

Expected: the printed usage block contains the five new lines:

```
  ci-toolkit file require NAME PATH [HINT]
  ci-toolkit dir require NAME PATH [HINT]
  ci-toolkit match require NAME VALUE REGEX [DESCRIPTION]
  ci-toolkit uint require NAME VALUE
  ci-toolkit shell join ARG...
```

- [ ] **Step 7: No commit required**

Task 12 is a verification pass over commits already made in Tasks 1–11. If any gate fails, fix the underlying issue and add a follow-up commit before tagging.

---

## Summary of commits

By the end of this plan you should have a clean linear history that looks like:

```
feat: [toolkit] Add ci::require_file validation helper
feat: [toolkit] Add ci::require_dir validation helper
feat: [toolkit] Add ci::require_match regex validation helper
feat: [toolkit] Add ci::require_uint validation helper
feat: [toolkit] Add ci::shell_join data helper
feat: [toolkit] Add file/dir/match/uint/shell-join CLI commands
docs: [readme] Document validation and shell_join helpers
docs: [user-docs] Add validation + shell_join helpers in en + zh-TW
test: [smoke] Cover uint require and shell join CLI commands
feat: [release] Bump ci-toolkit to v0.1.9
docs: [release] Bump install URL pins to v0.1.9
```

Each commit is independently testable. The release is ready to tag once `./scripts/release-check all` passes after Task 12.
