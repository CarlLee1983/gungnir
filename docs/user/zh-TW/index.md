# Gungnir

<!-- doc-key: overview -->
實驗性的平台中立 CI 腳本 Bash 輔助工具

Gungnir 是一個實驗性的、平台中立的 Bash 工具包，旨在簡化 CI/CD 腳本。它提供單一檔案，既可以作為 CLI 工具執行，也可以作為可引入（source）的 Bash 函式庫，整合了結構化日誌記錄、環境變數驗證和穩健的指令重試等常見模式。

---

<!-- doc-key: install-setup -->
## 安裝與設定

直接在您的 CI 環境中使用 `curl` 和 `chmod` 安裝 `ci-toolkit` 檔案。我們建議固定到特定的發佈標籤（release tag）以確保穩定性：

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.8/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

對於本地開發或作為 AI 技能，您可以使用提供的 `scripts/install-skill` 將工具包軟連結（symlink）到您的 Claude Code 技能目錄中。

### 對比：為什麼要使用 Gungnir？

| 任務 | 原始 Bash 語法 | Gungnir `ci-toolkit` |
|------|---------------|----------------------|
| **日誌記錄** | `echo "[INFO] starting"` | `ci::info "starting"` (結構化 stderr 日誌，附等級前綴) |
| **環境變數檢查** | `if [[ -z "$TOKEN" ]]; then ...; exit 1; fi` | `ci::require_env TOKEN` (簡潔、安全、防呆) |
| **指令重試** | `for i in {1..3}; do cmd && break; sleep 1; done` | `ci::retry 3 cmd` (完整保留退出碼與輸出) |
| **路徑定位** | `$(cd "$(dirname "$0")"/.. && pwd)` | `ci::root` 或 `ci::find_up .git` |

<!-- doc-key: connections -->
## 環境與初始化

Gungnir 需要 **Bash 4+**。它被設計為平台中立，不對特定的 CI 供應商（如 GitHub Actions 或 GitLab）做任何假設。

### Source 模式 vs CLI 模式

- **Source 模式 (建議腳本使用)**: `source ./ci-toolkit` 讓您可以使用 `ci::` 開頭的函式。這些函式會回傳狀態碼且**不會**呼叫 `exit`，讓您的腳本保有完全的控制權。
- **CLI 模式**: 直接執行 `./ci-toolkit`。發生錯誤時會以非零狀態碼 `exit`，適合放在 `workflow.yml` 或 `Makefile` 中的單行指令。

### 環境變數
- **`CI_TOOLKIT_DEBUG=1`**: 啟用詳細的偵錯日誌輸出至 stderr。
- **`ci::env_default VAR VALUE`**: 當變數未設定時，安全地設定一個預設值。

<!-- doc-key: discovery-read -->
## 探索與讀取

在不進行任何更改的情況下探索工具包的功能：

- **`ci::ls`**: 列出所有可用的函式及其描述。這是了解可用功能最快的方法。
- **`ci::is_true VAR`**: 對布林值變數進行穩健檢查。如果變數為 `1` 或 `true` 則回傳成功。

**原始 Bash 對比：**
```bash
# 原始 Bash (容易出錯)
if [[ "${SKIP_TESTS:-}" == "true" ]]; then ...

# Gungnir (穩健)
if ci::is_true SKIP_TESTS; then ...
```

<!-- doc-key: writes-mutations -->
## 寫入與變更

### 穩健的重試機制
Gungnir 的 `ci::retry` 比簡單的迴圈更強大。它會保留最後一次嘗試的退出狀態，並將失敗記錄到 stderr。可加上 `--delay SECONDS` 在失敗的嘗試之間 sleep — 適用於 package registry、deploy target 等需要喘息的上游服務。

**範例：不穩定的網路呼叫**
```bash
# 原始 Bash (冗長且容易寫錯)
n=0; until [ "$n" -ge 3 ]; do
  curl -fsS https://api.example.com && break
  n=$((n+1)); sleep 1
done

# Gungnir
ci::retry 3 curl -fsS https://api.example.com

# 兩次嘗試之間相隔 30 秒（適合 registry / package manager）
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

### 安全的環境檢查
`ci::require_env` 確保變數存在，且不會意外印出其內容（即使在某些環境中開啟了 `set -x`）。

<!-- doc-key: advanced-tools -->
## 進階工具

### 路徑發現
在 CI 中尋找儲存庫根目錄或特定的配置檔案通常很麻煩。

- **`ci::find_up <marker>`**: 從當前目錄向上搜尋，直到找到名為 `<marker>` 的檔案或目錄。
- **`ci::root`**: `ci::find_up .git` 的快捷方式。

**原始 Bash 對比：**
```bash
# 原始 Bash (深度固定，若腳本移動位置就會失效)
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)

