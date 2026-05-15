---
name: ci-toolkit
description: Use when writing, refactoring, reviewing, or troubleshooting Bash CI / build / deploy scripts in any project. Provides the Gungnir ci-toolkit (ci::ls, ci::info/warn/error/die, ci::is_true, ci::env_default, ci::require_env/tool/file/dir/match/uint, ci::eq/ne/in/not_in, ci::retry, ci::find_up/root, ci::version_gt/ge, ci::git_latest_tag, ci::strip_prefix, ci::shell_join, ci::trap_err, ci::slack_webhook) integration playbook with two modes — vendored copy or curl-pinned URL — and enforces modular script structure (main, run_xxx).
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

1. Use `./ci-toolkit ls` to discover all available `ci::*` helpers and their descriptions.
2. Use `../../examples/bun-deploy/scripts/` as the canonical skeleton — `check`, `build`, `deploy`, `release` are modular scripts using the `main() -> run_xxx()` pattern.
3. Decide vendor vs URL using the table above and reflect it in how the script obtains `ci-toolkit`.
4. Output the minimal viable set of scripts (`check`, `build`, `deploy` only — `release` is optional). Typical helper usage:
   - **Preflight**: `ci::require_env` for required vars, `ci::require_tool` for binaries (`git`, `curl`, `rsync`), `ci::require_file` / `ci::require_dir` for expected artifacts, `ci::trap_err` once at the top to print exit-code/file:line/function on any failure.
   - **Inputs**: `ci::is_true` for boolean flags, `ci::env_default` for optional variables, `ci::require_match` for free-form values (tags, IDs), `ci::require_uint` for counts/timeouts, `ci::in` / `ci::not_in` for whitelists (env names, region codes).
   - **Flow**: `ci::retry` around any network call (curl, rsync, deploy push); `ci::root` / `ci::find_up` to locate repo root or marker files instead of `cd ..` walks.
   - **Versions / output**: `ci::git_latest_tag`, `ci::version_gt` / `ci::version_ge`, `ci::strip_prefix` for tag → version conversion, `ci::shell_join` when building remote command strings for ssh / `rsync -e`.
   - **Notifications**: `ci::slack_webhook URL_VAR PROJECT STATUS MESSAGE` for best-effort Slack posts (no-op if the URL var is unset).
5. **Enforce Modular Structure**: Always use a `main()` entry point and a `run_xxx()` function structure. Avoid top-level execution logic.

### Refactoring an existing script

1. Grep the script for duplication signals (left = what to look for, right = the helper that replaces it):
   - hand-written log prefixes (`echo "[INFO] ..."`, `printf '[deploy] %s\n' ...`) → `ci::info` / `ci::warn` / `ci::error` / `ci::debug` (or `ci::die` for "log error then return 1")
   - guard blocks like `if [[ -z "$X" ]]; then echo "X required"; exit 1; fi` → `ci::require_env X`
   - manual boolean checks like `[[ "${VAR:-0}" == "1" ]]` or `[[ "$VAR" == "true" ]]` → `ci::is_true VAR`
   - `command -v X >/dev/null || { echo "X required"; exit 1; }` → `ci::require_tool X`
   - `[[ -f "$path" ]] || { echo "missing"; exit 1; }` / same for `-d` → `ci::require_file NAME PATH` / `ci::require_dir NAME PATH` (reports NAME, never PATH)
   - ad-hoc regex / integer validation (`[[ "$X" =~ ^... ]]`, `[[ "$X" =~ ^[0-9]+$ ]]`) → `ci::require_match NAME VALUE REGEX [DESC]` / `ci::require_uint NAME VALUE` (never prints VALUE)
   - whitelist tests via `case` arms or repeated `[[ "$X" == "a" || "$X" == "b" ]]` → `ci::in VALUE CANDIDATE...` / `ci::not_in VALUE CANDIDATE...`; for single-pair string equality use `ci::eq` / `ci::ne` (never prints values)
   - curl / fetch / network / `git push` calls without retry → `ci::retry N [--delay S] -- COMMAND...`
   - `cd "$(dirname "${BASH_SOURCE[0]}")/.."` style repo-root discovery → `ci::root` (= `ci::find_up .git`); for non-git markers use `ci::find_up MARKER`
   - hand-rolled `trap '...' ERR` blocks → `ci::trap_err` (single call; also sets `set -E`)
   - `git tag -l "v*" | sort -V | tail -n 1` / manual `sort -V` version compares → `ci::git_latest_tag PREFIX` / `ci::version_gt LHS RHS` / `ci::version_ge LHS RHS`
   - `${tag#v}` / `${name#prefix-}` repeated literal-prefix stripping → `ci::strip_prefix PREFIX VALUE`
   - manual `printf '%q ' "$@"` for building remote ssh / `rsync -e` strings → `ci::shell_join ARG...`
   - hand-rolled Slack curl with JSON escaping → `ci::slack_webhook URL_VAR PROJECT STATUS MESSAGE` (skips silently if URL_VAR unset or `curl` missing)
2. Use `../../examples/vendored-deploy-script/deploy-prod.sh` as the reference pattern — it shows the before/after for a real production deploy script.
3. Prefer vendored mode for refactors: copy `ci-toolkit` into the consumer repo and pin the version with a comment, so the refactor is fully reproducible.
4. Replace duplication only. Do not rewrite business logic, re-order steps, or restructure the script. The refactor is mechanical: the script does the same thing, with fewer hand-rolled helpers.

## Invariants

These hold for any script that sources or invokes `ci-toolkit`:

- **Platform-neutral.** No `GITHUB_ACTIONS`, `GITLAB_CI`, `CIRCLECI`, or other CI-vendor variable names. The script must work locally and in any CI.
- **No secret leakage.** Validation helpers report variable *names* only — never values. Do not `echo "$SECRET"` for debugging.
- **Stderr for logs, stdout for data.** Every `ci::log` family helper writes to stderr. Anything that returns a path (e.g. `ci::find_up`) writes the path to stdout.
- **Modular Structure.** Scripts should use a `main()` entry point and local functions.
- **Library functions return; they do not `exit`.** When sourced, `ci-toolkit` must not kill the caller's shell. Use `return 1`, never `exit 1`, from `ci::*` helpers.

## Reference paths

- Function table and integration overview: `../../README.md`
- Worked example for a new script: `../../examples/bun-deploy/`
- Worked example for a refactor: `../../examples/vendored-deploy-script/`
- Library source (read when in doubt about a helper's behavior): `../../ci-toolkit`
