# Vendored deploy script

A code-reference example showing how to retrofit Gungnir `ci-toolkit` into an existing ~400-line production deploy script — the kind that's already in many real projects: pulls latest git ref, runs a project-local `build.sh`, rsyncs to one or more remote hosts, posts to Slack.

Unlike [`bun-deploy/`](../bun-deploy/), this example is **not end-to-end runnable** from inside the directory. It exists so you can read it side-by-side with your own script and copy the substitutions. The referenced `build.sh`, `deploy.sh`, and `sync-env-to-shared.sh` belong to the target project, not to the example.

## Layout

```
examples/vendored-deploy-script/
├── ci-toolkit       -> ../../ci-toolkit  (symlink; in a real project, vendor a real copy)
├── deploy-prod.sh   (the refactored script — sources ci-toolkit from the same dir)
└── README.md
```

The "vendored next to the script" pattern matches how this is typically deployed in practice: drop a pinned `ci-toolkit` next to your existing deploy script and source it.

```bash
# in your project
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.0/ci-toolkit \
    -o infra/ci/ci-toolkit
chmod +x infra/ci/ci-toolkit
```

Then in `deploy-prod.sh`:
```bash
source "$SCRIPT_DIR/ci-toolkit"
```

## What `ci-toolkit` replaces

| Before (hand-written) | After (ci-toolkit) |
| --- | --- |
| `info() { echo "[deploy] $*"; }` | `ci::info "..."` |
| `warn() { echo "[deploy] WARN: $*" >&2; }` | `ci::warn "..."` |
| `fatal() { echo "[deploy] $*" >&2; exit 1; }` | `ci::die "..." || exit 1` |
| `command -v git \|\| fatal "..."` | `ci::require_tool git \|\| exit 1` |
| `[ -z "${BUILD_BRANCH:-}" ] && fatal "..."` | `ci::require_env BUILD_BRANCH \|\| exit 1` |
| `git fetch origin --quiet --prune` | `ci::retry 3 git fetch origin --quiet --prune` |
| `git pull --ff-only origin "$BUILD_BRANCH"` | `ci::retry 3 git pull --ff-only origin "$BUILD_BRANCH"` |
| `curl ... "$SLACK_WEBHOOK_URL"` | `ci::retry 3 curl ... "$SLACK_WEBHOOK_URL" \|\| true` |

Net effect: about **30% fewer lines**, identical behavior, and network operations automatically retry on transient failures.

## What stays project-local

These are deliberately **not** delegated to the toolkit — they encode project-specific policy, not generic CI primitives.

| Function in `deploy-prod.sh` | Why it stays |
| --- | --- |
| `is_project_root`, `resolve_repo_root`, `discover_build_repo` | Project-specific markers (`.git` + `infra/ci/build.sh`). `ci::find_up` only matches a single marker. |
| `parse_sample_cli` (`--dry-run`, `--skip-verify`) | The toolkit does not parse CLI flags; that's an application concern. |
| `checkout_latest_matching_tag` | Tag-selection policy is project-specific (sort, prefix, fallback). |
| `validate_deploy_user_host` | Format constraints (`user@host`, regex) are policy. |
| `run_deploy_if_requested` (multi-host loop, dry-run mapping) | Iteration policy and env mapping between `SAMPLE_DEPLOY_DRY_RUN` and `DEPLOY_DRY_RUN` are project-specific. |
| `slack_notify` | Message format and webhook policy are project-specific. The toolkit only retries the underlying `curl`. |

## How to adopt the pattern in your project

1. **Vendor the toolkit** next to your deploy script:
   ```bash
   curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.0/ci-toolkit \
       -o infra/ci/ci-toolkit
   chmod +x infra/ci/ci-toolkit
   git add infra/ci/ci-toolkit
   git commit -m "chore: [ci] Vendor Gungnir ci-toolkit v0.1.0"
   ```
2. **Source it** at the top of your deploy script:
   ```bash
   readonly SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
   source "$SCRIPT_DIR/ci-toolkit"
   ```
3. **Delete** any `info / warn / fatal / log` helpers you hand-wrote.
4. **Substitute** the table above mechanically.
5. **Wrap network ops** (`git fetch`, `git pull`, `curl`, `rsync`, registry pushes) with `ci::retry 3 ...`.
6. **Verify**: `bash -n deploy-prod.sh` and a dry-run pass should still succeed; your CI's existing logs will gain `[info]/[warn]/[error]` prefixes.

## Environment variables (illustrative)

The script uses the same variables as the original it was refactored from. Examples — not all required at once:

| Variable | Purpose |
| --- | --- |
| `BUILD_REPO` | Absolute path to the project clone to operate on. |
| `BUILD_BRANCH` | Branch to checkout + pull (required unless `BUILD_CHECKOUT_LATEST_TAG=1`). |
| `BUILD_CHECKOUT_LATEST_TAG` | Set to `1` to deploy from the latest tag matching `GIT_TAG_PREFIX`. |
| `GIT_TAG_PREFIX` | Tag-prefix filter (e.g. `release-v`). |
| `BUILD_SKIP_VERIFY` | Pass `--skip-verify` to `build.sh`. |
| `DO_DEPLOY` | Set to `1` to invoke `deploy.sh` after build. |
| `DEPLOY_HOST` / `DEPLOY_TARGETS` | Single host, or space-separated `user@host` list. |
| `DEPLOY_SSH_KEY` | Path to the SSH private key (file must be readable). |
| `SYNC_ENV_TO_SHARED` | Set to `1` to run `sync-env-to-shared.sh` before each deploy. |
| `SLACK_WEBHOOK_URL` | If set, post a success message after a real deploy. |
| `CI_TOOLKIT_DEBUG` | Set to `1` to show `ci::debug` log lines from the toolkit. |
