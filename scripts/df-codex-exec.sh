#!/usr/bin/env bash
# Claude-only transport for running a durable Codex worker one turn at a time.
#
# This file ships from the Claude Code plugin root. It must not be copied into
# codex-plugin/: a Codex coordinator uses native subagent and worktree threads.
#
# Usage:
#   df-codex-exec.sh start <name> --cd <dir> --brief <file> \
#       --df-run <run-id> --df-lane <lane> --df-repo-root <consumer-root> \
#       [--sandbox read-only|workspace-write|danger-full-access]
#   df-codex-exec.sh start <name> --cd <dir> --brief <file> \
#       --df-run <run-id> --df-lane <lane> --df-repo-root <consumer-root> \
#       --dangerously-bypass-approvals-and-sandbox
#   df-codex-exec.sh resume <name> --prompt <file>
#   df-codex-exec.sh status <name>
#   df-codex-exec.sh transcript <name>
#
# State lives at $DF_CODEX_STATE_ROOT/<name>. The default is outside every
# target repository under the user's state directory. Each turn records its
# prompt, JSONL event stream, final message, stderr, exit code, and start time.
# A persisted Codex thread id lets a later Claude coordinator resume the worker.
#
# Provider capacity, rate-limit, and transient 5xx failures are retried by
# resuming the same thread. Configure the bounded retry with
# DF_CODEX_MAX_RETRIES and DF_CODEX_RETRY_SLEEP.
set -uo pipefail
umask 077

