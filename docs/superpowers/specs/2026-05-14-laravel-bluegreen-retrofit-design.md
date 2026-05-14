# Laravel blue-green deploy retrofit — Gungnir ci-toolkit example

**狀態**：Spec / Brainstorm 階段
**日期**：2026-05-14
**範圍**：新增 `examples/laravel-bluegreen-deploy/` 範例 + 反饋 4 項 ci-toolkit API 提案

---

## 1. Context

來源腳本：`/Users/carl/Dev/CMG/StationHub/scripts/deploy/shared/deploy-script.sh`。約 326 行 Laravel 部署流程，特徵：

- **多主機藍綠部署**：用 associative array `TARGET_HOSTS` / `BEFORE_COMMANDS` / `MIDDLE_COMMANDS` 並對每台主機在 `site_blue` / `site_green` 之間翻轉 symlink。
- **遠端 SSH heredoc**：在每台主機跑 `cd $TARGET_DIR; ln -sfn ...; php artisan optimize:clear; supervisorctl update; queue:restart`。
- **CloudWatch log group 命名清洗**：5 段 `tr -d '\r\n\t' | sed 's/...//' | sed 's/^...//' | sed 's/.../_/g'` pipeline 重複。
- **本地 build**：composer install（失敗 sleep 30 重試）+ `npm i && npm run build`。
- **Slack 通知**：含 emoji、版本 diff log、環境/時間多行模板，並掛 `trap '... send_slack_notification failed ...' ERR`。
- **CLI flags**：`--skip`、`--tag=value`、`--cloudwatch`。
- **版本比較**：tag prefix 預設 `release/`，用 `printf '%s\n' a b | sort -V | head -n1` 比大小，必要時退出。

與 Gungnir 現有兩個範例對照：

| 範例 | 角色 | 與本案差異 |
| --- | --- | --- |
| `bun-deploy/` | 端到端可執行的 Bun/TypeScript 部署 | 本案是 code-reference，不要求可跑 |
| `vendored-deploy-script/` | 精簡 retrofit case study（單主機 + Slack + git） | 本案展示**進階**場景：藍綠 + 多主機 + Laravel post-deploy + CloudWatch |

---

## 2. Goals & Non-goals

**Goals**

- 提供進階 retrofit case study；讓讀者一眼認出 StationHub 風格腳本如何套 ci-toolkit。
- 透過實際重寫過程，識別並提案 4 項對 ci-toolkit 高 ROI 的新 API。
- 透過「不建議收」附錄，宣告 ci-toolkit 不打算碰的邊界。

**Non-goals**

- 端到端可執行（不 mock SSH / rsync）。
- 本次不改 ci-toolkit 本體；4 項提案 API 各自之後獨立成 plan。
- 不修改現有 `bun-deploy/` 或 `vendored-deploy-script/` 範例。
- 不新增 `tests/test_*.sh`（範例本身不可跑）。
- 不替換原版的領域邏輯（藍綠翻轉、CloudWatch 命名、Laravel post-deploy 全部原樣保留）。

---

## 3. Example layout

```
examples/laravel-bluegreen-deploy/
├── ci-toolkit          symlink -> ../../ci-toolkit
├── deploy-prod.sh      重寫後的腳本（與原版同檔名）
└── README.md           對照表 + 採用步驟 + 環境變數
```

`ci-toolkit` symlink 與既有兩個範例同模式，方便 `bash -n` 直接通過。`deploy-prod.sh` 仍是 code-reference：可 `bash -n` 但不能跑，因為需要外層 wrapper 餵入 `TARGET_HOSTS`、`BEFORE_COMMANDS`、`MIDDLE_COMMANDS`、SSH key、Slack webhook 等。

CHANGELOG.md 與 ci-toolkit 本體**不動**。

---

## 4. Rewrite strategy

### 4.1 取代表

