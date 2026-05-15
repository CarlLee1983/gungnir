# ci-toolkit v0.1.6 utility helpers — Design Spec

- **Spec date**: 2026-05-14
- **Status**: Approved (pending user review of written spec)
- **Target version**: `0.1.6`
- **Scope**: Three new public helpers in `ci-toolkit` — `ci::version_gt` / `ci::version_ge`, `ci::strip_prefix`, `ci::trap_err`. No example retrofits in this release.

## 1. Motivation

CI scripts written against `ci-toolkit` repeatedly hand-roll three concerns:

1. **Semver-style comparison** of git tags, tool versions, or pinned dependencies — typically with brittle `if [[ "$a" > "$b" ]]` lexicographic checks.
2. **Stripping a known prefix** (most often `v` from git tags) before passing the version onward. The natural `${var#prefix}` works in source mode but isn't available from CLI pipelines.
3. **Producing a useful error message when a script aborts** — current scripts either get silent failures or have to copy-paste a custom `trap ... ERR` boilerplate per file.

These are small but ubiquitous. Packaging them into the toolkit makes the affected scripts smaller and the failures uniform.

## 2. Non-goals

- Full SemVer 2.0 compliance (build-metadata ordering, exact pre-release precedence). Comparison piggybacks on `sort -V`, which is "good enough" for the realistic inputs in CI.
- Generic string manipulation library. `strip_prefix` is the only string helper this release; `strip_suffix`, `trim`, etc. are out of scope.
- Stack-aware trap chaining or EXIT cleanup composition. `ci::trap_err` installs one ERR trap and replaces any previous one.
- Modifying `set -e` / `set -u` / `set -o pipefail` in the caller's shell. Only `set -E` (errtrace) is touched, because the trap is useless without it.
- Retrofitting examples (`examples/laravel-bluegreen-deploy`, `examples/bun-deploy`, `examples/vendored-deploy-script`). Tracked separately.

## 3. API surface

### 3.1 Source-mode (library) functions

```bash
ci::version_gt LHS RHS       # exit 0 iff LHS >  RHS
ci::version_ge LHS RHS       # exit 0 iff LHS >= RHS
ci::strip_prefix PREFIX STR  # prints STR (prefix removed if present) on stdout
ci::trap_err                 # installs default ERR trap; enables set -E
```

All four functions follow existing toolkit conventions:

- Public name in the `ci::` namespace.
- Each carries a `# @description` comment immediately above, surfaced by `ci::ls` and enforced by `scripts/release-check`.
- Library form returns a status code; never calls `exit`.
- Logs go to stderr via `ci::error` / `ci::log`; data goes to stdout.

### 3.2 CLI commands

```
ci-toolkit version              # unchanged — prints toolkit name + version
ci-toolkit version gt LHS RHS   # new sub-command
ci-toolkit version ge LHS RHS
ci-toolkit strip-prefix P STR
ci-toolkit trap-err             # informational stub (see 4.3)
```

The `version` command is extended in a backward-compatible way: with zero positional args it preserves the existing "print toolkit version" behavior; with `gt` / `ge` it dispatches to comparison.

## 4. Behavior contracts

### 4.1 `ci::version_gt` / `ci::version_ge`

| Situation | Behavior |
| --- | --- |
| Two non-empty args, comparable | `gt`: exit 0 if LHS > RHS else exit 1. `ge`: exit 0 if LHS ≥ RHS else exit 1. |
| `LHS == RHS` (string equal) | `gt` exits 1; `ge` exits 0. |
| Missing arg or empty string | stderr: `Usage: ci::version_gt LHS RHS` / `ci::version_ge LHS RHS`; exit 64. |
| stdout | Never written (predicate only). |

**Implementation backbone**

```bash
ci::version_gt() {
  if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
    ci::error "Usage: ci::version_gt LHS RHS"
    return 64
  fi
  [[ "$1" != "$2" ]] || return 1
  local smaller
  smaller=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)
  [[ "$smaller" == "$2" ]]
}

ci::version_ge() {
  if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
    ci::error "Usage: ci::version_ge LHS RHS"
    return 64
  fi
  [[ "$1" == "$2" ]] || ci::version_gt "$1" "$2"
}
```

`sort -V` is on macOS coreutils via `brew install coreutils` and on every modern Linux distribution; it ships with the busybox builds CI runners typically use. Tests do not mock it — the assumption is that callers running `ci-toolkit` already have a sane userland.

