#!/usr/bin/env bash
set -uo pipefail

# test_prd_review_runners.sh — smoke tests for the df-prd-challenge review runners.
#
# Exercises the three runners against FAKE `codex`, `tmux` and `claude` binaries:
# every terminal state, the acceptance grammar (discovery and verification),
# limit detection and its false-positive channel, the verification-mode wiring,
# the no-clobber guards and the window timeout. No network, no real model calls.
#
# Usage: bash scripts/test_prd_review_runners.sh [-v]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_RUNNER="$REPO_ROOT/skills/df-prd-challenge/scripts/run_codex_prd_review.sh"
PERSONA_RUNNER="$REPO_ROOT/codex-plugin/skills/df-prd-challenge/scripts/run_codex_persona_reviews.sh"
TMUX_RUNNER="$REPO_ROOT/codex-plugin/skills/df-prd-challenge/scripts/run_claude_prd_review_tmux.sh"

VERBOSE=0
[[ "${1:-}" == "-v" ]] && VERBOSE=1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/df-runner-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '     %s\n' "$2"
}

expect_kv() {
  # expect_kv <label> <status-file> <KEY> <expected>
  local label="$1" file="$2" key="$3" want="$4" got
  got="$(sed -n "s/^$key=//p" "$file" 2>/dev/null | tail -1)"
  if [[ "$got" == "$want" ]]; then
    pass "$label ($key=$want)"
  else
    fail "$label" "$key: want '$want', got '$got' (file: $file)"
    [[ "$VERBOSE" -eq 1 ]] && cat "$file" >&2
  fi
}

# ------------------------------------------------------------------ fake codex
#
# Behaviour is selected per-invocation by FAKE_SCENARIO. The persona runner is
# handled by matching the persona name inside the prompt argument.

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/codex" <<'FAKE'
#!/usr/bin/env bash
# fake codex: writes a review to stdout per FAKE_SCENARIO
prompt=""
for arg in "$@"; do prompt="$arg"; done   # prompt is the last positional

scenario="${FAKE_SCENARIO:-valid_findings}"

# per-persona overrides, used by the partial-round tests
if [[ -n "${FAKE_FAIL_PERSONA:-}" && "$prompt" == *"$FAKE_FAIL_PERSONA"* ]]; then
  scenario="empty"
fi
if [[ -n "${FAKE_SLEEP_PERSONA:-}" && "$prompt" == *"$FAKE_SLEEP_PERSONA"* ]]; then
  scenario="sleep"
fi

# record whether the delta actually reached the prompt
if [[ -n "${FAKE_DELTA_MARKER:-}" && "$prompt" == *"REMEDIATION DELTA"* ]]; then
  printf 'seen\n' >>"$FAKE_DELTA_MARKER"
fi

padding="Lorem ipsum requirement text repeated so the body clears the minimum accepted size for a review body. It is deliberately verbose, describing the requirement, its acceptance criteria, and the risk of leaving the threshold unbounded across the document."

case "$scenario" in
  valid_findings)
    printf '## Findings — Codex\n\n### Critical: Unbounded payload size\n**Class:** SUBSTANTIVE\n**Requirement:** REQ-001\n**Issue:** %s\n**Suggestion:** Pin a maximum.\n' "$padding"
    ;;
  no_findings)
    printf '## Findings — Codex\n\nNO FINDINGS\n'
    ;;
  empty)
    : ;;
  header_only)
    printf '## Findings — Codex\n\nEverything looks fine to me.\n'
    ;;
  case_bracket)
    printf '## Findings — Codex\n\n### [CRITICAL]: Unbounded payload size\n**Class:** SUBSTANTIVE\n**Requirement:** REQ-001\n**Issue:** %s\n**Suggestion:** Pin a maximum, and state it once in the Pinned Parameters table.\n' "$padding"
    ;;
  verdicts_only)
    printf '#### F1: Unbounded payload size\n**Verdict:** CONFIRMED\n**Evidence:** REQ-001 now pins MAX_PAYLOAD.\n\n#### F2: Missing error state\n**Verdict:** CONFIRMED\n**Evidence:** Edge case table row 4.\n\nNo regressions found.\n'
    ;;
  verification_prose)
    printf 'Everything checks out, no problems at all.\n'
    ;;
  limit)
    echo "Error: you have reached your usage limit for this account" >&2
    exit 1
    ;;
  prose_429)
    printf '## Findings — Codex\n\n### Critical: Rate limiting undefined\n**Class:** SUBSTANTIVE\n**Issue:** %s\n' "$padding"
    echo "Error handling: the server replies 429 Too Many Requests and the client must back off" >&2
    exit 1
    ;;
  sleep)
    sleep 60
    ;;
esac
exit 0
FAKE
chmod +x "$BIN/codex"

# ------------------------------------------------------------- fake tmux/claude
#
# The tmux runner only needs: a session that "starts", buffer plumbing that
# succeeds, and a sentinel appearing. The report content is staged by the test.

