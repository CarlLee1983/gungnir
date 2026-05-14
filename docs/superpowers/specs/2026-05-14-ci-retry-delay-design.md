# `ci::retry --delay SECONDS` Design

**Status:** Design — approved 2026-05-14; awaiting implementation plan.
**Originates from:** [`2026-05-14-laravel-bluegreen-retrofit-design.md`](./2026-05-14-laravel-bluegreen-retrofit-design.md) §5.1.
**Implements:** the §5.1 proposal annotated in `examples/laravel-bluegreen-deploy/deploy-prod.sh` (`# proposed: ci::retry --delay SECONDS`).

---

## 1. Problem

`ci::retry` currently sleeps zero seconds between attempts. For most CI failure modes (network blip, registry contention, transient HTTP 503) the second attempt has to wait *something* — otherwise we just hammer the same upstream three times within a millisecond and exit with the same failure.

The laravel-bluegreen retrofit hit this on `composer install`: the original StationHub script used the idiom

```bash
if ! composer install --no-dev --optimize-autoloader; then
    sleep 30
    composer install --no-dev --optimize-autoloader
fi
```

which is `ci::retry 2 --delay 30 -- composer install` in disguise. Two other examples (`bun-deploy/`, `vendored-deploy-script/`) and the toolkit's own `ci::slack_webhook` would benefit from a small inter-attempt delay too.

## 2. Goals

- Add a single `--delay SECONDS` flag to `ci::retry` (source mode) and `ci-toolkit retry` (CLI mode).
- Preserve every existing caller's behavior. No call-site migration is required.
- Match the toolkit's idioms: return status codes, never `exit`; report invalid input as `64`; warn (not error) on failed attempts.

## 3. Non-goals

