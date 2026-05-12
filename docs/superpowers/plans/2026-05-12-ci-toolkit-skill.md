# ci-toolkit Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Claude Code skill from inside the Gungnir repo so AI agents working in any project know how to write or refactor Bash CI / build / deploy scripts using `ci-toolkit`.

**Architecture:** A single `skills/ci-toolkit/SKILL.md` indexes the skill; its body uses relative paths (`../../README.md`, `../../examples/...`) that resolve back into the live Gungnir repo via a symlink installed by `scripts/install-skill`. Two new test files (`tests/test_install_skill.sh`, `tests/test_skill_metadata.sh`) protect the install behavior and the SKILL.md metadata. Function tables and worked diffs stay in the README and examples — not duplicated into the skill.

**Tech Stack:** Bash 4+ (the project's existing runtime), the existing `tests/assert.sh` harness, no new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-12-ci-toolkit-skill-design.md`

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `scripts/install-skill` | Creates `~/.claude/skills/ci-toolkit` symlink to `skills/ci-toolkit/`. Idempotent; refuses to overwrite. |
| `skills/ci-toolkit/SKILL.md` | The skill itself. Frontmatter routes agents in; body sends them to README and examples. |
| `tests/test_install_skill.sh` | Behavior tests for the installer (cases 1–4). |
| `tests/test_skill_metadata.sh` | Static checks against `SKILL.md` (cases 5–6). |

No other files change. `scripts/test` already loops over `tests/test_*.sh`, so the new tests are discovered automatically.

---

## Task 1: Install-skill happy path

**Files:**
- Create: `tests/test_install_skill.sh`
- Create: `scripts/install-skill`
- Create: `skills/ci-toolkit/.keep` (placeholder so `$src` exists; replaced in Task 6)

- [ ] **Step 1: Write the failing test**

Create `tests/test_install_skill.sh` with:

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

# Case 1: Happy path — symlink is created
skills_dir="$(make_temp_dir)"
CLAUDE_SKILLS_DIR="$skills_dir" run_capture "$ROOT_DIR/scripts/install-skill"
assert_status 0 "$RUN_STATUS" "happy path: installer exits 0"
[[ -L "$skills_dir/ci-toolkit" ]] && pass "happy path: destination is a symlink" \
  || fail "happy path: destination is not a symlink"
assert_eq "$ROOT_DIR/skills/ci-toolkit" "$(readlink "$skills_dir/ci-toolkit")" \
  "happy path: symlink target equals skills/ci-toolkit"
assert_contains "$RUN_STDOUT" "linked" "happy path: stdout reports linked"

finish_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install_skill.sh`
Expected: FAIL because `scripts/install-skill` does not exist yet.

- [ ] **Step 3: Create the source placeholder**

The installer guards against a missing `$src`. The real SKILL.md arrives in Task 6, so create an empty placeholder so the directory exists for Task 1:

```bash
mkdir -p skills/ci-toolkit
touch skills/ci-toolkit/.keep
```

- [ ] **Step 4: Write minimal implementation**

Create `scripts/install-skill`:

```bash
#!/usr/bin/env bash

set -euo pipefail

gungnir_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$gungnir_root/skills/ci-toolkit"
dst_dir="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
dst="$dst_dir/ci-toolkit"

# Defensive: src is the script's own sibling so this should always exist.
# Kept as a guard for unusual usage (script copied elsewhere) — not exercised
# by tests in MVP.
if [[ ! -d "$src" ]]; then
  echo "missing $src" >&2
  exit 1
fi

mkdir -p "$dst_dir"
ln -s "$src" "$dst"
echo "linked $dst -> $src"
```

Make it executable:

```bash
chmod +x scripts/install-skill
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_install_skill.sh`
Expected: 4 `ok -` lines, then `All tests passed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/install-skill tests/test_install_skill.sh skills/ci-toolkit/.keep
git commit -m "feat: [skill] Add install-skill happy path"
```

---

## Task 2: Idempotent re-install

**Files:**
- Modify: `tests/test_install_skill.sh` (append case 2)
- Modify: `scripts/install-skill` (add idempotent branch)

- [ ] **Step 1: Write the failing test**

Insert this block in `tests/test_install_skill.sh` *before* the final `finish_tests` line:

```bash
# Case 2: Idempotent — running twice is a no-op
skills_dir2="$(make_temp_dir)"
CLAUDE_SKILLS_DIR="$skills_dir2" "$ROOT_DIR/scripts/install-skill" >/dev/null
CLAUDE_SKILLS_DIR="$skills_dir2" run_capture "$ROOT_DIR/scripts/install-skill"
assert_status 0 "$RUN_STATUS" "idempotent: second run exits 0"
assert_contains "$RUN_STDOUT" "already linked" "idempotent: stdout says already linked"
assert_eq "$ROOT_DIR/skills/ci-toolkit" "$(readlink "$skills_dir2/ci-toolkit")" \
  "idempotent: symlink target unchanged"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install_skill.sh`
Expected: case 1 still passes; case 2 fails because the second `install-skill` call hits `ln -s` against an existing path and aborts under `set -euo pipefail`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/install-skill`, replace the two-line block:

```bash
mkdir -p "$dst_dir"
ln -s "$src" "$dst"
echo "linked $dst -> $src"
```

with:

```bash
mkdir -p "$dst_dir"

if [[ -L "$dst" ]]; then
  current="$(readlink "$dst")"
  if [[ "$current" == "$src" ]]; then
    echo "already linked $dst -> $current"
    exit 0
  fi
fi

ln -s "$src" "$dst"
echo "linked $dst -> $src"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_install_skill.sh`
Expected: 7 `ok -` lines total (4 from case 1 + 3 from case 2), then `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_install_skill.sh scripts/install-skill
git commit -m "feat: [skill] Make install-skill idempotent"
```

---

## Task 3: Refuse to overwrite a regular file

**Files:**
- Modify: `tests/test_install_skill.sh` (append case 3)
- Modify: `scripts/install-skill` (add non-symlink guard)

- [ ] **Step 1: Write the failing test**

Insert this block in `tests/test_install_skill.sh` before `finish_tests`:

```bash
# Case 3: Refuses to overwrite a regular file at the destination
skills_dir3="$(make_temp_dir)"
printf 'unrelated content\n' >"$skills_dir3/ci-toolkit"
original_content="$(cat "$skills_dir3/ci-toolkit")"
CLAUDE_SKILLS_DIR="$skills_dir3" run_capture "$ROOT_DIR/scripts/install-skill"
[[ "$RUN_STATUS" -ne 0 ]] && pass "regular-file conflict: non-zero exit" \
  || fail "regular-file conflict: expected non-zero exit, got 0"
assert_contains "$RUN_STDERR" "aborting" "regular-file conflict: stderr mentions aborting"
assert_eq "$original_content" "$(cat "$skills_dir3/ci-toolkit")" \
  "regular-file conflict: existing file untouched"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install_skill.sh`
Expected: previous cases pass; case 3 fails because `ln -s` against an existing regular file is a hard error from `set -e`, but the message does not include `aborting`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/install-skill`, insert this block *between* the `if [[ -L "$dst" ]]` block and the final `ln -s "$src" "$dst"`:

```bash
if [[ -e "$dst" ]]; then
  echo "non-symlink path at $dst; aborting" >&2
  exit 1
fi
```

The full conflict-handling section now reads:

```bash
if [[ -L "$dst" ]]; then
  current="$(readlink "$dst")"
  if [[ "$current" == "$src" ]]; then
    echo "already linked $dst -> $current"
    exit 0
  fi
fi

if [[ -e "$dst" ]]; then
  echo "non-symlink path at $dst; aborting" >&2
  exit 1
fi

ln -s "$src" "$dst"
echo "linked $dst -> $src"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_install_skill.sh`
Expected: 10 `ok -` lines, then `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_install_skill.sh scripts/install-skill
git commit -m "feat: [skill] install-skill refuses to overwrite regular file"
```

---

## Task 4: Refuse to overwrite a different symlink

**Files:**
- Modify: `tests/test_install_skill.sh` (append case 4)
- Modify: `scripts/install-skill` (handle wrong-target symlink branch)

- [ ] **Step 1: Write the failing test**

Insert this block in `tests/test_install_skill.sh` before `finish_tests`:

```bash
# Case 4: Refuses to overwrite a symlink pointing elsewhere
skills_dir4="$(make_temp_dir)"
other_target="$(make_temp_dir)"
ln -s "$other_target" "$skills_dir4/ci-toolkit"
CLAUDE_SKILLS_DIR="$skills_dir4" run_capture "$ROOT_DIR/scripts/install-skill"
[[ "$RUN_STATUS" -ne 0 ]] && pass "wrong-symlink conflict: non-zero exit" \
  || fail "wrong-symlink conflict: expected non-zero exit, got 0"
assert_contains "$RUN_STDERR" "different symlink exists" \
  "wrong-symlink conflict: stderr mentions different symlink"
assert_eq "$other_target" "$(readlink "$skills_dir4/ci-toolkit")" \
  "wrong-symlink conflict: original symlink unchanged"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install_skill.sh`
Expected: case 4 fails because after the existing `if [[ -L "$dst" ]]` block falls through (target mismatch), `ln -s` errors out with `set -e` but the message does not include `different symlink exists`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/install-skill`, update the symlink branch from:

```bash
if [[ -L "$dst" ]]; then
  current="$(readlink "$dst")"
  if [[ "$current" == "$src" ]]; then
    echo "already linked $dst -> $current"
    exit 0
  fi
fi
```

to:

```bash
if [[ -L "$dst" ]]; then
  current="$(readlink "$dst")"
  if [[ "$current" == "$src" ]]; then
    echo "already linked $dst -> $current"
    exit 0
  fi
  echo "different symlink exists at $dst -> $current; aborting" >&2
  exit 1
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_install_skill.sh`
Expected: 13 `ok -` lines, then `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_install_skill.sh scripts/install-skill
git commit -m "feat: [skill] install-skill refuses to overwrite different symlink"
```

---

## Task 5: SKILL.md metadata tests (red)

**Files:**
- Create: `tests/test_skill_metadata.sh`

These tests will fail because `skills/ci-toolkit/SKILL.md` does not exist yet (only the `.keep` placeholder from Task 1). Task 6 creates SKILL.md and makes them pass.

- [ ] **Step 1: Write the failing test**

Create `tests/test_skill_metadata.sh`:

```bash
#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/assert.sh
source "$ROOT_DIR/tests/assert.sh"

set -e

SKILL_DIR="$ROOT_DIR/skills/ci-toolkit"
SKILL_FILE="$SKILL_DIR/SKILL.md"

if [[ ! -f "$SKILL_FILE" ]]; then
  fail "SKILL.md missing at $SKILL_FILE"
  finish_tests
  exit 1
fi
pass "SKILL.md exists"

# Case 5: every ../../-prefixed path in SKILL.md resolves on disk
seen_paths=0
while IFS= read -r rel_path; do
  seen_paths=$((seen_paths + 1))
  full="$SKILL_DIR/$rel_path"
  if [[ -e "$full" ]]; then
    pass "relative path resolves: $rel_path"
  else
    fail "relative path missing: $rel_path (looked at $full)"
  fi
done < <(grep -oE '\.\./\.\./[A-Za-z0-9._/-]+' "$SKILL_FILE" | sort -u)

if [[ "$seen_paths" -gt 0 ]]; then
  pass "SKILL.md contains at least one ../../ reference"
else
  fail "SKILL.md contains no ../../ references — body has no pointers to README/examples"
fi

# Case 6: description: line in frontmatter contains a trigger keyword
description_line="$(grep -E '^description:' "$SKILL_FILE" || true)"
if [[ -n "$description_line" ]]; then
  pass "description: line present in frontmatter"
else
  fail "description: line missing from frontmatter"
fi

keyword_hit=""
for kw in CI deploy build refactor; do
  if [[ "$description_line" == *"$kw"* ]]; then
    keyword_hit="$kw"
    break
  fi
done
if [[ -n "$keyword_hit" ]]; then
  pass "description contains trigger keyword ($keyword_hit)"
else
  fail "description missing all keywords (CI/deploy/build/refactor): $description_line"
fi

finish_tests
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_skill_metadata.sh`
Expected: FAIL with `SKILL.md missing at .../skills/ci-toolkit/SKILL.md`, exit 1.

- [ ] **Step 3: Commit the failing test**

Commit the test before the content so the TDD red→green cycle is preserved in git history:

```bash
git add tests/test_skill_metadata.sh
git commit -m "test: [skill] Add SKILL.md metadata static checks (red)"
```

---

## Task 6: Write SKILL.md and replace the placeholder (green)

**Files:**
- Delete: `skills/ci-toolkit/.keep`
- Create: `skills/ci-toolkit/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Create `skills/ci-toolkit/SKILL.md` with the following exact content:

````markdown
---
name: ci-toolkit
description: Use when writing, refactoring, reviewing, or troubleshooting Bash CI / build / deploy scripts in any project. Provides the Gungnir ci-toolkit (ci::info, ci::retry, ci::require_env, ci::find_up, ci::root, ...) integration playbook with two modes — vendored copy or curl-pinned URL — and points to canonical examples for new scripts and refactors.
---

# ci-toolkit

## When this skill applies

- The user is adding a new `build`, `deploy`, `release`, or other CI shell script to a project.
- The user is refactoring an existing `.sh` whose code shows duplicated boilerplate: hand-rolled `echo` log prefixes, `if [[ -z "$X" ]]` env validation, ad-hoc retry loops, or repeated `cd "$(dirname ...)"` repo-root walks.
- The user is reviewing a CI script and asking how to make it more robust or consistent.
- Any task that touches Bash automation under `scripts/`, `ci/`, `.github/`, or similar — and is not platform-specific yaml.

## Decision: vendor or URL

| Mode | When to use | How |
|------|-------------|-----|
| **Vendored** | Production CI scripts. You want a reproducible build that never fetches code from the network. | Copy `ci-toolkit` into the consumer repo (e.g. `infra/ci/ci-toolkit`); pin the version with a comment. |
| **URL** | Local dev scripts, throwaway prototypes, or CI where outbound network is fine and a stable pinned tag exists. | `curl -fsSL https://example/ci-toolkit -o ci-toolkit` early in the script, then `chmod +x` and `source`. Always pin to a tag, never `main`. |

Default to **vendored** for anything that runs in CI. Use URL only when the script is genuinely ephemeral.

## Two scenarios

### Writing a new script

1. Read the function table in `../../README.md` (the "Library functions" section) so you know what `ci::*` helpers exist.
2. Use `../../examples/bun-deploy/scripts/` as the canonical skeleton — `check`, `build`, `deploy`, `release` are minimal scripts that demonstrate the source-mode pattern.
3. Decide vendor vs URL using the table above and reflect it in how the script obtains `ci-toolkit`.
4. Output the minimal viable set of scripts (`check`, `build`, `deploy` only — `release` is optional). Do not introduce other abstractions. Do not invent CI-specific variable names.

### Refactoring an existing script

1. Grep the script for duplication signals:
   - hand-written log prefixes (`echo "[INFO] ..."`, `printf '[deploy] %s\n' ...`)
   - guard blocks like `if [[ -z "$X" ]]; then echo "X required"; exit 1; fi`
   - curl / fetch / network calls without retry
   - `cd "$(dirname "${BASH_SOURCE[0]}")/.."` style repo-root discovery
2. Use `../../examples/vendored-deploy-script/deploy-prod.sh` as the reference pattern — it shows the before/after for a real production deploy script.
3. Prefer vendored mode for refactors: copy `ci-toolkit` into the consumer repo and pin the version with a comment, so the refactor is fully reproducible.
4. Replace duplication only. Do not rewrite business logic, re-order steps, or restructure the script. The refactor is mechanical: the script does the same thing, with fewer hand-rolled helpers.

## Invariants

These hold for any script that sources or invokes `ci-toolkit`:

- **Platform-neutral.** No `GITHUB_ACTIONS`, `GITLAB_CI`, `CIRCLECI`, or other CI-vendor variable names. The script must work locally and in any CI.
- **No secret leakage.** Validation helpers report variable *names* only — never values. Do not `echo "$SECRET"` for debugging.
- **Stderr for logs, stdout for data.** Every `ci::log` family helper writes to stderr. Anything that returns a path (e.g. `ci::find_up`) writes the path to stdout.
- **Library functions return; they do not `exit`.** When sourced, `ci-toolkit` must not kill the caller's shell. Use `return 1`, never `exit 1`, from `ci::*` helpers.

## Reference paths

- Function table and integration overview: `../../README.md`
- Worked example for a new script: `../../examples/bun-deploy/`
- Worked example for a refactor: `../../examples/vendored-deploy-script/`
- Library source (read when in doubt about a helper's behavior): `../../ci-toolkit`
````

- [ ] **Step 2: Remove the placeholder**

```bash
rm skills/ci-toolkit/.keep
```

- [ ] **Step 3: Run the metadata test to verify it now passes**

Run: `bash tests/test_skill_metadata.sh`
Expected: every check passes — SKILL.md present, every `../../` path resolves (README.md, examples/bun-deploy/, examples/bun-deploy/scripts/, examples/vendored-deploy-script/, examples/vendored-deploy-script/deploy-prod.sh, ci-toolkit), description line present, keyword (`CI`) detected. Then `All tests passed`.

- [ ] **Step 4: Run the full test suite to confirm nothing else regressed**

Run: `./scripts/test`
Expected: every `tests/test_*.sh` reports `All tests passed`. No failures across the whole suite.

- [ ] **Step 5: Commit**

```bash
git add skills/ci-toolkit/SKILL.md
git rm skills/ci-toolkit/.keep
git commit -m "feat: [skill] Add ci-toolkit SKILL.md (green)"
```

---

## Task 7: Document install-skill in the README

**Files:**
- Modify: `README.md`

The README currently documents the toolkit but not the skill. Add a short section so users discover `scripts/install-skill`.

- [ ] **Step 1: Find the right place to insert**

Run: `grep -n '^## ' README.md`

Identify the section that talks about local development / setup / examples. Insert the new section after the existing "Examples" section, before any "License" / footer section. The exact heading depends on current README layout — keep it consistent with sibling headings.

- [ ] **Step 2: Add the section**

Insert this section (adjust heading level to match siblings):

```markdown
## Use with Claude Code

Gungnir ships a Claude Code skill (`skills/ci-toolkit/`) so AI coding agents
recognize when to reach for `ci-toolkit` while writing or refactoring CI / build
/ deploy scripts.

Install it once on your machine:

    scripts/install-skill

This creates a symlink at `~/.claude/skills/ci-toolkit`. Upgrade by `git pull`
on the Gungnir clone — the skill content is read live through the symlink.

To install into a non-default skills directory, set `CLAUDE_SKILLS_DIR`:

    CLAUDE_SKILLS_DIR=/custom/path scripts/install-skill

The installer is idempotent and refuses to overwrite an existing file or
mismatching symlink at the destination.
```

- [ ] **Step 3: Run the full suite once more**

Run: `./scripts/test`
Expected: still green. README change does not affect tests but confirms nothing was edited by accident.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: [readme] Document scripts/install-skill"
```

---

## Manual acceptance (record outcome in PR description; not gated by CI)

These are the spec's manual acceptance items. Run after Task 7 is committed.

1. From a clean shell, run `scripts/install-skill`. Verify `~/.claude/skills/ci-toolkit` is a symlink pointing into the Gungnir repo.
2. In a separate project (e.g. `~/Dev/CMG/arcade-report`), open Claude Code and ask: *"幫我寫一個 bun build 腳本"*. Confirm Claude routes through the `ci-toolkit` skill — it should reference `README.md` and the `bun-deploy` example before producing scripts.
3. In the same project, open an existing `deploy.sh` and ask: *"幫我重構這個 deploy.sh"*. Confirm Claude routes through the `ci-toolkit` skill and references the `vendored-deploy-script` example.

If steps 2 or 3 fail to route, check:
- `~/.claude/skills/ci-toolkit/SKILL.md` resolves (symlink not dangling).
- `description:` in the SKILL.md contains a trigger keyword (already enforced by `tests/test_skill_metadata.sh`).
- Claude's skill list when starting a session includes `ci-toolkit`.
