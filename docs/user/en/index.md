# Gungnir

<!-- doc-key: overview -->
Experimental, platform-neutral Bash helpers for CI scripts

Gungnir is an experimental, platform-neutral Bash toolkit designed to simplify CI/CD scripts. It provides a single-file artifact that functions as both a CLI tool and a sourceable Bash library, consolidating common patterns like structured logging, environment validation, and robust command retries.

---

<!-- doc-key: install-setup -->
## Install & setup

Install the `ci-toolkit` artifact directly in your CI environment using `curl` and `chmod`. We recommend pinning to a specific release tag for stability:

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.7/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

For local development or as an AI skill, you can use the provided `scripts/install-skill` to symlink the toolkit into your Claude Code skills directory.

### Comparison: Why use Gungnir?

| Task | Raw Bash | Gungnir `ci-toolkit` |
|------|----------|----------------------|
| **Logging** | `echo "[INFO] starting"` | `ci::info "starting"` (structured stderr logging with level prefix) |
| **Env Check** | `if [[ -z "$TOKEN" ]]; then ...; exit 1; fi` | `ci::require_env TOKEN` (silent, secure, dry) |
| **Retry** | `for i in {1..3}; do cmd && break; sleep 1; done` | `ci::retry 3 cmd` (preserves exit code and output) |
| **Path Fix** | `$(cd "$(dirname "$0")"/.. && pwd)` | `ci::root` or `ci::find_up .git` |

<!-- doc-key: connections -->
## Connections / initialisation

Gungnir requires **Bash 4+**. It is designed to be platform-neutral, making no assumptions about specific CI vendors (like GitHub Actions or GitLab).

### Source Mode vs CLI Mode

- **Source Mode (Recommended for scripts)**: `source ./ci-toolkit` allows you to use `ci::` functions. These functions return status codes and do **not** call `exit`, giving you full control over your script's flow.
- **CLI Mode**: Run `./ci-toolkit` directly. Commands will `exit` with non-zero codes on failure, which is ideal for one-liners in `workflow.yml` or `Makefile`.

### Environment Variables
- **`CI_TOOLKIT_DEBUG=1`**: Enables verbose debug logging to stderr.
- **`ci::env_default VAR VALUE`**: Safely sets a fallback value if a variable is unset.

<!-- doc-key: discovery-read -->
## Discovery / read

Explore the toolkit's capabilities without making changes:

- **`ci::ls`**: List all available functions with descriptions. This is the fastest way to see what's available.
- **`ci::is_true VAR`**: A robust check for boolean-like variables. It returns success if the variable is `1` or `true`.

**Raw Bash comparison:**
```bash
# Raw Bash (brittle)
if [[ "${SKIP_TESTS:-}" == "true" ]]; then ...

# Gungnir (robust)
if ci::is_true SKIP_TESTS; then ...
```

<!-- doc-key: writes-mutations -->
## Writes / mutations

### Robust Retries
Gungnir's `ci::retry` is more powerful than a simple loop. It preserves the exit status of the final attempt and logs failures to stderr. Use `--delay SECONDS` to sleep between failed attempts — useful for upstreams that need a moment to recover (package registries, deploy targets).

**Example: Flaky Network Call**
```bash
# Raw Bash (verbose and easy to get wrong)
n=0; until [ "$n" -ge 3 ]; do
  curl -fsS https://api.example.com && break
  n=$((n+1)); sleep 1
done

# Gungnir
ci::retry 3 curl -fsS https://api.example.com

# With a 30s gap between attempts (good for registries / package managers)
ci::retry 2 --delay 30 -- composer install --no-dev --optimize-autoloader
```

### Secure Environment Checks
`ci::require_env` ensures a variable exists without accidentally printing its value (even if `set -x` is on in some environments).

<!-- doc-key: advanced-tools -->
## Advanced tools

### Path Discovery
Finding the repository root or a specific configuration file is a common pain point in CI.

- **`ci::find_up <marker>`**: Searches upwards from the current directory until it finds a file or directory named `<marker>`.
- **`ci::root`**: A shortcut for `ci::find_up .git`.

**Raw Bash comparison:**
```bash
# Raw Bash (fixed depth, often breaks if script moves)
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)

# Gungnir (dynamic, works from any sub-directory)
REPO_ROOT=$(ci::root)
```

