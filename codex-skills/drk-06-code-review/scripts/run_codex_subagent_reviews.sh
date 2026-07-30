#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_subagent_reviews.sh <prd-path> <qa-path> <base-ref> <output-dir>
# Runs the three Phase A code review roles as parallel codex exec processes.

if [[ $# -lt 4 ]]; then
  echo "Usage: run_codex_subagent_reviews.sh <prd-path> <qa-path> <base-ref> <output-dir>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
prd_path="$1"
qa_path="$2"
base_ref="$3"
out_dir="$4"

if [[ "$prd_path" != /* ]]; then prd_path="$repo_root/$prd_path"; fi
if [[ "$qa_path" != /* ]]; then qa_path="$repo_root/$qa_path"; fi

if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi
if [[ ! -f "$qa_path" ]]; then
  echo "Error: QA runbook not found at $qa_path" >&2
  exit 1
fi
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Error: base-ref '$base_ref' is not a valid git ref." >&2
  exit 1
fi
if git diff --quiet "$base_ref" HEAD; then
  echo "Error: no diff found between HEAD and $base_ref" >&2
  exit 1
fi

codex_skills_dir="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}"
ref_dir="$codex_skills_dir/drk-06-code-review/references"
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$repo_root/codex-skills/drk-06-code-review/references"
fi
if [[ ! -d "$ref_dir" ]]; then
  echo "Error: reference directory not found" >&2
  exit 1
fi

review_dir="${DARK_FACTORY_REVIEW_DIR:-$out_dir}"
mkdir -p "$review_dir" "$out_dir"
git diff "$base_ref" HEAD > "$review_dir/branch-diff.txt"

prd_rel="${prd_path#"$repo_root"/}"
qa_rel="${qa_path#"$repo_root"/}"

sandbox_mode="read-only"

run_review() {
  local label="$1"
  local prompt_file="$2"
  local out_path="$3"
  local stderr_log="${out_path%.md}.stderr.log"
  local prompt_rel="${prompt_file#"$repo_root"/}"
  local prompt_text
  prompt_text="$(cat "$prompt_file")"

  {
    echo "# $label"
    echo
    echo "- PRD: \`$prd_rel\`"
    echo "- QA Runbook: \`$qa_rel\`"
    echo "- Base ref: \`$base_ref\`"
    echo "- Prompt: \`$prompt_rel\`"
    echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
    echo
  } >"$out_path"

  codex exec \
    --sandbox "$sandbox_mode" \
    --config model_reasoning_effort=xhigh \
    -C "$repo_root" \
    "Follow this reviewer prompt:

$prompt_text

The PRD path is $prd_rel.
The QA runbook path is $qa_rel.
The branch diff has been cached at $review_dir/branch-diff.txt.
Read changed files as needed for context.
Return findings in the exact format required by the reviewer prompt." \
    >>"$out_path" \
    2>"$stderr_log"
}

run_review "Codex Quality Subagent Review" "$ref_dir/codex-quality-subagent-prompt.md" "$out_dir/codex-quality-subagent-review.md" &
pid1=$!
run_review "Codex Security Subagent Review" "$ref_dir/codex-security-subagent-prompt.md" "$out_dir/codex-security-subagent-review.md" &
pid2=$!
run_review "Codex Spec Subagent Review" "$ref_dir/codex-spec-subagent-prompt.md" "$out_dir/codex-spec-subagent-review.md" &
pid3=$!

status=0
for pid in "$pid1" "$pid2" "$pid3"; do
  if ! wait "$pid"; then
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  echo "One or more Codex subagent reviews failed. See $out_dir/*.stderr.log" >&2
  exit "$status"
fi

echo "Codex subagent-style reviews written to: $out_dir"