| 原版（行號為 StationHub 版） | 重寫後 |
| --- | --- |
| L1 `#!/bin/bash` | `#!/usr/bin/env bash` + `set -euo pipefail`（README 註明 strict mode 新增） |
| L11 `TAG_PREFIX="${TAG_PREFIX:-release/}"` | `ci::env_default TAG_PREFIX "release/"` |
| L33-35 未知參數 `echo + exit 1` | `ci::die "unknown arg: $1" \|\| exit 1` |
| L43-46 SLACK_WEBHOOK_URL 缺值警告 | `ci::slack_webhook` 內建跳過邏輯 |
| L89 `trap '... send_slack_notification ... ' ERR` | local 保留；註解 `# proposed: ci::trap_err` 指向 §5.4 |
| L92 `cd $PROJECT_DIR`（缺檢查） | `ci::require_env PROJECT_DIR \|\| exit 1; cd "$PROJECT_DIR"` |
| L99 `git describe --tags --abbrev=0` | 保留（current tag 取得 — 與 latest 不同語意） |
| L102-104 `git fetch origin` / `git fetch --tags` / `git pull origin` | 各包 `ci::retry 3 ...` |
| L107 `git tag -l "${TAG_PREFIX}*" \| sort -V \| tail -n1` | `ci::git_latest_tag "$TAG_PREFIX"` |
| L111-112 `${TAG#${TAG_PREFIX}}` | local helper；註解 `# proposed: ci::strip_prefix` 指向 §5.3 |
| L115-119 版本比較退出 | local helper；註解 `# proposed: ci::version_gt` 指向 §5.2 |
| L128-129 composer 完整路徑 + env | `ci::require_tool composer \|\| exit 1`（路徑改 PATH 解析） |
| L132-136 composer install + `sleep 30` + retry | local `if !; then sleep 30; ...; fi`；註解 `# proposed: ci::retry --delay` 指向 §5.1 |
| L138-139 `npm i && npm run build` | `ci::require_tool npm`；命令本身保留 |
| L143-174 多主機 rsync 區段 | local 保留（藍綠 + rsync policy） |
| L177-294 多主機 SSH heredoc 區段 | local 保留（artisan / supervisord / CloudWatch policy） |
| L200-203 CloudWatch 變數清洗 x4 | local helper `sanitize_cloudwatch_token` 抽出，**不**進 ci-toolkit（§6 附錄） |
| L227-233 log group `printf` 組裝 | local helper `compute_cloudwatch_log_group` |
| L300-322 條件式建立 log group + `source` 子腳本 | local 保留；`source` 前用 `[[ -f ... ]] \|\| ci::warn` 防護，因為 `remote-cloudwatch-setup.sh` 不在範例 repo 內 |
| L325 success 通知 | local Slack 模板，內部呼叫 `ci::slack_webhook` 送 curl |

### 4.2 保留的 local 函式清單

| 函式 | 為何不抽到 ci-toolkit |
| --- | --- |
| `parse_cli` | CLI flag 政策（toolkit 設計刻意不做 argv 解析） |
| `send_slack_notification` | 多行訊息模板：emoji + commit log + 環境/版本/時間是專案政策 |
| `strip_tag_prefix`（暫時） | 等 §5.3 提案落地後移除 |
| `compare_versions_or_exit`（暫時） | 等 §5.2 提案落地後移除 |
| `compose_err_trap`（暫時） | 等 §5.4 提案落地後移除 |
| `sanitize_cloudwatch_token` | CloudWatch 命名規範特定，§6.3 列入 not-collected |
| `compute_cloudwatch_log_group` | 同上 |
| `deploy_files_to_host` / `run_post_deploy_on_host` | 藍綠翻轉、SSH heredoc 與多主機迭代政策 |
| `parse_blue_green_target_dir` | 藍綠目錄判斷 policy |

### 4.3 提案 API 註解規則

每個 local 暫時函式上方加一行統一格式註解：

```bash
# proposed: ci::strip_prefix VALUE PREFIX (see spec §5.3, plan TBD)
strip_tag_prefix() {
    local tag="$1" prefix="$2"
    printf '%s\n' "${tag#$prefix}"
}
```

讀者可從註解直接跳到 spec 對應節找完整提案；當對應 plan 落地後，這個 local 函式會被刪除、`ci::*` 函式取而代之。

---

## 5. Feedback to ci-toolkit

按「契合 ci-toolkit 平台中立哲學」由強到弱排序。**本案不實作這 4 項**；每項日後各自獨立成 plan，再走 TDD 流程。

### 5.1 `ci::retry` 加 `--delay SECONDS`

**提案簽名**

