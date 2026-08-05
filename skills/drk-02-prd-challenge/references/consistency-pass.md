# Consistency: the post-remediation gate and the consistency-only pass

Two different things live here. The **gate** runs after every remediation and
is mandatory. The **pass** is a first-class round type the loop switches to when
the trend says it is feeding on itself.

Both exist because a PRD states each load-bearing rule in three to five places —
requirement body, glossary, acceptance criteria, negative requirements, API
sketch. Every fix therefore has three to five propagation targets, and a fix
that lands in one of them leaves the others stale. Stale satellites come back as
next round's Critical/High findings.

---

## The post-remediation consistency gate

**Mandatory after every remediation step, before the next review round.** This
is not "check consistency" — it is a mechanical procedure whose output is a set
of counters. Every defect this catches is mechanically detectable; none of it
requires judgment.

For the set of edits you just applied:

### 1. Build the touched-identifier list

From the edits (not from memory), list every:

- **cross-reference** — requirement IDs (`REQ-xxx`), section titles/anchors,
  table names, figure or example labels, links between documents
- **threshold / parameter / default** — every number, duration, size, count,
  percentage, retry budget, timeout, enum value or flag name whose value the
  edit set, changed, or relied on
- **defined term** — every glossary term, status name, role name, state name,
  event name or field name the edit introduced, renamed, or whose meaning it
  changed

### 2. Re-resolve every entry

For each identifier on the list, search the **whole PRD** for it and check
every hit:

- Cross-reference → the target exists, is the thing being pointed at, and still
  says what the referring text claims it says.
- Threshold/parameter → every occurrence carries the **same** value, and every
  occurrence of the **old** value is gone. Search for the old value explicitly.
  The only place an old value may survive is a changelog or the Decision
  Register.
- Defined term → every use matches the current definition, and no synonym has
  crept in for the same concept (search for the plausible synonyms too).

### 3. Fix and re-run

Fix every mismatch found, using assertion-checked replacements
(`prd-structure-rules.md` § "Assertion-checked replacements"). A fix in this
step adds its own identifiers to the list — re-run step 2 over them, and it
joins the remediation delta that the round's verification will check.

### 4. Report the counters

The round record gets one line:

```
Consistency gate: <N> identifiers re-resolved, <M> stale hits found, <M> fixed, <K> passes to reach zero.
```

**The gate is not passed until a full pass over the touched-identifier list
returns zero stale hits.** A round is not finished before its gate passes.

### Stale-value check, mechanically

The single highest-yield check is the old-value sweep, because it is a pure text
search with an unambiguous expected result:

```bash
# after changing a threshold from <old> to <new>
grep -n -- '<old>' <prd-path>   # expected: zero hits outside changelog / Decision Register
grep -n -- '<new>' <prd-path>   # expected: every location that should carry it
```

Do the same for renamed terms and for removed section titles.

---

## The consistency-only pass

A first-class round type, distinct from a discovery round. The calling skill
switches to it when the trend shows the loop is self-feeding — when the majority
of a round's new Critical/High findings live in prose the previous round's
remediation added.

**Scope:** cross-reference integrity, terminology consistency, table and row
coherence, stale references, duplicated rule statements, and satellite
locations that restate a rule instead of referencing it.

### Charter — binding

**MAY:**

- Repoint or repair a stale cross-reference.
- Replace a satellite's *restatement* of a rule with a reference to the rule's
  normative home (see `prd-structure-rules.md`).
- Align a term to its glossary definition, or a value to its normative home's
  value.
- Repair table/row coherence: missing rows, rows that disagree with prose,
  columns whose meaning drifted.
- Renumber, re-anchor, and fix broken links.
- Relocate rationale prose into a marked `Why:` block or the rationale
  appendix — relocated, never deleted.

**MUST NOT:**

- Add, remove, or reword the normative content of any requirement.
- Add, remove, or reword any acceptance criterion.
- Change **any** threshold, parameter, default, limit, or enum value — including
  "obviously wrong" ones.
- Change scope: no new requirements, no descoping, no deferrals.
- Resolve an open question or make a decision the document leaves open.

### When it finds a substantive gap

**Record it; do not fix it.** Add it to the round record as:

```
NOTE (substantive, deferred to next round): <description> — found by consistency-only pass, not remediated per charter.
```

The next round picks it up under the normal remediation rules.

### Every consistency-only pass is verified

A consistency-only pass is a change to the document like any other, and it can
overstep its own charter without noticing — a real pass silently changed a
threshold and rewrote requirement text in four places, and only the verification
that followed caught it. It therefore gets a **delta verification** like every
other change (the skill's § "The delta verification" is the normative rule):

1. Diff the PRD before and after the pass.
2. Send that diff to the reviewers as a delta verification, with the block in
   `personas.md` § "Mode: delta verification", listing each change the pass made
   as an item to verdict.
3. Any change marked `NOT CONFIRMED`, or identified as outside the charter
   above, is reverted or re-done under the normal remediation rules — and the
   new delta is verified in turn.

**Never approve a PRD directly off a consistency-only pass or any other
restructure.** Restructuring fixes drift and introduces regressions in the same
motion; one real consolidation pass repaired six rounds of drift and, while
doing it, shipped the wrong user-facing copy in one place and silently removed
the normative force of an earlier fix in another.
