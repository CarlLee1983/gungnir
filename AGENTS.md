# AGENTS.md

Guidance for AI coding agents working in this repository. The same content is imported by `CLAUDE.md` for Claude Code.

## What this repo is

Gungnir ships a single experimental Bash artifact (`ci-toolkit`) that doubles as a CLI and as a sourceable `ci::` function library for CI scripts. There is no build step and no compiled output — the toolkit is the artifact, distributed via `curl` + `chmod +x`.

The design contract lives in `docs/superpowers/specs/2026-05-12-ci-bash-toolkit-design.md`; the executed implementation plan is `docs/superpowers/plans/2026-05-12-ci-bash-toolkit.md`. Read those before changing the shape of the toolkit.

## Quality gates

```bash
./scripts/test     # all Bash behavior tests
./scripts/lint     # ShellCheck if installed; skips with a clear notice otherwise
./scripts/smoke    # exercises CLI + source mode against the real artifact
```

Run a single test file directly:

```bash
bash tests/test_retry_and_paths.sh
```

`scripts/test` is a thin loop over `tests/test_*.sh`; tests stop at the first failing file because `set -euo pipefail` is on.

## Runtime requirement

Bash 4+. macOS default `/bin/bash` is 3.2 and trips on `set -u` with empty arrays inside the test harness. Install via `brew install bash` so `/usr/bin/env bash` resolves to `/opt/homebrew/bin/bash`.

`ci::version_gt`, `ci::version_ge`, and `ci::git_latest_tag` require a `sort` that implements `-V` (version sort). `ci::_require_sort_v` probes once per shell and returns `1` with a remediation hint if the contract is unmet. If you add a helper that depends on a non-portable coreutil flag, gate it behind a similar `ci::_require_*` probe (private; `ci::_*` names are filtered out of `ci-toolkit ls`) and add a `tests/test_*_contract.sh` covering both available and missing paths.

## Architecture: one file, three sections, two modes

`ci-toolkit` is organized as:

1. **Library section** — `ci::` namespaced functions (`ci::log`, `ci::info`, `ci::warn`, `ci::error`, `ci::debug`, `ci::die`, `ci::require_env`, `ci::require_tool`, `ci::retry`, `ci::find_up`, `ci::root`). These return status codes; they do not `exit` so that `source` callers retain control of their shell.
2. **Command section** — `ci::cmd_*` wrappers that adapt argv to library calls and return `64` on usage errors.
3. **Dispatch section** — only runs when the file is executed directly. Guarded by `[[ "${BASH_SOURCE[0]}" == "$0" ]]`.

When adding a feature, follow that flow: library function first (with a `# @description` comment), then CLI command wrapper, then a `case` arm in `ci::dispatch`, then update `ci::usage`.

## Conventions to preserve

- **Platform-neutral**: no GitHub Actions / GitLab / CircleCI variables, no `build`/`deploy` command abstractions. Plan Task 7 Step 3 enforces this with a grep.
- **No secret leakage**: validation helpers report variable *names*, never values. Tests assert that secret values do not appear in stderr.
- **Stderr for logs, stdout for data**: `ci::log` writes to stderr; helpers that return a path (e.g. `ci::find_up`) write the path to stdout.
- **TDD by behavior**: every helper has a `tests/test_*.sh` that exercises both source mode (`source ci-toolkit; ci::foo`) and CLI mode (`./ci-toolkit foo`) where applicable. Add the failing test first, then the implementation.
- **Modular Scripts**: Orchestration scripts (like those in `examples/`) should use a `main()` entry point and a `run_xxx()` function structure. Avoid top-level execution logic.
- **Self-Documentation**: All public `ci::` functions must have a `# @description` comment immediately above the function definition for discovery via `ci-toolkit ls`.

## Test harness

`tests/assert.sh` provides `assert_eq`, `assert_status`, `assert_contains`, `assert_not_contains`, `make_temp_dir`, `finish_tests`. Each test file defines a local `run_capture` that captures stdout/stderr/status into `RUN_STDOUT` / `RUN_STDERR` / `RUN_STATUS`. `make_temp_dir` is called inside `$(...)` so tmpdir cleanup is best-effort; tests must not rely on it for correctness.

## Release shape

Single file, distributed by URL. `CHANGELOG.md` is the source of truth for version notes; the `CI_TOOLKIT_VERSION` constant at the top of `ci-toolkit` must match the latest CHANGELOG entry.
