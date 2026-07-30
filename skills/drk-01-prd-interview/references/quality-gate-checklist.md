# PRD Quality Gate Checklist

All 7 items must pass before the PRD status changes from "Draft" to "Hardened".

## The Checklist

- [ ] **Atomic acceptance criteria**: Every acceptance criterion is a single,
  verifiable predicate (not prose). No criterion should be a tautology of
  its parent requirement. Bad: "The form should work well."
  Good: "Submitting with an empty email field shows inline error 'Email is required'."

- [ ] **Negative/edge cases per requirement**: Every REQ-xxx has at least one
  entry in the Edge Cases table. If a requirement has no edge cases listed,
  the interviewer must probe: "What happens if the user does X wrong?"

- [ ] **Measurable NFRs**: Non-functional requirements have numeric thresholds
  and a measurement method. If no NFRs apply, the section must state
  "No non-functional requirements identified" with brief justification.
  Bad: "Should be fast." Good: "< 200ms p95 measured by Lighthouse."

- [ ] **Glossary for ambiguous terms**: Any domain-specific or overloaded term
  has a definition in the Glossary section. If there are no ambiguous terms,
  the Glossary section should say "No ambiguous terms identified."

- [ ] **Explicit scope boundaries**: The "Out of Scope" section is non-empty
  and lists specific exclusions. Every PRD must say what it does NOT include.

- [ ] **At least one requirement**: The PRD contains at least one REQ-xxx
  with acceptance criteria. A PRD with no requirements is incomplete.

- [ ] **Priority assigned**: Every REQ-xxx has a Priority field set to
  P0, P1, or P2. Priorities must have been confirmed with the user during
  the interview — do not assign priorities without user input.

## How to Run the Gate

After drafting the PRD, evaluate each item:
1. Read through every acceptance criterion — is each one a single testable
   predicate? Is it specific enough that a QA engineer unfamiliar with the
   feature would know exactly what to test?
2. For each REQ-xxx, check the Edge Cases table — is there at least one entry?
3. Check the NFR table — does every row have a numeric threshold and measurement?
   If no NFRs, verify the section explains why.
4. Check the Glossary — are all potentially ambiguous terms defined?
5. Check Out of Scope — is it non-empty with specific exclusions?
6. Verify at least one REQ-xxx exists with acceptance criteria.
7. Verify every REQ-xxx has a Priority field (P0, P1, or P2).

If any item fails, tell the user which item failed and what's missing.
Loop back to the relevant interview topic to fill the gap.
Max 3 gate attempts — after the third failure, save as Draft with notes.
