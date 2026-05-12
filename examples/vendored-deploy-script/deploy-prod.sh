#!/usr/bin/env bash
# deploy-prod.sh — production deploy script that vendors Gungnir ci-toolkit.
#
# Pattern: a single script on a CI / build host runs:
#   git fetch + checkout → build.sh → optional rsync deploy to one or more
#   remote hosts → optional Slack notification.
#
# This file is a worked example showing how to retrofit ci-toolkit into an
# existing ~400-line deploy script. Domain logic (repo discovery, tag mode,
# multi-host targets, dry-run mapping, Slack) is preserved as-is; only the
# logging/env/tool/retry boilerplate is delegated to the toolkit.
#
# Required co-located files (relative to this script):
#   ci-toolkit                                  # vendored from Gungnir
#   $BUILD_REPO/infra/ci/build.sh               # project's own build script
#   $BUILD_REPO/infra/ci/deploy.sh              # project's own deploy script
#   $BUILD_REPO/infra/ci/sync-env-to-shared.sh  # optional, if SYNC_ENV_TO_SHARED=1
#
# In a real project, vendor ci-toolkit once:
#   curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.0/ci-toolkit \
#       -o infra/ci/ci-toolkit && chmod +x infra/ci/ci-toolkit
#
# Full env/CLI documentation is intentionally trimmed; see the repo it ships
# with for the long-form header. Behavior is identical to the original script.

set -euo pipefail

# --- 佈署機專用 (預設保持註解；本機若要 deploy 再取消註解) ---------------------
# DO_DEPLOY=1
# DEPLOY_TARGETS="deploy@host1.example.com deploy@host2.example.com"
# DEPLOY_SSH_KEY="$HOME/.ssh/my_deploy_key.pem"
# DEPLOY_DEST_ROOT=/var/www/my-app
# DEPLOY_SERVICE_NAME=my-app
# DEPLOY_RELEASE_RETAIN_COUNT=10
# REPO_FOLDER=production
# SYNC_ENV_TO_SHARED=1
# SLACK_PROJECT_NAME=my-app
# ---------------------------------------------------------------------------

readonly SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_FOLDER="${REPO_FOLDER:-production}"
readonly BUILD_REPO_DEFAULT="$SCRIPT_DIR/$REPO_FOLDER"

# Load ci-toolkit from the same directory as this script (vendored pattern).
# shellcheck source=./ci-toolkit
source "$SCRIPT_DIR/ci-toolkit"

DISCOVER_ARGS=()

sample_print_usage() {
    cat <<'USAGE' >&2
Usage: deploy-prod.sh [options] [repo dir]

Options:
  --dry-run     With DO_DEPLOY=1, run rsync in dry-run mode (DEPLOY_DRY_RUN=1).
  --skip-verify Pass --skip-verify to build.sh.
  -h, --help    Show this help.
USAGE
}

parse_sample_cli() {
    local -a rest=()
    SAMPLE_DEPLOY_DRY_RUN="${SAMPLE_DEPLOY_DRY_RUN:-0}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)     SAMPLE_DEPLOY_DRY_RUN=1 ;;
            --skip-verify) BUILD_SKIP_VERIFY=1 ;;
            -h|--help)     sample_print_usage; exit 0 ;;
            *)             rest+=("$1") ;;
        esac
        shift
    done
    DISCOVER_ARGS=("${rest[@]}")
    export SAMPLE_DEPLOY_DRY_RUN
    export BUILD_SKIP_VERIFY
}

# Project-specific marker (kept verbatim from the original): a project root
# has both `.git` and `infra/ci/build.sh`. ci::find_up could match a single
# marker, but two-marker logic stays project-local.
is_project_root() {
    [ -d "$1/.git" ] && [ -f "$1/infra/ci/build.sh" ]
}

resolve_repo_root() {
    local dir
    dir=$(cd "$1" && pwd)
    while true; do
        if is_project_root "$dir"; then printf '%s\n' "$dir"; return 0; fi
        [ "$dir" = "/" ] && return 1
        dir=$(cd "$dir/.." && pwd)
    done
}

discover_build_repo() {
    local resolved
    if [ -n "${BUILD_REPO:-}" ]; then return 0; fi
    if [ "${1:-}" != "" ] && [ -d "$1" ]; then
        BUILD_REPO=$(cd "$1" && pwd); return 0
    fi
    if is_project_root "$BUILD_REPO_DEFAULT"; then
        BUILD_REPO=$(cd "$BUILD_REPO_DEFAULT" && pwd); return 0
    fi
    if resolved=$(resolve_repo_root "$SCRIPT_DIR"); then BUILD_REPO=$resolved; return 0; fi
    if resolved=$(resolve_repo_root "$PWD");        then BUILD_REPO=$resolved; return 0; fi
    ci::die "cannot resolve repo root; set BUILD_REPO, pass a path, or place clone at \$REPO_FOLDER next to this script" || exit 1
}

