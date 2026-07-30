#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_prd_review.sh <prd-path> <output-path>
# Runs a Codex CLI review of a PRD and writes findings to the output path.
# Designed for the PRD challenge round — produces structured findings
# compatible with the synthesis step.
# Codex reads the PRD file internally — nothing is inlined into the prompt.

if [[ $# -lt 2 ]]; then
  echo "Usage: run_codex_prd_review.sh <prd-path> <output-path>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

prd_path="$1"
out_path="$2"

if [[ "$prd_path" != /* ]]; then
  prd_path="$repo_root/$prd_path"
fi

if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi

rel_path="${prd_path#"$repo_root"/}"
# If stripping failed (path outside repo), use basename
if [[ "$rel_path" == "$prd_path" ]]; then
  rel_path="$(basename "$prd_path")"
fi

{
  echo "# Codex PRD Challenge Review"
  echo
  echo "- Source: \`$rel_path\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (model diversity)"
  echo
} >"$out_path"

stderr_log="${out_path%.md}.stderr.log"

# Codex has read-only sandbox access to the repo. Tell it where to find
# the PRD — no content inlined. It can also explore the codebase for context.
# Use read-only sandbox if available, fall back to danger-full-access
# when bubblewrap network namespaces are unsupported (e.g., unprivileged VMs).
sandbox_mode="read-only"
if ! unshare --net true 2>/dev/null; then
  sandbox_mode="danger-full-access"
fi

codex_exit=0
codex exec \
  --sandbox "$sandbox_mode" \
  --config model_reasoning_effort=xhigh \
  -C "$repo_root" \
  "You are an independent reviewer examining a PRD (Product Requirements Document).
Your goal is to find gaps, contradictions, and ambiguities that the PRD author
may have missed.

First, read the PRD file at: $rel_path

Then explore the codebase for context to ground your analysis.

Review the PRD and produce findings in this exact format:

## Findings — Codex

### [SEVERITY]: [One-line finding title]
**Requirement:** [Which REQ-xxx or section this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix or question to resolve it]

---

Severity levels:
- **Critical**: Blocks implementation or causes incorrect behavior
- **High**: Significant gap that will likely cause rework
- **Medium**: Improvement that would strengthen the PRD
- **Low**: Minor suggestion or style issue

Focus on:
- Missing edge cases and error states
- Contradictory or ambiguous requirements
- Acceptance criteria that are not testable
- Scope gaps (mentioned in requirements but not in scope, or vice versa)
- Non-functional requirements that lack measurable thresholds

Do NOT suggest implementation approaches or architectural decisions.
Do NOT add new features — only identify gaps in existing requirements." \
  >>"$out_path" \
  2>"$stderr_log" \
  || codex_exit=$?

if [[ "$codex_exit" -ne 0 ]]; then
  echo "Error: codex exec failed with exit code $codex_exit. See $stderr_log" >&2
  # Append failure note to output so synthesis can see it
  echo "" >>"$out_path"
  echo "## Findings — Codex" >>"$out_path"
  echo "" >>"$out_path"
  echo "_Codex CLI exited with code $codex_exit. No findings produced._" >>"$out_path"
  exit 1
fi

# Validate structured output
if ! grep -q '^## Findings — Codex' "$out_path"; then
  echo "Warning: Codex output missing findings header. Check $stderr_log for errors." >&2
fi

if ! grep -Eq '^### (Critical|High|Medium|Low): ' "$out_path"; then
  echo "Warning: Codex produced no structured severity findings. Check $stderr_log for errors." >&2
fi

echo "Codex challenge review written to: $out_path"
