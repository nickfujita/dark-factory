#!/usr/bin/env bash
set -euo pipefail

# Usage: run_claude_prd_review_tmux.sh <prd-path> <output-path>
# Starts an interactive Claude Code session in tmux, sends a PRD review prompt,
# and waits until Claude writes a completion sentinel after the report.
#
# The caller's contract is the status file written next to the report
# (<output-path> with .md replaced by .status):
#
#   STATE=complete|failed|timeout
#   FINDINGS=<n>
#   REASON=<short machine token>   (only when STATE != complete)
#
# A sentinel over an empty or structurally invalid report is a FAILURE, not a
# clean round: an empty review that reports success is worse than a crash,
# because the natural next step on a "clean" result is to approve.
#
# Exit codes: 0 complete, 3 failed, 4 timeout, 1 usage / precondition error.
#
# Environment overrides:
#   CLAUDE_REVIEW_TIMEOUT_SECONDS=1800   window for the review
#   CLAUDE_REVIEW_MIN_BODY_BYTES=400     minimum report size when findings are claimed

if [[ $# -lt 2 ]]; then
  echo "Usage: run_claude_prd_review_tmux.sh <prd-path> <output-path>" >&2
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
out_path="$2"

if [[ "$prd_path" != /* ]]; then prd_path="$repo_root/$prd_path"; fi
if [[ "$out_path" != /* ]]; then out_path="$repo_root/$out_path"; fi

if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$out_path")"
done_path="${out_path%.md}.done"
status_path="${out_path%.md}.status"
min_body_bytes="${CLAUDE_REVIEW_MIN_BODY_BYTES:-400}"
rm -f "$done_path" "$status_path"

write_status() {
  # write_status <state> <findings> [reason]
  local tmp="${status_path}.tmp.$$"
  {
    echo "STATE=$1"
    echo "FINDINGS=$2"
    if [[ -n "${3:-}" ]]; then echo "REASON=$3"; fi
    echo "UPDATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$tmp"
  mv -f "$tmp" "$status_path"
}

# A round is accepted only if the report actually contains a review.
validate_report() {
  # echoes "<findings> <verdict> <reason>"
  local report="$1"
  local bytes=0 findings=0
  if [[ -f "$report" ]]; then bytes="$(wc -c <"$report" | tr -d ' ')"; fi
  if [[ "$bytes" -eq 0 ]]; then echo "0 invalid empty_report"; return 0; fi
  if ! grep -q '^## Findings' "$report"; then
    echo "0 invalid missing_findings_header"; return 0
  fi
  findings="$(grep -cE '^###[[:space:]]+(\*\*)?(Critical|High|Medium|Low)' "$report" || true)"
  if [[ "$findings" -eq 0 ]]; then
    if grep -qE '^[[:space:]]*(\*\*)?NO FINDINGS' "$report"; then
      echo "0 valid explicit_no_findings"; return 0
    fi
    echo "0 invalid no_structured_findings"; return 0
  fi
  if [[ "$bytes" -lt "$min_body_bytes" ]]; then
    echo "$findings invalid body_below_min_bytes"; return 0
  fi
  echo "$findings valid ok"
}

prd_rel="${prd_path#"$repo_root"/}"
out_rel="${out_path#"$repo_root"/}"
done_rel="${done_path#"$repo_root"/}"
session="${CLAUDE_REVIEW_TMUX_SESSION:-df-claude-prd-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
startup_delay="${CLAUDE_REVIEW_STARTUP_DELAY:-3}"
timeout_seconds="${CLAUDE_REVIEW_TIMEOUT_SECONDS:-1800}"
claude_command="${CLAUDE_REVIEW_COMMAND:-claude}"

prompt_file="$(mktemp "${TMPDIR:-/tmp}/dark-factory-claude-prd-prompt.XXXXXX")"
cat >"$prompt_file" <<PROMPT
You are the secondary Claude Code reviewer for a Codex-driven Dark Factory PRD challenge round.

Important execution rules:
- You are already running inside an interactive Claude Code session. Do not use claude -p, --print, SDK mode, or any non-interactive Claude invocation.
- Review only. Do not edit the PRD or source files.
- Write the final report to: $out_rel
- Only after the report is complete, create this completion sentinel: $done_rel
- Do not create the sentinel until the report is fully written.

First read the PRD at: $prd_rel
Explore the codebase for context to ground your analysis.

Produce findings in this exact format:

## Findings — Claude

### [SEVERITY]: [One-line finding title]
**Class:** SUBSTANTIVE | CONSISTENCY
**Requirement:** [Which REQ-xxx or section this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix or question to resolve it]

---

Severity levels:
- **Critical**: Blocks implementation or causes incorrect behavior
- **High**: Significant gap that will likely cause rework
- **Medium**: Improvement that would strengthen the PRD
- **Low**: Minor suggestion or style issue

Class is MANDATORY on every finding:
- **SUBSTANTIVE**: the PRD's intended behavior is wrong, missing, undecided, unbounded, or not testable. Fixing it changes what gets built.
- **CONSISTENCY**: the intended behavior is stated correctly in its normative home, but another location contradicts it, restates it stalely, renames it, or points at something that moved. Fixing it changes no intended behavior.
- If you cannot identify a normative home that is already correct, the finding is SUBSTANTIVE.

Focus on missing edge cases, contradictions, ambiguous requirements, untestable acceptance criteria, scope gaps, measurable non-functional requirements, unresolved decisions, non-deterministic behavior, and unbounded payloads.

IF YOU HAVE NO FINDINGS: write the '## Findings — Claude' header followed by a line containing exactly:

NO FINDINGS

Never write an empty report.

After writing $out_rel, run exactly:

mkdir -p "$(dirname "$done_rel")" && printf 'done\n' > "$done_rel"
PROMPT

tmux new-session -d -s "$session" -c "$repo_root" "$claude_command"
sleep "$startup_delay"
tmux load-buffer -b dark-factory-claude-prd "$prompt_file"
tmux paste-buffer -b dark-factory-claude-prd -t "$session:0"
tmux send-keys -t "$session:0" Enter

deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  if [[ -f "$done_path" ]]; then
    read -r findings verdict reason <<<"$(validate_report "$out_path")"
    if [[ "$verdict" != "valid" ]]; then
      # The sentinel is not evidence of a review. Do not let a structurally
      # empty report be read as a clean round.
      write_status "failed" "0" "$reason"
      echo "Error: completion sentinel exists but the report is not a usable review ($reason): $out_path" >&2
      echo "STATE=failed"
      echo "tmux session still available for inspection: $session" >&2
      exit 3
    fi
    write_status "complete" "$findings" "ok"
    echo "Claude PRD review written to: $out_path"
    echo "STATE=complete"
    echo "FINDINGS=$findings"
    echo "tmux session: $session"
    exit 0
  fi
  if ! tmux has-session -t "$session" 2>/dev/null; then
    write_status "failed" "0" "tmux_session_ended_before_sentinel"
    echo "Error: tmux session ended before completion sentinel was written: $session" >&2
    echo "STATE=failed"
    exit 3
  fi
  sleep 5
done

write_status "timeout" "0" "window_elapsed"
echo "Error: timed out waiting for Claude completion sentinel: $done_path" >&2
echo "STATE=timeout"
echo "tmux session still available for inspection: $session" >&2
exit 4
