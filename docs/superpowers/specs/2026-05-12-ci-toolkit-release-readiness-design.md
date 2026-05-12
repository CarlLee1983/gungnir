# CI Toolkit Release Readiness Design

Date: 2026-05-12
Status: Approved design, v0.1.0 release-readiness stabilization

## Context

Gungnir's `ci-toolkit` MVP now exists as a single executable/sourceable Bash artifact with behavior tests, smoke checks, documentation, examples, and a Claude Code skill. The current question is not whether to keep expanding the toolbox, but whether the existing experimental `v0.1.0` shape is ready to be tagged or published.

The project contract says the public artifact is the root-level `ci-toolkit` file, distributed by `curl` plus `chmod +x`, with no build step. The first-version scope is intentionally narrow: platform-neutral CI foundation helpers for logging, environment validation, tool detection, retry, path discovery, help, and version output. Stable `build`, `test`, `lint`, `deploy`, release abstractions, CI-vendor integrations, plugin systems, and config frameworks are out of scope for this release.

## Goal

Produce a reproducible release-readiness pass for `ci-toolkit` v0.1.0 that answers one question: is the current MVP safe to tag as the experimental initial release?

The pass should leave the repository with:

1. Version metadata that matches the changelog contract.
2. Local quality gates that have been run and recorded.
3. A copy-smoke check proving the artifact still works after distribution as a standalone file.
4. A boundary check proving the first release has not drifted into CI-vendor or task-command abstractions.
5. Clear release notes about what was verified and what remains unverified.

## Non-goals

- Do not add new `ci::` helpers.
- Do not add new public CLI commands except verification-only scripts if needed.
- Do not introduce `build`, `deploy`, `release`, GitHub Actions, GitLab CI, CircleCI, or other platform-specific behavior into `ci-toolkit`.
- Do not publish a GitHub Release, push tags, or perform external network-visible release actions as part of this stabilization spec.
- Do not redesign the skill, examples, test harness, or toolkit architecture.
- Do not require new runtime dependencies for consumers of `ci-toolkit`.

## Release-readiness definition

`ci-toolkit` is release-ready when all of the following are true:

1. `CI_TOOLKIT_VERSION` in `ci-toolkit` is intentionally aligned with the latest `CHANGELOG.md` entry.
   - Accepted alignment for v0.1.0: the CLI may print `0.1.0` or another explicitly documented form, but the repo must not leave an unexplained mismatch between `CI_TOOLKIT_VERSION` and `CHANGELOG.md`.
2. `./scripts/test` passes.
3. `./scripts/lint` has a meaningful release result.
   - If ShellCheck is installed, ShellCheck must pass.
   - If ShellCheck is unavailable locally, the release note must record that gap and name the command that still needs to run in an environment with ShellCheck.
4. `./scripts/smoke` passes.
5. A standalone copy-smoke passes from a temporary directory:
   - copy only `ci-toolkit` into a temp directory;
   - `chmod +x` it;
   - run `./ci-toolkit help`;
   - run `./ci-toolkit version`;
   - source it from Bash and call `ci::info`.
6. A boundary check confirms the public artifact does not depend on CI-vendor environment variables or introduce task-command abstractions.
   - Vendor markers to reject in `ci-toolkit`: `GITHUB_`, `GITLAB_`, `CIRCLE_`, `BUILDKITE_`, `BITBUCKET_`.
   - Public command names to reject in `ci::usage` / dispatch for v0.1.0: `build`, `deploy`, `release`, `test`, `lint`.
7. Release-readiness documentation records verification evidence and known gaps.

## Architecture

This stabilization should be implemented as a small verification layer around the existing artifact, not as a new packaging system.

Recommended shape:

- Keep `ci-toolkit` as the only runtime artifact.
- Keep existing behavior tests under `tests/test_*.sh` unchanged unless a real contract mismatch is discovered.
- Add or update a release verification script only if it removes manual ambiguity. A likely script name is `scripts/release-check`.
- Add release-readiness documentation under `docs/superpowers/` or as a concise root-level release note if a reusable note is more useful to future maintainers.

The stabilization work should prefer explicit shell commands over new frameworks. Bash is already the project runtime and no new dependency is justified for a release gate this small.

## Components

### 1. Version contract check

The implementation should inspect `ci-toolkit` and `CHANGELOG.md` and make the version relationship explicit.

The current project guidance says the `CI_TOOLKIT_VERSION` constant must match the latest changelog entry. The release-readiness pass should either:

