#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_spec_review.sh <prd-path> <qa-path> <base-ref> <output-path>
# Runs a Codex CLI spec compliance review of the branch diff against the PRD
# and QA runbook. Codex reads the files and computes the diff internally —
# nothing is inlined into the prompt.

if [[ $# -lt 4 ]]; then
  echo "Usage: run_codex_spec_review.sh <prd-path> <qa-path> <base-ref> <output-path>" >&2
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
out_path="$4"

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

prd_rel="${prd_path#"$repo_root"/}"
qa_rel="${qa_path#"$repo_root"/}"

if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Error: base-ref '$base_ref' is not a valid git ref." >&2
  exit 1
fi

if git diff --quiet "$base_ref" HEAD; then
  echo "Error: no diff found between HEAD and $base_ref" >&2
  exit 1
fi

{
  echo "# Codex Spec Compliance Review"
  echo
  echo "- PRD: \`$prd_rel\`"
  echo "- QA Runbook: \`$qa_rel\`"
  echo "- Base ref: \`$base_ref\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (spec compliance axis)"
  echo
} >"$out_path"

stderr_log="${out_path%.md}.stderr.log"

# Codex has read-only sandbox access to the repo. Tell it where to find the
# PRD and QA runbook and how to get the diff — no content inlined.
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
  "You are an independent spec compliance reviewer. Verify that the implementation
satisfies the approved PRD and QA runbook.

First, read these files:
- PRD: $prd_rel
- QA runbook: $qa_rel

Then run: git diff $base_ref HEAD
to see the branch changes.

Read the changed source files for full context as needed.

Review the branch diff against the PRD and QA runbook for:
- **Requirement coverage**: Every REQ-xxx and NEG-xxx has corresponding implementation
- **Acceptance criteria**: Each criterion is met by the code
- **Negative requirements**: What must NOT happen is enforced in code
- **Edge cases**: PRD edge cases are handled
- **QA alignment**: Implementation would pass each TC-xxx in the runbook
- **Scope**: No scope creep (implementing things not in PRD) and no missing scope

Produce findings in this exact format:

## Findings — Codex Spec

### [SEVERITY] <One-line finding title>
**Requirement:** REQ-xxx | NEG-xxx | TC-xxx
**Location:** \`path/to/file.ts:line\` (or \"Not implemented\" if missing entirely)
**Issue:** 2-3 sentences explaining the gap between spec and implementation.
**Recommendation:** What the code should do to satisfy the requirement.

---

Severity levels:
- **Critical**: PRD requirement completely unimplemented or actively violated
- **High**: Requirement partially implemented or acceptance criterion not met
- **Medium**: Edge case or secondary flow from PRD not handled
- **Low**: Minor deviation from PRD intent, low user impact

Base your review only on the PRD and QA runbook — not on general best practices.
Do not flag missing features that are explicitly out of scope in the PRD.
If the PRD is ambiguous about a requirement, note the ambiguity rather than
assuming a specific interpretation." \
  >>"$out_path" \
  2>"$stderr_log" \
  || codex_exit=$?

if [[ "$codex_exit" -ne 0 ]]; then
  echo "Error: codex exec failed with exit code $codex_exit. See $stderr_log" >&2
  echo "" >>"$out_path"
  echo "## Findings — Codex Spec" >>"$out_path"
  echo "" >>"$out_path"
  echo "_Codex CLI exited with code $codex_exit. No findings produced._" >>"$out_path"
  exit 1
fi

if ! grep -q '^## Findings — Codex Spec' "$out_path"; then
  echo "Warning: Codex output missing findings header. Check $stderr_log." >&2
fi

if ! grep -Eq '^### \[?(Critical|High|Medium|Low)\]?' "$out_path"; then
  echo "Warning: Codex produced no structured severity findings. Check $stderr_log for errors." >&2
fi

echo "Codex spec review written to: $out_path"
