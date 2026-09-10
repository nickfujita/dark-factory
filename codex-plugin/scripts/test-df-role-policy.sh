#!/usr/bin/env bash
# Acceptance coverage for the layered role-policy resolver. All repositories,
# run stores, agents, and overrides in this script are synthetic.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="$REPO_ROOT"
CODEX_ROOT="$REPO_ROOT/codex-plugin"
if [[ "$(basename "$REPO_ROOT")" == "codex-plugin" ]]; then
  SOURCE_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
  CODEX_ROOT="$REPO_ROOT"
fi
ROLE="$REPO_ROOT/scripts/df-role.mjs"
CHECK="$REPO_ROOT/scripts/check-model-policy.mjs"
STATE="$REPO_ROOT/scripts/df-state.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/df-role-policy.XXXXXX")"
PROJECT="$WORK/project"
OTHER_PROJECT="$WORK/other-project"
export DF_STATE_ROOT="$WORK/runs"
export XDG_CONFIG_HOME="$WORK/config"
export CODEX_AGENTS_DIR="$WORK/codex-agents"
export CLAUDE_AGENTS_DIR="$WORK/claude-agents"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }

expect_ok() { # label command...
  local label=$1 output rc
  shift
  output="$("$@" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "$label"
  else
    fail "$label" "exit=$rc output=$output"
  fi
}

