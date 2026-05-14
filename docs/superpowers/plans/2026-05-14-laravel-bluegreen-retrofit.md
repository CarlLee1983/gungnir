# Laravel Blue-Green Deploy Retrofit Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an advanced retrofit case study under `examples/laravel-bluegreen-deploy/` that shows how the StationHub Laravel multi-host blue/green deploy script reads after `ci-toolkit` is sourced — paired with a README that links every change back to the spec's substitution table and §5 API proposals.

**Architecture:** One self-contained example directory (`deploy-prod.sh` + `README.md` + `ci-toolkit` symlink). The retrofit script preserves all domain logic (blue/green flipping, multi-host SSH heredoc, CloudWatch naming) inside named local functions while delegating logging/env/tool/retry/git-tag/Slack-transport primitives to `ci::*`. Four temporary local helpers (`compose_err_trap`, `strip_tag_prefix`, `compare_versions_or_exit`, plus the inline composer retry) carry `# proposed: ci::xxx (see spec §5.X, plan TBD)` annotations that point readers at the four follow-up API proposals. ci-toolkit itself, `CHANGELOG.md`, and the two existing examples are not touched.

**Tech Stack:** Bash 4+ (project runtime), `ci-toolkit` (sourced, not modified), ShellCheck for static lint, `bash -n` for syntax verification. No new test files — the script is a code reference, not an executable.

**Spec:** `docs/superpowers/specs/2026-05-14-laravel-bluegreen-retrofit-design.md`

**Source script being retrofitted:** `/Users/carl/Dev/CMG/StationHub/scripts/deploy/shared/deploy-script.sh` (read-only reference; line numbers in this plan refer to that file unless stated otherwise).

---

## Verification model (read first — this plan is NOT TDD)

The example is **deliberately not executable** end-to-end (spec §2 Non-goals; spec §7). There is no SSH host, no `TARGET_HOSTS` associative array, no live Slack webhook. Therefore this plan does NOT introduce `tests/test_*.sh` files and does NOT follow the RED/GREEN cycle.

Instead, every task verifies via three static checks:

1. **Syntax** — `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh` must exit 0 after each step that touches the script. Run this religiously; a missing `}` or unterminated heredoc only surfaces here.
2. **Spec coverage** — for each task that implements a row of spec §4.1 or a function from spec §4.2, run a targeted `grep` to confirm the expected token is present. The exact grep commands are in each task.
3. **Lint** — final task runs `./scripts/lint` (ShellCheck if installed). Any disable directive must have a reason comment.

`bash -n` works on partial scripts as long as every block we add is itself well-formed, so order between tasks is flexible. Each task is designed to leave the script in a `bash -n`-clean state.

---

## File Structure

| Path | Responsibility |
|------|----------------|
| `examples/laravel-bluegreen-deploy/ci-toolkit` | Symlink → `../../ci-toolkit`. Matches existing examples; lets `source "$SCRIPT_DIR/ci-toolkit"` resolve. |
| `examples/laravel-bluegreen-deploy/deploy-prod.sh` | The retrofit. Sources `ci-toolkit`, organizes the original 326-line script into named local functions plus a `main()`. Preserves domain logic verbatim; replaces logging/env/tool/retry/git/Slack-transport primitives with `ci::*`. |
| `examples/laravel-bluegreen-deploy/README.md` | Reader-facing comparison table (mirrors spec §4.1), retained-local-function rationale (mirrors spec §4.2), adoption steps, environment-variable index, and pointer to the not-collected appendix (spec §6). |

No other files in the repo change. In particular:
- `ci-toolkit` and its tests are untouched.
- `CHANGELOG.md` is untouched.
- `examples/bun-deploy/` and `examples/vendored-deploy-script/` are untouched.

---

## Function inventory for `deploy-prod.sh`

After all tasks land, `deploy-prod.sh` defines the following functions in this order. Each entry is annotated with the task that introduces it.

| Function | Origin | Annotation in source | Introduced by |
|----------|--------|----------------------|---------------|
| `parse_cli` | Local — CLI flag policy (spec §6.1 not-collected) | none | Task 3 |
| `send_slack_notification` | Local — message-template policy (spec §6.2 not-collected) | uses `ci::slack_webhook` for transport | Task 4 |
| `compose_err_trap` | Local — temporary; replaced after §5.4 lands | `# proposed: ci::trap_err CALLBACK (see spec §5.4, plan TBD)` | Task 5 |
| `strip_tag_prefix` | Local — temporary; replaced after §5.3 lands | `# proposed: ci::strip_prefix VALUE PREFIX (see spec §5.3, plan TBD)` | Task 6 |
| `compare_versions_or_exit` | Local — temporary; replaced after §5.2 lands | `# proposed: ci::version_gt A B (see spec §5.2, plan TBD)` | Task 6 |
| `resolve_target_tag` | Local — wraps git-fetch + version compare | uses `ci::retry`, `ci::git_latest_tag` | Task 7 |
| `run_composer_install` | Local — composer retry-with-delay (spec L132-136) | inline `# proposed: ci::retry --delay (see spec §5.1, plan TBD)` | Task 8 |
| `run_npm_build` | Local — npm i + build (preserved verbatim) | uses `ci::require_tool` | Task 8 |
| `parse_blue_green_target_dir` | Local — blue/green policy (spec §6.7 not-collected) | none | Task 9 |
| `deploy_files_to_host` | Local — rsync + storage-aware exclude (spec §6.8 not-collected) | none | Task 10 |
| `sanitize_cloudwatch_token` | Local — CloudWatch naming policy (spec §6.3) | none | Task 11 |
| `compute_cloudwatch_log_group` | Local — CloudWatch printf assembly (spec §6.4) | none | Task 11 |
| `run_post_deploy_on_host` | Local — SSH heredoc (spec §6.5 not-collected) | none | Task 12 |
| `run_multi_host_deploy` | Local — multi-host iteration (spec §6.6 not-collected) | calls the four host-level helpers above | Task 12 |
| `run_cloudwatch_setup` | Local — log-group creation wrapper, with `[[ -f ]]` guard around `source` | uses `ci::warn` | Task 13 |
| `main` | Pipeline wiring | calls every `ci::*` and local helper in order | Task 14 |

---

## Task 1: Scaffold directory, symlink, and skeleton script

**Files:**
- Create: `examples/laravel-bluegreen-deploy/`
- Create: `examples/laravel-bluegreen-deploy/ci-toolkit` (symlink → `../../ci-toolkit`)
- Create: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (executable, skeleton)

- [ ] **Step 1: Create the directory and symlink**

Run from the repo root:

```bash
mkdir -p examples/laravel-bluegreen-deploy
ln -s ../../ci-toolkit examples/laravel-bluegreen-deploy/ci-toolkit
```

Verify the symlink resolves:

```bash
ls -l examples/laravel-bluegreen-deploy/ci-toolkit
test -e examples/laravel-bluegreen-deploy/ci-toolkit && echo OK
```

Expected: `ci-toolkit -> ../../ci-toolkit` and `OK`.

- [ ] **Step 2: Write the skeleton script**

