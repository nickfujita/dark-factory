---
name: arena
description: "Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it. High-consequence lane only, invoked by the operator by hand for /arena or 'throw it in the arena'. Never a default step. Never enter on your own."
disable-model-invocation: true
---

# Arena

Fan out N parallel attempts at the same task. Read every candidate end to end. Pick the strongest as the base. Graft the best ideas from the others into it. Verify the synthesized result.

The arena is token-expensive by design and gated accordingly. It runs only in the High-consequence lane, only when the operator invokes it by hand, and never as a default step of any playbook. df-design owns routine design exploration; the arena is for work where one attempt at a non-trivial artifact would lock in the wrong shape, and the operator has judged the redundancy worth paying for. Inside a df run, reserve every candidate and the judge through `scripts/df-state.sh` before spawning; they are nested dispatches against the run's budget. The script lands in this same wave; until it is on disk, write the reservation lines to the run state file by hand, still before spawning.

Principle names in this skill cite `../df/references/principles.md`.

## Start

Open a todo list with one entry per phase before launching anything. The arena runs autonomously and the list keeps phases from silently disappearing.

1. Frame
2. Fan out
3. Cross-judge
4. Pick
5. Graft
6. Verify

## Phase A: Frame

The N candidates receive the same prompt, so the prompt is the contract. Get it right before spawning anything.

1. State the artifact each candidate is producing.
2. Derive the rubric. State what success looks like for *this* task, then turn it into 3 to 6 concrete gradeable criteria. Concrete: `Adds a --dry-run flag that skips writes`. Vague: `code is correct`. The rubric is the picker's tool in Phase D; candidates only see the task.
3. Pick the runners. The panel resolves through the `design_runners` role in `../df/references/model-policy.md`, never a hardcoded slug; the arena runs in the High-consequence lane, so the role's full panel runs. The operator may name extra arms when the arena covers multiple design directions, and the same model N times is right when the work is generation-bound rather than judgment-sensitive.
4. Assign output paths. Each candidate writes to its own git worktree, per the separate-before-serializing-shared-state principle; N candidates writing to one path is shared mutable state. A per-candidate subdirectory under the session scratchpad serves only for artifacts that do not live in the repo.

## Phase B: Fan out

Spawn all N candidates with the Agent tool, in the background, in one message. Each gets the task, a pointer to the shared grounding, its own output path, and instructions to produce both the artifact and a short rationale.

The rationale is mandatory. Without it, the parent cannot tell whether a candidate's structure is principled or accidental, which makes Phase E grafting unreliable. Each rationale names the alternatives the candidate considered and what it rejected.

If a candidate fails to produce output, proceed with N-1 and note the dropout in the synthesis record.

## Phase C: Cross-judge

After all candidates complete, dispatch one read-only judge. Send it through the cross-model transport named in `../df/references/model-policy.md`, preferring the other model family from the session's; different families disagree in ways a same-family judge cannot. When the cross-family leg is unavailable or its usage window is exhausted, fall back to a read-only same-family judge and record the substitution in the synthesis note, because the pick still needs an independent check.

The judge sees the rubric and the candidates by path label, scores each criterion, and recommends a base with rationale. It runs in parallel with the parent's own reading in Phase D, never with the candidates still writing. A judge spawned while candidates are mid-write sees partial or empty outputs and reports them as dropouts.

## Phase D: Pick a base

Read every candidate end to end before picking. Skimming N candidates surfaces only the candidate whose surface looks most familiar.

Score each candidate against the rubric criterion by criterion, not on holistic feel. Compare against the cross-judge. Agreement on the base confirms the pick. Disagreement means one of you is biased or the rubric was ambiguous; read both rationales before deciding.

Pick the base on which candidate a future maintainer can extend most easily without breaking invariants. Prefer the cleaner boundary or smaller surface area when two feel tied, per the laziness-protocol principle.

Record the pick and the reason in a short synthesis note alongside the base artifact, including the cross-judge's verdict.

## Phase E: Graft

Walk each losing candidate once more and identify what is worth porting into the base. The signal is usually one or two things per candidate, not most of it.

Fold each graft in by hand, per the redesign-from-first-principles principle. Don't paste mechanically. The result has to remain coherent under one mental model.

Record what was grafted, from which candidate, and what was rejected and why. The rejection notes are the highest-signal part of the record. Future readers learn from what you considered and dropped, not just what you kept.

When N candidates converge on the same shape, that is a strong agreement signal. Note the convergence in the record and ship the consensus shape; no graft is needed. When N candidates wildly diverge, Phase A was under-specified. Reframe and re-run rather than averaging the divergence.

## Phase F: Verify

The synthesized artifact has to hold up under the same scrutiny as any other output, per the prove-it-works principle. The arena does not earn you a pass.

If verification surfaces a problem the arena did not catch, either Phase A was wrong (re-frame and re-run) or one candidate caught it and you missed the graft (go back to Phase E). Don't paper over.

## Outputs

One synthesized artifact. One short synthesis note alongside, naming the base, the grafts with their source candidates, the rejections, the dropouts if any, the judge substitution if one happened, and the verification result.
