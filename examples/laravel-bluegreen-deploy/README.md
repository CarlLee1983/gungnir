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
| L89 `trap 'send_slack_notification failed ...' ERR` | `compose_err_trap '...'` — local helper retained because this script needs a custom Slack callback; the toolkit's callback-less `ci::trap_err` is too narrow here |
| L92 `cd $PROJECT_DIR` (no check) | `ci::require_env PROJECT_DIR \|\| exit 1; cd "$PROJECT_DIR"` |
| L99 `git describe --tags --abbrev=0` | preserved (different semantics from "latest matching tag") |
| L102-104 `git fetch origin` / `git fetch --tags` / `git pull` | each wrapped in `ci::retry 3 ...` |
| L107 `git tag -l "${TAG_PREFIX}*" \| sort -V \| tail -n1` | `ci::git_latest_tag "$TAG_PREFIX"` |
| L111-112 `${VAR#$PREFIX}` (4 sites) | `ci::strip_prefix "$TAG_PREFIX" "$VAR"` (landed in v0.1.6) |
| L115-119 version compare + exit | `ci::version_gt "$new" "$current" \|\| ci::die "..."` (landed in v0.1.6) |
| L128-129 `/usr/local/bin/composer` + env | `ci::require_tool composer`; path resolved via PATH |
| L132-136 composer install + `sleep 30` + retry | `ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader` (landed in v0.1.5) |
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
| `compose_err_trap` | The toolkit's `ci::trap_err` is a callback-less default printer; this script needs to invoke `send_slack_notification` on failure, so the local helper stays. |
| `sanitize_cloudwatch_token` | CloudWatch-specific naming policy (spec §6.3 not-collected). |
| `compute_cloudwatch_log_group` | Same as above (spec §6.4 not-collected). |
| `parse_blue_green_target_dir` | Blue/green flip is deployment-strategy policy. |
| `deploy_files_to_host` | rsync flag policy (`--rsync-path="sudo rsync"`, storage-aware excludes). |
| `run_post_deploy_on_host` | SSH heredoc + artisan + supervisord is application-level Laravel policy. |
| `run_multi_host_deploy` | Multi-host topology iteration is project policy. |

## ci-toolkit API proposals surfaced by this retrofit

While rewriting, four high-ROI helpers stood out. Three have since landed in the toolkit; one (`ci::trap_err`) landed in a narrower form than the original proposal.

1. **`ci::retry --delay SECONDS`** (spec §5.1) — **landed in v0.1.5.** Adds an inter-attempt sleep to `ci::retry`; covers packagist/npm-registry transient failures. `run_composer_install` uses it.
2. **`ci::version_gt A B` / `ci::version_ge A B`** (spec §5.2) — **landed in v0.1.6.** `sort -V` wrapper for tag-prefix release flows. `resolve_target_tag` uses `ci::version_gt` directly.
3. **`ci::strip_prefix PREFIX VALUE`** (spec §5.3) — **landed in v0.1.6.** Used in `send_slack_notification` and `resolve_target_tag`; argument order is `(prefix, value)`, not the original proposal's `(value, prefix)`.
4. **`ci::trap_err`** (spec §5.4) — **landed in v0.1.6, callback-less.** The shipped helper installs a default `set -E` + ERR trap that prints exit code, file:line, function, and `BASH_COMMAND`. It does not accept a callback, so this script's `compose_err_trap` (which dispatches to `send_slack_notification`) stays local.

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
   curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.8/ci-toolkit \
       -o infra/ci/ci-toolkit
   chmod +x infra/ci/ci-toolkit
   git add infra/ci/ci-toolkit
   git commit -m "chore: [ci] Vendor Gungnir ci-toolkit v0.1.8"
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