Create `examples/laravel-bluegreen-deploy/deploy-prod.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# deploy-prod.sh — advanced retrofit case study for Gungnir ci-toolkit.
#
# Mirrors a real StationHub-style Laravel deploy script:
#   parse CLI flags → resolve target tag → composer + npm build →
#   for each host: blue/green flip + rsync + SSH heredoc post-deploy →
#   optional CloudWatch log-group creation → Slack notification.
#
# THIS IS A CODE REFERENCE, NOT AN EXECUTABLE EXAMPLE.
# It will fail at runtime without an outer wrapper that supplies
# TARGET_HOSTS / BEFORE_COMMANDS / MIDDLE_COMMANDS / CLOUDWATCH_HOST_CONFIGS
# associative arrays plus PROJECT_DIR, GIT_BRANCH, SSH key, and Slack webhook.
#
# See README.md for the substitution table and adoption steps.

set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./ci-toolkit
source "$SCRIPT_DIR/ci-toolkit"

# === Configuration & CLI state (filled in by later tasks) ===

# === Local functions (filled in by later tasks) ===

# === Pipeline ===
main() {
    :
}

main "$@"
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x examples/laravel-bluegreen-deploy/deploy-prod.sh
```

- [ ] **Step 4: Verify the skeleton parses**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0, no output.

Also confirm sourcing the toolkit works in isolation:

```bash
bash -c 'source examples/laravel-bluegreen-deploy/ci-toolkit && ci::info hello'
```

Expected: `[info] hello` on stderr, exit 0.

- [ ] **Step 5: Commit**

```bash
git add examples/laravel-bluegreen-deploy/
git commit -m "chore: [examples] Scaffold laravel-bluegreen-deploy"
```

---

## Task 2: Configuration defaults and CLI state

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (replace the `# === Configuration & CLI state ===` placeholder)

- [ ] **Step 1: Replace the configuration placeholder**

Use Edit to replace the line `# === Configuration & CLI state (filled in by later tasks) ===` (and the blank line immediately after it) with:

```bash
# === Configuration & CLI state ===

# Tag-prefix policy (StationHub default: "release/"; override via env).
ci::env_default TAG_PREFIX "release/"

# Blue/green directory layout on the remote host.
# shellcheck disable=SC2088
# Reason: preserved verbatim from the original script; the tilde is
# expanded at the `ssh -i "$SSH_KEY"` call site by the remote shell.
SSH_KEY="${SSH_KEY:-~/.ssh/sw-ssh-key.pem}"
DEPLOY_DIR="${DEPLOY_DIR:-/var/www}"
BLUE_DIR="${DEPLOY_DIR}/site_blue"
GREEN_DIR="${DEPLOY_DIR}/site_green"
SITE_DIR="${DEPLOY_DIR}/site"

# CLI flag state — populated by parse_cli (see Task 3).
SKIP_VERSION_CHECK=false
SPECIFIED_TAG=""
ENABLE_CLOUDWATCH=false

# Mutable pipeline state — set by resolve_target_tag (Task 7) and the
# multi-host loop (Task 12); read by send_slack_notification at the end
# of main() (Task 14).
CURRENT_TAG=""
LATEST_TAG=""
NOTIFY_MESSAGE=""
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify spec coverage**

Run:

```bash
grep -F 'ci::env_default TAG_PREFIX "release/"' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match (covers spec §4.1 row "L11 TAG_PREFIX default").

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add laravel-bluegreen config defaults and CLI state"
```

---

## Task 3: `parse_cli` — CLI flag parser (local)

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (insert under `# === Local functions ===`)

Rationale: CLI flag parsing is application policy; spec §6.1 marks it not-collected. The function shape mirrors the original L18-38 `while/case` block; the only change is replacing `echo "未知的參數..."; exit 1` with `ci::die ... || exit 1` (spec §4.1 row "L33-35").

- [ ] **Step 1: Replace the placeholder line**

Use Edit to replace `# === Local functions (filled in by later tasks) ===` with:

```bash
# === Local functions ===

# parse_cli — local CLI flag parsing (spec §6.1 not-collected).
# Sets SKIP_VERSION_CHECK / SPECIFIED_TAG / ENABLE_CLOUDWATCH module-level
# variables; intentionally not delegated to ci-toolkit (the toolkit does not
# parse argv — that is application policy).
parse_cli() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip)
                SKIP_VERSION_CHECK=true
                shift
                ;;
            --tag=*)
                SPECIFIED_TAG="${1#*=}"
                shift
                ;;
            --cloudwatch)
                ENABLE_CLOUDWATCH=true
                shift
                ;;
            -h|--help)
                cat <<'USAGE'
Usage: deploy-prod.sh [--skip] [--tag=<tag_name>] [--cloudwatch]

  --skip          Skip the "new tag must be greater than current" check.
  --tag=<name>    Deploy a specific tag instead of the latest matching one.
  --cloudwatch    Also create CloudWatch log groups after deploy.
USAGE
                exit 0
                ;;
            *)
                ci::die "unknown arg: $1 (try --help)" || exit 1
                ;;
        esac
    done
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify spec coverage**

Run:

```bash
grep -F 'ci::die "unknown arg' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match (covers spec §4.1 row "L33-35 未知參數").

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add parse_cli for laravel-bluegreen retrofit"
```

---

## Task 4: `send_slack_notification` — Slack template (local)

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `parse_cli`)

Rationale: The multi-line emoji-prefixed Slack template is project policy (spec §6.2 not-collected). The retrofit keeps the template verbatim but routes the actual HTTP call through `ci::slack_webhook`, which adds the toolkit's standard 3-retry + connect/max-time guards (spec §4.1 row "L43-46"). The version-diff `git log` block is preserved exactly — version comparison there uses `sort -V` directly because §5.2's `ci::version_gt` is still proposed, not implemented.

- [ ] **Step 1: Append the function**

Use Edit. Find the closing `}` of `parse_cli` (the one right before the second blank line) and insert AFTER that closing `}`:

```bash

# send_slack_notification — local message template (spec §6.2 not-collected).
# Builds the StationHub Slack template (emoji + git log diff + env/version/time)
# and delegates the HTTP POST + retry policy to ci::slack_webhook.
#
# Usage: send_slack_notification STATUS MESSAGE
#   STATUS  — "success" or anything else (treated as failure).
#   MESSAGE — single string; may contain literal \n that Slack renders.
send_slack_notification() {
    local status="$1"
    local notify_message="$2"
    local message=""
    local gitlogs=""
    local current_version new_version

    if [[ "$status" == "success" ]]; then
        message+="🚀 部署完成通知\n"
        message+="${notify_message}\n\n"

        if [[ -n "$CURRENT_TAG" && -n "$LATEST_TAG" ]]; then
            current_version=$(strip_tag_prefix "$CURRENT_TAG" "$TAG_PREFIX")
            new_version=$(strip_tag_prefix "$LATEST_TAG" "$TAG_PREFIX")

            # Direct sort -V here — ci::version_gt is still a §5.2 proposal.
            if [[ "$(printf '%s\n' "$current_version" "$new_version" | sort -V | head -n1)" != "$new_version" ]]; then
                message+="版本更新紀錄:\n"
                gitlogs=$(git log "${CURRENT_TAG}..${LATEST_TAG}" --format="%h %<(100,trunc)%s" 2>/dev/null || true)
                if [[ -n "$gitlogs" ]]; then
                    message+="${gitlogs}\n\n"
                else
                    message+="無更新紀錄\n\n"
                fi
            fi
        fi
    else
        message+="❌ 部署失敗通知\n"
        message+="錯誤訊息: ${notify_message}\n\n"
    fi

    message+="環境: ${DEPLOY_ENV:-unset}\n"
    message+="版本: ${LATEST_TAG}\n"
    message+="時間: $(date '+%Y-%m-%d %H:%M:%S')"

    # ci::slack_webhook handles missing-webhook + missing-curl gracefully
    # (warns and returns 0) and retries the POST 3x on transient failure.
    ci::slack_webhook SLACK_WEBHOOK_URL "laravel-bluegreen" "$status" "$message"
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify spec coverage**

Run:

```bash
grep -F 'ci::slack_webhook SLACK_WEBHOOK_URL' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match (covers spec §4.1 row "L43-46 SLACK_WEBHOOK_URL" + row "L325 success notification").

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add send_slack_notification with ci::slack_webhook transport"
```

---

## Task 5: `compose_err_trap` — ERR trap helper (temporary, points at §5.4)

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `send_slack_notification`)

