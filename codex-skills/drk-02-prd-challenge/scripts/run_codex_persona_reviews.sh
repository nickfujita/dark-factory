#!/usr/bin/env bash
set -euo pipefail

# run_codex_persona_reviews.sh — the three PRD challenge persona reviews.
#
# Usage:
#   run_codex_persona_reviews.sh start  <prd-path> <out-dir>
#   run_codex_persona_reviews.sh status <out-dir>
#   run_codex_persona_reviews.sh wait   <out-dir> [max_wait_seconds]
#   run_codex_persona_reviews.sh <prd-path> <out-dir>     # legacy: start + wait
#
# The reviews run DETACHED with a wide window and are polled, because a hard
# foreground timeout kills healthy rounds mid-exploration on a large PRD.
#
# The contract with the caller is the STATUS FILE, not the exit code and never
# a substring match over a review body or a stderr log:
#
#   STATE=running|complete|partial|failed|limit|timeout
#   PERSONAS_OK=<n>/3
#   REASON=<short machine token>          (only when STATE != complete)
#
# Per-persona detail lives in <out-dir>/<persona>.status, same fields plus
# EXIT / BODY_BYTES / FINDINGS.
#
# Exit codes for `status` / `wait` / legacy mode:
#   0 complete (or still running), 2 limit, 3 failed, 4 timeout, 5 partial,
#   1 usage / precondition error
#
# Environment overrides (defaults mirror the skill's pinned parameters):
#   CODEX_WINDOW_SECONDS=3600      total detached window for one round
#   CODEX_WAIT_SLICE_SECONDS=480   default blocking time for one `wait` call
#   CODEX_POLL_SECONDS=20          poll interval inside a slice
#   CODEX_MIN_BODY_BYTES=400       minimum accepted body when findings are claimed
#   CODEX_REASONING_EFFORT=xhigh   codex model_reasoning_effort
#   CODEX_REVIEW_FORCE=1           allow reusing a non-empty existing out-dir

WINDOW_SECONDS="${CODEX_WINDOW_SECONDS:-3600}"
WAIT_SLICE_SECONDS="${CODEX_WAIT_SLICE_SECONDS:-480}"
POLL_SECONDS="${CODEX_POLL_SECONDS:-20}"
MIN_BODY_BYTES="${CODEX_MIN_BODY_BYTES:-400}"
REASONING_EFFORT="${CODEX_REASONING_EFFORT:-xhigh}"

PERSONA_SLUGS=(user-advocate technical-feasibility scope-complexity)
PERSONA_NAMES=("Skeptical User Advocate" "Technical Feasibility Reviewer" "Scope & Complexity Challenger")
PERSONA_SECTIONS=("Persona 1: Skeptical User Advocate" "Persona 2: Technical Feasibility Reviewer" "Persona 3: Scope & Complexity Challenger")

usage() {
  cat <<'USAGE'
Usage:
  run_codex_persona_reviews.sh start  <prd-path> <out-dir>
  run_codex_persona_reviews.sh status <out-dir>
  run_codex_persona_reviews.sh wait   <out-dir> [max_wait_seconds]
  run_codex_persona_reviews.sh <prd-path> <out-dir>     # legacy: start + wait

The caller's contract is the status file printed by `status` / `wait`:
  STATE=running|complete|partial|failed|limit|timeout
Exit codes: 0 complete/running, 2 limit, 3 failed, 4 timeout, 5 partial,
1 usage error. See the header comment for environment overrides.
USAGE
}

# ---------------------------------------------------------------- path helpers

