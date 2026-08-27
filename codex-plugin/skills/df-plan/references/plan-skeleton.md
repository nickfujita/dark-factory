# Plan skeleton

Copy the fenced skeleton into the plan file and fill every placeholder. Keep every heading and block in the order shown. `scripts/check-plan.mjs` enforces this shape.

Rules the skeleton compresses:

- One H2 block per PR, its title a verb phrase ending in `(PR-<id>)`. Repeat the block per PR.
- One `### Task <n>. <name>` section per task, numbered 1 to N across the whole plan. Repeat the task shape inside each PR block; every task keeps its Files, Interfaces, and Steps blocks.
- The three verification blocks close each PR block, each opening with the verification rule verbatim.
- A PR with no perf-sensitive path replaces the four perf boxes with `Not perf-sensitive.` and a one-line reason, directly after the rule.
- Appendices are optional. Omit an appendix that would say only "none", except Appendix A, which records "nothing prototyped" explicitly when that is true.
- Angle-bracket placeholders must all be gone from the finished plan. The checker flags any that remain.

````markdown
# <Feature> plan

> df-implement executes this plan task by task. Never hand it to any other execution skill.

<What changes, for whom, the PR ids in order, and the flag name. Under six lines.>

**Goal.** <One sentence, the outcome.>
**Spec.** <Path to the PRD, or the recorded finish predicate.>
**Design.** <Path to the df-design rationale, or the recorded skip line.>
**Lane.** <Standard or High-consequence.>

## How to read this

One box is one unit of work. Every box names the evidence that checks it. Check a box only when its evidence exists, a file, a log line, a test run, a screenshot, or a commit SHA. The body is a how-to. The appendices explain and record.

df-implement executes this plan task by task. The operator merges every PR.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Global constraints

- <Project-wide requirements from the spec, exact values verbatim, one line each. Version floors, dependency limits, naming and copy rules. Every task's requirements include this section. Write "None." when the spec sets none.>

## <Task as a verb phrase> (PR-1)

**Depends on.** <PR id, or None.>

**Budget.** <From the run state. Remaining dispatches and wall clock, and this PR's expected draw. Or the no-run-state note.>

**You see.**

- [ ] <One observable result after this PR merges, with the exact log line or screen state.>

### Task 1. <Component>

**Files.**

- Create `<path>`.
- Modify `<path>`, lines <a> to <b>.
- Test `<path>`.

**Interfaces.**

- Consumes. <Exact signatures this task uses from earlier tasks, or None.>
- Produces. <Exact names, parameter types, and return types later tasks rely on, or None.>

**Steps.**

- [ ] Write the failing test.

```<lang>
<the complete test, verbatim>
```

- [ ] Run `<command>`. Expect FAIL because <the missing feature, stated concretely>.
- [ ] Implement.

```<lang>
<the complete code, verbatim>
```

- [ ] Run `<command>`. Expect PASS.
- [ ] Commit with `git commit -m "<type(scope): message>"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] <Test file and the case it gains.> Run `<command>`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] <Concrete scenario on the matching surface, and what drives it.> Save `<evidence path>`. Pass when <predicate>.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. <What is measured.>
- [ ] Probe. <The command or procedure, run at trunk and at the head, interleaved.>
- [ ] Baseline. Record the trunk <value> first.
- [ ] Rule. <Head against trunk, with the number that fails.>

## Appendix A. Prototype evidence

<Each open question a prototype answered, with the branch, the SHA, and the artifact links. Each question that stays unproven. Or the explicit note that nothing was prototyped.>

## Appendix B. Alternatives rejected

<Each approach weighed and why it lost.>

## Appendix C. Risks

<Each risk with the PR it lands in and what df-implement watches.>
````
