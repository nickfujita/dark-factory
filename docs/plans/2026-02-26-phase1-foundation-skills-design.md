# Phase 1 Foundation Skills — Design Document

## Goal

Build the 4 reusable skills that form the planning pipeline: PRD interview,
PRD challenge round, QA runbook generation, and QA execution. These skills
live in `dark-factory/skills/` and are synced to `~/.claude/skills/` for use
in any project repo.

## Architecture

**Hybrid skill structure**: 3 pure SKILL.md skills + 1 skill with scripts.

```
skills/
  prd-interview/                  # Pure SKILL.md
    SKILL.md
    references/
      prd-template.md
      quality-gate-checklist.md

  prd-challenge/                  # SKILL.md + scripts (needs Codex CLI)
    SKILL.md
    scripts/
      run_codex_prd_review.sh
    references/
      personas.md
      synthesis-prompt.md

  qa-runbook-gen/                 # Pure SKILL.md
    SKILL.md
    references/
      runbook-template.md
      spec-guardian-rules.md

  qa-acceptance/                  # Pure SKILL.md
    SKILL.md
```

Skills are invoked from the target project repo (e.g., `~/my-project`).
They have natural access to the project's codebase, docs, and git history.

## Constraints

- PRDs output to `docs/prd-<feature>.md` in the target project
- QA runbooks output to `docs/qa/qa-<feature>.md` in the target project
- No project-specific logic in the skills — they must work across any repo
- Phase 1.5 (existing QA doc cleanup) is deferred — it's project-specific
- Superpowers is already installed globally

---

## Skill 1: PRD Interview (`skills/prd-interview/`)

### Purpose

Interactive skill that guides a user through defining a feature as a PRD.
Claude asks questions one at a time, probing for requirements, edge cases,
and scope boundaries. Output is a structured PRD document that passes a
hard quality gate.

### Interview Process

1. **Context gathering** — Read project's CLAUDE.md, README, recent commits,
   existing docs. Understand the codebase before asking anything.
2. **Open exploration** — "What are you building? What problem does it solve?"
   Free-form to understand the idea.
3. **Structured probing** — One question at a time, multiple choice preferred:
   - User flows (happy path first, then edge cases)
   - Negative requirements ("What should NOT happen?")
   - Scope boundaries ("What's explicitly out of scope?")
   - Existing behavior that must not change
   - Non-functional requirements (performance, security, accessibility)
   - Ambiguous terms (building the glossary)
4. **Draft PRD** — Write the PRD in the template format, present to user
5. **Quality gate** — Run the 5-item checklist. If any item fails, loop
   back to fill gaps.
6. **Output** — Save to `docs/prd-<feature>.md`, commit to git

### PRD Template

```markdown
# PRD: <Feature Name>

**Status:** Draft | Hardened | Approved
**Date:** YYYY-MM-DD
**Feature ID:** <slug>

## Purpose
[Context, rationale, what problem this solves]

## Scope
### In Scope
[Bulleted list of what's included]
### Out of Scope
[Explicit exclusions]

## Requirements
### REQ-001: <Requirement Name>
**Priority:** P0/P1/P2
Requirements:
1. [Atomic, verifiable predicate]
2. [...]
Acceptance:
- [Testable assertion]
- [...]

### REQ-002: ...
[Repeat for each requirement]

## Negative Requirements
[What must NOT happen — explicit constraints]

## Edge Cases
[Per-flow edge cases, each tied to a requirement]

## Non-Functional Requirements
| NFR | Threshold | Measurement |
|-----|-----------|-------------|
| Response time | < 200ms p95 | Lighthouse / API benchmark |
| ... | ... | ... |

## Glossary
| Term | Definition |
|------|-----------|
| ... | ... |

## Constraints & Assumptions
[Technical constraints, deployment notes, dependencies]
```

### Quality Gate Checklist

All 5 must pass before the PRD is marked "Hardened":

