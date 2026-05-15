# Gungnir

<!-- doc-key: overview -->
實驗性的平台中立 CI 腳本 Bash 輔助工具。

Gungnir 只發佈一個檔案：`ci-toolkit`。你可以直接把它當 CLI 執行，也可以在 Bash 腳本中 `source` 它，取得 `ci::` 命名空間下的函式。它刻意保持小而專注：處理日誌、環境檢查、指令重試、路徑探索、版本比較、資料驗證、shell 參數逃逸與簡易通知等 CI 腳本常見原語。它**不**內建 GitHub Actions、GitLab、CircleCI、Docker、build 或 deploy 政策。

當你的 CI 腳本開始累積手寫的 `log()`、`fatal()`、`retry()`、`require_env()` 或「尋找 repo root」片段時，就適合使用 Gungnir。專案特有的決策仍留在你的腳本；重複、容易寫錯的基礎工作交給 toolkit。

## 你會得到什麼

- **單一 artifact**：下載 `ci-toolkit`、加上可執行權限，就能像一般腳本一樣提交或快取。
- **兩種模式**：CLI 模式適合單行指令；source 模式適合完整腳本。
- **安全輸出契約**：日誌走 stderr；資料走 stdout；驗證失敗只印欄位名稱，不印秘密值。
- **可預期的失敗**：source 函式回傳 status，不會自行 `exit`；CLI 使用錯誤回傳 `64`。
- **只需要 Bash 4+**：沒有 build step、沒有 package manager、沒有常駐服務。

---

<!-- doc-key: install-setup -->
## 安裝與設定

### 需求

- Bash 4+。較舊的 macOS `/bin/bash` 是 3.2；請用 `brew install bash` 安裝新版 Bash，並讓腳本使用 `#!/usr/bin/env bash`。
- 標準 shell 工具需在 `PATH` 上。
- 若使用 `ci::version_gt`、`ci::version_ge` 或 `ci::git_latest_tag`，需要支援 `sort -V` 的 `sort`。toolkit 會自行探測，缺少時會印出修復提示。
- 選用：若要用 `./scripts/lint` 做本地 lint，需安裝 `shellcheck`。

### 安裝固定版本

CI 中建議固定 release tag。除非你明確想追實驗性變更，否則不要在正式 automation 裡 curl `main`。

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.10/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

預期輸出：

```text
ci-toolkit 0.1.10
```

### Vendor 到腳本旁邊

若腳本要在 CI host、部署機或開發者電腦上執行，最穩定的方式是把固定版本放在使用它的腳本旁邊。

```bash
mkdir -p infra/ci
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.10/ci-toolkit \
  -o infra/ci/ci-toolkit
chmod +x infra/ci/ci-toolkit
git add infra/ci/ci-toolkit
git commit -m "Vendor Gungnir ci-toolkit v0.1.10"
```

在腳本中用「相對於腳本本身」的路徑載入，而不是依賴呼叫者目前目錄：

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./ci-toolkit
source "$SCRIPT_DIR/ci-toolkit"
```

### CLI 快速檢查

```bash
./ci-toolkit help
./ci-toolkit ls
./ci-toolkit log info "toolkit is installed"
./ci-toolkit env require HOME
./ci-toolkit tool require git
```

### 原始 Bash vs Gungnir

| 任務 | 原始 Bash 語法 | Gungnir `ci-toolkit` |
|------|---------------|----------------------|
| **日誌記錄** | `echo "[INFO] starting" >&2` | `ci::info "starting"` |
| **環境變數檢查** | `if [[ -z "${TOKEN:-}" ]]; then echo ...; exit 1; fi` | `ci::require_env TOKEN` |
| **工具檢查** | 手寫 `command -v` 檢查與 exit handling | `ci::require_tool git` |
| **指令重試** | 自行維護 counter、sleep、最後 exit code | `ci::retry 3 -- curl -fsS "$URL"` |
| **路徑定位** | 固定深度 `cd "$(dirname "$0")/.."` 片段 | `ci::root` 或 `ci::find_up marker` |
| **允許清單** | `case "$env" in prod\|staging) ...` | `ci::in "$env" prod staging` |

### Before / after：原始 Bash 語法 vs `ci::` 語法

Gungnir 的優點不是「Bash 做不到」，而是安全、完整的原始 Bash 寫法很冗長，而且很容易在 stderr、exit code、secret leakage 或邊界條件上寫錯。`ci::` 語法直接把意圖命名出來。

#### 日誌記錄

原始 Bash 常混用 stdout/stderr，或每個腳本 prefix 都不同：

```bash
echo "starting deploy"
echo "warning: cache missing" >&2
echo "error: deploy failed" >&2
```

使用 `ci::` 後，日誌格式一致且一律輸出到 stderr：

```bash
ci::info "starting deploy"
ci::warn "cache missing"
ci::error "deploy failed"
```

#### 必要環境變數

原始 Bash 檢查冗長，debug 時也容易意外印出 secret：

```bash
if [[ -z "${DEPLOY_TOKEN:-}" ]]; then
  echo "DEPLOY_TOKEN is required" >&2
  exit 1
