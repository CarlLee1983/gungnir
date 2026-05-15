# Gungnir

<!-- doc-key: overview -->
Experimental, platform-neutral Bash helpers for CI scripts.

Gungnir ships one file, `ci-toolkit`. You can execute it as a CLI or `source` it as a Bash library that exposes `ci::` functions. It is intentionally small: it handles reusable CI primitives such as logging, environment checks, retries, path discovery, version comparisons, validation, shell argument escaping, and simple notifications. It does **not** encode GitHub Actions, GitLab, CircleCI, Docker, build, or deploy policy.

Use Gungnir when your CI scripts have started accumulating hand-written helpers such as `log()`, `fatal()`, `retry()`, `require_env()`, or "find repo root" snippets. Keep project-specific decisions in your own scripts; delegate the boring, error-prone primitives to the toolkit.

## What you get

- **One artifact**: download `ci-toolkit`, mark it executable, and commit or cache it like any other script.
- **Two modes**: CLI mode for one-liners, source mode for full scripts.
- **Safe output contracts**: logs go to stderr; data goes to stdout; validation failures name the failing field but never print secret values.
- **Predictable failures**: source functions return statuses instead of exiting; CLI usage errors return `64`.
- **Bash 4+ only**: no build step, no package manager, no runtime service.

---

<!-- doc-key: install-setup -->
## Install & setup

### Requirements

- Bash 4+. On older macOS machines, `/bin/bash` is 3.2; install a newer Bash with `brew install bash` and run scripts through `#!/usr/bin/env bash`.
- Standard shell tools available on `PATH`.
- A `sort` implementation with `-V` support if you use `ci::version_gt`, `ci::version_ge`, or `ci::git_latest_tag`. The toolkit probes this and prints a remediation hint if it is missing.
- Optional: `shellcheck` if you want local linting via `./scripts/lint`.

### Install a pinned release

Pin a release tag in CI. Do not curl `main` from production automation unless you deliberately want experimental changes.

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.10/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

Expected output:

```text
ci-toolkit 0.1.10
```

### Vendor it next to your script

For scripts that need to run on a CI host, deployment host, or developer laptop, the lowest-surprise pattern is to vendor a pinned copy next to the script that uses it.

```bash
mkdir -p infra/ci
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.10/ci-toolkit \
  -o infra/ci/ci-toolkit
chmod +x infra/ci/ci-toolkit
git add infra/ci/ci-toolkit
git commit -m "Vendor Gungnir ci-toolkit v0.1.10"
```

Then load it with a path relative to the script, not the caller's current directory:

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./ci-toolkit
source "$SCRIPT_DIR/ci-toolkit"
```

### CLI quick check

```bash
./ci-toolkit help
./ci-toolkit ls
./ci-toolkit log info "toolkit is installed"
./ci-toolkit env require HOME
./ci-toolkit tool require git
```

### Raw Bash vs Gungnir

| Task | Raw Bash | Gungnir `ci-toolkit` |
|------|----------|----------------------|
| **Logging** | `echo "[INFO] starting" >&2` | `ci::info "starting"` |
| **Env check** | `if [[ -z "${TOKEN:-}" ]]; then echo ...; exit 1; fi` | `ci::require_env TOKEN` |
| **Tool check** | manual `command -v` check plus exit handling | `ci::require_tool git` |
| **Retry** | custom loop with counters, sleeps, and status preservation | `ci::retry 3 -- curl -fsS "$URL"` |
| **Path discovery** | fixed-depth `cd "$(dirname "$0")/.."` snippets | `ci::root` or `ci::find_up marker` |
| **String allow-list** | `case "$env" in prod\|staging) ...` | `ci::in "$env" prod staging` |


### Before / after: raw Bash syntax vs `ci::` syntax

The advantage of Gungnir is not that Bash cannot do these things. The advantage is that the safe version of raw Bash is repetitive and easy to get subtly wrong. The `ci::` syntax names the intent directly.

#### Logging

Raw Bash often mixes stdout and stderr, or uses inconsistent prefixes:

```bash
echo "starting deploy"
echo "warning: cache missing" >&2
echo "error: deploy failed" >&2
```

With `ci::`, logs are consistently structured and always go to stderr:

```bash
ci::info "starting deploy"
ci::warn "cache missing"
ci::error "deploy failed"
```

#### Required environment variables

Raw Bash checks are verbose, and it is easy to accidentally print a secret while debugging:

```bash
if [[ -z "${DEPLOY_TOKEN:-}" ]]; then
  echo "DEPLOY_TOKEN is required" >&2
  exit 1
