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

# --- JSON escaping ---------------------------------------------------------

payload_bin_dir="$(make_temp_dir)"
cat <<'EOF' >"$payload_bin_dir/curl"
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)
      printf '%s' "$2" >"$CURL_PAYLOAD_FILE"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
EOF
chmod +x "$payload_bin_dir/curl"

payload_file="$(make_temp_dir)/payload.json"

# Quotes and backslashes in the message must come out JSON-escaped.
run_capture bash -c "
  export PATH=\"$payload_bin_dir:\$PATH\"
  export MY_WEBHOOK_URL='https://hooks.slack.com/escape'
  export CURL_PAYLOAD_FILE='$payload_file'
  source '$ROOT_DIR/ci-toolkit'
  ci::slack_webhook MY_WEBHOOK_URL 'app' 'fail' 'build \"broke\": C:\\path'
"
assert_status 0 "$RUN_STATUS" "slack_webhook returns 0 with quoted message"
payload="$(cat "$payload_file")"
assert_eq '{"text":"*[app]* fail: build \"broke\": C:\\path"}' \
  "$payload" "payload escapes \" and \\\\"

# Newline / CR / tab in message must become \n / \r / \t literals.
run_capture bash -c "
  export PATH=\"$payload_bin_dir:\$PATH\"
  export MY_WEBHOOK_URL='https://hooks.slack.com/escape'
  export CURL_PAYLOAD_FILE='$payload_file'
  source '$ROOT_DIR/ci-toolkit'
  msg=\$'line1\nline2\tcol\rend'
  ci::slack_webhook MY_WEBHOOK_URL 'app' 'fail' \"\$msg\"
"
assert_status 0 "$RUN_STATUS" "slack_webhook returns 0 with control chars"
payload="$(cat "$payload_file")"
assert_eq '{"text":"*[app]* fail: line1\nline2\tcol\rend"}' \
  "$payload" "payload escapes \\n \\r \\t"

# Project / status field escaping (defense-in-depth — should not break JSON).
run_capture bash -c "
  export PATH=\"$payload_bin_dir:\$PATH\"
  export MY_WEBHOOK_URL='https://hooks.slack.com/escape'
  export CURL_PAYLOAD_FILE='$payload_file'
  source '$ROOT_DIR/ci-toolkit'
  ci::slack_webhook MY_WEBHOOK_URL 'pro\"ject' 'st\\atus' 'msg'
"
assert_status 0 "$RUN_STATUS" "slack_webhook returns 0 with metadata escaping"
payload="$(cat "$payload_file")"
assert_eq '{"text":"*[pro\"ject]* st\\atus: msg"}' \
  "$payload" "project / status fields are escaped"

finish_tests