expect_fail_contains() { # label needle command...
  local label=$1 needle=$2 output rc
  shift 2
  output="$("$@" 2>&1)"; rc=$?
  if [[ $rc -ne 0 && "$output" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label" "exit=$rc need=$needle output=$output"
  fi
}

json_field() { # json dotted-path
  node -e '
const value = JSON.parse(process.argv[1]);
const result = process.argv[2].split(".").reduce((item, key) => item[key], value);
process.stdout.write(JSON.stringify(result));
' "$1" "$2"
}

dispatch_count() {
  awk 'END { print NR - 1 }' "$DF_STATE_ROOT/$1/dispatches.tsv"
}

new_run() { # run-id
  (cd "$PROJECT" && bash "$STATE" init "$1" standard 9 120 role-policy-test >/dev/null)
}

prepare() { # run-id harness
  node "$ROLE" prepare-run --run "$1" --harness "$2" --repo-root "$PROJECT"
}

resolve() { # run-id responsibility lane
  node "$ROLE" resolve --run "$1" --responsibility "$2" --lane "$3" --repo-root "$PROJECT"
}

preflight() { # run-id responsibility lane
  node "$ROLE" preflight --run "$1" --responsibility "$2" --lane "$3" --repo-root "$PROJECT"
}

write_machine_override() { # JSON body
  mkdir -p "$XDG_CONFIG_HOME/dark-factory"
  printf '%s\n' "$1" >"$XDG_CONFIG_HOME/dark-factory/config.json"
}

clear_overrides() {
  rm -f "$XDG_CONFIG_HOME/dark-factory/config.json" "$PROJECT/.agents/dark-factory.json"
}

mkdir -p "$PROJECT" "$CODEX_AGENTS_DIR" "$CLAUDE_AGENTS_DIR"
git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email role-policy@example.invalid
git -C "$PROJECT" config user.name role-policy-test
printf 'synthetic role-policy project\n' >"$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" commit -qm initial
mkdir -p "$OTHER_PROJECT"
git -C "$OTHER_PROJECT" init -q
git -C "$OTHER_PROJECT" config user.email role-policy@example.invalid
git -C "$OTHER_PROJECT" config user.name role-policy-test
printf 'separate synthetic project\n' >"$OTHER_PROJECT/README.md"
git -C "$OTHER_PROJECT" add README.md
git -C "$OTHER_PROJECT" commit -qm initial

for agent in luna_max terra_xhigh sol_high; do
  file_name="${agent/_/-}.toml"
  printf 'name = "%s"\nmodel = "synthetic"\n' "$agent" >"$CODEX_AGENTS_DIR/$file_name"
done
printf '%s\n' '---' 'name: df-reviewer-recheck' 'model: synthetic' 'effort: high' '---' >"$CLAUDE_AGENTS_DIR/df-reviewer-recheck.md"

echo "== shipped matrix and parallel targets =="
clear_overrides
new_run matrix-claude
claude_plan="$(prepare matrix-claude claude)"
floor_metadata="$(node -e '
const plan = JSON.parse(process.argv[1]);
const binding = plan.namedAgentBindings.find((item) => item.agent === "df-reviewer-recheck");
process.stdout.write(JSON.stringify({ constraints: plan.dispatchConstraints, row: plan.resolutions[0].dispatchConstraints, binding }));
' "$claude_plan")"
if [[ $(json_field "$claude_plan" 'resolutions.length') == 42 && \
      $(json_field "$floor_metadata" 'constraints.nonFloorPinnedTargets') == '"cap-at-session"' && \
      $(json_field "$floor_metadata" 'constraints.namedAgentFloors.0') == '"df-reviewer-recheck"' && \
      $(json_field "$floor_metadata" 'row.namedAgentFloors.0') == '"df-reviewer-recheck"' && \
      $(json_field "$floor_metadata" 'binding.status') == '"bound"' ]]; then
  pass "shipped Claude policy freezes the complete matrix, floor, session cap, and named binding"
else
  fail "shipped Claude policy freezes the complete matrix, floor, session cap, and named binding" "$claude_plan"
fi
high_design="$(resolve matrix-claude design_runners high-consequence)"
if [[ $(json_field "$high_design" 'target.kind') == '"parallel"' && \
      $(json_field "$high_design" 'target.targets.length') == 2 && \
      $(json_field "$high_design" 'target.targets.0.model') == '"opus"' && \
      $(json_field "$high_design" 'target.targets.1.kind') == '"session"' ]]; then
  pass "high-consequence Claude design runners preserve ordered opus and session targets"
else
  fail "high-consequence Claude design runners preserve ordered opus and session targets" "$high_design"
fi
new_run matrix-codex
codex_plan="$(prepare matrix-codex codex)"
if [[ $(json_field "$codex_plan" 'resolutions.length') == 42 && \
      $(json_field "$(resolve matrix-codex design_runners standard)" 'target.agent') == '"terra_xhigh"' ]]; then
  pass "shipped Codex policy freezes the complete matrix and resolves design runners"
else
  fail "shipped Codex policy freezes the complete matrix and resolves design runners" "$codex_plan"
fi
expect_ok "direct preflight validates the shipped Claude named agent" \
  preflight matrix-claude recheck_leaf_reviewers standard
if [[ -f "$REPO_ROOT/agents/df-reviewer-recheck.md" ]]; then
  new_run source-agent
  if CLAUDE_CONFIG_DIR="$WORK/isolated-claude-config" DF_CLAUDE_AGENTS_DIR= CLAUDE_AGENTS_DIR= \
    node "$ROLE" prepare-run --run source-agent --harness claude --repo-root "$PROJECT" >/dev/null 2>&1 && \
    CLAUDE_CONFIG_DIR="$WORK/isolated-claude-config" DF_CLAUDE_AGENTS_DIR= CLAUDE_AGENTS_DIR= \
    node "$ROLE" preflight --run source-agent --responsibility recheck_leaf_reviewers --lane standard --repo-root "$PROJECT" >/dev/null 2>&1; then
    pass "source mode finds the bundled Claude named agent"
  else
    fail "source mode finds the bundled Claude named agent" "bundled agent lookup failed"
  fi
else
  pass "Codex plugin accepts its operator-local Claude agent definition"
fi
installed_checker_output="$(node "$CODEX_ROOT/scripts/check-model-policy.mjs" --policy "$CODEX_ROOT/references/model-policy.json" --skip-agent-validation 2>&1)"
installed_checker_rc=$?
if [[ $installed_checker_rc -eq 0 && "$installed_checker_output" == *"Model policy OK"* ]]; then
  pass "installed Codex root validates its own skill tree"
  printf '     Codex checker: %s\n' "$installed_checker_output"
else
  fail "installed Codex root validates its own skill tree" "exit=$installed_checker_rc output=$installed_checker_output"
fi
expect_fail_contains "a frozen run rejects a different harness" "already frozen for harness codex" \
  prepare matrix-codex claude
expect_fail_contains "a run cannot be resolved from another repository" "belongs to a different repository" \
  node "$ROLE" resolve --run matrix-codex --responsibility design_runners --lane standard --repo-root "$OTHER_PROJECT"

echo "== totality and precedence =="
node -e '
const fs = require("fs");
const source = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
delete source.roles.codex.orchestrator.quick;
fs.writeFileSync(process.argv[2], JSON.stringify(source));
' "$REPO_ROOT/references/model-policy.json" "$WORK/incomplete-policy.json"
expect_fail_contains "missing mapping names the exact responsibility" "orchestrator" \
  node "$CHECK" --policy "$WORK/incomplete-policy.json" --skip-agent-validation
node -e '
const fs = require("fs");
const source = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
source.roles.claude.design_runners["high-consequence"].targets = [{ kind: "parallel", targets: [{ kind: "session" }] }];
fs.writeFileSync(process.argv[2], JSON.stringify(source));
' "$REPO_ROOT/references/model-policy.json" "$WORK/nested-parallel-policy.json"
expect_fail_contains "nested parallel targets are rejected" "parallel targets cannot be nested" \
  node "$CHECK" --policy "$WORK/nested-parallel-policy.json" --skip-agent-validation

write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"sol_high"}}}}}'
new_run machine-wins
machine_plan="$(prepare machine-wins codex)"
machine_role="$(resolve machine-wins design_runners standard)"
if [[ $(json_field "$machine_role" 'target.agent') == '"sol_high"' && \
      $(json_field "$machine_role" 'provenance.1.kind') == '"machine"' ]]; then
  pass "machine override wins over shipped policy with provenance"