# Gungnir (動態搜尋，從任何子目錄皆可運作)
REPO_ROOT=$(ci::root)
```

### 版本字串比較

用於比較類 semver 字串（工具版本、git tag）時，無須再手刻容易出錯的字典序檢查 `[[ "$a" > "$b" ]]`。底層使用 `sort -V`。

```bash
# Source 模式
if ci::version_ge "$BUN_VERSION" "1.1.0"; then
  ci::info "bun is new enough"
fi

# CLI 模式
./ci-toolkit version gt 1.2.4 1.2.3   # exits 0
./ci-toolkit version ge 1.2.3 1.2.3   # exits 0
```

這兩個輔助函式可接受 `vX.Y.Z`、`X.Y.Z`、`X.Y` 以及簡單的 pre-release tag。build metadata（如 `1.0.0+build42`）會以字典序比較其尾段 — 對 CI 場景已夠用，但不等同於 SemVer 2.0 嚴格規範。

### 字串前綴移除

`${var#prefix}` 的小型包裝，CLI 模式同樣可用，且會將 glob 字元視為字面值。

```bash
# Source 模式
TAG=$(ci::git_latest_tag v)
VERSION=$(ci::strip_prefix v "$TAG")   # v1.2.3 -> 1.2.3

# CLI 模式
./ci-toolkit strip-prefix v v1.2.3     # -> 1.2.3
```

若前綴不存在，原字串會原封不動回傳。

### 字串述詞

CI 條件判斷最常出現的需求 —「這個字串等於那個字串嗎？」、「這個值是否在允許清單裡？」— 都收斂到四個輕量的狀態碼輔助函式。它們以字面字串比對為基礎，不支援萬用字元、正則或大小寫忽略，且**永遠不會印出比較的值**，因此對可能含有敏感資訊的輸入也安全。

```bash
# Source 模式
branch=$(git branch --show-current)
if ci::eq "$branch" main; then
  ci::info "running main-branch checks"
fi

target_env="${TARGET_ENV:-}"
if ci::in "$target_env" staging production preview; then
  ci::info "accepted deploy target: $target_env"
else
  ci::die "unsupported deploy target: $target_env" || exit 1
fi

# CLI 模式
./ci-toolkit eq "$TARGET_ENV" production
./ci-toolkit in  "$TARGET_ENV" staging production preview
./ci-toolkit not-in "$TARGET_ENV" dev experimental
```

| 輔助函式 | CLI | 行為 |
| --- | --- | --- |
| `ci::eq ACTUAL EXPECTED` | `eq` | `ACTUAL == EXPECTED` 時離開碼 `0`。 |
| `ci::ne ACTUAL EXPECTED` | `ne` | `ACTUAL != EXPECTED` 時離開碼 `0`。 |
| `ci::in VALUE CANDIDATE...` | `in` | `VALUE` 與任一 `CANDIDATE` 字面相等時離開碼 `0`。 |
| `ci::not_in VALUE CANDIDATE...` | `not-in` | `VALUE` 與所有 `CANDIDATE` 都不相等時離開碼 `0`。 |

少於 2 個參數視為使用方式錯誤，回傳 `64`，且不會印出任何值。

### 驗證輔助函式

四個短小的驗證函式，把腳本裡重複的 guard 區塊收斂成具名契約。失敗時只報「邏輯欄位名稱」，**不會印出 VALUE 或 PATH 的內容**，因此可以安全用於敏感輸入。

```bash
# Source 模式
ci::require_file LATEST_NAME_FILE "$DIST_DIR/.latest-name" "run build.sh first" || exit $?
ci::require_dir  STAGING_DIR       "$STAGING_DIR" "run build.sh first" || exit $?
ci::require_match DEPLOY_USER     "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint  DEPLOY_RETAIN   "$DEPLOY_RETAIN" || exit $?

# CLI 模式
./ci-toolkit file  require LATEST_NAME_FILE "$DIST_DIR/.latest-name"
./ci-toolkit dir   require STAGING_DIR      "$STAGING_DIR"
./ci-toolkit match require DEPLOY_USER      "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'
./ci-toolkit uint  require DEPLOY_RETAIN    "$DEPLOY_RETAIN"
```

| 輔助函式 | CLI | 行為 |
| --- | --- | --- |
| `ci::require_file NAME PATH [HINT]` | `file require` | `PATH` 不存在或不是檔案時離開碼 `1`。 |
| `ci::require_dir NAME PATH [HINT]` | `dir require` | `PATH` 不存在或不是目錄時離開碼 `1`。 |
| `ci::require_match NAME VALUE REGEX [DESCRIPTION]` | `match require` | `VALUE` 不符 Bash 延伸正則 `REGEX` 時離開碼 `1`。 |
| `ci::require_uint NAME VALUE` | `uint require` | `VALUE` 不是 `^[0-9]+$` 時離開碼 `1`。 |

使用方式錯誤一律回傳 `64`，並且**不會**將被拒絕的值寫入 stderr。

### Shell 參數逃逸

`ci::shell_join`（CLI：`shell join`）把 argv 陣列展開成單一的 shell-escaped 字串，可被 Bash 重新解析。典型用途是把命令字串塞進 `rsync -e` 之類只接受字串、不接受 argv 陣列的旗標。

```bash
source ./ci-toolkit

SSH_OPTS=(-i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
rsync -e "$RSYNC_SSH" "$STAGING_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"
```

輸出使用 Bash 內建的 `printf '%q'`，所以逃逸結果是 Bash-specific，不保證在 POSIX sh 下可移植。本工具鏈目標就是 Bash 4+，這是有意為之的。**不要**將其結果交給未驗證資料的 `eval`。

### 預設 ERR 陷阱

`ci::trap_err` 安裝一條精簡的 ERR trap，CI 腳本中任何失敗的指令都會印出 `exit code`、`file:line`、函式名稱與失敗的 `BASH_COMMAND`。僅在 source 模式生效 — CLI 形式只是說明用途。

```bash
source ./ci-toolkit
ci::trap_err

# 之後任何失敗的指令都會印出：
# [error] command failed (exit=1) at deploy.sh:42 in run_migrations: psql -c "..."
```

它會啟用 `set -E`（errtrace），讓 trap 可傳播進入函式內部，但不會動 `set -e/-u/pipefail` — 您原本的流程控制完全保留。第二次呼叫 `ci::trap_err` 會直接取代前一次（Bash `trap` 標準語意）。

<!-- doc-key: diagnostics-recovery -->
## 診斷與恢復

Gungnir 幫助您構建具有「自我修復」能力或描述性的 CI 腳本。

- **`ci::die "Message"`**: 記錄錯誤並回傳 `1`。在您的主腳本邏輯中搭配 `|| exit 1` 使用。
- **`ci::require_tool`**: 透過預先檢查依賴項，防止在執行到一半時才出現「command not found」錯誤。

<!-- doc-key: ai-integration -->
## AI 代理整合

Gungnir 是為 AI 優先開發而構建的。它附帶了一個 **Claude Code 技能** (`skills/ci-toolkit/`)，可幫助 LLM 識別何時使用該工具包。

**如何幫助代理：**
1. **減少程式碼**: 代理撰寫更少的樣板程式碼，減少出錯機會。
2. **標準化**: 代理撰寫的每個腳本都遵循相同的日誌記錄和錯誤處理模式。
3. **安全**: 代理使用 `ci::require_env` 而不是手動檢查變數，防止機密資訊洩漏。

<!-- doc-key: documentation-maintenance -->
## 文件維護

Gungnir 使用 Markdown 和 HTML 雙重格式維護文件。每個主題都由 `<!-- doc-key: id -->` 註釋錨定。

跨語系和格式的一致性通過以下方式驗證：
```bash
bun run scripts/check-user-docs.ts
```
這確保了參考文件 (`index.md`) 和視覺界面 (`index.html`) 始終以相同的順序呈現相同的功能。
