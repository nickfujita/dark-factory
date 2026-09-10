#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TRANSPORT=$SCRIPT_DIR/df-codex-exec.sh
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dark-factory-codex-exec-test.XXXXXX")
trap 'rm -r -- "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local file=$1 expected=$2
  grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

mkdir -p "$tmp/bin" "$tmp/worktree" "$tmp/state" "$tmp/codex-home/sessions" "$tmp/runs/transport-test"
printf 'Complete the bounded unit and end with REPORT.\n' > "$tmp/brief.md"
printf 'Run the next bounded unit and end with REPORT.\n' > "$tmp/prompt.md"
printf 'run_id\tlane\tcreated\tfinish_predicate\tartifact_sha\tbudget_dispatches\tbudget_wall_minutes\tstate\ntransport-test\tstandard\t2026-01-01T00:00:00Z\tfinish\t-\t20\t120\trunning\n' > "$tmp/runs/transport-test/run.tsv"
printf 'seq\tts\trole\tpurpose\tparent_seq\toutcome\n' > "$tmp/runs/transport-test/dispatches.tsv"

cat > "$tmp/fake-role.mjs" <<'NODE'
import { appendFileSync } from 'node:fs';
appendFileSync(process.env.FAKE_TRANSPORT_CALLS, 'preflight\n');
if (process.env.FAKE_ROLE_FAIL === '1') process.exit(7);
if (process.env.FAKE_ROLE_INVALID === '1') {
  process.stdout.write('not-json\n');
  process.exit(0);
}
const target = JSON.parse(process.env.FAKE_ROLE_TARGET || '{"kind":"transport","name":"codex-cli"}');
process.stdout.write(JSON.stringify({ target, validatedNamedAgents: [] }) + '\n');
NODE
cat > "$tmp/fake-state.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  path) printf '%s/%s\n' "$FAKE_TRANSPORT_RUNS" "$2" ;;
  reserve)
    if [[ "${FAKE_RESERVE_FAIL:-0}" == 1 ]]; then exit 3; fi
    if [[ "${FAKE_RESERVE_INVALID:-0}" == 1 ]]; then printf 'invalid-seq\n'; exit 0; fi
    printf 'reserve %s\n' "$2" >> "$FAKE_TRANSPORT_CALLS"
    seq=$(awk -F '\t' 'NR > 1 && $1 + 0 > max { max = $1 + 0 } END { print max + 1 }' "$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv")
    printf '%s\t2026-01-01T00:00:00Z\tcross_model_review\ttest\t-\tpending\n' "$seq" \
      >> "$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv"
    printf '%s\n' "$seq"
    ;;
  complete)
    printf 'complete %s %s\n' "$3" "$4" >> "$FAKE_TRANSPORT_CALLS"
    tmp_file="$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv.tmp.$$"
    awk -F '\t' -v OFS='\t' -v seq="$3" -v outcome="$4" 'NR > 1 && $1 == seq { $6 = outcome } { print }' \
      "$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv" > "$tmp_file"
    mv "$tmp_file" "$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv"
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$tmp/fake-state.sh"

cat > "$tmp/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -u

{
  printf 'CALL'
  for arg in "$@"; do printf '\t%s' "$arg"; done
  printf '\n'
} >> "$FAKE_CODEX_LOG"

out=''
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == '-o' ]]; then
    next=$((i + 1))
    out=${!next}
  fi
done

thread_id=11111111-2222-3333-4444-555555555555
printf '{"type":"thread.started","thread_id":"%s"}\n' "$thread_id"
if [[ ! -e "$FAKE_CODEX_FAILED_ONCE" ]]; then
  : > "$FAKE_CODEX_FAILED_ONCE"
  printf '{"type":"turn.failed","error":{"message":"Selected model is at capacity"}}\n'
  printf 'ERROR: Selected model is at capacity\n' >&2
  exit 1
fi

printf 'REPORT: fake worker completed\n' > "$out"
printf '{"type":"turn.completed"}\n'
FAKE_CODEX
chmod +x "$tmp/bin/codex"