require_preconditions() {
    ci::require_tool git || exit 1
    ci::require_tool bun || exit 1
}

assert_repo_layout() {
    [ -d "$BUILD_REPO/.git" ] || { ci::die "not a git repo: $BUILD_REPO"; exit 1; }
    [ -f "$BUILD_SCRIPT" ]    || { ci::die "build script missing: $BUILD_SCRIPT"; exit 1; }
}

require_branch_unless_tag_mode() {
    if [ "${BUILD_CHECKOUT_LATEST_TAG:-0}" = "1" ]; then return 0; fi
    ci::require_env BUILD_BRANCH || {
        ci::error "to deploy from a tag instead, set BUILD_CHECKOUT_LATEST_TAG=1 and GIT_TAG_PREFIX"
        exit 1
    }
}

fetch_origin() {
    ci::info "git fetch origin"
    ci::retry 3 git fetch origin --quiet --prune
}

fetch_tags_for_prefix_best_effort() {
    [ -n "${GIT_TAG_PREFIX:-}" ] || return 0
    ci::info "git fetch tags (prefix: ${GIT_TAG_PREFIX})"
    if ! ci::retry 3 git fetch origin \
            "refs/tags/${GIT_TAG_PREFIX}*:refs/tags/${GIT_TAG_PREFIX}*" --quiet 2>/dev/null; then
        ci::warn "tag-prefix fetch failed or no matching tags; build.sh still runs git fetch --tags"
    fi
}

checkout_latest_matching_tag() {
    [ -n "${GIT_TAG_PREFIX:-}" ] \
        || { ci::die "BUILD_CHECKOUT_LATEST_TAG=1 requires GIT_TAG_PREFIX (e.g. release-v)"; exit 1; }

    ci::retry 3 git fetch origin --tags --quiet 2>/dev/null || true

    local latest_tag
    latest_tag=$(git tag -l "${GIT_TAG_PREFIX}*" | sort -V | tail -n 1)
    [ -n "$latest_tag" ] || { ci::die "no tag matches ${GIT_TAG_PREFIX}*"; exit 1; }

    ci::info "checkout latest matching tag: $latest_tag"
    git checkout "$latest_tag"
}

checkout_branch_and_pull() {
    ci::info "branch: $BUILD_BRANCH"
    ci::info "git checkout + pull $BUILD_BRANCH"
    git checkout "$BUILD_BRANCH"
    ci::retry 3 git pull --ff-only origin "$BUILD_BRANCH"
}

sync_git_ref() {
    if [ "${BUILD_CHECKOUT_LATEST_TAG:-0}" = "1" ]; then
        checkout_latest_matching_tag
    else
        checkout_branch_and_pull
    fi
}

validate_deploy_user_host() {
    local target="$1" user host
    [[ "$target" == *"@"* ]] || { ci::die "deploy target must be user@host: $target"; exit 1; }
    host="${target#*@}"; user="${target%%@*}"
    [ -n "$host" ] && [ -n "$user" ] \
        || { ci::die "cannot parse user@host: $target"; exit 1; }
    [[ "$user" =~ ^[a-zA-Z0-9._-]+$ ]] \
        || { ci::die "DEPLOY_USER format invalid: $user (from $target)"; exit 1; }
    [[ "$host" =~ ^[a-zA-Z0-9.-]+$ ]] \
        || { ci::die "DEPLOY_HOST format invalid: $host (from $target)"; exit 1; }
}

assert_deploy_ssh_key_readable() {
    local key="${DEPLOY_SSH_KEY:-$HOME/.ssh/my_deploy_key.pem}"
    [ -f "$key" ] || { ci::die "SSH key not found: $key"; exit 1; }
    [ -r "$key" ] || { ci::die "SSH key not readable: $key"; exit 1; }
    export DEPLOY_SSH_KEY="$key"
}

assert_deploy_service_name_if_set() {
    [ -z "${DEPLOY_SERVICE_NAME:-}" ] && return 0
    [[ "${DEPLOY_SERVICE_NAME}" =~ ^[a-zA-Z0-9._-]+$ ]] \
        || { ci::die "DEPLOY_SERVICE_NAME format invalid: ${DEPLOY_SERVICE_NAME}"; exit 1; }
}

