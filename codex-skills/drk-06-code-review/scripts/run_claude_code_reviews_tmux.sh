#!/usr/bin/env bash
set -euo pipefail

# Usage: run_claude_code_reviews_tmux.sh <prd-path> <qa-path> <base-ref> <output-dir>
# Starts two interactive Claude Code sessions in tmux (quality + spec), sends
# review prompts, and waits until each writes a completion sentinel.

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

prd_rel="${prd_path#"$repo_root"/}"
qa_rel="${qa_path#"$repo_root"/}"
out_rel="${out_dir#"$repo_root"/}"
session="${CLAUDE_REVIEW_TMUX_SESSION:-df-claude-code-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
startup_delay="${CLAUDE_REVIEW_STARTUP_DELAY:-3}"
timeout_seconds="${CLAUDE_REVIEW_TIMEOUT_SECONDS:-1800}"
claude_command="${CLAUDE_REVIEW_COMMAND:-claude}"

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

After writing $out_file_rel, run exactly:

mkdir -p "$(dirname "$done_file_rel")" && printf 'done\n' > "$done_file_rel"
PROMPT
  fi
}

quality_prompt="$(mktemp "${TMPDIR:-/tmp}/dark-factory-claude-quality-prompt.XXXXXX")"
spec_prompt="$(mktemp "${TMPDIR:-/tmp}/dark-factory-claude-spec-prompt.XXXXXX")"
make_prompt quality "$quality_out" "$quality_done" "$quality_prompt"
make_prompt spec "$spec_out" "$spec_done" "$spec_prompt"

tmux new-session -d -s "$session" -n quality -c "$repo_root" "$claude_command"
tmux new-window -t "$session" -n spec -c "$repo_root" "$claude_command"
sleep "$startup_delay"

tmux load-buffer -b dark-factory-claude-quality "$quality_prompt"
tmux paste-buffer -b dark-factory-claude-quality -t "$session:quality"
tmux send-keys -t "$session:quality" Enter

tmux load-buffer -b dark-factory-claude-spec "$spec_prompt"
tmux paste-buffer -b dark-factory-claude-spec -t "$session:spec"
tmux send-keys -t "$session:spec" Enter

deadline=$((SECONDS + timeout_seconds))
while (( SECONDS < deadline )); do
  if [[ -f "$quality_done" && -f "$spec_done" ]]; then
    if [[ ! -s "$quality_out" || ! -s "$spec_out" ]]; then
      echo "Error: completion sentinel exists but one or more reports are empty." >&2
      exit 1
    fi
    echo "Claude code reviews written to: $out_dir"
    echo "tmux session: $session"
    exit 0
  fi
  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "Error: tmux session ended before both completion sentinels were written: $session" >&2
    exit 1
  fi
  sleep 5
done

echo "Error: timed out waiting for Claude completion sentinels in: $out_dir" >&2
echo "tmux session still available for inspection: $session" >&2
exit 1
