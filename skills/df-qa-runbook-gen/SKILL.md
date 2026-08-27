---
name: df-qa-runbook-gen
description: "Machine-generate a QA acceptance runbook from a hardened PRD: a structured runbook with YAML frontmatter, traceability links, and a coverage matrix. Supports UI-focused, backend/protocol, and hybrid features; no user interaction once started. Runs when the df feature playbook reaches its QA-runbook stage or when the operator invokes it explicitly — never on its own."
disable-model-invocation: true
---

# QA Runbook Generation

Generate a QA acceptance runbook from a hardened PRD. The runbook contains
test scenarios covering the full testing pyramid — from programmatic tests
(unit, integration, e2e) to browser automation — based on the feature type.
No user interaction is needed — this skill runs autonomously.

## Prerequisites

- A PRD file with Status: Hardened, Approved, or Approved with open items
- The PRD must have passed its quality gate (acceptance criteria are testable)

## Workflow

### Step 1: Locate and Read the PRD

**Locate the PRD file** using this priority:
1. If the user or previous pipeline step provided an explicit path, use it.
2. If the conversation context mentions a specific PRD file, use that path.
3. Scan `docs/` for files matching `prd-*.md`. If exactly one is found with
   Status: Hardened, Approved, or Approved with open items, use it. If
   multiple match, list them and ask the user which one to use (this is the
   only acceptable user interaction).
4. If no PRD is found, stop and report: "No PRD file found. Please provide
   the path to the PRD."

**Read the PRD file.** Check the Status field. If it is not "Hardened",
"Approved", or "Approved with open items", stop and report: "PRD status is
`<status>`. QA runbook generation requires a Hardened or Approved PRD."

**If the status is "Approved with open items"**, the PRD carries a
"Known open items — read first" section: unresolved questions the challenge
round deliberately left open. Read it before generating anything, do not invent
answers for those items, and carry each one into the runbook's assumptions so
the QA runner sees the same caveat the implementer does.

**Extract:**
- All requirements (REQ-xxx) with their acceptance criteria
- All edge cases from the Edge Cases table
- All negative requirements (NEG-xxx) with their related requirements
- Preconditions from the Constraints & Assumptions section
- The feature name and slug for output naming
- Priority for each requirement (default to P1 if not specified)

**Derive the feature slug** from the PRD filename: extract the filename
only (strip directory path), strip the `prd-` prefix and `.md` suffix,
then lowercase the result. Example: `docs/prd-User-Auth.md` -> slug
`user-auth`. This works regardless of the directory structure.

### Step 1.5: Feature Classification

**Classify the feature type** by analyzing the PRD requirements:

| Type | When to use | Test strategy |
|------|-------------|---------------|
| **ui** | Feature is primarily UI/frontend — new pages, components, user flows, visual changes | Browser automation test cases (TC-xxx) |
| **backend** | Feature is primarily backend/protocol — APIs, engines, data processing, security policies, integrations | Programmatic test specs (UT/IT/ET-xxx) + UI surface discovery |
| **hybrid** | Feature spans both — backend logic with significant UI | Both programmatic test specs AND browser automation test cases |

Classification signals:
- **ui**: PRD mentions pages, modals, forms, layouts, navigation, user-facing workflows
- **backend**: PRD mentions protocols, engines, policies, data pipelines, SDKs, APIs, integrations, cryptographic operations
- **hybrid**: PRD has both UI deliverables and backend components with independent testable behavior

Default to **hybrid** when uncertain — it produces the most complete runbook.

**Auto-discover the test framework:**
1. Check `package.json` for test scripts and dependencies (vitest, jest, playwright, cypress)
2. Check for config files: `vitest.config.*`, `jest.config.*`, `playwright.config.*`
3. Check `Makefile`, `pyproject.toml`, `pytest.ini` for non-JS projects
4. Default to `vitest` if nothing is discovered

Record the feature type and test framework for use in subsequent steps.

