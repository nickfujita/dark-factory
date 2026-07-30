# QA Runbook Template

Every generated QA runbook must follow this exact structure. The structure
adapts based on `feature_type` in the frontmatter.

## YAML Frontmatter

```yaml
---
id: qa-<feature-slug>
prd: docs/prd-<feature-slug>.md
feature_type: ui | backend | hybrid
# test_framework: vitest  # include for backend/hybrid; auto-discovered
base_url: http://localhost:3000
generated: YYYY-MM-DD
timeout: 30000
# startup_command: pnpm dev:all
# auth:
#   method: form
#   notes: "Login at /login with test credentials"
---
```

- `id`: matches the PRD feature slug with `qa-` prefix
- `prd`: relative path to the source PRD
- `feature_type`: `ui`, `backend`, or `hybrid` — determines which test
  sections to include
- `test_framework`: (for backend/hybrid) the project's test runner. Auto-
  discovered from project config. Default: `vitest`
- `base_url`: app URL used by drk-07-qa-acceptance. Must point to local/dev/
  test, never production. Required if TC-xxx test cases exist.
- `generated`: date the runbook was generated
- `timeout`: default timeout in milliseconds for agent-browser waits
- `startup_command`: (optional) shell command to start the app before testing.
  If omitted, skills auto-discover from `package.json` scripts or `Makefile`.
- `auth`: (optional) authentication hint — use block mapping style

## Document Structure — UI Features (`feature_type: ui`)

```markdown
# QA Acceptance Runbook: <Feature Name>

## Preconditions

- [Account/data setup required before testing]
- [Environment prerequisites (e.g., "Product catalog has at least one item")]
- [Authentication requirements]

## Test Cases

### TC-001: <Descriptive Scenario Name> [P0 - Critical]

**Traces to:** REQ-001

Steps:
1. [User action in natural language]
2. [Next user action]

Assertions:
- VERIFY text "<expected text>" visible in element matching "<UI description>"
- VERIFY element matching "<UI description>" is visible

---

[Continue for all test cases]

## Coverage Matrix

| Requirement | Test Cases | Status |
|-------------|-----------|--------|
| REQ-001 | TC-001, TC-002 | Covered |
| NEG-001 | TC-002 | Covered |
```

## Document Structure — Backend Features (`feature_type: backend`)

```markdown
# QA Acceptance Runbook: <Feature Name>

## Preconditions

- [Environment setup]
- [Dependencies and services that must be running]
- [Test data requirements]

## Programmatic Test Specifications

Test framework: <auto-discovered framework, e.g., vitest>

### Unit Tests

#### UT-001: <Descriptive Test Name> [P0 - Critical]

**Traces to:** REQ-001
**Module:** <package or module under test>

**Scenario:** <what is being tested — input conditions, state>
**Expected:** <expected behavior or output>

---

#### UT-002: <Descriptive Test Name> [P1 - High]

**Traces to:** REQ-001 (edge case)
**Module:** <package or module under test>

**Scenario:** <edge case or error condition>
**Expected:** <expected behavior>

---

### Integration Tests

#### IT-001: <Descriptive Test Name> [P0 - Critical]

**Traces to:** REQ-001, REQ-002
**Components:** <components/services that interact>

**Setup:** <any test-specific setup beyond preconditions>
**Scenario:** <what interaction is being tested>
**Expected:** <expected behavior across component boundaries>

---

### E2E Tests

#### ET-001: <Descriptive Test Name> [P0 - Critical]

**Traces to:** REQ-001
**Flow:** <end-to-end flow being tested>

**Scenario:** <full flow description — from trigger to final state>
**Expected:** <expected end state>

---

## UI Surface Tests

These test cases verify that backend changes are visible and correctly
represented in the frontend. Surfaces may be existing UI or proposed
locations where the feature should be surfaced.

### TC-001: <Descriptive Scenario Name> [P1 - High]

**Traces to:** REQ-001
**Surface:** Existing — <page name or path where this data appears>

Steps:
1. [Navigate to the relevant page]
2. [Perform actions to trigger display of the backend feature]

Assertions:
- VERIFY text "<expected>" visible in element matching "<UI description>"
- VERIFY element matching "<UI description>" is visible

---

### TC-002: <Proposed Surface Scenario Name> [P2 - Medium]

**Traces to:** REQ-003
**Surface:** Proposed — <description of where this should appear and why>

Steps:
1. [Navigate to proposed location]
2. [Expected user flow to see the backend feature]

Assertions:
- VERIFY [expected UI state if this surface is implemented]

---

## Coverage Matrix

| Requirement | Programmatic Tests | Browser Tests | Status |
|-------------|-------------------|---------------|--------|
| REQ-001 | UT-001, UT-002, IT-001 | TC-001 | Covered (both) |
| REQ-002 | IT-001, ET-001 | — | Covered (programmatic) |
| REQ-003 | UT-003 | TC-002 (proposed) | Covered (programmatic) |
| NEG-001 | UT-004 | TC-003 | Covered (both) |
```

