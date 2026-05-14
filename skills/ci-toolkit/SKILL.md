---
name: ci-toolkit
description: Use when writing, refactoring, reviewing, or troubleshooting Bash CI / build / deploy scripts in any project. Provides the Gungnir ci-toolkit (ci::ls, ci::is_true, ci::info, ci::retry, ...) integration playbook with two modes — vendored copy or curl-pinned URL — and enforces modular script structure (main, run_xxx).
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
4. Output the minimal viable set of scripts (`check`, `build`, `deploy` only — `release` is optional). Use `ci::is_true` for boolean flags and `ci::env_default` for optional variables.
5. **Enforce Modular Structure**: Always use a `main()` entry point and a `run_xxx()` function structure. Avoid top-level execution logic.

### Refactoring an existing script

1. Grep the script for duplication signals:
   - hand-written log prefixes (`echo "[INFO] ..."`, `printf '[deploy] %s\n' ...`)
   - guard blocks like `if [[ -z "$X" ]]; then echo "X required"; exit 1; fi`
   - manual boolean checks like `[[ "${VAR:-0}" == "1" ]]` or `[[ "$VAR" == "true" ]]` (replace with `ci::is_true`)
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
- **Modular Structure.** Scripts should use a `main()` entry point and local functions.
- **Library functions return; they do not `exit`.** When sourced, `ci-toolkit` must not kill the caller's shell. Use `return 1`, never `exit 1`, from `ci::*` helpers.

## Reference paths

- Function table and integration overview: `../../README.md`
- Worked example for a new script: `../../examples/bun-deploy/`
- Worked example for a refactor: `../../examples/vendored-deploy-script/`
- Library source (read when in doubt about a helper's behavior): `../../ci-toolkit`