dir_for() {
  out_dir="$1"
  if [[ "$out_dir" != /* ]]; then out_dir="$PWD/$out_dir"; fi
  run_status="$out_dir/run.status"
  run_meta="$out_dir/run.meta"
  run_pid="$out_dir/run.pid"
}

write_kv() {
  # write_kv <file> <line>...
  local f="$1"; shift
  local tmp="${f}.tmp.$$"
  printf '%s\n' "$@" >"$tmp"
  printf 'UPDATED=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$tmp"
  mv -f "$tmp" "$f"
}

read_field() {
  # read_field <file> <key>
  [[ -f "$1" ]] || { echo ""; return 0; }
  sed -n "s/^$2=//p" "$1" | tail -1
}

state_exit_code() {
  case "$1" in
    complete|running) echo 0 ;;
    limit) echo 2 ;;
    failed) echo 3 ;;
    timeout) echo 4 ;;
    partial) echo 5 ;;
    *) echo 1 ;;
  esac
}

# ------------------------------------------------------- structured detection

# A usage/rate limit is declared ONLY from structured signals: a non-zero exit
# PLUS an anchored error-envelope line in the tail of stderr that itself carries
# a limit token. Never a substring grep over the whole output — review bodies and
# reviewer stderr both contain repo content the reviewer read, and a loose match
# there has already aborted a healthy run.
is_usage_limit() {
  local log="$1"
  [[ -f "$log" ]] || return 1
  tail -n 40 "$log" \
    | grep -E '^[[:space:]]*(ERROR|Error|error|FATAL|fatal)[: ]|^[[:space:]]*stream error|^[[:space:]]*\{"error"|^[[:space:]]*HTTP/[0-9.]+ [0-9]{3}' \
    | grep -Eqi 'usage limit|rate.?limit|quota|\b429\b|too many requests|reached your (usage )?limit'
}

# A round is accepted only if the body actually contains a review. An empty
# review that reports success is worse than a crash.
validate_body() {
  # echoes "<findings> <bytes> <verdict> <reason>"
  local body="$1"
  local bytes=0 findings=0
  if [[ -f "$body" ]]; then bytes="$(wc -c <"$body" | tr -d ' ')"; fi
  if [[ "$bytes" -eq 0 ]]; then echo "0 0 invalid empty_body"; return 0; fi
  if ! grep -q '^## Findings' "$body"; then
    echo "0 $bytes invalid missing_findings_header"; return 0
  fi
  findings="$(grep -cE '^###[[:space:]]+(\*\*)?(Critical|High|Medium|Low)' "$body" || true)"
  if [[ "$findings" -eq 0 ]]; then
    if grep -qE '^[[:space:]]*(\*\*)?NO FINDINGS' "$body"; then
      echo "0 $bytes valid explicit_no_findings"; return 0
    fi
    echo "0 $bytes invalid no_structured_findings"; return 0
  fi
  if [[ "$bytes" -lt "$MIN_BODY_BYTES" ]]; then
    echo "$findings $bytes invalid body_below_min_bytes"; return 0
  fi
  echo "$findings $bytes valid ok"
}

persona_prompt() {
  local section="$1" prd_rel="$2" persona_text="$3"
  cat <<PROMPT
Read the PRD at $prd_rel.
Use only the section named "$section" from these persona instructions:

$persona_text

Explore the codebase for context, then review the PRD using that persona.
Return findings in the exact output format specified for that persona, including
the mandatory **Class:** SUBSTANTIVE | CONSISTENCY line on every finding.

IF YOU HAVE NO FINDINGS: output your persona's '## Findings — ...' header
followed by a line containing exactly:

NO FINDINGS

Never return an empty document. Never stop to ask a question — you are running
non-interactively with no stdin.

Do not suggest implementation approaches or new features.
PROMPT
}

# ------------------------------------------------------------------ the worker

run_one_persona() {
  local idx="$1" prd_rel="$2" repo_root="$3" persona_text="$4" sandbox_mode="$5"
  local slug="${PERSONA_SLUGS[$idx]}"
  local name="${PERSONA_NAMES[$idx]}"
  local section="${PERSONA_SECTIONS[$idx]}"
  local out_path="$out_dir/$slug.md"
  local body_path="$out_dir/$slug.body.md"
  local stderr_log="$out_dir/$slug.stderr.log"
  local status_path="$out_dir/$slug.status"
  local pgid_file="$out_dir/$slug.pgid"

  write_kv "$status_path" "STATE=running" "PERSONA=$name"

  local prompt
  prompt="$(persona_prompt "$section" "$prd_rel" "$persona_text")"

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
    -C "$repo_root" \
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

  local findings bytes verdict reason
  read -r findings bytes verdict reason <<<"$(validate_body "$body_path")"

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
    state="complete"; reason="ok"
  fi

  local tmp="$out_path.tmp.$$"
  {
    echo "# PRD Persona Review: $name"
    echo
    echo "- PRD: \`$prd_rel\`"
    echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
    echo "- State: \`$state\`"
    echo
    if [[ "$state" != "complete" ]]; then
      echo "## Findings — $name"
      echo
      echo "_No usable review produced. STATE=\`$state\`, EXIT=\`$codex_exit\`, REASON=\`$reason\`._"
      echo "_This reviewer produced NO opinion this round. Do not treat it as a clean result._"
      echo "_Raw stdout (may be partial): \`$body_path\`. Stderr: \`$stderr_log\`._"
      echo
    else
      cat "$body_path"
    fi
  } >"$tmp"
  mv -f "$tmp" "$out_path"

  write_kv "$status_path" \
    "STATE=$state" "PERSONA=$name" "EXIT=$codex_exit" \
    "BODY_BYTES=$bytes" "FINDINGS=$findings" "REASON=$reason"
}

worker() {
  local prd_rel="$1" repo_root="$2"
  dir_for "$3"
  echo "$$" >"$run_pid"

  local persona_path="$4"
  local persona_text
  persona_text="$(cat "$persona_path")"

  local sandbox_mode="read-only"
  if ! unshare --net true 2>/dev/null; then
    sandbox_mode="danger-full-access"
  fi

  local -a pids=()
  local i
  for i in 0 1 2; do
    run_one_persona "$i" "$prd_rel" "$repo_root" "$persona_text" "$sandbox_mode" &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do
    wait "$i" || true
  done

  local ok=0 limit=0 timeout=0 failed=0
  for i in 0 1 2; do
    case "$(read_field "$out_dir/${PERSONA_SLUGS[$i]}.status" STATE)" in
      complete) ok=$((ok + 1)) ;;
      limit) limit=$((limit + 1)) ;;
      timeout) timeout=$((timeout + 1)) ;;
      *) failed=$((failed + 1)) ;;
    esac
  done

  local state reason
  if [[ "$ok" -eq 3 ]]; then
    state="complete"; reason="ok"
  elif [[ "$limit" -gt 0 && "$ok" -eq 0 ]]; then
    state="limit"; reason="usage_limit"
  elif [[ "$ok" -gt 0 ]]; then
    state="partial"; reason="only_${ok}_of_3_reviewers_produced_a_review"
  elif [[ "$timeout" -gt 0 ]]; then
    state="timeout"; reason="window_elapsed"
  else
    state="failed"; reason="no_reviewer_produced_a_review"
  fi
  if [[ "$limit" -gt 0 && "$state" == "partial" ]]; then
    reason="${reason}_and_a_usage_limit_was_hit"
  fi

  write_kv "$run_status" "STATE=$state" "PERSONAS_OK=$ok/3" "LIMIT_HITS=$limit" "REASON=$reason"
  rm -f "$run_pid"
}

# ---------------------------------------------------------------- subcommands

cmd_start() {
  local prd_path="$1"
  dir_for "$2"

  if ! command -v codex >/dev/null 2>&1; then
    echo "Error: codex CLI is not installed or not in PATH." >&2
    exit 1
  fi

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if [[ "$prd_path" != /* ]]; then prd_path="$repo_root/$prd_path"; fi
  if [[ ! -f "$prd_path" ]]; then
    echo "Error: PRD file not found at $prd_path" >&2
    exit 1
  fi

  local codex_skills_dir="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}"
  local persona_path="$codex_skills_dir/drk-02-prd-challenge/references/personas.md"
  if [[ ! -f "$persona_path" ]]; then
    persona_path="$repo_root/codex-skills/drk-02-prd-challenge/references/personas.md"
  fi
  if [[ ! -f "$persona_path" ]]; then
    echo "Error: personas.md not found" >&2
    exit 1
  fi

  # Never reuse another round's output directory: a shared scratch path has
  # already destroyed a completed review.
  if [[ -s "$run_status" && "${CODEX_REVIEW_FORCE:-0}" != "1" ]]; then
    echo "Error: output directory already holds a run: $out_dir" >&2
    echo "Use a unique per-round directory, or set CODEX_REVIEW_FORCE=1." >&2
    exit 1
  fi

  mkdir -p "$out_dir"
  local prd_rel="${prd_path#"$repo_root"/}"
  if [[ "$prd_rel" == "$prd_path" ]]; then prd_rel="$(basename "$prd_path")"; fi

  local slug
  for slug in "${PERSONA_SLUGS[@]}"; do
    rm -f "$out_dir/$slug.body.md" "$out_dir/$slug.stderr.log" "$out_dir/$slug.status"
  done
  write_kv "$run_meta" \
    "PRD=$prd_path" "REL=$prd_rel" "REPO_ROOT=$repo_root" \
    "WINDOW_SECONDS=$WINDOW_SECONDS" "STARTED_EPOCH=$(date -u +%s)"
  # Status is written BEFORE the worker launches so a poller can never observe
  # a missing status file.
  write_kv "$run_status" "STATE=running" "PERSONAS_OK=0/3"

  local -a launcher=(nohup)
  if command -v setsid >/dev/null 2>&1; then launcher=(setsid nohup); fi
  "${launcher[@]}" bash "$0" __worker "$prd_rel" "$repo_root" "$out_dir" "$persona_path" \
    </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true

  echo "STARTED_DIR=$out_dir"
  echo "STATUS_FILE=$run_status"
  cat "$run_status"
}

reap_if_over_window() {
  [[ "$(read_field "$run_status" STATE)" == "running" ]] || return 0
  [[ -f "$run_meta" ]] || return 0
  local started window now
  started="$(read_field "$run_meta" STARTED_EPOCH)"
  window="$(read_field "$run_meta" WINDOW_SECONDS)"
  [[ -n "$started" && -n "$window" ]] || return 0
  now="$(date -u +%s)"
  if (( now - started > window + 120 )); then
    if [[ -f "$run_pid" ]]; then
      local wpid
      wpid="$(cat "$run_pid")"
      kill -TERM "-$wpid" 2>/dev/null || kill -TERM "$wpid" 2>/dev/null || true
      sleep 2
      kill -KILL "-$wpid" 2>/dev/null || kill -KILL "$wpid" 2>/dev/null || true
      rm -f "$run_pid"
    fi
    write_kv "$run_status" "STATE=timeout" "PERSONAS_OK=0/3" "REASON=window_elapsed"
  fi
}

cmd_status() {
  dir_for "$1"
  if [[ ! -f "$run_status" ]]; then
    echo "STATE=failed"; echo "REASON=no_status_file"; exit 3
  fi
  reap_if_over_window
  cat "$run_status"
  exit "$(state_exit_code "$(read_field "$run_status" STATE)")"
}

cmd_wait() {
  dir_for "$1"
  local max_wait="${2:-$WAIT_SLICE_SECONDS}"
  if [[ ! -f "$run_status" ]]; then
    echo "STATE=failed"; echo "REASON=no_status_file"; exit 3
  fi
  local deadline=$((SECONDS + max_wait))
  while (( SECONDS < deadline )); do
    reap_if_over_window
    local state
    state="$(read_field "$run_status" STATE)"
    if [[ "$state" != "running" ]]; then
      cat "$run_status"
      exit "$(state_exit_code "$state")"
    fi
    sleep "$POLL_SECONDS"
  done
  reap_if_over_window
  cat "$run_status"
  exit "$(state_exit_code "$(read_field "$run_status" STATE)")"
}

# --------------------------------------------------------------------- dispatch

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

case "$1" in
  __worker)
    shift
    [[ $# -eq 4 ]] || { echo "Internal usage: __worker <prd_rel> <repo_root> <out_dir> <personas>" >&2; exit 1; }
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
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    cmd_start "$1" "$2" >/dev/null
    cmd_wait "$2" "$((WINDOW_SECONDS + 180))"
    ;;
esac