Rationale: Spec §4.1 row "L89 trap" calls for a local helper carrying `# proposed: ci::trap_err`. The helper is one line, but the annotation is the point — it tells readers exactly where the proposal lives.

- [ ] **Step 1: Append the function**

Use Edit. After the closing `}` of `send_slack_notification`, insert:

```bash

# proposed: ci::trap_err CALLBACK (see spec §5.4, plan TBD)
# After §5.4 lands, replace this whole function with `ci::trap_err "$1"`.
compose_err_trap() {
    local callback="${1:-}"
    if [[ -z "$callback" ]]; then
        ci::die "compose_err_trap: callback is required" || exit 1
    fi
    set -E
    # shellcheck disable=SC2064
    # Reason: callback string is intentionally expanded eagerly here for the
    # case-study; the §5.4 proposal will switch to lazy expansion of $LINENO.
    trap "$callback" ERR
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify annotation is exact and discoverable**

Run:

```bash
grep -F '# proposed: ci::trap_err CALLBACK (see spec §5.4, plan TBD)' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match.

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add compose_err_trap with ci::trap_err proposal annotation"
```

---

## Task 6: `strip_tag_prefix` + `compare_versions_or_exit` (temporary, point at §5.3 / §5.2)

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `compose_err_trap`)

Rationale: Two more "remove once the proposal lands" helpers. Both are pure-bash and one-liner-equivalent — the helpers exist only so the call sites read identically to how they'd read once `ci::strip_prefix` / `ci::version_gt` ship.

- [ ] **Step 1: Append both functions**

Use Edit. After the closing `}` of `compose_err_trap`, insert:

```bash

# proposed: ci::strip_prefix VALUE PREFIX (see spec §5.3, plan TBD)
# After §5.3 lands, replace call sites with `ci::strip_prefix "$value" "$prefix"`
# and delete this function.
strip_tag_prefix() {
    local value="${1:-}"
    local prefix="${2:-}"
    printf '%s\n' "${value#"$prefix"}"
}

# proposed: ci::version_gt A B (see spec §5.2, plan TBD)
# After §5.2 lands, replace this whole function with:
#     ci::version_gt "$new_version" "$current_version" || {
#         ci::die "New version ($LATEST_TAG) is not greater..." || exit 1
#     }
# and delete this function.
compare_versions_or_exit() {
    local new_version="${1:-}"
    local current_version="${2:-}"
    if [[ "$(printf '%s\n' "$new_version" "$current_version" | sort -V | head -n1)" == "$new_version" ]]; then
        ci::error "New version ($LATEST_TAG) is not greater than current version ($CURRENT_TAG)"
        ci::die "Deployment aborted!" || exit 1
    fi
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify both annotations are exact**

Run:

```bash
grep -F '# proposed: ci::strip_prefix VALUE PREFIX (see spec §5.3, plan TBD)' examples/laravel-bluegreen-deploy/deploy-prod.sh
grep -F '# proposed: ci::version_gt A B (see spec §5.2, plan TBD)' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match each.

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add strip_tag_prefix and compare_versions_or_exit proposals"
```

---

## Task 7: `resolve_target_tag` — version resolution block

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `compare_versions_or_exit`)

Rationale: Mirrors original L94-121. The retrofit:
- Wraps `git fetch origin`, `git fetch --tags`, `git pull origin $GIT_BRANCH` each in `ci::retry 3` (spec §4.1 row "L102-104").
- Replaces the bare `git tag -l ... | sort -V | tail -n1` pipeline with `ci::git_latest_tag "$TAG_PREFIX"` (spec §4.1 row "L107").
- Uses `strip_tag_prefix` + `compare_versions_or_exit` from Task 6 instead of inlining (spec §4.1 rows L111-112, L115-119).
- Keeps `git describe --tags --abbrev=0` for `CURRENT_TAG` because that returns "the tag at HEAD", not "the latest matching tag" — different semantics (spec §4.1 row "L99 git describe — 保留").

Result variables (`CURRENT_TAG`, `LATEST_TAG`) are set on the module-level vars declared in Task 2.

- [ ] **Step 1: Append the function**

Use Edit. After the closing `}` of `compare_versions_or_exit`, insert:

```bash

# resolve_target_tag — sets CURRENT_TAG and LATEST_TAG (module-level).
# Mirrors the original L94-121 version-resolution block.
resolve_target_tag() {
    if [[ -n "$SPECIFIED_TAG" ]]; then
        LATEST_TAG="$SPECIFIED_TAG"
        return 0
    fi

    CURRENT_TAG=$(git describe --tags --abbrev=0)

    ci::retry 3 git fetch origin
    ci::retry 3 git fetch --tags

    ci::require_env GIT_BRANCH || exit 1
    ci::retry 3 git pull origin "$GIT_BRANCH"

    LATEST_TAG=$(ci::git_latest_tag "$TAG_PREFIX") || exit 1

    if [[ "$SKIP_VERSION_CHECK" == "false" ]]; then
        local current_version new_version
        current_version=$(strip_tag_prefix "$CURRENT_TAG" "$TAG_PREFIX")
        new_version=$(strip_tag_prefix "$LATEST_TAG" "$TAG_PREFIX")
        compare_versions_or_exit "$new_version" "$current_version"
    fi
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify spec coverage**

Run:

```bash
grep -cE 'ci::retry 3 git (fetch|pull)' examples/laravel-bluegreen-deploy/deploy-prod.sh
grep -F 'ci::git_latest_tag "$TAG_PREFIX"' examples/laravel-bluegreen-deploy/deploy-prod.sh
grep -F 'git describe --tags --abbrev=0' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: first grep prints `3`; the next two each have one match.

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add resolve_target_tag with ci::retry and ci::git_latest_tag"
```

---

## Task 8: `run_composer_install` + `run_npm_build`

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `resolve_target_tag`)

Rationale: Spec §4.1 row "L128-129 composer 完整路徑" — drop the hardcoded `/usr/local/bin/composer` path; rely on PATH resolution via `ci::require_tool composer`. Spec §4.1 row "L132-136" — keep the original `if ! ...; then sleep 30; ...; fi` inline retry-with-delay pattern, but annotate it with the §5.1 proposal pointer. Spec §4.1 row "L138-139" — `npm i && npm run build` stays as-is, guarded by `ci::require_tool npm`.

- [ ] **Step 1: Append both functions**

Use Edit. After the closing `}` of `resolve_target_tag`, insert:

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

# run_npm_build — preserved verbatim; only adds the ci::require_tool guard.
run_npm_build() {
    ci::require_tool npm || exit 1
    npm i
    npm run build
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify spec coverage**

Run:

```bash
grep -F '# proposed: ci::retry --delay SECONDS (see spec §5.1, plan TBD)' examples/laravel-bluegreen-deploy/deploy-prod.sh
grep -F 'ci::require_tool composer' examples/laravel-bluegreen-deploy/deploy-prod.sh
grep -F 'ci::require_tool npm' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match each.

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add run_composer_install and run_npm_build"
```

---

## Task 9: `parse_blue_green_target_dir`

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `run_npm_build`)

Rationale: The "what's the current symlink target → flip to the other one" logic is duplicated in the original at L148-159 and L180-189. Extracting it eliminates the duplication and is spec §4.2 row "parse_blue_green_target_dir — blue/green policy 保留". Returns the chosen target dir via stdout; signals "neither blue nor green yet, need to bootstrap" via exit code 2.

- [ ] **Step 1: Append the function**

Use Edit. After the closing `}` of `run_npm_build`, insert:

```bash

