# Gungnir CI Toolkit

Experimental, platform-neutral Bash helpers for CI scripts. A single file (`ci-toolkit`) that doubles as a CLI and as a sourceable `ci::` function library.

> **Status:** experimental. CLI flags and `ci::` source APIs may change before stabilization. Pin a release tag in CI; do not track `main`.

## Why

CI scripts tend to grow ad-hoc logging, environment checks, retries, and path lookups. Gungnir bundles a minimal set of those primitives with three properties:

- **One file, no build.** Distributed by URL; install with `curl` + `chmod +x`.
- **Two usage modes.** Run it as a CLI, or `source` it and call `ci::` functions directly.
- **Platform-neutral.** No GitHub Actions / GitLab / CircleCI assumptions, no `build` / `deploy` abstractions, no vendor environment variables.

## Requirements

- Bash 4+ (macOS default `/bin/bash` is 3.2 — install via `brew install bash`).
- POSIX `coreutils` (already present on Linux and macOS).
- A `sort` that supports `-V` (version sort). Required by `ci::version_gt`, `ci::version_ge`, and `ci::git_latest_tag`. Modern macOS and GNU coreutils both qualify; pre-Sequoia BSD `sort` does not. The toolkit probes once per shell and errors with a remediation hint (`brew install coreutils`) if `sort -V` is unavailable. Pre-release tag ordering follows whichever `sort -V` is on `PATH` — BSD `sort` and GNU `sort` agree on plain numeric versions but diverge on pre-release components, so pin GNU coreutils if you compare pre-release tags.
- Optional: `shellcheck` for `./scripts/lint`.

## Install in CI

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.7/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

Pin to a tag (`v0.1.7` above). The artifact is a single file with no runtime dependencies beyond Bash 4+.

## Quickstart

### CLI mode

```bash
./ci-toolkit help
./ci-toolkit version
./ci-toolkit log info "starting checks"
./ci-toolkit env require DEPLOY_TOKEN
./ci-toolkit tool require git
./ci-toolkit retry -- make test
./ci-toolkit retry 5 -- curl -fsS https://example.com/health
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

### Source mode

```bash
source ./ci-toolkit

ci::info "starting checks"
ci::require_env DEPLOY_TOKEN
ci::require_tool git
ci::retry 3 make test
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

Source mode keeps control of the caller's shell: helpers return status codes and never call `exit`.

## Examples

A worked example lives at [`examples/bun-deploy/`](examples/bun-deploy/) — a tiny Bun project with `check / build / deploy / release` scripts that compose `ci-toolkit` primitives. The deploy script defaults to a dry-run so you can run the whole pipeline without contacting a registry.

```bash
cd examples/bun-deploy

# build only (no env required)
RUN_DEPLOY=0 ./scripts/check
./scripts/build

# dry-run deploy (no real network calls)
IMAGE_TAG="$(date +%s)" \
REGISTRY_URL="ghcr.io/example" \
REGISTRY_TOKEN="dummy" \
./scripts/deploy
```

See [`examples/bun-deploy/README.md`](examples/bun-deploy/README.md) for layout, environment variables, and how to swap the deploy target (Cloudflare Workers, SSH/rsync, S3 …).

A second example, [`examples/vendored-deploy-script/`](examples/vendored-deploy-script/), is a code-reference refactor of a real ~400-line production deploy script (git-pull → build → multi-host rsync → Slack). It shows how to retrofit `ci-toolkit` into an existing script without restructuring it: which helpers to delete, which lines to substitute, and which domain logic to leave alone.

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

## CLI reference

| Command | Behavior |
| --- | --- |
| `help`, `-h`, `--help` | Print usage and exit `0`. |
| `version`, `--version` | Print `ci-toolkit <version>` to stdout. |
| `version gt LHS RHS` | Exit `0` iff `LHS > RHS` under `sort -V` semantics. Exit `1` otherwise (including equal). Requires `sort -V`. |
| `version ge LHS RHS` | Exit `0` iff `LHS >= RHS` under `sort -V` semantics. Requires `sort -V`. |
| `log <info\|warn\|error\|debug> <message>` | Write a structured log line to **stderr**. `debug` is silent unless `CI_TOOLKIT_DEBUG=1`. |
| `env require VAR_NAME` | Exit `1` if the environment variable is unset or empty. The variable's value is never printed. |
| `env default VAR_NAME DEFAULT` | Print the value of `VAR_NAME`, or `DEFAULT` if it is unset or empty. |
| `tool require TOOL_NAME` | Exit `1` if the tool is not found on `PATH`. |
| `retry [ATTEMPTS] [--delay SECONDS] -- COMMAND [ARGS...]` | Run `COMMAND` up to `ATTEMPTS` times (default `3`). `--delay` sleeps `SECONDS` between failed attempts; defaults to `0`. Returns the last attempt's exit status. |
| `eq ACTUAL EXPECTED` | Exit `0` iff `ACTUAL` string-equals `EXPECTED`. Never prints compared values. |
| `ne ACTUAL EXPECTED` | Exit `0` iff `ACTUAL` string-differs from `EXPECTED`. Never prints compared values. |
| `in VALUE CANDIDATE...` | Exit `0` iff `VALUE` string-equals any `CANDIDATE`. Literal comparison; no glob/regex. |
| `not-in VALUE CANDIDATE...` | Exit `0` iff `VALUE` matches no `CANDIDATE`. Literal comparison; no glob/regex. |
| `strip-prefix PREFIX STRING` | Print `STRING` with a leading literal `PREFIX` removed (no-op if absent). |
| `trap-err` | Source-mode only. From the CLI, prints a usage hint and exits `64`. |
| `git latest-tag [PREFIX]` | Print the latest sorted version tag starting with `PREFIX` (or any tag if blank) to stdout. Requires `sort -V`. |
| `slack webhook VAR PROJECT STATUS MSG` | Send a JSON-escaped notification to Slack using the URL stored in `VAR`. |
| `ls` | List all available `ci::` functions and their descriptions. |

