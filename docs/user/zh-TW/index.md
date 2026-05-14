# Gungnir

<!-- doc-key: overview -->
實驗性的平台中立 CI 腳本 Bash 輔助工具

Gungnir 是一個實驗性的、平台中立的 Bash 工具包，旨在簡化 CI/CD 腳本。它提供單一檔案，既可以作為 CLI 工具執行，也可以作為可引入（source）的 Bash 函式庫，整合了結構化日誌記錄、環境變數驗證和穩健的指令重試等常見模式。

---

<!-- doc-key: install-setup -->
## 安裝與設定

直接在您的 CI 環境中使用 `curl` 和 `chmod` 安裝 `ci-toolkit` 檔案。我們建議固定到特定的發佈標籤（release tag）以確保穩定性：

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.5/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

對於本地開發或作為 AI 技能，您可以使用提供的 `scripts/install-skill` 將工具包軟連結（symlink）到您的 Claude Code 技能目錄中。

### 對比：為什麼要使用 Gungnir？

| 任務 | 原始 Bash 語法 | Gungnir `ci-toolkit` |
|------|---------------|----------------------|
| **日誌記錄** | `echo "[INFO] starting"` | `ci::info "starting"` (標準化 stderr, 支援顏色) |
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
