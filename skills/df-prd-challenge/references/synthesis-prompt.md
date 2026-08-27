# Challenge Round Synthesis Prompt

After a review round's reviewers complete, synthesize their findings into a
single prioritized list for that round, then adjudicate it.

The Standard lane runs this once, over the two single-pass reviewers. The
High-consequence lane runs it once per round in both phases.

## Synthesis Instructions

Read this round's review outputs. Each output has a self-identifying header
(e.g., `## Findings — Skeptical User Advocate`). Produce a unified findings
list for the round.

**If any reviewer produced no findings or empty/malformed output**, distinguish
the two cases — they are not the same:

- The reviewer **explicitly reported zero findings** → that is a real, usable
  clean result. Record it as such.
- The reviewer produced an **empty or malformed file** → note it explicitly:
  "[Source] No findings produced — tool failure. Do not treat absence of
  findings as endorsement." The round did not get that reviewer's opinion.
  Continue synthesis with the remaining reviewers' outputs and mark the round
  as partial in the round record.

1. **Deduplicate**: If multiple reviewers raised the same concern, merge into
   one finding. Note which reviewers flagged it (higher confidence).

2. **Resolve severity disagreements**: When reviewers disagree on severity
   for the same finding, use the **highest** severity assigned by any
   reviewer. Note the disagreement.

