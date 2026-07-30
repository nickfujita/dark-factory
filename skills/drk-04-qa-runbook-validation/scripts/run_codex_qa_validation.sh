#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_qa_validation.sh <prd-path> <qa-path> <output-path>
# Runs a Codex CLI review of a PRD+QA runbook pair and writes findings to the
# output path. Designed for the QA runbook validation stage — produces
# structured findings compatible with the synthesis step.
# Codex reads the files internally — nothing is inlined into the prompt.

if [[ $# -lt 3 ]]; then
  echo "Usage: run_codex_qa_validation.sh <prd-path> <qa-path> <output-path>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

prd_path="$1"
qa_path="$2"
out_path="$3"

# Resolve relative paths to absolute using repo_root
if [[ "$prd_path" != /* ]]; then
  prd_path="$repo_root/$prd_path"
fi

if [[ "$qa_path" != /* ]]; then
  qa_path="$repo_root/$qa_path"
fi

# Validate both files exist
if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi

if [[ ! -f "$qa_path" ]]; then
  echo "Error: QA runbook file not found at $qa_path" >&2
  exit 1
fi

# Compute relative paths for display
prd_rel="${prd_path#"$repo_root"/}"
if [[ "$prd_rel" == "$prd_path" ]]; then
  prd_rel="$(basename "$prd_path")"
fi

qa_rel="${qa_path#"$repo_root"/}"
if [[ "$qa_rel" == "$qa_path" ]]; then
  qa_rel="$(basename "$qa_path")"
fi

# Write file header to output
{
  echo "# Codex QA Runbook Validation Review"
  echo
  echo "- PRD: \`$prd_rel\`"
  echo "- QA Runbook: \`$qa_rel\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (model diversity)"
  echo
} >"$out_path"

stderr_log="${out_path%.md}.stderr.log"

# Codex has read-only sandbox access to the repo. Tell it where to find the
# PRD and QA runbook — no content inlined.
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
  "You are an independent reviewer examining a QA runbook against its source PRD
(Product Requirements Document). Your goal is to find gaps where the QA
runbook does not adequately validate the PRD's requirements.

First, read these files:
- PRD: $prd_rel
- QA runbook: $qa_rel

Review both documents together and produce findings in this exact format:

## Findings — Codex

### [SEVERITY]: [One-line finding title]
**Category:** [Coverage | Consistency | Testability | Completeness]
**Requirement:** [Which REQ-xxx, NEG-xxx, or TC-xxx this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix — specify whether the PRD or QA runbook should change]

---

Severity levels:
- **Critical**: Requirement completely untested or QA contradicts PRD
- **High**: Significant coverage gap that will likely miss real defects
- **Medium**: Improvement that would strengthen the QA runbook
- **Low**: Minor suggestion or style issue

Focus areas:
- **Coverage**: PRD requirements that have no corresponding QA test case
- **Consistency**: QA steps or acceptance criteria that contradict the PRD
- **Testability**: Test cases with vague or unmeasurable pass/fail criteria
- **Completeness**: Missing edge cases, error paths, or non-functional checks
  mentioned in the PRD but absent from the QA runbook

Do NOT suggest implementation approaches or architectural decisions.
Do NOT add new test cases — only identify gaps in existing coverage." \
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

# Post-run validation: check for expected structure
if ! grep -q '^## Findings — Codex' "$out_path"; then
  echo "Warning: Codex output missing findings header. Check $stderr_log for errors." >&2
fi

if ! grep -Eq '^### (Critical|High|Medium|Low): ' "$out_path"; then
  echo "Warning: Codex produced no structured severity findings. Check $stderr_log for errors." >&2
fi

echo "Codex QA validation review written to: $out_path"
