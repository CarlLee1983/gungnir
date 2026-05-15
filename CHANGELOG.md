# Changelog

## v0.1.10 - require_match invalid-regex hardening

- `ci::require_match` (and the matching `ci-toolkit match require` CLI command) now wrap the case where `REGEX` is unparseable. Previously Bash leaked its native `[[: invalid regular expression` message to stderr before the toolkit error, and the helper returned `1` (validation failure). It now probes the regex once with stderr suppressed; on parse failure (status `2`) it emits `[error] invalid regex for NAME` and returns `64` (usage error). Valid regex paths — including the no-match case — are unchanged.
- Added regression coverage in `tests/test_validation_helpers.sh` for both source mode and CLI mode: status `64`, stderr contains `invalid regex`, stderr does not contain Bash's native `invalid regular expression`, `VALUE` never appears in stderr.

## v0.1.9 - Validation and shell-join helpers

- Added four public validation helpers: `ci::require_file NAME PATH [HINT]`, `ci::require_dir NAME PATH [HINT]`, `ci::require_match NAME VALUE REGEX [DESCRIPTION]`, and `ci::require_uint NAME VALUE`. All four return `0` on success, `1` on validation failure (stderr names `NAME` and, for `require_match`, the rule description or raw regex), and `64` on usage error. They never echo `VALUE` or `PATH` into stderr, which keeps them safe for sensitive inputs.
- Added `ci::shell_join ARG...` data helper that prints argv as a Bash-escaped command string via `printf '%q'`. Stdout is shell-escaped (Bash-specific, not POSIX-sh portable) and ends in a single trailing newline. Zero args returns `64`. Intended for adapters like `rsync -e` that require a command string instead of an argv array.
- Added matching nested CLI commands `ci-toolkit file require`, `ci-toolkit dir require`, `ci-toolkit match require`, `ci-toolkit uint require`, and `ci-toolkit shell join` as thin wrappers over the source-mode helpers. All preserve source-mode status codes and never leak rejected values.
- Added `tests/test_validation_helpers.sh` covering source mode and CLI mode for all four `require_*` helpers, including no-leak assertions for `require_match` and `require_uint`. Added `tests/test_shell_join.sh` covering source/CLI round-trip of argv containing spaces, quotes, backslashes, glob characters, and empty strings, plus zero-arg usage error. `scripts/smoke` now also runs one `uint require` and one `shell join` check against the real artifact.

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
