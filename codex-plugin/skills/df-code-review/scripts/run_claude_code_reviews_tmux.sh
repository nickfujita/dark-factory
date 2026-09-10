#!/usr/bin/env bash
# -E matters: without errtrace bash does not inherit an ERR trap into shell
# functions, so a tmux failure inside tm() would exit straight past the
# transport guard below and leave the reviewers running with no prompt.
set -Eeuo pipefail

# Usage: run_claude_code_reviews_tmux.sh <prd-path> <selection-ref> <repo-root> <base-ref> <output-dir>
# Starts two interactive Claude Code sessions in tmux (quality + spec), sends
# review prompts, and waits until each writes a completion sentinel.
#
# Output validation is FAIL-CLOSED (ported from df-prd-challenge): a sentinel
# over an empty, unstructured, or findings-free report is a FAILURE, not a
# clean round. Environment override: CLAUDE_REVIEW_MIN_BODY_BYTES=400 (minimum
# accepted report size when findings are claimed).
#
# Both reviewers run on this run's OWN tmux server, addressed by `-L <label>` on
# every call (CLAUDE_REVIEW_TMUX_LABEL overrides it). Not the operator's. From
# inside a pane $TMUX is set, tmux takes its socket path from it, and a plain
# `tmux new-session` lands the reviewers on the operator's live server as
# siblings of their working session, sharing one buffer namespace with every
# other concurrent run. TMUX_TMPDIR cannot substitute: it only feeds the default
# socket path, which is skipped whenever $TMUX supplies one.