fi
```

使用 `ci::` 後，helper 以變數名稱檢查，永遠不印變數值：

```bash
ci::require_env DEPLOY_TOKEN || exit $?
```

#### 必要工具

原始 Bash 每個腳本都要重複 `command -v` plumbing：

```bash
if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi
```

使用 `ci::` 後，語法直接描述 precondition：

```bash
ci::require_tool git || exit $?
```

#### 重試不穩定指令

正確的原始 retry loop 必須保留最後 exit status、正確計算嘗試次數，且不要掩蓋 deterministic failure：

```bash
attempt=1
max_attempts=3
status=0
while (( attempt <= max_attempts )); do
  curl -fsS "$HEALTH_URL" && status=0 && break
  status=$?
  echo "attempt $attempt failed" >&2
  attempt=$((attempt + 1))
done
exit "$status"
```

使用 `ci::` 後，retry policy 是一行，實際被執行的 command 仍清楚可見：

```bash
ci::retry 3 -- curl -fsS "$HEALTH_URL"
```

要加入 delay 不必重寫 loop：

```bash
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

#### 尋找 repository root

原始 Bash 常假設固定目錄深度，腳本移動後就失效：

```bash
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
```

使用 `ci::` 後，從目前工作目錄動態探索：

```bash
REPO_ROOT=$(ci::root) || exit $?
```

#### 驗證值且不洩漏內容

原始 Bash 驗證常把被拒絕的值或路徑印出來：

```bash
if [[ ! "$DEPLOY_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid deploy user: $DEPLOY_USER" >&2
  exit 1
fi
```

使用 `ci::` 後，stderr 只出現邏輯欄位名與規則，不印敏感值：

```bash
ci::require_match DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
```

#### 允許清單檢查

原始 Bash 的 `case` 可行，但重複出現時會快速膨脹：

```bash
case "${TARGET_ENV:-}" in
  staging|production|preview) ;;
  *)
    echo "unsupported TARGET_ENV" >&2
    exit 1
    ;;
esac
```

使用 `ci::` 後，允許值就是參數本身：

```bash
if ! ci::in "${TARGET_ENV:-}" staging production preview; then
  ci::die "unsupported TARGET_ENV" || exit 1
fi
```

---

<!-- doc-key: connections -->
## 環境與初始化

Gungnir 沒有伺服器端連線設定。這裡的「初始化」指的是你的腳本如何連接 toolkit：直接執行 CLI，或 source 到目前 Bash process。

### 選擇正確模式

| 模式 | 適用情境 | 行為 |
| --- | --- | --- |
| **Source 模式** | 你正在寫有 function、branch、cleanup 或多步驟流程的腳本。 | `source ./ci-toolkit` 後呼叫 `ci::...`。helper 回傳 status，不會結束你的 shell。 |
| **CLI 模式** | 你需要 Makefile、CI YAML step 或 shell pipeline 中的一行指令。 | 執行 `./ci-toolkit ...`。command 透過 process exit code 表達結果，usage error 印到 stderr。 |

### Source 模式骨架

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/ci-toolkit"

main() {
  ci::trap_err
  ci::info "starting checks"

  ci::require_tool git || exit $?
  ci::require_env DEPLOY_TOKEN || exit $?

  ci::retry 3 -- git fetch origin --quiet
  ci::info "done"
}

