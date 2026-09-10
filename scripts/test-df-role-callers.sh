#!/usr/bin/env bash
set -euo pipefail

# Offline acceptance for frozen role callers. It drives the common adapter and
# the source QA runner against fake role, state, and Codex process boundaries.
# No model process or network request is made.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_caller="$repo_root/scripts/df-role-caller.sh"
codex_caller="$repo_root/codex-plugin/scripts/df-role-caller.sh"
source_review="$repo_root/scripts/df-codex-review.sh"
source_quality="$repo_root/skills/df-code-review/scripts/run_codex_quality_review.sh"
source_spec="$repo_root/skills/df-code-review/scripts/run_codex_spec_review.sh"
source_qa="$repo_root/skills/df-qa-validation/scripts/run_codex_qa_validation.sh"
codex_subagents="$repo_root/codex-plugin/skills/df-code-review/scripts/run_codex_subagent_reviews.sh"
codex_qa="$repo_root/codex-plugin/skills/df-qa-validation/scripts/run_codex_qa_validation.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/df-role-callers.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [[ -z "${2:-}" ]] || printf '     %s\n' "$2"; }
expect_fail() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then bad "$label" 'command unexpectedly succeeded'; else ok "$label"; fi
}
line_number() { awk -v token="$2" '$0 ~ token { print NR; exit }' "$1"; }

consumer="$work/consumer"
runs="$work/runs"
bin="$work/bin"
mkdir -p "$consumer" "$runs/role-callers" "$bin"
git -C "$consumer" init -q
git -C "$consumer" config user.email role-callers@example.invalid
git -C "$consumer" config user.name role-callers-test
printf 'synthetic consumer\n' >"$consumer/README.md"
git -C "$consumer" add README.md
git -C "$consumer" commit -qm 'synthetic consumer'
printf 'run_id\tlane\tcreated\tfinish_predicate\tartifact_sha\tbudget_dispatches\tbudget_wall_minutes\tstate\nrole-callers\tstandard\t2026-01-01T00:00:00Z\tfinish\t-\t20\t120\trunning\n' >"$runs/role-callers/run.tsv"
printf 'seq\tts\trole\tpurpose\tparent_seq\toutcome\n' >"$runs/role-callers/dispatches.tsv"

cat >"$work/fake-role.mjs" <<'NODE'
import { appendFileSync } from 'node:fs';
const args = process.argv.slice(2);
const option = (name) => args[args.indexOf(name) + 1];
appendFileSync(process.env.FAKE_CALLER_LOG, `preflight ${option('--responsibility')} ${option('--lane')}\n`);
if (process.env.FAKE_ROLE_FAIL === '1') process.exit(1);
const target = JSON.parse(process.env.FAKE_ROLE_TARGET || '{"kind":"transport","name":"codex-cli"}');
process.stdout.write(`${JSON.stringify({ responsibility: option('--responsibility'), lane: option('--lane'), target, validatedNamedAgents: [] })}\n`);
NODE

cat >"$work/fake-state.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  path) printf '%s/%s\n' "$FAKE_CALLER_RUNS" "$2" ;;
  reserve)
    printf 'reserve %s\n' "$2" >>"$FAKE_CALLER_LOG"
    awk 'END { print NR }' "$FAKE_CALLER_RUNS/$2/dispatches.tsv" >>"$FAKE_CALLER_RUNS/$2/dispatches.tsv"
    awk 'END { print NR - 1 }' "$FAKE_CALLER_RUNS/$2/dispatches.tsv"
    ;;
  complete) printf 'complete %s %s %s\n' "$2" "$3" "$4" >>"$FAKE_CALLER_LOG" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$work/fake-state.sh"

cat >"$bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'worker\n' >>"$FAKE_CALLER_LOG"
if [[ "${FAKE_WORKER_FAIL:-0}" == 1 ]]; then
  exit 9
fi
prompt="$*"
out=''
next_is_out=0
for arg in "$@"; do
  if [[ "$next_is_out" == 1 ]]; then
    out="$arg"
    break
  fi
  [[ "$arg" == -o ]] && next_is_out=1
