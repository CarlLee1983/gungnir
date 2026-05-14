#!/usr/bin/env bash
# deploy-prod.sh — advanced retrofit case study for Gungnir ci-toolkit.
#
# Mirrors a real StationHub-style Laravel deploy script:
#   parse CLI flags → resolve target tag → composer + npm build →
#   for each host: blue/green flip + rsync + SSH heredoc post-deploy →
#   optional CloudWatch log-group creation → Slack notification.
#
# THIS IS A CODE REFERENCE, NOT AN EXECUTABLE EXAMPLE.
# It will fail at runtime without an outer wrapper that supplies
# TARGET_HOSTS / BEFORE_COMMANDS / MIDDLE_COMMANDS / CLOUDWATCH_HOST_CONFIGS
# associative arrays plus PROJECT_DIR, GIT_BRANCH, SSH key, and Slack webhook.
#
# See README.md for the substitution table and adoption steps.

set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./ci-toolkit
source "$SCRIPT_DIR/ci-toolkit"

# === Configuration & CLI state ===

# Tag-prefix policy (StationHub default: "release/"; override via env).
ci::env_default TAG_PREFIX "release/"

# Blue/green directory layout on the remote host.
# shellcheck disable=SC2088
# Reason: preserved verbatim from the original script; the tilde is
# expanded at the `ssh -i "$SSH_KEY"` call site by the remote shell.
SSH_KEY="${SSH_KEY:-~/.ssh/sw-ssh-key.pem}"
DEPLOY_DIR="${DEPLOY_DIR:-/var/www}"
BLUE_DIR="${DEPLOY_DIR}/site_blue"
GREEN_DIR="${DEPLOY_DIR}/site_green"
SITE_DIR="${DEPLOY_DIR}/site"

# CLI flag state — populated by parse_cli (see Task 3).
SKIP_VERSION_CHECK=false
SPECIFIED_TAG=""
ENABLE_CLOUDWATCH=false

# Mutable pipeline state — set by resolve_target_tag (Task 7) and the
# multi-host loop (Task 12); read by send_slack_notification at the end
# of main() (Task 14).
CURRENT_TAG=""
LATEST_TAG=""
NOTIFY_MESSAGE=""

# === Local functions ===

# parse_cli — local CLI flag parsing (spec §6.1 not-collected).
# Sets SKIP_VERSION_CHECK / SPECIFIED_TAG / ENABLE_CLOUDWATCH module-level
# variables; intentionally not delegated to ci-toolkit (the toolkit does not
# parse argv — that is application policy).
parse_cli() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip)
                SKIP_VERSION_CHECK=true
                shift
                ;;
            --tag=*)
                SPECIFIED_TAG="${1#*=}"
                shift
                ;;
            --cloudwatch)
                ENABLE_CLOUDWATCH=true
                shift
                ;;
            -h|--help)
                cat <<'USAGE'
Usage: deploy-prod.sh [--skip] [--tag=<tag_name>] [--cloudwatch]

  --skip          Skip the "new tag must be greater than current" check.
  --tag=<name>    Deploy a specific tag instead of the latest matching one.
  --cloudwatch    Also create CloudWatch log groups after deploy.
USAGE
                exit 0
                ;;
            *)
                ci::die "unknown arg: $1 (try --help)" || exit 1
                ;;
        esac
    done
}

