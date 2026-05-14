# Gungnir

<!-- doc-key: overview -->
Experimental, platform-neutral Bash helpers for CI scripts

Gungnir is an experimental, platform-neutral Bash toolkit designed to simplify CI/CD scripts. It provides a single-file artifact that functions as both a CLI tool and a sourceable Bash library, consolidating common patterns like structured logging, environment validation, and robust command retries.

---

<!-- doc-key: install-setup -->
## Install & setup

Install the `ci-toolkit` artifact directly in your CI environment using `curl` and `chmod`. We recommend pinning to a specific release tag for stability:

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.5/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

For local development or as an AI skill, you can use the provided `scripts/install-skill` to symlink the toolkit into your Claude Code skills directory.

### Comparison: Why use Gungnir?

| Task | Raw Bash | Gungnir `ci-toolkit` |
|------|----------|----------------------|
| **Logging** | `echo "[INFO] starting"` | `ci::info "starting"` (standardized stderr, colored) |
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
Gungnir's `ci::retry` is more powerful than a simple loop. It preserves the exit status of the final attempt and logs failures to stderr.

**Example: Flaky Network Call**
```bash
# Raw Bash (verbose and easy to get wrong)
n=0; until [ "$n" -ge 3 ]; do
  curl -fsS https://api.example.com && break
  n=$((n+1)); sleep 1
done

# Gungnir
ci::retry 3 curl -fsS https://api.example.com
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