Unknown commands or malformed arguments exit `64` and print usage to stderr.

## Source API reference

All functions live under the `ci::` namespace and return status codes; none of them call `exit`.

### Logging

| Function | Description |
| --- | --- |
| `ci::log LEVEL MESSAGE...` | Emit `[LEVEL] MESSAGE` to **stderr**. `LEVEL=debug` is suppressed unless `CI_TOOLKIT_DEBUG=1`. |
| `ci::info MESSAGE...` | Shortcut for `ci::log info`. |
| `ci::warn MESSAGE...` | Shortcut for `ci::log warn`. |
| `ci::error MESSAGE...` | Shortcut for `ci::log error`. |
| `ci::debug MESSAGE...` | Shortcut for `ci::log debug`. |
| `ci::die MESSAGE...` | Log at `error` and return `1`. The caller decides whether to `exit`. |

### Validation

| Function | Description |
| --- | --- |
| `ci::require_env VAR_NAME` | Return `1` if `VAR_NAME` is unset or empty. The value is never printed; only the name appears in the error message. |
| `ci::env_default VAR_NAME DEFAULT` | Set `VAR_NAME` to `DEFAULT` in the current shell if it is unset or empty. |
| `ci::is_true VAR_NAME` | Return `0` if variable is `1` or `true`. |
| `ci::require_tool TOOL_NAME` | Return `1` if `TOOL_NAME` is not resolvable via `command -v`. |

### Flow control

| Function | Description |
| --- | --- |
| `ci::retry ATTEMPTS [--delay SECONDS] [--] COMMAND...` | Run `COMMAND` up to `ATTEMPTS` times. `--delay` sleeps `SECONDS` between failed attempts (default `0`). Returns `0` on first success, otherwise returns the final attempt's exit status. Failed attempts log a `warn` line. |
| `ci::trap_err` | Install a default `ERR` trap that prints exit code, file:line, function, and `BASH_COMMAND` to **stderr**. Sets `set -E` so the trap inherits into shell functions. Source-mode only — the CLI command exits `64` with a hint. |

### String predicates

| Function | Description |
| --- | --- |
| `ci::eq ACTUAL EXPECTED` | Return `0` iff `ACTUAL == EXPECTED` (literal Bash string equality). Never prints compared values; usage error returns `64`. |
| `ci::ne ACTUAL EXPECTED` | Return `0` iff `ACTUAL != EXPECTED`. Never prints compared values; usage error returns `64`. |
| `ci::in VALUE CANDIDATE...` | Return `0` iff `VALUE` string-equals any `CANDIDATE`. Literal comparison; no glob/regex. Usage error (fewer than 2 args) returns `64`. |
| `ci::not_in VALUE CANDIDATE...` | Return `0` iff `VALUE` matches none of the `CANDIDATE` arguments. Literal comparison; no glob/regex. Usage error returns `64`. |

### Strings & versions

| Function | Description |
| --- | --- |
| `ci::strip_prefix PREFIX VALUE` | Print `VALUE` with a leading literal `PREFIX` removed; passes through unchanged if the prefix is absent. |
| `ci::version_gt LHS RHS` | Return `0` iff `LHS > RHS` under `sort -V` semantics; `1` otherwise (including equal). Returns `64` on usage error and `1` if `sort -V` is unavailable. |
| `ci::version_ge LHS RHS` | Return `0` iff `LHS >= RHS`. Equal pairs short-circuit before any `sort -V` probe. |

### Paths

