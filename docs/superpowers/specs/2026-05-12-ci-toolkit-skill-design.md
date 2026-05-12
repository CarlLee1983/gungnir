# ci-toolkit Skill Design

Date: 2026-05-12
Status: Approved design, MVP

## Context

Gungnir ships `ci-toolkit` (a single Bash artifact that doubles as a CLI and a sourceable `ci::` function library) plus two worked examples under `examples/`. Today, when an AI coding agent helps a developer in some other project, the agent has no signal that `ci-toolkit` exists, nor any reusable playbook for adopting it. The user wants a Claude Code skill that gives agents that signal and playbook, shipped from inside the Gungnir repo so the skill and the tool evolve together.

## Goal

Provide a skill — a single SKILL.md file plus an install script — that:

1. Activates when an AI agent is helping write, refactor, review, or troubleshoot Bash CI / build / deploy scripts in any project.
2. Teaches the agent when to reach for `ci-toolkit`, how to integrate it (vendored vs URL), and how to apply it both to new scripts and to refactors of existing scripts.
3. Stays in sync with the live `README.md` and `examples/` in the Gungnir repo by referencing them through relative paths, so the README remains the single source of truth for the function library.

## Non-goals

- Do not duplicate the `ci::` function table inside the skill. Agents read it from `README.md` at use time.
- Do not publish to a plugin registry or claude-plugins store. Distribution is `git clone` + `scripts/install-skill`.
- Do not split into separate skills for "write new" vs "refactor". One skill description covers both.
- Do not auto-test that Claude actually routes to the skill — that requires live LLM runs and is out of scope for MVP.
- Do not bundle a cheatsheet, decision tree, test scaffolds, or refactor-prompt templates. Those belong to a thicker future revision, not the MVP.
- Do not overwrite an existing symlink or file at the install target. Conflict means abort.

## Architecture

The skill ships from inside the Gungnir repo and is installed via symlink:

```
Gungnir/
  skills/
    ci-toolkit/
      SKILL.md
  scripts/
    install-skill           # ln -s symlink installer
```

After installation:

```
~/.claude/skills/ci-toolkit -> /absolute/path/to/Gungnir/skills/ci-toolkit
```

Key design choice: **symlink, not copy**. The body of `SKILL.md` references `../../README.md`, `../../examples/bun-deploy/`, `../../examples/vendored-deploy-script/`, and `../../ci-toolkit` via paths relative to the skill folder. Because the symlink target is the live folder inside the Gungnir repo, those relative paths resolve back into the live repo. The README and examples stay canonical; `git pull` in the Gungnir repo upgrades the skill in place.

This mirrors `ci-toolkit`'s own "one file, two modes" design philosophy from `AGENTS.md`: the SKILL.md is the single artifact, with one description (frontmatter) that handles two scenarios (new vs refactor) in one body.

## Components

### 1. `skills/ci-toolkit/SKILL.md`

YAML frontmatter:

- `name: ci-toolkit`
- `description`: a single English sentence that includes the keywords `CI`, `build`, `deploy`, and `refactor` so Claude's router picks it up in either scenario. Length is intentionally long enough to cover both triggers in one line.

Body sections, in order:

1. **When this skill applies** — 3–5 bullets describing trigger conditions (writing a new build/deploy/release script; refactoring an existing `.sh` with manual log prefixes, env validation, retries, or repo-root discovery; CI-script review questions).
2. **Decision: vendor or URL** — short table giving criteria for each mode, with one-line examples of pinning a version.
3. **Two scenarios** — two subsections (`Writing a new script` and `Refactoring an existing script`), each a numbered 4-step list pointing at the right README section and the right example folder.
4. **Invariants** — restatement of `AGENTS.md` "Conventions to preserve" rules: platform-neutral, no secret leak in error messages, stderr for logs / stdout for data, library functions return status instead of `exit`.
5. **Reference paths** — explicit list of relative paths to `README.md`, the two example folders, and the `ci-toolkit` source file.

Body is intentionally short. Function tables, recipe lists, and worked diffs live in `README.md` and `examples/`, not in `SKILL.md`.

### 2. `scripts/install-skill`

Single Bash script, sibling to existing `scripts/test`, `scripts/lint`, `scripts/smoke`. Same shape (`#!/usr/bin/env bash`, `set -euo pipefail`).

Behavior:

- Compute the Gungnir repo root by walking up from `${BASH_SOURCE[0]}`. Works regardless of the caller's `cwd`.
- Resolve install destination from `CLAUDE_SKILLS_DIR` if set, else `$HOME/.claude/skills`.
- Ensure `$src` (`skills/ci-toolkit/`) exists; create `$dst_dir` if missing.
- Conflict handling at destination `ci-toolkit`:
  - If it is a symlink already pointing at `$src` → print `already linked`, exit 0 (idempotent).
  - If it is a symlink pointing elsewhere → print the existing target, exit non-zero, do not overwrite.
  - If it is any non-symlink path → exit non-zero, do not overwrite.
  - Otherwise → `ln -s "$src" "$dst"`, print confirmation, exit 0.
