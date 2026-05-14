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

# shellcheck disable=SC2154
# Reason: these variables are supplied by an outer wrapper (see README §1):
#   PROJECT_DIR, GIT_BRANCH, DEPLOY_ENV, SLACK_WEBHOOK_URL,
#   TARGET_HOSTS, BEFORE_COMMANDS, MIDDLE_COMMANDS, CLOUDWATCH_HOST_CONFIGS,
#   CLOUDWATCH_ENV, CLOUDWATCH_APP, CLOUDWATCH_SERVICE, CLOUDWATCH_GROUP_ID
# ShellCheck cannot see the wrapper, so silence SC2154 file-wide.
set -euo pipefail

# shellcheck disable=SC2155
# Reason: the `cd ... && pwd` invocation cannot fail under normal conditions
# (the script directory always exists when BASH_SOURCE is set); separating
# the declaration would not improve safety here and the single-line form
# matches the convention used by the other examples in this repo.
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
                # shellcheck disable=SC2034
                # Reason: ENABLE_CLOUDWATCH is read by `ci::is_true ENABLE_CLOUDWATCH`
                # in run_cloudwatch_setup (indirect variable expansion via ${!name});
                # ShellCheck cannot follow that, so the assignment looks unused.
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

# run_composer_install — composer install with a 30s gap between attempts.
run_composer_install() {
    ci::require_tool composer || exit 1
    export COMPOSER_ALLOW_SUPERUSER=1

    ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
}

# run_npm_build — preserved verbatim; only adds the ci::require_tool guard.
run_npm_build() {
    ci::require_tool npm || exit 1
    npm i
    npm run build
}

# parse_blue_green_target_dir — local blue/green policy (spec §6.7 not-collected).
#
# Returns (stdout): the directory we should deploy INTO this run (the one the
# symlink is NOT currently pointing at).
#
# Exit codes:
#   0 — current symlink resolved; stdout is the next dir.
#   2 — neither blue nor green is current (first deploy); stdout is BLUE_DIR
#       and the caller should bootstrap both dirs on the host.
parse_blue_green_target_dir() {
    local host="$1"
    local current_target

    current_target=$(ssh -i "$SSH_KEY" "$host" "sudo readlink $SITE_DIR" 2>/dev/null || true)

    if [[ "$current_target" == "$BLUE_DIR" ]]; then
        printf '%s\n' "$GREEN_DIR"
        return 0
    elif [[ "$current_target" == "$GREEN_DIR" ]]; then
        printf '%s\n' "$BLUE_DIR"
        return 0
    else
        printf '%s\n' "$BLUE_DIR"
        return 2
    fi
}

# deploy_files_to_host — per-host blue/green rsync (spec §6.8 not-collected).
#
# Side effect: prints "deploying to ..." progress via ci::info, sets a local
# TARGET_DIR for the caller-printed log line, and rsyncs the working tree.
deploy_files_to_host() {
    local host="$1"
    local target_dir status

    set +e
    target_dir=$(parse_blue_green_target_dir "$host")
    status=$?
    set -e

    if [[ "$status" -eq 2 ]]; then
        ci::info "no existing blue/green symlink on $host — bootstrapping"
        ssh -i "$SSH_KEY" "$host" "sudo mkdir -p $BLUE_DIR $GREEN_DIR"
    fi

    ci::info "syncing to $target_dir on $host"

    if ssh -i "$SSH_KEY" "$host" "[ ! -d $target_dir/storage ]"; then
        rsync -az --delete --exclude=".git" \
            --rsync-path="sudo rsync" -e "ssh -i $SSH_KEY" \
            ./ "$host:$target_dir/"
    else
        rsync -az --delete --exclude=".git" --exclude="storage" \
            --rsync-path="sudo rsync" -e "ssh -i $SSH_KEY" \
            ./ "$host:$target_dir/"
    fi

    ssh -i "$SSH_KEY" "$host" \
        "sudo chmod -R 777 $target_dir/storage; sudo chmod -R 777 $target_dir/bootstrap/cache;"
}

