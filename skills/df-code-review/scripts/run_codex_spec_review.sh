#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_spec_review.sh <prd-path> <qa-path> <base-ref> <output-path>
# Runs a Codex CLI spec compliance review of the branch diff against the PRD
# and QA runbook. Codex reads the files and computes the diff internally —
# nothing is inlined into the prompt.
#
# Output validation is FAIL-CLOSED (ported from df-prd-challenge): an empty or
# trivial review body is a failed run and a non-zero exit, never a warning.
# Environment override: CODEX_MIN_BODY_BYTES=400 (minimum accepted body when
# findings are claimed).
#
# Sandbox policy (D26): prefer --sandbox read-only on the live tree. When the
# read-only sandbox is unavailable (bwrap network namespaces unsupported, e.g.
# unprivileged VMs), NEVER run full access on the live tree — point codex at a
# disposable snapshot (temp git worktree, or cp -a copy for non-git trees),
# created for this review and deleted after. The status output says which mode
# actually ran.

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

MIN_BODY_BYTES="${CODEX_MIN_BODY_BYTES:-400}"

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

# ---------------------------------------------------------------- sandbox (D26)
# Never fall back to danger-full-access on the live tree. If the read-only
# sandbox is unavailable, review a disposable snapshot instead: a degraded
# sandbox can then only touch a throwaway copy.
sandbox_mode="read-only"
sandbox_note="read-only sandbox on the live tree"
review_tree="$repo_root"
snapshot_dir=""
snapshot_kind=""

cleanup_snapshot() {
  [[ -n "$snapshot_dir" ]] || return 0
  if [[ "$snapshot_kind" == "worktree" ]]; then
    git -C "$repo_root" worktree remove --force "$snapshot_dir/tree" >/dev/null 2>&1 || true
  fi
  rm -rf "$snapshot_dir"
  snapshot_dir=""
}
trap cleanup_snapshot EXIT

if ! unshare --net true 2>/dev/null; then
  snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/df-review-snapshot.XXXXXX")"
  if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1 \
     && git -C "$repo_root" worktree add --detach "$snapshot_dir/tree" HEAD >/dev/null 2>&1; then
    snapshot_kind="worktree"
  else
    snapshot_kind="copy"
    mkdir -p "$snapshot_dir/tree"
    cp -a "$repo_root/." "$snapshot_dir/tree/"
  fi
  # The PRD and QA runbook may carry uncommitted edits; overlay the live
  # copies so the snapshot reviews the current documents, not HEAD's.
  mkdir -p "$snapshot_dir/tree/$(dirname "$prd_rel")" "$snapshot_dir/tree/$(dirname "$qa_rel")"
  cp -f "$prd_path" "$snapshot_dir/tree/$prd_rel"
  cp -f "$qa_path" "$snapshot_dir/tree/$qa_rel"
  review_tree="$snapshot_dir/tree"
  sandbox_mode="danger-full-access"
  sandbox_note="sandbox degraded to danger-full-access on a disposable $snapshot_kind snapshot (unshare --net unavailable); the live tree is not exposed"
fi

{
  echo "# Codex Spec Compliance Review"
  echo
  echo "- PRD: \`$prd_rel\`"
  echo "- QA Runbook: \`$qa_rel\`"
  echo "- Base ref: \`$base_ref\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (spec compliance axis)"
  echo "- Sandbox: $sandbox_note"
  echo
} >"$out_path"

body_path="${out_path%.md}.body.md"
stderr_log="${out_path%.md}.stderr.log"

# A review is accepted only if the body actually contains one (fail-closed,
# ported from df-prd-challenge's status-file contract).
validate_body() {
  # echoes "<verdict> <reason>"
  local body="$1" bytes=0 findings=0
  if [[ -f "$body" ]]; then
    bytes="$(wc -c <"$body" | tr -d ' ')"
  fi
  if [[ "$bytes" -eq 0 ]]; then
    echo "invalid empty_body"
    return 0
  fi
  if ! grep -q '^## Findings — Codex Spec' "$body"; then
    echo "invalid missing_findings_header"
    return 0
  fi
  # Tolerate case drift and the literal bracket form of the prompt's own
  # "### [SEVERITY]" template.
  findings="$(grep -ciE '^###[[:space:]]+(\*\*)?\[?(critical|high|medium|low)\b' "$body" || true)"
  if [[ "$findings" -eq 0 ]]; then
    if grep -qE '^[[:space:]]*(\*\*)?NO FINDINGS' "$body"; then
      echo "valid explicit_no_findings"
      return 0
    fi
    echo "invalid no_structured_findings"
    return 0
  fi
  if [[ "$bytes" -lt "$MIN_BODY_BYTES" ]]; then
    echo "invalid body_below_min_bytes"
    return 0
  fi
  echo "valid ok"
}

# Codex has read-only sandbox access to the review tree. Tell it where to find
# the PRD and QA runbook and how to get the diff — no content inlined. stdin
# is closed: a reviewer that blocks on stdin produces a header and no
# findings, then reports success.
codex_exit=0
codex exec \
  --sandbox "$sandbox_mode" \
  --config model_reasoning_effort=xhigh \
  -C "$review_tree" \
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

IF YOU HAVE NO FINDINGS: output the '## Findings — Codex Spec' header
followed by a line containing exactly:

NO FINDINGS

Never return an empty document. Never stop to ask a question — you are running
non-interactively with no stdin.

Base your review only on the PRD and QA runbook — not on general best practices.
Do not flag missing features that are explicitly out of scope in the PRD.
If the PRD is ambiguous about a requirement, note the ambiguity rather than
assuming a specific interpretation." \
  <"/dev/null" \
  >"$body_path" \
  2>"$stderr_log" \
  || codex_exit=$?

if [[ "$codex_exit" -ne 0 ]]; then
  echo "Error: codex exec failed with exit code $codex_exit. See $stderr_log" >&2
  echo "" >>"$out_path"
  echo "## Findings — Codex Spec" >>"$out_path"
  echo "" >>"$out_path"
  echo "_Codex CLI exited with code $codex_exit. No findings produced._" >>"$out_path"
  echo "_This run produced NO reviewer opinion. Do not treat it as a clean round._" >>"$out_path"
  exit 1
fi

# Post-run validation: FAIL-CLOSED. An empty or trivial review body means the
# run failed — surface it to the calling skill as a failed run, not a warning.
read -r verdict reason <<<"$(validate_body "$body_path")"
if [[ "$verdict" != "valid" ]]; then
  echo "Error: Codex produced no usable review (reason: $reason). Raw body: $body_path. Stderr: $stderr_log" >&2
  echo "" >>"$out_path"
  echo "## Findings — Codex Spec" >>"$out_path"
  echo "" >>"$out_path"
  echo "_No usable review produced (reason: \`$reason\`)._" >>"$out_path"
  echo "_This run produced NO reviewer opinion. Do not treat it as a clean round._" >>"$out_path"
  exit 1
fi

cat "$body_path" >>"$out_path"

echo "Codex spec review written to: $out_path"
echo "Sandbox: $sandbox_note"
