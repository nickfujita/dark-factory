#!/usr/bin/env bash
# Acceptance tests for native GitHub stack registration.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STACK=$REPO_ROOT/scripts/df-stack.sh
WORK=$(mktemp -d "${TMPDIR:-/tmp}/df-stack-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }

FAKE_GH=$WORK/gh
FAKE_LOG=$WORK/gh.log
FAKE_ALL_LOG=$WORK/gh-all.log
export FAKE_LOG FAKE_ALL_LOG

cat >"$FAKE_GH" <<'FAKE'
#!/usr/bin/env bash
set -u

printf '%q ' "$@" >>"$FAKE_LOG"
printf '\n' >>"$FAKE_LOG"
printf '%q ' "$@" >>"$FAKE_ALL_LOG"
printf '\n' >>"$FAKE_ALL_LOG"

[[ ${1:-} == api ]] || { echo "unexpected command" >&2; exit 90; }
shift
if [[ ${1:-} == --help ]]; then
  exit 0
fi

method=GET
endpoint=""
fields=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--header|--jq)
      shift 2
      ;;
    --method|-X)
      method=$2
      shift 2
      ;;
    -F|--field)
      fields="$fields $2"
      shift 2
      ;;
    --silent)
      shift
      ;;
    *)
      if [[ -z "$endpoint" ]]; then
        endpoint=$1
      fi
      shift
      ;;
  esac
done

mode=${FAKE_MODE:-dependent}
if [[ "$endpoint" == 'repos/acme/widget/stacks?per_page=1' ]]; then
  if [[ "$mode" == repo-unavailable ]]; then
    echo 'gh: Not Found (HTTP 404)' >&2
    exit 1
  fi
  exit 0
fi

case "$endpoint" in
  repos/acme/widget)
    printf 'main\n'
    ;;
  repos/acme/widget/pulls/101)
    printf '101\topen\tacme/widget\tfoundation\tacme/widget\tmain\n'
    ;;
  repos/acme/widget/pulls/102)
    if [[ "$mode" == independent || "$mode" == merged-bottom ]]; then
      printf '102\topen\tacme/widget\tfeature\tacme/widget\tmain\n'
    else
      printf '102\topen\tacme/widget\tfeature\tacme/widget\tfoundation\n'
    fi
    ;;
  repos/acme/widget/pulls/103)
    printf '103\topen\tacme/widget\tfinish\tacme/widget\tfeature\n'
    ;;
  'repos/acme/widget/stacks?pull_request=101'|'repos/acme/widget/stacks?pull_request=102')
    if [[ "$mode" == extend || "$mode" == merged-bottom ]]; then printf '7\n'; else printf '\n'; fi
    ;;
  'repos/acme/widget/stacks?pull_request=103')
    printf '\n'
    ;;
  repos/acme/widget/stacks/7)
    printf '101,102\n'
    ;;
  repos/acme/widget/stacks)
    [[ "$method" == POST ]] || exit 91
    [[ "$fields" == *'pull_requests[]=101'* && "$fields" == *'pull_requests[]=102'* ]] || exit 92
    printf '7\n'
    ;;
  repos/acme/widget/stacks/7/add)
    [[ "$method" == POST ]] || exit 93
    [[ "$fields" == *'pull_requests[]=103'* ]] || exit 94
    printf '7\n'
    ;;
  *)
    echo "unexpected endpoint: $endpoint" >&2
    exit 95
    ;;
esac
FAKE
chmod +x "$FAKE_GH"

run_stack() {
  local mode=$1
  shift
  : >"$FAKE_LOG"
  FAKE_MODE=$mode DF_GH_BIN=$FAKE_GH "$STACK" "$@" >"$WORK/output" 2>&1
  RUN_RC=$?
  RUN_OUTPUT=$(cat "$WORK/output")
}

run_stack dependent probe --repo acme/widget
if [[ $RUN_RC -eq 0 && "$RUN_OUTPUT" == *'status=available'* ]]; then
  pass "the REST endpoint proves repository capability"
else
  fail "the capability probe succeeds" "exit=$RUN_RC output=$RUN_OUTPUT"
fi

run_stack repo-unavailable probe --repo acme/widget
if [[ $RUN_RC -eq 2 && "$RUN_OUTPUT" == *'status=fallback reason=preview-unavailable'* ]]; then
  pass "preview unavailability returns the plain-chain fallback"
else
  fail "preview unavailability falls back" "exit=$RUN_RC output=$RUN_OUTPUT"
fi
if ! grep -q -- '--method POST' "$FAKE_LOG"; then
  pass "the failed capability probe creates no remote stack"
else
  fail "the failed capability probe is read-only" "$(cat "$FAKE_LOG")"
fi

run_stack dependent link --repo acme/widget 101 102
if [[ $RUN_RC -eq 0 && "$RUN_OUTPUT" == *'status=linked reason=created'* ]]; then
  pass "a dependent PR chain becomes a native stack"
