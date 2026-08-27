# Hillclimb

**You own the metric and the experiment's integrity. Supervise and review; delegate the attempts.** For sustained, iterative improvement of one measurable thing against a target. "Hillclimb on X", "make startup 50% faster", "keep trying until the metric improves by N%". A one-off fix is Bug fix or Perf issue; this is the loop.

Gated. The loop is expensive by design, so it runs only when the operator asks for it by name. Reserve its budget through `scripts/df-state.sh`, which lands in a parallel wave of this port, and stop when the budget exhausts, mid-climb included.

The core discipline is one change, one measurement, keep or revert. Never stack untested changes, and never claim a win from code inspection. The data decides, per the prove-it-works principle.

1. Ground the workload and architecture before choosing the ruler. Run the how skill over the target, name the realistic workload dimensions that can move the result (data size, history, state, concurrency), and select a case that reproduces the complaint. If no case reproduces it, fix the repro instead of hillclimbing. Then fix one metric, the direction that counts as better, and a checkable stop predicate that pairs a target with a floor on attempts, so a lucky early win cannot end the run. "At least 50% better than baseline and at least 10 iterations" is the shape. Use the operator's numbers when given, otherwise agree them.
2. Build the measurement harness, prove its sensitivity, then freeze it, per the build-the-lever principle. Run contrasting realistic workloads and confirm the target case reproduces the symptom while easier cases separate as expected. If the ruler cannot distinguish them, revise the workload or metric. Once frozen, one repeatable command emits the metric, sampled enough to clear the noise (median of N, never a single run). Changing the harness invalidates every earlier number. Record the baseline metric and a green run of the regression gate before any change.
3. Open the decision log via the show-me-your-work skill: `decisions.tsv`, one row per attempt, with id, hypothesis, change, before, after, delta, tests, verdict (kept or reverted), note. This is the run's memory. Read it before each attempt so the search accumulates instead of circling. It lives in the run store, not the work tree, so it survives reverts.
4. Ground each hypothesis in the architecture model from step 1, so it names a specific mechanism ("defer X off the boot path because it blocks first paint"), never "try memoizing something".
5. Loop, one hypothesis per iteration.
   - Hand the change to a subagent on the implementation-delegate role from `references/model-policy.md` with a tight scope; supervise and review the diff rather than typing it, per the guard-the-context-window principle. When several independent hypotheses are live, fan them to parallel subagents, each in its own worktree so they cannot collide. Reserve each dispatch through df-state before the spawn.
   - Measure before and after with the frozen harness, and run the regression gate.
   - Accept only when the metric moves past noise and the gate stays green. Otherwise revert the change in full; a tweak that "might help" does not ride along.
   - One commit per accepted fix, staging only the files you changed (`git add <files>`, never `-A`). Log the row either way, kept or reverted.

   Each iteration ends in a check before the next begins, per the sequence-verifiable-units principle. If the run is unattended, borrow only the wake mechanism from `playbooks/autonomous-run.md`, a bounded polling loop with an explicit interval and hard cap, not its stop rule. This playbook's stop criteria govern, so a plateau means pivot, not stop.
6. Push past the first plateau. On a stall, several rejects in a row, pivot category, combine near-misses, re-read the source, or try something more radical before concluding the hill is climbed. Correctness and simplicity outrank the number. Revert a win that breaks behavior, and keep a simplification that holds the number, per the laziness-protocol principle.
7. Stop when the predicate is met, when the budget exhausts, or when the remaining ideas are genuinely marginal and not worth their cost. Do not relax the predicate to declare victory, and do not quit while cheap untried hypotheses remain. Stuck means surface it instead of spinning.
8. Run `playbooks/df-open-pr.md` with the accepted commits stacked in the order they landed, so the metric's climb reads top to bottom.

**Reply.** The metric and target, baseline to final with the percent delta, iterations run (kept versus reverted), each accepted fix on one line, the decision-log path, and the best idea you would try next if pushed further.