else
  fail "machine override wins over shipped policy with provenance" "$machine_plan"
fi

mkdir -p "$PROJECT/.agents"
printf '%s\n' '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"terra_xhigh"}}}}}' >"$PROJECT/.agents/dark-factory.json"
new_run project-wins
project_role="$(prepare project-wins codex)"
project_resolved="$(resolve project-wins design_runners standard)"
if [[ $(json_field "$project_resolved" 'target.agent') == '"terra_xhigh"' && \
      $(json_field "$project_resolved" 'provenance.2.kind') == '"project"' ]]; then
  pass "project override wins over machine policy with provenance"
else
  fail "project override wins over machine policy with provenance" "$project_role"
fi

echo "== unsafe and unavailable inputs =="
clear_overrides
expect_fail_contains "path traversal in a run name is rejected" "cannot traverse a path" \
  prepare ../escape codex
new_run malformed-state
printf 'not a run state\n' >"$DF_STATE_ROOT/malformed-state/run.tsv"
expect_fail_contains "malformed external run state is rejected" "malformed run.tsv" \
  prepare malformed-state codex

new_run invalid-dispatch-outcome
printf '1\t2026-01-01T00:00:00Z\trole\tpurpose\t-\tinvalid\n' >>"$DF_STATE_ROOT/invalid-dispatch-outcome/dispatches.tsv"
before_invalid_outcome="$(dispatch_count invalid-dispatch-outcome)"
expect_fail_contains "invalid dispatch outcomes are rejected before preparation" "malformed dispatch state" \
  prepare invalid-dispatch-outcome codex
after_invalid_outcome="$(dispatch_count invalid-dispatch-outcome)"
if [[ "$before_invalid_outcome" == "$after_invalid_outcome" ]]; then
  pass "invalid dispatch outcomes do not add a reservation"
else
  fail "invalid dispatch outcomes do not add a reservation" "before=$before_invalid_outcome after=$after_invalid_outcome"