done
header='## Findings — Codex'
if [[ "$prompt" == *'Codex Security'* ]]; then
  header='## Findings — Codex Security'
elif [[ "$prompt" == *'Codex Quality'* ]]; then
  header='## Findings — Codex Quality'
elif [[ "$prompt" == *'Codex Spec'* ]]; then
  header='## Findings — Codex Spec'
fi
body="$header

NO FINDINGS

This deterministic fake reviewer output is padded to exercise the review
wrapper's non-trivial-body contract without invoking a model.
$(printf '%*s' 256 '' | tr ' ' x)
"
if [[ -n "$out" ]]; then
  printf '%s' "$body" >"$out"
else
  printf '%s' "$body"
fi
SH
chmod +x "$bin/codex"

export FAKE_CALLER_LOG="$work/calls.log"
export FAKE_CALLER_RUNS="$runs"
export DF_ROLE_CALLER_ROLE_HELPER="$work/fake-role.mjs"
export DF_ROLE_CALLER_STATE_HELPER="$work/fake-state.sh"
export PATH="$bin:$PATH"
export CODEX_SKILLS_HOME="$repo_root/codex-plugin/skills"

reset_calls() {
  : >"$FAKE_CALLER_LOG"
}

assert_single_success() {
  local label=$1
  shift
  reset_calls
  if "$@" >/dev/null 2>&1; then
    local preflight_line reserve_line worker_line complete_line
    preflight_line="$(line_number "$FAKE_CALLER_LOG" '^preflight')"
    reserve_line="$(line_number "$FAKE_CALLER_LOG" '^reserve')"
    worker_line="$(line_number "$FAKE_CALLER_LOG" '^worker')"
    complete_line="$(line_number "$FAKE_CALLER_LOG" '^complete')"
    if [[ "$(grep -c '^reserve' "$FAKE_CALLER_LOG")" == 1 ]] \
      && [[ "$(grep -c '^worker' "$FAKE_CALLER_LOG")" == 1 ]] \
      && [[ "$(grep -c '^complete .* ok$' "$FAKE_CALLER_LOG")" == 1 ]] \
      && [[ "$preflight_line" -lt "$reserve_line" && "$reserve_line" -lt "$worker_line" && "$worker_line" -lt "$complete_line" ]]; then
      ok "$label succeeds after preflight, reservation, worker, and completion"
    else
      bad "$label succeeds after preflight, reservation, worker, and completion" "$(cat "$FAKE_CALLER_LOG")"
    fi
  else
    bad "$label succeeds" "$(cat "$FAKE_CALLER_LOG")"
  fi
}

assert_single_worker_failure() {
  local label=$1
  shift
  reset_calls
  if FAKE_WORKER_FAIL=1 "$@" >/dev/null 2>&1; then
    bad "$label reports a worker failure"
  else
    local reserve_line worker_line complete_line
    reserve_line="$(line_number "$FAKE_CALLER_LOG" '^reserve')"
    worker_line="$(line_number "$FAKE_CALLER_LOG" '^worker')"
    complete_line="$(line_number "$FAKE_CALLER_LOG" '^complete')"
    if [[ "$(grep -c '^reserve' "$FAKE_CALLER_LOG")" == 1 ]] \
      && [[ "$(grep -c '^worker' "$FAKE_CALLER_LOG")" == 1 ]] \
      && [[ "$(grep -c '^complete .* failed$' "$FAKE_CALLER_LOG")" == 1 ]] \
      && [[ "$reserve_line" -lt "$worker_line" && "$worker_line" -lt "$complete_line" ]]; then
      ok "$label closes its reservation after worker failure"
    else
      bad "$label closes its reservation after worker failure" "$(cat "$FAKE_CALLER_LOG")"
    fi
  fi
}

