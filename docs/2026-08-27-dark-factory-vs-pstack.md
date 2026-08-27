# Dark Factory and P Stack: Containing Long-Running Codex Work

**Date:** 2026-08-27

**Dark Factory checkout reviewed:** `8f95ca430e4281a383cbcdac262e3e39cedc6273`

**P Stack snapshot reviewed:** [`bdf7aa355337897f167153e05069aca505dae17c`](https://github.com/cursor/plugins/tree/bdf7aa355337897f167153e05069aca505dae17c/pstack)

## Executive summary

Dark Factory has strong delivery artifacts and safety intent: a hardened PRD,
traceable QA runbook, developer verification, multi-model review, and local/dev
QA safeguards. Its Codex execution control is the weak link. The active flow
combines broad autonomous remediation, repeated high-effort reviewer fan-out,
fresh CLI sessions, and several independently-owned loops without a shared run
budget or durable controller state. A feature can therefore continue consuming
time after the original value of another review/remediation pass has become low.

P Stack offers a useful control-plane shape, not a wholesale replacement. Its
three-lane intent router separates normal feature work from explicitly contracted
autonomous work and durable orchestration. The latter has the properties Dark
Factory currently lacks: plain-file state, explicit budgets, liveness/retry
rules, a single writer/worktree, SHA-keyed verification, and a context threshold
that stops further spawning around 70% utilization.

**Recommendation:** retain Dark Factory as the *delivery-quality layer* and add
a P Stack-style *run-control layer*. Default normal work to one implementation
delegate and matching-surface verification. Reserve autonomous multi-stage work
for an explicit contract. Make every multi-agent/review loop a budgeted,
persisted, lead-adjudicated operation.

This is a static audit, not a benchmark. The listed mechanisms are observed in
the checked instructions and runners; claims about a particular past runaway are
inferences that should be tested with instrumented runs.

## Scope, evidence, and drift

### What was inspected

- Current checkout: [Codex master orchestrator](../../codex-skills/dark-factory-codex/SKILL.md),
  [PRD challenge](../../codex-skills/drk-02-prd-challenge/SKILL.md),
  [QA validation](../../codex-skills/drk-04-qa-runbook-validation/SKILL.md),
  [developer verification](../../codex-skills/drk-05-dev-verify/SKILL.md), and
  [code review](../../codex-skills/drk-06-code-review/SKILL.md).
- The active `/home/dev/.codex` configuration, named worker profiles, installed
  skill copies, and their review runner scripts.
- The Superpowers workflows invoked by the master skill, especially
  brainstorming, plan writing, subagent-driven development, debugging, review
  reception, and verification-before-completion.
- Cursor's public P Stack plugin at commit `bdf7aa…`, including its routing,
  feature, autonomous-run, orchestration, and multi-model review playbooks.

### Important drift finding

The installed Codex `drk-02-prd-challenge` skill differs materially from the
checkout source. The installed file is a much shorter, older loop specification;
the checkout source adds trend-aware gates, remediation-delta verification,
growth/self-feeding detection, tooling retry limits, and explicit blocked/defer
outcomes. Its support scripts and references also differ.

This means the code reviewed in the checkout is not necessarily the behavior
being executed by Codex on this VM. The drift is both a reliability defect and an
observability defect: an operator may believe a guard is live when the installed
skill does not contain it. Treat synchronization and version attestation as a
prerequisite to evaluating any further orchestration change.

### Evidence versus inference

| Type | Statement |
|---|---|
| Observed | The global Codex configuration defaults the root to Sol/xhigh and default child work to Terra/xhigh; several review runners explicitly set xhigh effort without selecting a constrained reviewer profile. |
| Observed | Dark Factory runs several review/remediation loops, while Superpowers SDD runs per-task implementation/review/fix loops and a final whole-branch review. |
| Observed | The current runners create fresh `codex exec` sessions and some do not impose an internal process deadline. |
| Inference to test | Fresh CLI reviewers can behave as new root sessions and may re-enter broad orchestration unless given a leaf-only profile. |
| Inference to test | The combination of no global budget, state loss after compaction, and broad re-review explains multi-hour or multi-day runs more plausibly than model quality alone. |

## Lifecycle maps

### Current Dark Factory Codex lifecycle

```text
PRD interview
  -> PRD challenge: 3 Codex reviewers x up to 10 rounds
  -> Claude tmux review x up to 3 rounds
  -> QA runbook generation
  -> inline + fresh Codex CLI validation (up to 3 rounds)
  -> human sign-off
  -> Superpowers: brainstorm -> plan -> SDD
       each task: implement -> task review -> up to 5 fix/re-review rounds
       -> final whole-branch review
  -> developer verification: all suites + QA + fix/retest/re-run loop
  -> code review: 3 Codex reviewers x up to 10 rounds
  -> 2 Claude tmux reviewers x up to 3 rounds
  -> browser QA acceptance
```

The arrows conceal two properties that drive duration: most review gates require
zero Critical/High findings before continuing, and remediation can expand the
next review surface. The orchestrator intentionally drives later stages itself;
it is not merely an artifact handoff.

### P Stack lifecycle from the supplied comparison

```text
intent
  -> router
       -> normal feature lane
            bounded architecture -> one implementer -> matching-surface verify
            -> optional read-only interrogation -> lead adjudication
       -> autonomous-run lane
            explicit scope/authority/exit contract -> bounded execution
       -> orchestrate lane
            durable plain-file state -> budget/liveness/retry control
            -> one writer/worktree -> SHA-keyed verification
            -> stop spawning near 70% context -> summarize or escalate
```

P Stack makes the autonomy choice a first-class routing decision. Dark Factory
makes autonomy largely an emergent property of stages and skills that each carry
their own loop rules.

## Similarities and material differences

| Concern | Dark Factory today | P Stack comparison | Consequence |
|---|---|---|---|
| Quality artifacts | PRD, QA runbook, review reports, test evidence | Intent/contract and verification state | Dark Factory is stronger on requirements-to-QA traceability. |
| Default feature path | Full pipeline can lead into SDD and later review gates | One bounded architecture pass, one implementer, matching verification | P Stack has a cheaper, clearer default. |
| Autonomous work | Staged skills autonomously remediate many findings | Explicit autonomous-run contract | Dark Factory can become autonomous before authority, cost, and exit conditions are made explicit. |
| Orchestration state | Mixed chat “running records,” temp outputs, and SDD ledger | Durable plain-file controller state | Compaction/restart recovery is inconsistent in Dark Factory. |
| Reviewer authority | Several reviewers report; severity is generally promoted to the highest | Optional read-only interrogation; lead adjudicates | Review disagreement can drive more Dark Factory work rather than a decision. |
| Delegation | Parallel reviewer fans and fresh CLI processes | One writer/worktree; bounded specialists | Shared-state and child-process control are clearer in P Stack. |
| Verification identity | Tests and reviews are repeatedly rerun over growing surfaces | SHA-keyed verification evidence | Dark Factory can repeat work without proving the artifact changed. |
| Context management | SDD has a ledger, but other stages rely on conversational continuity | Stop spawning around 70%, snapshot durable state | P Stack has an explicit containment boundary. |
| Budgets and liveness | Per-stage caps exist, but no feature-wide budget; script timeouts vary | Run budget, retries, liveness, stop conditions | Local caps compound into long total runs. |

## Ranked Codex runaway causes

### 1. No feature-wide budget across compounded loops

The PRD challenge and code review both allow a 10-round primary phase and a
three-round secondary phase. SDD can add five fix/re-review rounds for every
task, then a final review. Developer verification can re-enter its loop when a
convergence run discovers new failures. No single source accounts for elapsed
time, reviewer calls, full-suite runs, or tokens across those loops.

**Action:** introduce a run ledger with hard aggregate budgets. All stages must
consume the same counters and stop with an evidence package when one is reached.

### 2. Fresh xhigh CLI reviewers are not leaf workers

The installed runners invoke `codex exec` with xhigh reasoning effort and user
configuration. They do not select a named read-only reviewer profile or state
that reviewer sessions must not plan, delegate, invoke skills, or spawn further
work. Native agent depth limits do not necessarily govern separate CLI roots.

**Action:** create a single explicit `df-reviewer` launch profile: read-only,
fixed model/effort, agents disabled, structured output, process deadline, and a
hard “review only” developer instruction. Every CLI runner must use it.

### 3. Broad re-review makes remediation self-feeding

PRD review asks multiple personas to rediscover gaps in the entire PRD after
each autonomous edit. Synthesis uses the highest assigned severity, treats a
reappearance as a regression, and remediates all Critical/High findings. Code
review similarly refreshes the full growing branch diff. Correct improvements can
therefore create fresh review surface faster than the gate can close it.

**Action:** use one discovery round, then make subsequent passes delta-scoped:
verify only accepted remediations plus a fixed unresolved-finding list. Require
specific evidence or corroboration to introduce a new Critical/High item after
the discovery round.

### 4. Progress state outside SDD is vulnerable to compaction and restart

Superpowers SDD correctly identifies compaction as a source of repeated task
dispatch and uses a durable ledger. The PRD and code-review skills instead retain
a conversational “running record” and write their durable report at the end.
Temp-output pointers do not by themselves identify which rounds have already
been synthesized or remediated.

**Action:** before each dispatch, persist a state record containing run ID,
stage, artifact SHA, round, reviewer outputs, finding dispositions, budgets, and
next action. Resume from this record only; never start another round blindly.

### 5. Timeouts and retries are inconsistent and leave liveness ambiguous

Several skill call sites request an external timeout, while their underlying
Codex runner simply waits for child processes. The Claude tmux helpers have a
deadline but intentionally leave a timed-out session running for inspection.
This can be useful diagnostically, but without ownership/reaping it risks
orphaned work and makes a later controller unsure whether to retry.

**Action:** give every spawned process a run ID, deadline, heartbeat/status
file, and one owner. On expiry, record a terminal state, reap the process group
or explicitly adopt it on resume, and apply one tooling retry at a new output
path before escalating.

### 6. Verification ownership is duplicated rather than compositional

SDD reviews each task and the whole branch. Developer verification runs tests,
QA, and a hard e2e-coverage gate. Code review’s spec reviewer independently
checks e2e coverage, then QA acceptance executes the runbook again. This can be
defensible as defense in depth, but the same missing coverage is rediscovered and
repaired at several gates.

**Action:** assign one primary owner to each assurance claim. Downstream stages
consume an immutable evidence record keyed to artifact SHA and only rerun when
that identity changes or an explicitly different surface is being tested.

### 7. Two control planes conflict on next action and stopping rules

Dark Factory says it owns stage transitions and overrides conflicting skill
chaining. Yet it calls Superpowers, whose plan and SDD instructions prescribe
their own execution handoff and branch-finishing path. The conflict is described
in prose, not represented in a state machine that tooling can enforce.

**Action:** define one explicit transition table. Superpowers becomes a bounded
implementation subroutine whose allowed terminal transition is `drk-05`, not a
separate pipeline owner.

### 8. Installation drift hides whether containment improvements are live

The newer checkout has stronger PRD-loop controls, but the active installed
skill is older. This invalidates confidence in both safeguards and evaluations.

**Action:** install from a versioned manifest, record skill package SHA in each
run state file, and fail preflight on source/installed drift.

## Why Claude Code can seem faster

This does **not** show that Claude is inherently faster or that its flow is
intrinsically safer. The installed Claude PRD challenge also contains broad
review/remediation loops.

The more credible explanation is control flow:

1. Dark Factory has a Codex-native master orchestrator that explicitly carries
   artifacts through all stages. The repository documents that the Claude flow
   has no equivalent master orchestrator yet; manual stage starts create natural
   human pauses.
2. Codex primary review phases use fresh xhigh Codex CLI reviewers, while the
   secondary phase starts interactive Claude tmux sessions with up to 30-minute
   windows. These stages can keep progressing without a new human decision.
3. Codex instruction stacks combine global orchestration rules, Dark Factory,
   and Superpowers. A fresh CLI session may receive the broad environment before
   it receives its narrowly worded review prompt.
4. A visible Claude pause may be a control benefit, not a performance failure:
   it forces reassessment of scope, remaining value, and authority before more
   work is spawned.

The appropriate evaluation is a matched-feature experiment: same PRD, same
environment, fixed model profiles, event logging, and a shared definition of
done. Compare time, cost, accepted defects, and human interventions—not only
whether one conversation appears shorter.

## What to adopt from P Stack

1. **Intent routing first.** Require a lane decision before any pipeline work:
   normal feature, autonomous-run, or orchestrate.
2. **Explicit autonomy contract.** Autonomous-run must declare objective,
   editable scope, worktree/branch, allowed side effects, quality gates, budget,
   and terminal outcomes.
3. **One durable controller record.** Use a plain, human-readable run file as
   the source of truth for state, decisions, process IDs, retries, and evidence.
4. **One writer/worktree.** Parallelism is appropriate for read-only analysis;
   source changes are serialized behind one writer/controller.
5. **Lead adjudication.** Reviewers provide evidence; a controller accepts,
   rejects, defers, or escalates each finding. Do not let the maximum reported
   severity alone schedule more work.
6. **SHA-keyed verification.** Store the artifact/diff/test-plan identity with
   each result and invalidate it only when the corresponding surface changes.
7. **Context pressure control.** Near 70% context, stop spawning, persist state,
   summarize, and either resume in a fresh controller or ask for a decision.

These recommendations align with OpenAI guidance to start with the simplest
viable orchestration, use clear exit conditions, and introduce multi-agent
systems only where roles are genuinely distinct: [agent design guide](https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/),
[model selection guide](https://platform.openai.com/docs/models), and
[GPT-5.6 builder guidance](https://openai.com/index/builders-guide-to-gpt-5-6/).

## What not to copy

- **Do not replace Dark Factory’s PRD/QA traceability with a generic task list.**
  Retain the PRD quality gate, coverage matrix, local/dev QA restriction, and
  evidence-oriented final reports.
- **Do not make normal work pay autonomous-run overhead.** A small feature should
  not require an orchestrator ledger, multiple models, or a full lifecycle.
- **Do not equate lead adjudication with ignoring reviews.** Preserve independent
  review for high-risk changes; make its scope, authority, and stopping rule
  explicit.
- **Do not parallelize writers merely because reviewers are parallel.** Continue
  to serialize edits in a shared worktree.
- **Do not copy numeric defaults as facts.** The policies below are hypotheses
  to test against representative features, not evidence-based production limits.
- **Do not silently downgrade verification.** Move duplicate checks to
  SHA-keyed evidence reuse before removing them.

## Initial lane and budget policies — hypotheses to evaluate

These numbers are intentionally conservative starting points. They need tuning
from observed task size, test duration, defect escape rate, and operator cost.

| Lane | Entry contract | Initial limits | Terminal action |
|---|---|---|---|
| Normal feature | Named files/surface, one acceptance target, no material external side effect | 1 architecture pass; 1 implementer; 1 matching-surface verification; optional 1 read-only reviewer; 75 minutes wall time | Return evidence and outstanding decisions; do not escalate into autonomous mode implicitly. |
| Autonomous-run | Approved PRD/QA, bounded edit scope, worktree, explicit authority | 2 implementation waves; 2 review rounds per wave; 2 full-suite barriers; 180 minutes wall time; 6 total agent calls | Stop with durable report and request a renewed/expanded contract. |
| Orchestrate | Written run contract, state path, single writer, liveness/retry owner | 1 writer; at most 2 concurrent read-only agents; 1 retry per tooling failure; 1 remediation retry per finding; stop spawning at 70% context; 240 minutes wall time | Snapshot state, reap/adopt children, and either hand off to a fresh controller or escalate. |

Across all lanes, use an initial **no-progress breaker**: if two consecutive
rounds do not reduce accepted blocking findings or change the relevant artifact
SHA, stop the loop. A lead must decide whether the remaining item is wrong,
deferred, a changed requirement, or a genuine blocker.

## Phased implementation plan

### Phase 0 — establish truth before changing behavior

1. Synchronize the installed Codex skills from the intended checkout revision.
2. Add a read-only preflight that records checkout SHA, installed skill package
   SHA, runner version, model profile, and active configuration.
3. Instrument existing runners to emit one structured event per dispatch,
   completion, retry, timeout, and gate decision.
4. Run two representative features without policy changes to establish baseline
   elapsed time, calls, full-suite runs, review findings, retries, and context
   handoffs.

**Exit criterion:** source/installed drift is zero and baseline traces are
available without recording prompts, credentials, or source contents.

### Phase 1 — contain reviewer and process fan-out

1. Introduce the leaf-only read-only reviewer profile and use it in every
   `codex exec` review runner.
2. Add internal process-group timeouts, run IDs, status files, and orphan reaping.
3. Require native subagent dispatches to use bounded context rather than history
   inheritance; pass paths to artifacts instead of transcripts.
4. Add a single pipeline-level call/time budget, initially in report-only mode.

**Exit criterion:** every child has an owner, deadline, model profile, and
durable terminal status; no orphan remains after a forced timeout test.

### Phase 2 — introduce the router and normal lane

1. Implement the three-lane router as an explicit user-visible decision.
2. Make normal feature the default, using one delegate and matching-surface
   verification rather than the whole autonomous lifecycle.
3. Make entry to autonomous-run require the written contract and budget shown
   above.
4. Keep existing Dark Factory artifacts as optional/required gates by lane and
   risk classification, rather than automatically running every gate.

**Exit criterion:** sampled normal features never invoke SDD or multi-model
review unless their route or risk rule explicitly requires it.

### Phase 3 — durable orchestration and evidence reuse

1. Build the plain-file run ledger/state schema.
2. Move PRD challenge, developer verification, and code review onto it one at a
   time; preserve artifact SHA and finding-disposition history.
3. Convert follow-up reviews to delta scope and SHA-keyed evidence reuse.
4. Enforce the no-progress breaker and 70% context checkpoint.

**Exit criterion:** restart/compaction simulations complete without duplicate
dispatch or duplicate remediation, and re-runs can identify exactly why prior
evidence was invalidated.

### Phase 4 — evaluate and tune

1. Compare baseline and hybrid runs on matched features.
2. Measure lead time, cost, agent calls, test minutes, duplicate findings,
   retries, human escalations, and post-merge defect escapes.
3. Tighten or relax lane budgets only from this evidence.
4. Review whether any Dark Factory stage can become a higher-risk-only gate.

**Exit criterion:** the hybrid reduces P95 autonomous-run duration and duplicate
work without worsening accepted-defect or escape metrics.

## Hybrid recommendation

Adopt **P Stack as the traffic controller and Dark Factory as the quality
toolkit**:

```text
intent router
  -> normal lane: bounded Dark Factory artifacts as needed
  -> autonomous-run: Dark Factory PRD/QA + controlled implementation/verification
  -> orchestrate: durable P Stack run state controlling all Dark Factory loops
```

The controller owns budgets, state, concurrency, retries, context thresholds,
and final escalation. Dark Factory owns requirements quality, test traceability,
review rubrics, local/dev safety, and durable human-readable reports. Read-only
reviewers advise; one lead/controller decides; one writer changes code.

That preserves the useful rigor of Dark Factory while preventing rigor from
turning into self-sustaining work.

## Evaluation scorecard

| Metric | Baseline to capture | Desired hybrid direction |
|---|---|---|
| P50/P95 elapsed time per feature | Stage and total wall time | Lower P95, fewer abandoned long runs |
| Agent calls / model effort | Calls by role and profile | Fewer xhigh calls; no accidental root reviewers |
| Full-suite and QA executions | Counts and minutes | Fewer duplicate barriers; unchanged confidence |
| Review convergence | Blocking findings and artifact SHA by round | Monotonic progress or explicit stop |
| Recovery correctness | Restart/compaction duplicate dispatches | Zero duplicates |
| Process hygiene | Orphaned CLI/tmux children | Zero after terminal state |
| Quality outcome | Accepted findings, escaped defects, rework | No regression while reducing work |
| Human control | Escalations, overrides, contract renewals | Decisions occur at defined boundaries |

## References

- [Dark Factory Codex orchestrator](../../codex-skills/dark-factory-codex/SKILL.md)
- [Dark Factory PRD challenge source](../../codex-skills/drk-02-prd-challenge/SKILL.md)
- [Dark Factory developer verification source](../../codex-skills/drk-05-dev-verify/SKILL.md)
- [Dark Factory code-review source](../../codex-skills/drk-06-code-review/SKILL.md)
- [Dark Factory installation model](../../CLAUDE.md)
- [P Stack snapshot reviewed](https://github.com/cursor/plugins/tree/bdf7aa355337897f167153e05069aca505dae17c/pstack)
- [P Stack feature playbook](https://github.com/cursor/plugins/blob/bdf7aa355337897f167153e05069aca505dae17c/pstack/skills/poteto-mode/playbooks/feature.md)
- [P Stack autonomous-run playbook](https://github.com/cursor/plugins/blob/bdf7aa355337897f167153e05069aca505dae17c/pstack/skills/poteto-mode/playbooks/autonomous-run.md)
- [P Stack orchestration playbook](https://github.com/cursor/plugins/blob/bdf7aa355337897f167153e05069aca505dae17c/pstack/skills/poteto-mode/playbooks/orchestrate.md)
- [OpenAI: a practical guide to building agents](https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/)
- [OpenAI: Models](https://platform.openai.com/docs/models)
- [OpenAI: builder’s guide to GPT-5.6](https://openai.com/index/builders-guide-to-gpt-5-6/)
