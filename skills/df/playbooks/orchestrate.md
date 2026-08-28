# Orchestrate

**You own the program, never the code. Author briefs, drain the queue, keep the frontier green, decide.** For a program handed to one standing coordinator session: multi-day, many PRs, more dispatches than one context window survives, the operator checking in twice a day. One task driven to a predicate is `playbooks/autonomous-run.md`. One ambitious run needing a bespoke workflow is figure-it-out. Route here only when the work outlives any single agent. Work one agent could finish inside the session's budget is not a program; measured head-to-head, this playbook's ceremony turned a half-hour 12-unit job into 1 landed unit while a plain agent landed all 12. Below that line, run Autonomous run.

Ceremony must scale with the program. Every gate below prices in coordinator minutes; on cheap near-identical units, collapse it as each section directs rather than paying list price.

Three rules carry the rest.

- Completions are queue events, not interrupts.
- Every spawn and every resume carries the standing orders verbatim.
- The brief is the product. A vague brief fails quietly, because a worker cannot ask you a question.

Open a todo list with the steps below copied in verbatim. A step you skip stays listed with `skip: <reason>`.

## Roles

- **Coordinator (this session).** Frames, authors briefs, drains the inbox, owns the operator report, makes judgment calls. It never authors or edits code; conflicted merges and code changes are always dispatches. Mechanically pushing a verified unit's branch and opening its PR is bookkeeping the coordinator may do itself. State reads and writes go through `scripts/df-state.sh` at drain points, one command in and one line out, to conserve context. The script lands in a parallel wave of this port. It never spawns, waits, or wakes anything.
- **Worker / verifier.** Local subagents through the Agent tool, background by default, roles resolved through `references/model-policy.md`. Prefer fewer, broader workers. One writer per worktree or branch, per the separate-before-serializing-shared-state principle. A unit's verifier runs on the other model family through the cross-model transport named in the df model policy, reading from a disposable worktree snapshot.

Depth stays at coordinator and worker. In-flight children cap at 3. That cap makes a sub-coordinator layer pure ceremony at this scale. A program that genuinely exceeds what one coordinator's drains can manage exceeds the subscription; rescope it instead of adding a layer.

## Store

The run-state store is `scripts/df-state.sh path <run-id>`, outside the repo. Every file has exactly one writer; owners publish facts, readers aggregate at read time. Writes to the tsv files go through `scripts/df-state.sh`, and the plain TSV stays readable without it.

- `run.tsv` is the run row: lane, finish predicate, wall-clock budget, land-by time, state.
- `dispatches.tsv` has one row per dispatch, written before the spawn. The reservation is atomic and pre-dispatch, so a dispatch is counted before it exists. A nested dispatch counts against the parent's budget.
- `dispositions.tsv` has one row per terminal outcome, keyed by unit plus head SHA. It is the verification ledger.
- `preferences.md` is the standing-orders register: numbered lines, one constraint each (model policy, chain shape, verification bar, forbidden paths, escalation policy). Paste it verbatim into every spawn and every resume. Directives decay across resumes, and each dropped one costs an operator turn. When you catch yourself restating an instruction, append the line before you act.
- `gates.md` parks operator gates durably: the question, the options, and the default on no answer, so a completion flood cannot wipe question state.
- `decisions.tsv` is the trail via the show-me-your-work skill.

Status reporting derives from `run.tsv`, `dispatches.tsv`, and `dispositions.tsv` at each drain, never from hand-maintained narrative.

## The brief

Your prompts to agents are your only product, and a sloppy brief compounds into slop across the whole tree. Every spawn carries all of it; a field you cannot fill is a unit you have not scoped yet.

```
GOAL         one sentence, the outcome, executable by a stranger with no chat access
SCOPE        paths this unit may write; paths it may not; its exclusive worktree or branch
CONTEXT      pointers to files and PRs; upstream reports pasted in full when this unit
             depends on them, because workers cannot see siblings
ACCEPTANCE   checkable criteria, one per line
VERIFY       exact commands or the project verification skill's recipe, plus known gotchas
TIMEBOX      rough cap on runtime; on expiry, return partial findings and stop rather than run on
FORBIDDEN    no rebase, no force-push, no merge, no fixes outside scope, plus unit-specific bans
REPORT       status, branch, head SHA, PRs, verdict, what you actually ran, deviations,
             suggested follow-ups
STANDING     <preferences.md pasted verbatim>
```

Size the brief to the unit. A one-command unit gets the template collapsed to a paragraph that still names goal, scope, the verify command, and the report shape. A dependency is a context relay, not just ordering; undeclared upstream context makes the worker guess. Missing fields are a refuse-to-spawn condition. Never resume-chain a brief; respawn fresh with consolidated scope.

## Steps

1. **Frame.** State the done predicate as something countable ("all 12 units merged, each disposition-verified"). Quantify scope: units, rough effort, expected PRs, and the wall-clock budget. If one agent could finish inside that budget, stop here and run Autonomous run instead: the work directly in this session, plain workers where they help, verification inline, landing as you go, and none of the store machinery below. Schedule landing against the budget. By roughly 70% of it, stop spawning and land what is verified, because finished-but-unlanded work counts as zero. Present the framing once; reversible prep proceeds without waiting.
2. **Install the runtime.** Open the run store through `scripts/df-state.sh`, write the standing orders before any spawn, and open the trail via the show-me-your-work skill.
3. **Pilot.** Push one unit through the whole path: brief, worker, verification, disposition row, PR. The pilot exists to falsify the brief template, the verify recipe, and the unit size while that costs one agent instead of ten. Fix the contract from pilot evidence before any fan-out. On programs of near-identical cheap units, the first unit is the pilot, run as a normal unit, and fan-out starts the moment it lands.
4. **Scale.** Spawn a rolling window of workers up to the 3-in-flight cap, refilling as children finish; blocking batches pay the slowest child of every batch. Recompute ready work after each drain, relay upstream reports into downstream briefs, and keep sibling communication upward only.
5. **Drain.** Run the queue discipline below at every drain point.
6. **Land.** Landing is continuous, never a terminal phase; integration starts with the first verified unit and runs alongside the remaining waves. Landing here means merge-ready plus the operator's merge: drive each verified unit's PR merge-ready per `playbooks/babysit.md`, batch merge-ready PRs into the status report, and advance on the operator's merges. The frontier is the lowest unmerged PR of a dependent chain; keep it green before upper-chain work.
7. **Close.** Drain the final inbox, reconcile every dispatch to a terminal disposition (done, abandoned, zombie-reconciled), confirm the predicate on the real artifact, confirm every landed PR has a disposition for its current head SHA, audit the trail per show-me-your-work, and encode recurring corrections into `preferences.md` or the brief template. Leave the store intact. It is the postmortem.

