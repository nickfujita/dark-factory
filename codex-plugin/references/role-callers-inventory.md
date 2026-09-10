# Role caller inventory

Every dispatch begins from a frozen plan. At run entry, after `df-state.sh init`,
prepare it once with the active harness and consuming repository root:

```bash
node <plugin-root>/scripts/df-role.mjs prepare-run \
  --run <run-id> --harness <claude|codex> --repo-root <consumer-root>
```

The plan stays in external run state. Resume uses it. A caller never prepares a
replacement after an override or agent definition changes.

Shell-owned callers use `scripts/df-role-caller.sh reserve`. It checks the
active run lane, preflights the declared role, rejects a target the caller
cannot represent, prints the result, then reserves. The caller completes each
sequence with `df-state.sh complete`. Native harness callers use its
`preflight` mode before their native reservation and spawn. A parallel target
reserves one sequence for each actual native leaf.

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

All other background calls originate in skill instructions. They declare a role
from `model-policy.json`, preflight it at the common boundary, reserve after
that preflight, then use the target's native mechanism. A Codex native spawn
uses the resolved named agent. If `implementation_delegate` resolves to
`luna_max` and the documented parent limitation applies, the operator chooses
the explicit `terra_xhigh` override before preparing the run. Callers do not
substitute it on their own.

`df-codex-exec.sh` remains a Claude-to-Codex durable transport. Native Codex
subagents never route through it. A caller that cannot represent its frozen
target stops before reservation and worker start.
