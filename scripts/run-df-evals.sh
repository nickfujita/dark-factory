#!/usr/bin/env bash
# run-df-evals.sh: the df-eval scenario runner, the single entry point for
# skill-quality scenarios. Owned by skills/df-eval.
#
# Contract per scenario (skills/df-eval/references/scenario-authoring.md):
#   exit 0, no SKIP line              -> PASS
#   exit 0, one line 'SKIP: <dep>'    -> SKIP, the line names what is missing
#   nonzero exit                      -> FAIL
#
# Usage: run-df-evals.sh [scenario-name ...]
#   No arguments runs every *.sh in scripts/df-eval-scenarios/ in sorted
#   order. Names may be given with or without the .sh suffix.
#
# Env: DF_EVAL_SKIP_LIVE=1 makes live-session scenarios skip themselves; the
# gate lives in each live scenario, not here.
#
# Prints a PASS/FAIL/SKIP table. Exit 0 when nothing failed, 1 otherwise.

set -u

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCEN_DIR=$REPO_DIR/scripts/df-eval-scenarios
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/df-evals.XXXXXX")

[ -d "$SCEN_DIR" ] || { echo "no scenario directory at $SCEN_DIR" >&2; exit 1; }

scenarios=()
if [ $# -gt 0 ]; then
  for name in "$@"; do
    f=$SCEN_DIR/${name%.sh}.sh
    [ -f "$f" ] || { echo "unknown scenario '$name' (no $f)" >&2; exit 1; }
    scenarios+=("$f")
  done
else
  while IFS= read -r f; do
    scenarios+=("$f")
  done < <(find "$SCEN_DIR" -maxdepth 1 -type f -name '*.sh' | sort)
fi
[ "${#scenarios[@]}" -gt 0 ] || { echo "no scenarios found in $SCEN_DIR" >&2; exit 1; }

PASS=0
FAIL=0
SKIP=0

printf '%-24s %-5s %6s  %s\n' SCENARIO RESULT TIME DETAIL
printf '%-24s %-5s %6s  %s\n' -------- ------ ---- ------

for f in "${scenarios[@]}"; do
  name=$(basename "$f" .sh)
  log=$LOG_DIR/$name.log
  start=$(date +%s)
  bash "$f" >"$log" 2>&1
  code=$?
  dur=$(( $(date +%s) - start ))
  if [ "$code" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    result=FAIL
    detail="exit $code; log: $log"
  elif skip_line=$(grep -m1 '^SKIP: ' "$log"); then
    SKIP=$((SKIP + 1))
    result=SKIP
    detail=${skip_line#SKIP: }
  else
    PASS=$((PASS + 1))
    result=PASS
    detail=$(grep -v '^[[:space:]]*$' "$log" | tail -n 1)
  fi
  printf '%-24s %-5s %5ss  %s\n' "$name" "$result" "$dur" "$detail"
done

echo
printf '%d pass, %d fail, %d skip. logs in %s\n' "$PASS" "$FAIL" "$SKIP" "$LOG_DIR"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