# parse_blue_green_target_dir — local blue/green policy (spec §6.7 not-collected).
#
# Returns (stdout): the directory we should deploy INTO this run (the one the
# symlink is NOT currently pointing at).
#
# Exit codes:
#   0 — current symlink resolved; stdout is the next dir.
#   2 — neither blue nor green is current (first deploy); stdout is BLUE_DIR
#       and the caller should bootstrap both dirs on the host.
parse_blue_green_target_dir() {
    local host="$1"
    local current_target

    current_target=$(ssh -i "$SSH_KEY" "$host" "sudo readlink $SITE_DIR" 2>/dev/null || true)

    if [[ "$current_target" == "$BLUE_DIR" ]]; then
        printf '%s\n' "$GREEN_DIR"
        return 0
    elif [[ "$current_target" == "$GREEN_DIR" ]]; then
        printf '%s\n' "$BLUE_DIR"
        return 0
    else
        printf '%s\n' "$BLUE_DIR"
        return 2
    fi
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add parse_blue_green_target_dir helper"
```

---

## Task 10: `deploy_files_to_host` — rsync block

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `parse_blue_green_target_dir`)

Rationale: Mirrors original L144-174 (first multi-host loop body). Preserved local because:
- rsync flag policy (`--rsync-path="sudo rsync"`, exclude list) is project-specific (spec §6.8 not-collected).
- storage-dir-aware exclude is a domain rule.

Uses `parse_blue_green_target_dir` from Task 9 and bootstraps the directories when it returns 2.

- [ ] **Step 1: Append the function**

Use Edit. After the closing `}` of `parse_blue_green_target_dir`, insert:

```bash

# deploy_files_to_host — per-host blue/green rsync (spec §6.8 not-collected).
#
# Side effect: prints "deploying to ..." progress via ci::info, sets a local
# TARGET_DIR for the caller-printed log line, and rsyncs the working tree.
deploy_files_to_host() {
    local host="$1"
    local target_dir status

    set +e
    target_dir=$(parse_blue_green_target_dir "$host")
    status=$?
    set -e

    if [[ "$status" -eq 2 ]]; then
        ci::info "no existing blue/green symlink on $host — bootstrapping"
        ssh -i "$SSH_KEY" "$host" "sudo mkdir -p $BLUE_DIR $GREEN_DIR"
    fi

    ci::info "syncing to $target_dir on $host"

    if ssh -i "$SSH_KEY" "$host" "[ ! -d $target_dir/storage ]"; then
        rsync -az --delete --exclude=".git" \
            --rsync-path="sudo rsync" -e "ssh -i $SSH_KEY" \
            ./ "$host:$target_dir/"
    else
        rsync -az --delete --exclude=".git" --exclude="storage" \
            --rsync-path="sudo rsync" -e "ssh -i $SSH_KEY" \
            ./ "$host:$target_dir/"
    fi

    ssh -i "$SSH_KEY" "$host" \
        "sudo chmod -R 777 $target_dir/storage; sudo chmod -R 777 $target_dir/bootstrap/cache;"
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add deploy_files_to_host with rsync blue/green policy"
```

---

## Task 11: `sanitize_cloudwatch_token` + `compute_cloudwatch_log_group`

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `deploy_files_to_host`)

Rationale: Original L200-203 has the same 4-stage `tr | sed | sed | sed` pipeline repeated four times for `ENV / APP / SERVICE / GROUP_ID`, and again at L213-218 for the split node-config tokens. Extracting `sanitize_cloudwatch_token` collapses six duplications into one definition. Original L227-233 is the `printf "/%s/%s/%s/%s/%s/%s"` log-group composition. Both helpers are spec §6.3 / §6.4 not-collected — CloudWatch naming is a specific cloud-provider policy that the toolkit deliberately avoids.

The helper also handles the `CLOUDWATCH_NODE_CONFIG` "ap,1" vs plain-int parsing from L207-224.

- [ ] **Step 1: Append both functions**

Use Edit. After the closing `}` of `deploy_files_to_host`, insert:

```bash

# sanitize_cloudwatch_token — CloudWatch naming policy (spec §6.3 not-collected).
# Strips \r\n\t, leading/trailing whitespace, and replaces inner spaces with _.
sanitize_cloudwatch_token() {
    printf '%s' "${1:-}" \
        | tr -d '\r\n\t' \
        | sed 's/[[:space:]]*$//' \
        | sed 's/^[[:space:]]*//' \
        | sed 's/[[:space:]]/_/g'
}

# compute_cloudwatch_log_group — CloudWatch log-group name (spec §6.4 not-collected).
#
# Output: /<env>/<app>/<service>/<group_id>/<role>/<node_id>
#
# Inputs (env): CLOUDWATCH_ENV, CLOUDWATCH_APP, CLOUDWATCH_SERVICE,
#               CLOUDWATCH_GROUP_ID.
# Inputs (args):
#   $1 — HOST_NAME (used as role fallback when NODE_CONFIG has no comma).
#   $2 — NODE_CONFIG: either "ap,1" (role,node_id) or a plain node id.
compute_cloudwatch_log_group() {
    local host_name="$1"
    local node_config="${2:-1}"
    local env_clean app_clean service_clean group_id_clean
    local role_clean node_id_clean

    env_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_ENV:-dev}")
    app_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_APP:-cmg}")
    service_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_SERVICE:-station}")
    group_id_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_GROUP_ID:-9999}")

    if [[ -n "$node_config" && "$node_config" == *,* ]]; then
        role_clean=$(sanitize_cloudwatch_token "${node_config%%,*}")
        node_id_clean=$(sanitize_cloudwatch_token "${node_config#*,}")
    else
        role_clean=$(sanitize_cloudwatch_token "$host_name")
        node_id_clean=$(sanitize_cloudwatch_token "${node_config:-1}")
    fi

    printf '/%s/%s/%s/%s/%s/%s\n' \
        "$env_clean" "$app_clean" "$service_clean" \
        "$group_id_clean" "$role_clean" "$node_id_clean"
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify duplication is gone**