| Function | Description |
| --- | --- |
| `ci::find_up MARKER` | Walk up from `$PWD` toward `/` looking for an entry named `MARKER`. Print the matching directory to **stdout** on success, return `1` if no match. |
| `ci::root` | Equivalent to `ci::find_up .git`. |
| `ci::git_latest_tag [PREFIX]` | Print the latest sorted version tag starting with `PREFIX` to **stdout**. Returns `1` if no match or `sort -V` is unavailable. |
| `ci::slack_webhook VAR PROJ STAT MSG` | Send a best-effort, JSON-escaped Slack notification. Skips gracefully if `VAR` is unset or `curl` is missing. |
| `ci::ls` | Print all available `ci::` functions and their descriptions to **stdout**. |

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success. |
| `1` | A check failed (missing env / missing tool / retries exhausted / marker not found). |
| `64` | Usage error (unknown subcommand or malformed arguments). Modelled after `sysexits.h` `EX_USAGE`. |

## Environment variables

| Variable | Effect |
| --- | --- |
| `CI_TOOLKIT_DEBUG=1` | Enable `debug`-level log output on stderr. Default: off. |

## Conventions

These conventions are part of the toolkit's contract — preserve them when contributing.

- **stderr for logs, stdout for data.** `ci::log` writes to stderr. Helpers that return a value (such as `ci::find_up`) write that value to stdout so it can be captured by `$(...)` without log noise.
- **Status codes, not `exit`.** Source-mode callers stay in control of their shell. Functions return; they do not terminate the parent process.
- **No secret leakage.** Validation helpers report variable **names**, never values. Tests assert that secret values do not appear in stderr.
- **Platform-neutral.** No CI vendor variables (`GITHUB_*`, `GITLAB_*`, `CIRCLE_*`) and no `build` / `deploy` command abstractions. CI workflows compose the toolkit; the toolkit does not encode workflow opinions.

## Development

```bash
./scripts/test     # run all Bash behavior tests
./scripts/lint     # ShellCheck if installed; skips with a clear notice otherwise
./scripts/smoke    # exercise CLI + source mode against the real artifact
```

Run a single test file directly:

```bash
bash tests/test_retry_and_paths.sh
```

`scripts/test` is a thin loop over `tests/test_*.sh` and stops at the first failure because `set -euo pipefail` is on.

### Adding a feature

Follow the file's section flow:

1. **Library function** — add `ci::your_feature` in the library section. Return status codes; do not `exit`. Include a `# @description` comment above the function.
2. **Command wrapper** — add `ci::cmd_your_feature` that adapts argv, returning `64` on usage errors.
3. **Dispatch arm** — register the command in `ci::dispatch`'s `case` statement.
4. **Usage** — update `ci::usage` so `ci-toolkit help` lists the new command.
5. **Tests** — add a `tests/test_*.sh` that exercises both source mode (`source ci-toolkit; ci::your_feature`) and CLI mode (`./ci-toolkit your-feature`). Write the failing test first, then implement.

## Release readiness

`scripts/release-check` runs the verification pass used before tagging a
release. It exposes individual checks plus an aggregate pipeline:

```bash
./scripts/release-check version      # CI_TOOLKIT_VERSION vs CHANGELOG.md
./scripts/release-check artifact     # executable bit, Bash marker, README URL
./scripts/release-check boundary     # platform-neutral guardrails
./scripts/release-check descriptions # every public ci:: function has # @description
./scripts/release-check copy-smoke   # standalone single-file distribution
./scripts/release-check gates        # tests, lint, smoke, user-docs alignment
./scripts/release-check all          # everything above
```

The most recent release-readiness record lives under
`docs/superpowers/release-readiness/`.

## Project layout

```
.
├── ci-toolkit              # the artifact (CLI + sourceable library)
├── scripts/
│   ├── test                # runs every tests/test_*.sh
│   ├── lint                # optional ShellCheck pass
│   ├── smoke               # end-to-end CLI + source smoke checks
│   └── release-check       # pre-tag verification harness
├── tests/
│   ├── assert.sh           # shared assertion helpers
│   └── test_*.sh           # behavior tests per feature group
├── docs/
│   └── superpowers/
│       ├── specs/             # design contracts
│       ├── plans/             # executed implementation plans
│       └── release-readiness/ # per-version release-readiness records
├── examples/
│   ├── bun-deploy/             # runnable example: Bun build + dry-run docker deploy
│   └── vendored-deploy-script/ # code-reference: retrofit ci-toolkit into a vendored deploy script
├── AGENTS.md               # guidance for AI coding agents
├── CLAUDE.md               # imports AGENTS.md for Claude Code
├── CHANGELOG.md            # source of truth for release notes
└── README.md               # this file
```

## Versioning

- `CHANGELOG.md` is the source of truth for release notes.
- The `CI_TOOLKIT_VERSION` constant at the top of `ci-toolkit` must match the latest `CHANGELOG.md` entry.
- While the project is experimental, breaking changes can land in minor releases. Pin to an exact tag in CI.

## References

- Design contract: `docs/superpowers/specs/2026-05-12-ci-bash-toolkit-design.md`
- Executed plan: `docs/superpowers/plans/2026-05-12-ci-bash-toolkit.md`
- Agent guidance: `AGENTS.md`
- Release notes: `CHANGELOG.md`