export PATH="$tmp/bin:$PATH"
export CODEX_HOME="$tmp/codex-home"
export DF_CODEX_STATE_ROOT="$tmp/state"
export DF_CODEX_MAX_RETRIES=1
export DF_CODEX_RETRY_SLEEP=0
export FAKE_CODEX_LOG="$tmp/codex.log"
export FAKE_CODEX_FAILED_ONCE="$tmp/failed-once"
export DF_ROLE_CALLER_ROLE_HELPER="$tmp/fake-role.mjs"
export DF_ROLE_CALLER_STATE_HELPER="$tmp/fake-state.sh"
export FAKE_TRANSPORT_RUNS="$tmp/runs"
export FAKE_TRANSPORT_CALLS="$tmp/transport-calls.log"

worker_count() { grep -c '^CALL' "$tmp/codex.log" 2>/dev/null || true; }
reservation_count() { awk 'NR > 1 { count++ } END { print count + 0 }' "$tmp/runs/transport-test/dispatches.tsv"; }
pending_count() { awk -F '\t' 'NR > 1 && $6 == "pending" { count++ } END { print count + 0 }' "$tmp/runs/transport-test/dispatches.tsv"; }

assert_initial_preflight_gate() {
  local name=$1 mode=$2
  local before_workers before_reservations
  before_workers=$(worker_count)
  before_reservations=$(reservation_count)
  if env "$mode"=1 bash "$TRANSPORT" start "$name" \
    --cd "$tmp/worktree" --brief "$tmp/brief.md" \
    --df-run transport-test --df-lane standard --df-repo-root "$tmp/worktree" >/dev/null 2>&1; then
    fail "$name accepted a failed initial preflight"
  fi
  [[ ! -e "$tmp/state/$name" ]] || fail "$name created session metadata after failed initial preflight"
  [[ $(worker_count) == "$before_workers" ]] || fail "$name launched a worker after failed initial preflight"
  [[ $(reservation_count) == "$before_reservations" ]] || fail "$name reserved after failed initial preflight"
  [[ $(pending_count) == 0 ]] || fail "$name left an open reservation"
}

assert_initial_preflight_gate worker-preflight-fail FAKE_ROLE_FAIL
assert_initial_preflight_gate worker-preflight-invalid FAKE_ROLE_INVALID

if bash "$TRANSPORT" start '../escape' --cd "$tmp/worktree" --brief "$tmp/brief.md" \
  --df-run transport-test --df-lane standard --df-repo-root "$tmp/worktree" >/dev/null 2>&1; then
  fail 'unsafe session name was accepted'
fi

bash "$TRANSPORT" start worker-a \
  --cd "$tmp/worktree" \
  --brief "$tmp/brief.md" \
  --df-run transport-test --df-lane standard --df-repo-root "$tmp/worktree" > "$tmp/start.out" 2> "$tmp/start.err"

[[ $(cat "$tmp/state/worker-a/turn-1.exit") == 1 ]] || fail 'first provider-failed turn was not recorded'
[[ $(cat "$tmp/state/worker-a/turn-2.exit") == 0 ]] || fail 'provider retry did not complete'
[[ $(cat "$tmp/state/worker-a/thread.id") == 11111111-2222-3333-4444-555555555555 ]] \
  || fail 'thread id was not recorded'
assert_file_contains "$tmp/state/worker-a/meta" 'META_SANDBOX=workspace-write'
assert_file_contains "$tmp/codex.log" $'\t--sandbox\tworkspace-write'
assert_file_contains "$tmp/codex.log" $'\tresume\t11111111-2222-3333-4444-555555555555\t-'
assert_file_contains "$tmp/start.err" 'provider failure on turn 1'

bash "$TRANSPORT" resume worker-a --prompt "$tmp/prompt.md" > "$tmp/resume.out"
[[ $(cat "$tmp/state/worker-a/turn-3.exit") == 0 ]] || fail 'manual resume did not complete'