fi

new_run duplicate-dispatch-sequence
printf '1\t2026-01-01T00:00:00Z\trole\tpurpose\t-\tpending\n1\t2026-01-01T00:00:01Z\trole\tpurpose\t-\tpending\n' >>"$DF_STATE_ROOT/duplicate-dispatch-sequence/dispatches.tsv"
before_duplicate_sequence="$(dispatch_count duplicate-dispatch-sequence)"
expect_fail_contains "duplicate dispatch sequences are rejected before preparation" "malformed dispatch state" \
  prepare duplicate-dispatch-sequence codex
after_duplicate_sequence="$(dispatch_count duplicate-dispatch-sequence)"
if [[ "$before_duplicate_sequence" == "$after_duplicate_sequence" ]]; then
  pass "duplicate dispatch sequences do not add a reservation"
else
  fail "duplicate dispatch sequences do not add a reservation" "before=$before_duplicate_sequence after=$after_duplicate_sequence"
fi

new_run missing-dispatch-parent
printf '1\t2026-01-01T00:00:00Z\trole\tpurpose\t2\tpending\n' >>"$DF_STATE_ROOT/missing-dispatch-parent/dispatches.tsv"
before_missing_parent="$(dispatch_count missing-dispatch-parent)"
expect_fail_contains "missing dispatch parents are rejected before preparation" "malformed dispatch state" \
  prepare missing-dispatch-parent codex
after_missing_parent="$(dispatch_count missing-dispatch-parent)"
if [[ "$before_missing_parent" == "$after_missing_parent" ]]; then
  pass "missing dispatch parents do not add a reservation"
else
  fail "missing dispatch parents do not add a reservation" "before=$before_missing_parent after=$after_missing_parent"
fi

write_machine_override '{"schemaVersion":1,"unexpected":true}'
new_run unknown-field
expect_fail_contains "unknown field names its config source" "$XDG_CONFIG_HOME/dark-factory/config.json" \
  prepare unknown-field codex
expect_fail_contains "unknown field names the exact field" "unexpected" \
  prepare unknown-field codex

write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"native-model","model":"opus"}}}}}'
new_run codex-native-machine
before_machine_native="$(dispatch_count codex-native-machine)"
expect_fail_contains "Codex native machine overrides name their source" "$XDG_CONFIG_HOME/dark-factory/config.json" \
  prepare codex-native-machine codex
expect_fail_contains "Codex native machine overrides name their field" "roles.codex.design_runners.standard.kind" \
  prepare codex-native-machine codex
after_machine_native="$(dispatch_count codex-native-machine)"
if [[ "$before_machine_native" == "$after_machine_native" ]]; then
  pass "Codex native machine overrides do not add a reservation"
else
  fail "Codex native machine overrides do not add a reservation" "before=$before_machine_native after=$after_machine_native"
fi

clear_overrides
mkdir -p "$PROJECT/.agents"
printf '%s\n' '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"native-model","model":"opus"}}}}}' >"$PROJECT/.agents/dark-factory.json"
new_run codex-native-project
before_project_native="$(dispatch_count codex-native-project)"
expect_fail_contains "Codex native project overrides name their source" "$PROJECT/.agents/dark-factory.json" \
  prepare codex-native-project codex
expect_fail_contains "Codex native project overrides name their field" "roles.codex.design_runners.standard.kind" \
  prepare codex-native-project codex
after_project_native="$(dispatch_count codex-native-project)"
if [[ "$before_project_native" == "$after_project_native" ]]; then
  pass "Codex native project overrides do not add a reservation"
else
  fail "Codex native project overrides do not add a reservation" "before=$before_project_native after=$after_project_native"
fi
clear_overrides

write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"missing_named_agent"}}}}}'
new_run missing-agent
expect_ok "prepare accepts a frozen target whose agent may disappear later" prepare missing-agent codex
before_missing="$(dispatch_count missing-agent)"
expect_fail_contains "preflight names a missing named agent" "missing_named_agent" \
  preflight missing-agent design_runners standard