fi
```

With `ci::`, the helper checks the variable by name and never prints its value:

```bash
ci::require_env DEPLOY_TOKEN || exit $?
```

#### Required tools

Raw Bash repeats `command -v` plumbing in every script:

```bash
if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi
```

With `ci::`, the syntax describes the precondition:

```bash
ci::require_tool git || exit $?
```

#### Retry a flaky command

A correct raw retry loop must preserve the final exit status, count attempts correctly, and avoid hiding deterministic failures:

```bash
attempt=1
max_attempts=3
status=0
while (( attempt <= max_attempts )); do
  curl -fsS "$HEALTH_URL" && status=0 && break
  status=$?
  echo "attempt $attempt failed" >&2
  attempt=$((attempt + 1))
done
exit "$status"
```

With `ci::`, retry policy is one line and the wrapped command remains visible:

```bash
ci::retry 3 -- curl -fsS "$HEALTH_URL"
```

Add delay without rewriting the loop:

```bash
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

#### Find the repository root

Raw Bash often assumes a fixed directory depth, which breaks when the script moves:

```bash
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
```

With `ci::`, discover the root from the current working directory:

```bash
REPO_ROOT=$(ci::root) || exit $?
```

#### Validate values without leaking them

Raw Bash validation commonly prints the rejected value or path:

```bash
if [[ ! "$DEPLOY_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid deploy user: $DEPLOY_USER" >&2
  exit 1
fi
```

With `ci::`, stderr names the logical field and rule, not the sensitive value:

```bash
ci::require_match DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
```

#### Allow-list checks

Raw Bash `case` is fine, but it expands quickly as conditions get repeated:

```bash
case "${TARGET_ENV:-}" in
  staging|production|preview) ;;
  *)
    echo "unsupported TARGET_ENV" >&2
    exit 1
    ;;
esac
```

With `ci::`, the allowed values are the arguments:

```bash
if ! ci::in "${TARGET_ENV:-}" staging production preview; then
  ci::die "unsupported TARGET_ENV" || exit 1
fi
```

---

<!-- doc-key: connections -->
## Connections / initialisation

Gungnir has no server-side connection setup. "Connection" means how your script connects to the toolkit: execute it as a CLI, or source it into the current Bash process.

### Choose the right mode

| Mode | Use when | Behavior |
| --- | --- | --- |
| **Source mode** | You are writing a script with functions, branches, cleanup, or multiple steps. | `source ./ci-toolkit`, then call `ci::...`. Helpers return status codes and do not terminate your shell. |
| **CLI mode** | You need a one-liner in a Makefile, CI YAML step, or shell pipeline. | Run `./ci-toolkit ...`. Commands use process exit codes and print usage errors to stderr. |

### Source mode skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/ci-toolkit"

main() {
  ci::trap_err
  ci::info "starting checks"

  ci::require_tool git || exit $?
  ci::require_env DEPLOY_TOKEN || exit $?

  ci::retry 3 -- git fetch origin --quiet
  ci::info "done"
}

main "$@"
```

### CLI mode examples

```bash
./ci-toolkit log info "starting checks"
./ci-toolkit env require DEPLOY_TOKEN
./ci-toolkit tool require git
./ci-toolkit retry 5 -- curl -fsS https://example.com/health
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

### Output and exit-code contract

