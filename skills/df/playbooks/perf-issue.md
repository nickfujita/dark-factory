# Perf issue

**You own the measurement story. Plan, review, verify the numbers.** Tie every fix to a measurement. Do not read source instead of measuring.

1. Capture a baseline trace. When `.dark-factory/project.yaml` names a verification skill, drive the surface through it and use the profiler it or the manifest names. Otherwise use the closest measurement tooling you can reach on this box, and record exactly how the number was captured so the post-fix run can repeat it.
2. Ground hypotheses with the **how** skill. Never claim a perf ceiling without running it first.
   Most fixes come from eight strategy families. Use them as hypothesis generators, not a checklist. A family earns an attempt only when the trace shows the signal it names, and a focused fix for the dominant cost beats applying all eight.
   - **Elimination.** The cheapest work is work that doesn't run. Before optimizing the hot path, ask whether it needs to exist. A computation nobody consumes, a feature gate that's always off for this user, a sync that redundantly mirrors state, a legacy path kept just in case. The trace shows what's slow, never that it's deletable, so this family needs the `how` pass, not the profiler. Deleting the work beats every other family when it applies.
   - **Divide and conquer.** The dominant cost scales with input size. Split the work so each piece touches less (chunk, shard, prune the search space) or so independent pieces run in parallel.
   - **Caching.** The same computation or fetch repeats on identical inputs. Store and reuse the result. Name what invalidates it before claiming the win.
   - **Indirection.** The hot path does expensive work a cheaper intermediate could absorb. An index instead of a scan, a queue that shifts work off the interactive thread, a handle that lets a cheaper implementation swap in. Add the hop only when it removes more from the critical path than it adds. A layer that sits on the hot path without removing work is pure cost.
   - **Batching.** Many small operations each pay a fixed overhead (RPC, query, syscall, draw call). Coalesce them to pay the overhead once per batch.
   - **Redundancy.** The wait hangs on one slow instance or attempt. Duplicate the work (replicas, hedged requests, speculative execution) and take the fastest result. This trades extra load for lower tail latency, so the trace has to show the wait dominates and the system has headroom. Duplication without that tradeoff only adds load.
   - **Lazy evaluation.** Cost lands on results that are never used or not needed yet (eager init on the boot path, rendering offscreen items). Defer the work until first use.
   - **Scheduling.** The work must happen, but not during the interactive moment. Move it to where nobody is waiting: idle callbacks, a background warmup after boot, precompute before the user arrives, cleanup after the frame commits. Distinct from lazy evaluation, which defers until needed. Scheduling often runs the work earlier than the hot moment, or in its shadow. The win is perceived latency, so measure the interactive path, not total work done.
3. Plan the fix from the trace. If it crosses a function boundary, sketch the design in the thread before delegating. Run df-design when the shape is genuinely contested. Delegate implementation to a subagent in the implementation-delegate role from `references/model-policy.md`, with a specific scope. Review the diff yourself. Capture a post-fix trace with the same capture recipe as the baseline. Verify each attempt before trying the next, per the sequence-work-into-verifiable-units principle in `references/principles.md`.
4. Parse and compare the trace artifacts with a deterministic script, such as a diff of the extracted numbers or an import into a queryable table. "Inconclusive" or wrong-surface is not a pass. Flag it.
5. Cite the measurement in the PR.
6. Run **Opening a PR**, the `playbooks/df-open-pr.md` playbook. It owns the finish: commit shaping, the Why / Scope / Tradeoffs / Blast Radius / Verification description, the worktree cleanup guard, and the never-merge and never-draft rules.

For sustained improvement against a metric rather than a one-off fix, the hillclimb playbook applies. It is operator-invoked by name.

**Reply.** Baseline number, post-fix number, delta, artifact path.