usage() {
  sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

die() {
  printf 'df-codex-exec: %s\n' "$1" >&2
  exit "${2:-1}"
}

[[ $# -ge 2 ]] || usage
command_name=$1
session_name=$2
shift 2
[[ "$session_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
  || die 'session name must use only letters, numbers, dot, underscore, and hyphen'

workdir=''
brief=''
prompt=''
df_run=''
df_lane=''
df_repo_root=''
sandbox=''
dangerous_bypass='false'
security_option_seen='false'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cd)
      [[ $# -ge 2 ]] || die '--cd needs a directory'
      workdir=$2
      shift 2
      ;;
    --brief)
      [[ $# -ge 2 ]] || die '--brief needs a file'
      brief=$2
      shift 2
      ;;
    --prompt)
      [[ $# -ge 2 ]] || die '--prompt needs a file'
      prompt=$2
      shift 2
      ;;
    --df-run)
      [[ $# -ge 2 ]] || die '--df-run needs a value'
      df_run=$2
      shift 2
      ;;
    --df-lane)
      [[ $# -ge 2 ]] || die '--df-lane needs a value'
      df_lane=$2
      shift 2
      ;;
    --df-repo-root)
      [[ $# -ge 2 ]] || die '--df-repo-root needs a path'
      df_repo_root=$2
      shift 2
      ;;
    --sandbox)
      [[ $# -ge 2 ]] || die '--sandbox needs a mode'
      [[ "$security_option_seen" == 'false' ]] || die 'choose one sandbox option'
      sandbox=$2
      security_option_seen='true'
      shift 2
      ;;
    --dangerously-bypass-approvals-and-sandbox)
      [[ "$security_option_seen" == 'false' ]] || die 'choose one sandbox option'
      dangerous_bypass='true'
      security_option_seen='true'
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

state_root=${DF_CODEX_STATE_ROOT:-${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/dark-factory/codex}
session_dir=$state_root/$session_name
meta=$session_dir/meta
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
role_caller="$script_dir/df-role-caller.sh"
state_helper="${DF_ROLE_CALLER_STATE_HELPER:-$script_dir/df-state.sh}"

reserve_turn() {
  local receipt current_target seq
  receipt="$(bash "$role_caller" reserve \
    --run "$df_run" --lane "$df_lane" --repo-root "$df_repo_root" \
    --responsibility cross_model_review --purpose "durable Codex turn $1" \
    --allow-kind transport --allow-transport codex-cli)"
  current_target="$(node -e 'const receipt = JSON.parse(process.argv[1]); process.stdout.write(JSON.stringify(receipt.preflight.target));' "$receipt")"
  seq="$(node -e 'const receipt = JSON.parse(process.argv[1]); process.stdout.write(receipt.seqs[0]);' "$receipt")"
  if [[ "$current_target" != "$META_ROLE_TARGET" ]]; then
    complete_turn "$seq" failed
    die 'frozen role identity changed; start a new durable Codex session'
  fi
  printf '%s\n' "$seq"
}

complete_turn() {
  local seq=$1 outcome=$2
  (cd "$df_repo_root" && bash "$state_helper" complete "$df_run" "$seq" "$outcome") >/dev/null 2>&1 || true
}

active_turn_seq=''
close_active_turn() {
  local exit_code=$?
  if [[ -n "$active_turn_seq" ]]; then
    local outcome=failed
    [[ "$exit_code" -eq 0 ]] && outcome=ok
    complete_turn "$active_turn_seq" "$outcome"
    active_turn_seq=''
  fi
  return "$exit_code"
}
trap close_active_turn EXIT
trap 'exit 143' TERM INT

next_turn() {
  local highest=0 file turn
  for file in "$session_dir"/turn-*.events.jsonl; do
    [[ -e "$file" ]] || continue
    turn=${file##*/turn-}
    turn=${turn%%.*}
    (( turn > highest )) && highest=$turn
  done
  printf '%s\n' "$((highest + 1))"
}

load_meta() {
  [[ -f "$meta" ]] || die "no session named '$session_name' under $state_root" 2
  # Values were written with printf %q below.
  # shellcheck disable=SC1090
  source "$meta"
  workdir=$META_DIR
  df_run=${META_DF_RUN:-}
  df_lane=${META_DF_LANE:-}
  df_repo_root=${META_DF_REPO_ROOT:-}
  [[ -n "$df_run$df_lane$df_repo_root${META_ROLE_TARGET:-}" ]] \
    || die "legacy session '$session_name' has no frozen role identity; start a new session"
  if [[ -n "${META_DANGEROUS_BYPASS+x}" ]]; then
    sandbox=$META_SANDBOX
    dangerous_bypass=$META_DANGEROUS_BYPASS
  else
    # Sessions created by the original private transport predate recorded
    # sandbox metadata and always used this mode. Preserve their actual
    # security contract rather than changing it silently during a resume.
    sandbox='workspace-write'
    dangerous_bypass='true'
    printf 'df-codex-exec: legacy session has no sandbox metadata; preserving its original dangerous-bypass mode\n' >&2
  fi
}

active_wrapper_pid() {
  local pid_file pid
  for pid_file in "$session_dir"/turn-*.pid; do
    [[ -e "$pid_file" ]] || continue
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      printf '%s\n' "$pid"
      return 0
    fi
  done
  return 1
}

assert_idle() {
  local pid
  pid=$(active_wrapper_pid) || return 0
  die "session '$session_name' already has a running wrapper (pid $pid)" 2
}

record_thread_id() {
  local events=$1
  [[ -s "$session_dir/thread.id" ]] && return 0
  grep -oE '"(thread_id|session_id|conversation_id)"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]{36}"' "$events" 2>/dev/null \
    | head -1 \
    | grep -oE '[0-9a-fA-F-]{36}' > "$session_dir/thread.id" || true
}

run_turn() {
  # run_turn <turn> <input-file> <start|resume> [thread-id]
  local turn=$1 input=$2 mode=$3 thread_id=${4:-}
  local events=$session_dir/turn-$turn.events.jsonl
  local last=$session_dir/turn-$turn.last.md
  local stderr_log=$session_dir/turn-$turn.stderr.log
  local -a codex_args
  local dispatch_seq

  printf '%s\n' "$$" > "$session_dir/turn-$turn.pid"
  date -u +%FT%TZ > "$session_dir/turn-$turn.started"
  dispatch_seq="$(reserve_turn "$turn")"
  active_turn_seq=$dispatch_seq

  codex_args=(
    exec
    --json
    --skip-git-repo-check
    -C "$workdir"
    -o "$last"
  )
  if [[ "$dangerous_bypass" == 'true' ]]; then
    codex_args+=(--dangerously-bypass-approvals-and-sandbox)
  else
    codex_args+=(--sandbox "$sandbox")
  fi
  if [[ "$mode" == 'resume' ]]; then
    codex_args+=(resume "$thread_id" -)
  else
    codex_args+=(-)
  fi

  (cd "$workdir" && codex "${codex_args[@]}" < "$input" > "$events" 2> "$stderr_log")
  local exit_code=$?
  printf '%s\n' "$exit_code" > "$session_dir/turn-$turn.exit"
  rm -f "$session_dir/turn-$turn.pid"
  record_thread_id "$events"
  local outcome=ok
  [[ "$exit_code" -eq 0 ]] || outcome=failed
  complete_turn "$dispatch_seq" "$outcome"
  active_turn_seq=''

  printf 'session=%s turn=%s exit=%s thread=%s\n' \
    "$session_name" "$turn" "$exit_code" "$(cat "$session_dir/thread.id" 2>/dev/null || printf unknown)"
  printf 'last-message=%s\nevents=%s\n' "$last" "$events"
  [[ -s "$last" ]] || printf 'WARNING: empty last message; read %s\n' "$stderr_log" >&2
  return "$exit_code"
}

provider_failed() {
  local events=$1 stderr_log=$2
  grep -q '"type":"turn.failed"' "$events" 2>/dev/null || return 1
  grep -qiE 'at capacity|rate.?limit|overloaded|temporarily unavailable|(^|[^0-9])(502|503|504)([^0-9]|$)|timed out|connection (reset|refused)' \
    "$events" "$stderr_log" 2>/dev/null
}

run_turn_with_retry() {
  local turn=$1 input=$2 mode=$3 thread_id=${4:-}
  local attempts=0 max_retries=${DF_CODEX_MAX_RETRIES:-6}
  local pause=${DF_CODEX_RETRY_SLEEP:-60}
  local exit_code

  [[ "$max_retries" =~ ^[0-9]+$ ]] || die 'DF_CODEX_MAX_RETRIES must be a non-negative integer'
  [[ "$pause" =~ ^[0-9]+$ ]] || die 'DF_CODEX_RETRY_SLEEP must be a non-negative integer'

  run_turn "$turn" "$input" "$mode" "$thread_id"
  exit_code=$?
  while (( exit_code != 0 )) \
    && provider_failed "$session_dir/turn-$turn.events.jsonl" "$session_dir/turn-$turn.stderr.log" \
    && (( attempts < max_retries )); do
    attempts=$((attempts + 1))
    printf 'provider failure on turn %s; retrying in %ss (%s/%s)\n' \
      "$turn" "$pause" "$attempts" "$max_retries" >&2
    sleep "$pause"
    thread_id=$(cat "$session_dir/thread.id" 2>/dev/null || true)
    [[ -n "$thread_id" ]] || return "$exit_code"
    turn=$(next_turn)
    printf '%s\n' \
      'Your previous turn ended with a provider-side error, not by your choice. Resume exactly where your todo list left off under the same brief and standing orders, and end with the required REPORT section.' \
      > "$session_dir/turn-$turn.prompt.md"
    run_turn "$turn" "$session_dir/turn-$turn.prompt.md" resume "$thread_id"
    exit_code=$?
  done
  return "$exit_code"
}

case "$command_name" in
  start)
    [[ -n "$workdir" && -n "$brief" ]] || die 'start needs --cd and --brief'
    [[ -n "$df_run" && -n "$df_lane" && -n "$df_repo_root" ]] \
      || die 'start needs --df-run, --df-lane, and --df-repo-root'
    [[ -d "$workdir" ]] || die "no such directory: $workdir"
    [[ -f "$brief" ]] || die "no such brief: $brief"
    workdir=$(cd "$workdir" && pwd -P)
    df_repo_root=$(cd "$df_repo_root" && pwd -P)
    [[ "$brief" == /* ]] || brief=$PWD/$brief
    [[ ! -f "$meta" ]] || die "session '$session_name' already exists; use resume" 2
    [[ -z "$prompt" ]] || die 'start does not accept --prompt'
    [[ "$dangerous_bypass" == 'true' || -z "$sandbox" ]] || case "$sandbox" in
      read-only|workspace-write|danger-full-access) ;;
      *) die "unsupported sandbox mode: $sandbox" ;;
    esac
    [[ -n "$sandbox" ]] || sandbox='workspace-write'
    META_ROLE_TARGET="$(bash "$role_caller" preflight \
      --run "$df_run" --lane "$df_lane" --repo-root "$df_repo_root" \
      --responsibility cross_model_review --allow-kind transport --allow-transport codex-cli \
      | node -e 'const result = JSON.parse(require("fs").readFileSync(0, "utf8")); process.stdout.write(JSON.stringify(result.target));')"
    mkdir -p "$session_dir"
    printf 'META_DIR=%q\nMETA_DF_RUN=%q\nMETA_DF_LANE=%q\nMETA_DF_REPO_ROOT=%q\nMETA_ROLE_TARGET=%q\nMETA_SANDBOX=%q\nMETA_DANGEROUS_BYPASS=%q\nMETA_BRIEF=%q\n' \
      "$workdir" "$df_run" "$df_lane" "$df_repo_root" "$META_ROLE_TARGET" "$sandbox" "$dangerous_bypass" "$brief" > "$meta"
    cp "$brief" "$session_dir/turn-1.prompt.md"
    run_turn_with_retry 1 "$brief" start
    ;;
  resume)
    [[ -n "$prompt" && -f "$prompt" ]] || die 'resume needs --prompt <file>'
    [[ "$prompt" == /* ]] || prompt=$PWD/$prompt
    [[ -z "$workdir" && -z "$brief" ]] || die 'resume does not accept --cd or --brief'
    [[ "$security_option_seen" == 'false' && -z "$df_run$df_lane$df_repo_root" ]] || die 'resume keeps its frozen role and sandbox; those options belong on start'
    load_meta
    assert_idle
    thread_id=$(cat "$session_dir/thread.id" 2>/dev/null || true)
    [[ -n "$thread_id" ]] || die "session '$session_name' has no recorded thread id" 2
    turn=$(next_turn)
    cp "$prompt" "$session_dir/turn-$turn.prompt.md"
    run_turn_with_retry "$turn" "$prompt" resume "$thread_id"
    ;;
  status)
    [[ -z "$workdir$brief$prompt$df_run$df_lane$df_repo_root$sandbox" && "$security_option_seen" == 'false' ]] \
      || die 'status accepts only a session name'
    load_meta
    thread_id=$(cat "$session_dir/thread.id" 2>/dev/null || printf unknown)
    turn=$(( $(next_turn) - 1 ))
    running='no'
    active_wrapper_pid >/dev/null && running='yes'
    printf 'session=%s dir=%s role=%s lane=%s thread=%s turns=%s running=%s\n' \
      "$session_name" "$workdir" "$df_run" "$df_lane" "$thread_id" "$turn" "$running"
    for ((i=1; i<=turn; i++)); do
      printf '  turn %s: exit=%s started=%s last=%s\n' \
        "$i" \
        "$(cat "$session_dir/turn-$i.exit" 2>/dev/null || printf running)" \
        "$(cat "$session_dir/turn-$i.started" 2>/dev/null || true)" \
        "$session_dir/turn-$i.last.md"
    done
    ;;
  transcript)
    [[ -z "$workdir$brief$prompt$df_run$df_lane$df_repo_root$sandbox" && "$security_option_seen" == 'false' ]] \
      || die 'transcript accepts only a session name'
    load_meta
    thread_id=$(cat "$session_dir/thread.id" 2>/dev/null || true)
    [[ -n "$thread_id" ]] || die "session '$session_name' has no recorded thread id" 2
    find "${CODEX_HOME:-${HOME:-/tmp}/.codex}/sessions" -name "*${thread_id}*.jsonl" 2>/dev/null | head -1
    ;;
  *)
    usage
    ;;
esac