- [ ] All acceptance criteria are atomic, verifiable predicates (not prose)
- [ ] Every user flow has at least one negative/edge case
- [ ] Non-functional requirements stated with measurable thresholds
- [ ] Domain glossary exists for any ambiguous terms
- [ ] Scope boundaries explicitly defined (what is NOT included)

---

## Skill 2: PRD Challenge Round (`skills/prd-challenge/`)

### Purpose

Stress-test a hardened PRD with 4 parallel reviewers — 3 Claude persona
sub-agents + 1 Codex CLI review. Synthesize findings into a prioritized
question list for the user.

### The 4 Reviewers

1. **Skeptical User Advocate** (Claude sub-agent via Task tool):
   Focus: UX edge cases, error states, empty states, confusing flows,
   accessibility gaps.
   Input: draft PRD + project codebase access.
   Output: markdown findings with severity.

2. **Technical Feasibility Reviewer** (Claude sub-agent via Task tool):
   Focus: codebase pattern analysis, underspecified requirements,
   unrealistic expectations, integration pain, data model implications.
   Input: draft PRD + deep codebase access (reads existing code).
   Output: markdown findings with severity.

3. **Scope & Complexity Challenger** (Claude sub-agent via Task tool):
   Focus: hidden complexity, unstated assumptions, cuttable scope,
   YAGNI violations, scope creep.
   Input: draft PRD.
   Output: markdown findings with severity.

4. **Codex CLI Review** (shell script):
   Uses existing `review-prd-with-codex` skill pattern.
   Runs `codex exec` with PRD content as input.
   Independent model (GPT) perspective.
   Output: markdown findings report.

### Orchestration

- 3 Claude sub-agents launch in parallel via 3 simultaneous Task tool calls
- Codex review launches via bash in parallel with the sub-agents
- Wait for all 4 to complete
- Claude synthesizes all outputs into a single prioritized list:
  - Tagged with source persona + severity (Critical/High/Medium/Low)
  - Deduplicated where multiple reviewers raised the same concern
  - Critical/High presented to user; Medium/Low noted for reference

### Recheck Loop

- After user addresses Critical/High questions and updates PRD, run a
  lightweight recheck: single Claude call reading updated PRD + previous
  Q&A asking "Any remaining Critical or High concerns?"
- Clean → proceed to Stage 3 (QA runbook generation)
- New issues → user addresses, then proceed (max 2 total rounds)
- User can override at any time ("good enough, move on")

---

## Skill 3: QA Runbook Generation (`skills/qa-runbook-gen/`)

### Purpose

Machine-generate a QA acceptance runbook from the hardened PRD. No user
interaction — runs entirely autonomously. Output is a structured QA
document that agent-browser can execute.

### Generation Process

1. **Read hardened PRD** — Parse all requirements, acceptance criteria,
   edge cases, negative requirements
2. **Generate test cases** — For each requirement:
   - Happy path scenario per user flow
   - Negative/edge case scenarios from PRD's edge cases section
   - Priority tag matching requirement priority
   - Natural language steps (what user clicks/types/sees)
   - Assertions separated from actions
3. **Add YAML frontmatter** — Machine-parseable config (id, prd path,
   generated date, timeout)
4. **Run bidirectional coverage check**:
   - Every PRD requirement has at least one QA scenario
   - Every QA scenario traces to a PRD requirement
5. **Run spec guardian check** — Reject/rewrite scenarios containing:
   - Class names, function names, variable names
   - API endpoint paths (e.g., `/api/v1/users`)
   - Database table/column names
   - Internal architecture references
   - Only allow: UI element labels, visible text, user-facing URLs
6. **Self-correct** — If checks fail, revise and re-check (max 2 rounds)
7. **Flag untestable requirements** — Requirements that can't be expressed
   as UI tests get a note for user review at sign-off
8. **Output** — Save to `docs/qa/qa-<feature>.md`

### QA Runbook Output Format

```yaml
---
id: qa-<feature>
prd: docs/prd-<feature>.md
generated: YYYY-MM-DD
timeout: 30000
---
```