- normalize `CI_TOOLKIT_VERSION` to `0.1.0` while keeping the changelog header as `v0.1.0`; or
- document why `0.1.0-experimental` is the intentional CLI display for changelog entry `v0.1.0`.

The preferred option is to normalize the constant to `0.1.0` and let the README / changelog carry the experimental status. This keeps machine-readable version output simple while preserving the experimental warning in documentation.

### 2. Quality gates

The release pass should run the existing gates in sequence:

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

The pass must capture whether `scripts/lint` actually ran ShellCheck or skipped because ShellCheck is unavailable. A skip is acceptable for local development evidence, but not sufficient for a final release claim unless the release note calls it out as unverified.

### 3. Standalone copy-smoke

A release consumer downloads a single file, not the repository. The release pass should prove this mode directly by copying `ci-toolkit` into a temporary directory and running it there without relying on sibling files.

Required checks:

```bash
tmpdir="$(mktemp -d)"
cp ci-toolkit "$tmpdir/ci-toolkit"
chmod +x "$tmpdir/ci-toolkit"
(
  cd "$tmpdir"
  ./ci-toolkit help >/dev/null
  ./ci-toolkit version | grep -q 'ci-toolkit'
  bash -c "source './ci-toolkit' && ci::info 'ok'" >/dev/null
)
rm -rf "$tmpdir"
```

### 4. Boundary check

The first release must remain platform-neutral and must not grow workflow abstractions. The release pass should make this explicit with grep-style checks against `ci-toolkit`.

The check should fail if the artifact contains CI-vendor markers:

```bash
grep -nE 'GITHUB_|GITLAB_|CIRCLE_|BUILDKITE_|BITBUCKET_' ci-toolkit
```

The check should also fail if public command dispatch or usage exposes task abstractions that are explicitly out of scope for v0.1.0. The check should inspect command-facing lines rather than every README/example mention, because examples legitimately contain script names such as `build` and `deploy`.

### 5. Release-readiness note

The stabilization pass should record a concise note with:

- release candidate version;
- exact commands run;
- pass/fail/skip result for each gate;
- whether ShellCheck actually ran;
- copy-smoke result;
- boundary-check result;
- known gaps, including no published release artifact and no external GitHub release action.

This note can live at `docs/superpowers/release-readiness/2026-05-12-v0.1.0.md` or another similarly explicit path chosen during planning.

## Data flow

```text
Maintainer
  -> runs release-readiness task/script
  -> verifies local tests, lint, smoke
  -> copies ci-toolkit into a temp distribution shape
  -> verifies standalone CLI and source mode
  -> checks platform-neutral boundaries
  -> records evidence and gaps
  -> decides whether to tag/publish outside this spec
```

## Error handling

- If behavior tests fail, stop and fix the failing behavior before any release-ready claim.
- If smoke checks fail, stop and fix the artifact or smoke contract before any release-ready claim.
- If ShellCheck is unavailable, do not pretend lint passed; record `scripts/lint` as a local skip and treat ShellCheck as a release gap until run elsewhere.
- If copy-smoke fails, treat it as a release blocker because it means the public artifact is not self-contained.
- If boundary checks find CI-vendor markers or public task abstractions, treat it as a release blocker unless the design contract is intentionally revised first.
- If version metadata and changelog disagree, treat it as a release blocker until normalized or explicitly documented.

## Testing strategy

This spec is mostly a verification and documentation pass, so the most important tests are command-level checks rather than new unit tests.

Required verification commands:

```bash
./scripts/test
./scripts/lint
./scripts/smoke
```

Required additional checks:

```bash
# Standalone distribution smoke
# See the copy-smoke command block above.

# Boundary check
grep -nE 'GITHUB_|GITLAB_|CIRCLE_|BUILDKITE_|BITBUCKET_' ci-toolkit && exit 1 || true
```

If a `scripts/release-check` script is added, it should run all reproducible checks except external publication. It should return non-zero for release blockers and print a clear message for ShellCheck skip status.

## Acceptance criteria

- The repository has a written release-readiness record for v0.1.0.
- Version metadata and changelog relationship is resolved.
- Existing behavior tests pass.
- Existing smoke checks pass.
- Standalone copy-smoke passes.
- Boundary check passes.
- ShellCheck status is either passed or explicitly recorded as a release gap.
- No new public toolkit features are introduced by this stabilization work.
- No external release action is performed by this work.

## Future work

After this release-readiness pass, future specs may cover:

- publishing the `v0.1.0` GitHub Release artifact;
- using `ci-toolkit` in a real downstream repository;
- adding v0.2 helpers based on repeated downstream usage patterns;
- generating a release checklist from `scripts/release-check` output.
