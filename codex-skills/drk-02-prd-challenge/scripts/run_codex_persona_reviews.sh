#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_persona_reviews.sh <prd-path> <output-dir>
# Runs the three PRD challenge persona reviews as parallel codex exec processes.

if [[ $# -lt 2 ]]; then
  echo "Usage: run_codex_persona_reviews.sh <prd-path> <output-dir>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
prd_path="$1"
out_dir="$2"

if [[ "$prd_path" != /* ]]; then
  prd_path="$repo_root/$prd_path"
fi
if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi

codex_skills_dir="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}"
persona_path="$codex_skills_dir/drk-02-prd-challenge/references/personas.md"
if [[ ! -f "$persona_path" ]]; then
  persona_path="$repo_root/codex-skills/drk-02-prd-challenge/references/personas.md"
fi
if [[ ! -f "$persona_path" ]]; then
  echo "Error: personas.md not found" >&2
  exit 1
fi

mkdir -p "$out_dir"
prd_rel="${prd_path#"$repo_root"/}"
persona_rel="${persona_path#"$repo_root"/}"
persona_text="$(cat "$persona_path")"

sandbox_mode="read-only"

run_persona() {
  local persona_name="$1"
  local section="$2"
  local out_path="$3"
  local stderr_log="${out_path%.md}.stderr.log"

  {
    echo "# PRD Persona Review: $persona_name"
    echo
    echo "- PRD: \`$prd_rel\`"
    echo "- Persona source: \`$persona_rel\`"
    echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
    echo
  } >"$out_path"

  codex exec \
    --sandbox "$sandbox_mode" \
    --config model_reasoning_effort=xhigh \
    -C "$repo_root" \
    "Read the PRD at $prd_rel.
Use only the section named \"$section\" from these persona instructions:

$persona_text

Explore the codebase for context, then review the PRD using that persona.
Return findings in the exact output format specified for that persona.
Do not suggest implementation approaches or new features." \
    >>"$out_path" \
    2>"$stderr_log"
}

run_persona "Skeptical User Advocate" "Persona 1: Skeptical User Advocate" "$out_dir/user-advocate.md" &
pid1=$!
run_persona "Technical Feasibility Reviewer" "Persona 2: Technical Feasibility Reviewer" "$out_dir/technical-feasibility.md" &
pid2=$!
run_persona "Scope & Complexity Challenger" "Persona 3: Scope & Complexity Challenger" "$out_dir/scope-complexity.md" &
pid3=$!

status=0
for pid in "$pid1" "$pid2" "$pid3"; do
  if ! wait "$pid"; then
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  echo "One or more Codex persona reviews failed. See $out_dir/*.stderr.log" >&2
  exit "$status"
fi

echo "Codex persona reviews written to: $out_dir"
