#!/usr/bin/env bash
# -E matters: without errtrace bash does not inherit an ERR trap into shell
# functions, so a tmux failure inside tm() would exit straight past the
# transport guard below and leave the reviewers running with no prompt.
set -Eeuo pipefail

# Usage: run_claude_code_reviews_tmux.sh <prd-path> <qa-path> <base-ref> <output-dir>
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

if [[ $# -lt 4 ]]; then
  echo "Usage: run_claude_code_reviews_tmux.sh <prd-path> <qa-path> <base-ref> <output-dir>" >&2
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
prd_path="$1"
qa_path="$2"
base_ref="$3"
out_dir="$4"

if [[ "$prd_path" != /* ]]; then prd_path="$repo_root/$prd_path"; fi
if [[ "$qa_path" != /* ]]; then qa_path="$repo_root/$qa_path"; fi
if [[ "$out_dir" != /* ]]; then out_dir="$repo_root/$out_dir"; fi

if [[ ! -f "$prd_path" ]]; then echo "Error: PRD file not found at $prd_path" >&2; exit 1; fi
if [[ ! -f "$qa_path" ]]; then echo "Error: QA runbook not found at $qa_path" >&2; exit 1; fi
if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Error: base-ref '$base_ref' is not a valid git ref." >&2
  exit 1
fi
if git diff --quiet "$base_ref" HEAD; then
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
qa_rel="${qa_path#"$repo_root"/}"
out_rel="${out_dir#"$repo_root"/}"
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
  local out_file_rel="${out_file#"$repo_root"/}"
  local done_file_rel="${done_file#"$repo_root"/}"

  if [[ "$role" == "quality" ]]; then
    cat >"$prompt_file" <<PROMPT
You are the secondary Claude Code quality reviewer for a Codex-driven Dark Factory code review.

Important execution rules:
- You are already running inside an interactive Claude Code session. Do not use claude -p, --print, SDK mode, or any non-interactive Claude invocation.
- Review only. Do not edit files.
- Write the final report to: $out_file_rel
- Only after the report is complete, create this completion sentinel: $done_file_rel
- Do not create the sentinel until the report is fully written.

Run: git diff $base_ref HEAD
Read changed files for context. Review only changed code.

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

After writing $out_file_rel, run exactly:

mkdir -p "$(dirname "$done_file_rel")" && printf 'done\n' > "$done_file_rel"
PROMPT
  else
    cat >"$prompt_file" <<PROMPT
You are the secondary Claude Code spec compliance reviewer for a Codex-driven Dark Factory code review.

Important execution rules:
- You are already running inside an interactive Claude Code session. Do not use claude -p, --print, SDK mode, or any non-interactive Claude invocation.
- Review only. Do not edit files.
- Write the final report to: $out_file_rel
- Only after the report is complete, create this completion sentinel: $done_file_rel
- Do not create the sentinel until the report is fully written.

First read:
- PRD: $prd_rel
- QA runbook: $qa_rel

Then run: git diff $base_ref HEAD
Read changed files for context. Review the branch diff against the PRD and QA runbook.

Produce findings in this exact format:

## Findings — Claude Spec

### [SEVERITY] <One-line finding title>
**Requirement:** REQ-xxx | NEG-xxx | TC-xxx
**Location:** \`path/to/file.ts:line\` (or "Not implemented" if missing entirely)
**Issue:** 2-3 sentences explaining the gap between spec and implementation.
**Recommendation:** What the code should do to satisfy the requirement.

---

Severity levels: Critical, High, Medium, Low.

IF YOU HAVE NO FINDINGS: write the '## Findings — Claude Spec' header followed by a line containing exactly:

NO FINDINGS

Never write an empty report.

After writing $out_file_rel, run exactly:

mkdir -p "$(dirname "$done_file_rel")" && printf 'done\n' > "$done_file_rel"
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
tm new-session -d -s "$session" -n quality -c "$repo_root" "$suppress_bridge exec $claude_command"
tm new-window -t "$session" -n spec -c "$repo_root" "$suppress_bridge exec $claude_command"
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
      exit 1
    fi
    # Both reports are on disk, so neither reviewer has anything left to say.
    # Killing the session also retires this run's server.
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
exit 1
