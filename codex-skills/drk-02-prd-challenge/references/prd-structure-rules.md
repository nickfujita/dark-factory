# PRD structure rules for remediation

Every edit the remediation step makes to a PRD obeys these rules. They are
authoring rules, not review criteria — but a reviewer may raise a violation as
a `CONSISTENCY` finding.

---

## 1. One normative home per rule; satellites cross-reference, never restate

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

## 2. Separate rationale from specification

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

## 3. Treat document growth as a risk signal

Remediation instinctively **appends rather than edits**. Every appended
qualifier is new surface for the next round to find defects in. One measured run
accumulated sixty-two inline "challenge round:" annotations and grew by 130%.

Rules:

- Prefer an **in-place edit** to an appended qualifier. If the fix is "the
  existing sentence is wrong", change the sentence.
- Never leave process annotations (`challenge round 3:`, `per reviewer
  feedback:`) in the specification body. That is round metadata; it belongs in
  the challenge report, and the *content* belongs in a `Why:` block.
- Record the PRD word count each round and flag growth against the thresholds in
  the skill's pinned parameters. Growth is not automatically wrong — but growth
  concentrated in prose, while the finding count is not falling, means the loop
  is feeding on itself.

---

## 4. Restructuring is a change that must be verified

Any consolidation, section move, renumbering, or consistency-only pass is
followed by a verification round scoped to that pass. See
`consistency-pass.md` § "Every consistency-only pass is verified". Never approve
directly off a restructure.

---

## 5. Assertion-checked replacements

The default edit discipline for remediation.

- Every replacement must match its target **exactly once**. Use an edit tool
  that fails on 0 or >1 matches; do not hand-splice.
- On 0 matches: your assumption about the text is wrong. Re-read the document
  and re-locate. Do not loosen the match until it hits.
- On >1 matches: the rule is stated in more than one place — which is itself a
  rule-1 violation. Fix the duplication, do not blind-replace both.
- `replace_all` is permitted only for a mechanical rename where you have already
  asserted the expected count with a search.

This discipline is what catches the remediator's own mistakes at application
time instead of letting them land silently and surface as next round's findings.

---

## 6. Templates

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
| 1 | A3 | <one-line summary> | Medium | Declined | <why — e.g. "operator-ratified requirement; descoping it was proposed twice and rejected both times"> |
| 2 | B1 | <one-line summary> | Low | Deferred to v2 | <why> |
```

Every declined or deferred finding from the remediation step gets a row. Rows
are never removed — a decision that is reversed gets a new row recording the
reversal.
