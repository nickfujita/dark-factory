#!/usr/bin/env bash
set -uo pipefail

# test-df-check-leakage.sh — acceptance for the leakage gate.
#
# The gate stops df's own stage names from landing in a product repo, where a
# teammate has no way to learn what `df-code-review` means and where the names
# go stale. Two things it must get right beyond the obvious catch: it must stay
# quiet in dark-factory itself, which owns the vocabulary, and it must respect
# the exemptions the router grants.
#
# Offline, no dependencies beyond git and coreutils, about a second.
#
# Usage: bash scripts/test-df-check-leakage.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO_ROOT/scripts/df-check-leakage.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/df-leakage-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '     %s\n' "$2"
}

# A project repo with one commit of clean baseline, ready for a second commit.
new_repo() {
  # new_repo <name>; echoes the path
  local dir="$WORK/$1"
  mkdir -p "$dir/src"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name "leakage test"
  printf 'export const ok = true;\n' >"$dir/src/app.js"
  git -C "$dir" add -A >/dev/null
  git -C "$dir" commit -qm base
  printf '%s' "$dir"
}

commit_all() { git -C "$1" add -A >/dev/null && git -C "$1" commit -qm change; }

# run_gate <dir>; echoes "<exit> <stdout+stderr on one line>"
run_gate() {
  local dir="$1" out rc
  out="$(cd "$dir" && bash "$GATE" HEAD~1 2>&1)"
  rc=$?
  printf '%s %s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

expect() {
  # expect <label> <want-exit> <dir> [substring that must appear]
  local label="$1" want="$2" dir="$3" needle="${4:-}" res rc out
  res="$(run_gate "$dir")"
  rc="${res%% *}"; out="${res#* }"
  if [[ "$rc" != "$want" ]]; then
    fail "$label" "exit: want $want, got $rc; output: ${out:0:160}"
    return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    fail "$label" "output missing '$needle'; got: ${out:0:160}"
    return
  fi
  pass "$label"
}

# ------------------------------------------------------- the catch it exists for

dir="$(new_repo leak)"
printf '// see df-code-review for the rubric\n' >>"$dir/src/app.js"
commit_all "$dir"
expect "a stage name in project source is a hit" 1 "$dir" "src/app.js"

dir="$(new_repo leak-prose)"
printf 'Reviewed under the Dark Factory pipeline.\n' >"$dir/README.md"
commit_all "$dir"
expect "the product name in project prose is a hit" 1 "$dir" "README.md"

dir="$(new_repo clean)"
printf 'export const two = 2;\n' >>"$dir/src/app.js"
commit_all "$dir"
expect "a branch with no df vocabulary is clean" 0 "$dir" "clean against"

# --------------------------------------------------------------- the exemptions

dir="$(new_repo verify-agents)"
mkdir -p "$dir/.agents/skills/verify-web/features"
printf 'Driven during df-acceptance against df-verify-coverage entries.\n' \
  >"$dir/.agents/skills/verify-web/SKILL.md"
commit_all "$dir"
expect "a repo's own verification skill is exempt (.agents)" 0 "$dir"

dir="$(new_repo verify-claude)"
mkdir -p "$dir/.claude/skills/verify-cli"
printf 'Driven during df-acceptance.\n' >"$dir/.claude/skills/verify-cli/SKILL.md"
commit_all "$dir"
expect "a repo's own verification skill is exempt (.claude)" 0 "$dir"

dir="$(new_repo working-output)"
mkdir -p "$dir/.dark-factory/reviews/code-review"
printf 'df-code-review report\n' >"$dir/.dark-factory/reviews/code-review/r.md"
commit_all "$dir"
expect "local working output under .dark-factory is exempt" 0 "$dir"

# The exemption is scoped. A verification skill does not launder the whole repo.
dir="$(new_repo verify-plus-leak)"
mkdir -p "$dir/.agents/skills/verify-web"
printf 'Driven during df-acceptance.\n' >"$dir/.agents/skills/verify-web/SKILL.md"
printf '// df-code-review said to\n' >>"$dir/src/app.js"
commit_all "$dir"
expect "an exempt file does not excuse a leak elsewhere" 1 "$dir" "src/app.js"

# ------------------------------------------------------------ the home repo

dir="$(new_repo home)"
mkdir -p "$dir/.claude-plugin"
printf '{\n  "name": "dark-factory",\n  "version": "0.0.0"\n}\n' \
  >"$dir/.claude-plugin/plugin.json"
printf '// df-code-review, df-acceptance, Dark Factory\n' >>"$dir/src/app.js"
commit_all "$dir"
expect "dark-factory itself is skipped, it owns the vocabulary" 0 "$dir" "skipped"

# A different plugin repo is not the home repo and stays in scope.
dir="$(new_repo other-plugin)"
mkdir -p "$dir/.claude-plugin"
printf '{\n  "name": "some-other-plugin",\n  "version": "0.0.0"\n}\n' \
  >"$dir/.claude-plugin/plugin.json"
printf '// df-code-review\n' >>"$dir/src/app.js"
commit_all "$dir"
expect "another plugin repo is still scanned" 1 "$dir" "src/app.js"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
