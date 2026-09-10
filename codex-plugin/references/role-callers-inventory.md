# Role caller inventory

The session hook reports the Dark Factory root. Let `<df-root>` be that exact
path. Read this inventory and invoke its runtime helpers from `<df-root>`, not
from a consumer checkout or a copied global skill directory.

Every dispatch begins from a frozen plan. At run entry, after
`<df-root>/scripts/df-state.sh init`,
prepare it once with the active harness and consuming repository root:

```bash
node <df-root>/scripts/df-role.mjs prepare-run \
  --run <run-id> --harness <claude|codex> --repo-root <consumer-root>
```

The plan stays in external run state. Resume uses it. A caller never prepares a
replacement after an override or agent definition changes.

Shell-owned callers use `<df-root>/scripts/df-role-caller.sh reserve`. It checks
the active run lane, preflights the declared role, rejects a target the caller
cannot represent, prints the result, then reserves. The caller completes each
sequence with `<df-root>/scripts/df-state.sh complete`.

| Caller | Harness | Responsibility | Target it can run | Reservation owner |
| --- | --- | --- | --- | --- |
| `scripts/df-codex-exec.sh` | Claude | `cross_model_review` | `transport:codex-cli` | transport, one per turn and retry |
| `scripts/df-codex-review.sh` | Claude | `cross_model_review` | `transport:codex-cli` | review wrapper |
| `skills/df-code-review/scripts/run_codex_quality_review.sh` | Claude | `cross_model_review` | `transport:codex-cli` | quality runner |
| `skills/df-code-review/scripts/run_codex_spec_review.sh` | Claude | `cross_model_review` | `transport:codex-cli` | spec runner |
| `skills/df-prd-challenge/scripts/run_codex_prd_review.sh` | Claude | `cross_model_review` | `transport:codex-cli` | detached PRD runner |
| `skills/df-qa-validation/scripts/run_codex_qa_validation.sh` | Claude | `cross_model_review` | `transport:codex-cli` | QA runner |
| `codex-plugin/skills/df-code-review/scripts/run_codex_subagent_reviews.sh` | Codex | `persona_reviewers_cli` | `cli` | one reservation for each reviewer |
| `codex-plugin/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh` | Codex | `cross_model_review` | `transport:claude-tmux` | one reservation for each Claude reviewer |
| `codex-plugin/skills/df-prd-challenge/scripts/run_codex_persona_reviews.sh` | Codex | `persona_reviewers_cli` | `cli` | one reservation for each persona |
| `codex-plugin/skills/df-prd-challenge/scripts/run_claude_prd_review_tmux.sh` | Codex | `cross_model_review` | `transport:claude-tmux` | PRD tmux transport |
| `codex-plugin/skills/df-qa-validation/scripts/run_codex_qa_validation.sh` | Codex | `persona_reviewers_cli` | `cli` | QA runner |

## Native harness contract

Native callers use the same frozen plan without adding a CLI transport. Before
any child starts, set the exact policy responsibility, the leaf count for this
one role invocation, and the parent sequence when this is nested work.
Run this command from any directory:

```bash
df_root="<Dark Factory root reported by the session hook>"
run_id="<run-id>"
lane="<quick|standard|high-consequence>"
consumer_root="<absolute consuming repository root>"
responsibility="<exact responsibility from the table below>"
leaf_count="<ordered target leaves for this invocation, normally 1>"
parent_seq="<parent sequence, or empty for a top-level dispatch>"

case "<active harness>" in
  claude) native_kinds=(--allow-kind session --allow-kind native-model --allow-kind named-agent) ;;
  codex) native_kinds=(--allow-kind session --allow-kind named-agent) ;;
  *) echo "unsupported native harness" >&2; exit 1 ;;
esac

preflight_json=$(bash "$df_root/scripts/df-role-caller.sh" preflight \
  --run "$run_id" --responsibility "$responsibility" --lane "$lane" \
  --repo-root "$consumer_root" --dispatch-count "$leaf_count" \
  "${native_kinds[@]}") || exit $?

target_rows=$(node - "$preflight_json" "<active harness>" <<'NODE'
const [text, harness] = process.argv.slice(2);
const result = JSON.parse(text);
const leaves = result.target.kind === "parallel" ? result.target.targets : [result.target];
for (const target of leaves) {
  if (harness === "claude" && target.kind === "session") console.log("session\tinherit");
  else if (harness === "claude" && target.kind === "native-model") console.log(`native-model\t${target.model}`);
  else if (harness === "claude" && target.kind === "named-agent") console.log(`named-agent\t${target.agent}`);
  else if (harness === "codex" && target.kind === "session") console.log("session\tinherit");
  else if (harness === "codex" && target.kind === "named-agent") console.log(`named-agent\t${target.agent}`);
  else throw new Error(`unsupported native target '${target.kind}' for ${harness}`);
}
NODE
) || exit $?
[[ "$(printf '%s\n' "$target_rows" | sed '/^$/d' | wc -l)" -eq "$leaf_count" ]] || exit 1
```

The preflight adapter validates the supported kinds and ordered parallel leaf
count before it prints JSON. Inspect `target_rows`; do not discard it. Apply
each row to one native child call in order:

A site that repeats a single-leaf role for several independent workers runs
this contract once per worker with `leaf_count=1`. It does not claim that a
single-leaf target is a parallel group. A Claude High-consequence
`design_runners` invocation is the current two-leaf ordered exception. Its
`leaf_count` is 2 and one preflight governs those two returned leaves.

