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
printf '%s\n' '---' 'name: df-reviewer-recheck' '---' >"$CLAUDE_AGENTS_DIR/df-reviewer-recheck.md"

echo "== shipped matrix and parallel targets =="
clear_overrides
new_run matrix-claude
claude_plan="$(prepare matrix-claude claude)"
if [[ $(json_field "$claude_plan" 'resolutions.length') == 42 ]]; then
  pass "shipped Claude policy freezes all 14 responsibilities across three lanes"
else
  fail "shipped Claude policy freezes all 14 responsibilities across three lanes" "$claude_plan"
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
  if HOME="$WORK/isolated-home" DF_CLAUDE_AGENTS_DIR= CLAUDE_AGENTS_DIR= \
    node "$ROLE" preflight --run matrix-claude --responsibility recheck_leaf_reviewers --lane standard --repo-root "$PROJECT" >/dev/null 2>&1; then
    pass "source mode finds the bundled Claude named agent"
  else
    fail "source mode finds the bundled Claude named agent" "bundled agent lookup failed"
  fi
else
  pass "Codex plugin accepts its operator-local Claude agent definition"
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
write_machine_override '{"schemaVersion":1,"unexpected":true}'
new_run unknown-field
expect_fail_contains "unknown field names its config source" "$XDG_CONFIG_HOME/dark-factory/config.json" \
  prepare unknown-field codex
expect_fail_contains "unknown field names the exact field" "unexpected" \
  prepare unknown-field codex

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

echo "== immutable plans and atomic preparation =="
write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"terra_xhigh"}}}}}'
new_run frozen-config
expect_ok "prepare writes the initial frozen plan" prepare frozen-config codex
write_machine_override '{"schemaVersion":1,"roles":{"codex":{"design_runners":{"standard":{"kind":"named-agent","agent":"sol_high"}}}}}'
frozen_role="$(resolve frozen-config design_runners standard)"
if [[ $(json_field "$frozen_role" 'target.agent') == '"terra_xhigh"' ]]; then
  pass "changed overrides cannot alter a prepared plan"
else
  fail "changed overrides cannot alter a prepared plan" "$frozen_role"
fi
repeat_role="$(prepare frozen-config codex)"
if [[ $(json_field "$repeat_role" 'resolutions.20.target.agent') != '"sol_high"' ]]; then
  pass "repeated preparation returns the existing frozen plan"
else
  fail "repeated preparation returns the existing frozen plan" "$repeat_role"
fi

new_run concurrent-prepare
prepare concurrent-prepare codex >"$WORK/prepare-a.json" 2>"$WORK/prepare-a.err" &
pid_a=$!
prepare concurrent-prepare codex >"$WORK/prepare-b.json" 2>"$WORK/prepare-b.err" &
pid_b=$!
wait "$pid_a"; rc_a=$?
wait "$pid_b"; rc_b=$?
if [[ $rc_a -eq 0 && $rc_b -eq 0 && -f "$DF_STATE_ROOT/concurrent-prepare/work/role-plan.json" ]]; then
  pass "concurrent preparation publishes one complete plan without clobbering"
else
  fail "concurrent preparation publishes one complete plan without clobbering" "exit-a=$rc_a exit-b=$rc_b"
fi

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