```markdown
# QA Acceptance Runbook: <Feature Name>

## Preconditions
- [Setup requirements]

## Test Cases

### TC-001: <Scenario Name> [P0 - Critical]
**Traces to:** REQ-001

Steps:
1. Open <page>.
2. Click `<button label>`.
3. Fill `<field label>` with `<value>`.

Assertions:
- VERIFY text "<expected>" visible in element matching "<description>"
- VERIFY element matching "<description>" is not visible

---

### TC-002: <Negative Scenario> [P0 - Critical]
**Traces to:** REQ-001 (edge case)
...

## Coverage Matrix
| Requirement | Test Cases | Status |
|-------------|-----------|--------|
| REQ-001     | TC-001, TC-002 | Covered |
| REQ-002     | TC-003 | Covered |
| REQ-003     | -- | UNTESTABLE (flagged) |
```

### Design Decisions

- **Traceability links**: Every TC traces to a REQ. Coverage matrix is the
  bidirectional check in human-readable form.
- **Spec guardian**: No implementation details. Describes what the user sees,
  never how the system works.
- **Priority tags**: Match PRD requirement priorities so agent-browser can
  run P0 first.

---

## Skill 4: QA Execution (`skills/qa-acceptance/`)

### Purpose

Execute a QA runbook against a running app using agent-browser. Takes a QA
runbook path, runs each test case, reports pass/fail results.

### Execution Process

1. **Parse QA runbook** — Read YAML frontmatter (base_url, auth, timeout)
   and all test cases
2. **Verify app is running** — Check base_url is reachable before starting
3. **Execute test cases in priority order** — P0 first, then P1, P2
4. **For each test case**:
   - Open agent-browser to starting page
   - Execute steps via agent-browser commands (open, snapshot, click, fill,
     select, etc.)
   - Snapshot after each interaction to verify state
   - Run assertions by inspecting snapshot for expected text/elements
   - On pass: record PASS, move to next
   - On fail: capture screenshot, record FAIL with details, continue
5. **Produce results report** — Markdown table of all TCs with pass/fail,
   detailed failure sections with screenshots
6. **Save results** to `docs/qa/qa-<feature>-results.md`
7. **Return summary** — pass/fail count, failed TC list

### Results Format

```markdown
# QA Execution Results: <Feature Name>

**Date:** YYYY-MM-DD
**Runbook:** docs/qa/qa-<feature>.md
**Results:** X/Y passed

| TC | Name | Priority | Result | Notes |
|----|------|----------|--------|-------|
| TC-001 | Add Item to Cart | P0 | PASS | |
| TC-002 | Invalid Payment | P0 | FAIL | Expected error not found |

## Failed Test Details
### TC-002: Invalid Payment
**Step failed:** Step 6 - Click `Place Order`
**Expected:** Inline error message explains payment failure
**Actual:** Page redirected to confirmation
**Screenshot:** .claude/qa-screenshots/TC-002.png
```

### Design Decisions

- **Priority ordering**: P0 first — find critical failures fast
- **Continue on failure**: Run all tests, report all results
- **Screenshots only on failure**: No overhead during passing tests
- **No auto-fix**: This skill only reports. Fix loops are handled by the
  master orchestration skill in Phase 4.

---

## Manifest Updates

Add new skills to `manifests/skills.tsv`:

```
claude    skills/prd-interview         prd-interview
claude    skills/prd-challenge         prd-challenge
claude    skills/qa-runbook-gen        qa-runbook-gen
claude    skills/qa-acceptance         qa-acceptance
```

## Testing Strategy

Each skill is tested by running it on a real feature in a target project repo:
1. Run PRD interview for a small feature
2. Run challenge round on the resulting PRD
3. Run QA generation on the hardened PRD
4. Run QA execution on the generated runbook (requires running app)

Skills 1-3 can be tested without a running app. Skill 4 requires the
target app to be running.

---

*Design approved: 2026-02-26*