cat >"$BIN/tmux" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  new-session) [[ -n "${FAKE_SENTINEL:-}" ]] && printf 'done\n' >"$FAKE_SENTINEL"; exit 0 ;;
  has-session) exit 0 ;;
  -V) echo "tmux 3.4"; exit 0 ;;
  *) exit 0 ;;
esac
FAKE
chmod +x "$BIN/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/claude"
chmod +x "$BIN/claude"

export PATH="$BIN:$PATH"
export CODEX_POLL_SECONDS=1
export CODEX_WAIT_SLICE_SECONDS=40
export CODEX_WINDOW_SECONDS=25
export CODEX_SKILLS_HOME="$REPO_ROOT/codex-plugin/skills"

PRD="$WORK/prd-sample.md"
cat >"$PRD" <<'PRDDOC'
# PRD: Sample

**Status:** Hardened

## Requirements
REQ-001: The service accepts a payload.
PRDDOC

DELTA="$WORK/delta.md"
cat >"$DELTA" <<'DELTADOC'
## Remediated findings
- F1 (Critical, SUBSTANTIVE): Unbounded payload size — applied as proposed, REQ-001 now pins MAX_PAYLOAD.
- F2 (High, SUBSTANTIVE): Missing error state — applied, modified.
DELTADOC

run_codex_round() {
  # run_codex_round <name> <scenario> [env assignments...]
  local name="$1" scenario="$2"; shift 2
  local out="$WORK/$name.md"
  env FAKE_SCENARIO="$scenario" "$@" bash "$CODEX_RUNNER" start "$PRD" "$out" >/dev/null 2>&1
  env FAKE_SCENARIO="$scenario" "$@" bash "$CODEX_RUNNER" wait "$out" >/dev/null 2>&1
  echo "${out%.md}.status"
}

echo "== run_codex_prd_review.sh =="

st="$(run_codex_round discovery-clean valid_findings)"
expect_kv "discovery: a real review completes" "$st" STATE complete
expect_kv "discovery: mode is recorded" "$st" MODE discovery

st="$(run_codex_round discovery-nofindings no_findings)"
expect_kv "discovery: explicit NO FINDINGS is a clean round" "$st" STATE complete

st="$(run_codex_round discovery-empty empty)"
expect_kv "discovery: empty body fails closed" "$st" STATE failed
expect_kv "discovery: empty body reason" "$st" REASON empty_body

st="$(run_codex_round discovery-header header_only)"
expect_kv "discovery: header without findings fails closed" "$st" STATE failed
expect_kv "discovery: header-only reason" "$st" REASON no_structured_findings

st="$(run_codex_round discovery-casebracket case_bracket)"
expect_kv "discovery: '### [CRITICAL]:' is accepted (case + bracket drift)" "$st" STATE complete

st="$(run_codex_round limit-real limit)"
expect_kv "limit: anchored error envelope declares a limit" "$st" STATE limit
expect_kv "limit: reason" "$st" REASON usage_limit

st="$(run_codex_round limit-prose prose_429)"
expect_kv "limit: 'Error handling: ... 429' prose does NOT declare a limit" "$st" STATE failed

# --- verification mode
DELTA_MARKER="$WORK/delta-seen"
st="$(run_codex_round verify-clean verdicts_only \
      CODEX_REVIEW_MODE=verification CODEX_REVIEW_DELTA_FILE="$DELTA" \
      FAKE_DELTA_MARKER="$DELTA_MARKER")"
expect_kv "verification: all-CONFIRMED body with no findings header is accepted" "$st" STATE complete
expect_kv "verification: mode is recorded" "$st" MODE verification
if [[ -s "$DELTA_MARKER" ]]; then
  pass "verification: the delta reached the reviewer prompt"
else
  fail "verification: the delta reached the reviewer prompt" "marker file empty"
fi

st="$(run_codex_round verify-prose verification_prose \
      CODEX_REVIEW_MODE=verification CODEX_REVIEW_DELTA_FILE="$DELTA")"
expect_kv "verification: prose with no verdict blocks fails closed" "$st" STATE failed
expect_kv "verification: no-verdict reason" "$st" REASON no_verdict_blocks

out="$WORK/verify-nodelta.md"
if CODEX_REVIEW_MODE=verification bash "$CODEX_RUNNER" start "$PRD" "$out" >/dev/null 2>&1; then
  fail "verification: start without a delta file is refused" "start exited 0"
else
  pass "verification: start without a delta file is refused"
fi

# --- guards and window
out="$WORK/guard.md"
env FAKE_SCENARIO=sleep bash "$CODEX_RUNNER" start "$PRD" "$out" >/dev/null 2>&1
sleep 1
if bash "$CODEX_RUNNER" start "$PRD" "$out" >/dev/null 2>&1; then
  fail "guard: a second start over a RUNNING round is refused" "start exited 0"
else
  pass "guard: a second start over a RUNNING round is refused"
fi

out="$WORK/window.md"
env FAKE_SCENARIO=sleep CODEX_WINDOW_SECONDS=3 bash "$CODEX_RUNNER" start "$PRD" "$out" >/dev/null 2>&1
env FAKE_SCENARIO=sleep CODEX_WINDOW_SECONDS=3 bash "$CODEX_RUNNER" wait "$out" >/dev/null 2>&1
expect_kv "window: an over-running round times out" "${out%.md}.status" STATE timeout

