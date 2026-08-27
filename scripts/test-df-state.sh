#!/usr/bin/env bash
# D24 acceptance test for scripts/df-state.sh.
#
# Covers, against a throwaway DF_STATE_ROOT:
#   1. concurrent reservation: 8 racing reserves against a budget of 5,
#      exactly 5 succeed with unique seqs 1..5, exactly 3 refuse with exit 3,
#      exhaustion lands as stopped-budget, the lock is released
#   2. complete + status: recorded outcomes show up in the status counts
#   3. idempotent complete: same outcome exits 0 without change, a
#      conflicting outcome refuses with exit 4
#   4. stale lock: a lock owned by a dead pid is reclaimed; a lock owned by
#      a live pid is respected until the bounded wait times out (exit 5)
#   5. nested budget: a child reservation carries parent_seq and draws from
#      the same budget
#   6. stop: a stopped run refuses reservations but still accepts complete
#   7. resume support: seqs stay monotonic, ok outcomes survive later
#      appends, the would-be re-run set excludes ok seqs
#
# Prints PASS/FAIL per assertion. Exit 0 only when every assertion passes.
# No dependencies beyond bash and coreutils.

set -u

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
DF=$REPO_DIR/scripts/df-state.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/df-state-test.XXXXXX")
export DF_STATE_ROOT=$TMP/runs
trap 'rm -rf "$TMP"' EXIT

ASSERTS=0
FAILURES=0

