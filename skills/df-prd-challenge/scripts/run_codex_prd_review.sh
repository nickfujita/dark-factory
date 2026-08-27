#!/usr/bin/env bash
set -euo pipefail

# run_codex_prd_review.sh — Codex CLI reviewer for the PRD challenge round.
#
# Usage:
#   run_codex_prd_review.sh start  <prd-path> <out-path>
#   run_codex_prd_review.sh status <out-path>
#   run_codex_prd_review.sh wait   <out-path> [max_wait_seconds]
#   run_codex_prd_review.sh <prd-path> <out-path>      # legacy: start + wait
#
# The review runs DETACHED with a wide window and is polled, because a hard
# foreground timeout kills healthy rounds mid-exploration on a large PRD.
#
# The contract with the caller is the STATUS FILE, not the exit code and never
# a substring match over the review body or the stderr log:
#
#   STATE=running|complete|failed|limit|timeout
#   MODE=discovery|verification            (the mode this round actually ran in)
#   EXIT=<codex exit code>
#   BODY_BYTES=<n>
#   FINDINGS=<n>
#   SANDBOX=<short machine token>           (the sandbox mode the round ran in)
#   REASON=<short machine token>            (only when STATE != complete)
#
# Sandbox policy (D26): prefer --sandbox read-only on the live tree. When the
# read-only sandbox is unavailable (bwrap network namespaces unsupported, e.g.
# unprivileged VMs), NEVER run full access on the live tree — the worker points
# codex at a disposable snapshot (temp git worktree, or cp -a copy for non-git
# trees) created for the round and deleted after, and the status file's
# SANDBOX token says the round ran degraded on a snapshot.
#
# Exit codes for `status` / `wait` / legacy mode:
#   0 complete (or still running, for `wait` that used its whole slice)
#   2 limit    3 failed    4 timeout    1 usage / precondition error
#
# Environment overrides (defaults mirror the skill's pinned parameters):
#   CODEX_WINDOW_SECONDS=3600      total detached window for one round
#   CODEX_WAIT_SLICE_SECONDS=480   default blocking time for one `wait` call
#   CODEX_POLL_SECONDS=20          poll interval inside a slice
#   CODEX_MIN_BODY_BYTES=400       minimum accepted body when findings are claimed
#   CODEX_REASONING_EFFORT=xhigh   codex model_reasoning_effort
#   CODEX_REVIEW_MODE=discovery|verification
#   CODEX_REVIEW_DELTA_FILE=<path> remediation delta, required for verification
#   CODEX_REVIEW_FORCE=1           allow overwriting a non-empty existing out-path

WINDOW_SECONDS="${CODEX_WINDOW_SECONDS:-3600}"
WAIT_SLICE_SECONDS="${CODEX_WAIT_SLICE_SECONDS:-480}"
POLL_SECONDS="${CODEX_POLL_SECONDS:-20}"
MIN_BODY_BYTES="${CODEX_MIN_BODY_BYTES:-400}"
REASONING_EFFORT="${CODEX_REASONING_EFFORT:-xhigh}"
REVIEW_MODE="${CODEX_REVIEW_MODE:-discovery}"
DELTA_FILE="${CODEX_REVIEW_DELTA_FILE:-}"

usage() {
  cat <<'USAGE'
Usage:
  run_codex_prd_review.sh start  <prd-path> <out-path>
  run_codex_prd_review.sh status <out-path>
  run_codex_prd_review.sh wait   <out-path> [max_wait_seconds]
  run_codex_prd_review.sh <prd-path> <out-path>      # legacy: start + wait

The caller's contract is the status file printed by `status` / `wait`:
  STATE=running|complete|failed|limit|timeout
Exit codes: 0 complete/running, 2 limit, 3 failed, 4 timeout, 1 usage error.
See the header comment in this script for environment overrides.
USAGE
}

# ---------------------------------------------------------------- path helpers

