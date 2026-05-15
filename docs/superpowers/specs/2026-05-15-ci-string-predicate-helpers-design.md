# ci-toolkit v0.1.7 string predicate helpers — Design Spec

- **Spec date**: 2026-05-15
- **Status**: Draft for user review
- **Target version**: `0.1.7`
- **Scope**: Add four public string predicate helpers to `ci-toolkit`: `ci::eq`, `ci::ne`, `ci::in`, and `ci::not_in`, plus matching CLI commands.

## 1. Motivation

`ci-toolkit` already has predicate-style helpers such as `ci::is_true`, `ci::version_gt`, and `ci::version_ge`. These cover boolean environment variables and version-ish comparisons, but common CI scripts also need simple string predicates over values from many sources:

- environment variables (`DEPLOY_ENV`, `TARGET_ENV`, `RUN_DEPLOY`),
- git output (`branch`, `tag`, `commit`),
- toolkit helper output (`ci::git_latest_tag`, `ci::strip_prefix`),
- local script parsing results.

Bash has native `[[ "$a" == "$b" ]]`, but a small predicate family makes CI conditionals more discoverable, consistent with existing `ci::` status-code helpers, and available in CLI pipelines.

## 2. Non-goals

- Do not build a general-purpose Bash string library.
- Do not add substring, prefix, suffix, regex, trim, lowercase, or empty-string helpers in this release.
- Do not add environment-variable-specific predicates such as `ci::env_eq`; callers can pass `${VAR:-}` to the generic helpers.
- Do not print compared values on failure. Predicate helpers should not leak secrets by default.
- Do not introduce dependencies such as `jq`, `awk`, `sed`, or external test frameworks for these helpers.

## 3. API surface

### 3.1 Source-mode functions

```bash
ci::eq ACTUAL EXPECTED
ci::ne ACTUAL EXPECTED
ci::in VALUE CANDIDATE...
ci::not_in VALUE CANDIDATE...
```

All four functions follow existing toolkit conventions:

- Public name in the `ci::` namespace.
- `# @description` comment immediately above each public function.
- Return status codes only; never call `exit`.
- No stdout on normal predicate evaluation.
- Usage errors go to stderr through `ci::error` and return `64`.

### 3.2 CLI commands

```bash
ci-toolkit eq ACTUAL EXPECTED
ci-toolkit ne ACTUAL EXPECTED
ci-toolkit in VALUE CANDIDATE...
ci-toolkit not-in VALUE CANDIDATE...
```

CLI commands are thin wrappers over the source-mode helpers. They return the same status codes and do not print stdout on normal predicate success or failure.

## 4. Behavior contracts

### 4.1 `ci::eq`

| Situation | Behavior |
| --- | --- |
| `ACTUAL` exactly equals `EXPECTED` | exit `0` |
| Values differ | exit `1` |
| Fewer than 2 args | stderr: `Usage: ci::eq ACTUAL EXPECTED`; exit `64` |
| Empty string values | Valid values. `ci::eq "" ""` exits `0`; `ci::eq "" x` exits `1`. |
| stdout | Never written. |

### 4.2 `ci::ne`

| Situation | Behavior |
| --- | --- |
| Values differ | exit `0` |
| Values exactly equal | exit `1` |
| Fewer than 2 args | stderr: `Usage: ci::ne ACTUAL EXPECTED`; exit `64` |
| Empty string values | Valid values. `ci::ne "" x` exits `0`; `ci::ne "" ""` exits `1`. |
| stdout | Never written. |

### 4.3 `ci::in`

| Situation | Behavior |
| --- | --- |
| `VALUE` exactly equals any candidate | exit `0` |
| `VALUE` matches no candidate | exit `1` |
| Fewer than 2 args | stderr: `Usage: ci::in VALUE CANDIDATE...`; exit `64` |
| Empty string values | Valid. `ci::in "" "" x` exits `0`; `ci::in "" x y` exits `1`. |
| stdout | Never written. |

Candidates are compared literally with Bash string equality. No glob, regex, or case folding is applied.

### 4.4 `ci::not_in`

| Situation | Behavior |
| --- | --- |
| `VALUE` matches no candidate | exit `0` |
| `VALUE` exactly equals any candidate | exit `1` |
| Fewer than 2 args | stderr: `Usage: ci::not_in VALUE CANDIDATE...`; exit `64` |
| Empty string values | Valid. `ci::not_in "" x y` exits `0`; `ci::not_in "" "" x` exits `1`. |
| stdout | Never written. |

`ci::not_in` may delegate to `ci::in` internally, but must preserve usage-error status `64` rather than converting it into a boolean result.

## 5. Example usage

