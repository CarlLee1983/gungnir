# Gungnir CI Toolkit

Experimental platform-neutral Bash helpers for CI scripts.

## Status

This project is experimental. CLI commands and `ci::` source APIs may change before stabilization. Pin a release tag in CI instead of tracking `main`.

## Install in CI

```bash
curl -fsSL https://github.com/CMG/Gungnir/releases/download/v0.1.0/ci-toolkit -o ci-toolkit
chmod +x ci-toolkit
./ci-toolkit version
```

## CLI usage

```bash
./ci-toolkit help
./ci-toolkit version
./ci-toolkit log info "starting checks"
./ci-toolkit env require DEPLOY_TOKEN
./ci-toolkit tool require git
./ci-toolkit retry -- make test
```

## Source API usage

```bash
source ./ci-toolkit

ci::info "starting checks"
ci::require_env DEPLOY_TOKEN
ci::require_tool git
ci::retry 3 make test
```

## Runtime boundary

- Bash 4+ is required.
- Core behavior is platform-neutral and does not depend on a specific CI vendor.
- Optional external tools must be checked with `ci::require_tool` before use.
- Secret values must not be printed by validation helpers.

## Development checks

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

`scripts/lint` uses ShellCheck when installed and exits zero with a clear skip message when ShellCheck is unavailable.
