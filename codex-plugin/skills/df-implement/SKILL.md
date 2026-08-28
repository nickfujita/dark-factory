---
name: df-implement
description: "Implementation stage for routed work. Executes the plan task by task with a fresh implementer per task, one independent two-verdict review, a capped fix loop, and an on-disk ledger the later stages consume. Runs when the df feature playbook reaches the implementation step or the operator invokes $df-implement. Never enter on your own."
---

# df-implement

Execute the implementation plan. You own the design and the program. Delegate the code-writing. Review every diff yourself. The economy is a fresh implementer per task from an extracted brief, one independent review per task with two verdicts, and a capped fix loop. On one measured feature it cost about 1.5x and caught five faults that passed a 16.7k-test suite. It is the pipeline's one measured win. Keep it intact.

Delegating the code-writing is mandatory. No skip-with-reason escape, and the laziness-protocol principle does not override it. The gain is review separation, not lines saved. You can spawn a subagent even though you are one. Your workers cannot. They own their diffs directly, and review arrives from you.

Principle names in this skill cite `../df/references/principles.md`.

Narrate at most one short line between tool calls. The ledger and the tool results carry the record.

## Inputs

- The plan, one todo per task, from df-plan. It comes from df-plan.
- The spec. The PRD in the Standard and High-consequence lanes, the recorded finish predicate in Quick. The spec is the binding authority and the plan is its argument. Conflicts resolve against the spec. A plan with no reachable spec gets a ledger note, and rulings made without one are provisional.
- The lane, from the run state. It sets the TDD rule and the budgets.

## Setup

Work in an isolated worktree. Verify one exists for this run or create it. Never implement on the default branch without the operator's explicit consent. One writer per worktree. Never run two implementers in parallel.

Read the plan once. Note its global constraints. Create one todo per task. Then scan it once for conflicts before Task 1: tasks that contradict each other or the constraints, a task's tests against its own code, anything the plan mandates that the review rubric calls a defect. Rule on what you find, ledger each ruling, and dispatch Task 1. The review loop stays the net for conflicts that only emerge from implementation.

## Budget and ledger

The task ledger lives in the run state store outside the repo, the single authoritative record per run. `scripts/df-state.sh` is the accessor. The script lands in this same wave; until it is on disk, append the same lines to the run state file by hand, reservation still before spawn.

- Reserve every dispatch through `scripts/df-state.sh` **before** spawning. A dispatch is counted the moment it is reserved, not when it returns. A spawn without a reservation is a budget leak.
- Nested dispatches count against the parent budget. When df-implement itself runs as a dispatched stage, its implementers, reviewers, and re-reviewers draw down the run's budget, never a fresh one.
- Budget exhaustion is a stop, not a flag. Record the state, surface it to the operator, stop dispatching.
- The ledger is the recovery map. Conversation memory does not survive compaction, and controllers that lost their place have re-dispatched entire completed task sequences. At start, check the ledger. A task with a `complete` line is done; never re-dispatch it. A task whose last line is a fix round is mid-loop; resume at the next round. After compaction, trust the ledger and `git log` over your own recollection.

Ledger line formats:

- `Task <N>: complete (commits <base7>..<head7>, review clean)`
- `Task <N>: complete (commits <base7>..<head7>, <K> parked)`
- `Task <N>: fix round <R>/5 (<X> addressed, <Y> open; commits <a7>..<b7>)`
- `Task <N>: minor (deferred): <one-liner>`
- `Task <N>: parked: <finding>. Ruling: <why the code stands>`
- `Task <N>: Ruling: <what you decided>; <why>; <cost if wrong>`

Briefs, reports, and review packages live beside the ledger in the run state directory.

## Model tiering

Every spawn resolves a role through `../df/references/model-policy.md`, never a hardcoded model slug.

- Implementers run the `implementation_delegate` role. When the plan text contains the complete code to write, the work is transcription plus testing; use the menial tier for that implementer, and for batched mechanical edits.
- Task reviewers and re-reviewers run the `recheck_leaf_reviewers` role. It is a floor, the one pin allowed to exceed a throttled session, because its job is to keep the review meaningful.
- Fix rounds 4 and 5 dispatch on the judgment tier, the session model via inherit. When the session is throttled at or below the implementation tier, the escalation is fresh eyes alone. Dispatch it anyway.

## Rulings, not stalls

Execute every task without pausing to check in between tasks. Progress summaries and "should I continue?" prompts waste the operator's time. Conflicts, ambiguities, and plan defects are yours to decide: rule with the spec as the binding authority, write the ruling to the ledger, keep going. A wrong ruling costs rework the operator can see and undo. A session parked on a question costs their whole day.

