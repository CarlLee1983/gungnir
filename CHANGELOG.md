# Changelog

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