main "$@"
```

### CLI 模式範例

```bash
./ci-toolkit log info "starting checks"
./ci-toolkit env require DEPLOY_TOKEN
./ci-toolkit tool require git
./ci-toolkit retry 5 -- curl -fsS https://example.com/health
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

### 輸出與 exit code 契約

| 契約 | 說明 |
| --- | --- |
| 日誌 | `ci::log`、`ci::info`、`ci::warn`、`ci::error`、`ci::debug` 寫到 **stderr**。 |
| 資料 | `ci::root`、`ci::find_up`、`ci::strip_prefix`、`ci::shell_join` 等回傳資料的 helper 寫到 **stdout**。 |
| Source failure | Source 函式回傳 status。若 guard 失敗要停止腳本，請明確接 `|| exit $?`。 |
| CLI usage error | CLI 參數不正確回傳 `64`，usage 印到 stderr。 |
| Secret safety | `require_env`、`require_file`、`require_dir`、`require_match`、`require_uint` 報告名稱/規則，不報告敏感值。 |

### 環境變數

| 變數 | 效果 |
| --- | --- |
| `CI_TOOLKIT_DEBUG=1` | 啟用 `ci::debug` / `log debug` 輸出。預設不顯示 debug log。 |

`ci::env_default VAR VALUE` 是 helper，不是設定變數。在 source 模式中，若 `VAR` 未設定或為空，它會在目前 shell 設定預設值。

### 語法參考：CLI grammar

多數 CLI command 形狀如下：

```text
./ci-toolkit <command> [subcommand] [arguments...]
```

執行另一個 command 的 helper 會用 `--` 標示 toolkit option 結束、你的 command 開始：

```bash
./ci-toolkit retry [ATTEMPTS] [--delay SECONDS] -- COMMAND [ARGS...]
```

範例：

```bash
./ci-toolkit retry -- make test
./ci-toolkit retry 5 -- curl -fsS "$HEALTH_URL"
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev
```

巢狀 CLI command 採「名詞在前、動作在後」：

```bash
./ci-toolkit env require DEPLOY_TOKEN
./ci-toolkit env default DEPLOY_ENV staging
./ci-toolkit tool require git
./ci-toolkit file require SSH_KEY "$DEPLOY_SSH_KEY" "mount the key first"
./ci-toolkit dir require BUILD_DIR "$BUILD_DIR" "run build first"
./ci-toolkit match require DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint require RETAIN_RELEASES "$RETAIN_RELEASES"
./ci-toolkit shell join ssh -i "$DEPLOY_SSH_KEY" -p 22
./ci-toolkit git latest-tag v
./ci-toolkit slack webhook SLACK_WEBHOOK_URL my-service success "deploy complete"
```

### 語法參考：source-mode 規則

Source-mode helper 是一般 Bash function。它們不會 exit 你的腳本；只會回傳 status。依 helper 類型，把它放進 `if`、`||`、command substitution 或 assignment。

```bash
source ./ci-toolkit

ci::require_env DEPLOY_TOKEN || exit $?
ci::retry 3 -- git fetch origin --quiet
if ci::in "${TARGET_ENV:-}" staging production; then ...; fi
repo_root=$(ci::root) || exit $?
```

建議固定使用這些模式：

```bash
# 必要 precondition：guard 失敗就停止。
ci::require_tool git || exit $?
ci::require_env DEPLOY_TOKEN || exit $?

# Predicate / optional branch：直接放進 if。
if ci::is_true RUN_DEPLOY; then
  run_deploy
fi

# Data helper：捕捉 stdout，再處理失敗。
repo_root=$(ci::root) || exit $?
latest_tag=$(ci::git_latest_tag v) || exit $?

# 專案脈絡：predicate 搭配你的錯誤訊息。
ci::version_gt "$new" "$old" || ci::die "tag is not newer" || exit 1
```

### 語法參考：source 與 CLI 對照

