# ci-toolkit validation and shell argument helpers — Design Spec

- **Spec date**: 2026-05-15
- **Status**: Draft for user review
- **Target version**: Proposed `0.1.9`
- **Scope**: Add small platform-neutral validation helpers and a shell argument joining helper, motivated by a real deployment script (`/Users/carl/Dev/CMG/arcade-report/infra/ci/deploy.sh`) without absorbing deploy-specific behavior into the toolkit.

## 1. Motivation

The `arcade-report` deployment script is a useful stress case for `ci-toolkit`: it is a serious Bash CI script with local artifact checks, environment defaults, whitelist validation, SSH/rsync command construction, stage logging, remote rollback, and release retention. The script is careful and secure, but its top-level flow is harder to read because Bash guard boilerplate obscures the deployment contract.

`ci-toolkit` already provides foundational primitives such as `ci::require_env`, `ci::require_tool`, `ci::env_default`, `ci::is_true`, string predicates, and retry/path helpers. The next useful step is not a deployment framework. It is a small set of additional primitives that make real CI scripts read like declarative contracts while preserving the project's platform-neutral design.

This design adds validation helpers for files, directories, regular-expression allowlists, non-negative integers, and one data helper for safely rendering an argv array as a shell-escaped command string.

## 2. Goals

- Make CI Bash scripts more readable by replacing repeated inline guard blocks with named helper calls.
- Preserve the single-file artifact and source-mode-first architecture.
- Keep helpers platform-neutral: useful beyond SSH, rsync, systemd, or blue-green deployment.
- Preserve the no-secret-leakage convention: validation failures report field names and rule descriptions, not sensitive values.
- Provide CLI wrappers for quick checks and consistency with existing toolkit commands.
- Keep behavior testable with the existing Bash test harness.

## 3. Non-goals

- Do not add SSH-specific helpers such as `ci::ssh_opts`.
- Do not add rsync-specific helpers such as `ci::rsync_release`.
- Do not add systemd helpers such as `ci::systemd_restart` or service health abstractions.
- Do not add blue-green deployment orchestration.
- Do not parse configuration files or introduce a declarative config language.
- Do not introduce dependencies beyond Bash builtins and commands already required by the tested helper contract.
- Do not print rejected values in validation errors. Callers can log non-sensitive context explicitly when they choose.

## 4. API surface

### 4.1 Source-mode functions

```bash
ci::require_file NAME PATH [HINT]
ci::require_dir NAME PATH [HINT]
ci::require_match NAME VALUE REGEX [DESCRIPTION]
ci::require_uint NAME VALUE
ci::shell_join ARG...
```

All public functions must have `# @description` comments immediately above their definitions so `ci-toolkit ls` discovers them.

### 4.2 CLI commands

```bash
ci-toolkit file require NAME PATH [HINT]
ci-toolkit dir require NAME PATH [HINT]
ci-toolkit match require NAME VALUE REGEX [DESCRIPTION]
ci-toolkit uint require NAME VALUE
ci-toolkit shell join ARG...
```

CLI wrappers are thin adapters around source-mode helpers. They preserve status codes and stream behavior.

## 5. Behavior contracts

### 5.1 `ci::require_file NAME PATH [HINT]`

Checks that `PATH` exists and is a regular file.

| Situation | Behavior |
| --- | --- |
| `PATH` is a regular file | return `0`; no stdout or stderr |
| `PATH` is missing or not a regular file | stderr error names `NAME`; return `1` |
| `HINT` is provided on validation failure | append the hint to stderr without changing status |
| Fewer than 2 args | stderr usage; return `64` |

Suggested error shape:

```text
[error] required file missing: DEPLOY_SSH_KEY
[error] required file missing: LATEST_NAME_FILE (run build.sh first)
```

The helper deliberately accepts a logical `NAME` separate from `PATH`. This lets callers avoid printing secret-ish paths while still naming the failed contract.

### 5.2 `ci::require_dir NAME PATH [HINT]`

Checks that `PATH` exists and is a directory.

| Situation | Behavior |
| --- | --- |
| `PATH` is a directory | return `0`; no stdout or stderr |
| `PATH` is missing or not a directory | stderr error names `NAME`; return `1` |
| `HINT` is provided on validation failure | append the hint to stderr without changing status |
| Fewer than 2 args | stderr usage; return `64` |

Suggested error shape:

```text
[error] required directory missing: STAGING_DIR (run build.sh first)
```

### 5.3 `ci::require_match NAME VALUE REGEX [DESCRIPTION]`

Checks that `VALUE` matches the extended Bash regex `REGEX` using `[[ "$VALUE" =~ $REGEX ]]`.

