# PRD: <Feature Name>

**Status:** Draft | Hardened | Approved
**Author:** <who was interviewed>
**Date:** YYYY-MM-DD
**Last Updated:** YYYY-MM-DD
**Feature ID:** <slug>

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