3. **Carry the class**: every finding keeps the `SUBSTANTIVE` / `CONSISTENCY`
   class its reviewer emitted (definitions in `personas.md` § "Shared output
   contract"). If reviewers disagree on class, `SUBSTANTIVE` wins. If a
   reviewer omitted the class, classify it yourself and mark it `(inferred)` —
   inferred classes are never used to justify approving over residue.

4. **Prioritize by severity**:
   - **Critical** and **High**: listed first; all are addressed this round.
   - **Medium** / **Low**: a curated selection is addressed this round (the ones
     that genuinely strengthen the PRD); the rest are deferred.

   "Addressed" is not "applied": every finding goes through the remediator's
   judgment mandate (`prd-structure-rules.md` § 1), and what the Decision
   Register records is defined once, in `prd-structure-rules.md`
   § "Decision Register".

5. **Tag source**: Each finding shows which reviewer(s) raised it:
   - `[User Advocate]`, `[Tech Feasibility]`, `[Scope Challenger]`, `[Codex]`
   - Findings from multiple reviewers: `[User Advocate + Codex]`
   - A review adopted from an earlier independent run of byte-identical PRD
     text is tagged `[<source> — adopted]` and merged into this round's
     findings. It is **not** counted as an additional round.

6. **Attribute origin**: for every new Critical/High, record whether it lives in
   text the **previous round's remediation added** (`origin: remediation`) or in
   original document text (`origin: original`). The share of
   `origin: remediation` findings is what the skill's trend check reads to
   decide whether the loop is self-feeding.

7. **Regressions and register hits**: a finding that repeats one already
   remediated in an earlier round is a **regression** — flag it. A finding that
   matches a Decision Register entry is dismissed by citing that entry unless
   its severity rose or the reviewer brought new evidence.

## Lead adjudication

You are the lead. The reviewers produced findings; you decide what happens to
each one. Do not aggregate. Filter, contextualize, and decide. The reviewers saw
the PRD and a slice of the codebase. You have the whole run: what the operator
actually asked for, the Effort-Anchor, what the Decision Register already
settled, and what the lane is.

Excerpted from `interrogate`'s `references/lead-judgment.md`, which is the
normative home for these rules:

- **Nitpick Gravity.** Reviewers, especially adversarial ones, tend to fill
  their review. If they do not find critical issues, they inflate nits to fill
  the space. If a reviewer's findings are all nits and style preferences, the
  document is probably fine. Say so.
- **Hypothetical versus actual.** "What if someone passes null here" is only a
  finding if a caller can actually pass null. Trace it. A finding that cannot
  name a real path is dismissed.
- **"I would have done it differently."** The most common false positive.
  Not a bug, not a design flaw, not actionable unless the reviewer shows a
  concrete problem with the current approach.
- **Verdict calibration.** A good verdict is useful, not comprehensive. **If
  your Act-On list has more than 5 items, you are probably not filtering hard
  enough.** Re-read it and cut.
- **Dismissals are legitimate and they are stated.** The dismissed list is a
  trust mechanism, not busywork. It lets the operator override you where they
  disagree, which is more valuable than hiding what you rejected.

Two things pull the other way, and they win where they apply. Multiple
reviewers flagging the same issue independently is a consensus signal. Security
findings and correctness bugs get more scrutiny before dismissal, even from a
single reviewer.

Adjudication produces a disposition per finding, and the disposition is what
the remediation step acts on. The vocabulary is fixed in
`prd-structure-rules.md` § 1.

## Report format

The report is written once, at finalize. It must be self-contained — readable
without the original chat context.

```markdown
# PRD Challenge Round: <Feature Name>

**Date:** YYYY-MM-DD
**PRD:** <prd-path>
**Lane:** Standard | High-consequence
**Outcome:** Approved | Approved with open items | Escalated — substantive residue | Terminated — non-converging
**Dispatches:** <used> of <DISPATCH_BUDGET>
**Reviewers:** Skeptical User Advocate, Technical Feasibility, Scope & Complexity, Codex

## Summary

X Critical, Y High, Z Medium, W Low findings across N rounds.
Severity trend: R1 aC/bH → R2 cC/dH → ... → Rn 0C/0H
PRD growth: <baseline> → <final> words (<+n%>)

## Rounds

| Round | Phase | Type | Reviewer tiers | C | H | M | L | SUBST / CONSIST | origin: remediation | PRD words (Δ) | Consistency gate | Delta verification |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 | A | discovery | UA discovery, TF discovery, SC discovery | 3 | 7 | 12 | 4 | 8 / 6 | n/a | 10,412 (—) | 41 ids, 6 stale, 6 fixed | 10 CONFIRMED, 0 NOT CONFIRMED |
| A2 | A | discovery | UA discovery, TF recheck, SC discovery | 3 | 15 | 9 | 2 | 6 / 12 | 61% | 13,980 (+34%) | 88 ids, 19 stale, 19 fixed | 16 CONFIRMED, 2 NOT CONFIRMED → re-verified clean |
| A3 | A | consistency-only | — | 0 | 0 | 38 | 0 | 0 / 38 | — | 13,655 (−2%) | 38 ids, 38 stale, 38 fixed | 38 CONFIRMED, 0 NOT CONFIRMED |
| A4 | A | discovery | UA recheck, TF recheck, SC discovery | 0 | 0 | 3 | 1 | 1 / 3 | — | 13,701 (0%) | 12 ids, 0 stale | 4 CONFIRMED, 0 NOT CONFIRMED |

A4 is a discovery round returning zero Critical/High, so it is the round that
exits the phase.

## Dispositions

Every finding's disposition and its reasoning, per round — `applied as
proposed` / `applied, modified` / `declined — not real` / `declined — cost` /
`deferred` (`prd-structure-rules.md` § 1). Declines and deferrals also appear in
the PRD's Decision Register; this section is where a reader sees the whole set
in one place, including the fixes that were modified or rejected on their way in.

## Findings

### Critical

#### 1. [Finding title] [User Advocate + Tech Feasibility]
**Class:** SUBSTANTIVE
**Round:** A1
**Requirement:** REQ-xxx
**Issue:** [Merged description from both reviewers]
**Recommendation:** [What the reviewer proposed]
**Disposition:** [applied as proposed | applied, modified | declined — not real | declined — cost | deferred] — [one line of reasoning]
**Remediation applied:** [What you actually changed in the PRD, and where]
**Verified:** [CONFIRMED by <reviewer> in the delta verification of round <n> | NOT CONFIRMED → re-remediated, confirmed in <n+1> | unverified — why]

---

### High
...

### Medium (for reference)
...

### Low (for reference)
...

## Decision Register additions

| # | Round | Finding | Severity | Decision | Reason |
|---|---|---|---|---|---|

## Residual open items

<empty, or the list that was written into the PRD's "Known open items — read first" section>

## Notes

<tooling blockers, adopted reviews, tier substitutions, reviewer threads that
could not be resumed for their delta verification, retried rounds, the
dispatch count, and the reason the run terminated>
```

Rules for the report:

- **Number findings once, globally** across all rounds and phases.
- Every round row states its **type** and the **tier each reviewer ran at** —
  results are not interpretable without it.
- The severity trend and the growth column are decision-grade, not decoration.
  A reader must be able to see convergence (or its absence) from the table
  alone.
- **Every remediation shows its delta verification**, including any that could
  not be verified. An unverified delta is a stated fact in the report, never an
  omission.
- If a phase was tooling-blocked, say so in **Outcome**, not only in Notes.
- A Standard-lane report has one row in the Rounds table, typed
  `single-pass`, and its Notes say whether the operator invoked the
  second-opinion pass.