| Harness | Returned leaf | Native child selection |
| --- | --- | --- |
| Claude | `session` | Omit `model` and `subagent_type`; inherit the parent session. |
| Claude | `native-model` | Set the Agent tool's `model` to the returned model. Omit `subagent_type`. |
| Claude | `named-agent` | Set the Agent tool's `subagent_type` to the returned agent. Omit `model`. |
| Codex | `session` | Omit `agent_type`, `model`, and `reasoning_effort`; inherit the parent session. |
| Codex | `named-agent` | Set `spawn_agent.agent_type` to the returned agent. Omit `model` and `reasoning_effort`. |

`cli`, `transport`, and any other kind are unsupported at a native-only site.
The preflight must stop before reservation or launch when one appears. A
preflight usage error permits one correction after reading
`bash "$df_root/scripts/df-role-caller.sh" --help`; it does not permit inline
work, another responsibility, a substituted target, or a new role plan.

After successful preflight and inspection, reserve one sequence for every row,
in the same order, before issuing the native child calls:

```bash
seqs=()
while IFS=$'\t' read -r target_kind target_value; do
  reserve_args=(reserve "$run_id" "$responsibility" "<specific child purpose>")
  [[ -z "$parent_seq" ]] || reserve_args+=("$parent_seq")
  seq=$(cd "$consumer_root" && bash "$df_root/scripts/df-state.sh" "${reserve_args[@]}") || {
    for open_seq in "${seqs[@]}"; do
      (cd "$consumer_root" && bash "$df_root/scripts/df-state.sh" complete "$run_id" "$open_seq" failed) || true
    done
    exit 1
  }
  seqs+=("$seq")
done <<< "$target_rows"
```

Pair each sequence with its row and child call. The parent native caller owns
terminal completion, including a resumed child call. Record `ok` when the child
tool call completes, `failed` when launch or execution fails, and `expired`
when the child becomes unreachable after its deadline:

```bash
(cd "$consumer_root" && bash "$df_root/scripts/df-state.sh" complete \
  "$run_id" "${seqs[$leaf_index]}" "<ok|failed|expired>")
```

Do not leave a reserved sequence pending. A task-level `BLOCKED` result can
still have dispatch outcome `ok` when the child call itself completed and
returned that result.

## Native caller inventory

The row names are the exact sites that issue native child calls. The skill
parent named in the last column owns every terminal completion.

| Skill site | Exact responsibility | Native leaf or leaves | Completion owner |
| --- | --- | --- | --- |
| `arena`, candidate fan-out | `design_runners` | Claude High-consequence uses its two ordered leaves; Codex repeats one single-leaf invocation per candidate | `arena` parent |
| `df-code-review`, discovery and operator-invoked second opinion | `discovery_reviewers` | one single-leaf invocation per in-session reviewer | `df-code-review` parent |
| `df-code-review`, fresh delta verification | `recheck_leaf_reviewers` | one single-leaf invocation per verifier | `df-code-review` parent |
| `df-design`, candidate sketch runners | `design_runners` | Claude Standard has one leaf and High-consequence has two ordered leaves; Codex repeats one single-leaf invocation per required runner | `df-design` parent |
| `df-eval`, scenario and retro graders | `eval_graders` | one per grader | `df-eval` parent |
| `df-implement`, task implementer and rounds 1 to 3 | `implementation_delegate` | one per task or fix call | `df-implement` parent |
| `df-implement`, task reviewer and re-reviewer | `recheck_leaf_reviewers` | one per review call | `df-implement` parent |
| `df-implement`, fresh implementer in rounds 4 and 5 | `judgment_delegate` | one per fix call | `df-implement` parent |
| `df-plan`, read-only planning explorers | `menial_scoped_investigation` | one per explorer | `df-plan` parent |
| `df-prd-challenge`, discovery and full persona reviewers | `discovery_reviewers` | one single-leaf invocation per reviewer | `df-prd-challenge` parent |
| `df-prd-challenge`, downgraded rechecks and fresh delta verifiers | `recheck_leaf_reviewers` | one single-leaf invocation per reviewer | `df-prd-challenge` parent |
| `how`, explorers | `menial_scoped_investigation` | one per explorer | `how` parent |
| `how`, explainer | `investigation_synthesizer` | one explainer | `how` parent |
| `how`, optional same-family critic | `judgment_delegate` | one critic | `how` parent |
| `interrogate`, native reviewer | `discovery_reviewers` | one reviewer | `interrogate` parent |
| `recall`, large-trail readers | `menial_scoped_investigation` | one per reader | `recall` parent |
| `swarm`, read-only worker | `menial_scoped_investigation` | one per worker | `swarm` parent |
| `swarm`, writing worker | `implementation_delegate` | one per worker | `swarm` parent |
| `why`, source investigators | `menial_scoped_investigation` | one per investigator | `why` parent |
| `why`, final synthesizer | `investigation_synthesizer` | one synthesizer | `why` parent |

`df` prepares the frozen role plan and routes dispatches to the owning skill;
it does not add another child call. `df-qa-validation` runs its first review in
the orchestrator session and delegates the second to its listed shell wrapper;
it has no native child site.

If `implementation_delegate` resolves to `luna_max` and the documented parent
limitation applies, the operator chooses the explicit `terra_xhigh` override
before preparing the run. Callers do not substitute it on their own.

`df-codex-exec.sh` remains a Claude-to-Codex durable transport. Native Codex
subagents never route through it. A caller that cannot represent its frozen
target stops before reservation and worker start.
