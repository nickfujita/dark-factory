#!/usr/bin/env bash
# D23 acceptance test for the df router skill.
#
# Proves, in clean headless sessions, that ordinary prompts cannot activate
# the df skill while explicit /df invocation can. Three cases:
#   1. bug-shaped prompt without /df  -> df must NOT engage
#   2. casual prompt                  -> df must NOT engage
#   3. explicit /df invocation        -> df MUST engage
#
# Mechanics, verified against claude CLI 2.1.247:
#   - The skill is installed as a project-level skill in a throwaway
#     directory, so the operator's global ~/.claude is never touched.
#   - --setting-sources project keeps the operator's global skills and
#     CLAUDE.md out of the session. Built-in skills still load.
#   - --output-format stream-json emits every assistant message and tool
#     call. The initial user message (where /df expands) is not emitted,
#     so engagement is detected behaviorally: a tool call touching the
#     skill's own files, or the router's lane-proposal language.
#   - --permission-mode dontAsk denies tool permission prompts instead of
#     hanging, which keeps runs short. Denied calls still appear in the
#     stream, so detection is unaffected.
#
# Env overrides: DF_TEST_DIR, DF_TEST_MODEL, DF_TEST_BUDGET_USD.
# Exit status: 0 when all cases pass, 1 otherwise.

set -u

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK_DIR=${DF_TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/df-invocation-test.XXXXXX")}
MODEL=${DF_TEST_MODEL:-haiku}
BUDGET=${DF_TEST_BUDGET_USD:-0.30}
RUN_TIMEOUT=300
FAILURES=0

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

setup_project() {
  mkdir -p "$WORK_DIR/.claude/skills"
  rm -rf "$WORK_DIR/.claude/skills/df"
  cp -r "$REPO_DIR/skills/df" "$WORK_DIR/.claude/skills/df"
  # A trivial target file so bug-shaped prompts have something real to chew on.
  cat > "$WORK_DIR/bug.sh" <<'EOF'
#!/bin/sh
# Prints the number of lines in the given file.
# Bug: seeds the counter at 1, so the count is off by one.
count=1
while IFS= read -r _line; do
  count=$((count + 1))
done < "$1"
echo "$count"
EOF
  chmod +x "$WORK_DIR/bug.sh"
}

# Run one headless session. $1 = case id, $2 = prompt.
# Transcript lands in $WORK_DIR/$1.jsonl.
run_case() {
  ( cd "$WORK_DIR" && timeout "$RUN_TIMEOUT" claude -p "$2" \
      --output-format stream-json --verbose \
      --model "$MODEL" \
      --max-budget-usd "$BUDGET" \
      --no-session-persistence \
      --setting-sources project \
      --permission-mode dontAsk \
      > "$1.jsonl" 2> "$1.err" )
}

# True when the transcript shows df in play: a Skill-tool call naming df,
# or any tool call whose input references the installed skill directory.
df_engaged() {
  jq -e '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use")
    | select(
        (.name == "Skill" and ((.input.skill? // "") == "df"))
        or ((.input | tostring) | contains(".claude/skills/df"))
      )
  ' "$WORK_DIR/$1.jsonl" >/dev/null 2>&1
}

# True when assistant text or thinking carries the router's lane proposal.
lane_proposed() {
  jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "text" or .type == "thinking")
    | (.text? // .thinking? // "")
  ' "$WORK_DIR/$1.jsonl" 2>/dev/null \
    | grep -q -E 'Quick lane|Standard lane|High-consequence|[Ll]ane: *(Quick|Standard|High)'
}

# Sanity check that the session produced a result event at all.
run_completed() {
  jq -e 'select(.type == "result")' "$WORK_DIR/$1.jsonl" >/dev/null 2>&1
}

verdict() {
  echo "[$1] $2 - $3"
  [ "$2" = "PASS" ] || FAILURES=$((FAILURES + 1))
}

setup_project
echo "scratch project: $WORK_DIR"
echo "model=$MODEL budget=\$$BUDGET per run"
echo

# Case 1: bug-shaped prompt, no /df. A one-line /df suggestion in the reply
# is fine; invoking the skill is not.
run_case case1 "There is a bug in bug.sh, it prints the wrong count. Fix it."
if ! run_completed case1; then
  verdict case1 FAIL "session did not complete (see case1.err)"
elif df_engaged case1; then
  verdict case1 FAIL "df skill engaged on a bug-shaped prompt without /df"
else
  verdict case1 PASS "no df invocation on a bug-shaped prompt"
fi

# Case 2: casual prompt. Nothing about it should touch df.
run_case case2 "thanks, that looks good"
if ! run_completed case2; then
  verdict case2 FAIL "session did not complete (see case2.err)"
elif df_engaged case2; then
  verdict case2 FAIL "df skill engaged on a casual prompt"
else
  verdict case2 PASS "no df invocation on a casual prompt"
fi

# Case 3: explicit /df. The CLI expands the slash command client-side; proof
# of engagement is the router acting out its contract (reading its own
# reference files, proposing a lane).
run_case case3 "/df there is a bug in bug.sh, it prints the wrong count"
if ! run_completed case3; then
  verdict case3 FAIL "session did not complete (see case3.err)"
elif df_engaged case3 || lane_proposed case3; then
  verdict case3 PASS "explicit /df engaged the router"
else
  verdict case3 FAIL "explicit /df did not engage the router"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "all cases passed"
else
  echo "$FAILURES case(s) failed; transcripts in $WORK_DIR"
fi
exit "$( [ "$FAILURES" -eq 0 ] && echo 0 || echo 1 )"
