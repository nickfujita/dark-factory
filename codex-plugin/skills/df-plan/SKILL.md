---
name: df-plan
description: "Planning stage for routed work. Turns the settled requirements and design into a checklist plan, one block per PR, every task written so a cheap model implements it by transcription, machine-checked by check-plan.mjs. Runs when the df feature playbook reaches the plan step or the operator invokes $df-plan. Never enter on your own."
---

# df-plan

**You own the plan, not the code. The plan is the deliverable. Do not implement.** The plan is a checklist df-implement runs box by box and the operator audits from the evidence. Write every task so a cheap model can implement it by transcription. Exact paths, exact signatures, verbatim code. A task that needs judgment to fill in is a task you have not finished writing.

The spec is the binding authority and the plan is its argument. Every task traces to a spec requirement, and a requirement with no task is a gap.

Principle names in this skill cite `../df/references/principles.md`.

## Inputs

- The settled requirements. The PRD in the Standard and High-consequence lanes, the recorded finish predicate in a Quick-lane escalation.
- The design from df-design, the synthesized sketch and its rationale. A recorded `df-design skipped: <reason>` counts as the design record.
- For a user-facing graphical UI change, `<run-dir>/work/prototype/approved-ui-prototype.md` from the prototype playbook. For other work, a recorded `prototype skipped: no user-facing visual change` counts as the prototype record.
- The lane and its budgets, from the run state store, which lives outside the
  target repo (`bash scripts/df-state.sh path`).

## Skip rule

When the change is one or two files with an obvious approach, skip the plan. Say so, leave `df-plan skipped: <reason>` in the todo list, and return control. Skipping the plan never skips verification; the lane's discipline still applies to the change.

## Settle open questions before writing

Planning does not decide a visual UI question. If the work changes a user-facing graphical UI and the approved prototype record is missing, return to df-design. Do not draft the plan around prose or an unapproved screenshot.

A non-visual question about timing, behavior, or whether an API works gets a prototype, not a guess. Run `../df/playbooks/prototype.md` and keep its evidence for Appendix A. Ask the operator only about a product or preference call no run can settle, and offer options when you ask (the never-block-on-the-human principle).

## Explore in subagents

Spawn read-only explorers as background native Codex subagents, on the menial investigation role from `../df/references/model-policy.md` (the guard-the-context-window principle). Each returns file pointers, conventions, test commands, and entry points. No inlined dumps.

## Slice into PRs

One PR is one change with its own evidence (the sequence-verifiable-units principle). A Standard or High-consequence feature ships as several small PRs behind the feature flag, typically three to seven, merging as each goes green. Set `Depends on. None.` and `Branch. Independent from main.` for every independent PR. Do not stack independent work merely because it belongs to the feature. Set `Depends on. PR-<id>.` and `Branch. Dependent on PR-<id>.` only when the upper PR cannot work without that lower PR. The plan checker enforces that pairing. The PR-opening playbook registers a genuine branch chain as a native GitHub stack when the repository supports it. Its capability fallback preserves the plain chain.

**Vertical slice first.** Order the PRs so a user-visible slice lands early, in the first PR or two. A plan whose visible surface is all at the end is misordered; reorder it before writing any verification. The **You see** block makes this checkable. When the early PRs' You see boxes name only internal state, either the ordering is wrong or the slice is missing.

## Slice PRs into tasks

A task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate. Fold setup, configuration, scaffolding, and docs into the task whose deliverable needs them. Split only where a reviewer could reject one task while approving its neighbor.

df-implement dispatches a fresh implementer per task from the task's text alone. The implementer never sees the whole plan, so each task is self-contained, and the Interfaces block is how it learns the exact names and types neighboring tasks use. Number tasks 1 to N sequentially across the whole plan; the df-implement ledger keys on those numbers.

## Write for transcription

- **Exact file paths.** Create, modify, and test paths per task, with line ranges on modified files.
- **Interfaces per task.** Consumes lists the exact signatures this task uses from earlier tasks. Produces lists the exact function names, parameter types, and return types later tasks rely on.
- **Verbatim code in steps.** A code step carries the complete code in a fenced block, not a description of it. Repeat shared code rather than pointing at another task; the implementer cannot see it.
- **Small steps.** One action per box, two to five minutes each. Write the failing test. Run it and watch it fail for the stated reason. Implement the minimal code. Run it and watch it pass. Commit.
- **TDD shape per lane.** Standard and High-consequence plans write the watch-it-fail sequence into every code task. df-implement enforces it at dispatch time; the plan is where the failing test gets written down.
- **No placeholders.** These are plan failures, never write them: TBD, TODO, implement later, fill in details, add appropriate error handling, handle edge cases, write tests for the above, similar to Task N, or a step that says what to do without showing how.

