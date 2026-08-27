# PRD structure rules for remediation

Section 1 governs **whether and how** the remediation step acts on a finding.
Sections 2–6 govern **how the resulting edit is written**; they are authoring
rules, not review criteria — but a reviewer may raise a violation as a
`CONSISTENCY` finding. Section 7 holds the templates.

---

## 1. The remediator's judgment mandate

A reviewer's finding is **evidence**. Its suggested fix is a **proposal**.
Neither is an instruction. Before you act on any finding:

1. **Consult the Decision Register first.** If the finding matches an entry, it
   is dismissed by citing that entry — do not re-litigate it, and do not
   silently re-apply a decision that was already made. It reopens only if the
   severity has risen or the reviewer brings new evidence, and reopening gets
   its own register row.
2. **Satisfy yourself the finding is real.** Verify the claim against the source
   material — the PRD text it cites, the code it describes, the external fact it
   asserts. Do not take the reviewer's characterisation on trust: a reviewer
   that misread the document produces a finding that is false, and applying it
   damages the PRD. If the claim does not hold, the finding is **declined**, and
   the register row says what you checked and what you found.
3. **Form your own view of the fix.** You may accept the reviewer's proposal,
   modify it, or **reject the proposed fix while accepting the finding** and
   resolving it another way. Weigh what the proposed fix costs against what it
   buys; a recommendation can be locally correct and globally wrong. If you
   reject a proposal, the finding is still yours to resolve.
4. **Record the disposition of every finding**, with one line of reasoning:
   `applied as proposed` / `applied, modified` / `declined — not real` /
   `declined — accepted but not worth the cost` / `deferred`. Declined and
   deferred findings go in the Decision Register (§ 7); the full disposition
   list goes in the round record and the report.

This is a requirement of the remediation step, not a disposition you may adopt
when you happen to have time. Evidence in `rationale.md` § "Remediation
discipline".

---

## 2. One normative home per rule; satellites cross-reference, never restate

Each load-bearing rule has exactly **one** normative home — the place that
states it. Everywhere else refers to that home.

A satellite that cross-references **cannot go stale.** A satellite that restates
always will.

### Satellite roles

Each satellite section has a defined job. It may repeat a **value**; it may
never restate a **rule**.

| Satellite | Its job | May repeat | Must not |
|---|---|---|---|
| Acceptance criteria | evidence that the rule holds | the value under test | restate the rule, or introduce behaviour the rule does not specify |
| Edge cases | an index of scenarios and which rule governs each | the value | define behaviour that has no normative home |
| Negative requirements | prohibitions and non-goals | the value | restate the positive rule in inverted form |
| Glossary | definitions of terms | — | contain rules or thresholds |
| API sketch | shapes: names, types, fields | field names and values | define behaviour, ordering, or error semantics |
| Examples / walkthroughs | illustration | values | be the only place a behaviour is stated |

### Pinned Parameters table

Give the PRD a **Pinned Parameters** table near the top holding every threshold,
limit, timeout, default, retry budget, size cap and enum the document depends
on, with one row per parameter. Every other location refers to the parameter by
name. This ends the whole stale-value class outright: there is exactly one place
to change, and the consistency gate's old-value sweep has exactly one expected
hit.

State the document's reading conventions explicitly, next to that table — which
sections are normative, which are satellites, and what a satellite is allowed to
contain.

### Rewriting a restatement

When you find a satellite restating a rule:

```
- The queue drains oldest-first and retries up to three times with exponential backoff.
+ Drain order and retry behaviour: see REQ-014 (normative). Retry budget: `MAX_RETRIES` (Pinned Parameters).
```

---

## 3. Separate rationale from specification

Prose written to stop a reviewer re-raising a finding is **audit trail addressed
to reviewers**, sitting inside a specification written for an implementer with
no context. It accumulates fast: in one measured run, justification-connective
density (*because*, *otherwise*, *rather than*) tripled while the document grew
from ten thousand to thirty-three thousand words.

Rules:

- Specification text says **what**, in the imperative. It does not argue.
- Rationale goes in a marked `**Why:**` block immediately after the requirement,
  or in a Rationale appendix keyed by requirement ID.
