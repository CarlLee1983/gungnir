#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/assert.sh
source "$ROOT_DIR/tests/assert.sh"

set -e

SKILL_DIR="$ROOT_DIR/skills/ci-toolkit"
SKILL_FILE="$SKILL_DIR/SKILL.md"

if [[ ! -f "$SKILL_FILE" ]]; then
  fail "SKILL.md missing at $SKILL_FILE"
  finish_tests
  exit 1
fi
pass "SKILL.md exists"

# Case 5: every ../../-prefixed path in SKILL.md resolves on disk
seen_paths=0
while IFS= read -r rel_path; do
  seen_paths=$((seen_paths + 1))
  full="$SKILL_DIR/$rel_path"
  if [[ -e "$full" ]]; then
    pass "relative path resolves: $rel_path"
  else
    fail "relative path missing: $rel_path (looked at $full)"
  fi
done < <(grep -oE '\.\./\.\./[A-Za-z0-9._/-]+' "$SKILL_FILE" | sort -u)

if [[ "$seen_paths" -gt 0 ]]; then
  pass "SKILL.md contains at least one ../../ reference"
else
  fail "SKILL.md contains no ../../ references — body has no pointers to README/examples"
fi

# Case 6: description: line in frontmatter contains a trigger keyword
description_line="$(grep -E '^description:' "$SKILL_FILE" || true)"
if [[ -n "$description_line" ]]; then
  pass "description: line present in frontmatter"
else
  fail "description: line missing from frontmatter"
fi

keyword_hit=""
for kw in CI deploy build refactor; do
  if [[ "$description_line" == *"$kw"* ]]; then
    keyword_hit="$kw"
    break
  fi
done
if [[ -n "$keyword_hit" ]]; then
  pass "description contains trigger keyword ($keyword_hit)"
else
  fail "description missing all keywords (CI/deploy/build/refactor): $description_line"
fi

finish_tests