after_missing="$(dispatch_count missing-agent)"
if [[ "$before_missing" == "$after_missing" ]]; then
  pass "missing-agent preflight does not reserve a dispatch"
else
  fail "missing-agent preflight does not reserve a dispatch" "before=$before_missing after=$after_missing"
fi
printf 'name = "missing_named_agent"\nmodel = "synthetic"\n' >"$CODEX_AGENTS_DIR/missing-named-agent.toml"
expect_fail_contains "a newly appearing agent cannot replace a frozen missing binding" "missing_named_agent was missing when the role plan was frozen" \
  preflight missing-agent design_runners standard

write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"identity_agent"}}}}}'
printf 'name = "identity_agent"\nmodel = "synthetic"\n' >"$CODEX_AGENTS_DIR/identity-agent.toml"
new_run identity-drift
expect_ok "prepare freezes a uniquely available named-agent definition" prepare identity-drift codex
printf 'name = "identity_agent"\nmodel = "changed"\n' >"$CODEX_AGENTS_DIR/identity-agent.toml"
expect_fail_contains "changed named-agent content is rejected before reservation" "identity_agent no longer matches the frozen definition identity" \
  preflight identity-drift design_runners standard

write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"ambiguous_agent"}}}}}'
printf 'name = "ambiguous_agent"\nmodel = "synthetic"\n' >"$CODEX_AGENTS_DIR/ambiguous-agent-one.toml"
printf 'name = "ambiguous_agent"\nmodel = "synthetic"\n' >"$CODEX_AGENTS_DIR/ambiguous-agent-two.toml"
new_run ambiguous-agent
expect_ok "prepare freezes an ambiguous named-agent binding as unavailable" prepare ambiguous-agent codex
expect_fail_contains "preflight names an ambiguous frozen named agent" "ambiguous_agent was ambiguous when the role plan was frozen" \
  preflight ambiguous-agent design_runners standard

echo "== immutable plans and atomic preparation =="
write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"terra_xhigh"}}}}}'
new_run frozen-config
frozen_plan="$(prepare frozen-config codex)"
expect_ok "prepare writes the initial frozen plan" test -n "$frozen_plan"
frozen_digest="$(json_field "$frozen_plan" 'planDigest')"
write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"sol_high"}}}}}'
frozen_role="$(resolve frozen-config design_runners standard)"
if [[ $(json_field "$frozen_role" 'target.agent') == '"terra_xhigh"' ]]; then
  pass "changed overrides cannot alter a prepared plan"
else
  fail "changed overrides cannot alter a prepared plan" "$frozen_role"
fi
repeat_plan="$(prepare frozen-config codex)"
repeat_check="$(node -e '
const plan = JSON.parse(process.argv[1]);
const row = plan.resolutions.find((item) => item.responsibility === "design_runners" && item.lane === "standard");
process.stdout.write(JSON.stringify({ digest: plan.planDigest, target: row.target }));
' "$repeat_plan")"
if [[ $(json_field "$repeat_check" 'digest') == "$frozen_digest" && \
      $(json_field "$repeat_check" 'target.agent') == '"terra_xhigh"' ]]; then
  pass "repeated preparation returns the original standard target and complete digest"
else
  fail "repeated preparation returns the original standard target and complete digest" "$repeat_plan"
fi

clear_overrides
new_run live-aged-lock
live_lock="$DF_STATE_ROOT/live-aged-lock/work/role-plan.lock"
mkdir -p "$live_lock"
printf 'pid=%s\tts=2026-01-01T00:00:00Z\n' "$$" >"$live_lock/owner"
touch -d '2 minutes ago' "$live_lock"
timeout 1 node "$ROLE" prepare-run --run live-aged-lock --harness codex --repo-root "$PROJECT" >"$WORK/live-aged-lock.json" 2>"$WORK/live-aged-lock.err"
live_lock_rc=$?
if [[ $live_lock_rc -eq 124 && -f "$live_lock/owner" && ! -f "$DF_STATE_ROOT/live-aged-lock/work/role-plan.json" ]]; then
  pass "a live aged role-plan lock is not preempted"