### Version-style Comparison

For comparing semver-ish strings (tool versions, git tags) without writing brittle lexicographic `[[ "$a" > "$b" ]]` checks. Backed by `sort -V`.

```bash
# Source mode
if ci::version_ge "$BUN_VERSION" "1.1.0"; then
  ci::info "bun is new enough"
fi

# CLI mode
./ci-toolkit version gt 1.2.4 1.2.3   # exits 0
./ci-toolkit version ge 1.2.3 1.2.3   # exits 0
```

The helpers accept `vX.Y.Z`, `X.Y.Z`, `X.Y`, and simple pre-release tags. Build metadata (`1.0.0+build42`) sorts lexicographically by the tail — fine for CI, not a SemVer-2.0 promise.

### Prefix stripping

A small wrapper around Bash's `${var#prefix}` that also works from CLI pipelines and treats glob characters literally.

```bash
# Source mode
TAG=$(ci::git_latest_tag v)
VERSION=$(ci::strip_prefix v "$TAG")   # v1.2.3 -> 1.2.3

# CLI mode
./ci-toolkit strip-prefix v v1.2.3     # -> 1.2.3
```

If the prefix is absent, the original string is returned unchanged.

### String predicates

Lightweight status-code helpers for the most common CI conditional: "does this string equal that string?" / "is this value in this allowed list?" They compare literal Bash strings — no glob, regex, or case folding — and never print compared values, which keeps them safe for inputs that may be sensitive.

```bash
# Source mode
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

# CLI mode
./ci-toolkit eq "$TARGET_ENV" production
./ci-toolkit in  "$TARGET_ENV" staging production preview
./ci-toolkit not-in "$TARGET_ENV" dev experimental
```

| Helper | CLI | Behavior |
| --- | --- | --- |
| `ci::eq ACTUAL EXPECTED` | `eq` | Exit `0` iff `ACTUAL == EXPECTED`. |
| `ci::ne ACTUAL EXPECTED` | `ne` | Exit `0` iff `ACTUAL != EXPECTED`. |
| `ci::in VALUE CANDIDATE...` | `in` | Exit `0` iff `VALUE` matches any `CANDIDATE`. |
| `ci::not_in VALUE CANDIDATE...` | `not-in` | Exit `0` iff `VALUE` matches no `CANDIDATE`. |

Fewer than 2 arguments returns `64` (usage error) without printing values.

### Default ERR trap

`ci::trap_err` installs a one-line ERR trap so failures inside CI scripts report `exit code`, `file:line`, function name, and the failing `BASH_COMMAND`. Source mode only — the CLI form is informational.

```bash
source ./ci-toolkit
ci::trap_err

# Anywhere below, a failing command prints:
# [error] command failed (exit=1) at deploy.sh:42 in run_migrations: psql -c "..."
```

It enables `set -E` (errtrace) so the trap propagates into functions, but leaves `set -e/-u/pipefail` alone — your script keeps its existing flow control. A second `ci::trap_err` call replaces the first (standard Bash `trap` semantics).

<!-- doc-key: diagnostics-recovery -->
## Diagnostics / recovery

Gungnir helps you build "self-healing" or descriptive CI scripts.

- **`ci::die "Message"`**: Logs an error and returns `1`. Use it with `|| exit 1` in your main script logic.
- **`ci::require_tool`**: Prevents "command not found" errors halfway through a long-running job by checking dependencies upfront.

<!-- doc-key: ai-integration -->
## AI-agent integration

Gungnir is built for AI-first development. It ships with a **Claude Code skill** (`skills/ci-toolkit/`) that helps LLMs recognize when to use the toolkit.

**How it helps agents:**
1. **Less code**: Agents write fewer lines of boilerplate, reducing errors.
2. **Standardization**: Every script an agent writes follows the same logging and error-handling patterns.
3. **Safety**: Agents use `ci::require_env` instead of manually checking vars, preventing secret exposure.

<!-- doc-key: documentation-maintenance -->
## Documentation maintenance

Gungnir maintains documentation parity using a dual Markdown and HTML approach. Every topic is anchored by a `<!-- doc-key: id -->` comment.

Consistency across locales and formats is verified via:
```bash
bun run scripts/check-user-docs.ts
```
This ensures that the reference (`index.md`) and the visual surface (`index.html`) always present the same features in the same order.