- No `--backoff exp` / `--max-delay` / `--jitter` / `--timeout`. Spec §5.1 risk note explicitly defers these to avoid flag-interaction sprawl; if backoff becomes necessary later, it gets its own spec.
- No change to the per-attempt warning line format. (Existing tests grep `Attempt 1/3 failed` literally; preserving that string keeps the test suite green and downstream users' log scrapers stable.)
- No change to how stdout/stderr are forwarded by `ci::retry`.

## 4. Decisions (locked during brainstorm)

| # | Decision | Rationale |
|---|---|---|
| D1 | `--` separator is **optional** in source mode. | All 11 existing source-mode call sites (`ci-toolkit:213`, two examples, tests, README narrative) pass the command positionally without `--`. Requiring `--` would force a coordinated multi-file migration that buys nothing functional. |
| D2 | `--delay` accepts a **non-negative integer only** (regex `^[0-9]+$`). | Matches the validation style of other `ci::` helpers, avoids locale-sensitive float parsing, and matches what `sleep` reliably accepts on both BSD (macOS) and GNU (Linux). Sub-second granularity isn't useful for CI retry. |
| D3 | **Strict `--*` parsing**: after `ATTEMPTS` is consumed, the parser eats every token that starts with `--`. Unknown `--*` returns `64`. A bare `--` consumes itself and stops. The first non-`--*` token starts the command. | Catches typos (`--delya`) loudly. Matches CLI mode semantics, where the dispatcher already enforces this. A command whose first token legitimately starts with `--` (e.g. `--version`) must be preceded by the explicit `--` separator — this is the documented escape hatch. |

## 5. API

### Signature (both modes)

```
ci::retry           ATTEMPTS [--delay SECONDS] [--] COMMAND ARGS...
ci-toolkit retry  [ATTEMPTS] [--delay SECONDS]  --  COMMAND ARGS...
```

- `ATTEMPTS` — positive integer.
  - Source mode: required.
  - CLI mode: optional, defaults to `3` (current behavior preserved).
- `--delay SECONDS` — non-negative integer; default `0`. `0` is byte-equivalent to omitting the flag.
- `--` — optional in source mode; **required** in CLI mode (current behavior preserved).
- `COMMAND ARGS...` — everything after the parser finishes consuming flags.

### Parse rule

After `ATTEMPTS` is consumed, loop on `"$1"`:

```
loop:
  case "$1" in
    --delay)
      consume "$1" "$2"
      validate SECONDS matches ^[0-9]+$
      continue loop
    --)
      consume "$1"
      break out of flag loop
    --*)
      ci::error "ci::retry: unknown option: $1"
      return 64
    *)
      break out of flag loop (start of command)
  esac
exec command: "$@"
```

### Examples

| Form | Parses as |
|---|---|
| `ci::retry 3 git fetch origin` | 3 attempts, delay 0, cmd = `git fetch origin` |
| `ci::retry 3 -- git fetch origin` | 3 attempts, delay 0, cmd = `git fetch origin` |
| `ci::retry 2 --delay 30 -- composer install` | 2 attempts, delay 30s, cmd = `composer install` |
| `ci::retry 2 --delay 30 composer install` | 2 attempts, delay 30s, cmd = `composer install` |
| `ci::retry 3 --delay 0 -- cmd` | 3 attempts, no delay (explicit-default; legal) |
| `ci::retry 3 --foo bar` | returns `64`, "unknown option: --foo" |
| `ci::retry 3 --version` | returns `64`. **Workaround:** `ci::retry 3 -- --version` |

## 6. Behavior

```
for attempt in 1..ATTEMPTS:
  set +e; "$@"; status=$?; set -e
  if status == 0:
    return 0
  ci::warn "Attempt $attempt/$ATTEMPTS failed with status $status: $*"
  if attempt < ATTEMPTS and delay > 0:
    sleep "$delay"
return last status
```

**Invariants:**

- Sleep is only **between** attempts — never before the first, never after the last.
- Sleep is skipped when `delay == 0`, so `--delay 0` and the omit-`--delay` path emit identical syscalls.
- `ATTEMPTS=1` with `--delay 5` is legal — there's no "between", so no sleep ever fires.
- stdout / stderr / exit status of the command pass through unchanged.
- Per-attempt warning line format is **unchanged**: `Attempt N/M failed with status X: cmd args...`. Existing tests grep this literally.

## 7. Error codes

All errors return (never `exit`).

| Trigger | Code | stderr message |
|---|---|---|
| missing `ATTEMPTS` | `64` | `Usage: ci::retry ATTEMPTS [--delay SECONDS] [--] COMMAND...` |
| `ATTEMPTS` not a positive int | `64` | (same usage) |
| `--delay` without value (end of args) | `64` | `ci::retry: --delay requires a value` |
| `--delay foo` (non-numeric) | `64` | `ci::retry: --delay value must be a non-negative integer, got: foo` |
| `--delay -1` | `64` | (same — `-1` fails `^[0-9]+$`) |
| unknown flag | `64` | `ci::retry: unknown option: --xxx` |
| no command after flags | `64` | (usage) |
| command failed all attempts | command's last exit status | (no extra wrapper line — covered by per-attempt warns) |

## 8. CLI mode (`ci::cmd_retry`)

Update `ci::cmd_retry` (`ci-toolkit:350-375`) to accept `--delay SECONDS` between `ATTEMPTS` and `--`:

```
ci-toolkit retry [ATTEMPTS] [--delay SECONDS] -- COMMAND ARGS...
```

- Default `ATTEMPTS=3` is preserved.
- `--` is still **required** in CLI mode (current behavior; protects against argv being interpreted as flags).
- `ci::cmd_retry` parses `ATTEMPTS`, then forwards `--delay SECONDS` and the rest to `ci::retry`. Validation errors print the usage and return `64`.
- `ci::usage` is updated so `ci-toolkit help` shows the new signature.

## 9. Surface changes

| File | Change |
|---|---|
| `ci-toolkit` (`ci::retry`, lines 86–115) | Add flag-parse loop, sleep between attempts, validate `--delay`. |
| `ci-toolkit` (`ci::cmd_retry`, lines ~350–375) | Accept `--delay SECONDS`; forward to `ci::retry`. |
| `ci-toolkit` (`CI_TOOLKIT_VERSION`, line ~3) | Bump `0.1.4` → `0.1.5`. |
| `ci-toolkit` (`ci::usage`) | Show new retry signature. |
| `CHANGELOG.md` | Add `## v0.1.5 - Add retry delay`; note back-compat preserved. |
| `README.md` (signature table) | Update signature; add `--delay` example. |
| `docs/user/zh-TW/index.md`, `docs/user/en/index.md` | Add `--delay` example with brief use-case. |
| `tests/test_retry_and_paths.sh` | Existing tests stay unchanged (back-compat regression). |
| `tests/test_retry_delay.sh` (new file) | New test coverage — see §10. |
| `tests/test_source_and_cli.sh` (line 32) | Bump version literal `0.1.4` → `0.1.5`. Fixing the fragility (read `CI_TOOLKIT_VERSION` dynamically) is out of scope — track separately. |
| `examples/laravel-bluegreen-deploy/deploy-prod.sh` (`run_composer_install`, lines ~213–224) | Replace inline sleep-retry with `ci::retry 2 --delay 30 -- composer install ...`; delete the `# proposed:` annotation. |
| `examples/laravel-bluegreen-deploy/README.md` | Mark §5.1 as **landed** in the "proposed APIs" section; update substitution-table row L132-136. |

## 10. Tests

New file `tests/test_retry_delay.sh`. Twelve assertions plus three back-compat regression assertions:

| # | Scenario | Mode | Expectation |
|---|---|---|---|
| 1 | `ci::retry 2 --delay 0 false` | source | exit ≠ 0; same warnings as today |
| 2 | `ci::retry 2 --delay 1 -- bash -c '... succeed on 2nd try ...'` | source | exit 0; wall-clock ≥ 1s (use `SECONDS` builtin) |
| 3 | `ci::retry 3 --delay 1 false` (all fail; 2 sleeps between 3 attempts) | source | exit ≠ 0; wall-clock ≥ 2s |
| 4 | `ci::retry 1 --delay 5 false` (one attempt, no between, no sleep) | source | exit ≠ 0; wall-clock < 1s |
| 5 | `ci::retry 3 --delay -1 -- true` | source | exit 64; stderr names `--delay` |
| 6 | `ci::retry 3 --delay abc -- true` | source | exit 64 |
| 7 | `ci::retry 3 --delay -- true` (missing value) | source | exit 64 |
| 8 | `ci::retry 3 --bogus -- true` | source | exit 64 |
| 9 | `ci::retry 3 -- false` (explicit `--`, no flags) | source | exit ≠ 0; equivalent to `ci::retry 3 false` |
| 10 | `ci-toolkit retry 2 --delay 1 -- bash -c '...'` | CLI | exit 0; wall-clock ≥ 1s |
| 11 | `ci-toolkit retry --delay 1 -- false` (no ATTEMPTS, default 3) | CLI | exit ≠ 0; wall-clock ≥ 2s |
| 12 | `ci-toolkit retry 2 --delay foo -- true` | CLI | exit 64 |
| 13 | `ci::retry 3 cmd` (no `--`, no flags) — regression | source | unchanged from current |
| 14 | `ci-toolkit retry 2 -- cmd` — regression | CLI | unchanged |
| 15 | `ci-toolkit retry -- cmd` (default ATTEMPTS) — regression | CLI | unchanged |

Wall-clock assertions use `bash`'s `SECONDS` builtin (`start=$SECONDS; …; (( SECONDS - start >= N ))`). Tests that assert "did NOT sleep" use a small allowance (e.g. `<1s`) to tolerate startup overhead.

## 11. Out-of-scope follow-ups (track separately)

1. **Read `CI_TOOLKIT_VERSION` dynamically in `test_source_and_cli.sh`** — would prevent the same "forgot to bump assertion" bug that PR #2 just fixed. One-line refactor, but adds a new pattern; spin out its own spec/plan.
2. **Migrate the `bun-deploy` / `vendored-deploy-script` examples to `--delay`** where appropriate — out of scope; those examples retry network ops that already tolerate the current zero-delay behavior.
3. **Internal `ci::slack_webhook` retry** (`ci-toolkit:213`) — same. The 5s/15s curl timeouts already gate retry pacing; adding `--delay` here is an optimization, not a fix.

## 12. Acceptance criteria

A PR is acceptable when:

- All 12 new tests + 3 regression tests pass on macOS Bash 4+ (Homebrew) and Linux Bash 4+.
- `./scripts/lint` passes (ShellCheck clean).
- `./scripts/test` passes the entire suite.
- `./scripts/release-check all` exits 0.
- Existing source-mode and CLI-mode call sites compile and behave identically (no warnings, no exit-status drift).
- `CHANGELOG.md` v0.1.5 entry, `CI_TOOLKIT_VERSION = 0.1.5`, and `tests/test_source_and_cli.sh` literal are mutually consistent.
- `examples/laravel-bluegreen-deploy/` is updated: `run_composer_install` uses `ci::retry 2 --delay 30 -- composer ...`, README marks §5.1 as landed.