assert_preflight_failure() {
  local label=$1
  shift
  reset_calls
  if FAKE_ROLE_FAIL=1 "$@" >/dev/null 2>&1; then
    bad "$label rejects a failed preflight"
  elif [[ "$(grep -c '^preflight' "$FAKE_CALLER_LOG")" -ge 1 ]] \
    && ! grep -qE '^(reserve|worker|complete)' "$FAKE_CALLER_LOG"; then
    ok "$label stops before reservation and worker on preflight failure"
  else
    bad "$label stops before reservation and worker on preflight failure" "$(cat "$FAKE_CALLER_LOG")"
  fi
}

receipt="$(bash "$source_caller" reserve --run role-callers --lane standard --repo-root "$consumer" \
  --responsibility cross_model_review --purpose adapter-test \
  --allow-kind transport --allow-transport codex-cli)"
if [[ "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).seqs[0])' "$receipt")" == 1 ]] \
  && [[ "$(line_number "$FAKE_CALLER_LOG" '^preflight')" -lt "$(line_number "$FAKE_CALLER_LOG" '^reserve')" ]]; then
  ok 'source adapter preflights before reservation'
else
  bad 'source adapter preflights before reservation' "$(cat "$FAKE_CALLER_LOG")"
fi

: >"$FAKE_CALLER_LOG"
expect_fail 'unsupported target stops before reservation' \
  env FAKE_ROLE_TARGET='{"kind":"named-agent","agent":"terra_xhigh"}' \
  bash "$source_caller" reserve --run role-callers --lane standard --repo-root "$consumer" \
    --responsibility cross_model_review --purpose unsupported --allow-kind transport --allow-transport codex-cli
if grep -q '^reserve' "$FAKE_CALLER_LOG"; then bad 'unsupported target made no reservation'; else ok 'unsupported target made no reservation'; fi

: >"$FAKE_CALLER_LOG"
expect_fail 'failed preflight stops before reservation' \
  env FAKE_ROLE_FAIL=1 bash "$source_caller" reserve --run role-callers --lane standard --repo-root "$consumer" \
    --responsibility cross_model_review --purpose failed-preflight --allow-kind transport --allow-transport codex-cli
if grep -q '^reserve' "$FAKE_CALLER_LOG"; then bad 'failed preflight made no reservation'; else ok 'failed preflight made no reservation'; fi

: >"$FAKE_CALLER_LOG"
FAKE_ROLE_TARGET='{"kind":"parallel","targets":[{"kind":"transport","name":"codex-cli"},{"kind":"transport","name":"codex-cli"}]}' \
  bash "$codex_caller" reserve --run role-callers --lane standard --repo-root "$consumer" \
    --responsibility cross_model_review --purpose paired --dispatch-count 2 \
    --allow-kind transport --allow-transport codex-cli >/dev/null
if [[ "$(grep -c '^reserve' "$FAKE_CALLER_LOG")" == 2 ]]; then ok 'paired target reserves both native leaves'; else bad 'paired target reserves both native leaves'; fi

parallel_native_target='{"kind":"parallel","targets":[{"kind":"transport","name":"codex-cli"},{"kind":"cli","model":null,"effort":null}]}'
assert_multiple_allowed_leaves() {
  local label=$1
  local adapter=$2
  reset_calls
  if FAKE_ROLE_TARGET="$parallel_native_target" bash "$adapter" reserve \
    --run role-callers --lane standard --repo-root "$consumer" \
    --responsibility cross_model_review --purpose multiple-allowed-leaves --dispatch-count 2 \
    --allow-kind transport --allow-kind cli --allow-transport codex-cli >/dev/null; then
    if [[ "$(grep -c '^reserve' "$FAKE_CALLER_LOG")" == 2 ]]; then
      ok "$label accepts repeated allowed kinds for matching parallel leaves"
    else
      bad "$label accepts repeated allowed kinds for matching parallel leaves" "$(cat "$FAKE_CALLER_LOG")"
    fi
  else
    bad "$label accepts repeated allowed kinds for matching parallel leaves" "$(cat "$FAKE_CALLER_LOG")"
  fi
}