| 用途 | Source 語法 | CLI 語法 | 成功輸出 |
| --- | --- | --- | --- |
| 顯示 help | n/a | `./ci-toolkit help` | stdout usage |
| 顯示版本 | n/a | `./ci-toolkit version` | `ci-toolkit X.Y.Z` |
| 列出函式 | `ci::ls` | `./ci-toolkit ls` | stdout function list |
| info log | `ci::info MESSAGE...` | `./ci-toolkit log info MESSAGE` | stderr log line |
| warn log | `ci::warn MESSAGE...` | `./ci-toolkit log warn MESSAGE` | stderr log line |
| error log | `ci::error MESSAGE...` | `./ci-toolkit log error MESSAGE` | stderr log line |
| debug log | `ci::debug MESSAGE...` | `./ci-toolkit log debug MESSAGE` | 只有 `CI_TOOLKIT_DEBUG=1` 時輸出 stderr |
| die helper | `ci::die MESSAGE...` | n/a | error log；回傳 `1` |
| 必要環境變數 | `ci::require_env VAR_NAME` | `./ci-toolkit env require VAR_NAME` | 無 stdout |
| 預設環境變數 | `ci::env_default VAR_NAME DEFAULT` | `./ci-toolkit env default VAR_NAME DEFAULT` | 有效值 stdout |
| 必要工具 | `ci::require_tool TOOL_NAME` | `./ci-toolkit tool require TOOL_NAME` | 無 stdout |
| 重試 command | `ci::retry ATTEMPTS [--delay SECONDS] [--] COMMAND...` | `./ci-toolkit retry [ATTEMPTS] [--delay SECONDS] -- COMMAND...` | 被包住 command 的輸出 |
| 向上找 marker | `ci::find_up MARKER` | n/a | 匹配目錄 stdout |
| 找 git root | `ci::root` | n/a | git root stdout |
| 最新 tag | `ci::git_latest_tag [PREFIX]` | `./ci-toolkit git latest-tag [PREFIX]` | tag stdout |
| 移除 prefix | `ci::strip_prefix PREFIX STRING` | `./ci-toolkit strip-prefix PREFIX STRING` | 結果字串 stdout |
| 版本大於 | `ci::version_gt LHS RHS` | `./ci-toolkit version gt LHS RHS` | status only |
| 版本大於等於 | `ci::version_ge LHS RHS` | `./ci-toolkit version ge LHS RHS` | status only |
| 相等 predicate | `ci::eq ACTUAL EXPECTED` | `./ci-toolkit eq ACTUAL EXPECTED` | status only |
| 不相等 predicate | `ci::ne ACTUAL EXPECTED` | `./ci-toolkit ne ACTUAL EXPECTED` | status only |
| 允許清單 predicate | `ci::in VALUE CANDIDATE...` | `./ci-toolkit in VALUE CANDIDATE...` | status only |
| 排除清單 predicate | `ci::not_in VALUE CANDIDATE...` | `./ci-toolkit not-in VALUE CANDIDATE...` | status only |
| 必要檔案 | `ci::require_file NAME PATH [HINT]` | `./ci-toolkit file require NAME PATH [HINT]` | 無 stdout |
| 必要目錄 | `ci::require_dir NAME PATH [HINT]` | `./ci-toolkit dir require NAME PATH [HINT]` | 無 stdout |
| 正則驗證 | `ci::require_match NAME VALUE REGEX [DESCRIPTION]` | `./ci-toolkit match require NAME VALUE REGEX [DESCRIPTION]` | 無 stdout |
| unsigned int 驗證 | `ci::require_uint NAME VALUE` | `./ci-toolkit uint require NAME VALUE` | 無 stdout |
| shell-escape argv | `ci::shell_join ARG...` | `./ci-toolkit shell join ARG...` | Bash-escaped command string |
| ERR trap | `ci::trap_err` | `./ci-toolkit trap-err` | source 安裝 trap；CLI 回傳 `64` 並提示 |
| Slack webhook | `ci::slack_webhook URL_VAR PROJECT STATUS MESSAGE` | `./ci-toolkit slack webhook URL_VAR PROJECT STATUS MESSAGE` | 無 stdout |

### 語法參考：參數意義