paths_for() {
  # sets: out_path body_path stderr_log status_file pid_file meta_file
  out_path="$1"
  if [[ "$out_path" != /* ]]; then
    out_path="$PWD/$out_path"
  fi
  local base="${out_path%.md}"
  body_path="${base}.body.md"
  stderr_log="${base}.stderr.log"
  status_file="${base}.status"
  pid_file="${base}.pid"
  meta_file="${base}.meta"
}

write_status() {
  # write_status <state> <exit> <body_bytes> <findings> [reason]
  local tmp="${status_file}.tmp.$$"
  {
    echo "STATE=$1"
    echo "MODE=$REVIEW_MODE"
    echo "EXIT=$2"
    echo "BODY_BYTES=$3"
    echo "FINDINGS=$4"
    if [[ -n "${SANDBOX_NOTE:-}" ]]; then echo "SANDBOX=$SANDBOX_NOTE"; fi
    if [[ -n "${5:-}" ]]; then echo "REASON=$5"; fi
    echo "UPDATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$tmp"
  mv -f "$tmp" "$status_file"
}

# ------------------------------------------------------- snapshot (D26 sandbox)

# Globals set by make_snapshot; cleaned by cleanup_snapshot (idempotent).
SNAPSHOT_DIR=""
SNAPSHOT_KIND=""
SNAPSHOT_REPO_ROOT=""

cleanup_snapshot() {
  [[ -n "$SNAPSHOT_DIR" ]] || return 0
  if [[ "$SNAPSHOT_KIND" == "worktree" && -n "$SNAPSHOT_REPO_ROOT" ]]; then
    git -C "$SNAPSHOT_REPO_ROOT" worktree remove --force "$SNAPSHOT_DIR/tree" \
      >/dev/null 2>&1 || true
  fi
  rm -rf "$SNAPSHOT_DIR"
  SNAPSHOT_DIR=""
}

make_snapshot() {
  # make_snapshot <repo_root> — sets SNAPSHOT_DIR/SNAPSHOT_KIND/SNAPSHOT_TREE.
  # Must NOT run in a command substitution (the globals would be lost).
  local repo_root="$1"
  SNAPSHOT_REPO_ROOT="$repo_root"
  SNAPSHOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/df-review-snapshot.XXXXXX")"
  if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1 \
     && git -C "$repo_root" worktree add --detach "$SNAPSHOT_DIR/tree" HEAD >/dev/null 2>&1; then
    SNAPSHOT_KIND="worktree"
  else
    SNAPSHOT_KIND="copy"
    mkdir -p "$SNAPSHOT_DIR/tree"
    cp -a "$repo_root/." "$SNAPSHOT_DIR/tree/"
  fi
  SNAPSHOT_TREE="$SNAPSHOT_DIR/tree"
}

read_state() {
  [[ -f "$status_file" ]] || { echo ""; return 0; }
  sed -n 's/^STATE=//p' "$status_file" | tail -1
}

state_exit_code() {
  case "$1" in
    complete|running) echo 0 ;;
    limit) echo 2 ;;
    failed) echo 3 ;;
    timeout) echo 4 ;;
    *) echo 1 ;;
  esac
}

# ------------------------------------------------------- structured detection

# A usage/rate limit is declared ONLY from structured signals: a non-zero exit
# PLUS an anchored error-envelope line in the tail of stderr that itself carries
# a limit token. Never a substring grep over the whole output — the review body
# and the reviewer's stderr both contain repo content the reviewer read, and a
# loose match there has already aborted a healthy run.
is_usage_limit() {
  local log="$1"
  [[ -f "$log" ]] || return 1
  # The envelope anchor requires the colon immediately after the token: a prose
  # line such as "Error handling: the server replies 429 Too Many Requests" is
  # repo content, not an error envelope, and must not declare a limit.
  tail -n 40 "$log" \
    | grep -E '^[[:space:]]*(ERROR|Error|error|FATAL|fatal):|^[[:space:]]*stream error|^[[:space:]]*\{"error"|^[[:space:]]*HTTP/[0-9.]+ [0-9]{3}' \
    | grep -Eqi 'usage limit|rate.?limit|quota|\b429\b|too many requests|reached your (usage )?limit'
}

# A round is accepted only if the body actually contains a review — see
# references/rationale.md § "Harness correctness" for why this is checked at all.
#
# The grammar is mode-aware. A discovery round is a findings document; a
# verification round is a set of verdict blocks and may legitimately carry no
# findings header at all when nothing regressed. Judging a verification body by
# the discovery grammar fails the healthiest round the loop can produce.
validate_body() {
  # echoes "<findings_count> <bytes> <verdict> [reason]"
  local body="$1"
  local bytes=0 findings=0 verdicts=0
  if [[ -f "$body" ]]; then
    bytes="$(wc -c <"$body" | tr -d ' ')"
  fi
  if [[ "$bytes" -eq 0 ]]; then
    echo "0 0 invalid empty_body"
    return 0
  fi
  # Tolerate case drift and the literal bracket form of the prompt's own
  # "### [SEVERITY]:" template. Fail-closed is right; failing a well-formed
  # round over punctuation is not.
  findings="$(grep -ciE '^###[[:space:]]+(\*\*)?\[?(critical|high|medium|low)\b' "$body" || true)"
  verdicts="$(grep -ciE '^[[:space:]]*(\*\*)?verdict(\*\*)?[[:space:]]*:' "$body" || true)"

  if [[ "$REVIEW_MODE" == "verification" ]]; then
    if [[ "$verdicts" -gt 0 ]]; then
      # A verdict block cannot be empty, so it is its own evidence that a review
      # happened; the byte floor is a discovery-mode proxy and does not apply.
      echo "$findings $bytes valid ok"
      return 0
    fi
    if grep -qE '^[[:space:]]*(\*\*)?NO FINDINGS' "$body"; then
      echo "0 $bytes valid explicit_no_findings"
      return 0
    fi
    echo "0 $bytes invalid no_verdict_blocks"
    return 0
  fi

  if ! grep -q '^## Findings' "$body"; then
    echo "0 $bytes invalid missing_findings_header"
    return 0
  fi
  if [[ "$findings" -eq 0 ]]; then
    if grep -qE '^[[:space:]]*(\*\*)?NO FINDINGS' "$body"; then
      echo "0 $bytes valid explicit_no_findings"
      return 0
    fi
    echo "0 $bytes invalid no_structured_findings"
    return 0
  fi
  if [[ "$bytes" -lt "$MIN_BODY_BYTES" ]]; then
    echo "$findings $bytes invalid body_below_min_bytes"
    return 0
  fi
  echo "$findings $bytes valid ok"
}

# ------------------------------------------------------------------ the worker

worker() {
  local prd_path="$1"
  local repo_root="$2"
  local rel_path="$3"
  paths_for "$4"

  echo "$$" >"$pid_file"

  local prompt
  prompt="$(build_prompt "$rel_path")"

  # D26: never full access on the live tree. If the read-only sandbox is
  # unavailable, review a disposable snapshot instead — a degraded sandbox can
  # then only touch a throwaway copy, and the status file says so.
  local sandbox_mode="read-only"
  local review_tree="$repo_root"
  SANDBOX_NOTE="read-only_live_tree"
  if ! unshare --net true 2>/dev/null; then
    make_snapshot "$repo_root"
    # The PRD under review may be uncommitted; overlay the live copy so the
    # snapshot reviews the current document, not HEAD's.
    mkdir -p "$SNAPSHOT_TREE/$(dirname "$rel_path")"
    cp -f "$prd_path" "$SNAPSHOT_TREE/$rel_path"
    review_tree="$SNAPSHOT_TREE"
    sandbox_mode="danger-full-access"
    SANDBOX_NOTE="degraded_full_access_on_disposable_${SNAPSHOT_KIND}_snapshot"
    {
      echo "SNAPSHOT_DIR=$SNAPSHOT_DIR"
      echo "SNAPSHOT_KIND=$SNAPSHOT_KIND"
    } >>"$meta_file"
    trap 'cleanup_snapshot' EXIT
    trap 'cleanup_snapshot; exit 143' TERM INT
  fi

  # Run codex in its own session, and poll it here rather than capping it in the
  # foreground — a hard foreground timeout kills healthy rounds mid-exploration.
  # The session leader records its own pid so the whole process group (codex and
  # anything it spawned) can be reaped if the window elapses.
  local pgid_file="${out_path%.md}.pgid"
  rm -f "$pgid_file"
  local -a launcher=()
  if command -v setsid >/dev/null 2>&1 && setsid --help 2>&1 | grep -q -- '--wait'; then
    launcher=(setsid --wait bash -c 'echo $$ >"$0"; exec "$@"' "$pgid_file")
  fi

  local codex_exit=0 timed_out=0 codex_pid=""
  # stdin is closed. A reviewer that blocks on stdin produces a header and no
  # findings, and then reports success.
  ${launcher[@]+"${launcher[@]}"} codex exec \
    --sandbox "$sandbox_mode" \
    --config "model_reasoning_effort=$REASONING_EFFORT" \
    -C "$review_tree" \
    "$prompt" \
    <"/dev/null" \
    >"$body_path" \
    2>"$stderr_log" &
  codex_pid=$!

  local deadline=$((SECONDS + WINDOW_SECONDS))
  while kill -0 "$codex_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      timed_out=1
      local pgid=""
      [[ -f "$pgid_file" ]] && pgid="$(cat "$pgid_file" 2>/dev/null || true)"
      if [[ -n "$pgid" ]]; then
        kill -TERM "-$pgid" 2>/dev/null || true
        sleep 5
        kill -KILL "-$pgid" 2>/dev/null || true
      fi
      kill -TERM "$codex_pid" 2>/dev/null || true
      sleep 2
      kill -KILL "$codex_pid" 2>/dev/null || true
      break
    fi
    sleep 2
  done
  wait "$codex_pid" 2>/dev/null || codex_exit=$?
  rm -f "$pgid_file"

  local read_out
  read_out="$(validate_body "$body_path")"
  local findings bytes verdict reason
  read -r findings bytes verdict reason <<<"$read_out"

  local state=""
  if [[ "$timed_out" -eq 1 ]]; then
    state="timeout"; reason="window_elapsed"
  elif [[ "$codex_exit" -ne 0 ]]; then
    if is_usage_limit "$stderr_log"; then
      state="limit"; reason="usage_limit"
    else
      state="failed"; reason="codex_exit_${codex_exit}"
    fi
  elif [[ "$verdict" != "valid" ]]; then
    state="failed"
  else
    state="complete"; reason=""
  fi

  assemble_output "$rel_path" "$state" "$codex_exit" "$reason"
  write_status "$state" "$codex_exit" "$bytes" "$findings" "$reason"
  rm -f "$pid_file"
  cleanup_snapshot
}

assemble_output() {
  local rel_path="$1" state="$2" codex_exit="$3" reason="${4:-}"
  local tmp="${out_path}.tmp.$$"
  {
    echo "# Codex PRD Challenge Review"
    echo
    echo "- Source: \`$rel_path\`"
    echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
    echo "- Reviewer: Codex CLI (model diversity)"
    echo "- Mode: \`$REVIEW_MODE\`"
    echo "- State: \`$state\`"
    echo
    if [[ "$state" != "complete" ]]; then
      echo "## Findings — Codex"
      echo
      echo "_No usable review produced. STATE=\`$state\`, EXIT=\`$codex_exit\`, REASON=\`${reason:-unknown}\`._"
      echo "_This round produced NO reviewer opinion. Do not treat it as a clean round._"
      echo "_Raw stdout (may be partial): \`$body_path\`. Stderr: \`$stderr_log\`._"
      echo
    else
      cat "$body_path"
    fi
  } >"$tmp"
  mv -f "$tmp" "$out_path"
}

build_prompt() {
  local rel_path="$1"
  local common="You are an independent reviewer examining a PRD (Product Requirements Document).

First, read the PRD file at: $rel_path

Then explore the codebase for context to ground your analysis.

Produce findings in this exact format:

## Findings — Codex

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
- **SUBSTANTIVE**: the PRD's intended behavior is wrong, missing, undecided,
  unbounded, or not testable. Fixing it changes what gets built.
- **CONSISTENCY**: the intended behavior is stated correctly in its normative
  home, but another location contradicts it, restates it stalely, renames it,
  or points at something that moved. Fixing it changes no intended behavior.
- If you cannot identify a normative home that is already correct, the finding
  is SUBSTANTIVE.

IF YOU HAVE NO FINDINGS: output the '## Findings — Codex' header followed by a
line containing exactly:

NO FINDINGS

Never return an empty document. Never stop to ask a question — you are running
non-interactively with no stdin.

Do NOT suggest implementation approaches or architectural decisions.
Do NOT add new features — only identify gaps in existing requirements."

  if [[ "$REVIEW_MODE" == "verification" && -n "$DELTA_FILE" && -f "$DELTA_FILE" ]]; then
    printf '%s\n\n%s\n' \
      "This is a VERIFICATION round, not a discovery round. You are scoped to the
remediation delta below. For EACH listed finding emit exactly one verdict block:

#### <finding id>: <finding title>
**Verdict:** CONFIRMED | NOT CONFIRMED
**Evidence:** [quote or cite the exact PRD location that settles it]
**Reason (only if NOT CONFIRMED):** [what is still wrong or now wrong]

'Partially addressed' is NOT CONFIRMED. Do not leave a listed finding without a
verdict. CONFIRMED requires evidence you can quote from the current document; if
you cannot quote the text that settles it, the verdict is NOT CONFIRMED.

You did not raise these findings, and the remediator may have applied a
different fix from the one suggested, or declined the finding with a recorded
reason. Judge each item against the CONCERN as stated in the delta, not against
whether the suggested edit was applied verbatim.

Then emit a regression sweep, in the findings format below, for anything the
remediation broke or newly introduced — including in prose the remediation
itself added.

--- REMEDIATION DELTA ---
$(cat "$DELTA_FILE")
--- END REMEDIATION DELTA ---" \
      "$common"
  else
    printf '%s\n\n%s\n' \
      "Your goal is to find gaps, contradictions, and ambiguities that the PRD author
may have missed. Focus on:
- Missing edge cases and error states
- Contradictory or ambiguous requirements
- Acceptance criteria that are not testable
- Scope gaps (mentioned in requirements but not in scope, or vice versa)
- Non-functional requirements that lack measurable thresholds
- Unresolved decisions, non-deterministic behavior, and unbounded payloads" \
      "$common"
  fi
}

# ---------------------------------------------------------------- subcommands

cmd_start() {
  local prd_path="$1"
  paths_for "$2"

  if ! command -v codex >/dev/null 2>&1; then
    echo "Error: codex CLI is not installed or not in PATH." >&2
    exit 1
  fi

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  if [[ "$prd_path" != /* ]]; then
    prd_path="$repo_root/$prd_path"
  fi
  if [[ ! -f "$prd_path" ]]; then
    echo "Error: PRD file not found at $prd_path" >&2
    exit 1
  fi
  if [[ "$REVIEW_MODE" == "verification" && ( -z "$DELTA_FILE" || ! -f "$DELTA_FILE" ) ]]; then
    echo "Error: CODEX_REVIEW_MODE=verification requires CODEX_REVIEW_DELTA_FILE to point at an existing file." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$out_path")"

  # Never clobber another run's output. Each run gets a unique out-path; a
  # collision means two runs are sharing a scratch path, which has already
  # destroyed a completed review once. The out-file only appears at a terminal
  # state, so a still-RUNNING round at this path is caught by the status file.
  if [[ "$(read_state)" == "running" && "${CODEX_REVIEW_FORCE:-0}" != "1" ]]; then
    echo "Error: a round is already running at this path: $out_path" >&2
    echo "Use a unique per-round path, or set CODEX_REVIEW_FORCE=1 to take it over." >&2
    exit 1
  fi
  if [[ -s "$out_path" && "${CODEX_REVIEW_FORCE:-0}" != "1" ]]; then
    echo "Error: output path already exists and is non-empty: $out_path" >&2
    echo "Use a unique per-round path, or set CODEX_REVIEW_FORCE=1 to overwrite." >&2
    exit 1
  fi

  local rel_path="${prd_path#"$repo_root"/}"
  if [[ "$rel_path" == "$prd_path" ]]; then
    rel_path="$(basename "$prd_path")"
  fi

  rm -f "$body_path" "$stderr_log" "$pid_file"
  {
    echo "PRD=$prd_path"
    echo "REL=$rel_path"
    echo "REPO_ROOT=$repo_root"
    echo "MODE=$REVIEW_MODE"
    echo "WINDOW_SECONDS=$WINDOW_SECONDS"
    echo "STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "STARTED_EPOCH=$(date -u +%s)"
  } >"$meta_file"

  # Status is written BEFORE the worker launches so a poller can never observe
  # a missing status file.
  write_status "running" "" "0" "0" ""

  local -a launcher=(nohup)
  if command -v setsid >/dev/null 2>&1; then
    launcher=(setsid nohup)
  fi
  "${launcher[@]}" bash "$0" __worker "$prd_path" "$repo_root" "$rel_path" "$out_path" \
    </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true

  echo "STARTED_PATH=$out_path"
  echo "STATUS_FILE=$status_file"
  cat "$status_file"
}

reap_if_over_window() {
  local state
  state="$(read_state)"
  [[ "$state" == "running" ]] || return 0
  [[ -f "$meta_file" ]] || return 0
  local started window now
  started="$(sed -n 's/^STARTED_EPOCH=//p' "$meta_file" | tail -1)"
  window="$(sed -n 's/^WINDOW_SECONDS=//p' "$meta_file" | tail -1)"
  [[ -n "$started" && -n "$window" ]] || return 0
  now="$(date -u +%s)"
  if (( now - started > window + 60 )); then
    # codex was setsid-ed into its OWN session, so killing the worker's process
    # group does not reach it. Reap the recorded codex process group too, or a
    # declared timeout leaves an orphan burning tokens.
    local pgid_file="${out_path%.md}.pgid" pgid=""
    [[ -f "$pgid_file" ]] && pgid="$(cat "$pgid_file" 2>/dev/null || true)"
    if [[ -n "$pgid" ]]; then
      kill -TERM "-$pgid" 2>/dev/null || true
    fi
    if [[ -f "$pid_file" ]]; then
      local wpid
      wpid="$(cat "$pid_file")"
      kill -TERM "-$wpid" 2>/dev/null || kill -TERM "$wpid" 2>/dev/null || true
      sleep 2
      kill -KILL "-$wpid" 2>/dev/null || kill -KILL "$wpid" 2>/dev/null || true
      rm -f "$pid_file"
    fi
    if [[ -n "$pgid" ]]; then
      kill -KILL "-$pgid" 2>/dev/null || true
      rm -f "$pgid_file"
    fi
    # A KILLed worker never runs its cleanup trap; remove any disposable
    # snapshot it recorded in the meta file so a reaped round leaves no
    # orphaned worktree/copy behind.
    local snap_dir snap_kind snap_repo
    snap_dir="$(sed -n 's/^SNAPSHOT_DIR=//p' "$meta_file" | tail -1)"
    snap_kind="$(sed -n 's/^SNAPSHOT_KIND=//p' "$meta_file" | tail -1)"
    snap_repo="$(sed -n 's/^REPO_ROOT=//p' "$meta_file" | tail -1)"
    if [[ -n "$snap_dir" && -d "$snap_dir" ]]; then
      if [[ "$snap_kind" == "worktree" && -n "$snap_repo" ]]; then
        git -C "$snap_repo" worktree remove --force "$snap_dir/tree" >/dev/null 2>&1 || true
      fi
      rm -rf "$snap_dir"
    fi
    # Report the mode the round was STARTED in, not the poller's environment.
    local meta_mode
    meta_mode="$(sed -n 's/^MODE=//p' "$meta_file" | tail -1)"
    [[ -n "$meta_mode" ]] && REVIEW_MODE="$meta_mode"
    write_status "timeout" "" "0" "0" "window_elapsed"
  fi
}

cmd_status() {
  paths_for "$1"
  if [[ ! -f "$status_file" ]]; then
    echo "STATE=failed"
    echo "REASON=no_status_file"
    exit 3
  fi
  reap_if_over_window
  cat "$status_file"
  exit "$(state_exit_code "$(read_state)")"
}

cmd_wait() {
  paths_for "$1"
  local max_wait="${2:-$WAIT_SLICE_SECONDS}"
  if [[ ! -f "$status_file" ]]; then
    echo "STATE=failed"
    echo "REASON=no_status_file"
    exit 3
  fi
  local deadline=$((SECONDS + max_wait))
  while (( SECONDS < deadline )); do
    reap_if_over_window
    local state
    state="$(read_state)"
    if [[ "$state" != "running" ]]; then
      cat "$status_file"
      exit "$(state_exit_code "$state")"
    fi
    sleep "$POLL_SECONDS"
  done
  reap_if_over_window
  cat "$status_file"
  exit "$(state_exit_code "$(read_state)")"
}

# --------------------------------------------------------------------- dispatch

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

case "$1" in
  __worker)
    shift
    [[ $# -eq 4 ]] || { echo "Internal usage: __worker <prd> <repo_root> <rel> <out>" >&2; exit 1; }
    worker "$1" "$2" "$3" "$4"
    ;;
  start)
    shift
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    cmd_start "$1" "$2"
    ;;
  status)
    shift
    [[ $# -eq 1 ]] || { usage >&2; exit 1; }
    cmd_status "$1"
    ;;
  wait)
    shift
    [[ $# -ge 1 ]] || { usage >&2; exit 1; }
    cmd_wait "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    # Legacy two-positional form: start, then poll for the whole window.
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    cmd_start "$1" "$2" >/dev/null
    paths_for "$2"
    cmd_wait "$2" "$((WINDOW_SECONDS + 120))"
    ;;
esac
