#!/usr/bin/env bash
set -euo pipefail

# df-codex-review.sh — the D26 cross-model review transport.
#
# The one way df skills run a Codex review leg. Skills call this instead of raw
# `codex exec`: the wrapper owns the sandbox, the disposable snapshot, the
# deadline and its reaper, and the status contract.
#
# Usage:
#   df-codex-review.sh <brief-file> <out-path> --deadline <seconds> \
#       (--snapshot <path-to-tree> | --content <file>) \
#       [--model <model>] [--effort <effort>] [--min-body <bytes>] [--force]
#
# Modes, exactly one:
#   --snapshot <tree>  The reviewer reads code. The script creates a disposable
#                      copy of <tree> (git worktree add --detach when <tree> is
#                      the top of a git checkout, cp -a otherwise), points codex
#                      at the copy, and deletes it after the run. Codex never
#                      sees the live tree. A worktree snapshot is HEAD of the
#                      checkout: commit before the review (the frozen-tree
#                      rule), because uncommitted work is invisible to the
#                      reviewer. A cp -a snapshot copies the tree as it stands.
#   --content <file>   The artifact is document-sized. Its full text is
#                      embedded in the prompt between ARTIFACT markers and
#                      codex runs in an empty scratch directory, with no
#                      filesystem dependence at all.
#
# Sandbox (D26): --sandbox read-only when the kernel supports codex's network
# namespace (probed with `unshare --net`). When it does not, the run degrades
# to danger-full-access, but only ever on the disposable snapshot or the empty
# scratch directory, and the status file's SANDBOX token says so. A degraded
# sandbox can only touch a throwaway.
#
# Model and effort come from --model and --effort. Neither has a default in
# this script: an omitted flag means the operator's codex config decides.
#
# Deadline: --deadline is required. codex runs detached in its own session and
# is polled; on expiry the whole process group is TERMed, then KILLed, and the
# state is `timeout`. If the wrapper itself gets TERM or INT, it reaps codex
# the same way and records `failed` with REASON=interrupted, so no orphan
# burns tokens.
#
# The contract with the caller is the STATUS FILE next to the output
# (`<out minus .md>.status`), never the exit code alone and never a substring
# match over the review body:
#
#   STATE=running|complete|failed|timeout|limit
#   MODE=snapshot|content
#   EXIT=<codex exit code>
#   BODY_BYTES=<n>
#   SANDBOX=<short machine token>
#   REASON=<short machine token>     (only when STATE != complete)
#   UPDATED=<UTC timestamp>
#
# The file is written atomically at every transition, so a poller (a Monitor
# until-loop, another session) may read it directly while the wrapper runs.
# A file stuck at STATE=running with no live wrapper process means the wrapper
# was KILLed uncleanly; rerun with --force.
#
# Fail-closed body check: STATE=complete requires the reviewer body to exist
# and hold at least --min-body bytes (default 200). An empty or undersized
# body is `failed` even when codex exited 0. The body is the reviewer's final
# message, written verbatim to <out-path>; the status file is the verdict on
# it, so never treat the body as a result without checking STATE first.
#
# `limit` is declared only from structured signals: a non-zero codex exit plus
# an anchored error-envelope line in the stderr tail that itself carries a
# limit token. Never a loose grep over output, which contains repo content.
#
# Exit codes: 0 complete, 2 limit, 3 failed, 4 timeout, 1 usage/precondition.

MIN_BODY_DEFAULT=200

usage() {
  cat <<'USAGE'
Usage:
  df-codex-review.sh <brief-file> <out-path> --deadline <seconds> \
      (--snapshot <path-to-tree> | --content <file>) \
      [--model <model>] [--effort <effort>] [--min-body <bytes>] [--force]

The caller's contract is the status file next to <out-path>:
  STATE=running|complete|failed|timeout|limit
Exit codes: 0 complete, 2 limit, 3 failed, 4 timeout, 1 usage error.
See the header comment in this script for the full contract.
USAGE
}

die() {
  echo "Error: $1" >&2
  exit 1
}