| Contract | Details |
| --- | --- |
| Logs | `ci::log`, `ci::info`, `ci::warn`, `ci::error`, and `ci::debug` write to **stderr**. |
| Data | Helpers that return a value, such as `ci::root`, `ci::find_up`, `ci::strip_prefix`, and `ci::shell_join`, write to **stdout**. |
| Source failures | Source functions return a status. Add explicit exit handling when a failed guard should stop the script. |
| CLI usage errors | Malformed CLI invocations return `64` and print usage to stderr. |
| Secret safety | `require_env`, `require_file`, `require_dir`, `require_match`, and `require_uint` report names/rules, not sensitive values. |

### Environment variables

| Variable | Effect |
| --- | --- |
| `CI_TOOLKIT_DEBUG=1` | Enables `ci::debug` / `log debug` output. Debug logs are silent by default. |

`ci::env_default VAR VALUE` is a helper, not a configuration variable. In source mode it sets `VAR` in the current shell if `VAR` is unset or empty.


### Syntax reference: CLI grammar

Most CLI commands follow this shape:

```text
./ci-toolkit <command> [subcommand] [arguments...]
```

Commands that run another command use `--` to mark where toolkit options end and your command begins:

```bash
./ci-toolkit retry [ATTEMPTS] [--delay SECONDS] -- COMMAND [ARGS...]
```

Examples:

```bash
./ci-toolkit retry -- make test                  # default 3 attempts
./ci-toolkit retry 5 -- curl -fsS "$HEALTH_URL"  # explicit attempts
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev
```

Nested CLI commands put the noun first, then the action:

```bash
./ci-toolkit env require DEPLOY_TOKEN
./ci-toolkit env default DEPLOY_ENV staging
./ci-toolkit tool require git
./ci-toolkit file require SSH_KEY "$DEPLOY_SSH_KEY" "mount the key first"
./ci-toolkit dir require BUILD_DIR "$BUILD_DIR" "run build first"
./ci-toolkit match require DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint require RETAIN_RELEASES "$RETAIN_RELEASES"
./ci-toolkit shell join ssh -i "$DEPLOY_SSH_KEY" -p 22
./ci-toolkit git latest-tag v
./ci-toolkit slack webhook SLACK_WEBHOOK_URL my-service success "deploy complete"
```

### Syntax reference: source-mode rules

Source-mode helpers are normal Bash functions. They do not exit your script; they return a status. Use them in `if`, `||`, command substitution, or assignments depending on what the helper returns.

```bash
source ./ci-toolkit

ci::require_env DEPLOY_TOKEN || exit $?          # guard helper
ci::retry 3 -- git fetch origin --quiet          # command wrapper
if ci::in "${TARGET_ENV:-}" staging production; then ...; fi  # predicate
repo_root=$(ci::root) || exit $?                 # data helper
```

Use these patterns consistently:

```bash
# Required preconditions: stop when a guard fails.
ci::require_tool git || exit $?
ci::require_env DEPLOY_TOKEN || exit $?

# Predicates and optional branches: use helpers directly in if statements.
if ci::is_true RUN_DEPLOY; then
  run_deploy
fi

# Data helpers: capture stdout, then handle failure.
repo_root=$(ci::root) || exit $?
latest_tag=$(ci::git_latest_tag v) || exit $?

# Project-specific context: combine predicates with your own error message.
ci::version_gt "$new" "$old" || ci::die "tag is not newer" || exit 1
```

### Syntax reference: source and CLI equivalents