| 名稱 | 意義 | 範例 |
| --- | --- | --- |
| `VAR_NAME` | 環境變數名稱，不是變數值。 | `DEPLOY_TOKEN` |
| `NAME` | 失敗時可安全印出的邏輯名稱。 | `SSH_KEY`, `BUILD_DIR` |
| `PATH` | 要驗證的檔案或目錄路徑；驗證失敗時不印出。 | `"$DEPLOY_SSH_KEY"` |
| `HINT` | 可選修復提示。 | `"mount deploy key"` |
| `REGEX` | Bash extended regular expression。 | `'^[0-9]+$'` |
| `DESCRIPTION` | 安全的規則描述，替代印出 raw value。 | `"digits only"` |
| `ATTEMPTS` | 正整數 retry 次數；CLI retry 省略時預設 `3`。 | `5` |
| `SECONDS` | retry 失敗後的等待秒數。 | `30` |
| `PREFIX` | 字面 prefix，不是 glob。 | `v` |
| `CANDIDATE...` | 一個以上允許/排除的字面字串。 | `staging production` |
| `URL_VAR` | 存 Slack webhook URL 的環境變數名稱。 | `SLACK_WEBHOOK_URL` |

---

<!-- doc-key: discovery-read -->
## 探索與讀取

在更改腳本前、除錯中，或教 AI/code assistant 了解 toolkit 能力時，使用這些命令。

### 列出可用函式

```bash
./ci-toolkit ls
```

`ls` 會印出所有 public `ci::` function 與其 `# @description`。`ci::_...` private helper 會被隱藏。

### 查看 CLI usage

```bash
./ci-toolkit help
```

當你記得 helper 但忘了 CLI 巢狀順序（例如 `file require` 還是 `require file`）時使用。

### 讀取布林旗標

`ci::is_true VAR` 只在變數值為 `1` 或 `true` 時回傳成功。

```bash
RUN_DEPLOY=${RUN_DEPLOY:-0}
if ci::is_true RUN_DEPLOY; then
  ci::info "deploy checks enabled"
fi
```

這能避免腳本各處散落臨時比較。它刻意不把所有非空值都視為 true。

### 讀取路徑與 tag

```bash
repo_root=$(ci::root) || exit $?
latest_release=$(ci::git_latest_tag v) || exit $?
version=$(ci::strip_prefix v "$latest_release")
```

回傳資料的 helper 用 command substitution 捕捉。因為 log 走 stderr，stdout 可以安全放進 `$(...)`。

---

<!-- doc-key: writes-mutations -->
## 寫入與變更

Gungnir 不會自行 deploy、build、publish 或修改你的專案。它包住你的 command，讓會造成變更的腳本更早失敗、重試 transient operation，並提供更清楚的 log。

### 穩健的重試機制

`ci::retry` 最多執行 command `N` 次，成功就立刻回傳；若全部失敗，回傳最後一次 attempt 的 status。失敗 attempt 會把 warn log 寫到 stderr。

