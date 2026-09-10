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
process.stdout.write(JSON.stringify({ target: { kind: 'transport', name: 'codex-cli' }, validatedNamedAgents: [] }) + '\n');
NODE
cat > "$tmp/fake-state.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  path) printf '%s/%s\n' "$FAKE_TRANSPORT_RUNS" "$2" ;;
  reserve)
    printf 'reserve %s\n' "$2" >> "$FAKE_TRANSPORT_CALLS"
    awk 'END { print NR }' "$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv" >> "$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv"
    awk 'END { print NR - 1 }' "$FAKE_TRANSPORT_RUNS/$2/dispatches.tsv"
    ;;
  complete) printf 'complete %s %s\n' "$3" "$4" >> "$FAKE_TRANSPORT_CALLS" ;;
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

mkdir -p "$tmp/state/legacy-worker"
cat > "$tmp/state/legacy-worker/meta" <<LEGACY_META
META_DIR=$tmp/worktree
META_MODEL=gpt-test
META_EFFORT=high
META_BRIEF=$tmp/brief.md
LEGACY_META
printf '11111111-2222-3333-4444-555555555555\n' > "$tmp/state/legacy-worker/thread.id"
if bash "$TRANSPORT" resume legacy-worker --prompt "$tmp/prompt.md" > "$tmp/legacy.out" 2> "$tmp/legacy.err"; then
  fail 'legacy session without a frozen role identity was resumed'
fi
assert_file_contains "$tmp/legacy.err" 'has no frozen role identity; start a new session'

printf 'PASS: Claude-to-Codex transport start, retry, resume, status, transcript, sandbox, and frozen-role contracts\n'