else
  fail "a live aged role-plan lock is not preempted" "exit=$live_lock_rc owner=$(test -f "$live_lock/owner" && printf present || printf missing)"
fi

new_run dead-lock-recovery
dead_lock="$DF_STATE_ROOT/dead-lock-recovery/work/role-plan.lock"
mkdir -p "$dead_lock"
printf 'pid=999999\tts=2026-01-01T00:00:00Z\n' >"$dead_lock/owner"
touch -d '2 minutes ago' "$dead_lock"
dead_lock_plan="$(prepare dead-lock-recovery codex)"
if [[ -f "$DF_STATE_ROOT/dead-lock-recovery/work/role-plan.json" && ! -d "$dead_lock" && -n "$dead_lock_plan" ]]; then
  pass "a dead role-plan lock owner is recovered"
else
  fail "a dead role-plan lock owner is recovered" "$dead_lock_plan"
fi

clear_overrides
mkdir -p "$WORK/concurrent-config-a/dark-factory" "$WORK/concurrent-config-b/dark-factory"
printf '%s\n' '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"terra_xhigh"}}}}}' >"$WORK/concurrent-config-a/dark-factory/config.json"
printf '%s\n' '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"sol_high"}}}}}' >"$WORK/concurrent-config-b/dark-factory/config.json"
new_run concurrent-prepare
XDG_CONFIG_HOME="$WORK/concurrent-config-a" node "$ROLE" prepare-run --run concurrent-prepare --harness codex --repo-root "$PROJECT" >"$WORK/prepare-a.json" 2>"$WORK/prepare-a.err" &
pid_a=$!
XDG_CONFIG_HOME="$WORK/concurrent-config-b" node "$ROLE" prepare-run --run concurrent-prepare --harness codex --repo-root "$PROJECT" >"$WORK/prepare-b.json" 2>"$WORK/prepare-b.err" &
pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?
concurrent_check="$(node -e '
const fs = require("fs");
const plans = [process.argv[1], process.argv[2], fs.readFileSync(process.argv[3], "utf8")].map(JSON.parse);
const row = (plan) => plan.resolutions.find((item) => item.responsibility === "design_runners" && item.lane === "standard");
process.stdout.write(JSON.stringify({ digests: plans.map((plan) => plan.planDigest), targets: plans.map(row).map((item) => item.target.agent) }));
' "$(cat "$WORK/prepare-a.json")" "$(cat "$WORK/prepare-b.json")" "$DF_STATE_ROOT/concurrent-prepare/work/role-plan.json")"
if [[ $rc_a -eq 0 && $rc_b -eq 0 && \
      $(json_field "$concurrent_check" 'digests.0') == $(json_field "$concurrent_check" 'digests.1') && \
      $(json_field "$concurrent_check" 'digests.1') == $(json_field "$concurrent_check" 'digests.2') && \
      $(json_field "$concurrent_check" 'targets.0') == $(json_field "$concurrent_check" 'targets.1') && \
      $(json_field "$concurrent_check" 'targets.1') == $(json_field "$concurrent_check" 'targets.2') ]]; then
  pass "distinct concurrent overrides return the one persisted winner digest and target"
else
  fail "distinct concurrent overrides return the one persisted winner digest and target" "exit-a=$rc_a exit-b=$rc_b output=$concurrent_check"
fi