# sanitize_cloudwatch_token — CloudWatch naming policy (spec §6.3 not-collected).
# Strips \r\n\t, leading/trailing whitespace, and replaces inner spaces with _.
sanitize_cloudwatch_token() {
    printf '%s' "${1:-}" \
        | tr -d '\r\n\t' \
        | sed 's/[[:space:]]*$//' \
        | sed 's/^[[:space:]]*//' \
        | sed 's/[[:space:]]/_/g'
}

# compute_cloudwatch_log_group — CloudWatch log-group name (spec §6.4 not-collected).
#
# Output: /<env>/<app>/<service>/<group_id>/<role>/<node_id>
#
# Inputs (env): CLOUDWATCH_ENV, CLOUDWATCH_APP, CLOUDWATCH_SERVICE,
#               CLOUDWATCH_GROUP_ID.
# Inputs (args):
#   $1 — HOST_NAME (used as role fallback when NODE_CONFIG has no comma).
#   $2 — NODE_CONFIG: either "ap,1" (role,node_id) or a plain node id.
compute_cloudwatch_log_group() {
    local host_name="$1"
    local node_config="${2:-1}"
    local env_clean app_clean service_clean group_id_clean
    local role_clean node_id_clean

    env_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_ENV:-dev}")
    app_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_APP:-cmg}")
    service_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_SERVICE:-station}")
    group_id_clean=$(sanitize_cloudwatch_token "${CLOUDWATCH_GROUP_ID:-9999}")

    if [[ -n "$node_config" && "$node_config" == *,* ]]; then
        role_clean=$(sanitize_cloudwatch_token "${node_config%%,*}")
        node_id_clean=$(sanitize_cloudwatch_token "${node_config#*,}")
    else
        role_clean=$(sanitize_cloudwatch_token "$host_name")
        node_id_clean=$(sanitize_cloudwatch_token "${node_config:-1}")
    fi

    printf '/%s/%s/%s/%s/%s/%s\n' \
        "$env_clean" "$app_clean" "$service_clean" \
        "$group_id_clean" "$role_clean" "$node_id_clean"
}

# run_post_deploy_on_host — SSH heredoc post-deploy (spec §6.5 not-collected).
#
# The heredoc body is preserved verbatim from the original L238-289. All bash
# vars referenced inside ($target_dir, $before_cmd, $middle_cmd, $SITE_DIR,
# $cloudwatch_log_group_name) are interpolated by the LOCAL shell before the
# heredoc is fed to ssh — this is intentional and matches the original.
run_post_deploy_on_host() {
    local host_name="$1"
    local target_host="$2"
    local target_dir before_cmd middle_cmd
    local cloudwatch_node_config cloudwatch_log_group_name

    set +e
    target_dir=$(parse_blue_green_target_dir "$target_host")
    set -e

    before_cmd="${BEFORE_COMMANDS[$host_name]}"
    middle_cmd="${MIDDLE_COMMANDS[$host_name]}"
    cloudwatch_node_config="${CLOUDWATCH_HOST_CONFIGS[$host_name]:-1}"
    cloudwatch_log_group_name=$(compute_cloudwatch_log_group "$host_name" "$cloudwatch_node_config")

    ci::info "CloudWatch log group for ${target_host}: ${cloudwatch_log_group_name}"

    # shellcheck disable=SC2087
    # Reason: unquoted EOF is intentional — local-side expansion of
    # $target_dir / $before_cmd / $middle_cmd / $SITE_DIR /
    # $cloudwatch_log_group_name is the documented contract of this heredoc
    # (mirrors the original StationHub script L238). Tokens that must run on
    # the remote side are escaped with `\$(...)`.
    ssh -i "$SSH_KEY" "$target_host" <<EOF
cd "$target_dir"
pwd
eval "$before_cmd"
eval "$middle_cmd"
sudo ln -sfn "$target_dir" "$SITE_DIR"

if [ ! -d /var/log/laravel ]; then
    sudo mkdir -p /var/log/laravel
    sudo chown -R root:root /var/log/laravel
    sudo chmod -R 777 /var/log/laravel
fi

if [ -d "$target_dir/storage/logs" ] && [ ! -L "$target_dir/storage/logs" ]; then
    sudo rm -rf "$target_dir/storage/logs"
fi
sudo ln -sfn /var/log/laravel "$target_dir/storage/logs"

if [ "\$(readlink -f /etc/supervisor/conf.d/supervisord.conf)" != "\$(readlink -f $target_dir/supervisord.conf)" ]; then
    sudo ln -sfn "$target_dir/supervisord.conf" "/etc/supervisor/conf.d/supervisord.conf"
fi

cd "$SITE_DIR"

if [ -n "$cloudwatch_log_group_name" ]; then
    sudo php artisan env:manage set CLOUDWATCH_LOG_GROUP_NAME "$cloudwatch_log_group_name"
else
    echo "WARN: CLOUDWATCH_LOG_GROUP_NAME empty; skipping env:manage set"
fi

sudo php artisan optimize:clear
sudo php artisan config:cache
sudo php artisan view:cache
sudo supervisorctl update
sudo php artisan queue:restart
EOF

    NOTIFY_MESSAGE+="部署主機 : ${target_host}\n"
    NOTIFY_MESSAGE+="當前目錄 : ${target_dir}\n"
}

