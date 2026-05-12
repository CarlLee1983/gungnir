# CI Bash Toolkit Design

Date: 2026-05-12
Status: Approved design, experimental first implementation

## Context

`/Users/carl/Dev/CMG/Gungnir` currently contains only OMX runtime state and is not yet a source repository. This design treats Gungnir as a new independently publishable CI Bash toolkit project rather than a refactor of existing CI files.

## Goal

Create an independently publishable, platform-neutral Bash toolkit that consolidates reusable CI shell patterns into one curl-installable artifact. The first implementation is experimental: it should optimize for fast validation across real CI scripts while keeping the shape clean enough to stabilize later with semantic versioning.

## Non-goals

- Do not bind the first version to GitHub Actions, GitLab CI, CircleCI, or another CI-specific API.
- Do not provide stable `build`, `test`, `lint`, `deploy`, or release abstractions in the first version.
- Do not require `jq` or other non-core runtime dependencies unless a specific command checks for them first.
- Do not introduce a plugin system or config-file framework in the first version.
- Do not support POSIX `sh`; Bash is the runtime boundary.

## Architecture

The published artifact is a single executable file named `ci-toolkit`. The same file supports two modes:

1. CLI mode: execute the file directly, for example `./ci-toolkit retry -- make test`.
2. Source API mode: source the same file from Bash, then call namespaced functions such as `ci::retry`, `ci::log`, or `ci::require_env`.

The file should be internally organized into three sections:

- Library section: reusable `ci::` functions.
- Command section: CLI subcommands that wrap library behavior.
- Dispatch section: argument parsing and command dispatch that runs only when the file is executed directly.

When sourced, the dispatch section must not run. When executed directly, the dispatch section owns process-level exits.

## First-version feature scope

The first version focuses on CI foundation helpers.

### Logging

Provide reusable logging helpers:

- `ci::info`
- `ci::warn`
- `ci::error`
- `ci::debug`

The CLI exposes equivalent behavior through `ci-toolkit log <level> <message>`. Debug output is enabled with `CI_TOOLKIT_DEBUG=1`.

### Failure helpers

Provide `ci::die "message"` for consistent failure formatting. In source mode, helpers should avoid unexpectedly exiting the caller unless the function contract explicitly says it terminates. Most library functions should communicate failure through status codes.

### Environment validation

Provide `ci::require_env VAR_NAME` and `ci-toolkit env require VAR_NAME`.

The helper reports missing variable names but never prints variable values, so secrets are not leaked into CI logs.

### Tool detection

Provide `ci::require_tool <name>` and `ci-toolkit tool require <name>`.

Any future helper that depends on optional tools such as `jq`, `git`, or `curl` must check availability explicitly.

### Retry

Provide `ci::retry <attempts> <command...>` and `ci-toolkit retry -- <command...>`.

Retry should preserve the wrapped command's stdout and stderr. It should print concise attempt status to stderr and return the wrapped command's final status when all attempts fail. Fixed delay is enough for the first version; exponential backoff can remain experimental or be deferred.

### Path helpers

Provide simple helpers such as `ci::find_up` and `ci::root` for locating a repository root or marker file from nested directories.

### Help and version

Provide:

- `ci-toolkit help`
- `ci-toolkit version`

The artifact header should include version, experimental notice, Bash expectation, and examples for execute vs source usage.

## Installation and versioning

The primary CI consumption path is curl + pinned version:

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.0/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

Versioning uses two tracks:

- Recommended CI usage pins a release tag such as `v0.1.0`.
- Early adopters may pin a commit SHA or nightly artifact.

The first version is experimental. CLI and source APIs may change, but each release should include a short changelog. Breaking changes are allowed during the experimental phase, but release notes must call them out explicitly. Documentation should recommend pinning release tags rather than tracking `main`.

## Runtime compatibility

- Bash 4+ is the target runtime.
- Platform-neutral behavior is the default.
- Common tools such as `git`, `curl`, and `mktemp` may be used only where checked or clearly documented.
- The toolkit must not depend on CI-specific environment variables for core behavior.

## Error handling and side effects

Error behavior should be CI-friendly and predictable:

- Failure messages go to stderr.
- CLI argument errors return usage text plus a non-zero exit status.
- `require_env` reports variable names only, not values.
- `retry` reports attempts without rewriting the wrapped command's output streams.
- Source-mode functions should use return statuses where practical instead of exiting the caller shell.
- CLI dispatch may exit because it owns the process.
- The toolkit should not mutate CI platform state, such as writing to GitHub Actions output or env files.

## Data flow

```text
CI script
  -> download pinned ci-toolkit
  -> chmod +x
  -> call CLI or source API
  -> helpers run validation/log/retry behavior
  -> exit status returns to CI runner
```

## Testing and quality strategy

Use a small Bash test harness for the first version. Do not require `bats-core` initially; consider it later only if the test suite grows enough to justify it.

Required behavior tests:

- `ci::require_env` fails for missing variables and does not leak values.
- `ci::require_tool` fails when a tool is unavailable.
- `ci::retry` retries, eventually succeeds when a later attempt passes, and returns the final failing status when all attempts fail.
- Sourcing `ci-toolkit` does not run CLI dispatch.
- Executing `ci-toolkit` enters subcommand dispatch.

Required smoke checks:

- `./ci-toolkit help`
- `./ci-toolkit version`
- `source ./ci-toolkit && ci::info "ok"`

Quality checks:

- Use `shellcheck` as a development-time lint check.
- Release checks should run tests, shellcheck, and smoke checks.
- The release artifact must be executable after curl/download without requiring a build step in consuming CI jobs.

## Future evolution

If the single file grows too large, the project can later move to multi-file source organization with a release-time bundling step. The public artifact should remain a single `ci-toolkit` file unless there is a strong reason to change the consumption model.

Task command abstractions such as `build`, `test`, `lint`, or `deploy` should be introduced only after repeated usage patterns prove stable across repositories.
