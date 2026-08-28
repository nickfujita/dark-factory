#!/usr/bin/env bash
set -uo pipefail

# test_tmux_transport.sh — real-tmux transport test for the two Claude reviewer
# runners that Codex drives.
#
# Why this exists separately from test_prd_review_runners.sh: that suite stubs
# `tmux` with a script whose default branch is `exit 0`, so every mistake in a
# window target passes there, and it says nothing about which server the
# reviewer landed on. This one drives REAL tmux servers against throwaway repos,
# with a fake `claude` standing in for the reviewer, so the pane target, the
# buffer paste, the sentinel handshake, the server isolation and the teardown
# all get exercised for real.
#
# Cases:
#   1. base-index 1 — the operator config that broke the PRD transport in the
#      field. Before the window-name fix the runner died on
#      `can't find window: 0`.
#   2. base-index 0 — the tmux default, so the fix does not trade one config
#      for the other.
#   3. a transport error after the session is already up — the runner must
#      still honour its status-file contract and must not leave the reviewer
#      session running.
#   4. two rounds at once — separate servers, separate buffers, no crosstalk.
#   5. the code-review runner, which spawns two reviewers in one session.
#
# Isolation: each case drives the runner's own CLAUDE_REVIEW_TMUX_LABEL, so the
# production isolation path is what gets tested rather than a substitute.
# TMUX_TMPDIR is NOT usable for this. Inside a tmux pane $TMUX is set, tmux
# reads its socket path out of $TMUX, and TMUX_TMPDIR is ignored — so a runner
# "isolated" that way lands on the operator's live server. Nothing here ever
# calls kill-server; a private server exits on its own once its last session is
# killed by name.
#
# Usage: bash scripts/test_tmux_transport.sh [-v]

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRD_RUNNER="$REPO_ROOT/codex-plugin/skills/df-prd-challenge/scripts/run_claude_prd_review_tmux.sh"
CR_RUNNER="$REPO_ROOT/codex-plugin/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh"
TMUX_BIN="$(command -v tmux || true)"

VERBOSE=0
[[ "${1:-}" == "-v" ]] && VERBOSE=1

if [[ -z "$TMUX_BIN" ]]; then
  echo "SKIP: tmux is not installed; the transport test needs a real tmux." >&2
  exit 0