if [[ $# -ne 5 ]]; then
  echo "Usage: run_claude_code_reviews_tmux.sh <prd-path> <selection-ref> <repo-root> <base-ref> <output-dir>" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: tmux is not installed or not in PATH." >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude CLI is not installed or not in PATH." >&2
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
selection_tool="$df_root/scripts/df-code-review-selection.mjs"

prd_path="$1"
selection_ref="$2"
repo_root="$3"
base_ref="$4"
out_dir="$5"

if [[ "$repo_root" != /* ]]; then repo_root="$(cd "$repo_root" && pwd -P)"; fi
if [[ "$out_dir" != /* ]]; then out_dir="$repo_root/$out_dir"; fi
selection_input="$out_dir/selection-input.json"
node "$selection_tool" prepare \
  --prd-path "$prd_path" \
  --selection-ref "$selection_ref" \
  --repo-root "$repo_root" \
  --output-path "$selection_input" >/dev/null
repo_root="$(git -C "$repo_root" rev-parse --show-toplevel)"
if [[ "$prd_path" != /* ]]; then prd_path="$repo_root/$prd_path"; fi
selection_details="$(node "$selection_tool" describe --input-path "$selection_input")"

if ! git -C "$repo_root" rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Error: base-ref '$base_ref' is not a valid git ref." >&2
  exit 1
fi
if git -C "$repo_root" diff --quiet "$base_ref" HEAD; then
  echo "Error: no diff found between HEAD and $base_ref" >&2
  exit 1
fi

mkdir -p "$out_dir"
quality_out="$out_dir/claude-quality-review.md"
spec_out="$out_dir/claude-spec-review.md"
quality_done="$out_dir/claude-quality-review.done"
spec_done="$out_dir/claude-spec-review.done"
rm -f "$quality_done" "$spec_done"
min_body_bytes="${CLAUDE_REVIEW_MIN_BODY_BYTES:-400}"

node "$selection_tool" verify \
  --prd-path "$prd_path" \
  --selection-ref "$selection_ref" \
  --repo-root "$repo_root" >/dev/null

# Claude Code has no read-only sandbox flag. Review in a disposable snapshot
# instead of the consumer checkout. A worktree gives a frozen HEAD; selected
# inputs are overlaid because their sealed bytes may include uncommitted edits.
snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/df-review-snapshot.XXXXXX")"
snapshot_kind=""
preserve_snapshot=0
cleanup_snapshot() {
  [[ -n "$snapshot_dir" ]] || return 0
  if [[ "$preserve_snapshot" -eq 1 ]]; then
    echo "Frozen reviewer snapshot retained for inspection: $snapshot_dir/tree" >&2
    return 0
  fi
  if [[ "$snapshot_kind" == "worktree" ]]; then
    git -C "$repo_root" worktree remove --force "$snapshot_dir/tree" >/dev/null 2>&1 || true
  fi
  rm -rf "$snapshot_dir"
  snapshot_dir=""
}
trap cleanup_snapshot EXIT

if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1 \
   && git -C "$repo_root" worktree add --detach "$snapshot_dir/tree" HEAD >/dev/null 2>&1; then
  snapshot_kind="worktree"
else
  snapshot_kind="copy"
  mkdir -p "$snapshot_dir/tree"
  cp -a "$repo_root/." "$snapshot_dir/tree/"
fi
while IFS= read -r input_rel; do
  mkdir -p "$snapshot_dir/tree/$(dirname "$input_rel")"
  cp -f "$repo_root/$input_rel" "$snapshot_dir/tree/$input_rel"
done < <(node "$selection_tool" paths --input-path "$selection_input")
review_tree="$snapshot_dir/tree"

# Verify after copying so a changed selected input cannot launch reviewers.
node "$selection_tool" verify \
  --prd-path "$prd_path" \
  --selection-ref "$selection_ref" \
  --repo-root "$repo_root" >/dev/null

# A review is accepted only if the report actually contains one (fail-closed,
# ported from df-prd-challenge's report grammar).
validate_report() {
  # validate_report <report> <expected-header> — echoes "<verdict> <reason>"
  local report="$1" header="$2" bytes=0 findings=0
  if [[ -f "$report" ]]; then bytes="$(wc -c <"$report" | tr -d ' ')"; fi
  if [[ "$bytes" -eq 0 ]]; then echo "invalid empty_report"; return 0; fi
  if ! grep -q "^$header" "$report"; then
    echo "invalid missing_findings_header"; return 0
  fi
  if ! node "$selection_tool" validate-report-header \
    --prd-path "$prd_path" \
    --selection-ref "$selection_ref" \
    --repo-root "$repo_root" \
    --report-path "$report" >/dev/null; then
    echo "invalid selection_header"; return 0
  fi
  # Tolerate case drift and the literal bracket form of the prompt's own
  # "### [SEVERITY]" template.
  findings="$(grep -ciE '^###[[:space:]]+(\*\*)?\[?(critical|high|medium|low)\b' "$report" || true)"
  if [[ "$findings" -eq 0 ]]; then
    if grep -qE '^[[:space:]]*(\*\*)?NO FINDINGS' "$report"; then
      echo "valid explicit_no_findings"; return 0
    fi
    echo "invalid no_structured_findings"; return 0
  fi
  if [[ "$bytes" -lt "$min_body_bytes" ]]; then
    echo "invalid body_below_min_bytes"; return 0
  fi
  echo "valid ok"
}

prd_rel="${prd_path#"$repo_root"/}"
session="${CLAUDE_REVIEW_TMUX_SESSION:-df-claude-code-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

# One tmux server per run, keyed on this script's pid so concurrent rounds
# cannot collide. Every tmux call goes through tm(); a bare `tmux` would fall
# back to the operator's server. The server exits once its last session is gone.
tmux_label="${CLAUDE_REVIEW_TMUX_LABEL:-df-claude-code-$$}"
tm() { tmux -L "$tmux_label" "$@"; }

startup_delay="${CLAUDE_REVIEW_STARTUP_DELAY:-3}"
timeout_seconds="${CLAUDE_REVIEW_TIMEOUT_SECONDS:-1800}"
claude_command="${CLAUDE_REVIEW_COMMAND:-claude}"

# Both reviewers are machine-driven sessions: their reports are addressed to
# this flow, not to a human. The Matrix phone bridge, if installed, cannot tell
# that apart from a session someone opened by hand, so it would give each
# reviewer its own room and read its replies aloud — three live rooms and three
# spoken replies for one round of work. The variable is the bridge's opt-out: no
# room, no push notification, no TTS, no phone-bridge context injected.
#
# It must travel *inside* the command string. Exporting it here is not enough:
# when a tmux server is already running — always, in this flow, since the
# orchestrator is itself in tmux — `new-session` seeds the child from the
# server's environment plus `update-environment`, not from this shell, so an
# exported variable is silently dropped. tmux runs the command string through
# `sh -c`, so the assignment survives on every tmux version.
suppress_bridge="CCMATRIX_SUPPRESS_SESSION=1"

make_prompt() {
  local role="$1"
  local out_file="$2"
  local done_file="$3"
  local prompt_file="$4"
  # The reviewers run in a snapshot, while the coordinator waits for reports
  # in the live output directory. Use absolute result paths so the snapshot
  # cwd does not redirect a report or sentinel into the disposable tree.
  local out_file_path="$out_file"
  local done_file_path="$done_file"

  if [[ "$role" == "quality" ]]; then
    cat >"$prompt_file" <<PROMPT
You are the secondary Claude Code quality reviewer for a Codex-driven Dark Factory code review.

Important execution rules:
- You are already running inside an interactive Claude Code session. Do not use claude -p, --print, SDK mode, or any non-interactive Claude invocation.
- Review only. Do not edit files.
- Write the final report to: $out_file_path
- Only after the report is complete, create this completion sentinel: $done_file_path
- Do not create the sentinel until the report is fully written.

Run: git diff $base_ref HEAD
Read changed files for context. Review only changed code.

Begin the report with this sealed selection header. Preserve every line:

## Sealed verification selection
$selection_details

Produce findings in this exact format:

## Findings — Claude Quality

### [SEVERITY] <One-line finding title>
**Category:** Correctness | Edge Case | Error Handling | Test Coverage | Performance | Clarity
**Location:** \`path/to/file.ts:line\`
**Issue:** 2-3 sentences explaining the problem.
**Recommendation:** Concrete fix.

---

Severity levels: Critical, High, Medium, Low.

IF YOU HAVE NO FINDINGS: write the '## Findings — Claude Quality' header followed by a line containing exactly:

NO FINDINGS

Never write an empty report.

After writing $out_file_path, run exactly:

mkdir -p "$(dirname "$done_file_path")" && printf 'done\n' > "$done_file_path"
PROMPT
  else
    cat >"$prompt_file" <<PROMPT
You are the secondary Claude Code spec compliance reviewer for a Codex-driven Dark Factory code review.

Important execution rules:
- You are already running inside an interactive Claude Code session. Do not use claude -p, --print, SDK mode, or any non-interactive Claude invocation.
- Review only. Do not edit files.
- Write the final report to: $out_file_path
- Only after the report is complete, create this completion sentinel: $done_file_path
- Do not create the sentinel until the report is fully written.

First read:
- PRD: $prd_rel

Then read every selected skillPath and recipePath. Do not substitute,
discover, merge, or omit an entry. A no-user-route selection has zero entries;
read its reason and review only the PRD-bound scope.

Begin the report with this sealed selection header. Preserve every line:

## Sealed verification selection
$selection_details

Then run: git diff $base_ref HEAD
Read changed files for context. Review the branch diff against the PRD and sealed selection.

Produce findings in this exact format:

## Findings — Claude Spec

### [SEVERITY] <One-line finding title>
**Requirement:** REQ-xxx | NEG-xxx | selected entry ID
**Location:** \`path/to/file.ts:line\` (or "Not implemented" if missing entirely)
**Issue:** 2-3 sentences explaining the gap between spec and implementation.
**Recommendation:** What the code should do to satisfy the requirement.

---

Severity levels: Critical, High, Medium, Low.

IF YOU HAVE NO FINDINGS: write the '## Findings — Claude Spec' header followed by a line containing exactly:

NO FINDINGS

Never write an empty report.

After writing $out_file_path, run exactly:

mkdir -p "$(dirname "$done_file_path")" && printf 'done\n' > "$done_file_path"
PROMPT
  fi
}

quality_prompt="$(mktemp "${TMPDIR:-/tmp}/dark-factory-claude-quality-prompt.XXXXXX")"
spec_prompt="$(mktemp "${TMPDIR:-/tmp}/dark-factory-claude-spec-prompt.XXXXXX")"
make_prompt quality "$quality_out" "$quality_done" "$quality_prompt"
make_prompt spec "$spec_out" "$spec_done" "$spec_prompt"

# Everything from the spawn to the last keystroke is the transport window. A
# tmux error in here leaves two reviewer sessions running with no prompt in
# them, and nothing would ever read or retire them. Disarmed once the wait loop
# starts, because the loop's own failure paths keep the session on purpose.
transport_failed() {
  local rc=$?
  trap - ERR
  echo "Error: the tmux transport failed before the reviewers received their prompts (exit $rc)." >&2
  tm kill-session -t "$session" 2>/dev/null || true
  exit 1
}
trap transport_failed ERR

# Both windows are named, never addressed by index: `base-index 1` in an
# operator's ~/.tmux.conf shifts the first window to 1 and a `:0` target dies
# with "can't find window: 0".
tm new-session -d -s "$session" -n quality -c "$review_tree" "$suppress_bridge exec $claude_command"
tm new-window -t "$session" -n spec -c "$review_tree" "$suppress_bridge exec $claude_command"
sleep "$startup_delay"

tm load-buffer -b dark-factory-claude-quality "$quality_prompt"
tm paste-buffer -b dark-factory-claude-quality -t "$session:quality"
tm send-keys -t "$session:quality" Enter

tm load-buffer -b dark-factory-claude-spec "$spec_prompt"
tm paste-buffer -b dark-factory-claude-spec -t "$session:spec"
tm send-keys -t "$session:spec" Enter

trap - ERR

deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  if [[ -f "$quality_done" && -f "$spec_done" ]]; then
    # The sentinel is not evidence of a review. Fail closed on a structurally
    # empty or findings-free report rather than reading it as a clean round.
    read -r q_verdict q_reason <<<"$(validate_report "$quality_out" "## Findings — Claude Quality")"
    read -r s_verdict s_reason <<<"$(validate_report "$spec_out" "## Findings — Claude Spec")"
    if [[ "$q_verdict" != "valid" || "$s_verdict" != "valid" ]]; then
      echo "Error: completion sentinel exists but a report is not a usable review (quality: ${q_reason}, spec: ${s_reason})." >&2
      echo "Reviewer session kept for inspection: tmux -L $tmux_label attach -t $session" >&2
      preserve_snapshot=1
      exit 1
    fi
    # Both reports are on disk, so neither reviewer has anything left to say.
    # Killing the session also retires this run's server.
    if ! node "$selection_tool" verify \
      --prd-path "$prd_path" \
      --selection-ref "$selection_ref" \
      --repo-root "$repo_root" >/dev/null; then
      echo "Error: selected source changed during review. Coverage must reseal and this review must restart." >&2
      preserve_snapshot=1
      exit 1
    fi
    tm kill-session -t "$session" 2>/dev/null || true
    echo "Claude code reviews written to: $out_dir"
    exit 0
  fi
  if ! tm has-session -t "$session" 2>/dev/null; then
    echo "Error: tmux session ended before both completion sentinels were written: $session" >&2
    exit 1
  fi
  sleep 5
done

echo "Error: timed out waiting for Claude completion sentinels in: $out_dir" >&2
echo "Reviewer session kept for inspection: tmux -L $tmux_label attach -t $session" >&2
preserve_snapshot=1
exit 1