| Situation | Behavior |
| --- | --- |
| `VALUE` matches `REGEX` | return `0`; no stdout or stderr |
| `VALUE` does not match | stderr error names `NAME` and a rule description; return `1` |
| `DESCRIPTION` is provided | use it in the error instead of printing raw `REGEX` |
| Fewer than 3 args | stderr usage; return `64` |

Suggested error shape:

```text
[error] invalid DEPLOY_SERVICE_NAME (expected [A-Za-z0-9._-]+)
```

If no description is provided, the helper may print the regex pattern because the pattern is a rule, not the sensitive value. It must not print `VALUE`.

This helper is useful for allowlists such as hostnames, service names, deploy targets, branch naming policies, and release names. It is not intended to replace arbitrary text processing.

### 5.4 `ci::require_uint NAME VALUE`

Checks that `VALUE` is a non-negative base-10 integer: `0` or digits without sign.

| Situation | Behavior |
| --- | --- |
| `VALUE` matches `^[0-9]+$` | return `0`; no stdout or stderr |
| `VALUE` is empty, negative, signed, decimal, or non-numeric | stderr error names `NAME`; return `1` |
| Fewer than 2 args | stderr usage; return `64` |

Suggested error shape:

```text
[error] invalid DEPLOY_RELEASE_RETAIN_COUNT (non-negative integer required)
```

`ci::require_uint` is intentionally narrower than a generic number parser. CI scripts often use unsigned counters for retries, retention, ports, and shard counts, and a strict helper keeps the contract obvious.

### 5.5 `ci::shell_join ARG...`

Prints a shell-escaped command string that represents the provided argv array.

| Situation | Behavior |
| --- | --- |
| One or more args | stdout contains a single shell command line; return `0` |
| Args contain spaces, quotes, glob characters, or empty strings | output remains safe to reparse by Bash |
| Zero args | stderr usage; return `64` |

Example:

```bash
SSH_CMD=$(ci::shell_join ssh -i "$DEPLOY_SSH_KEY" -p "$DEPLOY_PORT" -o BatchMode=yes)
rsync -e "$SSH_CMD" "$STAGING_DIR/" "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_RELEASE/"
```

Expected implementation should use Bash `printf '%q'` rather than inventing escaping rules. This makes `ci::shell_join` Bash-specific, which is acceptable because the whole toolkit targets Bash 4+.

Output should include a trailing newline like other stdout data helpers. Command substitution removes the trailing newline for common use.

## 6. Example: deploy script readability

The current deploy script contains careful but repetitive guards:

```bash
[ -d "$STAGING_DIR" ] || { echo "[deploy] staging dir not found ..." >&2; exit 1; }
[ -f "$DIST_DIR/.latest-name" ] || { echo "[deploy] dist/.latest-name missing ..." >&2; exit 1; }
[ -f "$DEPLOY_SSH_KEY" ] || { echo "[deploy] ssh key not found ..." >&2; exit 1; }
```

With these helpers, the top of the script can express its contract more directly:

```bash
source "$REPO_ROOT/ci-toolkit"

ci::require_env DEPLOY_HOST || exit $?
ci::env_default DEPLOY_USER arcade
ci::env_default DEPLOY_PORT 22
ci::env_default DEPLOY_DEST_ROOT /var/www/arcade-report
ci::env_default DEPLOY_SERVICE_NAME arcade-report
ci::env_default DEPLOY_RELEASE_RETAIN_COUNT 5
ci::env_default DEPLOY_DRY_RUN 0
ci::env_default DEPLOY_SKIP_RESTART 0

ci::require_tool ssh || exit $?
ci::require_tool rsync || exit $?
ci::require_dir STAGING_DIR "$STAGING_DIR" "run build.sh first" || exit $?
ci::require_file LATEST_NAME_FILE "$DIST_DIR/.latest-name" "run build.sh first" || exit $?
ci::require_file DEPLOY_SSH_KEY "$DEPLOY_SSH_KEY" || exit $?
ci::require_match DEPLOY_HOST "$DEPLOY_HOST" '^[A-Za-z0-9.-]+$' '[A-Za-z0-9.-]+' || exit $?
ci::require_match DEPLOY_USER "$DEPLOY_USER" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_match DEPLOY_SERVICE_NAME "$DEPLOY_SERVICE_NAME" '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+' || exit $?
ci::require_uint DEPLOY_RELEASE_RETAIN_COUNT "$DEPLOY_RELEASE_RETAIN_COUNT" || exit $?

RSYNC_SSH=$(ci::shell_join ssh "${SSH_OPTS[@]}")
```

This keeps deployment-specific decisions in the application repository while moving reusable validation and shell-joining patterns into `ci-toolkit`.

## 7. Implementation shape

Add library functions near the existing validation/predicate helpers, after `ci::require_tool` or near the string predicate block. The preferred grouping is:

1. logging/failure helpers,
2. environment/tool/path validation helpers,
3. predicates,
4. data helpers such as `strip_prefix` and `shell_join`,
5. git/slack/retry helpers.

