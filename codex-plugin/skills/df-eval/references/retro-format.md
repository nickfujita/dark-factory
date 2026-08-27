# Retro output format

The retro's synthesis is exactly three lists plus a budget line. No preamble, no narration. One sentence per cell. The operator should read each Problem and Proposal pair in five seconds.

## Accepted

At most five rows. That is the D14 cap, and it binds. When more findings survive the criteria, keep the five most decision-changing and move the rest to Backlog for the next cycle.

| Problem | Proposal | Routing |
|---|---|---|
| the failure mode observed in the trail | the change that prevents it | one of the routing values below |

Routing values:

- `<skill path> § <section>` for a prose edit. The parent applies it only after the operator approves the row.
- `scenario: scripts/df-eval-scenarios/<name>.sh` when a script, lint, or store-file assertion can enforce the finding. Prefer this routing over prose. Skill text is for what mechanisms cannot enforce.
- `tune description: <skill path>` when the skill exists but did not trigger when it should have.
- `new skill via skill-creator: <kebab-name>` only when no existing skill is a real home and the pattern recurs.

Acceptance criteria, applied to every finding:

- Durability. Still true in six months once paths, SHAs, and tool versions have changed.
- Specificity. Broad enough to apply across tasks, precise enough that a future session recognizes when to use it. Reject platitudes and hyper-specific facts.
- Existing-skill-first. A new skill needs a recurring pattern with no real home.
- Convergence. A finding echoed by two or more graders carries higher confidence. Singletons clear a higher bar on the other criteria.
- Decision-changing. A future session does something different because of the edit, not just reads more text.
- Structural-mechanism check. When a scenario or check could enforce it cheaply, route it there.
- Skill-was-used. Accept only findings that route to a skill the trail actually invoked. A skill that should have triggered but did not routes to `tune description`. Neither, reject as `skill-not-used`.
- Already-covered. Read the target skill before accepting a prose row. Guidance that already exists and is well placed makes the finding an execution problem, rejected as `already-covered`. Guidance that exists but is buried becomes a wording or placement row, not an addition.

## Rejected

One entry per rejected finding:

- Principle: one sentence.
- Reason: `durability`, `specificity`, `existing-skill-first`, `convergence`, `decision-changing`, `structural`, `duplicate`, `skill-not-used`, or `already-covered`.

## Backlog

One entry per item: the pattern, what was hit, and the suggested mechanism. Backlog items are records, not edits. They carry into the next cycle's input and never touch a skill without going back through an Accepted row.

## Budget

The report's last line, read from `scripts/df-state.sh status <run-id>` and never from memory:

```
budget: <reserved>/<budget_dispatches> dispatches, <elapsed>/<budget_wall_minutes> minutes, final state <state>
```

The retro stayed in budget when the final state is `done` and the run never flipped to `stopped-budget`. This line is a graded outcome of the retro itself. A retro that blew its budget failed that outcome, and says so, whatever the quality of its findings.