## Queue and drain

- On a completion notification, record the pointer and return to what you were doing. Never deep-review inline; a completion that needs review becomes a verifier dispatch. Never review a diff inside a drain.
- Drain in batches at four points: the end of a critical section, a wave boundary, a Monitor until-loop wake, and before an operator report. Arrivals during a drain wait for the next one.
- Critical sections you finish first: authoring a brief, a conflict decision, writing a gate, updating dispatches or dispositions.
- Each drain classifies every pointer (landed, needs-verify, failed, zombie, noise), writes the rows through `scripts/df-state.sh`, then spawns the next wave in one message.
- Account for every spawned child at each drain: arrived, respawned, or its scope explicitly absorbed. Silently redoing a missing child's work hides both the wasted spend and the coverage gap its result existed to close.
- A drain turn ends with three lines: counts against the states, what changed, gates open.

## Branch discipline

Plain git and gh, no stacking tool. Branch from main for independent units. A branch chain exists only when PRs genuinely depend on each other, with the chain order named in each chained PR's description.

- Workers never rebase and never force-push. Anything rebase-shaped is reported upward and dispatched deliberately.
- One writer per worktree or branch, with the holder recorded in the standing orders.
- PR closes and retargets are coordinator decisions, dispatched with briefs like any other unit. Closing a base PR orphans every chain above it.
- Babysitters follow `playbooks/babysit.md`, one per chain, and report conflicts upward rather than rebasing.

## Verification

Scale verification to the unit. When VERIFY is a single cheap command, the worker runs it and reports the output, and the coordinator spot-checks receipts. A dedicated verifier, on the other model family through the cross-model transport, is for units whose verification is expensive, judgment-laden, or high-blast-radius. A verifier whose entire product would be rerunning one command is ceremony, not verification.

`dispositions.tsv` takes one row per verdict, keyed by unit plus head SHA: `live-verified | test-verified | type-check-only | blocked | failed`. CI green is an input to a verdict, not a verdict. Behavioral work needs better than `type-check-only`. `blocked` is not a pass; re-dispatch when the environment heals. `failed` gets a fix dispatch, not a re-verify. A worker may self-report; a verifier overrides it on the same key. A new head SHA voids the row, so re-verify after any rework. The store answers "was this verified", not memory and not the transcript.

A unit is not done until its output is externalized the moment it lands, never batched to the end of the run: the branch pushed, the disposition row written, receipts in the store. Work that exists only in one session when that session dies was never done.

## Liveness and failure

- Never resume an agent to check on it; a resume restarts an idle agent. Probe read-only: dispositions, dispatches, gh, pushed branches. A delegate past its expected runtime with no side effect (commits, pushes, check deltas) is stuck. Stand it down and replace it with a fresh dispatch and consolidated scope.
- A silent death gets a synthetic disposition row (unit, failure mode, last evidence, options). Replan on evidence as it arrives; never wait for full quiescence.
- Retry by mode: budget-hit, respawn with smaller scope; transient tool error, retry once. Two retries, then abandon the unit, record it, and replan around it.
- A zombie that returns hours late reconciles against the current store before anything is accepted; the world moved while it slept. Salvage unique findings through a fresh dispatch, never a blind merge.
- When continued spawning would produce garbage tree-wide (bad upstream output, broken acceptance, dead infra), write a stop line at the top of the standing orders, let in-flight work finish, fix the cause, clear it.
- Bound your own infra retries the same way you bound a child's. After a few consecutive tool aborts, stop retrying, write a terminal handoff to durable state (what is done, where it lives, the exact command to resume), and end the run.
- After a harness restart: re-read the standing orders and the store, reattach work by PR and branch rather than agent id, respawn workers from their stored briefs plus current state, drain, resume.

## Escalation

Reaches the operator, parked as `gates.md` entries with a default on no answer and batched into the status report rather than raised per item: irreversible actions (deploys, deletions, force-pushes, closing someone else's PR), genuine product or preference calls no experiment settles, a standing order that contradicts observed reality, a program-level dead end that survived a replan. Merge-ready PRs batch here too. The operator merges every PR, and a merge wait is never a per-PR interrupt.

Never reaches the operator: retries, CI flake triage, review-thread triage, format fixes, scope the brief already forbids (refuse and continue), and "should I keep going". When in doubt, act and log; deferring is the measured failure mode.

Mid-run discoveries fix only what blocks the frontier. Everything else parks in follow-ups; at fan-out a small scope leak multiplies into PRs nobody asked for.

**Reply.** At checkpoints and close: the predicate and the count against it from the store, what landed, the PR list with states, the verdicts summary, what was abandoned and why, gates awaiting the operator (the only asks), the store path, and the trail path. Numbers from the tables, not narrative. Include PR links.