- No uninstall command. `rm ~/.claude/skills/ci-toolkit` is sufficient.

The script never deletes or moves anything the user did not explicitly install.

### 3. Test additions

Two new test files, both using `tests/assert.sh` and discovered by `scripts/test` because they match `tests/test_*.sh`:

- **`tests/test_install_skill.sh`** — exercises `scripts/install-skill` behavior (cases 1–4 below).
- **`tests/test_skill_metadata.sh`** — static checks against `skills/ci-toolkit/SKILL.md` (cases 5–6 below): every `../../`-prefixed path in `SKILL.md` resolves to an existing file, and the `description:` line contains at least one of `CI`, `deploy`, `build`, `refactor`.

`scripts/test` keeps its existing thin loop unchanged.

## Data flow

When a user is working in some downstream project and asks an agent to write or refactor a CI / build / deploy script:

1. Claude's skill router scans `~/.claude/skills/*/SKILL.md` frontmatter.
2. The `ci-toolkit` skill's `description` matches because it lists the relevant keywords.
3. Claude loads `SKILL.md` from the symlink target inside the Gungnir repo.
4. The body instructs the agent to:
   - Read `../../README.md` for the function table.
   - Read `../../examples/bun-deploy/` (new-script mode) or `../../examples/vendored-deploy-script/` (refactor mode) for the canonical pattern.
   - Apply the appropriate integration mode in the user's project.
5. The agent produces or edits scripts inside the user's project (not inside Gungnir).

The Gungnir repo itself is never modified during this flow.

## Error handling

- **`install-skill` conflicts** — abort with a specific message, never overwrite. The user resolves manually (rename their existing entry, or set `CLAUDE_SKILLS_DIR` elsewhere).
- **Missing source folder** — abort with `missing <path>` so the user knows the symlink would point at nothing.
- **Stale symlink after Gungnir repo is moved/deleted** — out of scope; the symlink will dangle and Claude will silently skip the skill. The user runs `install-skill` again from the new location.
- **README / example renames inside Gungnir** — caught by `tests/test_skill_metadata.sh` (case 5). Renaming a referenced file without updating `SKILL.md` fails `scripts/test`.

## Testing

Cases 1–4 live in `tests/test_install_skill.sh`, all using the existing `assert.sh` harness and a per-test temp dir as `CLAUDE_SKILLS_DIR`:

1. **Happy path** — fresh `CLAUDE_SKILLS_DIR`, run installer once. Assert exit 0; assert `$CLAUDE_SKILLS_DIR/ci-toolkit` is a symlink whose target equals the absolute path of `skills/ci-toolkit` inside the repo.
2. **Idempotent** — run installer twice in a row against the same `CLAUDE_SKILLS_DIR`. Assert exit 0 on the second run; assert stdout contains `already linked`.
3. **Refuses to overwrite a regular file** — pre-create `$CLAUDE_SKILLS_DIR/ci-toolkit` as a plain file. Run installer; assert non-zero exit; assert the file is unchanged; assert stderr / stdout mentions `aborting`.
4. **Refuses to overwrite a different symlink** — pre-create the destination as a symlink to a temp dir. Run installer; assert non-zero exit; assert stdout / stderr contains `different symlink exists`; assert the original symlink is unchanged.

Cases 5–6 live in `tests/test_skill_metadata.sh`:

5. **Relative paths resolve** — every `../../`-prefixed path in `SKILL.md` exists on disk.
6. **Description has trigger keywords** — `description:` line contains at least one of `CI`, `deploy`, `build`, `refactor`.

Manual acceptance, recorded once in the PR description, not gated by CI:

7. Run `scripts/install-skill` on the developer's own machine. From an unrelated project, ask Claude Code to "write a bun build script". Confirm the skill is routed and the agent reads `README.md` plus the `bun-deploy` example before producing scripts.
8. Same setup, but ask Claude Code to "refactor this deploy.sh". Confirm the agent goes through the `vendored-deploy-script` example as a pattern and replaces duplicated boilerplate without rewriting business logic.

## Out of scope (future work)

- Auto-generated function-table cheatsheet in the skill folder, synced from `README.md`.
- Decision-tree / flowchart for vendor-vs-URL choice with project signals.
- Refactor-prompt templates that an agent can quote.
- Packaging as a Claude Code plugin once the team owns more than one Gungnir-flavored skill.
- A `scripts/uninstall-skill` companion, if conflict scenarios become common in practice.