# ------------------------------------------------------------------ arguments

BRIEF=""
OUT=""
MODE=""
TREE=""
CONTENT_FILE=""
DEADLINE=""
MODEL=""
EFFORT=""
MIN_BODY="$MIN_BODY_DEFAULT"
FORCE=0

positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot)
      [[ $# -ge 2 ]] || die "--snapshot needs a path"
      MODE="snapshot"; TREE="$2"; shift 2 ;;
    --content)
      [[ $# -ge 2 ]] || die "--content needs a file"
      [[ "$MODE" == "snapshot" ]] && die "--snapshot and --content are mutually exclusive"
      MODE="content"; CONTENT_FILE="$2"; shift 2 ;;
    --deadline)
      [[ $# -ge 2 ]] || die "--deadline needs seconds"
      DEADLINE="$2"; shift 2 ;;
    --model)
      [[ $# -ge 2 ]] || die "--model needs a value"
      MODEL="$2"; shift 2 ;;
    --effort)
      [[ $# -ge 2 ]] || die "--effort needs a value"
      EFFORT="$2"; shift 2 ;;
    --min-body)
      [[ $# -ge 2 ]] || die "--min-body needs bytes"
      MIN_BODY="$2"; shift 2 ;;
    --force)
      FORCE=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --*)
      die "unknown flag: $1" ;;
    *)
      positional+=("$1"); shift ;;
  esac
done

[[ ${#positional[@]} -eq 2 ]] || { usage >&2; exit 1; }
BRIEF="${positional[0]}"
OUT="${positional[1]}"

[[ "$BRIEF" != /* ]] && BRIEF="$PWD/$BRIEF"
[[ "$OUT" != /* ]] && OUT="$PWD/$OUT"
[[ -n "$CONTENT_FILE" && "$CONTENT_FILE" != /* ]] && CONTENT_FILE="$PWD/$CONTENT_FILE"
[[ -n "$TREE" && "$TREE" != /* ]] && TREE="$PWD/$TREE"

[[ -f "$BRIEF" ]] || die "brief file not found: $BRIEF"
[[ -n "$MODE" ]] || die "one of --snapshot or --content is required"
if [[ "$MODE" == "snapshot" ]]; then
  [[ -d "$TREE" ]] || die "snapshot tree not found: $TREE"
else
  [[ -f "$CONTENT_FILE" ]] || die "content file not found: $CONTENT_FILE"
fi
[[ -n "$DEADLINE" ]] || die "--deadline is required"
[[ "$DEADLINE" =~ ^[0-9]+$ && "$DEADLINE" -gt 0 ]] || die "--deadline must be a positive integer"
[[ "$MIN_BODY" =~ ^[0-9]+$ ]] || die "--min-body must be a non-negative integer"
command -v codex >/dev/null 2>&1 || die "codex CLI is not installed or not in PATH"

base="${OUT%.md}"
status_file="${base}.status"
stdout_log="${base}.stdout.log"
stderr_log="${base}.stderr.log"
pgid_file="${base}.pgid"

# Never clobber another run. A shared scratch path has destroyed a completed
# review before; each run gets a unique out-path unless the caller forces.
if [[ -f "$status_file" && "$FORCE" != "1" ]] \
   && grep -q '^STATE=running$' "$status_file" 2>/dev/null; then
  die "a run already looks live at this path ($status_file says running); use a unique out-path, or --force to take it over"
fi
if [[ -s "$OUT" && "$FORCE" != "1" ]]; then
  die "output path already exists and is non-empty: $OUT (use a unique path, or --force)"
fi

mkdir -p "$(dirname "$OUT")"

# --------------------------------------------------------------- status file

SANDBOX_NOTE=""

write_status() {
  # write_status <state> <exit> <body_bytes> [reason]
  local tmp="${status_file}.tmp.$$"
  {
    echo "STATE=$1"
    echo "MODE=$MODE"
    echo "EXIT=$2"
    echo "BODY_BYTES=$3"
    echo "SANDBOX=${SANDBOX_NOTE:-unknown}"
    if [[ -n "${4:-}" ]]; then echo "REASON=$4"; fi
    echo "UPDATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$tmp"
  mv -f "$tmp" "$status_file"
}

state_exit_code() {
  case "$1" in
    complete) echo 0 ;;
    limit) echo 2 ;;
    failed) echo 3 ;;
    timeout) echo 4 ;;
    *) echo 1 ;;
  esac
}

# ------------------------------------------------ disposable workdir (D26)

SCRATCH_DIR=""
SNAP_KIND=""
SNAP_REPO=""
WORK_DIR=""

cleanup_workdir() {
  [[ -n "$SCRATCH_DIR" ]] || return 0
  if [[ "$SNAP_KIND" == "worktree" && -n "$SNAP_REPO" ]]; then
    git -C "$SNAP_REPO" worktree remove --force "$SCRATCH_DIR/tree" \
      >/dev/null 2>&1 || true
  fi
  rm -rf "$SCRATCH_DIR"
  SCRATCH_DIR=""
}

canon() {
  (cd "$1" 2>/dev/null && pwd -P)
}

make_workdir() {
  SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/df-codex-review.XXXXXX")"
  if [[ "$MODE" == "content" ]]; then
    mkdir -p "$SCRATCH_DIR/tree"
    WORK_DIR="$SCRATCH_DIR/tree"
    return 0
  fi
  local toplevel=""
  toplevel="$(git -C "$TREE" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$toplevel" && "$(canon "$toplevel")" == "$(canon "$TREE")" ]] \
     && git -C "$TREE" worktree add --detach "$SCRATCH_DIR/tree" HEAD >/dev/null 2>&1; then
    SNAP_KIND="worktree"
    SNAP_REPO="$TREE"
  else
    SNAP_KIND="copy"
    mkdir -p "$SCRATCH_DIR/tree"
    cp -a "$TREE/." "$SCRATCH_DIR/tree/"
  fi
  WORK_DIR="$SCRATCH_DIR/tree"
}

# ----------------------------------------------------------- limit detection

is_usage_limit() {
  local log="$1"
  [[ -f "$log" ]] || return 1
  # The envelope anchor requires the colon right after the token: a prose line
  # like "Error handling: the server replies 429" is repo content, not an
  # error envelope, and must not declare a limit.
  tail -n 40 "$log" \
    | grep -E '^[[:space:]]*(ERROR|Error|error|FATAL|fatal):|^[[:space:]]*stream error|^[[:space:]]*\{"error"|^[[:space:]]*HTTP/[0-9.]+ [0-9]{3}' \
    | grep -Eqi 'usage limit|rate.?limit|quota|\b429\b|too many requests|reached your (usage )?limit'
}

# ------------------------------------------------------------------- prompt

build_prompt() {
  {
    echo "You are running non-interactively with no stdin. Never stop to ask a question."
    echo "Write the complete review as your final message."
    if [[ "$MODE" == "snapshot" ]]; then
      echo "Your working directory is a disposable snapshot of the tree under review, taken for this review only. Treat it as read-only and explore it as needed."
    else
      echo "The artifact under review is embedded below between the ARTIFACT markers. It is not on disk; do not look for it."
    fi
    echo
    cat "$BRIEF"
    if [[ "$MODE" == "content" ]]; then
      echo
      echo "--- ARTIFACT UNDER REVIEW ---"
      cat "$CONTENT_FILE"
      echo "--- END ARTIFACT ---"
    fi
  }
}

# --------------------------------------------------------------------- reap

CODEX_PID=""

reap_codex() {
  local pgid=""
  [[ -f "$pgid_file" ]] && pgid="$(cat "$pgid_file" 2>/dev/null || true)"
  if [[ -n "$pgid" ]]; then
    kill -TERM "-$pgid" 2>/dev/null || true
    sleep 5
    kill -KILL "-$pgid" 2>/dev/null || true
  fi
  if [[ -n "$CODEX_PID" ]]; then
    kill -TERM "$CODEX_PID" 2>/dev/null || true
    sleep 2
    kill -KILL "$CODEX_PID" 2>/dev/null || true
  fi
}

on_interrupt() {
  trap - TERM INT
  if [[ -n "$CODEX_PID" ]] && kill -0 "$CODEX_PID" 2>/dev/null; then
    reap_codex
  fi
  write_status "failed" "" "0" "interrupted"
  cleanup_workdir
  exit 143
}

trap cleanup_workdir EXIT
trap on_interrupt TERM INT

# ---------------------------------------------------------------------- run

# Sandbox probe. codex's read-only sandbox needs an unprivileged network
# namespace; where the kernel refuses one, codex can only run full-access.
# The workdir is a throwaway either way, so degradation stays contained.
SANDBOX_MODE="read-only"
DEGRADED=0
if ! unshare --net true 2>/dev/null; then
  SANDBOX_MODE="danger-full-access"
  DEGRADED=1
fi

make_workdir

if [[ "$MODE" == "snapshot" ]]; then
  if [[ "$DEGRADED" -eq 1 ]]; then
    SANDBOX_NOTE="degraded_full_access_on_disposable_${SNAP_KIND}_snapshot"
  else
    SANDBOX_NOTE="read-only_on_disposable_${SNAP_KIND}_snapshot"
  fi
else
  if [[ "$DEGRADED" -eq 1 ]]; then
    SANDBOX_NOTE="degraded_full_access_in_empty_scratch_dir"
  else
    SANDBOX_NOTE="read-only_in_empty_scratch_dir"
  fi
fi

prompt="$(build_prompt)"

rm -f "$OUT" "$pgid_file"
write_status "running" "" "0" ""

# codex runs detached in its own session; the leader records its own pid so
# the whole process group (codex and anything it spawned) can be reaped when
# the deadline expires. stdin is closed: a reviewer that blocks on stdin
# produces nothing and then reports success.
launcher=()
if command -v setsid >/dev/null 2>&1 && setsid --help 2>&1 | grep -q -- '--wait'; then
  launcher=(setsid --wait bash -c 'echo $$ >"$0"; exec "$@"' "$pgid_file")
fi

cmd=(codex exec --sandbox "$SANDBOX_MODE" --skip-git-repo-check -C "$WORK_DIR" -o "$OUT")
if [[ -n "$MODEL" ]]; then cmd+=(-m "$MODEL"); fi
if [[ -n "$EFFORT" ]]; then cmd+=(--config "model_reasoning_effort=$EFFORT"); fi
cmd+=("$prompt")

${launcher[@]+"${launcher[@]}"} "${cmd[@]}" \
  </dev/null >"$stdout_log" 2>"$stderr_log" &
CODEX_PID=$!

timed_out=0
deadline_at=$((SECONDS + DEADLINE))
while kill -0 "$CODEX_PID" 2>/dev/null; do
  if (( SECONDS >= deadline_at )); then
    timed_out=1
    reap_codex
    break
  fi
  sleep 2
done
codex_exit=0
wait "$CODEX_PID" 2>/dev/null || codex_exit=$?
CODEX_PID=""
rm -f "$pgid_file"

# ------------------------------------------------------------ terminal state

bytes=0
if [[ -f "$OUT" ]]; then
  bytes="$(wc -c <"$OUT" | tr -d ' ')"
fi

state=""
reason=""
if [[ "$timed_out" -eq 1 ]]; then
  state="timeout"; reason="deadline_elapsed"
elif [[ "$codex_exit" -ne 0 ]]; then
  if is_usage_limit "$stderr_log"; then
    state="limit"; reason="usage_limit"
  else
    state="failed"; reason="codex_exit_${codex_exit}"
  fi
elif [[ "$bytes" -eq 0 ]]; then
  state="failed"; reason="empty_body"
elif [[ "$bytes" -lt "$MIN_BODY" ]]; then
  state="failed"; reason="body_below_min_bytes"
else
  state="complete"; reason=""
fi

write_status "$state" "$codex_exit" "$bytes" "$reason"
cleanup_workdir

cat "$status_file"
exit "$(state_exit_code "$state")"