## Verification blocks

Every PR block ends with unit, live, and perf verification, and each of the three opens with this sentence pair verbatim. "Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked." That is the verification rule (the prove-it-works principle).

- **Unit** names the test file, the case it gains, and the exact command.
- **Live is mandatory.** Each box is one concrete scenario on the matching surface, driven through the repo's own verification skill when it has one, otherwise agent-browser for UI or the closest surface you can reach. Each box names the evidence file it saves and its pass predicate.
- **Perf** names the metric, the probe, the trunk baseline measured first, and the rule with the number that fails. A PR with no perf-sensitive path writes `Not perf-sensitive.` plus a one-line reason after the rule, and no boxes. An invented metric to fill the block is worse than the stated skip.

## Budget notes

Every PR block carries a Budget line sourced from the run state, never invented. Read the lane's dispatch and wall-clock budget and what is already consumed, through `scripts/df-state.sh` once it is on disk, by reading the run state file directly until then. State what remains and this PR's expected draw in dispatches. A standalone run with no run state writes that down in the Budget line instead. When the PR draws sum past the remaining budget, that is a finding to surface to the operator, not a note to bury.

## Write the file, then check it

1. Unless the operator names a path, write the plan into the run's own state
   directory, `bash scripts/df-state.sh path "<run-id>"`.
2. Copy the skeleton from `references/plan-skeleton.md` and fill every placeholder. Keep every heading and block in the order shown. One H2 block per PR, `### Task <n>. <name>` headings inside it. For each PR, pair `Depends on.` with the exact matching `Branch.` value.
3. The body is a how-to. Appendices hold explanation and record. Short declarative sentences. No long dashes. No mid-sentence colons. The technical-writing and unslop skills own the full rule set.
4. Run the checker beside this skill, `node <this skill's directory>/scripts/check-plan.mjs <plan file>`, and fix every defect line it prints (the encode-lessons-in-structure principle). It enforces the skeleton's shape, the verification rule in every block, the punctuation bans, and the placeholder bans. The `D5 gate` line it prints for a plan over 8 tasks is a gate to route to the operator, not a defect to edit away.

## Self-review

Look at the spec with fresh eyes before handing back, and fix inline.

- **Coverage.** Each spec requirement points to a task. List any gap and add the task.
- **Placeholder scan.** The checker catches the named patterns; you catch the described-not-shown steps it cannot.
- **Interface consistency.** Names and types used in later tasks match what earlier tasks defined. A function called one thing in Task 3 and another in Task 7 is a bug.

## The D5 gate

Count the tasks. A plan with more than 8 tasks pauses for explicit operator sign-off before implementation starts. The gate holds in every path, including an autonomous run; no budget, lane rule, or autonomy contract overrides it. At 8 or fewer, the lane's normal checkpoint applies.

## Handoff

The plan's executor is df-implement, task by task. Never hand the plan to any superpowers skill; the checker fails a plan that names one.

- In the Standard lane, present the technical design and the plan together for one combined sign-off. For a visual UI change, name the approved prototype and show how each user-visible task follows it. The visual direction is not reopened during planning. In High-consequence, the design was already checkpointed; present the plan.
- Post the plan path and the checker's output, then stop. Execution starts on the operator's explicit go, and a plan over the D5 gate does not start without it.
- Inside the feature playbook, return control to the playbook; its next steps are the QA runbook and then df-implement. Invoked standalone, run df-implement on the operator's go.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "The implementer can figure that out" | The implementer is a cheap model dispatched with this task's text alone. What the plan does not say does not happen. |
| "The perf block is ceremony here" | Then write `Not perf-sensitive.` with the reason. An invented metric is slop with a checkbox. |
| "Nine tasks is basically eight" | The gate is a number so it cannot be argued with. Present the plan and get the sign-off. |
| "Verification design slows the plan down" | The plan is the only place verification gets designed. df-implement executes what is written; it does not invent live scenarios later. |
| "The skeleton is overhead for a small feature" | A small feature is the skip rule's territory. Past one or two files, the shape is the point. |

**Reply.** The plan path, the PR ids with dependencies and which PR carries the visible slice, the task count and whether the D5 gate holds, what the prototypes proved and what stays unproven, and the checker's output.
