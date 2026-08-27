#!/usr/bin/env bash
# df-state.sh: the D24 run-state store for Dark Factory runs.
#
# One authoritative state directory per run, under .dark-factory/runs/<run-id>/
# (override the root with DF_STATE_ROOT). Every dispatch is reserved here
# BEFORE it spawns. A refused reservation means the dispatch does not happen.
# A nested dispatch reserves with its parent's seq and draws from the same
# per-run budget. Budget exhaustion is a stop, not a flag: reserve records
# stopped-budget in the store and refuses.
#
# Schema and rules: references/run-state-schema.md (version 1).
#
# Subcommands:
#   init     <run-id> <lane> <budget-dispatches> <budget-wall-minutes> <finish-predicate...>
#   reserve  <run-id> <role> <purpose> [parent-seq]     prints the granted seq
#   complete <run-id> <seq> ok|failed|expired
#   status   <run-id>
#   stop     <run-id> done|budget|operator
#
# Exit codes: 0 success, 1 usage or argument error, 2 unknown run or seq,
# 3 reservation refused, 4 outcome already recorded differently, 5 lock
# acquisition timed out.
#
# Dependencies: bash and coreutils only. All writes happen under the run's
# mkdir lock and land via temp file + atomic mv, so a lock-free reader always
# sees a complete file.

set -u

ROOT=${DF_STATE_ROOT:-$PWD/.dark-factory/runs}
LOCK_WAIT_SECS=${DF_STATE_LOCK_WAIT:-10}
NO_OWNER_GRACE_SECS=5
LOCKED_DIR=""

die() { # message [exit-code]
  printf 'df-state: %s\n' "$1" >&2
  exit "${2:-1}"
}

on_exit() {
  if [ -n "$LOCKED_DIR" ]; then
    rm -f "$LOCKED_DIR/lock/owner"
    rmdir "$LOCKED_DIR/lock" 2>/dev/null
  fi
}
trap on_exit EXIT

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# TSV fields must never contain a tab or newline. Replace with spaces.
sanitize() { printf '%s' "$1" | tr '\t\n\r' '   '; }

run_dir_of() { printf '%s/%s' "$ROOT" "$1"; }

require_run() { # run-id -> echoes the run dir, exits 2 when absent
  local dir
  dir=$(run_dir_of "$1")
  [ -f "$dir/run.tsv" ] || die "unknown run '$1' (no $dir/run.tsv)" 2
  printf '%s' "$dir"
}

pid_alive() {
  kill -0 "$1" 2>/dev/null && return 0
  [ -d "/proc/$1" ]
}

reclaim_stale() { # run-dir. Rename first so only one contender wins.
  local stale="$1/lock.stale.$$"
  if mv "$1/lock" "$stale" 2>/dev/null; then
    rm -f "$stale/owner"
    rmdir "$stale" 2>/dev/null
  fi
}

lock_acquire() { # run-dir. Returns 1 on bounded-wait timeout.
  local dir=$1/lock deadline owner_pid age
  deadline=$(( $(date +%s) + LOCK_WAIT_SECS ))
  while :; do
    if mkdir "$dir" 2>/dev/null; then
      LOCKED_DIR=$1
      printf 'pid=%s\tts=%s\n' "$$" "$(now_iso)" > "$dir/owner"
      return 0
    fi
    owner_pid=""
    [ -f "$dir/owner" ] && \
      owner_pid=$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$dir/owner" 2>/dev/null | head -n 1)
    if [ -n "$owner_pid" ]; then
      if ! pid_alive "$owner_pid"; then
        reclaim_stale "$1"
        continue
      fi
    else
      # mkdir raced ahead of the owner write, or the holder died between the
      # two. Give the write a grace period, then treat the lock as stale.
      age=$(( $(date +%s) - $(stat -c %Y "$dir" 2>/dev/null || date +%s) ))
      if [ "$age" -ge "$NO_OWNER_GRACE_SECS" ]; then
        reclaim_stale "$1"
        continue
      fi
    fi
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 0.05
  done
}

lock_release() {
  if [ -n "$LOCKED_DIR" ]; then
    rm -f "$LOCKED_DIR/lock/owner"
    rmdir "$LOCKED_DIR/lock" 2>/dev/null
    LOCKED_DIR=""
  fi
}

run_field() { # run-dir column-name
  awk -F'\t' -v col="$2" '
    NR==1 { for (i = 1; i <= NF; i++) if ($i == col) c = i }
    NR==2 { if (c) print $c }
  ' "$1/run.tsv"
}

set_state() { # run-dir new-state. Caller holds the lock.
  local tmp=$1/run.tsv.tmp.$$
  awk -F'\t' -v OFS='\t' -v st="$2" '
    NR==1 { for (i = 1; i <= NF; i++) if ($i == "state") c = i; print; next }
    NR==2 { $c = st; print }
  ' "$1/run.tsv" > "$tmp"
  mv "$tmp" "$1/run.tsv"
}