| Purpose | Source syntax | CLI syntax | Success output |
| --- | --- | --- | --- |
| Print help | n/a | `./ci-toolkit help` | Usage text on stdout |
| Print version | n/a | `./ci-toolkit version` | `ci-toolkit X.Y.Z` |
| List functions | `ci::ls` | `./ci-toolkit ls` | Function list on stdout |
| Info log | `ci::info MESSAGE...` | `./ci-toolkit log info MESSAGE` | Log line on stderr |
| Warn log | `ci::warn MESSAGE...` | `./ci-toolkit log warn MESSAGE` | Log line on stderr |
| Error log | `ci::error MESSAGE...` | `./ci-toolkit log error MESSAGE` | Log line on stderr |
| Debug log | `ci::debug MESSAGE...` | `./ci-toolkit log debug MESSAGE` | Stderr only when `CI_TOOLKIT_DEBUG=1` |
| Die helper | `ci::die MESSAGE...` | n/a | Error log; returns `1` |
| Require env var | `ci::require_env VAR_NAME` | `./ci-toolkit env require VAR_NAME` | No stdout |
| Default env var | `ci::env_default VAR_NAME DEFAULT` | `./ci-toolkit env default VAR_NAME DEFAULT` | Effective value on stdout |
| Require tool | `ci::require_tool TOOL_NAME` | `./ci-toolkit tool require TOOL_NAME` | No stdout |
| Retry command | `ci::retry ATTEMPTS [--delay SECONDS] [--] COMMAND...` | `./ci-toolkit retry [ATTEMPTS] [--delay SECONDS] -- COMMAND...` | Wrapped command output |
| Find marker upward | `ci::find_up MARKER` | n/a | Matching directory on stdout |
| Find git root | `ci::root` | n/a | Git root on stdout |
| Latest tag | `ci::git_latest_tag [PREFIX]` | `./ci-toolkit git latest-tag [PREFIX]` | Tag on stdout |
| Strip prefix | `ci::strip_prefix PREFIX STRING` | `./ci-toolkit strip-prefix PREFIX STRING` | Result string on stdout |
| Version greater-than | `ci::version_gt LHS RHS` | `./ci-toolkit version gt LHS RHS` | Status only |
| Version greater-or-equal | `ci::version_ge LHS RHS` | `./ci-toolkit version ge LHS RHS` | Status only |
| Equality predicate | `ci::eq ACTUAL EXPECTED` | `./ci-toolkit eq ACTUAL EXPECTED` | Status only |
| Inequality predicate | `ci::ne ACTUAL EXPECTED` | `./ci-toolkit ne ACTUAL EXPECTED` | Status only |
| Allow-list predicate | `ci::in VALUE CANDIDATE...` | `./ci-toolkit in VALUE CANDIDATE...` | Status only |
| Deny-list predicate | `ci::not_in VALUE CANDIDATE...` | `./ci-toolkit not-in VALUE CANDIDATE...` | Status only |
| Require file | `ci::require_file NAME PATH [HINT]` | `./ci-toolkit file require NAME PATH [HINT]` | No stdout |
| Require directory | `ci::require_dir NAME PATH [HINT]` | `./ci-toolkit dir require NAME PATH [HINT]` | No stdout |
| Require regex match | `ci::require_match NAME VALUE REGEX [DESCRIPTION]` | `./ci-toolkit match require NAME VALUE REGEX [DESCRIPTION]` | No stdout |
| Require unsigned int | `ci::require_uint NAME VALUE` | `./ci-toolkit uint require NAME VALUE` | No stdout |
| Shell-escape argv | `ci::shell_join ARG...` | `./ci-toolkit shell join ARG...` | Bash-escaped command string |
| ERR trap | `ci::trap_err` | `./ci-toolkit trap-err` | Source installs trap; CLI returns `64` with hint |
| Slack webhook | `ci::slack_webhook URL_VAR PROJECT STATUS MESSAGE` | `./ci-toolkit slack webhook URL_VAR PROJECT STATUS MESSAGE` | No stdout |

### Syntax reference: argument meanings