Run:

```bash
grep -c "tr -d '\\\\r\\\\n\\\\t' | sed" examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: `1` (only the single occurrence inside `sanitize_cloudwatch_token`). The original had 6.

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Extract CloudWatch sanitize and log-group helpers"
```

---

## Task 12: `run_post_deploy_on_host` + `run_multi_host_deploy`

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `compute_cloudwatch_log_group`)

Rationale: Original L177-294 is the second per-host loop: artisan + supervisord + queue:restart over SSH heredoc. Spec §6.5 marks the SSH heredoc wrapping as not-collected (remote quoting risks make a generic wrapper net-negative). The whole heredoc is preserved verbatim; the only refactor is splitting "iterate hosts" from "what to do on each host" so a reader can scan the heredoc without scrolling through the loop scaffolding.

The heredoc requires bash variable expansion at LOCAL evaluation time for `$target_dir`, `$before_cmd`, etc. — so we use unquoted `EOF` (matching the original L238 `<<EOF`). `$SITE_DIR` is also expanded locally; the resulting absolute path is sent to the remote shell verbatim. The single `\$(readlink ...)` is intentionally escaped so that `readlink` runs on the REMOTE host (where `/etc/supervisor/conf.d/supervisord.conf` actually lives). The original at L256 left it unescaped — a latent bug that we silently fix; the README will mention this caveat.

- [ ] **Step 1: Append both functions**

Use Edit. After the closing `}` of `compute_cloudwatch_log_group`, insert:

```bash

# run_post_deploy_on_host — SSH heredoc post-deploy (spec §6.5 not-collected).
#
# The heredoc body is preserved verbatim from the original L238-289. All bash
# vars referenced inside ($target_dir, $before_cmd, $middle_cmd, $SITE_DIR,
# $cloudwatch_log_group_name) are interpolated by the LOCAL shell before the
# heredoc is fed to ssh — this is intentional and matches the original.
run_post_deploy_on_host() {
    local host_name="$1"
    local target_host="$2"
    local target_dir before_cmd middle_cmd
    local cloudwatch_node_config cloudwatch_log_group_name

    set +e
    target_dir=$(parse_blue_green_target_dir "$target_host")
    set -e

    before_cmd="${BEFORE_COMMANDS[$host_name]}"
    middle_cmd="${MIDDLE_COMMANDS[$host_name]}"
    cloudwatch_node_config="${CLOUDWATCH_HOST_CONFIGS[$host_name]:-1}"
    cloudwatch_log_group_name=$(compute_cloudwatch_log_group "$host_name" "$cloudwatch_node_config")

    ci::info "CloudWatch log group for ${target_host}: ${cloudwatch_log_group_name}"

    ssh -i "$SSH_KEY" "$target_host" <<EOF
cd "$target_dir"
pwd
eval "$before_cmd"
eval "$middle_cmd"
sudo ln -sfn "$target_dir" "$SITE_DIR"

if [ ! -d /var/log/laravel ]; then
    sudo mkdir -p /var/log/laravel
    sudo chown -R root:root /var/log/laravel
    sudo chmod -R 777 /var/log/laravel
fi

if [ -d "$target_dir/storage/logs" ] && [ ! -L "$target_dir/storage/logs" ]; then
    sudo rm -rf "$target_dir/storage/logs"
fi
sudo ln -sfn /var/log/laravel "$target_dir/storage/logs"

if [ "\$(readlink -f /etc/supervisor/conf.d/supervisord.conf)" != "\$(readlink -f $target_dir/supervisord.conf)" ]; then
    sudo ln -sfn "$target_dir/supervisord.conf" "/etc/supervisor/conf.d/supervisord.conf"
fi

cd "$SITE_DIR"

if [ -n "$cloudwatch_log_group_name" ]; then
    sudo php artisan env:manage set CLOUDWATCH_LOG_GROUP_NAME "$cloudwatch_log_group_name"
else
    echo "WARN: CLOUDWATCH_LOG_GROUP_NAME empty; skipping env:manage set"
fi

sudo php artisan optimize:clear
sudo php artisan config:cache
sudo php artisan view:cache
sudo supervisorctl update
sudo php artisan queue:restart
EOF

    NOTIFY_MESSAGE+="部署主機 : ${target_host}\n"
    NOTIFY_MESSAGE+="當前目錄 : ${target_dir}\n"
}

# run_multi_host_deploy — multi-host iteration (spec §6.6 not-collected).
# Sequentially: rsync to every host, then post-deploy on every host.
run_multi_host_deploy() {
    local host_name target_host

    for host_name in "${!TARGET_HOSTS[@]}"; do
        target_host="${TARGET_HOSTS[$host_name]}"
        ci::info "deploying files to host: ${target_host}"
        deploy_files_to_host "$target_host"
    done

    for host_name in "${!TARGET_HOSTS[@]}"; do
        target_host="${TARGET_HOSTS[$host_name]}"
        ci::info "running post-deploy on host: ${target_host}"
        run_post_deploy_on_host "$host_name" "$target_host"
    done
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify the heredoc is structurally intact**

Run:

```bash
grep -cE '^EOF$' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: `1` (one heredoc terminator from this task).

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add run_post_deploy_on_host and run_multi_host_deploy"
```

---

## Task 13: `run_cloudwatch_setup` — conditional log-group creation

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (append after `run_multi_host_deploy`)

Rationale: Original L300-322 sources `$PROJECT_DIR/scripts/deploy/shared/remote-cloudwatch-setup.sh`. That file does NOT exist in this example repo. Spec §4.1 row "L300-322" says: guard with `[[ -f ... ]] || ci::warn` so a `bash -n` reader doesn't get tripped, and the script as a runtime tool stays honest about its outer-wrapper dependency.

- [ ] **Step 1: Append the function**

Use Edit. After the closing `}` of `run_multi_host_deploy`, insert:

```bash

