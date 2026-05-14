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

# === Pipeline ===
main() {
    :
}

main "$@"
