#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_subagent_reviews.sh <prd-path> <qa-path> <base-ref> <output-dir>
# Runs the three Phase A code review roles as parallel codex exec processes.
#
# Output validation is FAIL-CLOSED (ported from df-prd-challenge): an empty or
# trivial review body is a failed review and a non-zero exit, never a warning.
# Environment override: CODEX_MIN_BODY_BYTES=400 (minimum accepted body when
# findings are claimed).
#
# Sandbox policy (D26): prefer --sandbox read-only on the live tree. When the
# read-only sandbox is unavailable (bwrap network namespaces unsupported, e.g.
# unprivileged VMs), NEVER run full access on the live tree — point codex at a
# disposable snapshot (temp git worktree, or cp -a copy for non-git trees)
# shared by the three reviewers, created for this round and deleted after. The
# review target is committed state (git diff base..HEAD), so a snapshot at HEAD
# is exact.

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
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Error: base-ref '$base_ref' is not a valid git ref." >&2
  exit 1
fi
if git diff --quiet "$base_ref" HEAD; then
  echo "Error: no diff found between HEAD and $base_ref" >&2
  exit 1
fi

codex_skills_dir="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}"
ref_dir="$codex_skills_dir/df-code-review/references"
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$repo_root/codex-skills/df-code-review/references"
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
  review_tree="$snapshot_dir/tree"
  sandbox_mode="danger-full-access"
  sandbox_note="sandbox degraded to danger-full-access on a disposable $snapshot_kind snapshot (unshare --net unavailable); the live tree is not exposed"
fi

# A review is accepted only if the body actually contains one (fail-closed,
# ported from df-prd-challenge's status-file contract).
validate_body() {
  # validate_body <body> <expected-header> — echoes "<verdict> <reason>"
  local body="$1" header="$2" bytes=0 findings=0
  if [[ -f "$body" ]]; then
    bytes="$(wc -c <"$body" | tr -d ' ')"
  fi
  if [[ "$bytes" -eq 0 ]]; then
    echo "invalid empty_body"
    return 0
  fi
  if ! grep -q "^$header" "$body"; then
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

run_review() {
  local label="$1"
  local prompt_file="$2"
  local out_path="$3"
  local findings_header="$4"
  local body_path="${out_path%.md}.body.md"
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
    echo "- Sandbox: $sandbox_note"
    echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
    echo
  } >"$out_path"

  # stdin is closed: a reviewer that blocks on stdin produces a header and no
  # findings, then reports success.
  local codex_exit=0
  codex exec \
    --sandbox "$sandbox_mode" \
    --config model_reasoning_effort=xhigh \
    -C "$review_tree" \
    "Follow this reviewer prompt:

$prompt_text

The PRD path is $prd_rel.
The QA runbook path is $qa_rel.
The branch diff has been cached at $review_dir/branch-diff.txt.
Read changed files as needed for context.
Return findings in the exact format required by the reviewer prompt.

IF YOU HAVE NO FINDINGS: output the '$findings_header' header followed by a
line containing exactly:

NO FINDINGS

Never return an empty document. Never stop to ask a question — you are running
non-interactively with no stdin." \
    <"/dev/null" \
    >"$body_path" \
    2>"$stderr_log" \
    || codex_exit=$?

  if [[ "$codex_exit" -ne 0 ]]; then
    echo "Error: codex exec failed for $label with exit code $codex_exit. See $stderr_log" >&2
    {
      echo "$findings_header"
      echo
      echo "_Codex CLI exited with code $codex_exit. No findings produced._"
      echo "_This reviewer produced NO opinion this round. Do not treat it as a clean result._"
    } >>"$out_path"
    return 1
  fi

  # Post-run validation: FAIL-CLOSED. An empty or trivial review body means
  # the review failed — surface it as a failed review, not a warning.
  local verdict reason
  read -r verdict reason <<<"$(validate_body "$body_path" "$findings_header")"
  if [[ "$verdict" != "valid" ]]; then
    echo "Error: $label produced no usable review (reason: $reason). Raw body: $body_path. Stderr: $stderr_log" >&2
    {
      echo "$findings_header"
      echo
      echo "_No usable review produced (reason: \`$reason\`)._"
      echo "_This reviewer produced NO opinion this round. Do not treat it as a clean result._"
    } >>"$out_path"
    return 1
  fi

  cat "$body_path" >>"$out_path"
}

run_review "Codex Quality Subagent Review" "$ref_dir/codex-quality-subagent-prompt.md" "$out_dir/codex-quality-subagent-review.md" "## Findings — Codex Quality" &
pid1=$!
run_review "Codex Security Subagent Review" "$ref_dir/codex-security-subagent-prompt.md" "$out_dir/codex-security-subagent-review.md" "## Findings — Codex Security" &
pid2=$!
run_review "Codex Spec Subagent Review" "$ref_dir/codex-spec-subagent-prompt.md" "$out_dir/codex-spec-subagent-review.md" "## Findings — Codex Spec" &
pid3=$!

status=0
for pid in "$pid1" "$pid2" "$pid3"; do
  if ! wait "$pid"; then
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  echo "One or more Codex subagent reviews failed or produced no usable review. See $out_dir/*.stderr.log" >&2
  exit "$status"
fi

echo "Codex subagent-style reviews written to: $out_dir"
echo "Sandbox: $sandbox_note"