Five things stop you, and only these: an irreversible or destructive operation; a security-sensitive action; a side effect outside the worktree, such as a merge, a push to a shared branch, or a publish; budget exhaustion; and a plan so broken that every path forward is a guess.

## The task loop

Background spawns return on their own. Never poll with short sleeps. Drive a long wait with a bounded polling loop, an explicit poll interval and a hard overall cap, and do local bookkeeping while workers run.

### 1. Brief and dispatch

Extract the task's full text from the plan into a brief file in the run state directory. The brief is the single source of requirements, exact values verbatim. Never hand a worker the whole plan, and never paste accumulated prior-task history into a dispatch.

The dispatch brief carries every field. A field you cannot fill is a task you have not scoped yet.

```
GOAL        one sentence, the outcome, executable by a stranger with no chat access
SCOPE       exact file paths this task may write, and paths it may not
SHAPE       the named data shape and its organizing structure, chosen before the
            delegate writes logic: a state machine over scattered booleans, a
            table over branching, a typed model over repeated shape assumptions
            (the model-the-domain principle)
CONTEXT     file pointers; interfaces and decisions from earlier tasks the brief
            cannot know; your resolution of any ambiguity you noticed; a pointer
            to any ledger finding parked in the area this task touches
ACCEPTANCE  checkable criteria, one per line
VERIFY      exact commands, plus known gotchas
TIMEBOX     rough cap on runtime; on expiry, return partial findings and stop
FORBIDDEN   no subagents, no rebase, no force-push, no fixes outside scope,
            plus task-specific bans
REPORT      the report file path and the status contract
```

Batch small same-shape work. Several tasks that are each the same one-line fix, constant change, or field addition across files become one dispatch listing every file and its change, reviewed as one unit. One-dispatch-per-task is for work that needs its own judgment, tests, or review surface.

Record BASE with `git rev-parse HEAD` before dispatching. Record the worker's agent identity from the dispatch result; rounds 1 to 3 of the fix loop resume it. Dispatch as a background native Codex subagent, per `references/implementer-prompt.md`.

### 2. Handle the report

- **DONE.** Package the diff and dispatch the task review.
- **DONE_WITH_CONCERNS.** Read the concerns first. Correctness or scope concerns get addressed before review. Observations get noted and carried into the review dispatch.
- **NEEDS_CONTEXT.** Answer completely and re-dispatch. Do not rush the worker into implementation.
- **BLOCKED.** Assess. A context problem gets more context. A reasoning problem gets a more capable tier. An oversized task gets split. A wrong plan gets a ruling, ledgered and carried in the re-dispatch. Never force an unchanged retry; if the worker said it is stuck, something changes.

### 3. The task review

One independent reviewer per task, returning two verdicts: spec compliance and code quality. Never skip it, and never accept a report missing either verdict. The worker's self-review never substitutes. This gate is task-scoped; the whole-branch review belongs to df-code-review, later.

Package the diff once per review. Run `git log --oneline BASE..HEAD`, `git diff --stat BASE..HEAD`, and `git diff -U10 BASE..HEAD`, redirected into one uniquely named file in the run state directory. The output never enters your context. Never derive a task's diff from `HEAD~1`; it silently drops all but the last commit of a multi-commit task. Never dispatch a reviewer without a diff file.

Reviewers follow the df router's reviewer transport rule. Create a disposable snapshot with `git worktree add --detach <scratch path> HEAD`, pass its path in the dispatch, and delete it after the verdict. Any inspection beyond the diff file happens there, never in the live tree.

The reviewer gets the brief file, the report file, the diff file, the snapshot path, and the binding constraints copied verbatim from the plan or spec. Do not add open-ended directives, and do not pre-judge findings for it. If the prompt you are writing contains "do not flag" or "at most Minor", stop; adjudication has a place, and it is not here.

The reviewer may return cannot-verify items, requirements that live in unchanged code or span tasks. Resolve each one yourself before marking the task complete. A confirmed gap is a failed spec verdict and enters the fix loop.

Dispatch per `references/task-reviewer-prompt.md`.

### 4. The fix loop

The loop triggers on a failed spec verdict, any Critical or Important finding, or a cannot-verify item you confirmed as a real gap.

Two routes leave before the loop starts:

- Minor findings go to the ledger as deferred, never into the loop. df-code-review consumes the list and triages which must be fixed before merge.
- A finding that conflicts with what the plan's text mandates gets a ruling first, spec as authority, ledgered before you act.

Everything else enters. A fix round is one fix dispatch plus one scoped re-review. Five rounds maximum per task.