```bash
# Source 模式
ci::retry 3 -- curl -fsS https://api.example.com/health
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader

# CLI 模式
./ci-toolkit retry 3 -- curl -fsS https://api.example.com/health
./ci-toolkit retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

retry 適合可能 transient 的操作：registry download、`git fetch`、package install、health probe、`curl`、`rsync` 或 remote API。除非你有明確 flaky infrastructure 原因，否則不要 retry unit test、syntax check 或 build 這類 deterministic failure。

### 安全的環境檢查

`ci::require_env NAME` 檢查名為 `NAME` 的環境變數是否存在且非空。它只印變數名稱，不印變數值。

```bash
ci::require_env REGISTRY_TOKEN || exit $?
printf '%s' "$REGISTRY_TOKEN" | docker login ghcr.io --username ci --password-stdin
```

可選值請用 default：

```bash
ci::env_default REGISTRY_USER ci
ci::env_default DEPLOY_REAL 0
```

### 必要檔案、目錄、格式與整數

用驗證 helper 命名邏輯欄位，並避免把實際值印到 log。

```bash
ci::require_file SSH_KEY "$DEPLOY_SSH_KEY" "create or mount the deploy key" || exit $?
ci::require_dir BUILD_DIR "$BUILD_DIR" "run build first" || exit $?
ci::require_match DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint RETAIN_RELEASES "$RETAIN_RELEASES" || exit $?
```

CLI 對照：

```bash
./ci-toolkit file  require SSH_KEY "$DEPLOY_SSH_KEY" "create or mount the deploy key"
./ci-toolkit dir   require BUILD_DIR "$BUILD_DIR" "run build first"
./ci-toolkit match require DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint  require RETAIN_RELEASES "$RETAIN_RELEASES"
```

### Slack webhook 通知

`ci::slack_webhook URL_VAR PROJECT STATUS MESSAGE` 會用 `URL_VAR` 指定的環境變數取得 Slack webhook URL 並送出簡短 JSON payload。它是 best-effort：URL 空白或缺 `curl` 時只 warn 並回傳成功，避免通知失敗中斷 deploy path。

```bash
ci::slack_webhook SLACK_WEBHOOK_URL "my-service" "success" "release $IMAGE_TAG deployed"
```

CLI 對照：

```bash
./ci-toolkit slack webhook SLACK_WEBHOOK_URL "my-service" "success" "release $IMAGE_TAG deployed"
```

---

<!-- doc-key: advanced-tools -->
## 進階工具

### 日誌與失敗 helper

```bash
ci::info "starting"
ci::warn "optional cache unavailable"
ci::error "preflight failed"
ci::debug "resolved BUILD_DIR=$BUILD_DIR"
ci::die "unsupported deploy target" || exit 1
```

`ci::debug` 只有在 `CI_TOOLKIT_DEBUG=1` 時輸出。`ci::die` 以 error level 記錄並回傳 `1`；它不會替你 `exit`。

### 路徑探索

```bash
repo_root=$(ci::root) || exit $?
config_root=$(ci::find_up package.json) || exit $?
```

`ci::find_up <marker>` 從 `$PWD` 往上找名為 `<marker>` 的檔案或目錄，並印出匹配目錄。`ci::root` 等同 `ci::find_up .git`。

### 版本比較與 tag 探索

```bash
latest=$(ci::git_latest_tag v) || exit $?
version=$(ci::strip_prefix v "$latest")

if ci::version_ge "$version" "1.2.0"; then
  ci::info "release is new enough"
fi

if ci::version_gt "1.2.4" "1.2.3"; then
  ci::info "greater"
fi
```

CLI 對照：

```bash
./ci-toolkit git latest-tag v
./ci-toolkit strip-prefix v v1.2.3
./ci-toolkit version gt 1.2.4 1.2.3
./ci-toolkit version ge 1.2.3 1.2.3
```

這些 helper 依賴 `sort -V`。它們適合 CI version gate 與 release tag，但不是完整 SemVer 2.0 實作。

### 字串 predicate

字串 predicate 只回傳 status，不印出被比較的值。

```bash
branch=$(git branch --show-current)
if ci::eq "$branch" main; then
  ci::info "main branch checks"
fi

if ci::in "${TARGET_ENV:-}" staging production preview; then
  ci::info "accepted target"
else
  ci::die "unsupported TARGET_ENV" || exit 1
fi
```

| Helper | CLI | 行為 |
| --- | --- | --- |
| `ci::eq ACTUAL EXPECTED` | `eq` | `ACTUAL == EXPECTED` 時 exit `0`。 |
| `ci::ne ACTUAL EXPECTED` | `ne` | `ACTUAL != EXPECTED` 時 exit `0`。 |
| `ci::in VALUE CANDIDATE...` | `in` | `VALUE` 符合任一 candidate 時 exit `0`。 |
| `ci::not_in VALUE CANDIDATE...` | `not-in` | `VALUE` 不符合任何 candidate 時 exit `0`。 |

### Shell 參數逃逸

`ci::shell_join` 把 argv array 轉成一個 Bash-escaped command string。這適合 `rsync -e` 這種需要 command string 而非 argv 的工具。

```bash
SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
rsync -e "$RSYNC_SSH" "$BUILD_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"
```

輸出使用 Bash `printf '%q'`。不要把未信任資料透過 `eval` 重新執行。

### 預設 ERR trap

```bash
ci::trap_err
```

`ci::trap_err` 安裝 `ERR` trap，失敗時報告 exit code、`file:line`、function name 與失敗的 `BASH_COMMAND`。它會啟用 `set -E` 讓 trap 傳進 function，但不會替你啟用 `set -e`、`set -u` 或 `pipefail`。

---

<!-- doc-key: diagnostics-recovery -->
## 診斷與恢復

### Exit code

| Code | 意義 |
| --- | --- |
| `0` | 成功。 |
| `1` | runtime check 失敗、predicate 為 false、找不到 marker，或 retry 全部失敗。 |
| `64` | 使用方式錯誤：未知 command、缺少必要參數、retry count 無效、regex 無效，或像 CLI 執行 `trap-err` 這類 source/CLI 模式不匹配。 |

### 疑難排解

| 症狀 | 可能原因 | 修復 |
| --- | --- | --- |
| macOS 出現 `bad array subscript` 或奇怪 Bash 行為 | 腳本跑在 Bash 3.2。 | 使用 `#!/usr/bin/env bash` 並安裝 Bash 4+（`brew install bash`）。 |
| version/tag helper 抱怨 `sort -V` | 你的 `sort` 不支援 version sort。 | 安裝 GNU coreutils，或確保相容 `sort` 在 `PATH` 上。 |
| log 中看不到某個值 | 通常是刻意設計。 | validation helper 避免印值以防 secret leakage；需要時請自己印安全摘要。 |
| `ci::debug` 沒輸出 | debug logging 未啟用。 | 用 `CI_TOOLKIT_DEBUG=1` 執行。 |
| `ci::root` 失敗 | `$PWD` 往上沒有 `.git` 目錄。 | 從 checkout 內執行，或用 `ci::find_up <project-marker>`。 |
| CLI command exit `64` | 參數不符合 `./ci-toolkit help`。 | 重新看 `help`，檢查巢狀 command 順序。 |