pkill -f "$WORK/bin/codex" 2>/dev/null || true

echo
echo "== run_codex_persona_reviews.sh =="

run_persona_round() {
  local name="$1" scenario="$2"; shift 2
  local dir="$WORK/$name"
  env FAKE_SCENARIO="$scenario" "$@" bash "$PERSONA_RUNNER" start "$PRD" "$dir" >/dev/null 2>&1
  env FAKE_SCENARIO="$scenario" "$@" bash "$PERSONA_RUNNER" wait "$dir" >/dev/null 2>&1
  echo "$dir/run.status"
}

st="$(run_persona_round personas-clean valid_findings)"
expect_kv "personas: three reviews complete the round" "$st" STATE complete
expect_kv "personas: all three reported" "$st" PERSONAS_OK 3/3

st="$(run_persona_round personas-partial valid_findings FAKE_FAIL_PERSONA='named "Persona 3')"
expect_kv "personas: one silent reviewer makes the round partial" "$st" STATE partial
expect_kv "personas: partial count" "$st" PERSONAS_OK 2/3

st="$(run_persona_round personas-hung valid_findings FAKE_SLEEP_PERSONA='named "Persona 3' CODEX_WINDOW_SECONDS=5)"
expect_kv "personas: a reviewer that outruns the window leaves a partial round" "$st" STATE partial
expect_kv "personas: completed reviews are still counted" "$st" PERSONAS_OK 2/3

PDELTA_MARKER="$WORK/persona-delta-seen"
st="$(run_persona_round personas-verify verdicts_only \
      CODEX_REVIEW_MODE=verification CODEX_REVIEW_DELTA_FILE="$DELTA" \
      FAKE_DELTA_MARKER="$PDELTA_MARKER")"
expect_kv "personas: verification round accepts verdict-only bodies" "$st" STATE complete
expect_kv "personas: verification mode is recorded" "$st" MODE verification
if [[ -s "$PDELTA_MARKER" ]]; then
  pass "personas: the delta reached the reviewer prompts"
else
  fail "personas: the delta reached the reviewer prompts" "marker file empty"
fi

if CODEX_REVIEW_MODE=verification bash "$PERSONA_RUNNER" start "$PRD" "$WORK/personas-nodelta" >/dev/null 2>&1; then
  fail "personas: start without a delta file is refused" "start exited 0"
else
  pass "personas: start without a delta file is refused"
fi

echo
echo "== run_claude_prd_review_tmux.sh =="

tmux_round() {
  # tmux_round <name> <report-body-file> [env...]
  local name="$1" body="$2"; shift 2
  local out="$WORK/$name.md"
  cp "$body" "$out"
  env FAKE_SENTINEL="${out%.md}.done" \
      CLAUDE_REVIEW_STARTUP_DELAY=0 CLAUDE_REVIEW_TIMEOUT_SECONDS=20 "$@" \
      bash "$TMUX_RUNNER" "$PRD" "$out" >/dev/null 2>&1
  echo "${out%.md}.status"
}

cat >"$WORK/report-findings.md" <<'REPORT'
## Findings — Claude

### High: Retry budget is unbounded
**Class:** SUBSTANTIVE
**Requirement:** REQ-001
**Issue:** The document never states how many times the client retries, so two
implementations can both satisfy the acceptance criteria and behave differently
under load. This is the kind of gap that only shows up in production.
**Suggestion:** Pin MAX_RETRIES in the Pinned Parameters table.
REPORT

cat >"$WORK/report-verdicts.md" <<'REPORT'
#### F1: Unbounded payload size
**Verdict:** CONFIRMED
**Evidence:** REQ-001 now pins MAX_PAYLOAD.
REPORT

cat >"$WORK/report-prose.md" <<'REPORT'
Looks good to me, nothing to report.
REPORT

st="$(tmux_round tmux-discovery "$WORK/report-findings.md")"
expect_kv "tmux: a structured report completes the round" "$st" STATE complete
expect_kv "tmux: mode is recorded" "$st" MODE discovery

st="$(tmux_round tmux-prose "$WORK/report-prose.md")"
expect_kv "tmux: a sentinel over unstructured prose fails closed" "$st" STATE failed

st="$(tmux_round tmux-verify "$WORK/report-verdicts.md" \
      CLAUDE_REVIEW_MODE=verification CLAUDE_REVIEW_DELTA_FILE="$DELTA")"
expect_kv "tmux: verification accepts a verdict-only report" "$st" STATE complete
expect_kv "tmux: verification mode is recorded" "$st" MODE verification

if CLAUDE_REVIEW_MODE=verification bash "$TMUX_RUNNER" "$PRD" "$WORK/tmux-nodelta.md" >/dev/null 2>&1; then
  fail "tmux: start without a delta file is refused" "exited 0"
else
  pass "tmux: start without a delta file is refused"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