pass() { ASSERTS=$((ASSERTS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { ASSERTS=$((ASSERTS + 1)); FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$1"; }

assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

assert_code() { # desc expected-exit-code command...
  local desc=$1 want=$2 got
  shift 2
  "$@" >/dev/null 2>&1
  got=$?
  assert_eq "$desc" "$want" "$got"
}

state_of() { awk -F'\t' 'NR==2 { print $8 }' "$DF_STATE_ROOT/$1/run.tsv"; }

count_of() { # run-id status-key
  bash "$DF" status "$1" | awk -F'\t' -v k="$2" '$1 == k { print $2 }'
}

echo "== 1. concurrent reservation against a budget of 5 =="
bash "$DF" init run-a standard 5 120 all acceptance checks green >/dev/null 2>&1
OUT=$TMP/out
mkdir -p "$OUT"
for i in 1 2 3 4 5 6 7 8; do
  (
    bash "$DF" reserve run-a worker "concurrent job $i" >"$OUT/$i.out" 2>"$OUT/$i.err"
    echo $? >"$OUT/$i.code"
  ) &
done
wait
succ=0 refused=0 other=0
for i in 1 2 3 4 5 6 7 8; do
  case $(cat "$OUT/$i.code") in
    0) succ=$((succ + 1)) ;;
    3) refused=$((refused + 1)) ;;
    *) other=$((other + 1)) ;;
  esac
done
assert_eq "exactly 5 of 8 concurrent reserves succeed" 5 "$succ"
assert_eq "exactly 3 of 8 concurrent reserves refuse with exit 3" 3 "$refused"
assert_eq "no reserve exits with an unexpected code" 0 "$other"
seqs=$(for i in 1 2 3 4 5 6 7 8; do
  [ "$(cat "$OUT/$i.code")" = 0 ] && cat "$OUT/$i.out"
done | sort -n | paste -sd' ')
assert_eq "granted seqs are 1..5, unique" "1 2 3 4 5" "$seqs"
assert_eq "exhaustion is recorded as stopped-budget" stopped-budget "$(state_of run-a)"
lockdir=absent
[ -d "$DF_STATE_ROOT/run-a/lock" ] && lockdir=present
assert_eq "lock is released after the reservation storm" absent "$lockdir"

echo "== 2. complete and status counts =="
assert_code "complete seq 1 ok" 0 bash "$DF" complete run-a 1 ok
assert_code "complete seq 2 ok" 0 bash "$DF" complete run-a 2 ok
assert_code "complete seq 3 failed" 0 bash "$DF" complete run-a 3 failed
assert_eq "status reserved is 5/5" "5/5" "$(count_of run-a reserved)"
assert_eq "status ok count is 2" 2 "$(count_of run-a ok)"
assert_eq "status failed count is 1" 1 "$(count_of run-a failed)"
assert_eq "status pending count is 2" 2 "$(count_of run-a pending)"
assert_eq "status budget_remaining is 0" 0 "$(count_of run-a budget_remaining)"

echo "== 3. idempotent complete =="
assert_code "re-completing seq 1 as ok is idempotent (exit 0)" 0 bash "$DF" complete run-a 1 ok
assert_code "conflicting outcome for seq 1 refuses with exit 4" 4 bash "$DF" complete run-a 1 failed
assert_eq "ok count unchanged after the idempotent replay" 2 "$(count_of run-a ok)"
assert_code "completing an unknown seq exits 2" 2 bash "$DF" complete run-a 99 ok

echo "== 4. stale lock reclaim and bounded wait =="
bash "$DF" init run-b standard 3 120 stale lock scenario >/dev/null 2>&1
mkdir "$DF_STATE_ROOT/run-b/lock"
printf 'pid=999999999\tts=2026-01-01T00:00:00Z\n' > "$DF_STATE_ROOT/run-b/lock/owner"
got=$(bash "$DF" reserve run-b worker "after stale lock" 2>/dev/null)
code=$?
assert_eq "reserve reclaims a dead-owner lock (exit 0)" 0 "$code"
assert_eq "reclaimed reserve is granted seq 1" 1 "$got"
residue=$(ls "$DF_STATE_ROOT/run-b" | grep -c 'lock.stale')
assert_eq "no stale-lock residue is left behind" 0 "$residue"
mkdir "$DF_STATE_ROOT/run-b/lock"
printf 'pid=%s\tts=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DF_STATE_ROOT/run-b/lock/owner"
assert_code "a live-owner lock is respected until timeout (exit 5)" 5 \
  env DF_STATE_LOCK_WAIT=1 bash "$DF" reserve run-b worker "against live lock"
rm -f "$DF_STATE_ROOT/run-b/lock/owner"
rmdir "$DF_STATE_ROOT/run-b/lock"

echo "== 5. nested dispatches draw from the parent budget =="
bash "$DF" init run-c standard 2 120 nested budget scenario >/dev/null 2>&1
p=$(bash "$DF" reserve run-c lead "parent work" 2>/dev/null)
n=$(bash "$DF" reserve run-c worker "nested work" "$p" 2>/dev/null)
assert_eq "parent reservation is granted seq 1" 1 "$p"
assert_eq "nested reservation is granted seq 2" 2 "$n"
assert_eq "nested row carries parent_seq 1" 1 \
  "$(awk -F'\t' 'NR>1 && $1 == 2 { print $5 }' "$DF_STATE_ROOT/run-c/dispatches.tsv")"
assert_code "third reserve refuses with exit 3: nesting spent the same budget" 3 \
  bash "$DF" reserve run-c worker "overflow"

echo "== 6. stop makes further reservations refuse =="
bash "$DF" init run-d standard 5 120 stop scenario >/dev/null 2>&1
assert_code "reserve with an unknown parent-seq is an argument error (exit 1)" 1 \
  bash "$DF" reserve run-d worker "bad parent" 42
s=$(bash "$DF" reserve run-d worker "pre-stop work" 2>/dev/null)
assert_eq "pre-stop reserve is granted seq 1" 1 "$s"
assert_code "stop run-d operator exits 0" 0 bash "$DF" stop run-d operator
assert_eq "stop records stopped-operator" stopped-operator "$(state_of run-d)"
assert_code "reserve after stop refuses with exit 3" 3 \
  bash "$DF" reserve run-d worker "post-stop work"
assert_code "complete still works after stop" 0 bash "$DF" complete run-d 1 ok

echo "== 7. resume support =="
bash "$DF" init run-e standard 5 120 resume scenario >/dev/null 2>&1
s1=$(bash "$DF" reserve run-e worker "first attempt" 2>/dev/null)
bash "$DF" complete run-e "$s1" ok >/dev/null 2>&1
s2=$(bash "$DF" reserve run-e worker "second attempt" 2>/dev/null)
assert_eq "seq stays monotonic across completes (no reuse on resume)" 2 "$s2"
assert_eq "seq 1 outcome stays ok after later appends" ok \
  "$(awk -F'\t' 'NR>1 && $1 == 1 { print $6 }' "$DF_STATE_ROOT/run-e/dispatches.tsv")"
rerun=$(awk -F'\t' 'NR>1 && $6 != "ok" { print $1 }' "$DF_STATE_ROOT/run-e/dispatches.tsv" | paste -sd' ')
assert_eq "the would-be re-run set excludes ok seqs" 2 "$rerun"
assert_code "resume can record a dead pending dispatch as expired" 0 \
  bash "$DF" complete run-e 2 expired
assert_eq "expired count is 1 after the resume sweep" 1 "$(count_of run-e expired)"

echo
printf '%d assertions, %d failures\n' "$ASSERTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
exit 0