```bash
source ./ci-toolkit

branch="$(git branch --show-current)"
if ci::eq "$branch" main; then
  ci::info "running main-branch checks"
fi

target_env="${TARGET_ENV:-}"
if ci::in "$target_env" staging production preview; then
  ci::info "accepted deploy target: $target_env"
else
  ci::die "unsupported deploy target: $target_env" || exit 1
fi
```

CLI mode:

```bash
./ci-toolkit eq "$TARGET_ENV" production
./ci-toolkit in "$TARGET_ENV" staging production preview
```

## 6. Implementation shape

Add functions in the library section after `ci::is_true` and before path/version helpers. This keeps predicate helpers grouped near existing validation-style primitives while preserving the file's library → command → dispatch flow.

Expected implementation backbone:

```bash
ci::eq() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::eq ACTUAL EXPECTED"
    return 64
  fi
  [[ "$1" == "$2" ]]
}

ci::ne() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::ne ACTUAL EXPECTED"
    return 64
  fi
  [[ "$1" != "$2" ]]
}

ci::in() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::in VALUE CANDIDATE..."
    return 64
  fi
  local value="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ "$value" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

ci::not_in() {
  if [[ $# -lt 2 ]]; then
    ci::error "Usage: ci::not_in VALUE CANDIDATE..."
    return 64
  fi
  if ci::in "$@"; then
    return 1
  fi
  return 0
}
```

Command wrappers should return `64` through `ci::usage` or the helper's own usage message consistently with nearby command wrappers. Dispatch names use dash form only where Bash function names would be awkward: source `ci::not_in`, CLI `not-in`.

## 7. Test plan

Create `tests/test_string_predicates.sh` using the existing `run_capture` + `assert_*` harness.

### 7.1 Source mode cases

1. `ci::eq foo foo` exits `0`.
2. `ci::eq foo bar` exits `1`.
3. `ci::eq "" ""` exits `0`.
4. `ci::eq foo` exits `64` and stderr contains `Usage: ci::eq`.
5. `ci::ne foo bar` exits `0`.
6. `ci::ne foo foo` exits `1`.
7. `ci::ne "" foo` exits `0`.
8. `ci::ne foo` exits `64` and stderr contains `Usage: ci::ne`.
9. `ci::in staging dev staging prod` exits `0`.
10. `ci::in qa dev staging prod` exits `1`.
11. `ci::in "" dev "" prod` exits `0`.
12. `ci::in staging` exits `64` and stderr contains `Usage: ci::in`.
13. `ci::not_in qa dev staging prod` exits `0`.
14. `ci::not_in staging dev staging prod` exits `1`.
15. `ci::not_in "" dev staging` exits `0`.
16. `ci::not_in staging` exits `64` and stderr contains `Usage: ci::not_in`.
17. Normal predicate success/failure writes no stdout or stderr.

### 7.2 CLI mode cases

1. `ci-toolkit eq foo foo` exits `0`.
2. `ci-toolkit eq foo bar` exits `1`.
3. `ci-toolkit eq foo` exits `64`.
4. `ci-toolkit ne foo bar` exits `0`.
5. `ci-toolkit in staging dev staging prod` exits `0`.
6. `ci-toolkit in qa dev staging prod` exits `1`.
7. `ci-toolkit not-in qa dev staging prod` exits `0`.
8. `ci-toolkit not-in staging dev staging prod` exits `1`.
9. Normal predicate success/failure writes no stdout or stderr.

### 7.3 Existing gates

- Update `tests/test_source_and_cli.sh` only if help output assertions need new command lines.
- Update `scripts/smoke` with one low-cost predicate check, for example `ci-toolkit eq 0.1.7 0.1.7`.
- Run `./scripts/test`, `./scripts/lint`, `./scripts/smoke`, and `./scripts/release-check all`.

## 8. Documentation and release shape

Update these docs in the implementation phase:

- `ci-toolkit` usage text.
- `README.md` CLI reference and Source API reference.
- `docs/user/en/index.md` and `docs/user/zh-TW/index.md` if user docs track the new release before tagging.
- `CHANGELOG.md` latest entry for `v0.1.7`.

The `CI_TOOLKIT_VERSION` constant must be bumped to `0.1.7` in the same release change that updates `CHANGELOG.md`.

## 9. Compatibility and safety notes

- These helpers compare literal Bash strings only.
- They do not evaluate globs or regexes.
- They do not print actual compared values, which keeps them safe for values that may be sensitive.
- They intentionally do not read environment variables by name. Callers who want env checks can write `ci::eq "${DEPLOY_ENV:-}" production` or `ci::in "${TARGET_ENV:-}" staging production`.
- Source-mode functions return status codes and never terminate the caller shell.

## 10. Open decisions

None for this release. The chosen direction is generic string predicates first, with no env-specific helpers in v0.1.7.
