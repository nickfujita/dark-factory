#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_spec_review.sh <prd-path> <selection-ref> <repo-root> \
#   <base-ref> <output-path> --df-run <run-id> --df-lane <lane> \
#   --df-repo-root <consumer-root>
# Runs a Codex CLI spec compliance review of the branch diff against the PRD
# and sealed recipe selection. Codex reads the files and computes the diff
# internally. The selection identities are explicit review input.
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

if [[ $# -ne 11 ]]; then
  echo "Usage: run_codex_spec_review.sh <prd-path> <selection-ref> <repo-root> <base-ref> <output-path> --df-run <run-id> --df-lane <lane> --df-repo-root <consumer-root>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_root="$(cd "$script_dir/../../.." && pwd)"
if [[ -n "${DARK_FACTORY_ROOT:-}" && -f "$DARK_FACTORY_ROOT/scripts/df-code-review-selection.mjs" ]]; then
  df_root="$DARK_FACTORY_ROOT"
elif [[ -f "$local_root/scripts/df-code-review-selection.mjs" ]]; then
  df_root="$local_root"
else
  echo "Error: cannot find df-code-review-selection.mjs. Invoke this wrapper from the Dark Factory installation or checkout named by the session hook." >&2
  exit 1
fi
df_root="$(cd "$df_root" && pwd -P)"
selection_tool="$df_root/scripts/df-code-review-selection.mjs"
role_caller="$df_root/scripts/df-role-caller.sh"
state_helper="${DF_ROLE_CALLER_STATE_HELPER:-$df_root/scripts/df-state.sh}"

prd_path="$1"
selection_ref="$2"
repo_root="$3"
base_ref="$4"
out_path="$5"
shift 5

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
repo_root="$(cd "$repo_root" && pwd -P)"
df_repo_root="$(cd "$df_repo_root" && pwd -P)"
if [[ "$repo_root" != "$df_repo_root" ]]; then
  echo "Error: repo-root and --df-repo-root must name the same consumer checkout." >&2
  exit 1
fi

MIN_BODY_BYTES="${CODEX_MIN_BODY_BYTES:-400}"

if [[ "$repo_root" != /* ]]; then repo_root="$(cd "$repo_root" && pwd -P)"; fi
if [[ "$out_path" != /* ]]; then out_path="$repo_root/$out_path"; fi
selection_input="${out_path}.selection.json"
node "$selection_tool" prepare \
  --prd-path "$prd_path" \
  --selection-ref "$selection_ref" \
  --repo-root "$repo_root" \
  --output-path "$selection_input" >/dev/null
repo_root="$(git -C "$repo_root" rev-parse --show-toplevel)"
selection_details="$(node "$selection_tool" describe --input-path "$selection_input")"

if [[ "$prd_path" != /* ]]; then prd_path="$repo_root/$prd_path"; fi
prd_rel="${prd_path#"$repo_root"/}"

if ! git -C "$repo_root" rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Error: base-ref '$base_ref' is not a valid git ref." >&2
  exit 1
fi

if git -C "$repo_root" diff --quiet "$base_ref" HEAD; then
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
  snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/df-review-snapshot.XXXXXX")"
  if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1 \
     && git -C "$repo_root" worktree add --detach "$snapshot_dir/tree" HEAD >/dev/null 2>&1; then
    snapshot_kind="worktree"
  else
    snapshot_kind="copy"
    mkdir -p "$snapshot_dir/tree"
    cp -a "$repo_root/." "$snapshot_dir/tree/"
  fi
  # Selected inputs may carry uncommitted edits. Overlay every PRD, skill and
  # recipe that B1 materialized, so the frozen snapshot reads the same bytes
  # as the owning consumer checkout.
  while IFS= read -r input_rel; do
    mkdir -p "$snapshot_dir/tree/$(dirname "$input_rel")"
    cp -f "$repo_root/$input_rel" "$snapshot_dir/tree/$input_rel"
  done < <(node "$selection_tool" paths --input-path "$selection_input")
  review_tree="$snapshot_dir/tree"
  sandbox_mode="danger-full-access"
  sandbox_note="sandbox degraded to danger-full-access on a disposable $snapshot_kind snapshot (unshare --net unavailable); the live tree is not exposed"
fi

# Validate once more after creating any snapshot and before the reviewer can
# start. A changed selected source requires coverage to reseal and a restart.
node "$selection_tool" verify \
  --prd-path "$prd_path" \
  --selection-ref "$selection_ref" \
  --repo-root "$repo_root" >/dev/null

{
  echo "# Codex Spec Compliance Review"
  echo
  echo "- PRD: \`$prd_rel\`"
  echo "- Selection input: \`$selection_input\`"
  echo "- Base ref: \`$base_ref\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (spec compliance axis)"
  echo "- Sandbox: $sandbox_note"
  echo
  echo "## Sealed verification selection"
  printf '%s\n' "$selection_details"
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
# the PRD and sealed selection and how to get the diff. stdin
# is closed: a reviewer that blocks on stdin produces a header and no
# findings, then reports success.
dispatch_receipt="$(bash "$role_caller" reserve \
  --run "$df_run" --lane "$df_lane" --repo-root "$repo_root" \
  --responsibility cross_model_review --purpose 'code review spec' \
  --allow-kind transport --allow-transport codex-cli)"
dispatch_seq="$(node -e 'const receipt = JSON.parse(process.argv[1]); process.stdout.write(receipt.seqs[0]);' "$dispatch_receipt")"

codex_exit=0
codex exec \
  --sandbox "$sandbox_mode" \
  -C "$review_tree" \
  "You are an independent spec compliance reviewer. Verify that the implementation
satisfies the approved PRD and every identity in the sealed verification selection.

First, read these files:
- PRD: $prd_rel

$selection_details

For every selected entry, read its skillPath and recipePath. Do not substitute,
discover, merge, or omit an entry. A no-user-route selection has zero entries;
read its reason and review only the PRD-bound scope.

Then run: git diff $base_ref HEAD
to see the branch changes.

Read the changed source files for full context as needed.

Review the branch diff against the PRD and sealed selection for:
- **Requirement coverage**: Every REQ-xxx and NEG-xxx has corresponding implementation
- **Acceptance criteria**: Each criterion is met by the code
- **Negative requirements**: What must NOT happen is enforced in code
- **Edge cases**: PRD edge cases are handled
- **Recipe alignment**: Implementation matches every selected recipe identity,
  including its medium, sub-feature, and REQ/NEG mappings
- **Scope**: No scope creep (implementing things not in PRD) and no missing scope

Produce findings in this exact format:

## Findings — Codex Spec

### [SEVERITY] <One-line finding title>
**Requirement:** REQ-xxx | NEG-xxx | selected entry ID
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

Base your review only on the PRD and sealed selection — not on general best practices.
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

if ! node "$selection_tool" verify \
  --prd-path "$prd_path" \
  --selection-ref "$selection_ref" \
  --repo-root "$repo_root" >/dev/null; then
  echo "Error: selected source changed during review. Coverage must reseal and this review must restart." >&2
  echo "" >>"$out_path"
  echo "_Selected source changed during review. Coverage must reseal and this review must restart._" >>"$out_path"
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