### Step 2: Generate Test Cases

Read `references/runbook-template.md` for the exact output format.
(This file is in the skill directory: `$HOME/.claude/skills/df-qa-runbook-gen/references/`
or the repo's `skills/df-qa-runbook-gen/references/` directory. If neither
exists, stop and report the error — do not invent a format.)

**Preconditions**: Generate the Preconditions section from the PRD's
Constraints & Assumptions section and any setup requirements implied by
the requirements (e.g., "user must be logged in", "test product must exist").

---

#### Path A: UI Features (`feature_type: ui`)

Generate browser automation test cases using the standard format:

**Test cases from requirements**: For each REQ-xxx:
1. Write a happy path test case covering the core acceptance criteria
2. Write edge case / negative test cases from the Edge Cases table
3. Assign the same priority as the source requirement (default P1 if missing)
4. Add a `Traces to: REQ-xxx` link. A TC may trace to multiple
   requirements — list all: `Traces to: REQ-001, REQ-003`

**Test cases from negative requirements**: For each NEG-xxx:
1. Write a test case that verifies the constraint is enforced
2. Trace to the related REQ-xxx if specified, or to the NEG-xxx itself:
   `Traces to: NEG-001 (related to REQ-002)`
3. Assign P0 priority (negative requirements are safety constraints)

Rules:
- Steps are natural language describing user actions
- Assertions use the `VERIFY` format from the template
- Each test case has a unique ID (TC-001, TC-002, ...)
- Test case names are descriptive (not "Test 1")

---

#### Path B: Backend/Protocol Features (`feature_type: backend`)

Generate two categories of test content:

##### B.1: Programmatic Test Specifications

For each REQ-xxx and NEG-xxx, generate specifications for the three test
layers. These are specs describing WHAT to test, not test code.

**Unit tests (UT-xxx):** Test individual functions, methods, or modules in
isolation.
- One or more UT per requirement, focusing on the core logic
- Cover happy path, edge cases, and error conditions
- Reference the module/package being tested
- IDs: UT-001, UT-002, ...

**Integration tests (IT-xxx):** Test interactions between components,
services, or subsystems.
- Cover data flow between modules, API request/response cycles, database
  operations, external service interactions
- Reference the components that interact
- IDs: IT-001, IT-002, ...

**E2E tests (ET-xxx):** Test complete user-visible flows exercised
programmatically (not via browser).
- Cover full request lifecycle, multi-step operations, cross-component
  workflows
- These run in the test framework (e.g., Vitest) not in a browser
- IDs: ET-001, ET-002, ...

Rules for programmatic test specs:
- Specs describe the test scenario and expected behavior, not implementation
- Reference module names, API endpoints, and data structures as needed — the
  Spec Guardian rules do NOT apply to programmatic test specs
- Each spec traces to at least one REQ-xxx or NEG-xxx
- Prioritize coverage of core business logic and safety-critical paths

##### B.2: UI Surface Discovery

After generating programmatic test specs, **search the codebase** for
frontend/UI locations where the backend changes are or could be
surfaced to users. This step serves two purposes:
1. Generate browser automation TCs for existing surfaces (testing)
2. Propose surfaces where backend changes SHOULD be visible (informing
   the development team how to surface new features in the UI)

**Search strategy:**
1. Scan frontend/UI directories for components that reference the
   backend module, API endpoints, or data types from the PRD
2. Look for admin panels, settings pages, monitoring views, or
   management interfaces related to the feature domain
3. Check route definitions for pages that display relevant data
4. Search for existing UI patterns that could be extended (tables, lists,
   detail views, configuration forms, status indicators)

**For each surface found or proposed, generate a browser automation TC:**
- Use the standard TC-xxx format with VERIFY assertions
- Tag existing surfaces: `**Surface:** Existing — <page/component>`
- Tag proposed surfaces: `**Surface:** Proposed — <description of where
  this should appear and why>`