assert_unallowed_leaf_stops() {
  local label=$1
  local adapter=$2
  reset_calls
  if FAKE_ROLE_TARGET="$parallel_native_target" bash "$adapter" reserve \
    --run role-callers --lane standard --repo-root "$consumer" \
    --responsibility cross_model_review --purpose unallowed-leaf --dispatch-count 2 \
    --allow-kind transport --allow-transport codex-cli >/dev/null 2>&1; then
    bad "$label rejects a leaf outside the allowed kinds"
  elif grep -q '^reserve' "$FAKE_CALLER_LOG"; then
    bad "$label rejects a leaf outside the allowed kinds" "$(cat "$FAKE_CALLER_LOG")"
  else
    ok "$label rejects a leaf outside the allowed kinds before reservation"
  fi
}

assert_multiple_allowed_leaves 'source adapter' "$source_caller"
assert_multiple_allowed_leaves 'Codex adapter' "$codex_caller"
assert_unallowed_leaf_stops 'source adapter' "$source_caller"
assert_unallowed_leaf_stops 'Codex adapter' "$codex_caller"

: >"$FAKE_CALLER_LOG"
expect_fail 'lane mismatch stops before reservation' \
  bash "$source_caller" reserve --run role-callers --lane quick --repo-root "$consumer" \
    --responsibility cross_model_review --purpose wrong-lane --allow-kind transport --allow-transport codex-cli
if grep -q '^reserve' "$FAKE_CALLER_LOG"; then bad 'lane mismatch made no reservation'; else ok 'lane mismatch made no reservation'; fi

installed_runs="$work/installed-runs"
(cd "$consumer" && DF_STATE_ROOT="$installed_runs" bash "$repo_root/scripts/df-state.sh" init installed-source standard 8 120 installed-root-test >/dev/null)
DF_STATE_ROOT="$installed_runs" node "$repo_root/scripts/df-role.mjs" prepare-run \
  --run installed-source --harness claude --repo-root "$consumer" >/dev/null
installed_source_receipt="$(cd "$work" && env -u DF_ROLE_CALLER_ROLE_HELPER -u DF_ROLE_CALLER_STATE_HELPER \
  DF_STATE_ROOT="$installed_runs" bash "$source_caller" reserve --run installed-source --lane standard \
  --repo-root "$consumer" --responsibility cross_model_review --purpose installed-source \
  --allow-kind transport --allow-transport codex-cli)"
(cd "$consumer" && DF_STATE_ROOT="$installed_runs" bash "$repo_root/scripts/df-state.sh" complete installed-source \
  "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).seqs[0])' "$installed_source_receipt")" ok >/dev/null)
(cd "$consumer" && DF_STATE_ROOT="$installed_runs" bash "$repo_root/codex-plugin/scripts/df-state.sh" init installed-codex standard 8 120 installed-root-test >/dev/null)
DF_STATE_ROOT="$installed_runs" node "$repo_root/codex-plugin/scripts/df-role.mjs" prepare-run \
  --run installed-codex --harness codex --repo-root "$consumer" >/dev/null
installed_codex_receipt="$(cd "$work" && env -u DF_ROLE_CALLER_ROLE_HELPER -u DF_ROLE_CALLER_STATE_HELPER \
  DF_STATE_ROOT="$installed_runs" bash "$codex_caller" reserve --run installed-codex --lane standard \
  --repo-root "$consumer" --responsibility persona_reviewers_cli --purpose installed-codex --allow-kind cli)"
(cd "$consumer" && DF_STATE_ROOT="$installed_runs" bash "$repo_root/codex-plugin/scripts/df-state.sh" complete installed-codex \
  "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).seqs[0])' "$installed_codex_receipt")" ok >/dev/null)
if [[ "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).preflight.target.kind)' "$installed_source_receipt")" == transport ]] \
  && [[ "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).preflight.target.kind)' "$installed_codex_receipt")" == cli ]]; then
  ok 'both plugin roots resolve from a synthetic consumer cwd'
else
  bad 'both plugin roots resolve from a synthetic consumer cwd'
fi

