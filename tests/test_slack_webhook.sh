#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/assert.sh
source "$ROOT_DIR/tests/assert.sh"

run_capture() {
  local stdout_file stderr_file status
  stdout_file="$(make_temp_dir)/stdout"
  stderr_file="$(make_temp_dir)/stderr"
  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  # shellcheck disable=SC2034
  RUN_STDOUT="$(cat "$stdout_file")"
  RUN_STDERR="$(cat "$stderr_file")"
  RUN_STATUS="$status"
}

set -e

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::slack_webhook"
assert_status 64 "$RUN_STATUS" "source slack_webhook requires args"

run_capture bash -c "source '$ROOT_DIR/ci-toolkit'; ci::slack_webhook MY_WEBHOOK_URL my-app success done"
assert_status 0 "$RUN_STATUS" "source slack_webhook ignores missing var gracefully"
assert_contains "$RUN_STDERR" "Slack webhook variable MY_WEBHOOK_URL is not set" "source slack_webhook warns on missing var"

# Mock curl
bin_dir="$(make_temp_dir)"
cat <<'EOF' >"$bin_dir/curl"
#!/usr/bin/env bash
echo "$@" >> "$CURL_MOCK_LOG"
EOF
chmod +x "$bin_dir/curl"

log_file="$(make_temp_dir)/curl.log"

run_capture bash -c "export PATH=\"$bin_dir:\$PATH\"; export MY_WEBHOOK_URL='https://hooks.slack.com/xyz'; export CURL_MOCK_LOG='$log_file'; source '$ROOT_DIR/ci-toolkit'; ci::slack_webhook MY_WEBHOOK_URL my-app success 'job finished'"
assert_status 0 "$RUN_STATUS" "source slack_webhook succeeds with mock curl"
assert_contains "$(cat "$log_file")" "https://hooks.slack.com/xyz" "curl mock receives URL"
assert_contains "$(cat "$log_file")" "job finished" "curl mock receives message payload"

# CLI missing args
run_capture "$ROOT_DIR/ci-toolkit" slack webhook
assert_status 64 "$RUN_STATUS" "CLI slack webhook requires args"
assert_contains "$RUN_STDERR" "Usage:" "CLI prints usage on missing args"

# CLI success
run_capture bash -c "export PATH=\"$bin_dir:\$PATH\"; export MY_WEBHOOK_URL='https://hooks.slack.com/cli'; export CURL_MOCK_LOG='$log_file'; '$ROOT_DIR/ci-toolkit' slack webhook MY_WEBHOOK_URL cli-app fail 'it broke'"
assert_status 0 "$RUN_STATUS" "CLI slack webhook succeeds with mock curl"
assert_contains "$(cat "$log_file")" "https://hooks.slack.com/cli" "CLI curl mock receives URL"
assert_contains "$(cat "$log_file")" "it broke" "CLI curl mock receives message payload"

finish_tests