**Accepted input shapes** are whatever `sort -V` orders. Known good: `1.2.3`, `v1.2.3`, `1.2`, `1.2.3-rc1`, `2020.07.01`. Build metadata (`1.0.0+build42`) is sorted lexicographically by the tail — acceptable for CI but documented as a limitation.

### 4.2 `ci::strip_prefix`

| Situation | Behavior |
| --- | --- |
| `STR` starts with `PREFIX` | stdout: stripped string; exit 0. |
| `STR` does not start with `PREFIX` | stdout: original `STR`; exit 0. |
| `PREFIX` is empty | stdout: original `STR`; exit 0 (no-op). |
| `STR` is empty | stdout: empty; exit 0. |
| Fewer than 2 positional args supplied | stderr: `Usage: ci::strip_prefix PREFIX STRING`; exit 64. |
| stderr | Never written on success. |

**Implementation**

```bash
ci::strip_prefix() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::strip_prefix PREFIX STRING"
    return 64
  fi
  local prefix="$1"
  local value="$2"
  printf '%s\n' "${value#"$prefix"}"
}
```

The quoted `"$prefix"` in `${value#"$prefix"}` is critical: it disables glob interpretation so callers can strip `*`, `?`, `[abc]` literally.

### 4.3 `ci::trap_err`

| Situation | Behavior |
| --- | --- |
| Called from source mode | Runs `set -E` in caller's shell; installs `trap '<handler>' ERR`. Returns 0. |
| Trap fires | One line to stderr: `[error] command failed (exit=N) at FILE:LINE in FUNC: BASH_COMMAND`. Does not call `exit`. |
| Called twice | Second call replaces the first (Bash semantics for `trap`). No error. |
| CLI (`ci-toolkit trap-err`) | stderr: `ci::trap_err: only effective in source mode (use: source ci-toolkit && ci::trap_err)`; exit 64. |
| Modifies other shell options | No. Only `set -E`. |

**Implementation**

The handler is inlined into the `trap` argument so there is no auxiliary `ci::*` function to document. (`ci::ls` lists every function matching `^ci::.*\(\)` other than `ci::cmd_*`, `ci::dispatch`, and `ci::usage`; introducing a private helper would either leak it via `ls` or require touching `ci::ls`, which is out of scope for v0.1.6.)

```bash
ci::trap_err() {
  set -E
  # shellcheck disable=SC2016  # variables expand at trap time, not now
  trap 'printf "[error] command failed (exit=%s) at %s:%s in %s: %s\n" \
    "$?" "${BASH_SOURCE[0]}" "${LINENO}" "${FUNCNAME[0]:-main}" "${BASH_COMMAND}" >&2' ERR
}
```

`$?` is captured first inside the trap body — that's the canonical Bash trick to preserve the exiting command's status. All five fields expand at trap-fire time because the outer single quotes defer evaluation.

**Known limitations** (documented in CHANGELOG + user docs):
- `set -E` does not propagate ERR into command-substitution subshells in every Bash build; this is a Bash quirk, not a toolkit issue.
- At the top level (outside any function) `${FUNCNAME[0]:-main}` substitutes the literal string `main`, since `FUNCNAME` is empty. Acceptable — it makes the line readable rather than blank.

## 5. Test plan

Three new test files plus targeted edits to one existing file. Each file mirrors the toolkit's existing `run_capture` + `assert_*` pattern.

### 5.1 `tests/test_version_compare.sh`

Cases:

1. `ci::version_gt 1.2.4 1.2.3` → exit 0
2. `ci::version_gt 1.2.3 1.2.4` → exit 1
3. `ci::version_gt 1.2.3 1.2.3` → exit 1
4. `ci::version_ge 1.2.3 1.2.3` → exit 0
5. `ci::version_ge 1.2.4 1.2.3` → exit 0
6. `ci::version_ge 1.2.3 1.2.4` → exit 1
7. `ci::version_gt v1.2.4 v1.2.3` → exit 0 (verifies `v` prefix is tolerated)
8. `ci::version_gt 1.0.0 1.0.0-rc1` → exit 0 (pre-release ordering)
9. `ci::version_gt 1.2.3` (missing arg) → exit 64, stderr contains `Usage`
10. `ci::version_gt "" 1.0.0` (empty arg) → exit 64
11. CLI `./ci-toolkit version gt 1.2.4 1.2.3` → exit 0
12. CLI `./ci-toolkit version` (no args) → exit 0 + stdout contains `ci-toolkit 0.1.6` (backward compat)
13. CLI `./ci-toolkit version gt 1.2.3` (missing arg) → exit 64

### 5.2 `tests/test_strip_prefix.sh`