- **Rounds 1 to 3.** Resume the original implementer with the open findings verbatim. Its context is intact. If the harness cannot resume it, dispatch fresh with the brief path, the report path, and the findings; the report file is the persistent memory either way.
- **Rounds 4 and 5.** Dispatch a fresh implementer on the judgment tier, with the brief path, the report path, the open findings, and this framing: "A prior implementer attempted this task N times; you own it now. Read the report file for what was tried." A loop that survives three resumes usually means the implementer cannot see its own problem.

Every round, the implementer fixes, re-runs the tests covering the amended code, and appends a fix report to the same report file. Confirm the fix report names the covering tests, the command, and the output before dispatching the re-review.

The re-review is scoped to the fix delta, never a whole-task re-read. Package `FIX_BASE..HEAD` only, where FIX_BASE is the head the previous review saw, and dispatch per `references/re-review-prompt.md`. It verdicts each finding ADDRESSED or NOT ADDRESSED and inspects the fix diff for new breakage. New Critical or Important breakage in the fix diff joins the open findings. Out-of-scope observations go to the ledger as deferred minors; they never extend the loop.

Write the round's ledger line after each round. Never fix findings yourself in the controller session; your context stays clean for coordination, and controller fixes skip review.

### 5. The breaker

When round 5's re-review still leaves findings open, stop dispatching. Adjudicate each open finding yourself; you hold the plan and the cross-task context the reviewer lacks.

- The reviewer is wrong, or the point is contestable: park it with a ruling saying why the code stands.
- Real, but nothing downstream builds on it: park it with a ruling saying it is real and deferred.
- Real and load-bearing, a later task builds on it or it reveals a plan defect: rule on the smallest change that unblocks the dependent work, ledger it, and carry the ruling into the next task's dispatch. Parking a structural failure silently lets every dependent task build on it. Stop only when the defect leaves every path forward a guess.

Adjudicate only at the cap. Adjudicating earlier to end a loop is pre-judging with a different name. Every adjudication is a ledger entry. A silent discard is forbidden.

### 6. Complete the task

When the review comes back clean, or every open finding is parked with a ruling at the cap, write the completion ledger line and mark the todo complete. Never move to the next task while Critical or Important findings are neither fixed nor parked-with-ruling at the cap.

## TDD

The lane sets the rule. The dispatch names the lane, and the implementer's report carries the evidence.

**Standard and High-consequence lanes: watch it fail.** The implementer writes one minimal failing test first, runs it, and confirms it fails for the intended reason, the feature missing, not a typo or an unrelated error. Then the minimal code to pass, then watch it pass with pristine output. If you didn't watch the test fail, you don't know if it tests the right thing. A test that passes immediately is testing existing behavior. The report's RED and GREEN evidence, command and output both ways, is what the reviewer verifies against the diff.

**Quick lane, feature work only: the escape hatch.** Prefer no new test over a bad test. A bad test mostly tests mocks, encodes implementation details, depends on timing or unrelated global state, needs expensive infrastructure for a small fix, or would be deleted right after proving the change. When a focused test is impractical, the implementer states why and runs the closest executable check instead: a targeted script, a manual reproduction command, browser automation, a snapshot comparison, a log assertion, or a focused integration check. Silence is not an option; the reason and the check both land in the report.

The escape hatch never applies to a reproduced defect. A bug fix stages its failing repro before the fix in every lane; the bug-fix playbook owns that rule.

## Finish

- No whole-branch review here. df-code-review owns the branch-level pass. Running one here pays for a duplicate seat.
- The ledger stays. Never delete the run state directory at finish. df-code-review consumes the deferred minors, the parked findings, and the rulings, and triages which block merge.
- Collect every ledger line containing `Ruling:` into the handoff, in the order made, each with what it costs if wrong. The list is exhaustive. A ruling that never reaches the operator was a decision made in secret.
- The terminal is df-dev-verify. Inside the feature playbook, return control to the playbook; its next step is df-dev-verify. Invoked standalone, run df-dev-verify directly. Never hand off to any superpowers skill.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "Close enough on spec compliance" | Spec gaps mean not done. Fix, or hit the cap and adjudicate. Those are the only exits. |
| "I'll fix it myself, dispatching is overhead" | Controller fixes pollute your context and skip review. Resume the implementer. |
| "One more round will converge" | Past the cap, rounds don't converge; the failure is structural. Adjudicate and route. |
| "This finding is obviously wrong, I'll drop it" | Adjudication happens only at the cap, and every ruling is a ledger entry. Silent discards are forbidden. |
| "The fix was small, skip the re-review" | Unreviewed fixes are how regressions land. Every round ends with a scoped re-review. |
| "The implementer spawned its own reviewer, free assurance" | A duplicate seat and an unreserved dispatch. It is a defect to flag, not rigor. |
| "Ledger bookkeeping is overhead" | The ledger is what survives compaction. Controllers without one have re-dispatched entire completed task sequences. |
