# PRD: <Feature Name>

**Status:** Draft | Hardened | Approved | Approved with open items
**Lane:** Standard | High-consequence
**Effort-Anchor:** <the operator's own answer to "if you did this yourself, how long would it take?", e.g. 2-4h>
**Author:** <who was interviewed>
**Date:** YYYY-MM-DD
**Last Updated:** YYYY-MM-DD
**Feature ID:** <slug>

`Effort-Anchor` is the operator's stated expectation, recorded verbatim. It is
not an estimate the agent produced, and no later stage may revise it. Every
later stage compares its projected cost against this number and stops to ask
when the projection exceeds it by the anchor stop multiple.

## Known open items — read first

Omit this section entirely while the PRD still has open items pending. The
challenge round adds it, using the template in `df-prd-challenge`'s
`references/prd-structure-rules.md`, only when the PRD is approved with
residue. It goes here, above everything else, because it is written for the
zero-context implementing agent.

## Pinned Parameters

Every threshold, limit, timeout, default, retry budget, size cap and enum this
document depends on gets one row here. Everywhere else refers to the parameter
by name and never restates the value.

| Parameter | Value | Applies to |
|-----------|-------|------------|
| `<NAME>` | <value> | <which requirement or behavior> |

If the feature has no tunables: "No pinned parameters — this feature has no
thresholds, limits, or configurable defaults."

**Reading conventions.** Requirements and Negative Requirements are normative.
Acceptance criteria, Edge Cases, the Glossary, and any examples are satellites:
they may repeat a value, and they may never restate a rule or introduce
behavior that has no normative home.

## Purpose

[1-2 paragraphs: What problem does this solve? Why now? What's the context?]

## Scope

### In Scope

- [Bulleted list of what this feature includes]

### Out of Scope

- [Explicit exclusions — what this feature does NOT do]

## Requirements

### REQ-001: <Requirement Name>

**Priority:** P0 | P1 | P2

Behavior:
1. [Atomic, verifiable predicate — one testable behavior per item]
2. [...]

Acceptance:
- [Testable assertion a QA agent can verify through the UI]
- [...]

---

### REQ-002: <Requirement Name>

**Priority:** P0 | P1 | P2

Behavior:
1. [...]

Acceptance:
- [...]

---

[Repeat for each requirement]

## Negative Requirements

### NEG-001: <Constraint Name>

**Related to:** REQ-xxx (or "General" if not tied to a specific requirement)

- [What must NOT happen — explicit constraints on behavior]
- [Example: "Deleting a team must NOT delete the team's projects"]

---

[Repeat for each negative requirement]

## Edge Cases

| Requirement | Edge Case | Expected Behavior |
|-------------|-----------|-------------------|
| REQ-001 | [Unusual input or state] | [What should happen] |
| REQ-001 | [Error condition] | [How the system responds] |
| REQ-002 | [...] | [...] |

## Non-Functional Requirements

| NFR | Threshold | Measurement |
|-----|-----------|-------------|
| Response time | < Xms p95 | [How to measure] |
| Accessibility | WCAG 2.1 AA | [Audit tool or manual check] |
| [Other] | [Measurable target] | [Method] |

If no NFRs apply: "No non-functional requirements identified — [brief justification]."

## Glossary

| Term | Definition |
|------|-----------|
| [Ambiguous term] | [Precise definition in this context] |

If no ambiguous terms: "No ambiguous terms identified."

## Constraints & Assumptions

- [Technical constraints (e.g., must work with existing auth system)]
- [Deployment assumptions (e.g., feature flag rollout)]
- [Dependencies on other features or services]

## Decision Register

Findings raised during review and deliberately not applied. A reviewer
re-raising one of these should be answered by citing the entry, unless the
severity has risen or new evidence is offered. Rows are never removed; a
reversed decision gets a new row recording the reversal.

| # | Round | Finding | Severity | Decision | Reason |
|---|-------|---------|----------|----------|--------|
| 1 | — | <one-line summary> | Medium | Declined — not real | <what was checked and what was found> |

The interview starts this table empty. `df-prd-challenge` owns what goes in it;
`references/prd-structure-rules.md` in that skill is the normative rule for
what the register records.