append_row() { # file row. Caller holds the lock.
  local tmp=$1.tmp.$$
  cat "$1" > "$tmp"
  printf '%s\n' "$2" >> "$tmp"
  mv "$tmp" "$1"
}

dispatch_field() { # run-dir seq column-index
  awk -F'\t' -v s="$2" -v c="$3" 'NR>1 && $1 == s { print $c }' "$1/dispatches.tsv"
}

cmd_init() {
  [ $# -ge 5 ] || die "usage: df-state.sh init <run-id> <lane> <budget-dispatches> <budget-wall-minutes> <finish-predicate...>"
  local run_id=$1 lane=$2 bd=$3 bw=$4
  shift 4
  local fp=$*
  case $run_id in ''|*[!A-Za-z0-9._-]*) die "run-id must match [A-Za-z0-9._-]+" ;; esac
  [ -n "$lane" ] || die "lane must not be empty"
  case $bd in ''|*[!0-9]*) die "budget-dispatches must be a positive integer" ;; esac
  case $bw in ''|*[!0-9]*) die "budget-wall-minutes must be a positive integer" ;; esac
  [ "$bd" -ge 1 ] || die "budget-dispatches must be at least 1"
  [ "$bw" -ge 1 ] || die "budget-wall-minutes must be at least 1"
  [ -n "$fp" ] || die "finish-predicate must not be empty"
  local dir
  dir=$(run_dir_of "$run_id")
  [ -e "$dir" ] && die "run '$run_id' already exists at $dir"
  local sha
  sha=${DF_ARTIFACT_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}
  [ -n "$sha" ] || sha='-'
  mkdir -p "$dir"
  local tmp=$dir/run.tsv.tmp.$$
  {
    printf 'run_id\tlane\tcreated\tfinish_predicate\tartifact_sha\tbudget_dispatches\tbudget_wall_minutes\tstate\n'
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\trunning\n' \
      "$run_id" "$(sanitize "$lane")" "$(now_iso)" "$(sanitize "$fp")" \
      "$(sanitize "$sha")" "$bd" "$bw"
  } > "$tmp"
  mv "$tmp" "$dir/run.tsv"
  printf 'seq\tts\trole\tpurpose\tparent_seq\toutcome\n' > "$dir/dispatches.tsv.tmp.$$"
  mv "$dir/dispatches.tsv.tmp.$$" "$dir/dispatches.tsv"
  printf 'ts\tstage\tfinding_id\tdisposition\tnote\n' > "$dir/dispositions.tsv.tmp.$$"
  mv "$dir/dispositions.tsv.tmp.$$" "$dir/dispositions.tsv"
  printf 'initialized run %s (lane %s, budget %s dispatches / %s wall minutes)\n' \
    "$run_id" "$lane" "$bd" "$bw" >&2
}

cmd_reserve() {
  { [ $# -ge 3 ] && [ $# -le 4 ]; } || die "usage: df-state.sh reserve <run-id> <role> <purpose> [parent-seq]"
  local run_id=$1 role=$2 purpose=$3 parent=${4:--}
  [ -n "$role" ] || die "role must not be empty"
  [ -n "$purpose" ] || die "purpose must not be empty"
  if [ "$parent" != "-" ]; then
    case $parent in ''|*[!0-9]*) die "parent-seq must be a seq number or -" ;; esac
  fi
  local dir
  dir=$(require_run "$run_id") || exit $?
  lock_acquire "$dir" || die "could not acquire the run lock within ${LOCK_WAIT_SECS}s" 5
  local state
  state=$(run_field "$dir" state)
  case $state in
    done|stopped-budget|stopped-operator)
      die "reservation refused. run '$run_id' is terminal (state $state). do not spawn." 3 ;;
    paused)
      die "reservation refused. run '$run_id' is paused. do not spawn." 3 ;;
    running) : ;;
    *) die "run '$run_id' has unknown state '$state'. refusing to touch it." ;;
  esac
  if [ "$parent" != "-" ]; then
    [ -n "$(dispatch_field "$dir" "$parent" 1)" ] || \
      die "parent-seq $parent does not exist in run '$run_id'"
  fi
  local bd count
  bd=$(run_field "$dir" budget_dispatches)
  count=$(awk 'NR>1 { n++ } END { print n+0 }' "$dir/dispatches.tsv")
  if [ "$count" -ge "$bd" ]; then
    set_state "$dir" stopped-budget
    die "reservation refused. dispatch budget exhausted ($count of $bd reserved). run '$run_id' is now stopped-budget. do not spawn." 3
  fi
  local bw created created_epoch elapsed_min
  bw=$(run_field "$dir" budget_wall_minutes)
  created=$(run_field "$dir" created)
  created_epoch=$(date -d "$created" +%s 2>/dev/null || echo "")
  if [ -n "$created_epoch" ]; then
    elapsed_min=$(( ( $(date +%s) - created_epoch ) / 60 ))
    if [ "$elapsed_min" -ge "$bw" ]; then
      set_state "$dir" stopped-budget
      die "reservation refused. wall-clock budget exhausted (${elapsed_min} of ${bw} minutes). run '$run_id' is now stopped-budget. do not spawn." 3
    fi
  fi
  local seq
  seq=$(awk -F'\t' 'NR>1 && $1+0 > m { m = $1+0 } END { print m+1 }' "$dir/dispatches.tsv")
  append_row "$dir/dispatches.tsv" "$(printf '%s\t%s\t%s\t%s\t%s\tpending' \
    "$seq" "$(now_iso)" "$(sanitize "$role")" "$(sanitize "$purpose")" "$parent")"
  lock_release
  printf '%s\n' "$seq"
}