# send_slack_notification — local message template (spec §6.2 not-collected).
# Builds the StationHub Slack template (emoji + git log diff + env/version/time)
# and delegates the HTTP POST + retry policy to ci::slack_webhook.
#
# Usage: send_slack_notification STATUS MESSAGE
#   STATUS  — "success" or anything else (treated as failure).
#   MESSAGE — single string; may contain literal \n that Slack renders.
send_slack_notification() {
    local status="$1"
    local notify_message="$2"
    local message=""
    local gitlogs=""
    local current_version new_version

    if [[ "$status" == "success" ]]; then
        message+="🚀 部署完成通知\n"
        message+="${notify_message}\n\n"

        if [[ -n "$CURRENT_TAG" && -n "$LATEST_TAG" ]]; then
            current_version=$(strip_tag_prefix "$CURRENT_TAG" "$TAG_PREFIX")
            new_version=$(strip_tag_prefix "$LATEST_TAG" "$TAG_PREFIX")

            # Direct sort -V here — ci::version_gt is still a §5.2 proposal.
            if [[ "$(printf '%s\n' "$current_version" "$new_version" | sort -V | head -n1)" != "$new_version" ]]; then
                message+="版本更新紀錄:\n"
                gitlogs=$(git log "${CURRENT_TAG}..${LATEST_TAG}" --format="%h %<(100,trunc)%s" 2>/dev/null || true)
                if [[ -n "$gitlogs" ]]; then
                    message+="${gitlogs}\n\n"
                else
                    message+="無更新紀錄\n\n"
                fi
            fi
        fi
    else
        message+="❌ 部署失敗通知\n"
        message+="錯誤訊息: ${notify_message}\n\n"
    fi

    message+="環境: ${DEPLOY_ENV:-unset}\n"
    message+="版本: ${LATEST_TAG}\n"
    message+="時間: $(date '+%Y-%m-%d %H:%M:%S')"

    # ci::slack_webhook handles missing-webhook + missing-curl gracefully
    # (warns and returns 0) and retries the POST 3x on transient failure.
    ci::slack_webhook SLACK_WEBHOOK_URL "laravel-bluegreen" "$status" "$message"
}

# proposed: ci::trap_err CALLBACK (see spec §5.4, plan TBD)
# After §5.4 lands, replace this whole function with `ci::trap_err "$1"`.
compose_err_trap() {
    local callback="${1:-}"
    if [[ -z "$callback" ]]; then
        ci::die "compose_err_trap: callback is required" || exit 1
    fi
    set -E
    # shellcheck disable=SC2064
    # Reason: callback string is intentionally expanded eagerly here for the
    # case-study; the §5.4 proposal will switch to lazy expansion of $LINENO.
    trap "$callback" ERR
}

# proposed: ci::strip_prefix VALUE PREFIX (see spec §5.3, plan TBD)
# After §5.3 lands, replace call sites with `ci::strip_prefix "$value" "$prefix"`
# and delete this function.
strip_tag_prefix() {
    local value="${1:-}"
    local prefix="${2:-}"
    printf '%s\n' "${value#"$prefix"}"
}

# proposed: ci::version_gt A B (see spec §5.2, plan TBD)
# After §5.2 lands, replace this whole function with:
#     ci::version_gt "$new_version" "$current_version" || {
#         ci::die "New version ($LATEST_TAG) is not greater..." || exit 1
#     }
# and delete this function.
compare_versions_or_exit() {
    local new_version="${1:-}"
    local current_version="${2:-}"
    if [[ "$(printf '%s\n' "$new_version" "$current_version" | sort -V | head -n1)" == "$new_version" ]]; then
        ci::error "New version ($LATEST_TAG) is not greater than current version ($CURRENT_TAG)"
        ci::die "Deployment aborted!" || exit 1
    fi
}

# resolve_target_tag — sets CURRENT_TAG and LATEST_TAG (module-level).
# Mirrors the original L94-121 version-resolution block.
resolve_target_tag() {
    if [[ -n "$SPECIFIED_TAG" ]]; then
        LATEST_TAG="$SPECIFIED_TAG"
        return 0
    fi

    CURRENT_TAG=$(git describe --tags --abbrev=0)

    ci::retry 3 git fetch origin
    ci::retry 3 git fetch --tags

    ci::require_env GIT_BRANCH || exit 1
    ci::retry 3 git pull origin "$GIT_BRANCH"

    LATEST_TAG=$(ci::git_latest_tag "$TAG_PREFIX") || exit 1

    if [[ "$SKIP_VERSION_CHECK" == "false" ]]; then
        local current_version new_version
        current_version=$(strip_tag_prefix "$CURRENT_TAG" "$TAG_PREFIX")
        new_version=$(strip_tag_prefix "$LATEST_TAG" "$TAG_PREFIX")
        compare_versions_or_exit "$new_version" "$current_version"
    fi
}

# === Pipeline ===
main() {
    :
}

main "$@"