### 安全除錯模式

```bash
CI_TOOLKIT_DEBUG=1 ./your-script.sh
```

Source 模式中，把 `ci::trap_err` 與明確 preflight check 放在 `main()` 前段，讓失敗指向真正出錯的 command。

---

<!-- doc-key: ai-integration -->
## AI 代理整合

Gungnir 對 AI 產生 CI/deploy 腳本很有幫助，因為它給 agent 一組小而穩定的 vocabulary，而不是讓 agent 每次都發明自製 Bash helper。

### 建議給 agent 的 prompt

```text
Use ./ci-toolkit for CI primitives. Source it in Bash scripts and prefer ci::info,
ci::warn, ci::die, ci::require_env, ci::require_tool, ci::retry, ci::find_up,
ci::root, validation helpers, and ci::shell_join instead of writing custom helpers.
Keep project-specific build/deploy policy in the script.
```

### 請 agent 保留的規則

- 依腳本位置 source `ci-toolkit`。
- 保持 `main()` entry point 與小型 `run_*` functions。
- 對 secrets 使用 `ci::require_env`，不要 echo 值。
- `ci::retry` 只包 transient network 或 remote operation。
- log 留在 stderr，data helper 從 stdout 捕捉。
- 不要把 CI vendor-specific 假設放進 reusable helper。

### 範例：agent-friendly deployment preflight

```bash
preflight() {
  ci::require_tool git || exit $?
  ci::require_tool rsync || exit $?
  ci::require_env DEPLOY_HOST || exit $?
  ci::require_env DEPLOY_USER || exit $?
  ci::require_file SSH_KEY "$DEPLOY_SSH_KEY" "mount deploy key" || exit $?
}
```

此 repo 也包含給 Claude Code 使用的 `skills/ci-toolkit/`。執行 `scripts/install-skill` 可 symlink 到本機 Claude skills 目錄。

---

<!-- doc-key: documentation-maintenance -->
## 文件維護

使用者文件每個語系都有 Markdown 與 HTML：

```text
docs/user/en/index.md
docs/user/en/index.html
docs/user/zh-TW/index.md
docs/user/zh-TW/index.html
```

每個主要主題都由 doc-key marker comment 錨定。每個語系內 Markdown 與 HTML 的 doc-key 順序必須一致，讓 reference 與 visual surface 保持同步。

修改後執行文件一致性檢查：

```bash
bun run scripts/check-user-docs.ts
```

更完整的 repository 驗證：

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

新增 public helper 時，請依序更新：

1. 在 public `ci::` function 上方新增或更新 `# @description`。
2. 更新 `./ci-toolkit help` usage 與 CLI examples。
3. 新增 source-mode 與 CLI-mode tests。
4. 更新 `README.md`、`CHANGELOG.md` 與 user docs。
5. 執行 doc parity check 與上述 quality gates。
