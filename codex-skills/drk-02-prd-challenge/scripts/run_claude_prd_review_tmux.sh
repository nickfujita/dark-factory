#!/usr/bin/env bash
set -euo pipefail

# Usage: run_claude_prd_review_tmux.sh <prd-path> <output-path>
# Starts an interactive Claude Code session in tmux, sends a PRD review prompt,
# and waits until Claude writes a completion sentinel after the report.

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
rm -f "$done_path"

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
**Requirement:** [Which REQ-xxx or section this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix or question to resolve it]

---

Severity levels:
- **Critical**: Blocks implementation or causes incorrect behavior
- **High**: Significant gap that will likely cause rework
- **Medium**: Improvement that would strengthen the PRD
- **Low**: Minor suggestion or style issue

Focus on missing edge cases, contradictions, ambiguous requirements, untestable acceptance criteria, scope gaps, and measurable non-functional requirements.

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
    if [[ ! -s "$out_path" ]]; then
      echo "Error: completion sentinel exists but report is empty: $out_path" >&2
      exit 1
    fi
    echo "Claude PRD review written to: $out_path"
    echo "tmux session: $session"
    exit 0
  fi
  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "Error: tmux session ended before completion sentinel was written: $session" >&2
    exit 1
  fi
  sleep 5
done

echo "Error: timed out waiting for Claude completion sentinel: $done_path" >&2
echo "tmux session still available for inspection: $session" >&2
exit 1