# run_cloudwatch_setup — conditional CloudWatch log-group creation.
# Mirrors original L300-322. The referenced setup script lives in the OUTER
# wrapper (StationHub) repo, NOT in this example — hence the [[ -f ]] guard.
run_cloudwatch_setup() {
    if ! ci::is_true ENABLE_CLOUDWATCH; then
        ci::info "skipping CloudWatch log-group creation (use --cloudwatch to enable)"
        ci::info "note: CloudWatch env vars are still set during deploy"
        return 0
    fi

    ci::info "=========================================="
    ci::info "creating CloudWatch log groups..."
    ci::info "=========================================="

    ci::require_env CLOUDWATCH_ENV || return 0
    ci::require_env CLOUDWATCH_APP || return 0
    ci::require_env CLOUDWATCH_SERVICE || return 0

    local setup_script="${PROJECT_DIR}/scripts/deploy/shared/remote-cloudwatch-setup.sh"
    if [[ ! -f "$setup_script" ]]; then
        ci::warn "remote-cloudwatch-setup.sh not found at $setup_script — skipping"
        ci::warn "(this is expected in the examples/ tree; supply it in your outer wrapper)"
        return 0
    fi

    # shellcheck source=/dev/null
    # Reason: the setup script lives in the outer wrapper and is intentionally
    # not part of this example. ShellCheck cannot resolve the path statically.
    source "$setup_script"

    ci::info "=========================================="
    ci::info "CloudWatch log-group creation complete"
    ci::info "=========================================="
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify the source guard is exact**

Run:

```bash
grep -F 'if [[ ! -f "$setup_script" ]]; then' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match.

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Add run_cloudwatch_setup with [[ -f ]] source guard"
```

---

## Task 14: Wire `main()` and final pipeline

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (replace the stub `main()` at the bottom)

Rationale: The stub from Task 1 is `main() { :; }`. Replace it with the full pipeline that calls every helper in order — matching the original top-to-bottom flow.

- [ ] **Step 1: Replace the stub `main()`**

Use Edit. Find this exact block:

```bash
# === Pipeline ===
main() {
    :
}

main "$@"
```

Replace it with:

```bash
# === Pipeline ===
main() {
    parse_cli "$@"

    compose_err_trap 'send_slack_notification "failed" "Script failed at line $LINENO"'

    ci::require_env PROJECT_DIR || exit 1
    cd "$PROJECT_DIR"

    resolve_target_tag
    ci::info "deploying tag: $LATEST_TAG"
    git checkout "$LATEST_TAG"

    run_composer_install
    run_npm_build

    run_multi_host_deploy

    ci::info "all deployments completed successfully"

    run_cloudwatch_setup

    send_slack_notification "success" "$NOTIFY_MESSAGE"
}

main "$@"
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0.

- [ ] **Step 3: Verify the pipeline is wired**

Run:

```bash
grep -nE '^\s*(parse_cli|compose_err_trap|resolve_target_tag|run_composer_install|run_npm_build|run_multi_host_deploy|run_cloudwatch_setup|send_slack_notification) ' \
    examples/laravel-bluegreen-deploy/deploy-prod.sh \
    | grep -v '() {$'
```

Expected: at least one call line for each of `parse_cli`, `compose_err_trap`, `resolve_target_tag`, `run_composer_install`, `run_npm_build`, `run_multi_host_deploy`, `run_cloudwatch_setup`, `send_slack_notification`.

Also confirm the final `main "$@"` invocation is present:

```bash
grep -F 'main "$@"' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: one match.

- [ ] **Step 4: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "feat: [examples] Wire main() pipeline for laravel-bluegreen retrofit"
```

---

## Task 15: ShellCheck pass — fix or annotate every warning

**Files:**
- Modify: `examples/laravel-bluegreen-deploy/deploy-prod.sh` (annotations / minor fixes only — no logic changes)

Rationale: Spec §7 says ShellCheck-clean is the target; allow `# shellcheck disable=SCxxxx` with an inline reason when a warning is a structural false positive. Tasks 2, 5, and 13 already added three `disable` comments — this task is the catch-up pass for anything ShellCheck flags that we did NOT anticipate.

- [ ] **Step 1: Run ShellCheck**

If `shellcheck` is installed locally:

```bash
shellcheck examples/laravel-bluegreen-deploy/deploy-prod.sh || true
```

If not, install via `brew install shellcheck` first, or run `./scripts/lint` which already gracefully skips.

Expected: zero unexpected warnings. Realistic anticipated warnings:

| Code | Where | Action |
|------|-------|--------|
| SC1090 | `source "$setup_script"` (Task 13) | already annotated `# shellcheck source=/dev/null` |
| SC2088 | `SSH_KEY="${SSH_KEY:-~/.ssh/...}"` (Task 2) | already annotated |
| SC2064 | `trap "$callback" ERR` (Task 5) | already annotated |
| SC2154 | unset assoc arrays `TARGET_HOSTS`, `BEFORE_COMMANDS`, `MIDDLE_COMMANDS`, `CLOUDWATCH_HOST_CONFIGS`, env vars `PROJECT_DIR`, `GIT_BRANCH`, `DEPLOY_ENV`, `SLACK_WEBHOOK_URL`, `CLOUDWATCH_ENV`, etc. | annotate per-use OR add a file-level disable directive (see Step 2) |
| SC2086 | possibly inside the SSH heredoc (Task 12) | acceptable inside a heredoc destined for a remote shell; annotate per-line if flagged |

- [ ] **Step 2: Add file-level disable for outer-wrapper variables**

The original is intentionally meant to be sourced/wrapped by code that supplies several vars. Rather than annotating every usage of `${TARGET_HOSTS[$host_name]}` etc., add a single block of directives just below the file header docstring.

Use Edit. Find the line `set -euo pipefail` and INSERT BEFORE it:

```bash
# shellcheck disable=SC2154
# Reason: these variables are supplied by an outer wrapper (see README §1):
#   PROJECT_DIR, GIT_BRANCH, DEPLOY_ENV, SLACK_WEBHOOK_URL,
#   TARGET_HOSTS, BEFORE_COMMANDS, MIDDLE_COMMANDS, CLOUDWATCH_HOST_CONFIGS,
#   CLOUDWATCH_ENV, CLOUDWATCH_APP, CLOUDWATCH_SERVICE, CLOUDWATCH_GROUP_ID
# ShellCheck cannot see the wrapper, so silence SC2154 file-wide.
```

- [ ] **Step 3: Fix anything else ShellCheck flags**

For each remaining warning:
- If it's a legitimate bug (e.g. `cd $dir` without quotes), fix it — quote variables, prefer `[[ ]]` over `[ ]` if simple substitution.
- If it's a structural false positive (heredoc internals, intentional dynamic source), add a per-line `# shellcheck disable=SCxxxx` with a one-line reason comment ABOVE the affected line.

Re-run `shellcheck examples/laravel-bluegreen-deploy/deploy-prod.sh` until exit code is 0.

- [ ] **Step 4: Verify the project lint script still passes**

Run: `./scripts/lint`
Expected: exit 0 (either runs shellcheck and finds zero issues, or skips with the standard "ShellCheck not installed" notice).

Then re-run `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh` to confirm no edits accidentally broke syntax.

- [ ] **Step 5: Commit**

```bash
git add examples/laravel-bluegreen-deploy/deploy-prod.sh
git commit -m "chore: [examples] Make laravel-bluegreen ShellCheck-clean"
```

---

## Task 16: Write `README.md`

**Files:**
- Create: `examples/laravel-bluegreen-deploy/README.md`

Rationale: Matches the structure of `examples/vendored-deploy-script/README.md` but emphasizes "this is an ADVANCED retrofit — multi-host + blue/green + Laravel post-deploy + CloudWatch" (spec §1 comparison table). Sections:

1. What this example is (and is NOT — not e2e runnable).
2. Layout.
3. Substitution table (mirrors spec §4.1).
4. What stays project-local (mirrors spec §4.2).
5. Proposed ci-toolkit APIs surfaced by this retrofit (mirrors spec §5; explicit "not implemented yet" caveat).
6. What deliberately stays out of ci-toolkit (mirrors spec §6 / not-collected appendix).
7. Adoption steps.
8. Environment-variable index (the wrapper-supplied vars listed in Task 15).

- [ ] **Step 1: Create the README**

Write `examples/laravel-bluegreen-deploy/README.md` with this exact content:

````markdown
# Laravel blue-green deploy retrofit (advanced)

An **advanced code-reference** showing how to retrofit Gungnir `ci-toolkit` into a real-world Laravel multi-host blue/green deploy script — the kind that:

- iterates an associative array of target hosts,
- flips a `/var/www/site` symlink between `site_blue` and `site_green`,
- rsyncs the build, then SSHs in a heredoc to run `php artisan optimize:clear`, supervisorctl, queue:restart,
- composes CloudWatch log-group names from environment tokens,
- and posts a multi-line Slack template with commit-log diff.

This example is **deliberately not end-to-end runnable**. Unlike [`bun-deploy/`](../bun-deploy/), there is no working Docker / build harness; unlike [`vendored-deploy-script/`](../vendored-deploy-script/), the multi-host + blue/green + Laravel post-deploy + CloudWatch surface area is too entangled with real production to mock honestly. You can run `bash -n deploy-prod.sh` and read the source side-by-side with your own script.

```
examples/laravel-bluegreen-deploy/
├── ci-toolkit       -> ../../ci-toolkit   (symlink)
├── deploy-prod.sh   (the retrofit — sources ci-toolkit from the same dir)
└── README.md
```

## Substitution table

Line numbers refer to the StationHub original this script was rewritten from.

| Original (StationHub `deploy-script.sh`) | Retrofitted |
| --- | --- |
| L1 `#!/bin/bash` | `#!/usr/bin/env bash` + `set -euo pipefail` |
| L11 `TAG_PREFIX="${TAG_PREFIX:-release/}"` | `ci::env_default TAG_PREFIX "release/"` |
| L33-35 unknown-arg `echo + exit 1` | `ci::die "unknown arg: $1 (try --help)" \|\| exit 1` |
| L43-46 manual `SLACK_WEBHOOK_URL` unset warning | `ci::slack_webhook` skips automatically when var is empty |
| L89 `trap 'send_slack_notification failed ...' ERR` | `compose_err_trap '...'` — local helper, annotated `# proposed: ci::trap_err` |
| L92 `cd $PROJECT_DIR` (no check) | `ci::require_env PROJECT_DIR \|\| exit 1; cd "$PROJECT_DIR"` |
| L99 `git describe --tags --abbrev=0` | preserved (different semantics from "latest matching tag") |
| L102-104 `git fetch origin` / `git fetch --tags` / `git pull` | each wrapped in `ci::retry 3 ...` |
| L107 `git tag -l "${TAG_PREFIX}*" \| sort -V \| tail -n1` | `ci::git_latest_tag "$TAG_PREFIX"` |
| L111-112 `${VAR#$PREFIX}` (4 sites) | `strip_tag_prefix` — local helper, annotated `# proposed: ci::strip_prefix` |
| L115-119 version compare + exit | `compare_versions_or_exit` — local helper, annotated `# proposed: ci::version_gt` |
| L128-129 `/usr/local/bin/composer` + env | `ci::require_tool composer`; path resolved via PATH |
| L132-136 composer install + `sleep 30` + retry | inline `if ! ...; then sleep 30; ...; fi`; annotated `# proposed: ci::retry --delay` |
| L138-139 `npm i && npm run build` | preserved; `ci::require_tool npm` guard added |
| L143-174 multi-host rsync | preserved in `deploy_files_to_host` + `run_multi_host_deploy` |
| L177-294 multi-host SSH heredoc | preserved in `run_post_deploy_on_host` |
| L200-203 four-stage `tr \| sed \| sed \| sed` (6× duplication) | extracted to `sanitize_cloudwatch_token` (1× definition) |
| L227-233 `printf` log-group composition | extracted to `compute_cloudwatch_log_group` |
| L300-322 `source ... remote-cloudwatch-setup.sh` | wrapped by `[[ -f ]] \|\| ci::warn` (the referenced file lives in the outer wrapper, not in this example) |
| L325 success notification | local `send_slack_notification "success" "$NOTIFY_MESSAGE"`, delegating transport to `ci::slack_webhook` |

> One silent fix: inside the SSH heredoc, the `readlink -f` comparison is escaped (`\$(readlink ...)`) so it runs on the remote host. The StationHub original ran it locally — almost certainly an oversight — but if byte-for-byte parity matters more than correctness for your reading, drop the backslashes.

## What stays project-local

| Local function | Why it's NOT in ci-toolkit |
| --- | --- |
| `parse_cli` (`--skip` / `--tag=` / `--cloudwatch`) | The toolkit deliberately does not parse argv (application policy). |
| `send_slack_notification` | Multi-line emoji + commit-log + env/version/time template is project policy. `ci::slack_webhook` only guarantees transport (retry + timeouts). |
| `compose_err_trap` *(temporary)* | Will be replaced when `ci::trap_err` lands — see spec §5.4. |
| `strip_tag_prefix` *(temporary)* | Will be replaced when `ci::strip_prefix` lands — see spec §5.3. |
| `compare_versions_or_exit` *(temporary)* | Will be replaced when `ci::version_gt` lands — see spec §5.2. |
| `sanitize_cloudwatch_token` | CloudWatch-specific naming policy (spec §6.3 not-collected). |
| `compute_cloudwatch_log_group` | Same as above (spec §6.4 not-collected). |
| `parse_blue_green_target_dir` | Blue/green flip is deployment-strategy policy. |
| `deploy_files_to_host` | rsync flag policy (`--rsync-path="sudo rsync"`, storage-aware excludes). |
| `run_post_deploy_on_host` | SSH heredoc + artisan + supervisord is application-level Laravel policy. |
| `run_multi_host_deploy` | Multi-host topology iteration is project policy. |

## ci-toolkit API proposals surfaced by this retrofit

While rewriting, four high-ROI helpers stood out. Each gets its own future plan; **none are implemented yet**. Inside `deploy-prod.sh`, the temporary local helpers each carry a `# proposed: ci::xxx (see spec §5.X, plan TBD)` annotation. Once a proposal lands, replace the local function with the new `ci::*` call and delete the annotation.

1. **`ci::retry --delay SECONDS`** (spec §5.1) — adds a backoff to the existing `ci::retry`; covers packagist/npm-registry transient failures.
2. **`ci::version_gt A B` / `ci::version_ge A B`** (spec §5.2) — `sort -V` wrapper for tag-prefix release flows.
3. **`ci::strip_prefix VALUE PREFIX`** (spec §5.3) — primarily for CLI mode; in source mode, `${VAR#$PREFIX}` is already concise.
4. **`ci::trap_err CALLBACK`** (spec §5.4) — `set -E` + ERR trap convention common in CI scripts.

## What deliberately stays out of ci-toolkit

Spec §6 captures eight patterns from this retrofit that look reusable but conflict with the toolkit's platform-neutral mandate. Quick summary — read the spec for full rationale:

1. CLI flag parsing
2. Multi-line Slack templating
3. CloudWatch token sanitization
4. CloudWatch log-group `printf` assembly
5. SSH heredoc wrapping
6. Multi-host associative-array iteration
7. Blue/green symlink flipping
8. rsync command wrapping

## How to adopt the pattern in your project

1. **Vendor the toolkit** next to your deploy script:
   ```bash
   curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.4/ci-toolkit \
       -o infra/ci/ci-toolkit
   chmod +x infra/ci/ci-toolkit
   git add infra/ci/ci-toolkit
   git commit -m "chore: [ci] Vendor Gungnir ci-toolkit v0.1.4"
   ```
2. **Source it** at the top of your deploy script:
   ```bash
   readonly SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
   source "$SCRIPT_DIR/ci-toolkit"
   ```
3. **Mechanically apply** the substitution table above. Order suggestion:
   1. Replace handwritten logger functions with `ci::info` / `ci::warn` / `ci::error` / `ci::die`.
   2. Replace `command -v X || fatal` with `ci::require_tool X || exit 1`.
   3. Replace `[ -z "${VAR:-}" ] && fatal` with `ci::require_env VAR || exit 1`.
   4. Wrap network ops (`git fetch`, `git pull`, `curl`, registry-push) with `ci::retry 3 ...`.
   5. Replace `git tag -l "$prefix*" | sort -V | tail -n1` with `ci::git_latest_tag "$prefix"`.
   6. Replace Slack `curl -X POST ...` with `ci::slack_webhook URL_VAR PROJECT STATUS MESSAGE`.
4. **Keep policy-shaped helpers local.** Anything in the "What stays project-local" table above should stay in your script.
5. **Verify**: `bash -n deploy-prod.sh` and (optionally) `shellcheck deploy-prod.sh`.

## Environment variables (wrapper-supplied)

This script is meant to be invoked by an outer wrapper that exports the following before calling it. None are validated up-front because the original doesn't — to keep behavior identical, validation happens at first use (and an ERR trap surfaces missing-var failures to Slack).

| Variable | Required? | Purpose |
| --- | --- | --- |
| `PROJECT_DIR` | yes | Absolute path to the Laravel project clone. Validated via `ci::require_env`. |
| `GIT_BRANCH` | yes (unless `--tag=` is passed) | Branch to `git pull` from. |
| `TAG_PREFIX` | no | Tag-prefix filter (default `release/`). |
| `DEPLOY_ENV` | no | Free-form env label included in the Slack template (e.g. `prod`, `staging`). |
| `SLACK_WEBHOOK_URL` | no | If unset, `ci::slack_webhook` warns and skips silently. |
| `SSH_KEY` | no | Path to the SSH key used by both rsync and `ssh` calls (default: original's `~/.ssh/sw-ssh-key.pem`). |
| `DEPLOY_DIR` | no | Root deploy directory on remote hosts (default `/var/www`). |
| `TARGET_HOSTS` | yes (assoc array) | `[host_name]=user@host` map. |
| `BEFORE_COMMANDS` | yes (assoc array) | `[host_name]=<bash snippet>` run on the remote before the symlink flip. |
| `MIDDLE_COMMANDS` | yes (assoc array) | `[host_name]=<bash snippet>` run on the remote after `BEFORE_COMMANDS`. |
| `CLOUDWATCH_HOST_CONFIGS` | no (assoc array) | `[host_name]="role,node_id"` or `[host_name]="node_id"`; defaults to `1`. |
| `CLOUDWATCH_ENV` / `CLOUDWATCH_APP` / `CLOUDWATCH_SERVICE` / `CLOUDWATCH_GROUP_ID` | yes (if `--cloudwatch`) | CloudWatch log-group name tokens. |
| `CI_TOOLKIT_DEBUG` | no | Set to `1` to surface `ci::debug` lines from the toolkit. |
````

- [ ] **Step 2: Verify the README's relative links resolve**

```bash
test -d examples/laravel-bluegreen-deploy/../bun-deploy && echo bun-link-ok
test -d examples/laravel-bluegreen-deploy/../vendored-deploy-script && echo vendored-link-ok
```

Expected: both lines print `*-link-ok`.

- [ ] **Step 3: Commit**

```bash
git add examples/laravel-bluegreen-deploy/README.md
git commit -m "docs: [examples] Add README for laravel-bluegreen retrofit"
```

---

## Task 17: Final verification

**Files:** none modified — verification only.

- [ ] **Step 1: `bash -n` on the final script**

Run: `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh`
Expected: exit 0, no output.

- [ ] **Step 2: All four `# proposed: ci::*` annotations are present and unique**

Run:

```bash
grep -c '^# proposed: ci::' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected: `4`. Verify each one matches the spec §4.3 format:

```bash
grep '^# proposed: ci::' examples/laravel-bluegreen-deploy/deploy-prod.sh
```

Expected output (order may vary slightly depending on function ordering, but each line must be present):

```
# proposed: ci::trap_err CALLBACK (see spec §5.4, plan TBD)
# proposed: ci::strip_prefix VALUE PREFIX (see spec §5.3, plan TBD)
# proposed: ci::version_gt A B (see spec §5.2, plan TBD)
# proposed: ci::retry --delay SECONDS (see spec §5.1, plan TBD)
```

- [ ] **Step 3: Platform-neutrality grep (mirror the ci-toolkit plan task 7 step 3 check)**

Run:

```bash
grep -nE 'GITHUB_ACTIONS|GITLAB_CI|CIRCLECI|JENKINS_URL|TRAVIS' \
    examples/laravel-bluegreen-deploy/deploy-prod.sh \
    && echo "FAIL: platform-specific var found" || echo "OK: no platform-specific vars"
```

Expected: `OK: no platform-specific vars`.

- [ ] **Step 4: Final lint pass**

Run: `./scripts/lint`
Expected: exit 0.

- [ ] **Step 5: Confirm the project's existing tests still pass (sanity check)**

Run: `./scripts/test`
Expected: every existing test still passes. We added no new tests and modified no code that tests exercise, so this should be a no-op — but run it to catch any unrelated drift.

- [ ] **Step 6: Confirm the existing examples still parse**

Run:

```bash
bash -n examples/vendored-deploy-script/deploy-prod.sh
```

Expected: exit 0. (`bun-deploy/` is a TypeScript example with no top-level `.sh` to parse.) The symlink content under `ci-toolkit` is shared between examples, so any change to `ci-toolkit` would break adjacent examples. We did not modify `ci-toolkit`, so this should be a no-op.

- [ ] **Step 7: No unintended modifications**

```bash
git status
```

Expected: clean working tree (all task commits already in). If anything is uncommitted, commit it with an appropriate message before declaring done.

- [ ] **Step 8: Skim the diff one final time**

```bash
git log --oneline master..HEAD
```

Expected: roughly 16 task commits, all under the `examples/laravel-bluegreen-deploy/` path. No commits should touch `ci-toolkit`, `CHANGELOG.md`, `examples/bun-deploy/`, or `examples/vendored-deploy-script/`.

---

## Self-review checklist (run when all tasks complete)

- [ ] Every row in spec §4.1 has a matching task — verified via the per-task grep checks.
- [ ] Every entry in spec §4.2 (retained local functions) maps to a function defined in `deploy-prod.sh`.
- [ ] All four `# proposed: ci::*` annotations from spec §5 are present and match the format in spec §4.3 exactly.
- [ ] ci-toolkit, CHANGELOG.md, and the two other examples are untouched.
- [ ] `bash -n` and ShellCheck both clean.
- [ ] No `tests/test_*.sh` files were added (spec §2 non-goal).
- [ ] README mirrors spec §1 (advanced retrofit framing), §4.1 (table), §4.2 (retained-local), §5 (proposals), §6 (not-collected).