| Name | Meaning | Example |
| --- | --- | --- |
| `VAR_NAME` | Name of an environment variable, not its value. | `DEPLOY_TOKEN` |
| `NAME` | Safe logical label to print on failure. Use this instead of printing secrets or paths. | `SSH_KEY`, `BUILD_DIR` |
| `PATH` | File or directory path to validate. Not printed on validation failure. | `"$DEPLOY_SSH_KEY"` |
| `HINT` | Optional remediation text printed after the safe logical name. | `"mount deploy key"` |
| `REGEX` | Bash extended regular expression used by `[[ value =~ regex ]]`. | `'^[0-9]+$'` |
| `DESCRIPTION` | Safe description of the regex rule. Printed instead of the raw value. | `"digits only"` |
| `ATTEMPTS` | Positive integer retry count. Omit for default `3` in CLI retry. | `5` |
| `SECONDS` | Delay between failed retry attempts. | `30` |
| `PREFIX` | Literal string prefix, not a glob. | `v` |
| `CANDIDATE...` | One or more literal allowed/blocked strings. | `staging production` |
| `URL_VAR` | Name of the env var that stores a Slack webhook URL. | `SLACK_WEBHOOK_URL` |

---

<!-- doc-key: discovery-read -->
## Discovery / read

Use these commands before changing scripts, during debugging, or when teaching an AI/code assistant what the toolkit provides.

### List available functions

```bash
./ci-toolkit ls
```

`ls` prints every public `ci::` function with its `# @description` text. Private helpers named `ci::_...` are intentionally hidden.

### Inspect CLI usage

```bash
./ci-toolkit help
```

Use this when you remember the helper but not the exact CLI nesting, for example `file require` vs `require file`.

### Read boolean-like flags

`ci::is_true VAR` returns success only when the variable's value is `1` or `true`.

```bash
RUN_DEPLOY=${RUN_DEPLOY:-0}
if ci::is_true RUN_DEPLOY; then
  ci::info "deploy checks enabled"
fi
```

This avoids ad-hoc comparisons scattered through the script. It intentionally does not treat every non-empty value as true.

### Read paths and tags

```bash
repo_root=$(ci::root) || exit $?
latest_release=$(ci::git_latest_tag v) || exit $?
version=$(ci::strip_prefix v "$latest_release")
```

Use command substitution for helpers that return data. Because logs go to stderr, stdout stays safe to capture.

---

<!-- doc-key: writes-mutations -->
## Writes / mutations

Gungnir does not deploy, build, publish, or mutate your project by itself. It wraps your commands so mutation-heavy scripts fail earlier, retry transient operations, and report clearer logs.

### Robust retries

`ci::retry` runs a command up to `N` times, returns as soon as it succeeds, and otherwise returns the final attempt's status. Failed attempts emit warnings to stderr.

