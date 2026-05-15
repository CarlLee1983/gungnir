# Changelog

## v0.1.8 - String predicate helpers

- Added four public string predicate helpers: `ci::eq ACTUAL EXPECTED`, `ci::ne ACTUAL EXPECTED`, `ci::in VALUE CANDIDATE...`, and `ci::not_in VALUE CANDIDATE...`. All four return status codes only; they never `exit`, never print compared values (safe for sensitive inputs), and never write to stdout on normal predicate evaluation. Usage errors return `64` via `ci::error` and print only the helper name in the usage line.
- Added matching CLI commands `ci-toolkit eq`, `ci-toolkit ne`, `ci-toolkit in`, and `ci-toolkit not-in` as thin wrappers over the source-mode helpers. Dispatch maps the dashed `not-in` command to `ci::not_in`. CLI commands return the same status codes (`0`, `1`, `64`) and emit no stdout on predicate success or failure.
- Behavior contract: comparisons are literal Bash string equality with no glob, regex, or case folding. Empty strings are valid values for all four helpers (`ci::eq "" ""` exits `0`, `ci::in "" "" x` exits `0`).
- Added `tests/test_string_predicates.sh` covering source mode (eq/ne/in/not_in success, failure, empty-string, usage error) and CLI mode (eq/ne/in/not-in success, failure, usage error). `scripts/smoke` now also runs one `eq`, one `in`, and one `not-in` check against the real artifact.

## v0.1.7 - Hardened helpers and release-check

- `ci::slack_webhook` now JSON-escapes `\`, `"`, `\n`, `\r`, and `\t` in `PROJECT`, `STATUS`, and `MESSAGE` before posting. Previously a quote or backslash in the message produced invalid JSON and the Slack webhook rejected the call. Added regression tests in `tests/test_slack_webhook.sh`.
- Made the `sort -V` dependency explicit. `ci::version_gt`, `ci::version_ge`, and `ci::git_latest_tag` now probe once per shell via the new private helper `ci::_require_sort_v` and return `1` with a remediation hint (`brew install coreutils`) when `sort -V` is unavailable. `ci::ls` now also hides `ci::_*` private helpers from discovery output.
- Added `release-check examples` (and wired it into `release-check all`). Scans `examples/**/*.{md,sh}` for `releases/download/vX.Y.Z/ci-toolkit` URLs and `Vendor Gungnir ci-toolkit vX.Y.Z` commit-message strings, failing if any pin diverges from `CI_TOOLKIT_VERSION`.
- README and the Laravel blue-green example now document the helpers that landed in v0.1.6 (`ci::version_gt`, `ci::version_ge`, `ci::strip_prefix`, `ci::trap_err`). The Laravel example deletes its temporary `strip_tag_prefix` / `compare_versions_or_exit` helpers and calls the real `ci::*` helpers directly; `compose_err_trap` stays project-local because `ci::trap_err` is intentionally callback-less.

## v0.1.6 - Added utility helpers

- Added `ci::version_gt` and `ci::version_ge` helpers for semver-style comparison, backed by `sort -V`. Accepts `vX.Y.Z`, `X.Y.Z`, `X.Y`, and simple pre-release tags. CLI: `ci-toolkit version gt LHS RHS` / `ci-toolkit version ge LHS RHS` — the no-arg `version` form is preserved.
- Added `ci::strip_prefix PREFIX STRING` and `ci-toolkit strip-prefix` for literal prefix removal. Returns the original string unchanged when the prefix is absent; glob-character prefixes (`*`, `?`, `[abc]`) are treated literally.
- Added `ci::trap_err` (source mode only) which enables `set -E` and installs a default ERR trap printing `exit code`, `file:line`, function, and `BASH_COMMAND`. Leaves `set -e/-u/pipefail` untouched. `ci-toolkit trap-err` (CLI) is an informational stub — see source mode.

### Known limitations

- `set -E` does not propagate `ERR` into every command-substitution subshell in older Bash builds; this is a Bash quirk, not a toolkit issue.
- `ci::trap_err` replaces any previously installed `ERR` trap (standard Bash `trap` semantics).

## v0.1.5 - Added retry delay

- Added `--delay SECONDS` flag to `ci::retry` (source mode) and `ci-toolkit retry` (CLI mode). Sleeps between failed attempts only; never before the first attempt and never after the last.
- Preserves every existing call site's behavior. `--delay 0` and the omit-`--delay` path emit identical syscalls.
- Retrofitted `examples/laravel-bluegreen-deploy/run_composer_install` to use `ci::retry 2 --delay 30 -- composer install ...`.

## v0.1.4 - Added Toolkit Self-Documentation

- Added `ci::ls` helper to list all available public functions and their descriptions.
- Added `ls` CLI command for quick toolkit discovery.
- Added standardized documentation comments to all core functions.

## v0.1.3 - Added Semantic Boolean Helper
 
- Added `ci::is_true` helper to check if an environment variable is "1" or "true".
 
## v0.1.2 - Added Environment Defaulting

- Added `ci::env_default` helper to provide semantic defaults for environment variables.
- Added `env default` CLI command to print variable values or fallbacks.

## v0.1.1 - Added Git and Slack helpers

- Added `ci::git_latest_tag` helper to find the latest version tag by prefix.
- Added `ci::slack_webhook` helper for best-effort CI notifications.
- Added `git latest-tag` and `slack webhook` CLI commands.
- Refactored `examples/vendored-deploy-script/deploy-prod.sh` to use new helpers and modular structure.
- Added behavior tests for new helpers.


## v0.1.0 - Experimental initial release

- Added single-file `ci-toolkit` artifact for CLI and source API usage.
- Added logging helpers: `ci::info`, `ci::warn`, `ci::error`, and `ci::debug`.
- Added `ci::die` failure helper.
- Added environment validation through `ci::require_env` and `ci-toolkit env require`.
- Added tool validation through `ci::require_tool` and `ci-toolkit tool require`.
- Added retry support through `ci::retry` and `ci-toolkit retry --`.
- Added custom CLI retry attempts through `ci-toolkit retry ATTEMPTS --`.
- Added path helpers `ci::find_up` and `ci::root`.
- Added Bash behavior tests, optional ShellCheck linting, and smoke checks.
- Added release artifact checks for executability, Bash runtime markers, and README install URL consistency.

### Breaking changes

None. This is the first experimental release.