1. `ci::strip_prefix v v1.2.3` → stdout `1.2.3`, exit 0
2. `ci::strip_prefix v 1.2.3` (no match) → stdout `1.2.3`, exit 0
3. `ci::strip_prefix "" v1.2.3` (empty prefix) → stdout `v1.2.3`, exit 0
4. `ci::strip_prefix v ""` (empty string) → stdout empty line, exit 0
5. `ci::strip_prefix '*' '*foo'` (glob-character prefix) → stdout `foo`, exit 0
6. `ci::strip_prefix v` (missing arg) → exit 64, stderr contains `Usage`
7. CLI `./ci-toolkit strip-prefix v v1.2.3` → stdout `1.2.3`

### 5.3 `tests/test_trap_err.sh`

These run inside `bash -c '...'` subshells to keep the test harness clean.

1. After `source ci-toolkit && ci::trap_err; false`, stderr contains `[error] command failed (exit=1) at`
2. After firing on `false`, stderr contains `false` (verifies BASH_COMMAND capture)
3. ERR inside a function (e.g., `f() { false; }; f`) → stderr contains `in f`
4. Without `set -e`, an `echo` after the failing command still runs (verifies trap does not call `exit`)
5. Two consecutive `ci::trap_err` calls — running again still produces a single error line per failure (no duplicate output, no error)
6. CLI `./ci-toolkit trap-err` → exit 64, stderr contains `only effective in source mode`

### 5.4 Existing test adjustments

- `tests/test_source_and_cli.sh` — if it asserts the literal `help` output, append the new command lines from §3.2. Otherwise no change.
- `tests/test_release_check.sh` — should pass unchanged. The new public functions all carry `# @description`; the gate will accept them. Run once to confirm.
- `scripts/smoke` — add minimal CLI exercises:
  - `./ci-toolkit strip-prefix v v0.1.6` → expect `0.1.6`
  - `./ci-toolkit version gt 0.1.6 0.1.5` → expect exit 0

## 6. Documentation & release shape

### 6.1 `CHANGELOG.md`

```
## 0.1.6 - 2026-05-14
### Added
- ci::version_gt / ci::version_ge: predicate helpers for semver-style comparison
  (sort -V backbone; accepts `vX.Y.Z`, `X.Y.Z`, `X.Y`, simple pre-release tags).
- ci::strip_prefix: literal prefix removal; returns original string unchanged
  when prefix is absent.
- ci::trap_err: installs a default ERR trap that prints exit code, file:line,
  function, and BASH_COMMAND. Enables `set -E`; leaves `set -e/-u/pipefail`
  untouched.
### Changed
- `ci-toolkit version` now also accepts `gt`/`ge` sub-commands. No-arg form
  preserved.
```

### 6.2 `ci-toolkit`

- Bump `CI_TOOLKIT_VERSION="0.1.6"` at the top of the file.
- Extend `ci::usage` with the new lines listed in §3.2.

### 6.3 User docs

`docs/user/en/index.md` and `docs/user/zh-TW/index.md` each get a short section under "Helpers" with one example per new helper. `scripts/check-user-docs.ts` (the docs-alignment gate added in v0.1.5's release-check) will verify that the new commands appear in both `ci::ls` and the user docs.

### 6.4 Release-check expectations

Running `./scripts/release-check` after implementation must pass:
- `./scripts/test` — three new test files + existing suite.
- `./scripts/lint` — ShellCheck clean on the new code.
- `./scripts/smoke` — new CLI invocations succeed.
- `scripts/check-user-docs.ts` — the three new public names appear in both surfaces.
- `# @description` contract — all four new public functions carry the comment.

## 7. Open risks & mitigations

| Risk | Mitigation |
| --- | --- |
| `sort -V` absent / different on some BusyBox builds | Out-of-scope — same risk applies to existing `ci::git_latest_tag`, which already uses `sort -V`. |
| Pre-release ordering edge cases | Spec explicitly delegates to `sort -V` semantics; not a SemVer-2.0 claim. |
| `set -E` interaction with subshells | Document the Bash quirk in `CHANGELOG.md` and user docs; out of scope to fix. |
| `ci::trap_err` overwriting a caller's custom trap | Documented behavior. Add a one-line note in user docs. |

## 8. Out-of-scope follow-ups

- Retrofit `examples/laravel-bluegreen-deploy/scripts/*.sh`, `examples/bun-deploy/deploy.sh`, and `examples/vendored-deploy-script/deploy-prod.sh` to use the new helpers — separate PR.
- `ci::strip_suffix`, `ci::version_eq` — wait for demand.
- Composable cleanup-on-EXIT helper — separate spec when needed.
