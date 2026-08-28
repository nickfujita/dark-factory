#!/usr/bin/env bash
set -uo pipefail

# test_bridge_suppression.sh — the machine-spawned Claude reviewers must opt out
# of the Matrix phone bridge, and the opt-out must actually survive tmux.
#
# Two things can break independently, so both are checked:
#
#   1. Wiring — every `new-session`/`new-window` in the reviewer runners that
#      starts Claude carries the assignment.
#   2. Delivery — the assignment really lands in the spawned process's
#      environment. This is the part that looks obviously fine and is not:
#      exporting the variable before calling tmux does nothing once a tmux
#      server is already running, because `new-session` seeds the child from the
#      *server's* environment plus `update-environment`, not from the caller's
#      shell. Measured on tmux 3.4 with a server already up:
#
#        export CCMATRIX_SUPPRESS_SESSION=1; tmux new-session …   -> UNSET
#        tmux new-session … "CCMATRIX_SUPPRESS_SESSION=1 exec …"  -> 1
#
# Usage: bash scripts/test_bridge_suppression.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRD_RUNNER="$REPO_ROOT/codex-plugin/skills/df-prd-challenge/scripts/run_claude_prd_review_tmux.sh"
CODE_RUNNER="$REPO_ROOT/codex-plugin/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh"
VAR="CCMATRIX_SUPPRESS_SESSION"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '     %s\n' "$2"
}

# ------------------------------------------------------------------- 1. wiring

check_wiring() {
  # check_wiring <label> <script>
  local label="$1" script="$2" line spawns=0 bare=0
  # `tm` is the runners' wrapper that pins every tmux call to the run's own
  # server, so spawns read as `tm new-session`; match both spellings.
  while IFS= read -r line; do
    # Only spawns that launch the reviewer command are in scope; tmux calls that
    # paste buffers or poll the session are not.
    [[ "$line" != *'$claude_command'* ]] && continue
    spawns=$((spawns + 1))
    [[ "$line" != *'$suppress_bridge'* ]] && bare=$((bare + 1))
  done < <(grep -E '\b(tmux|tm) (new-session|new-window)' "$script")

  if [[ "$spawns" -eq 0 ]]; then
    fail "$label: found a reviewer spawn to check" "no 'new-session/new-window' running \$claude_command"
    return
  fi
  if [[ "$bare" -ne 0 ]]; then
    fail "$label: every reviewer spawn suppresses the bridge" "$bare of $spawns spawn(s) missing \$suppress_bridge"
    return
  fi
  pass "$label: all $spawns reviewer spawn(s) suppress the bridge"

  if grep -q "^suppress_bridge=\"$VAR=1\"$" "$script"; then
    pass "$label: suppression variable is $VAR=1"
  else
    fail "$label: suppression variable is $VAR=1" "suppress_bridge assignment not found or renamed"
  fi
}

check_wiring "df-prd-challenge PRD reviewer" "$PRD_RUNNER"
check_wiring "df-code-review code reviewers" "$CODE_RUNNER"

# ----------------------------------------------------------------- 2. delivery

if ! command -v tmux >/dev/null 2>&1; then
  printf 'skip tmux delivery check (tmux not installed)\n'
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/df-suppression.XXXXXX")"
  # The probes run on their own tmux server, the way the runners do, so this
  # test never adds sessions to the operator's. `tm` is that pin; a bare `tmux`
  # would land on the operator's server because $TMUX names its socket.
  probe_label="df-suppression-$$"
  tm() { tmux -L "$probe_label" "$@"; }
  # Both probe sessions outlive their command by a couple of seconds, so clean
  # up every one of them however this script exits. Killing the last session
  # retires the probe server; nothing here calls kill-server.
  probe_sessions=()
  cleanup() {
    rm -rf "$WORK"
    local s
    for s in ${probe_sessions[@]+"${probe_sessions[@]}"}; do
      tm kill-session -t "$s" 2>/dev/null
    done
    # A server that exits on its own unlinks its socket; one killed with its
    # last session can leave the file behind.
    tm list-sessions >/dev/null 2>&1 \
      || rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$probe_label"
  }
  trap cleanup EXIT

  probe_session="df-suppression-probe-$$"
  probe_sessions+=("$probe_session")

  # Stands in for `claude`: records whether it inherited the opt-out.
  cat >"$WORK/fake-claude" <<'PROBE'
#!/usr/bin/env bash
printf '%s\n' "${CCMATRIX_SUPPRESS_SESSION:-UNSET}" > "$1"
sleep 2
PROBE
  chmod +x "$WORK/fake-claude"

  # Reproduce the runner's spawn line exactly, with the reviewer command
  # swapped for the probe — same quoting, same `sh -c`, same tmux server.
  claude_command="$WORK/fake-claude $WORK/probe.txt"
  suppress_bridge="$VAR=1"
  tm new-session -d -s "$probe_session" -c "$WORK" "$suppress_bridge exec $claude_command"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$WORK/probe.txt" ]] && break
    sleep 0.5
  done

  got="$(cat "$WORK/probe.txt" 2>/dev/null || echo MISSING)"
  if [[ "$got" == "1" ]]; then
    pass "tmux delivers $VAR=1 into the spawned process"
  else
    fail "tmux delivers $VAR=1 into the spawned process" "child saw '$got'"
  fi

  # The negative control: the mistake this guards against. If this ever starts
  # passing, tmux inherits the caller's environment on this machine and the
  # comment in the runners is stale — but the runners stay correct either way.
  rm -f "$WORK/probe.txt"
  probe_session="df-suppression-control-$$"
  probe_sessions+=("$probe_session")
  CCMATRIX_SUPPRESS_SESSION=1 tm new-session -d -s "$probe_session" -c "$WORK" "exec $claude_command"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$WORK/probe.txt" ]] && break
    sleep 0.5
  done
  got="$(cat "$WORK/probe.txt" 2>/dev/null || echo MISSING)"
  if [[ "$got" == "1" ]]; then
    printf 'note this tmux passed the caller environment through (child saw "1");\n'
    printf '     the inline assignment is still required on servers that do not.\n'
  else
    pass "control: an exported variable alone does not reach the pane (saw '$got')"
  fi
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
