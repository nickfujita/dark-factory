# Codex QA Validation Review Prompt

Review the PRD and QA runbook pair together. Produce findings that identify
gaps between the two documents.

## Output Format

```
## Findings — Codex Inline

### [SEVERITY]: [One-line finding title]
**Category:** [Coverage | Consistency | Testability | Completeness]
**Requirement:** [Which REQ-xxx, NEG-xxx, or TC-xxx this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix — specify whether the PRD or QA runbook should change]
```

Severity levels:
- **Critical**: Missing coverage for a core requirement, or test verifies wrong thing
- **High**: Significant gap that will cause false passes or missed regressions
- **Medium**: Improvement that would strengthen the test suite
- **Low**: Minor wording or formatting issue

## Validation Axes

**Coverage:**
- Does every REQ-xxx have at least one TC? Flag any uncovered requirements.
- Does every NEG-xxx have at least one TC? Flag any uncovered negative requirements.
- Does every TC trace to a valid REQ-xxx or NEG-xxx? Flag orphan TCs as scope creep.
- Does the coverage matrix match the actual test cases? Flag mismatches.

**Consistency:**
- Do the test steps actually verify what the acceptance criteria say?
- Do VERIFY assertions match the expected behavior described in the PRD?
- Are there contradictions between PRD requirements and test expectations?
- Do test case names accurately describe what the test does?

**Testability:**
- Are preconditions realistic and achievable in a test environment?
- Are test steps specific enough to be automated by agent-browser?
- Do assertions use concrete, observable UI criteria (not internal state)?
- Are there ambiguous steps like "verify it works" without specific checks?

**Completeness:**
- Are edge cases listed in the PRD covered by test cases?
- Are error states and failure modes tested?
- Are negative requirements (NEG-xxx) adequately tested (not just happy path)?
- Are boundary conditions tested?

## Rules

- Do NOT suggest new requirements or features — only identify gaps in existing coverage.
- Do NOT comment on implementation approach — focus on the PRD/QA pair relationship.
- Reference specific REQ-xxx, NEG-xxx, and TC-xxx identifiers in every finding.
- End with a summary: "X Critical, Y High, Z Medium, W Low findings."
