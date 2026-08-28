#!/usr/bin/env bash
# Scan a branch for Dark Factory vocabulary that leaked into the project.
#
# The project's tree belongs to the project. A teammate reading `df-code-review`
# in a code comment has no way to learn what that is, and the names change: a
# whole generation of `drk-*` stage names retired in one day and left dead
# references behind in shared source. This catches the next one at the branch,
# before a reviewer has to.
#
# Reports and exits nonzero. It never edits: the fix is a judgment about what
# the comment meant, and the substitution table in the df router names it.
#
# Usage: df-check-leakage.sh [base-ref]        (default: origin/HEAD, else main)
set -uo pipefail

base=${1:-}
if [ -z "$base" ]; then
  base=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || base=""
  [ -n "$base" ] || base=main
fi
git rev-parse --verify --quiet "$base" >/dev/null \
  || { echo "df-check-leakage: no such base ref '$base'" >&2; exit 1; }

# dark-factory is the repo that OWNS this vocabulary. Its own source, manifests
# and Justfile name these skills on every branch, so scanning it reports dozens
# of hits that are all correct usage. A gate that fires every time is a gate
# people learn to skip, and skipping is exactly when a real leak into a product
# repo gets through. Recognise the home repo and say nothing.
top=$(git rev-parse --show-toplevel 2>/dev/null) || top=""
if [ -n "$top" ] && [ -f "$top/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"dark-factory"' "$top/.claude-plugin/plugin.json"; then
  echo "df-check-leakage: skipped, this is dark-factory itself and it owns the vocabulary"
  exit 0
fi

# Anchor on names that are unambiguously ours. A bare `df-` would fire on any
# project with its own df prefix, so the skill names are listed explicitly.
PATTERN='\bdrk-[0-9]|\bdrk-reviewer|dark-factory-codex|[Dd]ark [Ff]actory|df-prd-interview|df-prd-challenge|df-verify-coverage|df-qa-validation|df-dev-verify|df-code-review|df-acceptance|df-implement|df-design|df-plan|df-eval|df-reviewer-recheck|df-state\.sh|df-open-pr'

# Two exemptions, both from the router's writing-into-the-project rule.
# `.dark-factory/` holds a run's local working output. A repo's own verification
# skill is the project's asset and may name whatever it likes, so anything under
# a `skills/verify-*/` directory is out of scope wherever the harness keeps it.
files=$(git diff --name-only --diff-filter=ACMR "$base"...HEAD -- . \
        ':(exclude).dark-factory/**' \
        ':(exclude,glob)**/skills/verify-*/**' 2>/dev/null) || files=""
[ -n "$files" ] || { echo "df-check-leakage: no changed files against $base"; exit 0; }

hits=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if out=$(grep -nE "$PATTERN" -- "$f" 2>/dev/null); then
    printf '%s\n' "$out" | sed "s#^#${f}:#"
    hits=$((hits + 1))
  fi
done <<EOF
$files
EOF

if [ "$hits" -gt 0 ]; then
  cat >&2 <<'MSG'

df-check-leakage: Dark Factory vocabulary found in the branch.

Name the kind of work, not the skill that did it. Keep finding ids verbatim.

  df-prd-challenge  -> spec review
  df-dev-verify     -> dev verification
  df-code-review    -> code review
  df-acceptance     -> QA acceptance

A deliberate mention (a repo documenting its own tooling) is fine: rerun with
that file committed on the base, or state the exemption in the PR.
MSG
  exit 1
fi
echo "df-check-leakage: clean against $base"