- Rationale is **relocated, never deleted.** It encodes hard-won corrections a
  future implementer would otherwise undo.
- **Structured tables and matrices are the good pattern** — dense, scannable,
  single-location, and mechanically checkable. Prose paragraphs are where
  redundancy breeds. When a fix would add a paragraph, ask whether it should add
  a table row instead.

---

## 4. Treat document growth as a risk signal

Remediation instinctively **appends rather than edits**. Every appended
qualifier is new surface for the next round to find defects in. One measured run
accumulated sixty-two inline "challenge round:" annotations and grew by 130%.

Rules:

- Prefer an **in-place edit** to an appended qualifier. If the fix is "the
  existing sentence is wrong", change the sentence.
- Never leave process annotations (`challenge round 3:`, `per reviewer
  feedback:`) in the specification body. That is round metadata; it belongs in
  the challenge report, and the *content* belongs in a `Why:` block.
- Record the PRD word count after every change and measure it against
  `GROWTH_HARD_CAP` in the skill's pinned parameters. That cap is a stop, not a
  flag. Growth is not automatically wrong — but growth concentrated in prose,
  while the finding count is not falling, means the loop is feeding on itself,
  and the skill terminates the run rather than extending it.

---

## 5. Restructuring is a change that must be verified

Any consolidation, section move, renumbering, or consistency-only pass is a
change like any other: it is followed by a delta verification scoped to what it
changed. See `consistency-pass.md` § "Every consistency-only pass is verified".
Never approve directly off a restructure.

---

## 6. Assertion-checked replacements

The default edit discipline for remediation.

- Every replacement must match its target **exactly once**. Use an edit tool
  that fails on 0 or >1 matches; do not hand-splice.
- On 0 matches: your assumption about the text is wrong. Re-read the document
  and re-locate. Do not loosen the match until it hits.
- On >1 matches: the rule is stated in more than one place — which is itself a
  § 2 violation. Fix the duplication, do not blind-replace both.
- `replace_all` is permitted only for a mechanical rename where you have already
  asserted the expected count with a search.

This discipline is what catches the remediator's own mistakes at application
time instead of letting them land silently and surface as next round's findings.

---

## 7. Templates

### "Known open items — read first"

When a PRD is approved with residue, this section goes at the **top** of the
PRD — immediately after the title and status block, before any overview. It is
written for the zero-context implementing agent, not for the reviewers.

```markdown
## Known open items — read first

This PRD was approved with the items below still open. Read them before
implementing anything; they are not oversights.

| # | What is unresolved | Where it bites | Risk if you guess | Decision owed by |
|---|---|---|---|---|
| 1 | <the open question, stated plainly> | REQ-xxx, §<section> | <what breaks / what gets built wrong> | <role or "the operator"> |

If you hit one of these during implementation, stop and ask rather than
choosing for yourself.
```

### Decision Register

An in-document record of findings that were **declined or deferred**, with
reasons. It makes a re-raised finding cheap to dismiss and prevents silent
scope erosion — including reviewers proposing to descope requirements the
operator explicitly ratified.

Place it near the end of the PRD, before any appendices.

```markdown
## Decision Register

Findings raised during review and deliberately not applied. A reviewer
re-raising one of these should be answered by citing the entry, unless the
severity has risen or new evidence is offered.

| # | Round | Finding | Severity | Decision | Reason |
|---|---|---|---|---|---|
| 1 | A3 | <one-line summary> | Medium | Declined — not real | <what you checked and what you found> |
| 2 | A5 | <one-line summary> | High | Declined — cost | <why — e.g. "operator-ratified requirement; descoping it was proposed twice and rejected both times"> |
| 3 | B1 | <one-line summary> | Low | Deferred to v2 | <why> |
```

**This is the normative rule for what the register records** (other files refer
here rather than restating it): every finding whose disposition under § 1 was
**declined or deferred** gets a row, whatever its severity. Rows are never
removed — a decision that is reversed gets a new row recording the reversal.
A finding that was *applied* — as proposed or modified — does not get a row; its
disposition lives in the round record and the report.