: >"$FAKE_CALLER_LOG"
prd="$consumer/prd.md"
input="$consumer/input.md"
out="$consumer/out.md"
printf '# PRD\n' >"$prd"
printf '# Review input\n' >"$input"
(cd "$consumer" && bash "$source_qa" "$prd" "$input" "$out" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer")
preflight_line="$(line_number "$FAKE_CALLER_LOG" '^preflight')"
reserve_line="$(line_number "$FAKE_CALLER_LOG" '^reserve')"
worker_line="$(line_number "$FAKE_CALLER_LOG" '^worker')"
complete_line="$(line_number "$FAKE_CALLER_LOG" '^complete')"
if [[ "$preflight_line" -lt "$reserve_line" && "$reserve_line" -lt "$worker_line" && "$worker_line" -lt "$complete_line" ]]; then
  ok 'QA runner orders preflight, reservation, worker, and completion'
else
  bad 'QA runner orders preflight, reservation, worker, and completion' "$(cat "$FAKE_CALLER_LOG")"
fi

: >"$FAKE_CALLER_LOG"
if (cd "$consumer" && FAKE_WORKER_FAIL=1 bash "$source_qa" "$prd" "$input" "$out" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer") >/dev/null 2>&1; then
  bad 'QA runner reports a failed worker'
else
  failure_complete="$(grep '^complete ' "$FAKE_CALLER_LOG" | tail -1 || true)"
  if [[ "$failure_complete" == *' failed' ]]; then
    ok 'QA runner closes its reservation after a failed worker'
else
  bad 'QA runner closes its reservation after a failed worker' "$(cat "$FAKE_CALLER_LOG")"
fi
fi

review_brief="$consumer/review-brief.md"
review_content="$consumer/review-content.md"
printf '# Review brief\n' >"$review_brief"
printf '# Review content\n' >"$review_content"
assert_single_success 'df-codex-review' bash "$source_review" "$review_brief" "$consumer/review-success.md" \
  --deadline 5 --content "$review_content" --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_single_worker_failure 'df-codex-review' bash "$source_review" "$review_brief" "$consumer/review-worker-failure.md" \
  --deadline 5 --content "$review_content" --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_preflight_failure 'df-codex-review' bash "$source_review" "$review_brief" "$consumer/review-preflight-failure.md" \
  --deadline 5 --content "$review_content" --df-run role-callers --df-lane standard --df-repo-root "$consumer"

printf 'branch change\n' >"$consumer/feature.md"
git -C "$consumer" add feature.md
git -C "$consumer" commit -qm 'synthetic feature change'
assert_single_success 'source quality runner' bash "$source_quality" HEAD~1 "$consumer/quality-success.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_single_worker_failure 'source quality runner' bash "$source_quality" HEAD~1 "$consumer/quality-worker-failure.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_preflight_failure 'source quality runner' bash "$source_quality" HEAD~1 "$consumer/quality-preflight-failure.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_single_success 'source spec runner' bash "$source_spec" "$prd" "$input" HEAD~1 "$consumer/spec-success.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_single_worker_failure 'source spec runner' bash "$source_spec" "$prd" "$input" HEAD~1 "$consumer/spec-worker-failure.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_preflight_failure 'source spec runner' bash "$source_spec" "$prd" "$input" HEAD~1 "$consumer/spec-preflight-failure.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"

assert_single_success 'Codex QA runner' env FAKE_ROLE_TARGET='{"kind":"cli","model":null,"effort":null}' \
  bash "$codex_qa" "$prd" "$input" "$consumer/codex-qa-success.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_single_worker_failure 'Codex QA runner' env FAKE_ROLE_TARGET='{"kind":"cli","model":null,"effort":null}' \
  bash "$codex_qa" "$prd" "$input" "$consumer/codex-qa-worker-failure.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_preflight_failure 'Codex QA runner' env FAKE_ROLE_TARGET='{"kind":"cli","model":null,"effort":null}' \
  bash "$codex_qa" "$prd" "$input" "$consumer/codex-qa-preflight-failure.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"

assert_three_success() {
  local label=$1
  shift
  reset_calls
  if "$@" >/dev/null 2>&1; then
    local preflight_line reserve_line worker_line
    preflight_line="$(line_number "$FAKE_CALLER_LOG" '^preflight')"
    reserve_line="$(line_number "$FAKE_CALLER_LOG" '^reserve')"
    worker_line="$(line_number "$FAKE_CALLER_LOG" '^worker')"
    if [[ "$(grep -c '^preflight' "$FAKE_CALLER_LOG")" == 4 ]] \
      && [[ "$(grep -c '^reserve' "$FAKE_CALLER_LOG")" == 3 ]] \
      && [[ "$(grep -c '^worker' "$FAKE_CALLER_LOG")" == 3 ]] \
      && [[ "$(grep -c '^complete .* ok$' "$FAKE_CALLER_LOG")" == 3 ]] \
      && [[ "$preflight_line" -lt "$reserve_line" && "$reserve_line" -lt "$worker_line" ]]; then
      ok "$label preflights and closes all three worker reservations"
    else
      bad "$label preflights and closes all three worker reservations" "$(cat "$FAKE_CALLER_LOG")"
    fi
  else
    bad "$label succeeds" "$(cat "$FAKE_CALLER_LOG")"
  fi
}

assert_three_worker_failure() {
  local label=$1
  shift
  reset_calls
  if FAKE_WORKER_FAIL=1 "$@" >/dev/null 2>&1; then
    bad "$label reports worker failures"
  elif [[ "$(grep -c '^reserve' "$FAKE_CALLER_LOG")" == 3 ]] \
    && [[ "$(grep -c '^worker' "$FAKE_CALLER_LOG")" == 3 ]] \
    && [[ "$(grep -c '^complete .* failed$' "$FAKE_CALLER_LOG")" == 3 ]]; then
    ok "$label closes all three reservations after worker failures"
  else
    bad "$label closes all three reservations after worker failures" "$(cat "$FAKE_CALLER_LOG")"
  fi
}

assert_three_success 'Codex subagent runner' env FAKE_ROLE_TARGET='{"kind":"cli","model":null,"effort":null}' \
  bash "$codex_subagents" "$prd" "$input" HEAD~1 "$consumer/subagents-success" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_three_worker_failure 'Codex subagent runner' env FAKE_ROLE_TARGET='{"kind":"cli","model":null,"effort":null}' \
  bash "$codex_subagents" "$prd" "$input" HEAD~1 "$consumer/subagents-worker-failure" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_preflight_failure 'Codex subagent runner' env FAKE_ROLE_TARGET='{"kind":"cli","model":null,"effort":null}' \
  bash "$codex_subagents" "$prd" "$input" HEAD~1 "$consumer/subagents-preflight-failure" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"

callers=(
  scripts/df-codex-exec.sh scripts/df-codex-review.sh
  skills/df-code-review/scripts/run_codex_quality_review.sh
  skills/df-code-review/scripts/run_codex_spec_review.sh
  skills/df-prd-challenge/scripts/run_codex_prd_review.sh
  skills/df-qa-validation/scripts/run_codex_qa_validation.sh
  codex-plugin/skills/df-code-review/scripts/run_codex_subagent_reviews.sh
  codex-plugin/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh
  codex-plugin/skills/df-prd-challenge/scripts/run_codex_persona_reviews.sh
  codex-plugin/skills/df-prd-challenge/scripts/run_claude_prd_review_tmux.sh
  codex-plugin/skills/df-qa-validation/scripts/run_codex_qa_validation.sh
)
caller_paths=()
for file in "${callers[@]}"; do caller_paths+=("$repo_root/$file"); done
if rg -n -- '--model|--effort|model_reasoning_effort|CODEX_REASONING_EFFORT' \
  "${caller_paths[@]}" >/dev/null; then
  bad 'static dispatch-caller scan finds no private model or effort selection'
else
  ok 'static dispatch-caller scan finds no private model or effort selection'
fi

for file in "${callers[@]}"; do
  if rg -q 'df-role-caller' "$repo_root/$file"; then :; else bad "inventory caller uses the shared boundary: $file"; fi
done
if [[ "$fail" -eq 0 ]]; then ok 'static inventory check finds the shared boundary in every caller'; fi

assert_root_inventory_instructions() {
  local label=$1
  local skill_root=$2
  local skill_file count=0
  while IFS= read -r skill_file; do
    count=$((count + 1))
    if ! rg -Fq '<df-root>/references/role-callers-inventory.md' "$skill_file"; then
      bad "$label declares the session-hook inventory root" "$skill_file"
    fi
    if rg -Fq '../../references/role-callers-inventory.md' "$skill_file"; then
      bad "$label has no copied-skill relative inventory link" "$skill_file"
    fi
  done < <(rg -l 'role-callers-inventory\.md' "$skill_root" | sort)
  if [[ "$count" != 14 ]]; then
    bad "$label contains the complete inventory-instruction set" "found $count instructions"
  elif [[ "$fail" -eq 0 ]]; then
    ok "$label declares the session-hook inventory root in every caller instruction"
  fi
}

assert_root_inventory_instructions 'source tree' "$repo_root/skills"
assert_root_inventory_instructions 'Codex tree' "$repo_root/codex-plugin/skills"

sync_root="$work/sync-layout"
copied_source_skill="$sync_root/claude-skills/df-qa-validation"
copied_codex_skill="$sync_root/codex-skills/df-qa-validation"
copied_source_router="$sync_root/claude-skills/df"
copied_codex_router="$sync_root/codex-skills/df"
copied_source_code_review="$sync_root/claude-skills/df-code-review"
copied_codex_code_review="$sync_root/codex-skills/df-code-review"
copied_source_prd_challenge="$sync_root/claude-skills/df-prd-challenge"
copied_codex_prd_challenge="$sync_root/codex-skills/df-prd-challenge"
mkdir -p "$(dirname "$copied_source_skill")" "$(dirname "$copied_codex_skill")"
cp -a "$repo_root/skills/df-qa-validation" "$copied_source_skill"
cp -a "$repo_root/codex-plugin/skills/df-qa-validation" "$copied_codex_skill"
cp -a "$repo_root/skills/df" "$copied_source_router"
cp -a "$repo_root/codex-plugin/skills/df" "$copied_codex_router"
cp -a "$repo_root/skills/df-code-review" "$copied_source_code_review"
cp -a "$repo_root/codex-plugin/skills/df-code-review" "$copied_codex_code_review"
cp -a "$repo_root/skills/df-prd-challenge" "$copied_source_prd_challenge"
cp -a "$repo_root/codex-plugin/skills/df-prd-challenge" "$copied_codex_prd_challenge"

source_hook_line="$(sh "$repo_root/scripts/df-session-hook.sh" | tail -1)"
source_hook_root="${source_hook_line#The dark-factory root here is }"
source_hook_root="${source_hook_root%%. Resolve*}"
codex_hook_line="$(sh "$repo_root/codex-plugin/scripts/df-session-hook.sh" | tail -1)"
codex_hook_root="${codex_hook_line#The dark-factory root here is }"
codex_hook_root="${codex_hook_root%%. Resolve*}"
source_inventory="$source_hook_root/references/role-callers-inventory.md"
codex_inventory="$codex_hook_root/references/role-callers-inventory.md"
source_qa_from_hook="$source_hook_root/skills/df-qa-validation/scripts/run_codex_qa_validation.sh"
codex_qa_from_hook="$codex_hook_root/skills/df-qa-validation/scripts/run_codex_qa_validation.sh"
source_prepare_from_hook="$source_hook_root/scripts/df-role.mjs"
codex_prepare_from_hook="$codex_hook_root/scripts/df-role.mjs"
if [[ "$source_hook_root" == "$repo_root" && "$codex_hook_root" == "$repo_root/codex-plugin" ]] \
  && [[ -f "$source_inventory" && -f "$codex_inventory" ]] \
  && cmp -s "$source_inventory" "$codex_inventory" \
  && rg -Fq '<df-root>/scripts/df-role-caller.sh reserve' "$source_inventory" \
  && rg -Fq '<df-root>/scripts/df-role-caller.sh reserve' "$codex_inventory" \
  && rg -Fq '<df-root>/scripts/df-state.sh complete' "$source_inventory" \
  && rg -Fq '<df-root>/scripts/df-state.sh complete' "$codex_inventory" \
  && rg -Fq '<df-root>/references/role-callers-inventory.md' "$copied_source_skill/SKILL.md" \
  && rg -Fq '<df-root>/references/role-callers-inventory.md' "$copied_codex_skill/SKILL.md" \
  && [[ ! -e "$sync_root/claude-skills/references/role-callers-inventory.md" ]] \
  && [[ ! -e "$sync_root/codex-skills/references/role-callers-inventory.md" ]] \
  && [[ -x "$source_qa_from_hook" && -x "$codex_qa_from_hook" ]]; then
  ok 'copied source and Codex skills resolve inventory and wrappers from hook roots'
else
  bad 'copied source and Codex skills resolve inventory and wrappers from hook roots'
fi

copied_role_helpers_ok=1
for copied_skill in "$copied_source_router" "$copied_codex_router"; do
  rg -Fq 'df_root="<Dark Factory root reported by the session hook>"' "$copied_skill/SKILL.md" \
    && rg -Fq 'node "$df_root/scripts/df-role.mjs" prepare-run' "$copied_skill/SKILL.md" \
    || copied_role_helpers_ok=0
done
for copied_skill in "$copied_source_code_review" "$copied_codex_code_review" \
  "$copied_source_prd_challenge" "$copied_codex_prd_challenge"; do
  rg -Fq 'df_root="<Dark Factory root reported by the session hook>"' "$copied_skill/SKILL.md" \
    && rg -Fq 'node "$df_root/scripts/df-role.mjs" preflight' "$copied_skill/SKILL.md" \
    && rg -Fq 'bash "$df_root/scripts/df-state.sh" reserve' "$copied_skill/SKILL.md" \
    || copied_role_helpers_ok=0
done
if [[ "$copied_role_helpers_ok" == 1 && -f "$source_prepare_from_hook" && -f "$codex_prepare_from_hook" ]]; then
  ok 'copied source and Codex skill instructions root-qualify role helpers'
else
  bad 'copied source and Codex skill instructions root-qualify role helpers'
fi

sync_router_runs="$work/sync-router-runs"
(cd "$consumer" && DF_STATE_ROOT="$sync_router_runs" bash "$source_hook_root/scripts/df-state.sh" init sync-router-source standard 8 120 sync-router-test >/dev/null)
source_prepare_json="$(cd "$consumer" && DF_STATE_ROOT="$sync_router_runs" node "$source_prepare_from_hook" prepare-run \
  --run sync-router-source --harness claude --repo-root "$consumer")"
(cd "$consumer" && DF_STATE_ROOT="$sync_router_runs" bash "$codex_hook_root/scripts/df-state.sh" init sync-router-codex standard 8 120 sync-router-test >/dev/null)
codex_prepare_json="$(cd "$consumer" && DF_STATE_ROOT="$sync_router_runs" node "$codex_prepare_from_hook" prepare-run \
  --run sync-router-codex --harness codex --repo-root "$consumer")"
if [[ "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).harness)' "$source_prepare_json")" == claude ]] \
  && [[ "$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).harness)' "$codex_prepare_json")" == codex ]] \
  && [[ -f "$sync_router_runs/sync-router-source/work/role-plan.json" ]] \
  && [[ -f "$sync_router_runs/sync-router-codex/work/role-plan.json" ]]; then
  ok 'hook-root role helpers prepare both copied routers from a consumer cwd'
else
  bad 'hook-root role helpers prepare both copied routers from a consumer cwd'
fi

assert_single_success 'source copied-layout QA instruction' bash "$source_qa_from_hook" "$prd" "$input" "$consumer/sync-source-qa.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"
assert_single_success 'Codex copied-layout QA instruction' env -u CODEX_SKILLS_HOME \
  FAKE_ROLE_TARGET='{"kind":"cli","model":null,"effort":null}' \
  bash "$codex_qa_from_hook" "$prd" "$input" "$consumer/sync-codex-qa.md" \
  --df-run role-callers --df-lane standard --df-repo-root "$consumer"

printf '%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