```bash
ci::retry [ATTEMPTS] [--delay SECONDS] -- COMMAND...
# 例：
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

**動機**：原版 L132-136 用 `if ! composer; then sleep 30; composer; fi` 處理 packagist 抖動 — 一個常見的 CI 重試場景。當前 `ci::retry` 零延遲，對網路 / registry 限速幾乎無用。

**最小可行實作雛形（草稿，非正式 plan）**

```bash
ci::retry() {
  local attempts="${1:-}" delay=0
  shift || true
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --delay) delay="$2"; shift 2 ;;
      --) shift; break ;;
      *) ci::error "ci::retry: unknown option $1"; return 64 ;;
    esac
  done
  # ...rest same as today; if status != 0 and attempt < attempts: sleep "$delay"
}
```

**測試要點**

- `ci::retry 3 -- false` — 三次都失敗，退出碼正確。
- `ci::retry 2 --delay 1 -- bash -c '...'` — 第一次失敗第二次成功，總耗時 ≥ 1s。
- `ci::retry 3 --delay 0 -- ...` — 與舊行為等價。
- CLI 模式 `ci-toolkit retry 2 --delay 1 -- false`。
- `--delay -1` / `--delay foo` 回傳 64。

**風險 / 取捨**

- CLI 旗標位置：`--delay` 必須在 `ATTEMPTS` 之後、`--` 之前。需更新 `ci::cmd_retry` 與 usage。
- 未來若再加 `--backoff exp` / `--max-delay`，要避免 flag 互動爆炸；先只收 `--delay`。

---

### 5.2 `ci::version_gt A B` / `ci::version_ge A B`

**提案簽名**

```bash
ci::version_gt NEW CURRENT    # 返回 0 if NEW > CURRENT
ci::version_ge NEW CURRENT    # 返回 0 if NEW >= CURRENT
```

**動機**：原版 L115、L63 兩處重複 `printf '%s\n' a b | sort -V | head -n1 != b` 判斷。tag/release 版本比較是 CI 通用需求，不綁專案。

**最小可行實作雛形**

```bash
ci::version_gt() {
  local a="${1:-}" b="${2:-}"
  [[ -z "$a" || -z "$b" ]] && { ci::error "Usage: ci::version_gt A B"; return 64; }
  [[ "$a" == "$b" ]] && return 1
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" ]]
}
```

**測試要點**

- `ci::version_gt 1.10.0 1.9.0` → 0
- `ci::version_gt 1.9.0 1.10.0` → 1
- `ci::version_gt 1.2.3 1.2.3` → 1（_gt 相等回 false）
- `ci::version_ge 1.2.3 1.2.3` → 0
- 含 prefix 應在呼叫前先 strip：`ci::version_gt v2 v10` 仍要正確排序（`sort -V` 本身能處理）。
- CLI 模式：`ci-toolkit version gt 1.10 1.9; echo $?`

**風險 / 取捨**

- `sort -V` 行為在 BSD / GNU sort 上一致但 macOS 預設 `/usr/bin/sort` 是 BSD；測試需在 macOS + Linux 雙跑（與既有測試一致）。
- 是否同時加 `version_eq` / `version_lt` 為對稱性 — 建議第一版只收 `_gt` / `_ge`，其他需要時再加。

---

### 5.3 `ci::strip_prefix VALUE PREFIX`

**提案簽名**

```bash
stripped=$(ci::strip_prefix "$tag" "$TAG_PREFIX")
# CLI:
ci-toolkit strip-prefix release/1.2.3 release/   # → 1.2.3
```

**動機**：原版 L111-112、L59-60 共 4 處 `${VAR#$PREFIX}`；雖然純 bash 一行能寫，CLI 模式對 Makefile / GitHub Actions step / 其他 shell 子腳本有價值。

**最小可行實作雛形**

```bash
ci::strip_prefix() {
  local value="${1?Usage: ci::strip_prefix VALUE PREFIX}"
  local prefix="${2?Usage: ci::strip_prefix VALUE PREFIX}"
  printf '%s\n' "${value#$prefix}"
}
```

**測試要點**

- `ci::strip_prefix release/1.2.3 release/` → `1.2.3`
- 不匹配 prefix → 原值不動
- 空 prefix → 原值不動
- CLI 模式整合測試

**風險 / 取捨**

- 純 source 模式 ROI 低（`${VAR#$PREFIX}` 已夠）；主價值在 CLI 模式。文件需老實說明：source 模式 caller 仍可直接用 bash 內建。
- 是否同時加 `ci::strip_suffix`（`${VAR%$SUFFIX}`）對稱 — 同 §5.2 處理原則，第一版不加。

---

### 5.4 `ci::trap_err NOTIFY_CMD`

**提案簽名**

```bash
ci::trap_err 'send_slack_notification failed "Script failed at line $LINENO"'
```

**動機**：原版 L89 模式 — 失敗時送通知、退出 — 是 CI 腳本的高重複樣板（vendored-deploy-script 也有類似需求但避開了）。

**最小可行實作雛形**

```bash
ci::trap_err() {
  local cb="${1:-}"
  [[ -z "$cb" ]] && { ci::error "Usage: ci::trap_err CALLBACK"; return 64; }
  set -E
  trap "$cb" ERR
}
```

**測試要點**

- 觸發失敗時 callback 真的被叫到。
- callback 內可讀到 `$LINENO`。
- 函式內失敗也會觸發（`set -E` 效果）。
- 二次呼叫覆蓋既有 ERR trap。

**風險 / 取捨**

- `set -E` 與 `set -e` 在子函式中互動微妙（subshell 行為、`||` chain），文件需附「採用前注意事項」。
- callback 字串內 `$LINENO` 等變數 expansion 時機：傳入時為單引號（lazy）vs 雙引號（eager）。本提案語意採 lazy；文件要明寫並用 single-quote 範例。
- 風險最大的一項；plan 階段需要更細的測試矩陣。

---

## 6. Not-collected appendix

下列 8 項在重寫過程中也察覺到，但**不**建議收入 ci-toolkit。理由各一行。

1. **CLI flag parser**（`--skip` / `--tag=`）— ci-toolkit 設計刻意不碰 argv 解析（屬應用層）。
2. **Slack 多行訊息模板**（emoji + commit log + 環境）— 訊息格式是專案政策，`ci::slack_webhook` 只保證 transport 重試。
3. **CloudWatch token 清洗**（`tr | sed | sed | sed`）— 命名規範屬特定 cloud provider 政策。
4. **CloudWatch log group `printf` 組裝** — 同 3，與 ci-toolkit 平台中立目標衝突。
5. **SSH heredoc 包裝** — 遠端 quoting / interpolation 風險點，做成通用 wrapper 弊大於利。
6. **多主機 associative array 迭代**（`TARGET_HOSTS` / `BEFORE_COMMANDS` / `MIDDLE_COMMANDS`）— 多主機編排是專案 topology 政策。
7. **Blue/green 目錄翻轉**（`readlink + 切換`）— 部署策略屬應用層政策。
8. **rsync 命令包裝**（`--rsync-path="sudo rsync"`、exclude policy）— 同步策略屬政策。

備註：3、4 是同一類議題 — 任何「pattern → 平台 logger / cloud naming」的 wrapper 都不收。

---

## 7. Testing & verification

- `bash -n examples/laravel-bluegreen-deploy/deploy-prod.sh` 必須通過。
- 不新增 `tests/test_*.sh`：範例本身不可執行，沒有可斷言的執行行為。
- `./scripts/lint` 維持原行為（ShellCheck 有裝就跑）。新範例腳本目標是過 ShellCheck；若原 StationHub 風格在 ShellCheck 下有結構性誤判（如 associative array 經 sourcing 注入），允許用 `# shellcheck disable=SCxxxx` 並在註解標明原因。
- README 含「採用步驟」與「環境變數」表，與既有兩個範例風格一致。

---

## 8. Out-of-scope follow-ups

本 spec 落地後，下列 4 項各自獨立成 plan，再走 TDD：

1. plan: `ci::retry --delay`（§5.1）
2. plan: `ci::version_gt` / `ci::version_ge`（§5.2）
3. plan: `ci::strip_prefix`（§5.3）
4. plan: `ci::trap_err`（§5.4）

每項 plan 落地後，`examples/laravel-bluegreen-deploy/deploy-prod.sh` 內對應的 local 暫時函式可被刪除、改呼 `ci::*`。屆時更新範例的 PR 一併移除 `# proposed: ...` 註解。