## Document Structure — Hybrid Features (`feature_type: hybrid`)

Combine both structures: UI requirements get TC-xxx test cases, backend
requirements get programmatic test specs (UT/IT/ET-xxx), and UI surface discovery runs for backend requirements. Use the backend document
order with both test types present.

## Rules for Browser Automation Steps (TC-xxx)

- Steps describe what the USER does, never what the system does internally
- Use UI labels and visible text, not CSS selectors or test IDs
- Use `data-testid` hints only in parentheses when available:
  `Click "Add to Cart" (data-testid: "add-to-cart-btn")`
- Each step is a single atomic action (click, fill, navigate, etc.)
- Navigation steps start with "Open" or "Navigate to"
- Fill steps use the format: `Fill "<field label>" with "<value>"`
- Click steps use the format: `Click "<button/link label>"`

## Rules for Programmatic Test Specs (UT/IT/ET-xxx)

- Specs describe WHAT to test and WHAT to expect, not HOW to implement
- Reference module names, API endpoints, data structures, and protocols
  as needed — these are technical specifications
- Keep specs framework-agnostic where possible — describe behavior, not
  assertion syntax
- Each spec must be concrete enough that a developer can write the test
  without ambiguity
- Include relevant test data or input/output examples when they clarify
  the scenario

## Rules for Assertions (TC-xxx only)

Every assertion starts with `VERIFY`. Assertions describe visible UI state,
not internal state. Use "element matching" followed by a UI description
(not a selector). Separate assertions from steps — never embed assertions
in steps. Each test case must have at least one assertion.

**Supported assertion patterns:**

| Pattern | Example |
|---------|---------|
| Text in element | `VERIFY text "Welcome" visible in element matching "header greeting"` |
| Element visible | `VERIFY element matching "success banner" is visible` |
| Element not visible | `VERIFY element matching "error message" is not visible` |
| URL contains | `VERIFY current URL contains "/dashboard"` |
| Input value | `VERIFY field "<field label>" contains value "<expected>"` |
| Element count | `VERIFY <N> elements matching "<description>" are visible` |
| Element disabled | `VERIFY element matching "<description>" is disabled` |
| Text not present | `VERIFY text "<text>" is not visible on page` |

The "element matching" description should be concrete and observable: use
headings, labels, ARIA roles, visible text, or relative positions. Avoid
vague descriptions. Examples:
- Good: `element matching "the 'Order Total' section in the checkout summary"`
- Good: `element matching "notification banner at the top of the page"`
- Bad: `element matching "success notification"` (too vague — which one?)

## Traceability Annotations

- Happy path: `**Traces to:** REQ-001`
- Edge case: `**Traces to:** REQ-001 (edge case)`
- Negative requirement: `**Traces to:** NEG-001 (related to REQ-002)`
- Multiple requirements: `**Traces to:** REQ-001, REQ-003`

## Coverage Matrix Status Values

- `Covered` — at least one test exists (ui features, single-type coverage)
- `Covered (both)` — has both programmatic and browser automation tests
- `Covered (programmatic)` — covered by UT/IT/ET only
- `Covered (browser)` — covered by TC only
- `UNTESTABLE: <reason>` — requirement cannot be tested

## Priority Tags

- `[P0 - Critical]` — Core flow, must pass for feature to ship
- `[P1 - High]` — Important edge case or secondary flow
- `[P2 - Medium]` — Nice-to-have coverage, non-blocking
