# Challenge Round Synthesis Prompt

After a review round's reviewers complete, synthesize their findings into a
single prioritized list for that round. This runs once per round in both
phases (Phase A: the 3 Claude personas; Phase B: Codex).

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
   - **Critical** and **High**: listed first; all are remediated this round.
   - **Medium** / **Low**: a curated selection is remediated this round (the
     ones that genuinely strengthen the PRD); the rest are recorded as
     deferred, and every *declined* one gets a Decision Register row.

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

## Report format

The report is written once, at finalize. It must be self-contained — readable
without the original chat context.

```markdown
# PRD Challenge Round: <Feature Name>

**Date:** YYYY-MM-DD
**PRD:** <prd-path>
**Outcome:** Approved | Approved with open items | Escalated — substantive residue
**Reviewers:** Skeptical User Advocate, Technical Feasibility, Scope & Complexity, Codex

## Summary

X Critical, Y High, Z Medium, W Low findings across N rounds.
Severity trend: R1 aC/bH → R2 cC/dH → ... → Rn 0C/0H
PRD growth: <baseline> → <final> words (<+n%>)

## Rounds

| Round | Phase | Type | Reviewers | C | H | M | L | SUBST / CONSIST | origin: remediation | PRD words (Δ) | Consistency gate |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 | A | discovery | UA, TF, SC | 3 | 7 | 12 | 4 | 8 / 6 | n/a | 10,412 (—) | 41 ids, 6 stale, 6 fixed |
| A2 | A | discovery | UA, TF, SC | 3 | 15 | 9 | 2 | 6 / 12 | 61% | 13,980 (+34%) | 88 ids, 19 stale, 19 fixed |
| A3 | A | consistency-only | — | 0 | 0 | 38 | 0 | 0 / 38 | — | 13,655 (−2%) | 38 ids, 38 stale, 38 fixed |
| A4 | A | verification | UA, TF, SC | 0 | 0 | 3 | 1 | 1 / 3 | — | 13,701 (0%) | 12 ids, 0 stale |

Verification round verdicts: A4 — 22 CONFIRMED, 0 NOT CONFIRMED.

## Findings

### Critical

#### 1. [Finding title] [User Advocate + Tech Feasibility]
**Class:** SUBSTANTIVE
**Round:** A1
**Requirement:** REQ-xxx
**Issue:** [Merged description from both reviewers]
**Recommendation:** [What should change in the PRD and why — the risk being mitigated]
**Remediation applied:** [What you actually changed in the PRD to resolve this — or, if deferred, the reason]

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

<tooling blockers, adopted reviews, convergence-extension rounds used>
```

Rules for the report:

- **Number findings once, globally** across all rounds and phases.
- Every round row states its **type** and which reviewers ran — results are not
  interpretable without it.
- The severity trend and the growth column are decision-grade, not decoration.
  A reader must be able to see convergence (or its absence) from the table
  alone.
- If a phase was tooling-blocked, say so in **Outcome**, not only in Notes.