cmd_complete() {
  [ $# -eq 3 ] || die "usage: df-state.sh complete <run-id> <seq> ok|failed|expired"
  local run_id=$1 seq=$2 outcome=$3
  case $seq in ''|*[!0-9]*) die "seq must be a number" ;; esac
  case $outcome in ok|failed|expired) : ;; *) die "outcome must be ok, failed, or expired" ;; esac
  local dir
  dir=$(require_run "$run_id") || exit $?
  lock_acquire "$dir" || die "could not acquire the run lock within ${LOCK_WAIT_SECS}s" 5
  local current
  current=$(dispatch_field "$dir" "$seq" 6)
  [ -n "$current" ] || die "no dispatch with seq $seq in run '$run_id'" 2
  if [ "$current" = "$outcome" ]; then
    lock_release
    printf 'seq %s already %s. no change.\n' "$seq" "$outcome" >&2
    return 0
  fi
  [ "$current" = "pending" ] || \
    die "seq $seq already has outcome '$current'. a recorded outcome never changes." 4
  local tmp=$dir/dispatches.tsv.tmp.$$
  awk -F'\t' -v OFS='\t' -v s="$seq" -v o="$outcome" '
    NR>1 && $1 == s { $6 = o }
    { print }
  ' "$dir/dispatches.tsv" > "$tmp"
  mv "$tmp" "$dir/dispatches.tsv"
  lock_release
  printf 'seq %s recorded %s\n' "$seq" "$outcome" >&2
}

cmd_status() {
  [ $# -eq 1 ] || die "usage: df-state.sh status <run-id>"
  local dir
  dir=$(require_run "$1") || exit $?
  cat "$dir/run.tsv"
  printf '\n'
  local bd bw created counts n pend ok failed expired
  bd=$(run_field "$dir" budget_dispatches)
  bw=$(run_field "$dir" budget_wall_minutes)
  created=$(run_field "$dir" created)
  counts=$(awk -F'\t' 'NR>1 { n++; c[$6]++ }
    END { printf "%d %d %d %d %d", n+0, c["pending"]+0, c["ok"]+0, c["failed"]+0, c["expired"]+0 }' \
    "$dir/dispatches.tsv")
  read -r n pend ok failed expired <<EOF
$counts
EOF
  local created_epoch elapsed_min
  created_epoch=$(date -d "$created" +%s 2>/dev/null || echo "")
  if [ -n "$created_epoch" ]; then
    elapsed_min=$(( ( $(date +%s) - created_epoch ) / 60 ))
  else
    elapsed_min='-'
  fi
  printf 'reserved\t%s/%s\n' "$n" "$bd"
  printf 'pending\t%s\n' "$pend"
  printf 'ok\t%s\n' "$ok"
  printf 'failed\t%s\n' "$failed"
  printf 'expired\t%s\n' "$expired"
  printf 'budget_remaining\t%s\n' "$((bd - n))"
  printf 'elapsed_minutes\t%s/%s\n' "$elapsed_min" "$bw"
}

cmd_stop() {
  [ $# -eq 2 ] || die "usage: df-state.sh stop <run-id> done|budget|operator"
  local run_id=$1 target
  case $2 in
    done) target=done ;;
    budget|stopped-budget) target=stopped-budget ;;
    operator|stopped-operator) target=stopped-operator ;;
    *) die "reason must be done, budget, or operator" ;;
  esac
  local dir
  dir=$(require_run "$run_id") || exit $?
  lock_acquire "$dir" || die "could not acquire the run lock within ${LOCK_WAIT_SECS}s" 5
  local state
  state=$(run_field "$dir" state)
  set_state "$dir" "$target"
  lock_release
  printf 'run %s: %s -> %s\n' "$run_id" "$state" "$target" >&2
}

main() {
  [ $# -ge 1 ] || die "usage: df-state.sh init|reserve|complete|status|stop ..."
  local cmd=$1
  shift
  case $cmd in
    init)     cmd_init "$@" ;;
    reserve)  cmd_reserve "$@" ;;
    complete) cmd_complete "$@" ;;
    status)   cmd_status "$@" ;;
    stop)     cmd_stop "$@" ;;
    *) die "unknown subcommand '$cmd'. subcommands: init reserve complete status stop" ;;
  esac
}

main "$@"
