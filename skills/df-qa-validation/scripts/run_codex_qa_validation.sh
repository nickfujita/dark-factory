#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_qa_validation.sh <prd-path> <review-input-path> <output-path> \
#   --df-run <run-id> --df-lane <lane> --df-repo-root <consumer-root>
# Runs a Codex CLI review of a PRD+verification review input pair and writes findings to the
# output path. Designed for the verification review input validation stage — produces
# structured findings compatible with the synthesis step.
# Codex reads the files internally — nothing is inlined into the prompt.
#
# Output validation is FAIL-CLOSED (ported from df-prd-challenge): an empty or
# trivial review body is a failed run and a non-zero exit, never a warning.
# Environment override: CODEX_MIN_BODY_BYTES=400 (minimum accepted body when
# findings are claimed).
#
# Sandbox policy (D26): prefer --sandbox read-only on a frozen snapshot. When the
# read-only sandbox is unavailable (bwrap network namespaces unsupported, e.g.
# unprivileged VMs), NEVER run full access on the live tree — point codex at a
# disposable snapshot (temp git worktree, or cp -a copy for non-git trees),
# created for this review and deleted after. The status output says which mode
# actually ran.

if [[ $# -ne 9 ]]; then
  echo "Usage: run_codex_qa_validation.sh <prd-path> <review-input-path> <output-path> --df-run <run-id> --df-lane <lane> --df-repo-root <consumer-root>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

prd_path="$1"
qa_path="$2"
out_path="$3"
shift 3

df_run=''
df_lane=''
df_repo_root=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --df-run) df_run=$2; shift 2 ;;
    --df-lane) df_lane=$2; shift 2 ;;
    --df-repo-root) df_repo_root=$2; shift 2 ;;
    *) echo "Error: unknown role-dispatch option '$1'" >&2; exit 1 ;;
  esac
done
[[ -n "$df_run" && -n "$df_lane" && -n "$df_repo_root" ]] || {
  echo "Error: --df-run, --df-lane, and --df-repo-root are required." >&2
  exit 1
}
repo_root="$(cd "$df_repo_root" && pwd -P)"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
role_caller="$plugin_root/scripts/df-role-caller.sh"
state_helper="${DF_ROLE_CALLER_STATE_HELPER:-$plugin_root/scripts/df-state.sh}"

MIN_BODY_BYTES="${CODEX_MIN_BODY_BYTES:-400}"

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
  echo "Error: verification review input file not found at $qa_path" >&2
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

# ---------------------------------------------------------------- sandbox (D26)
# Never fall back to danger-full-access on the live tree. If the read-only
# sandbox is unavailable, review a disposable snapshot instead: a degraded
# sandbox can then only touch a throwaway copy.
sandbox_mode="read-only"
sandbox_note="read-only sandbox on a frozen snapshot"
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
dispatch_seq=''
complete_dispatch() {
  local exit_code=$?
  if [[ -n "$dispatch_seq" ]]; then
    local outcome=ok
    [[ "$exit_code" -eq 0 ]] || outcome=failed
    (cd "$repo_root" && bash "$state_helper" complete "$df_run" "$dispatch_seq" "$outcome") >/dev/null 2>&1 || true
  fi
  cleanup_snapshot
  return "$exit_code"
}
trap complete_dispatch EXIT

if ! unshare --net true 2>/dev/null; then
  sandbox_mode="danger-full-access"
fi

# Freeze both documents in every mode. A run-state input may be outside the
# repository and cannot be read via its basename in the live checkout.
snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/df-review-snapshot.XXXXXX")"
if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1 \
   && git -C "$repo_root" worktree add --detach "$snapshot_dir/tree" HEAD >/dev/null 2>&1; then
  snapshot_kind="worktree"
else
  snapshot_kind="copy"
  mkdir -p "$snapshot_dir/tree"
  cp -a "$repo_root/." "$snapshot_dir/tree/"
fi
mkdir -p "$snapshot_dir/tree/$(dirname "$prd_rel")" "$snapshot_dir/tree/$(dirname "$qa_rel")"
cp -f "$prd_path" "$snapshot_dir/tree/$prd_rel"
cp -f "$qa_path" "$snapshot_dir/tree/$qa_rel"
review_tree="$snapshot_dir/tree"
sandbox_note="$sandbox_mode on a disposable $snapshot_kind snapshot"