clear_overrides
new_run truncated-plan
expect_ok "prepare writes a complete plan for truncation validation" prepare truncated-plan codex
node -e '
const crypto = require("crypto");
const fs = require("fs");
const stable = (value) => Array.isArray(value) ? value.map(stable) : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])])) : value;
const digest = (value) => crypto.createHash("sha256").update(JSON.stringify(stable(value))).digest("hex");
const path = process.argv[1];
const plan = JSON.parse(fs.readFileSync(path, "utf8"));
plan.responsibilities = plan.responsibilities.filter((item) => item !== "escalation");
plan.resolutions = plan.resolutions.filter((item) => item.responsibility !== "escalation");
const wanted = new Set(plan.resolutions.flatMap((item) => item.target.kind === "named-agent" ? [item.target.agent] : item.target.kind === "parallel" ? item.target.targets.filter((leaf) => leaf.kind === "named-agent").map((leaf) => leaf.agent) : []));
plan.namedAgentBindings = plan.namedAgentBindings.filter((item) => wanted.has(item.agent));
plan.policyDigest = digest(plan.resolutions);
delete plan.planDigest;
plan.planDigest = digest(plan);
fs.writeFileSync(path, JSON.stringify(plan));
' "$DF_STATE_ROOT/truncated-plan/work/role-plan.json"
expect_fail_contains "self-consistent truncated plans are rejected as incomplete" "invalid responsibility-by-lane matrix" \
  resolve truncated-plan design_runners standard

new_run frozen-codex-native-target
expect_ok "prepare writes a Codex plan for target compatibility validation" prepare frozen-codex-native-target codex
node -e '
const crypto = require("crypto");
const fs = require("fs");
const stable = (value) => Array.isArray(value) ? value.map(stable) : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])])) : value;
const digest = (value) => crypto.createHash("sha256").update(JSON.stringify(stable(value))).digest("hex");
const path = process.argv[1];
const plan = JSON.parse(fs.readFileSync(path, "utf8"));
const row = plan.resolutions.find((item) => item.responsibility === "design_runners" && item.lane === "high-consequence");
row.target = { kind: "parallel", targets: [{ kind: "native-model", model: "opus" }, { kind: "session" }] };
plan.policyDigest = digest(plan.resolutions);
delete plan.planDigest;
plan.planDigest = digest(plan);
fs.writeFileSync(path, JSON.stringify(plan));
' "$DF_STATE_ROOT/frozen-codex-native-target/work/role-plan.json"
expect_fail_contains "frozen Codex plans reject native targets inside parallel groups" "native-model targets require the Claude harness" \
  resolve frozen-codex-native-target design_runners high-consequence

new_run corrupted-plan
expect_ok "prepare writes a plan for corruption validation" prepare corrupted-plan codex
printf '{not valid json\n' >"$DF_STATE_ROOT/corrupted-plan/work/role-plan.json"
expect_fail_contains "corrupted frozen plans are rejected" "role plan" \
  resolve corrupted-plan design_runners standard

echo "== mirrors and direct preflight =="
if cmp -s "$SOURCE_ROOT/references/model-policy.json" "$CODEX_ROOT/references/model-policy.json" && \
   cmp -s "$SOURCE_ROOT/scripts/df-role.mjs" "$CODEX_ROOT/scripts/df-role.mjs" && \
   cmp -s "$SOURCE_ROOT/scripts/check-model-policy.mjs" "$CODEX_ROOT/scripts/check-model-policy.mjs" && \
   cmp -s "$SOURCE_ROOT/scripts/test-df-role-policy.sh" "$CODEX_ROOT/scripts/test-df-role-policy.sh" && \
   cmp -s "$SOURCE_ROOT/skills/df/references/model-policy.md" "$CODEX_ROOT/skills/df/references/model-policy.md"; then
  pass "both plugin roots ship matching policy, resolver, checker, tests, and docs"
else
  fail "both plugin roots ship matching policy, resolver, checker, tests, and docs" "one or more mirrored files differ"
fi
clear_overrides
new_run direct-preflight
expect_ok "direct preflight validates a shipped Codex named agent" preflight matrix-codex design_runners standard
if [[ $(dispatch_count matrix-codex) == 0 ]]; then
  pass "direct preflight leaves the external run reservation count unchanged"
else
  fail "direct preflight leaves the external run reservation count unchanged" "reserved=$(dispatch_count matrix-codex)"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