run_sync_env_to_shared_if_requested() {
    [ "${SYNC_ENV_TO_SHARED:-0}" = "1" ] || return 0
    local sync_script="$BUILD_REPO/infra/ci/sync-env-to-shared.sh"
    [ -f "$sync_script" ] || { ci::die "SYNC_ENV_TO_SHARED=1 but $sync_script not found"; exit 1; }
    ci::info "sync-env-to-shared.sh → ${DEPLOY_USER}@${DEPLOY_HOST}"
    "$sync_script"
}

run_deploy_if_requested() {
    local deploy_script target
    local -a target_list

    if [ "${DO_DEPLOY:-0}" != "1" ]; then
        ci::info "skip deploy.sh (set DO_DEPLOY=1 to enable)"
        return 0
    fi

    assert_deploy_ssh_key_readable
    assert_deploy_service_name_if_set
    [ -n "${DEPLOY_RELEASE_RETAIN_COUNT+x}" ] && export DEPLOY_RELEASE_RETAIN_COUNT

    if [ "${SAMPLE_DEPLOY_DRY_RUN:-0}" = "1" ]; then
        export DEPLOY_DRY_RUN=1
        ci::info "deploy dry-run (DEPLOY_DRY_RUN=1)"
    fi

    deploy_script="$BUILD_REPO/infra/ci/deploy.sh"
    [ -f "$deploy_script" ] || { ci::die "deploy script missing: $deploy_script"; exit 1; }

    SAMPLE_DEPLOY_RAN=1

    if [ -n "${DEPLOY_TARGETS:-}" ]; then
        read -ra target_list <<< "${DEPLOY_TARGETS}"
        [ "${#target_list[@]}" -gt 0 ] \
            || { ci::die "DO_DEPLOY=1 but DEPLOY_TARGETS is blank"; exit 1; }
        for target in "${target_list[@]}"; do
            [ -n "$target" ] || continue
            validate_deploy_user_host "$target"
            export DEPLOY_USER="${target%%@*}"
            export DEPLOY_HOST="${target#*@}"
            run_sync_env_to_shared_if_requested
            ci::info "deploy.sh → ${DEPLOY_USER}@${DEPLOY_HOST}"
            "$deploy_script"
        done
        return 0
    fi

    ci::require_env DEPLOY_HOST || {
        ci::error "alternatively set DEPLOY_TARGETS=\"user@h1 user@h2\" for multiple hosts"
        exit 1
    }

    run_sync_env_to_shared_if_requested
    ci::info "deploy.sh"
    "$deploy_script"
}

slack_notify() {
    [ -n "${SLACK_WEBHOOK_URL:-}" ] || return 0

    if ! command -v curl >/dev/null 2>&1; then
        ci::warn "SLACK_WEBHOOK_URL set but curl is not on PATH; skipping Slack"
        return 0
    fi

    local project="${SLACK_PROJECT_NAME:-my-app}"
    local status="$1" message="$2"
    local payload="{\"text\": \"*[$project]* ${status}: ${message}\"}"

    # Notification is best-effort: retry transient errors, but never fail the
    # pipeline on Slack flakiness.
    ci::retry 3 curl -sS --connect-timeout 5 --max-time 15 \
        -X POST -H 'Content-type: application/json' \
        --data "$payload" "$SLACK_WEBHOOK_URL" -o /dev/null || true
}

# --- main --------------------------------------------------------------------

parse_sample_cli "$@"

discover_build_repo "${DISCOVER_ARGS[@]}"

BUILD_REPO=$(cd "$BUILD_REPO" && pwd)
readonly BUILD_REPO
readonly BUILD_SCRIPT="$BUILD_REPO/infra/ci/build.sh"

require_preconditions
assert_repo_layout
require_branch_unless_tag_mode

cd "$BUILD_REPO"
ci::info "repo: $BUILD_REPO"

fetch_origin
fetch_tags_for_prefix_best_effort
sync_git_ref

if [ "${BUILD_SKIP_VERIFY:-0}" = "1" ]; then
    ci::info "build.sh --skip-verify"
    "$BUILD_SCRIPT" --skip-verify
else
    ci::info "build.sh"
    "$BUILD_SCRIPT"
fi

SAMPLE_DEPLOY_RAN=0
run_deploy_if_requested

if [ "${SAMPLE_DEPLOY_RAN:-0}" = "1" ]; then
    slack_notify "success" "Build and deploy completed successfully."
fi
