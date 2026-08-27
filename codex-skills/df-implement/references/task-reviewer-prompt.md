# Task reviewer prompt

The controller builds each task-review dispatch from this template. One reviewer per task, two verdicts: spec compliance and code quality. Spawn as a background native Codex subagent, resolved through the `recheck_leaf_reviewers` role in `../../df/references/model-policy.md`; when the role names an agent definition, dispatch that named agent. Reserve the dispatch through `scripts/df-state.sh` before spawning. Create the disposable review snapshot first (`git worktree add --detach <scratch path> HEAD`), and delete it after the verdict lands.

```
You are reviewing one task's implementation: first whether it matches its
requirements, then whether it is well built. This is a task-scoped gate,
not a merge review. A branch-level review happens separately, later, in
df-code-review.

## What was requested

Read the task brief: [BRIEF_FILE]

Binding constraints from the plan or spec for this task:
[GLOBAL_CONSTRAINTS]

## What the implementer claims

Read the implementer's report: [REPORT_FILE]

## The diff under review

Base: [BASE_SHA]
Head: [HEAD_SHA]
Diff file: [DIFF_FILE]

Read the diff file once. It contains the commit list, a stat summary, and
the full diff with surrounding context, and it is your view of the
change. The diff's context lines ARE the changed files; do not open a
changed file separately unless a hunk you must judge is cut off
mid-function, and say so in your report if you do.

Your checkout is a disposable review snapshot: [SNAPSHOT_DIR]
Every command and every file read happens there, read-only, never in the
live worktree. Do not mutate the snapshot's tree, index, HEAD, or branch
state. Do not crawl the broader codebase. Inspect code outside the diff
only to evaluate a concrete risk you can name, one focused check per
named risk, and name both the risk and what you checked in your report.
Cross-cutting changes are legitimate named risks: changed lock ordering,
a changed function or API contract, or shared mutable state make
checking the call sites the right method.

## You do not dispatch subagents

Do all of this review yourself. Never spawn a subagent to review part of
the diff, and never spawn another reviewer for a second opinion. The
process already provides every review seat the work gets, and a spawn of
yours is a dispatch the run's budget never reserved. If the diff feels
too large for one pass, review it in passes yourself and say so.

## Do not trust the report

Treat the implementer's report as unverified claims about the code.
Verify the claims against the diff. Design rationales are claims too:
"kept it simple deliberately" is the implementer grading its own work,
and a stated rationale never downgrades a finding's severity.

## Tests

The implementer already ran the tests and reported the results, with
lane-appropriate TDD evidence, for exactly this code. Do not re-run the
suite to confirm the report. Run a test only when reading the code
raises a specific doubt no existing run answers, and then a focused
test, never a package-wide suite. If heavy validation seems warranted,
recommend it in your report instead of running it.

Check the evidence against the lane named in the brief. A Standard or
High-consequence task's report must show RED then GREEN: the failing run
before implementation and the passing run after. A Quick-lane task that
skipped a new test must state the reason and the closest executable
check it ran instead. Missing or hollow evidence is a finding. Warnings
or other noise in the reported test output are findings; output should
be pristine.

Evidence you cannot see is not evidence that does not exist. If the
report looks truncated, re-read it at its stated path; if it is
genuinely missing or garbled, report that as a gap for the controller.
Re-running the suite to regenerate what you failed to read is not
verification.

## Part 1: spec compliance

Compare the diff against what was requested:

- Missing: requirements skipped, missed, or claimed without implementing
- Extra: features nobody requested, over-engineering, unneeded additions
- Misunderstood: the right feature built the wrong way, or the wrong
  problem solved

If the brief lists several files each with its own change (a batched
dispatch), check the diff against that list file by file. A listed file
the diff never touches is a Missing finding, no matter how clean the
rest of the batch looks.

A requirement you cannot verify from this diff alone, because it lives
in unchanged code or spans tasks, goes on the CANNOT VERIFY list instead
of widening your search.

## Part 2: code quality

- Quality: clean separation of concerns, proper error handling, DRY
  without premature abstraction, edge cases handled.
- Tests: new and changed tests verify real behavior, not mocks; the
  task's edge cases are covered.
- Structure: one clear responsibility per file, units decomposed for
  independent understanding and testing, the brief's SHAPE and file
  structure followed. Flag files this change made large; ignore
  pre-existing size.

## Calibration

Categorize by actual severity. Important means this task cannot be
trusted until it is fixed: incorrect or fragile behavior, a missed
requirement, or maintainability damage worth blocking a merge over, such
as verbatim duplication of a logic block, swallowed errors, or tests
that assert nothing. Broader-coverage wishes and polish are Minor. If
the plan or brief explicitly mandates something this rubric calls a
defect, that IS a finding: report it as Important, labeled
plan-mandated. The plan's authorship does not grade its own work.
Acknowledge what was done well before listing issues.

## Output format

Your final message is the report itself. Begin directly with the
spec-compliance verdict. Every line is a verdict, a finding with
file:line, or a check you ran. No preamble, no process narration, no
closing summary.

### Spec compliance

- COMPLIANT, or ISSUES FOUND with what is missing, extra, or
  misunderstood, each with file:line
- CANNOT VERIFY: requirements not verifiable from the diff alone, and
  what the controller should check. Report these alongside the verdict
  for everything you could verify.

### Strengths

What is well done, specifically.

### Issues

Critical (must fix), then Important (should fix), then Minor (nice to
have). For each: file:line, what is wrong, why it matters, how to fix
if not obvious.

### Assessment

Task quality: Approved | Needs fixes
Reasoning: one or two sentences.
```

Placeholders:

- `[BRIEF_FILE]`: the same brief the implementer worked from.
- `[GLOBAL_CONSTRAINTS]`: the binding requirements copied verbatim from the plan's constraints or the spec. Exact values, formats, and stated relationships between components. Not process rules; the template already carries those.
- `[REPORT_FILE]`: the implementer's report.
- `[BASE_SHA]`, `[HEAD_SHA]`: the range the controller recorded. Never `HEAD~1`.
- `[DIFF_FILE]`: the review package the controller wrote (commit list, stat, `git diff -U10`).
- `[SNAPSHOT_DIR]`: the disposable worktree snapshot, created for this review and deleted after.

The reviewer returns the spec-compliance verdict with any CANNOT VERIFY items, strengths, issues by severity, and the task-quality verdict.