# run_multi_host_deploy — multi-host iteration (spec §6.6 not-collected).
# Sequentially: rsync to every host, then post-deploy on every host.
run_multi_host_deploy() {
    local host_name target_host

    for host_name in "${!TARGET_HOSTS[@]}"; do
        target_host="${TARGET_HOSTS[$host_name]}"
        ci::info "deploying files to host: ${target_host}"
        deploy_files_to_host "$target_host"
    done

    for host_name in "${!TARGET_HOSTS[@]}"; do
        target_host="${TARGET_HOSTS[$host_name]}"
        ci::info "running post-deploy on host: ${target_host}"
        run_post_deploy_on_host "$host_name" "$target_host"
    done
}

# run_cloudwatch_setup — conditional CloudWatch log-group creation.
# Mirrors original L300-322. The referenced setup script lives in the OUTER
# wrapper (StationHub) repo, NOT in this example — hence the [[ -f ]] guard.
run_cloudwatch_setup() {
    if ! ci::is_true ENABLE_CLOUDWATCH; then
        ci::info "skipping CloudWatch log-group creation (use --cloudwatch to enable)"
        ci::info "note: CloudWatch env vars are still set during deploy"
        return 0
    fi

    ci::info "=========================================="
    ci::info "creating CloudWatch log groups..."
    ci::info "=========================================="

    ci::require_env CLOUDWATCH_ENV || return 0
    ci::require_env CLOUDWATCH_APP || return 0
    ci::require_env CLOUDWATCH_SERVICE || return 0

    local setup_script="${PROJECT_DIR}/scripts/deploy/shared/remote-cloudwatch-setup.sh"
    if [[ ! -f "$setup_script" ]]; then
        ci::warn "remote-cloudwatch-setup.sh not found at $setup_script — skipping"
        ci::warn "(this is expected in the examples/ tree; supply it in your outer wrapper)"
        return 0
    fi

    # shellcheck source=/dev/null
    # Reason: the setup script lives in the outer wrapper and is intentionally
    # not part of this example. ShellCheck cannot resolve the path statically.
    source "$setup_script"

    ci::info "=========================================="
    ci::info "CloudWatch log-group creation complete"
    ci::info "=========================================="
}

# === Pipeline ===
main() {
    parse_cli "$@"

    # shellcheck disable=SC2016
    # Reason: single-quoted callback is intentional — $LINENO must be
    # expanded LAZILY when the ERR trap fires, not eagerly when
    # compose_err_trap is called.
    compose_err_trap 'send_slack_notification "failed" "Script failed at line $LINENO"'

    ci::require_env PROJECT_DIR || exit 1
    cd "$PROJECT_DIR"

    resolve_target_tag
    ci::info "deploying tag: $LATEST_TAG"
    git checkout "$LATEST_TAG"

    run_composer_install
    run_npm_build

    run_multi_host_deploy

    ci::info "all deployments completed successfully"

    run_cloudwatch_setup

    send_slack_notification "success" "$NOTIFY_MESSAGE"
}

main "$@"
