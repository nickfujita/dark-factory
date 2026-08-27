#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_quality_review.sh <base-ref> <output-path>
# Runs a Codex CLI code quality review of the branch diff and writes findings
# to the output path. Codex has read-only repo access and runs its own
# git diff / file reads internally — nothing is inlined into the prompt.

if [[ $# -lt 2 ]]; then
  echo "Usage: run_codex_quality_review.sh <base-ref> <output-path>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
base_ref="$1"
out_path="$2"

# Validate base ref before using it
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Error: base-ref '$base_ref' is not a valid git ref." >&2
  exit 1
fi

# Verify there are changes to review
if git diff --quiet "$base_ref" HEAD; then
  echo "Error: no diff found between HEAD and $base_ref" >&2
  exit 1
fi

{
  echo "# Codex Code Quality Review"
  echo
  echo "- Base ref: \`$base_ref\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (code quality axis)"
  echo
} >"$out_path"

stderr_log="${out_path%.md}.stderr.log"

# Codex has read-only sandbox access to the repo. Tell it the base ref and
# let it run git diff and read source files internally — no inlined content.
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
  "You are an independent code quality reviewer examining a feature branch diff.

Run: git diff $base_ref HEAD
to see the branch changes. Read the changed source files for full context.

Review the diff for code quality and correctness issues. Focus on:
- **Correctness**: Logic errors, wrong conditions, off-by-one errors
- **Edge cases**: Null/undefined handling, empty inputs, boundary values
- **Error handling**: Unhandled exceptions, swallowed errors, missing propagation
- **Test coverage**: Missing tests for critical paths or edge cases
- **Performance**: N+1 queries, unnecessary re-renders (not premature optimization)
- **Clarity**: Dead code, misleading names, overly complex logic

Produce findings in this exact format:

## Findings — Codex Quality

### [SEVERITY] <One-line finding title>
**Category:** Correctness | Edge Case | Error Handling | Test Coverage | Performance | Clarity
**Location:** \`path/to/file.ts:line\`
**Issue:** 2-3 sentences explaining the problem.
**Recommendation:** Concrete fix. Include a short code snippet if it clarifies the fix.

---

Severity levels:
- **Critical**: Will cause incorrect behavior or crashes in production
- **High**: Likely to cause bugs under normal use
- **Medium**: Could cause issues in less common scenarios
- **Low**: Clarity or style improvement, no functional impact

Only report findings on changed code (lines in the diff). Do NOT suggest
features or refactoring beyond the diff scope. YAGNI applies." \
  >>"$out_path" \
  2>"$stderr_log" \
  || codex_exit=$?

if [[ "$codex_exit" -ne 0 ]]; then
  echo "Error: codex exec failed with exit code $codex_exit. See $stderr_log" >&2
  echo "" >>"$out_path"
  echo "## Findings — Codex Quality" >>"$out_path"
  echo "" >>"$out_path"
  echo "_Codex CLI exited with code $codex_exit. No findings produced._" >>"$out_path"
  exit 1
fi

if ! grep -q '^## Findings — Codex Quality' "$out_path"; then
  echo "Warning: Codex output missing findings header. Check $stderr_log." >&2
fi

if ! grep -Eq '^### \[?(Critical|High|Medium|Low)\]?' "$out_path"; then
  echo "Warning: Codex produced no structured severity findings. Check $stderr_log for errors." >&2
fi

echo "Codex quality review written to: $out_path"