- Proposed surfaces help inform the development team about where backend
  changes should be accessible from the UI, even if the surface doesn't
  exist yet

**Be creative but don't force it.** If a backend change genuinely has no
meaningful frontend surface (e.g., internal cryptographic improvements),
note this in the coverage matrix rather than inventing artificial surfaces.
But try — most backend changes have at least a status indicator, a log
view, a configuration toggle, or a metrics display where they could be
surfaced.

---

#### Path C: Hybrid Features (`feature_type: hybrid`)

Apply **both** Path A and Path B:
1. Generate browser automation test cases (TC-xxx) for UI requirements
2. Generate programmatic test specs (UT/IT/ET-xxx) for backend requirements
3. Run UI surface discovery for backend requirements that lack
   direct UI test cases
4. Avoid duplicating coverage — if a requirement already has a TC, don't
   also generate an ET that tests the same thing from the browser

---

### Step 3: Add Frontmatter

Add YAML frontmatter with:
- `id`: `qa-<feature-slug>`
- `prd`: relative path to the source PRD
- `feature_type`: `ui`, `backend`, or `hybrid` (from Step 1.5)
- `test_framework`: auto-discovered test framework (from Step 1.5, omit for `ui`-only)
- `base_url`: target app URL for df-qa-acceptance (only if TC-xxx test cases exist)
- `generated`: today's date (YYYY-MM-DD)
- `timeout`: 30000 (default)
- `auth`: (optional) authentication hint for df-qa-acceptance

`base_url` rule:
- Default to `http://localhost:3000`.
- If the PRD or project docs specify a URL, use it only if it is clearly a
  local/dev/test environment (`localhost`, `127.0.0.1`, `::1`, `.local`,
  `.test`, `.dev`).
- Never emit production-like URLs in generated runbooks.
- If only production URLs are documented, keep `http://localhost:3000` and
  add a Preconditions note: "Set `base_url` to your local/dev environment
  before execution."

`startup_command` rule:
- If the PRD or project docs mention a command to start the dev server
  (e.g., `pnpm dev:all`, `npm run dev`, `make run`), populate this field.
- If no startup command is mentioned, omit the field — skills will
  auto-discover it from the repo.

`auth` rule — use block mapping style (not flow mapping) to avoid YAML
escaping issues:
```yaml
auth:
  method: form
  notes: "Login at /login with test credentials"
```
- If the Preconditions or PRD mention authentication requirements, include
  the `auth` field.
- If the app does not require authentication, omit the field entirely.

### Step 4: Bidirectional Coverage Check

Build the coverage matrix:
1. For every REQ-xxx, verify at least one test (TC, UT, IT, or ET) exists ->
   if not, generate it
2. For every NEG-xxx, verify at least one test exists -> if not, generate it
3. For every test, verify it traces to a REQ-xxx or NEG-xxx -> if not, the
   test is scope creep and should be removed
4. If a test traces to multiple requirements, list it under each requirement
   in the coverage matrix

Coverage status values:
- `Covered` — at least one test exists (ui features, single-type coverage)
- `Covered (programmatic)` — covered by UT/IT/ET only (no browser automation)
- `Covered (browser)` — covered by TC only
- `Covered (both)` — covered by both programmatic tests and browser automation
- `UNTESTABLE: <reason>` — cannot be tested (use canonical colon-delimited format)

For **backend** and **hybrid** features: if a requirement is covered only
by programmatic tests (no TC), this is acceptable — do not mark it as
UNTESTABLE. But note in the coverage matrix whether a UI surface
was proposed.

### Step 5: Spec Guardian Check

