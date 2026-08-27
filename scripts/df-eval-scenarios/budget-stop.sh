#!/usr/bin/env bash
# df-eval scenario: the dispatch budget is a stop, not a flag (v2 plan §7).
#
# Deterministic; no model involved. Drives scripts/df-state.sh against a
# throwaway DF_STATE_ROOT. A run with a budget of N grants exactly N
# reservations, refuses reservation N+1 with exit 3, and flips itself to
# stopped-budget. Every state assertion reads the store files on disk, not
# command stdout, because the store is what a resumed session would trust.

set -u

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
DF=$REPO_DIR/scripts/df-state.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/df-eval-budget.XXXXXX")
export DF_STATE_ROOT=$TMP/runs
trap 'rm -rf "$TMP"' EXIT

BUDGET=3
RUN=budget-stop
STORE=$DF_STATE_ROOT/$RUN
FAILURES=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$1"; }

assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

state_of() { awk -F'\t' 'NR==2 { print $8 }' "$STORE/run.tsv"; }
rows_of() { awk 'NR>1 { n++ } END { print n+0 }' "$STORE/dispatches.tsv"; }

bash "$DF" init "$RUN" standard "$BUDGET" 120 scripted budget scenario >/dev/null 2>&1 \
  || { fail "init refused"; exit 1; }

i=1
while [ "$i" -le "$BUDGET" ]; do
  bash "$DF" reserve "$RUN" worker "scripted dispatch $i" >/dev/null 2>&1
  assert_eq "reservation $i is granted (exit 0)" 0 $?
  i=$((i + 1))
done

assert_eq "store holds exactly $BUDGET dispatch rows" "$BUDGET" "$(rows_of)"
assert_eq "run state is still running before the overflow" running "$(state_of)"

bash "$DF" reserve "$RUN" worker "dispatch over budget" >/dev/null 2>&1
assert_eq "reservation $((BUDGET + 1)) refuses (exit 3)" 3 $?
assert_eq "the refused reservation leaves no dispatch row" "$BUDGET" "$(rows_of)"
assert_eq "the refusal flips the run to stopped-budget" stopped-budget "$(state_of)"

bash "$DF" reserve "$RUN" worker "dispatch after the stop" >/dev/null 2>&1
assert_eq "the stop is terminal; a later reservation still refuses (exit 3)" 3 $?
assert_eq "the terminal state holds in the store" stopped-budget "$(state_of)"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "budget stop holds: $BUDGET of $BUDGET granted, overflow refused, store reads stopped-budget"
  exit 0
fi
echo "$FAILURES assertion(s) failed"
exit 1