```bash
# Source mode
ci::retry 3 -- curl -fsS https://api.example.com/health
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader

# CLI mode
./ci-toolkit retry 3 -- curl -fsS https://api.example.com/health
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

Use retries for operations that are plausibly transient: registry downloads, `git fetch`, package installs, health probes, `curl`, `rsync`, or remote API calls. Do **not** retry deterministic failures such as unit tests, syntax checks, or builds unless you have a specific flaky infrastructure reason.

### Secure environment checks

`ci::require_env NAME` checks whether the environment variable named by `NAME` is set and non-empty. It prints the variable name, never its value.

```bash
ci::require_env REGISTRY_TOKEN || exit $?
printf '%s' "$REGISTRY_TOKEN" | docker login ghcr.io --username ci --password-stdin
```

For optional values, prefer defaults:

```bash
ci::env_default REGISTRY_USER ci
ci::env_default DEPLOY_REAL 0
```

### Required files, directories, formats, and integers

Use validation helpers to name the logical field and keep actual values out of logs.

```bash
ci::require_file SSH_KEY "$DEPLOY_SSH_KEY" "create or mount the deploy key" || exit $?
ci::require_dir BUILD_DIR "$BUILD_DIR" "run build first" || exit $?
ci::require_match DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint RETAIN_RELEASES "$RETAIN_RELEASES" || exit $?
```

CLI equivalents:

```bash
./ci-toolkit file  require SSH_KEY "$DEPLOY_SSH_KEY" "create or mount the deploy key"
./ci-toolkit dir   require BUILD_DIR "$BUILD_DIR" "run build first"
./ci-toolkit match require DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint  require RETAIN_RELEASES "$RETAIN_RELEASES"
```

### Slack webhook notification

`ci::slack_webhook URL_VAR PROJECT STATUS MESSAGE` sends a small JSON payload to the webhook URL stored in `URL_VAR`. It is best-effort: if the URL variable is empty or `curl` is missing, it warns and returns success so notifications do not break the deploy path.

```bash
ci::slack_webhook SLACK_WEBHOOK_URL "my-service" "success" "release $IMAGE_TAG deployed"
```

CLI equivalent:

```bash
./ci-toolkit slack webhook SLACK_WEBHOOK_URL "my-service" "success" "release $IMAGE_TAG deployed"
```

---

<!-- doc-key: advanced-tools -->
## Advanced tools

### Logging and failure helpers

```bash
ci::info "starting"
ci::warn "optional cache unavailable"
ci::error "preflight failed"
ci::debug "resolved BUILD_DIR=$BUILD_DIR"
ci::die "unsupported deploy target" || exit 1
```

`ci::debug` is silent unless `CI_TOOLKIT_DEBUG=1`. `ci::die` logs at error level and returns `1`; it does not call `exit` for you.

### Path discovery

```bash
repo_root=$(ci::root) || exit $?
config_root=$(ci::find_up package.json) || exit $?
```

`ci::find_up <marker>` walks upward from `$PWD` until it finds a file or directory named `<marker>` and prints the matching directory. `ci::root` is shorthand for `ci::find_up .git`.

### Version-style comparison and tag discovery

```bash
latest=$(ci::git_latest_tag v) || exit $?
version=$(ci::strip_prefix v "$latest")

if ci::version_ge "$version" "1.2.0"; then
  ci::info "release is new enough"
fi

if ci::version_gt "1.2.4" "1.2.3"; then
  ci::info "greater"
fi
```

CLI equivalents:

```bash
./ci-toolkit git latest-tag v
./ci-toolkit strip-prefix v v1.2.3
./ci-toolkit version gt 1.2.4 1.2.3
./ci-toolkit version ge 1.2.3 1.2.3
```

These helpers rely on `sort -V`. They are good for CI version gates and release tags, but they are not a full SemVer 2.0 implementation.

### String predicates

String predicates return status only and never print compared values.

```bash
branch=$(git branch --show-current)
if ci::eq "$branch" main; then
  ci::info "main branch checks"
fi

if ci::in "${TARGET_ENV:-}" staging production preview; then
  ci::info "accepted target"
else
  ci::die "unsupported TARGET_ENV" || exit 1