fi
for r in "$PRD_RUNNER" "$CR_RUNNER"; do
  [[ -x "$r" ]] || { echo "FAIL: runner not found or not executable: $r" >&2; exit 1; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/df-tmux-transport.XXXXXX")"

# Every case's label is derived from its name, so cleanup knows them all up
# front. Registering them from inside make_sandbox would not work: it is called
# in a command substitution, so an array it appends to dies with the subshell
# and the trap would tear down nothing.
CASES=(base-index-1 base-index-0 spawn-error conc-a conc-b code-review code-review-error)
label_for() { printf 'df-transport-%s-%s' "$$" "$1"; }

sessions_on() { "$TMUX_BIN" -L "$1" list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' '; }

cleanup() {
  local case_name label name
  for case_name in "${CASES[@]}"; do
    label="$(label_for "$case_name")"
    while read -r name; do
      [[ -n "$name" ]] && "$TMUX_BIN" -L "$label" kill-session -t "$name" 2>/dev/null
    done < <("$TMUX_BIN" -L "$label" list-sessions -F '#{session_name}' 2>/dev/null)
    # A private server unlinks its socket when it exits on its own, but one
    # killed with its last session can leave the file behind.
    "$TMUX_BIN" -L "$label" list-sessions >/dev/null 2>&1 \
      || rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$label"
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

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
    [[ "$VERBOSE" -eq 1 && -f "$file" ]] && cat "$file" >&2
  fi
}

expect_clean_server() {
  # expect_clean_server <label-text> <case-name>
  local text="$1" left
  left="$(sessions_on "$(label_for "$2")")"
  if [[ -z "${left// /}" ]]; then
    pass "$text: reviewer session torn down, private server retired"
  else
    fail "$text: reviewer session torn down" "still running: $left"
  fi
}

expect_operator_server_untouched() {
  # The whole point of the private label: a reviewer must never show up as a
  # sibling of the operator's own session.
  local text="$1" strays
  strays="$("$TMUX_BIN" list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^df-claude-' || true)"
  if [[ "$strays" == "0" ]]; then
    pass "$text: nothing landed on the operator's tmux server"
  else
    fail "$text: nothing landed on the operator's tmux server" "$strays df-claude-* session(s) there"
  fi
}

# ------------------------------------------------------------------ sandboxes
#
# Each case gets its own HOME (so its tmux server reads the base-index this case
# is testing), its own label, its own repo, and its own fake `claude`.

make_sandbox() {
  # make_sandbox <case-name> <base-index> [break-paste]
  local name="$1" base_index="$2" break_paste="${3:-no}"
  local dir="$WORK/$name"

  mkdir -p "$dir/home" "$dir/bin" "$dir/repo/docs"

  cat >"$dir/home/.tmux.conf" <<CONF
set -g base-index $base_index
setw -g pane-base-index $base_index
CONF

  # Reproduces the field failure: a transport error that lands after
  # new-session already succeeded. Otherwise the real tmux is used directly, so
  # the runner's own -L handling is what provides isolation.
  if [[ "$break_paste" == "yes" ]]; then
    {
      echo '#!/usr/bin/env bash'
      echo 'if [[ " $* " == *" paste-buffer "* ]]; then'
      echo "  echo \"can't find window: 0\" >&2"
      echo '  exit 1'
      echo 'fi'
      echo "exec $TMUX_BIN \"\$@\""
    } >"$dir/bin/tmux"
    chmod +x "$dir/bin/tmux"
  fi

  # Fake reviewer: reads the prompt the runner pastes into its pane and does
  # what it asks. If the paste never lands, no sentinel appears and the runner
  # times out, which is the point.
  cat >"$dir/bin/claude" <<'FAKE'
#!/usr/bin/env bash
set -u
buf="$(mktemp)"
# The paste arrives as one burst a few seconds after launch. Wait for the first
# line, then keep reading until the burst goes quiet.
if IFS= read -r -t 60 line; then printf '%s\n' "$line" >>"$buf"; fi
while IFS= read -r -t 3 line; do printf '%s\n' "$line" >>"$buf"; done

out="$(sed -n 's/^- Write the final report to: //p' "$buf" | head -1)"
sentinel="$(sed -n 's/.*create this completion sentinel: //p' "$buf" | head -1)"
# Each reviewer role has its own required report header; take it from the
# prompt rather than hardcoding one per runner.
header="$(grep -m1 '^## Findings' "$buf")"
if [[ -z "$out" || -z "$sentinel" || -z "$header" ]]; then
  printf 'fake claude: the prompt never reached this pane\n' >&2
  sleep 25
  exit 9
fi

mkdir -p "$(dirname "$out")"
{
  printf '%s\n\n' "$header"
  cat <<'REPORT'
### Critical: Payload size and retention are both unbounded
**Class:** SUBSTANTIVE
**Requirement:** REQ-001
**Issue:** The requirement says the service accepts a payload, without naming a
maximum size or a retention window. Two implementations can both satisfy it as
written and still disagree about when a stored payload expires and how large
one may be. A reviewer has no way to tell a correct build from an incorrect one.
**Suggestion:** Pin a maximum payload size and a retention window in REQ-001,
and state what the service returns when either bound is exceeded.
REPORT
} >"$out"
mkdir -p "$(dirname "$sentinel")" && printf 'done\n' > "$sentinel"
# Outlive the sentinel so the runner's poll reads the file before the session
# ends, the way a real reviewer session stays up after its last write.
sleep 25
FAKE
  chmod +x "$dir/bin/claude"

  git -C "$dir/repo" init -q
  git -C "$dir/repo" config user.email test@example.invalid
  git -C "$dir/repo" config user.name "transport test"
  cat >"$dir/repo/docs/prd-sample.md" <<'PRDDOC'
# PRD: Sample

**Status:** Hardened

## Requirements
REQ-001: The service accepts a payload.
PRDDOC
  cat >"$dir/repo/docs/qa-sample.md" <<'QADOC'
# QA: Sample

## Scenario 1
Send a payload and confirm the service stores it.
QADOC
  printf 'export const accept = (p) => p;\n' >"$dir/repo/service.js"
  git -C "$dir/repo" add -A >/dev/null
  git -C "$dir/repo" commit -qm "base"
  printf 'export const accept = (p) => ({ ...p, seen: true });\n' >"$dir/repo/service.js"
  git -C "$dir/repo" add -A >/dev/null
  git -C "$dir/repo" commit -qm "change under review"

  printf '%s' "$dir"
}

run_prd_case() {
  # run_prd_case <sandbox-dir> <case-name> <out-rel>; echoes the exit code
  local dir="$1" name="$2" out_rel="$3" rc=0
  (
    cd "$dir/repo" || exit 1
    unset TMUX TMUX_PANE
    PATH="$dir/bin:$PATH" \
    HOME="$dir/home" \
    XDG_CONFIG_HOME="$dir/home/.config" \
    CLAUDE_REVIEW_TMUX_LABEL="$(label_for "$name")" \
    CLAUDE_REVIEW_STARTUP_DELAY=2 \
    CLAUDE_REVIEW_TIMEOUT_SECONDS=90 \
      bash "$PRD_RUNNER" "docs/prd-sample.md" "$out_rel"
  ) >"$dir/stdout" 2>"$dir/stderr"
  rc=$?
  printf '%s' "$rc"
}

# ------------------------------------------------------- case 1: base-index 1
#
# The field failure. The operator's ~/.tmux.conf sets `base-index 1`, so a new
# session's first window is 1 and a runner targeting `<session>:0` cannot find
# it.

dir="$(make_sandbox base-index-1 1)"
rc="$(run_prd_case "$dir" base-index-1 "out/review.md")"
if [[ "$rc" == "0" ]]; then
  pass "base-index 1: runner completed (exit 0)"
else
  fail "base-index 1: runner completed" "exit $rc; stderr: $(tr '\n' ' ' <"$dir/stderr" | cut -c1-200)"
fi
expect_kv "base-index 1" "$dir/repo/out/review.status" STATE complete
expect_kv "base-index 1" "$dir/repo/out/review.status" FINDINGS 1
if grep -q '^## Findings' "$dir/repo/out/review.md" 2>/dev/null; then
  pass "base-index 1: the pasted prompt reached the reviewer and a report came back"
else
  fail "base-index 1: report written" "missing or malformed: $dir/repo/out/review.md"
fi
expect_clean_server "base-index 1" base-index-1
expect_operator_server_untouched "base-index 1"

# ------------------------------------------------------- case 2: base-index 0
#
# The tmux default. Guards against fixing case 1 by breaking the common config.

dir="$(make_sandbox base-index-0 0)"
rc="$(run_prd_case "$dir" base-index-0 "out/review.md")"
if [[ "$rc" == "0" ]]; then
  pass "base-index 0: runner completed (exit 0)"
else
  fail "base-index 0: runner completed" "exit $rc; stderr: $(tr '\n' ' ' <"$dir/stderr" | cut -c1-200)"
fi
expect_kv "base-index 0" "$dir/repo/out/review.status" STATE complete
expect_clean_server "base-index 0" base-index-0

# ------------------------------------------- case 3: transport error mid-spawn
#
# The reviewer session is already up when the transport fails. Two things must
# hold: the caller still gets the documented status file, and the reviewer
# session does not survive as an orphan holding a CLI nobody will ever read.

dir="$(make_sandbox spawn-error 1 yes)"
rc="$(run_prd_case "$dir" spawn-error "out/review.md")"
if [[ "$rc" != "0" ]]; then
  pass "transport error: runner failed loudly (exit $rc)"
else
  fail "transport error: runner failed loudly" "exit 0, which reads as a clean round"
fi
if [[ -f "$dir/repo/out/review.status" ]]; then
  pass "transport error: status file honoured the caller's contract"
  expect_kv "transport error" "$dir/repo/out/review.status" STATE failed
else
  fail "transport error: status file honoured the caller's contract" \
       "no status file at $dir/repo/out/review.status; the caller cannot tell a failure from a crash"
fi
expect_clean_server "transport error" spawn-error

# ------------------------------------------------- case 4: two rounds at once
#
# Concurrent rounds must not share a server or a paste buffer. The buffer names
# are fixed literals, so on one shared server the second round's load-buffer
# overwrites the first round's prompt before it is pasted.

dir_a="$(make_sandbox conc-a 1)"
dir_b="$(make_sandbox conc-b 0)"
run_prd_case "$dir_a" conc-a "out/review.md" >"$WORK/rc-a" &
pid_a=$!
run_prd_case "$dir_b" conc-b "out/review.md" >"$WORK/rc-b" &
pid_b=$!
wait "$pid_a"; wait "$pid_b"
rc_a="$(cat "$WORK/rc-a")"; rc_b="$(cat "$WORK/rc-b")"
if [[ "$rc_a" == "0" && "$rc_b" == "0" ]]; then
  pass "concurrent rounds: both completed (exit $rc_a / $rc_b)"
else
  fail "concurrent rounds: both completed" \
       "exit $rc_a / $rc_b; a: $(tr '\n' ' ' <"$dir_a/stderr" | cut -c1-120)"
fi
expect_kv "concurrent round a" "$dir_a/repo/out/review.status" STATE complete
expect_kv "concurrent round b" "$dir_b/repo/out/review.status" STATE complete
# Each reviewer must have been handed its OWN prompt. The prompts name their own
# repo-absolute output path, so a crossed buffer writes into the wrong sandbox.
if [[ -f "$dir_a/repo/out/review.md" && -f "$dir_b/repo/out/review.md" ]]; then
  pass "concurrent rounds: each reviewer wrote into its own sandbox, no crossed buffer"
else
  fail "concurrent rounds: each reviewer wrote into its own sandbox" \
       "a=$([[ -f "$dir_a/repo/out/review.md" ]] && echo present || echo MISSING), b=$([[ -f "$dir_b/repo/out/review.md" ]] && echo present || echo MISSING)"
fi
expect_clean_server "concurrent round a" conc-a
expect_clean_server "concurrent round b" conc-b

# --------------------------------------------- case 5: the code-review runner
#
# Same transport, two reviewers in one session. Its windows were already named,
# so this is a guard on the shared isolation and teardown, not a repro.

run_cr_case() {
  # run_cr_case <sandbox-dir> <case-name>; echoes the exit code
  local dir="$1" name="$2" rc=0
  (
    cd "$dir/repo" || exit 1
    unset TMUX TMUX_PANE
    PATH="$dir/bin:$PATH" \
    HOME="$dir/home" \
    XDG_CONFIG_HOME="$dir/home/.config" \
    CLAUDE_REVIEW_TMUX_LABEL="$(label_for "$name")" \
    CLAUDE_REVIEW_STARTUP_DELAY=2 \
    CLAUDE_REVIEW_TIMEOUT_SECONDS=90 \
      bash "$CR_RUNNER" "docs/prd-sample.md" "docs/qa-sample.md" "HEAD~1" "out/cr"
  ) >"$dir/stdout" 2>"$dir/stderr"
  rc=$?
  printf '%s' "$rc"
}

dir="$(make_sandbox code-review 1)"
rc="$(run_cr_case "$dir" code-review)"
if [[ "$rc" == "0" ]]; then
  pass "code review: runner completed (exit 0)"
else
  fail "code review: runner completed" "exit $rc; stderr: $(tr '\n' ' ' <"$dir/stderr" | cut -c1-200)"
fi
for role in quality spec; do
  if grep -q '^## Findings' "$dir/repo/out/cr/claude-$role-review.md" 2>/dev/null; then
    pass "code review: the $role reviewer got its own prompt and reported"
  else
    fail "code review: the $role reviewer reported" "missing: $dir/repo/out/cr/claude-$role-review.md"
  fi
done
expect_clean_server "code review" code-review
expect_operator_server_untouched "code review"

# A transport error there strands two reviewers, not one.
dir="$(make_sandbox code-review-error 1 yes)"
rc="$(run_cr_case "$dir" code-review-error)"
if [[ "$rc" != "0" ]]; then
  pass "code review transport error: runner failed loudly (exit $rc)"
else
  fail "code review transport error: runner failed loudly" "exit 0, which reads as a clean round"
fi
expect_clean_server "code review transport error" code-review-error

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