# Write file header to output
{
  echo "# Codex Verification Input Validation Review"
  echo
  echo "- PRD: \`$prd_rel\`"
  echo "- Verification Input: \`$qa_rel\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (model diversity)"
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
  if ! grep -q '^## Findings — Codex' "$body"; then
    echo "invalid missing_findings_header"
    return 0
  fi
  # Tolerate case drift and the literal bracket form of the prompt's own
  # "### [SEVERITY]:" template.
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
# the PRD and verification review input — no content inlined. stdin is closed: a reviewer
# that blocks on stdin produces a header and no findings, then reports success.
dispatch_receipt="$(bash "$role_caller" reserve \
  --run "$df_run" --lane "$df_lane" --repo-root "$repo_root" \
  --responsibility cross_model_review --purpose 'qa validation review' \
  --allow-kind transport --allow-transport codex-cli)"
dispatch_seq="$(node -e 'const receipt = JSON.parse(process.argv[1]); process.stdout.write(receipt.seqs[0]);' "$dispatch_receipt")"

codex_exit=0
codex exec \
  --sandbox "$sandbox_mode" \
  -C "$review_tree" \
  "You are an independent reviewer examining a verification review input against its source PRD
(Product Requirements Document). The input contains a coverage handoff and
verbatim project-owned base skills, feature maps, and programmatic proof plans.
Review the intended proof against the approved requirements, not whether a
planned feature has already been implemented or accepted.

First, read these files:
- PRD: $prd_rel
- verification review input: $qa_rel

Review both documents together and produce findings in this exact format:

## Findings — Codex

### [SEVERITY]: [One-line finding title]
**Category:** [Coverage | Consistency | Testability | Completeness]
**Requirement:** [Which REQ-xxx, NEG-xxx, or TC-xxx this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix — specify whether the PRD or verification review input should change]

---

Severity levels:
- **Critical**: Requirement completely untested or QA contradicts PRD
- **High**: Significant coverage gap that will likely miss real defects
- **Medium**: Improvement that would strengthen the verification review input
- **Low**: Minor suggestion or style issue

Focus areas:
- **Coverage**: PRD requirements without a recipe or justified programmatic proof plan
- **Consistency**: QA steps or acceptance criteria that contradict the PRD
- **Testability**: Test cases with vague or unmeasurable pass/fail criteria
- **Completeness**: Missing edge cases, error paths, or non-functional checks
  mentioned in the PRD but absent from the verification review input

IF YOU HAVE NO FINDINGS: output the '## Findings — Codex' header followed by a
line containing exactly:

NO FINDINGS

Never return an empty document. Never stop to ask a question — you are running
non-interactively with no stdin.

Do NOT suggest implementation approaches or architectural decisions.
Do NOT add requirements or edit recipes. Identify gaps in the supplied plan.
A planned recipe is not a live PASS. Use each declared medium's public contract;
do not require browser steps for CLI, TUI, MCP, API, or internal-only behavior.
Requirement IDs are not catalog IDs. Programmatic-only proof is valid for
internal requirements. A matching test ID is not evidence of meaningful assertions." \
  <"/dev/null" \
  >"$body_path" \
  2>"$stderr_log" \
  || codex_exit=$?

if [[ "$codex_exit" -ne 0 ]]; then
  echo "Error: codex exec failed with exit code $codex_exit. See $stderr_log" >&2
  # Append failure note to output so synthesis can see it
  echo "" >>"$out_path"
  echo "## Findings — Codex" >>"$out_path"
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
  echo "## Findings — Codex" >>"$out_path"
  echo "" >>"$out_path"
  echo "_No usable review produced (reason: \`$reason\`)._" >>"$out_path"
  echo "_This run produced NO reviewer opinion. Do not treat it as a clean round._" >>"$out_path"
  exit 1
fi

cat "$body_path" >>"$out_path"

echo "Codex QA validation review written to: $out_path"
echo "Sandbox: $sandbox_note"