assert_resume_gate() {
  local label=$1
  shift
  local before_workers before_reservations next_turn
  before_workers=$(worker_count)
  before_reservations=$(reservation_count)
  next_turn=4
  if env "$@" bash "$TRANSPORT" resume worker-a --prompt "$tmp/prompt.md" >/dev/null 2>&1; then
    fail "$label was accepted"
  fi
  [[ $(worker_count) == "$before_workers" ]] || fail "$label launched a worker"
  [[ $(reservation_count) == "$before_reservations" ]] || fail "$label made a reservation"
  [[ $(pending_count) == 0 ]] || fail "$label left an open reservation"
  [[ ! -e "$tmp/state/worker-a/turn-$next_turn.pid" ]] || fail "$label wrote a turn pid"
  [[ ! -e "$tmp/state/worker-a/turn-$next_turn.started" ]] || fail "$label wrote a turn start timestamp"
}

assert_resume_gate 'failed resume preflight' FAKE_ROLE_FAIL=1
assert_resume_gate 'failed resume reservation' FAKE_RESERVE_FAIL=1
assert_resume_gate 'invalid resume reservation receipt' FAKE_RESERVE_INVALID=1

cp "$tmp/state/worker-a/meta" "$tmp/state/worker-a/meta.saved"
sed 's#^META_ROLE_TARGET=.*#META_ROLE_TARGET=\\{\\\"kind\\\":\\\"transport\\\"\\,\\\"name\\\":\\\"other\\\"\\}#' \
  "$tmp/state/worker-a/meta.saved" > "$tmp/state/worker-a/meta"
assert_resume_gate 'frozen target mismatch'
mv "$tmp/state/worker-a/meta.saved" "$tmp/state/worker-a/meta"

bash "$TRANSPORT" status worker-a > "$tmp/status.out"
assert_file_contains "$tmp/status.out" 'turns=3 running=no'

: > "$tmp/codex-home/sessions/rollout-11111111-2222-3333-4444-555555555555.jsonl"
transcript=$(bash "$TRANSPORT" transcript worker-a)
[[ "$transcript" == "$tmp/codex-home/sessions/rollout-11111111-2222-3333-4444-555555555555.jsonl" ]] \
  || fail 'transcript did not honor CODEX_HOME'

if bash "$TRANSPORT" resume worker-a --prompt "$tmp/prompt.md" --sandbox read-only >/dev/null 2>&1; then
  fail 'resume accepted a sandbox-mode change'
fi

bash "$TRANSPORT" start worker-b \
  --cd "$tmp/worktree" \
  --brief "$tmp/brief.md" \
  --df-run transport-test --df-lane standard --df-repo-root "$tmp/worktree" \
  --dangerously-bypass-approvals-and-sandbox > "$tmp/bypass.out"
assert_file_contains "$tmp/state/worker-b/meta" 'META_DANGEROUS_BYPASS=true'
tail -1 "$tmp/codex.log" | grep -Fq $'\t--dangerously-bypass-approvals-and-sandbox\t-' \
  || fail 'explicit dangerous bypass was not passed to Codex'

[[ "$(grep -c '^reserve ' "$tmp/transport-calls.log")" == 4 ]] \
  || fail 'every durable turn, including a provider retry, reserved once'
[[ "$(grep -c '^complete ' "$tmp/transport-calls.log")" == 4 ]] \
  || fail 'every durable turn, including a provider retry, closed its reservation'

for field in META_DIR META_DF_RUN META_DF_LANE META_DF_REPO_ROOT META_ROLE_TARGET; do
  session="missing-${field#META_}"
  session=${session,,}
  mkdir -p "$tmp/state/$session"
  grep -v "^$field=" "$tmp/state/worker-a/meta" > "$tmp/state/$session/meta"
  printf '11111111-2222-3333-4444-555555555555\n' > "$tmp/state/$session/thread.id"
  before_workers=$(worker_count)
  before_reservations=$(reservation_count)
  if bash "$TRANSPORT" resume "$session" --prompt "$tmp/prompt.md" > "$tmp/$session.out" 2> "$tmp/$session.err"; then
    fail "session missing $field was resumed"
  fi
  assert_file_contains "$tmp/$session.err" "has no $field; start a new session"
  [[ $(worker_count) == "$before_workers" ]] || fail "session missing $field launched a worker"
  [[ $(reservation_count) == "$before_reservations" ]] || fail "session missing $field reserved a dispatch"
done

[[ $(pending_count) == 0 ]] || fail 'durable transport left an open reservation'

printf 'PASS: Claude-to-Codex transport start, retry, resume, status, transcript, sandbox, and frozen-role contracts\n'