else
  fail "the dependent chain links" "exit=$RUN_RC output=$RUN_OUTPUT"
fi
if grep -q -- '--method POST repos/acme/widget/stacks ' "$FAKE_LOG"; then
  pass "new stack registration uses one REST create request"
else
  fail "new stack registration reaches the REST create endpoint" "$(cat "$FAKE_LOG")"
fi

run_stack independent link --repo acme/widget 101 102
if [[ $RUN_RC -eq 1 && "$RUN_OUTPUT" == *'reason=chain-invalid'* ]]; then
  pass "independent PRs stay off-stack"
else
  fail "independent PRs are rejected" "exit=$RUN_RC output=$RUN_OUTPUT"
fi
if ! grep -q -- '--method POST' "$FAKE_LOG"; then
  pass "an invalid chain causes no remote mutation"
else
  fail "an invalid chain is fully preflighted" "$(cat "$FAKE_LOG")"
fi

run_stack extend link --repo acme/widget 101 102 103
if [[ $RUN_RC -eq 0 && "$RUN_OUTPUT" == *'status=linked reason=extended'* ]]; then
  pass "a dependent PR extends an existing native stack"
else
  fail "the existing stack extends" "exit=$RUN_RC output=$RUN_OUTPUT"
fi
if grep -q -- '--method POST repos/acme/widget/stacks/7/add ' "$FAKE_LOG"; then
  pass "stack extension uses the REST add endpoint"
else
  fail "stack extension reaches the REST add endpoint" "$(cat "$FAKE_LOG")"
fi

run_stack merged-bottom link --repo acme/widget 102 103
if [[ $RUN_RC -eq 0 && "$RUN_OUTPUT" == *'status=linked reason=extended'* ]]; then
  pass "a stack extends after GitHub rebases the remaining chain"
else
  fail "the rebased remaining chain extends" "exit=$RUN_RC output=$RUN_OUTPUT"
fi

: >"$FAKE_LOG"
DF_GH_BIN=$WORK/missing-gh "$STACK" probe --repo acme/widget >"$WORK/output" 2>&1
RUN_RC=$?
RUN_OUTPUT=$(cat "$WORK/output")
if [[ $RUN_RC -eq 2 && "$RUN_OUTPUT" == *'status=fallback reason=cli-unavailable'* ]]; then
  pass "a machine without gh keeps the plain chain"
else
  fail "missing CLI support falls back" "exit=$RUN_RC output=$RUN_OUTPUT"
fi

if ! grep -Eq '(^| )(stack|merge|rebase|push|--force|--force-with-lease)( |$)' "$FAKE_ALL_LOG"; then
  pass "the helper invokes no stack CLI, merge, rebase, push, or force operation"
else
  fail "the helper stays inside gh api" "$(cat "$FAKE_ALL_LOG")"
fi

if cmp -s "$REPO_ROOT/scripts/df-stack.sh" "$REPO_ROOT/codex-plugin/scripts/df-stack.sh"; then
  pass "both plugin roots ship the same helper"
else
  fail "the helper is mirrored" "scripts/df-stack.sh differs from codex-plugin/scripts/df-stack.sh"
fi

PLAN=$WORK/plan.md
cat >"$PLAN" <<'PLAN'
# Stack routing plan

One independently based PR.

**Goal.** Prove branch routing.
**Spec.** Recorded finish predicate.
**Design.** Design skipped because the shape is fixed.
**Lane.** Standard.

## How to read this

One box is one unit of work and names the evidence.
Check a box only when its evidence exists.
df-implement executes the plan.
Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Global constraints

- None.

## Add routing (PR-1)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** No run state exists.

**You see.**

- [ ] The branch targets main.

### Task 1. Route the branch

**Files.**

- Modify `example.txt`.

**Interfaces.**

- Consumes. None.

**Steps.**

- [ ] Write the change.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The route is valid. Run `true`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Inspect the route. Save `/tmp/route.txt`. Pass when the base is main.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This plan changes no runtime path.
PLAN

CHECKER=$REPO_ROOT/skills/df-plan/scripts/check-plan.mjs
if node "$CHECKER" "$PLAN" >"$WORK/plan-check" 2>&1; then
  pass "the plan checker accepts an independent PR based on main"
else
  fail "the independent plan route is valid" "$(cat "$WORK/plan-check")"
fi

sed -i 's/\*\*Branch\.\*\* Independent from main\./**Branch.** Dependent on PR-0./' "$PLAN"
if node "$CHECKER" "$PLAN" >"$WORK/plan-check" 2>&1; then
  fail "the plan checker rejects mismatched routing" "the invalid plan passed"
elif grep -q 'an independent PR must say' "$WORK/plan-check"; then
  pass "the plan checker rejects stacking an independent PR"
else
  fail "the invalid plan names its routing defect" "$(cat "$WORK/plan-check")"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
