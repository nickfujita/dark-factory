#!/usr/bin/env bash
set -uo pipefail

# check-no-repo-scratch.sh — no skill may write its working artifacts into the
# repo it is operating on.
#
# df leaves no trace in a target repo. Run state already lives in the agent's
# own store (`scripts/df-state.sh path`), and everything a run produces that is
# not a deliverable belongs beside it: scratch, review reports, evidence.
#
# What a skill MAY write into the project: the PRD under `docs/`, the acceptance
# evidence record under `docs/qa/`, the project's own verification skill, and
# the feature code itself. Those are committed on purpose. Everything else is
# the agent's business, not the repo's.
#
# This started as a real defect. Five skills wrote scratch into `.dark-factory/`
# or `.claude/` inside the target repo, which meant a df run dirtied `git status`
# in a product repo and needed a `.gitignore` entry to stay out of commits.
#
# Usage: bash scripts/check-no-repo-scratch.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Repo-relative scratch paths. Anchored so a store-relative path built from
# `df-state.sh path` never matches: those are absolute and carry no leading dot
# segment.
PATTERN='(^|[^-[:alnum:]/_.])\.(dark-factory|claude|agents)/(tmp|reviews|qa-screenshots|evidence|scratch)\b'

hits=0
while IFS= read -r f; do
  if out=$(grep -nE "$PATTERN" -- "$f" 2>/dev/null); then
    printf '%s\n' "$out" | sed "s#^#${f}:#"
    hits=$((hits + 1))
  fi
done < <(find skills codex-plugin/skills -name '*.md' -type f | sort)

if [ "$hits" -gt 0 ]; then
  cat >&2 <<'MSG'

check-no-repo-scratch: a skill writes working artifacts into the target repo.

Working artifacts belong in the run's own directory in the agent's store,
outside the repo:

  run_dir="$(bash scripts/df-state.sh path "<run-id>")"
  "$run_dir/work"      scratch for one run
  "$run_dir/reviews"   review reports
  "$run_dir/evidence"  acceptance artifacts

Committed deliverables stay in the project: docs/prd-*.md, docs/qa/, the
project's own verification skill, and the feature code.
MSG
  exit 1
fi
echo "No repo scratch OK"