fi
```

| Helper | CLI | Behavior |
| --- | --- | --- |
| `ci::eq ACTUAL EXPECTED` | `eq` | Exit `0` iff `ACTUAL == EXPECTED`. |
| `ci::ne ACTUAL EXPECTED` | `ne` | Exit `0` iff `ACTUAL != EXPECTED`. |
| `ci::in VALUE CANDIDATE...` | `in` | Exit `0` iff `VALUE` matches any candidate. |
| `ci::not_in VALUE CANDIDATE...` | `not-in` | Exit `0` iff `VALUE` matches no candidate. |

### Shell argument escaping

`ci::shell_join` converts an argv array into one Bash-escaped command string. This is useful for tools that require a command string instead of argv, such as `rsync -e`.

```bash
SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
rsync -e "$RSYNC_SSH" "$BUILD_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"
```

The output uses Bash `printf '%q'`. Do not feed untrusted data through `eval`.

### Default ERR trap

```bash
ci::trap_err
```

`ci::trap_err` installs an `ERR` trap that reports exit code, `file:line`, function name, and the failing `BASH_COMMAND`. It enables `set -E` so the trap propagates into functions, but it does not enable `set -e`, `set -u`, or `pipefail` for you.

---

<!-- doc-key: diagnostics-recovery -->
## Diagnostics / recovery

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success. |
| `1` | A runtime check failed, a predicate was false, a marker was not found, or retries were exhausted. |
| `64` | Usage error: unknown command, missing required arguments, invalid retry count, invalid regex, or a source/CLI mismatch such as running `trap-err` as a CLI action. |

### Troubleshooting guide

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `bad array subscript` or unexpected Bash behavior on macOS | Script is running under Bash 3.2. | Use `#!/usr/bin/env bash` and install Bash 4+ (`brew install bash`). |
| Version/tag helpers complain about `sort -V` | Your `sort` lacks version-sort support. | Install GNU coreutils or ensure a compatible `sort` is on `PATH`. |
| A value is missing from logs | This is usually intentional. | Validation helpers avoid printing values to prevent secret leakage. Log safe summaries yourself if needed. |
| `ci::debug` prints nothing | Debug logging is disabled. | Run with `CI_TOOLKIT_DEBUG=1`. |
| `ci::root` fails | No `.git` directory exists above `$PWD`. | Run from inside a checkout, or use `ci::find_up <project-marker>`. |
| CLI command exits `64` | Arguments do not match `./ci-toolkit help`. | Re-run with `help`; check nested command order. |

### Safe debugging pattern

```bash
CI_TOOLKIT_DEBUG=1 ./your-script.sh
```

In source mode, combine `ci::trap_err` with explicit preflight checks near the top of `main()` so failures point at the command that actually failed.

---

<!-- doc-key: ai-integration -->
## AI-agent integration

Gungnir is useful for AI-generated CI and deploy scripts because it gives the agent a small, stable vocabulary instead of inviting it to invent custom Bash helpers.

### Recommended prompt for an agent

```text
Use ./ci-toolkit for CI primitives. Source it in Bash scripts and prefer ci::info,
ci::warn, ci::die, ci::require_env, ci::require_tool, ci::retry, ci::find_up,
ci::root, validation helpers, and ci::shell_join instead of writing custom helpers.
Keep project-specific build/deploy policy in the script.
```

### What to ask the agent to preserve

- Source `ci-toolkit` relative to the script location.
- Keep a `main()` entry point and small `run_*` functions.
- Use `ci::require_env` for secrets instead of echoing values.
- Use `ci::retry` only around transient network or remote operations.
- Keep logs on stderr and capture data helpers from stdout.
- Do not introduce CI-vendor-specific assumptions into reusable helpers.

### Example: agent-friendly deployment preflight

```bash
preflight() {
  ci::require_tool git || exit $?
  ci::require_tool rsync || exit $?
  ci::require_env DEPLOY_HOST || exit $?
  ci::require_env DEPLOY_USER || exit $?
  ci::require_file SSH_KEY "$DEPLOY_SSH_KEY" "mount deploy key" || exit $?
}
```

The repository also includes `skills/ci-toolkit/` for Claude Code users. Run `scripts/install-skill` to symlink it into your local Claude skills directory.

---

<!-- doc-key: documentation-maintenance -->
## Documentation maintenance

User documentation is kept in Markdown and HTML for each locale:

```text
docs/user/en/index.md
docs/user/en/index.html
docs/user/zh-TW/index.md
docs/user/zh-TW/index.html
```

Every major topic is anchored by a doc-key marker comment. The doc-key order must match between Markdown and HTML for each locale so generated/user-facing surfaces stay navigable.

Run the documentation parity check after edits:

```bash
bun run scripts/check-user-docs.ts
```

For broader repository validation, run:

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

When adding a new public helper, update documentation in this order:

1. Add or update the helper's `# @description` above the public `ci::` function.
2. Update `./ci-toolkit help` usage text and CLI examples.
3. Add source-mode and CLI-mode tests.
4. Update `README.md`, `CHANGELOG.md`, and the user docs.
5. Run the doc parity check and the quality gates above.