Command wrappers should follow the existing `ci::cmd_*` style and return `64` on usage errors. Dispatch should add nested command handling for `file require`, `dir require`, `match require`, `uint require`, and `shell join` without introducing a general subcommand framework.

No release-time bundling or extra generated files are required.

## 8. Testing plan

Create focused behavior tests, preferably `tests/test_validation_helpers.sh` and `tests/test_shell_join.sh`, or one combined file if the implementation stays small.

### 8.1 Source-mode validation cases

- `ci::require_file NAME existing_file` returns `0`, stdout/stderr empty.
- `ci::require_file NAME missing_file` returns `1`, stderr contains `NAME`, stderr does not contain the path unless `NAME` equals the path by caller choice.
- `ci::require_file` with missing args returns `64` and usage.
- `ci::require_dir NAME existing_dir` returns `0`, stdout/stderr empty.
- `ci::require_dir NAME file_path` returns `1`, stderr contains `NAME`.
- `ci::require_dir` with missing args returns `64` and usage.
- `ci::require_match DEPLOY_USER arcade '^[A-Za-z0-9._-]+$'` returns `0`.
- `ci::require_match DEPLOY_USER 'bad user' '^[A-Za-z0-9._-]+$' '[A-Za-z0-9._-]+'` returns `1`, stderr contains `DEPLOY_USER` and the description, stderr does not contain `bad user`.
- `ci::require_match` with missing args returns `64` and usage.
- `ci::require_uint COUNT 0` and `ci::require_uint COUNT 5` return `0`.
- `ci::require_uint COUNT -1`, `+1`, `1.5`, empty string, and `abc` return `1` without printing the value.
- `ci::require_uint` with missing args returns `64` and usage.

### 8.2 Source-mode shell join cases

- `ci::shell_join ssh -p 22 host` returns a command string that contains the argv in order.
- Args with spaces round-trip through `bash -c 'eval "set -- $joined"; ...'` or an equivalent controlled test.
- Args with quotes, backslashes, glob characters, and empty string round-trip correctly.
- Zero args returns `64` and usage.

Round-trip tests must avoid executing arbitrary commands. They should only reparse into positional parameters in a controlled Bash process and compare values.

### 8.3 CLI cases

- `ci-toolkit file require NAME PATH` mirrors `ci::require_file` status and stderr behavior.
- `ci-toolkit dir require NAME PATH` mirrors `ci::require_dir`.
- `ci-toolkit match require NAME VALUE REGEX [DESCRIPTION]` mirrors `ci::require_match` and does not leak rejected values.
- `ci-toolkit uint require NAME VALUE` mirrors `ci::require_uint`.
- `ci-toolkit shell join ARG...` prints the same output as `ci::shell_join`.

### 8.4 Existing gates

- `./scripts/test`
- `./scripts/lint`
- `./scripts/smoke`
- `./scripts/release-check all`

Smoke should add one low-cost check for `shell join` or a validation helper once implemented.

## 9. Documentation updates

If implemented, update:

- `CHANGELOG.md` with a new release entry.
- `README.md` CLI and source API references.
- `docs/user/en/index.md` and `docs/user/zh-TW/index.md` plus generated HTML if that remains the docs workflow.
- `ci-toolkit help` usage output.
- `ci-toolkit ls` descriptions via `# @description` comments.

The documentation should emphasize that these are validation primitives, not deployment orchestration.

## 10. Risks and mitigations

### Risk: regex helper leaks sensitive values

Mitigation: error messages name `NAME` and the expected rule, never `VALUE`. Tests must assert rejected secret-like strings do not appear in stderr.

### Risk: `shell_join` encourages unsafe eval

Mitigation: document its intended use as an adapter for APIs that require a command string, such as `rsync -e`. Avoid examples that eval untrusted data. Tests may reparse the output in controlled conditions, but docs should not recommend general-purpose eval.

### Risk: helper surface grows too broad

Mitigation: keep this release to file/dir/regex/uint/shell-join primitives. Defer batch defaults, section logging, SSH helpers, and deploy abstractions.

### Risk: portability of `printf '%q'`

Mitigation: Bash 4+ is already the runtime boundary. The helper should document that the output is Bash-escaped, not POSIX-sh portable.

## 11. Open decisions for implementation planning

These decisions should be resolved when writing the implementation plan:

1. Whether to place `ci::shell_join` near `ci::strip_prefix` as a data helper or near validation helpers because it primarily supports command construction.
2. Whether CLI usage should use `file require` / `dir require` or flatter names such as `require-file` / `require-dir`. This spec recommends nested commands for readability and consistency with `env require` and `tool require`.
3. Whether `require_match` should print the raw regex when no description is supplied. This spec allows it, but implementation may choose a generic message to minimize log noise.