Read `references/spec-guardian-rules.md`.
(This file is in the skill directory: `$HOME/.claude/skills/df-qa-runbook-gen/references/`
or the repo's `skills/df-qa-runbook-gen/references/` directory.)

**Scope: browser automation test cases (TC-xxx) only.** Programmatic test
specifications (UT-xxx, IT-xxx, ET-xxx) are exempt from Spec Guardian rules
because they are technical specifications that necessarily reference
modules, APIs, and data structures.

Scan every **TC-xxx** test case for forbidden content:
- Code identifiers, API endpoints, database references
- Internal architecture, HTTP details, test framework internals
- Infrastructure and configuration details (env vars, config paths, service names)

If violations are found, rewrite the offending steps/assertions using only
user-visible language. If a step cannot be rewritten without implementation
details, flag the requirement as `UNTESTABLE: <reason>`.

**`data-testid` rule**: A `data-testid` hint is allowed only in parentheses
as supplementary info. The step must be understandable without the
parenthetical. If removing the `data-testid` parenthetical makes the step
ambiguous, improve the UI label description instead.

**User-facing URL rule**: URLs that appear in the browser's address bar
are allowed in navigation steps (e.g., `Navigate to /products/new`). Only
API-internal routes that users never see are forbidden.

### Step 5b: Cross-Check Loop

After Steps 4 and 5, if either step generated new TCs or rewrote existing
ones, re-run both checks on the changed TCs only:
- New TCs from Step 4 must pass the spec guardian (Step 5)
- Rewritten TCs from Step 5 must still satisfy coverage (Step 4)

The initial execution of Steps 4 and 5 is pass 1. If changes occurred,
re-run both checks on changed TCs (pass 2). **No further passes.** If
violations remain after pass 2, flag the affected test cases with
`UNTESTABLE: guardian violation after 2 correction rounds` in the coverage
matrix. Do not suppress the test cases — include them with the flag so the
user can review.

Note: This loop applies only to TC-xxx test cases. Programmatic test specs
(UT/IT/ET-xxx) are not subject to the cross-check loop.

### Step 6: Output

Assemble the final document: frontmatter (Step 3) + preconditions + test
content (Step 2, as modified by Steps 4/5/5b) + coverage matrix (Step 4).

Document order for **backend** and **hybrid** features:
1. Frontmatter
2. Preconditions
3. Programmatic Test Specifications (Unit -> Integration -> E2E)
4. UI Surface Tests / Browser Automation Test Cases
5. Coverage Matrix

Document order for **ui** features:
1. Frontmatter
2. Preconditions
3. Test Cases (TC-xxx)
4. Coverage Matrix

1. Create the output directory: `mkdir -p docs/qa`
2. Save to `docs/qa/qa-<feature-slug>.md`
3. Report: "QA runbook generated at `docs/qa/qa-<feature-slug>.md`
   with X test specs and Y browser automation TCs covering Z out of W
   total requirements. Feature type: `<type>`.
   [List any UNTESTABLE requirements if applicable]"

### Step 7: Trigger Validation

After the QA runbook is generated, trigger the `df-qa-validation` skill
with both paths:
- PRD path: the source PRD used for generation
- QA runbook path: the just-generated `docs/qa/qa-<feature-slug>.md`

Start the validation immediately after Step 6. Pass both paths explicitly.
Only skip this trigger if the user explicitly asks to defer it.

## Notes

- **Reference file resolution**: `references/runbook-template.md` and
  `references/spec-guardian-rules.md` are relative to the skill directory.
  Look in `$HOME/.claude/skills/df-qa-runbook-gen/references/` (global) or
  the repo's `skills/df-qa-runbook-gen/references/` directory.
- This skill runs autonomously — do not ask the user questions during
  generation except to disambiguate which PRD to use.
- If the PRD has ambiguous requirements that can't be turned into tests,
  flag them as `UNTESTABLE: <reason>` rather than guessing intent.
- The coverage matrix is the key quality artifact — it proves bidirectional
  traceability between requirements and tests.
- For backend features, UI surface discovery is a creative exercise —
  propose surfaces where backend changes could be visible to users, even if
  those surfaces don't exist yet. This informs the development team about
  where to surface new capabilities in the frontend.
