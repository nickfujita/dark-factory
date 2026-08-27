# Feature

**You own the design. Plan, review, verify.** Delegate implementation and stay in the lead. This playbook is the artifact spine. New or changed behavior enters here and leaves as merged PRs behind a feature flag with an executed acceptance runbook.

**Lane check.** The router already classified the lane and recorded it. Confirm it before step 1. This playbook runs the Standard and High-consequence lanes. A Quick-lane ask never enters here; it stays with the router's Quick discipline, one PR against a recorded finish predicate.

**Budgets.** Every stage below spends from the lane's dispatch and wall-clock budget. Reserve each dispatch through `scripts/df-state.sh` before the spawn, so the dispatch is counted before it exists, and name that reservation in the spawn's brief. The script lands in a parallel wave of this port. Budget exhaustion at any stage is a stop, not a flag.

1. **Requirements.** Run `df-prd-interview`. Lite interview in Standard, full interview in High-consequence.
2. **Challenge.** Run `df-prd-challenge`. Standard is a single pass, one Claude reviewer plus one Codex reviewer, lead adjudication, one remediation wave, one delta verification. High-consequence runs the hardened loop with its dispatch budget and growth stop.
3. **Design.** Run `df-design`. Skipping stays in the todo list as `df-design skipped: <reason>`; do not fold the design decision silently into implementation. A design still contested after the checkpoint goes through `interrogate` before implementation.
4. **Plan.** `df-plan` is pending port. Until it lands, write a checklist plan inline: one section per PR, each item a checkbox that names its verification, no placeholders. The plan decides the PR slicing before any code exists.
5. **QA runbook.** Run `df-qa-runbook-gen`, then `df-qa-validation`. Standard gets a thin runbook and one combined validation pass. High-consequence gets the full runbook and full validation, three rounds maximum.
6. **Throughput checkpoint.** Write it as four todo items. A dimension that genuinely does not apply keeps its item with `n/a: <reason>` rather than being dropped.
   - **Blocking first steps.** Gates run before fan-out.
   - **Independent workstreams.** Disjoint files, services, or layers parallelize. Shared writes serialize.
   - **Shared mutable state.** Default to splitting the target, per the separate-before-serializing-shared-state principle. Serialize only for real invariants.
   - **Smallest safe decomposition.** If one worker is best, name why.

   Code-coupled work goes to a single owner with the checkpoint inline; that owner fans out internally after the blocking phase. Parent-level fan-out is for slices that produce independent artifacts. Rewrite the checkpoint at phase boundaries, and spawn a fresh owner rather than chaining interrupts.
7. **Implement.** Run `df-implement`, which lands in a parallel wave of this port. It owns delegation, the per-task review economy, and the TDD discipline. Review every delegate's diff yourself.
8. **Verify.** Run `df-dev-verify` on the matching surface. "Inconclusive" or wrong-surface is not a pass. Flag it.
9. **Review.** Run `df-code-review`. One whole-branch discovery pass, then delta-scoped verification of fixes. Never rediscovery over the whole artifact.
10. **Open PRs.** Run `playbooks/df-open-pr.md` per PR. Small PRs merge into main behind the feature flag as each goes green, typically three to seven. The first PRs deliver a visible vertical slice. Each PR gets its own review and live verification of its changed surface. Verified-but-unlanded work counts as zero, so PRs merge as they land rather than waiting for the whole chain.
11. **Flag flip.** The flag-flip PR is the last one. It triggers `df-qa-acceptance` with the full runbook, plus `df-code-review`'s integrated pass over the assembled chain, the flag-removal diff, and dead code.

**Reply.** What you built, what you chose and why, open decisions. Tables for design alternatives.
