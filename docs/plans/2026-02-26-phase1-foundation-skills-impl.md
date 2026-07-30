# Phase 1 Foundation Skills Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create 4 reusable Claude Code skills (PRD interview, PRD challenge round, QA runbook generation, QA execution) in the dark-factory repo.

**Architecture:** Pure SKILL.md skills with reference files for 3 skills, plus SKILL.md with a shell script for the challenge round (Codex CLI orchestration). All skills are synced to `~/.claude/skills/` via the existing manifest-based sync.

**Tech Stack:** Markdown (SKILL.md), Bash (Codex orchestration script), Claude Code skills system, Codex CLI

---

### Task 1: Create PRD Interview Skill — Reference Files

**Files:**
- Create: `skills/prd-interview/references/prd-template.md`
- Create: `skills/prd-interview/references/quality-gate-checklist.md`

**Step 1: Create the PRD template reference file**

```bash
mkdir -p skills/prd-interview/references
```

Write `skills/prd-interview/references/prd-template.md`:

```markdown
# PRD: <Feature Name>

**Status:** Draft | Hardened | Approved
**Date:** YYYY-MM-DD
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

Requirements:
1. [Atomic, verifiable predicate — one testable behavior per item]
2. [...]

Acceptance:
- [Testable assertion a QA agent can verify through the UI]
- [...]

---

### REQ-002: <Requirement Name>

**Priority:** P0 | P1 | P2

Requirements:
1. [...]

Acceptance:
- [...]

---

[Repeat for each requirement]

## Negative Requirements

- [What must NOT happen — explicit constraints on behavior]
- [Example: "Deleting a team must NOT delete the team's projects"]

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

## Glossary

| Term | Definition |
|------|-----------|
| [Ambiguous term] | [Precise definition in this context] |

## Constraints & Assumptions

- [Technical constraints (e.g., must work with existing auth system)]
- [Deployment assumptions (e.g., feature flag rollout)]
- [Dependencies on other features or services]
```

**Step 2: Create the quality gate checklist reference file**

Write `skills/prd-interview/references/quality-gate-checklist.md`:

```markdown
# PRD Quality Gate Checklist

All 5 items must pass before the PRD status changes from "Draft" to "Hardened".

## The Checklist

- [ ] **Atomic acceptance criteria**: Every acceptance criterion is a single,
  verifiable predicate (not prose). Bad: "The form should work well."
  Good: "Submitting with an empty email field shows inline error 'Email is required'."

- [ ] **Negative/edge cases per flow**: Every user flow has at least one
  negative or edge case documented. If a flow has no edge cases listed,
  the interviewer must probe: "What happens if the user does X wrong?"

- [ ] **Measurable NFRs**: Non-functional requirements have numeric thresholds
  and a measurement method. Bad: "Should be fast." Good: "< 200ms p95
  measured by Lighthouse."

- [ ] **Glossary for ambiguous terms**: Any domain-specific or overloaded term
  has a definition in the Glossary section. If there are no ambiguous terms,
  the Glossary section should say "No ambiguous terms identified."

- [ ] **Explicit scope boundaries**: The "Out of Scope" section is non-empty
  and lists specific exclusions. Every PRD must say what it does NOT include.

## How to Run the Gate

After drafting the PRD, evaluate each item:
1. Read through every acceptance criterion — is each one a single testable predicate?
2. For each user flow, check the Edge Cases table — is there at least one entry?
3. Check the NFR table — does every row have a numeric threshold and measurement?
4. Check the Glossary — are all potentially ambiguous terms defined?
5. Check Out of Scope — is it non-empty with specific exclusions?

If any item fails, tell the user which item failed and what's missing.
Loop back to the relevant interview topic to fill the gap.
```

**Step 3: Commit**

```bash
git add skills/prd-interview/references/prd-template.md skills/prd-interview/references/quality-gate-checklist.md
git commit -m "feat: add PRD template and quality gate checklist references"
```

---

### Task 2: Create PRD Interview Skill — SKILL.md

**Files:**
- Create: `skills/prd-interview/SKILL.md`

**Step 1: Write the SKILL.md**

Write `skills/prd-interview/SKILL.md`:

```markdown
---
name: prd-interview
description: "Interactive PRD authoring through structured interview. Use when starting a new feature, writing requirements, creating a PRD, or when the user says 'let's define what to build'. Guides the user through requirements gathering with probing questions, produces a structured PRD document, and enforces a hard quality gate before the PRD is accepted."
---

# PRD Interview

Conduct a structured interview to produce a PRD (Product Requirements Document)
that passes a hard quality gate. The PRD captures what to build, not how.

## Before Starting

1. Read the project's CLAUDE.md, README, and recent git log (last 10 commits)
2. Scan `docs/` for existing PRDs to understand naming and conventions
3. Note the project's tech stack and existing patterns

## Interview Process

### Phase 1: Open Exploration

Start with a single open question:

> "What are you building? What problem does it solve for the user?"

Listen. Do not jump to requirements yet. Understand the motivation and context.
Follow up with at most 2 clarifying questions before moving to structured probing.

### Phase 2: Structured Probing

Ask questions **one at a time**. Prefer multiple choice when possible.
Cover these topics in order:

1. **User flows** — "Walk me through the happy path. What does the user do
   step by step?" Then for each flow: "What could go wrong here?"
2. **Negative requirements** — "What should this feature explicitly NOT do?
   Any existing behavior that must not change?"
3. **Scope boundaries** — "What's out of scope for this feature? What are
   you deliberately not building?"
4. **Non-functional requirements** — "Any performance, accessibility, or
   security requirements? What are the thresholds?"
5. **Ambiguous terms** — "Are there any terms here that could mean different
   things to different people?"
6. **Constraints** — "Any technical constraints, dependencies, or deployment
   considerations?"

Skip topics the user already covered in Phase 1. Do not re-ask what's
already clear.

### Phase 3: Draft PRD

When you have enough information:

1. Read `references/prd-template.md` for the exact output format
2. Write the PRD following the template structure
3. Present the full PRD to the user: "Here's the draft PRD. Please review
   each section."

Save to `docs/prd-<feature-slug>.md` where `<feature-slug>` is a lowercase
hyphenated name derived from the feature (e.g., `docs/prd-team-invitations.md`).

### Phase 4: Quality Gate

Read `references/quality-gate-checklist.md` and evaluate the draft against
all 5 items.

- If all pass: set Status to "Hardened" and tell the user the PRD is ready
  for the challenge round.
- If any fail: tell the user which items failed and what's missing. Ask the
  specific questions needed to fill the gaps. Loop back to Phase 2 for
  those topics only.

### Phase 5: Output

1. Save the final PRD to `docs/prd-<feature-slug>.md`
2. Commit: `git add docs/prd-<feature-slug>.md && git commit -m "docs: add PRD for <feature>"`
3. Report: "PRD saved to `docs/prd-<feature-slug>.md` with status Hardened.
   Ready for the PRD challenge round."

## Key Rules

- **One question at a time.** Never ask multiple questions in one message.
- **Multiple choice preferred.** When there are a few obvious options, present
  them as choices rather than asking open-ended.
- **Do not suggest implementation.** The PRD is about requirements, not
  architecture or code. Never mention specific technologies, libraries,
  or design patterns in the PRD.
- **Probe for negatives.** Users rarely volunteer what should NOT happen.
  Always ask.
- **Measurable over qualitative.** "Fast" is not a requirement. "< 200ms p95"
  is a requirement.
```

**Step 2: Verify the skill structure**

```bash
head -5 skills/prd-interview/SKILL.md
ls -R skills/prd-interview/
```

Expected:
```
---
name: prd-interview
description: "Interactive PRD authoring through structured interview..."
---

skills/prd-interview/:
SKILL.md  references/

skills/prd-interview/references/:
prd-template.md  quality-gate-checklist.md
```

**Step 3: Commit**

```bash
git add skills/prd-interview/SKILL.md
git commit -m "feat: add PRD interview skill"
```

---

### Task 3: Create PRD Challenge Round — Codex Review Script

**Files:**
- Create: `skills/prd-challenge/scripts/run_codex_prd_review.sh`

**Step 1: Write the Codex review script**

This script follows the same pattern as `skills/review-prd-with-codex/scripts/review_prd.sh`
but is tailored for the challenge round (structured finding output, no persisted state file).

```bash
mkdir -p skills/prd-challenge/scripts
```

Write `skills/prd-challenge/scripts/run_codex_prd_review.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_prd_review.sh <prd-path> <output-path>
# Runs a Codex CLI review of a PRD and writes findings to the output path.
# Designed for the PRD challenge round — produces structured findings
# compatible with the synthesis step.

if [[ $# -lt 2 ]]; then
  echo "Usage: run_codex_prd_review.sh <prd-path> <output-path>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

prd_path="$1"
out_path="$2"

if [[ "$prd_path" != /* ]]; then
  prd_path="$repo_root/$prd_path"
fi

if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi

rel_path="${prd_path#$repo_root/}"

prompt="$(cat <<'PROMPT'
You are an independent reviewer examining a PRD (Product Requirements Document).
Your goal is to find gaps, contradictions, and ambiguities that the PRD author
may have missed.

Review the PRD and produce findings in this exact format:

## Findings

### [SEVERITY]: [One-line finding title]
**Requirement:** [Which REQ-xxx or section this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix or question to resolve it]

---

Severity levels:
- **Critical**: Blocks implementation or causes incorrect behavior
- **High**: Significant gap that will likely cause rework
- **Medium**: Improvement that would strengthen the PRD
- **Low**: Minor suggestion or style issue

Focus on:
- Missing edge cases and error states
- Contradictory or ambiguous requirements
- Acceptance criteria that are not testable
- Scope gaps (mentioned in requirements but not in scope, or vice versa)
- Non-functional requirements that lack measurable thresholds

Do NOT suggest implementation approaches or architectural decisions.
Do NOT add new features — only identify gaps in existing requirements.
PROMPT
)"

prompt="$prompt

PRD file: $rel_path

$(cat "$prd_path")"

{
  echo "# Codex PRD Challenge Review"
  echo
  echo "- Source: \`$rel_path\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (model diversity)"
  echo
} >"$out_path"

codex exec \
  --skip-git-repo-check \
  --sandbox read-only \
  --config model_reasoning_effort=high \
  -C "$repo_root" \
  "$prompt" \
  >>"$out_path" \
  2>/dev/null

echo "Codex challenge review written to: $out_path"
```

**Step 2: Make script executable and verify syntax**

```bash
chmod +x skills/prd-challenge/scripts/run_codex_prd_review.sh
bash -n skills/prd-challenge/scripts/run_codex_prd_review.sh
```

Expected: no output (clean syntax check)

**Step 3: Commit**

```bash
git add skills/prd-challenge/scripts/run_codex_prd_review.sh
git commit -m "feat: add Codex PRD review script for challenge round"
```

---

### Task 4: Create PRD Challenge Round — Reference Files

**Files:**
- Create: `skills/prd-challenge/references/personas.md`
- Create: `skills/prd-challenge/references/synthesis-prompt.md`

**Step 1: Write the personas reference file**

Write `skills/prd-challenge/references/personas.md`:

```markdown
# PRD Challenge Round Personas

Each persona is a system prompt for a Claude sub-agent dispatched via the
Task tool. All receive the PRD as input. Output format is identical across
personas: markdown findings with severity tags.

## Persona 1: Skeptical User Advocate

```
You are reviewing a PRD as a skeptical user advocate. Your job is to find
gaps from the USER's perspective — not the developer's.

Focus areas:
- What happens when the user does something unexpected?
- Are there confusing flows or unclear UI states?
- What error states are missing? What does the user see when things fail?
- Are there empty states (first-time use, no data yet)?
- Are there accessibility concerns (keyboard nav, screen readers, color contrast)?
- Would a non-technical user understand every flow described here?

Do NOT comment on implementation feasibility or architecture.
Do NOT suggest new features — only identify gaps in what's already described.

Output your findings in this format:

### [SEVERITY]: [One-line finding title]
**Requirement:** [Which REQ-xxx or section]
**Issue:** [2-3 sentences]
**Suggestion:** [Concrete fix or question]

Severity: Critical, High, Medium, Low
```

## Persona 2: Technical Feasibility Reviewer

```
You are reviewing a PRD as a technical feasibility reviewer. You have access
to the project's codebase. Your job is to find requirements that are
underspecified, unrealistic, or likely to cause integration pain.

Focus areas:
- Are there requirements that conflict with existing code patterns?
- Are there data model implications not mentioned in the PRD?
- Are there requirements that assume capabilities the codebase doesn't have?
- Are there API contracts or integration points left underspecified?
- Are there performance implications of the proposed requirements?
- Are there migration or backwards-compatibility concerns?

Read the codebase to ground your analysis. Reference specific files and
patterns you find.

Do NOT suggest alternative architectures — only identify specification gaps.

Output your findings in this format:

### [SEVERITY]: [One-line finding title]
**Requirement:** [Which REQ-xxx or section]
**Issue:** [2-3 sentences]
**Suggestion:** [Concrete fix or question]

Severity: Critical, High, Medium, Low
```

## Persona 3: Scope & Complexity Challenger

```
You are reviewing a PRD as a scope and complexity challenger. Your job is to
find hidden complexity, unstated assumptions, and requirements that could be
cut without losing the core value.

Focus areas:
- What requirements use simple language but hide significant complexity?
- What assumptions are unstated? (e.g., "users can..." — can they really?)
- Which requirements could be deferred to a later iteration?
- Are there YAGNI violations — features included "just in case"?
- Is the scope creeping beyond the stated purpose?
- Are there requirements that duplicate existing functionality?

Be aggressive about questioning necessity. The goal is a tight, focused PRD.

Do NOT suggest new features or scope expansion.

Output your findings in this format:

### [SEVERITY]: [One-line finding title]
**Requirement:** [Which REQ-xxx or section]
**Issue:** [2-3 sentences]
**Suggestion:** [Concrete fix or question]

Severity: Critical, High, Medium, Low
```
```

**Step 2: Write the synthesis prompt reference file**

Write `skills/prd-challenge/references/synthesis-prompt.md`:

```markdown
# Challenge Round Synthesis Prompt

After all 4 reviewers complete, Claude synthesizes findings into a single
prioritized list.

## Synthesis Instructions

Read all 4 review outputs (3 Claude personas + 1 Codex). Produce a unified
findings list:

1. **Deduplicate**: If multiple reviewers raised the same concern, merge into
   one finding. Note which reviewers flagged it (higher confidence).

2. **Prioritize by severity**:
   - **Critical**: Listed first. User MUST address before proceeding.
   - **High**: Listed second. User SHOULD address.
   - **Medium**: Listed for reference. User MAY address.
   - **Low**: Listed for reference. Informational.

3. **Tag source**: Each finding shows which reviewer(s) raised it:
   - `[User Advocate]`, `[Tech Feasibility]`, `[Scope Challenger]`, `[Codex]`
   - Findings from multiple reviewers: `[User Advocate + Codex]`

4. **Format**:

```
## Challenge Round Findings

### Critical

#### 1. [Finding title] [User Advocate + Tech Feasibility]
**Requirement:** REQ-xxx
**Issue:** [Merged description from both reviewers]
**Question for product owner:** [Specific question to resolve this]

---

### High

#### 2. [Finding title] [Codex]
**Requirement:** REQ-xxx
**Issue:** [Description]
**Question for product owner:** [Specific question]

---

### Medium (for reference)

#### 3. [Finding title] [Scope Challenger]
...

### Low (for reference)

#### 4. [Finding title] [User Advocate]
...
```

5. **Summary line**: End with a count:
   "X Critical, Y High, Z Medium, W Low findings. Please address the
   Critical and High items."
```

**Step 3: Commit**

```bash
git add skills/prd-challenge/references/personas.md skills/prd-challenge/references/synthesis-prompt.md
git commit -m "feat: add challenge round personas and synthesis prompt"
```

---

### Task 5: Create PRD Challenge Round — SKILL.md

**Files:**
- Create: `skills/prd-challenge/SKILL.md`

**Step 1: Write the SKILL.md**

Write `skills/prd-challenge/SKILL.md`:

```markdown
---
name: prd-challenge
description: "Multi-model PRD challenge round with persona-based review. Use after a PRD passes its quality gate, when the user wants stress-testing of requirements, or when asked to 'challenge this PRD'. Launches 3 Claude persona sub-agents + 1 Codex review in parallel, synthesizes findings into a prioritized question list."
---

# PRD Challenge Round

Stress-test a hardened PRD with 4 parallel reviewers to surface gaps the
author missed. Three Claude personas provide perspective diversity; one Codex
review provides model diversity.

## Prerequisites

- A PRD file that has passed the quality gate (Status: Hardened)
- Codex CLI installed and authenticated (`codex --version` succeeds)

## Workflow

### Step 1: Confirm the PRD

Ask the user to confirm the PRD path. If the PRD status is still "Draft",
warn that it should pass the quality gate first (but do not block — the user
may override).

### Step 2: Launch 4 Parallel Reviews

Read `references/personas.md` for the 3 persona system prompts.

Launch all 4 reviews simultaneously:

**Reviews 1-3 (Claude sub-agents):** Use the Task tool to dispatch 3
sub-agents in a single message (all 3 Task calls in one response). Each
sub-agent receives:
- Its persona system prompt from `references/personas.md`
- The full PRD content
- For the Technical Feasibility Reviewer: instruct it to explore the codebase

Each sub-agent returns markdown findings.

**Review 4 (Codex CLI):** In the same message as the 3 Task calls, also
launch a Bash command:

```bash
bash .claude/skills/prd-challenge/scripts/run_codex_prd_review.sh \
  "<prd-path>" \
  "/tmp/codex-challenge-review.md"
```

This runs Codex in parallel with the Claude sub-agents.

### Step 3: Synthesize Findings

After all 4 reviews complete:

1. Read all 4 outputs
2. Read `references/synthesis-prompt.md` for synthesis instructions
3. Produce a single unified findings list following the synthesis format
4. Present to the user

### Step 4: User Addresses Findings

Present Critical and High findings as questions for the user. The user
updates the PRD based on their answers.

### Step 5: Lightweight Recheck

After the user addresses findings and updates the PRD, run a single
recheck (NOT a full challenge round):

Read the updated PRD and the previous findings list. Ask yourself:
"Given the updates, are there any remaining Critical or High concerns
that were not adequately addressed?"

- If clean: "Challenge round complete. PRD is ready for QA runbook
  generation."
- If new issues: present them to the user (max 2 total rounds)
- User can override: "good enough, move on" at any time

### Step 6: Output

Report the final status:
- "Challenge round complete. N findings addressed. PRD at `<path>` is
  ready for the next stage."

## Notes

- Personas are gap-finders, not scope-expanders. They should never suggest
  new features.
- Codex provides model diversity (GPT vs Claude). It may catch blind spots
  all Claude personas share.
- The recheck is lightweight (single Claude call, not 4 parallel reviews).
- Max 2 rounds total. Do not loop indefinitely.
```

**Step 2: Verify the skill structure**

```bash
ls -R skills/prd-challenge/
```

Expected:
```
skills/prd-challenge/:
SKILL.md  references/  scripts/

skills/prd-challenge/references/:
personas.md  synthesis-prompt.md

skills/prd-challenge/scripts/:
run_codex_prd_review.sh
```

**Step 3: Commit**

```bash
git add skills/prd-challenge/SKILL.md
git commit -m "feat: add PRD challenge round skill"
```

---

### Task 6: Create QA Runbook Generation Skill — Reference Files

**Files:**
- Create: `skills/qa-runbook-gen/references/runbook-template.md`
- Create: `skills/qa-runbook-gen/references/spec-guardian-rules.md`

**Step 1: Write the runbook template reference file**

```bash
mkdir -p skills/qa-runbook-gen/references
```

Write `skills/qa-runbook-gen/references/runbook-template.md`:

````markdown
# QA Runbook Template

Every generated QA runbook must follow this exact structure.

## YAML Frontmatter

```yaml
---
id: qa-<feature-slug>
prd: docs/prd-<feature-slug>.md
generated: YYYY-MM-DD
timeout: 30000
---
```

- `id`: matches the PRD feature slug with `qa-` prefix
- `prd`: relative path to the source PRD
- `generated`: date the runbook was generated
- `timeout`: default timeout in milliseconds for agent-browser waits

## Document Structure

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
3. [...]

Assertions:
- VERIFY text "<expected text>" visible in element matching "<UI description>"
- VERIFY element matching "<UI description>" is visible
- VERIFY element matching "<UI description>" is not visible
- VERIFY current URL contains "<path fragment>"

---

### TC-002: <Negative Scenario Name> [P0 - Critical]

**Traces to:** REQ-001 (edge case)

Steps:
1. [Setup steps to reach the error condition]
2. [Action that should fail]

Assertions:
- VERIFY text "<error message>" visible in element matching "<UI description>"
- VERIFY [previous state is preserved]

---

[Continue for all test cases]

## Coverage Matrix

| Requirement | Test Cases | Status |
|-------------|-----------|--------|
| REQ-001 | TC-001, TC-002 | Covered |
| REQ-002 | TC-003 | Covered |
| REQ-003 | -- | UNTESTABLE: [reason] |
```

## Rules for Steps

- Steps describe what the USER does, never what the system does internally
- Use UI labels and visible text, not CSS selectors or test IDs
- Use `data-testid` hints only in parentheses when available:
  `Click "Add to Cart" (data-testid: "add-to-cart-btn")`
- Each step is a single atomic action (click, fill, navigate, etc.)
- Navigation steps start with "Open" or "Navigate to"
- Fill steps use the format: `Fill "<field label>" with "<value>"`
- Click steps use the format: `Click "<button/link label>"`

## Rules for Assertions

- Every assertion starts with `VERIFY`
- Assertions describe visible UI state, not internal state
- Use "element matching" followed by a UI description (not a selector)
- Separate assertions from steps — never embed assertions in steps
- Each test case must have at least one assertion

## Priority Tags

- `[P0 - Critical]` — Core user flow, must pass for feature to ship
- `[P1 - High]` — Important edge case or secondary flow
- `[P2 - Medium]` — Nice-to-have coverage, non-blocking
````

**Step 2: Write the spec guardian rules reference file**

Write `skills/qa-runbook-gen/references/spec-guardian-rules.md`:

```markdown
# Spec Guardian Rules

The QA runbook must describe what the USER sees and does. It must never
reference internal implementation details. These rules are enforced during
generation and checked during multi-model validation.

## Forbidden Content

The following must NOT appear in any test case:

1. **Code identifiers**: class names, function names, variable names,
   module paths (e.g., `UserService`, `handleSubmit`, `src/components/`)

2. **API endpoints**: URL paths that are not user-visible
   (e.g., `/api/v1/users`, `POST /auth/login`)

3. **Database references**: table names, column names, SQL
   (e.g., `users table`, `org_id column`, `SELECT * FROM`)

4. **Internal architecture**: references to queues, caches, workers,
   middleware, hooks, state management internals

5. **HTTP details**: status codes, headers, request/response bodies
   (e.g., "returns 200", "Authorization header")

6. **Test framework internals**: test IDs used as primary identifiers
   (data-testid is allowed only as a parenthetical hint, not as the
   primary way to identify an element)

## Allowed Content

- UI element labels ("Add to Cart" button, "Email" field)
- Visible text on the page
- User-facing URLs (the URL bar content, not API routes)
- Page titles and headings
- Error messages as displayed to the user
- data-testid hints in parentheses as supplementary info

## Self-Correction Process

If any test case violates these rules:
1. Identify the violation
2. Rewrite the step or assertion using only user-visible language
3. If the requirement can only be tested through internal inspection
   (e.g., "data must be encrypted at rest"), flag it as UNTESTABLE
   in the coverage matrix

## Examples

**Bad:** `VERIFY response status is 200`
**Good:** `VERIFY text "Profile updated" visible in element matching "success notification"`

**Bad:** `Call POST /api/users with payload {...}`
**Good:** `Click "Create Account"`

**Bad:** `Check that UserService.create() was called`
**Good:** `VERIFY text "Welcome, Jane" visible in element matching "header greeting"`
```

**Step 3: Commit**

```bash
git add skills/qa-runbook-gen/references/runbook-template.md skills/qa-runbook-gen/references/spec-guardian-rules.md
git commit -m "feat: add QA runbook template and spec guardian rules"
```

---

### Task 7: Create QA Runbook Generation Skill — SKILL.md

**Files:**
- Create: `skills/qa-runbook-gen/SKILL.md`

**Step 1: Write the SKILL.md**

Write `skills/qa-runbook-gen/SKILL.md`:

```markdown
---
name: qa-runbook-gen
description: "Machine-generate a QA acceptance runbook from a hardened PRD. Use after the PRD challenge round completes, when the user asks to 'generate QA tests', or when a PRD is ready for QA runbook generation. Produces a structured runbook with YAML frontmatter, traceability links, and a coverage matrix. No user interaction required — runs autonomously."
---

# QA Runbook Generation

Generate a QA acceptance runbook from a hardened PRD. The runbook contains
UI-level test scenarios that agent-browser can execute. No user interaction
is needed — this skill runs autonomously.

## Prerequisites

- A PRD file with Status: Hardened or Approved
- The PRD must have passed its quality gate (acceptance criteria are testable)

## Workflow

### Step 1: Read the PRD

Read the PRD file. Extract:
- All requirements (REQ-xxx) with their acceptance criteria
- All edge cases from the Edge Cases table
- All negative requirements
- The feature name and slug for output naming

### Step 2: Generate Test Cases

Read `references/runbook-template.md` for the exact output format.

For each requirement:
1. Write a happy path test case covering the core acceptance criteria
2. Write edge case / negative test cases from the Edge Cases and Negative
   Requirements sections
3. Assign the same priority as the source requirement
4. Add a `Traces to: REQ-xxx` link

Rules:
- Steps are natural language describing user actions
- Assertions use the `VERIFY` format from the template
- Each test case has a unique ID (TC-001, TC-002, ...)
- Test case names are descriptive (not "Test 1")

### Step 3: Add Frontmatter

Add YAML frontmatter with:
- `id`: `qa-<feature-slug>`
- `prd`: relative path to the source PRD
- `generated`: today's date
- `timeout`: 30000 (default)

### Step 4: Bidirectional Coverage Check

Build the coverage matrix:
1. For every PRD requirement, verify at least one TC exists → if not,
   generate it
2. For every TC, verify it traces to a PRD requirement → if not, the TC
   is scope creep and should be removed

If any requirement cannot be expressed as a UI test (e.g., "data encrypted
at rest"), mark it as UNTESTABLE with a reason in the coverage matrix.

### Step 5: Spec Guardian Check

Read `references/spec-guardian-rules.md`.

Scan every test case for forbidden content:
- Code identifiers, API endpoints, database references
- Internal architecture, HTTP details, test framework internals

If violations are found, rewrite the offending steps/assertions using only
user-visible language. If a step cannot be rewritten without implementation
details, flag the requirement as UNTESTABLE.

Max 2 self-correction rounds.

### Step 6: Output

1. Save to `docs/qa/qa-<feature-slug>.md`
   (create the `docs/qa/` directory if it doesn't exist)
2. Report: "QA runbook generated at `docs/qa/qa-<feature-slug>.md`
   with X test cases covering Y/Z requirements.
   [List any UNTESTABLE requirements if applicable]"

## Notes

- This skill runs autonomously — do not ask the user questions during
  generation. The PRD is the source of truth.
- If the PRD has ambiguous requirements that can't be turned into tests,
  flag them as UNTESTABLE rather than guessing intent.
- The coverage matrix is the key quality artifact — it proves bidirectional
  traceability between requirements and tests.
```

**Step 2: Verify the skill structure**

```bash
ls -R skills/qa-runbook-gen/
```

Expected:
```
skills/qa-runbook-gen/:
SKILL.md  references/

skills/qa-runbook-gen/references/:
runbook-template.md  spec-guardian-rules.md
```

**Step 3: Commit**

```bash
git add skills/qa-runbook-gen/SKILL.md
git commit -m "feat: add QA runbook generation skill"
```

---

### Task 8: Create QA Execution Skill

**Files:**
- Create: `skills/qa-acceptance/SKILL.md`

**Step 1: Write the SKILL.md**

```bash
mkdir -p skills/qa-acceptance
```

Write `skills/qa-acceptance/SKILL.md`:

```markdown
---
name: qa-acceptance
description: "Execute a QA acceptance runbook against a running app using agent-browser. Use when QA tests need to be run, when the user says 'run the QA runbook', or after implementation is complete and acceptance testing is needed. Reads a QA runbook, executes each test case via browser automation, and produces a pass/fail results report."
---

# QA Acceptance Execution

Execute a QA acceptance runbook against a running application using
agent-browser. Runs each test case, captures results, and produces a
structured report.

## Prerequisites

- A QA runbook file (generated by qa-runbook-gen or manually authored)
- The target application must be running and accessible
- agent-browser must be available (`agent-browser --version`)

## Workflow

### Step 1: Parse the Runbook

Read the QA runbook file. Extract:
- YAML frontmatter (timeout, any auth config)
- All test cases with their steps, assertions, and priorities
- Sort test cases by priority: P0 first, then P1, then P2

### Step 2: Verify App Is Running

Before executing any tests, check that the base URL is reachable:

```bash
agent-browser open <base-url> && agent-browser wait --load networkidle && agent-browser snapshot -i
```

If the app is not reachable, stop and report: "Cannot reach <base-url>.
Is the application running?"

### Step 3: Execute Test Cases

For each test case (in priority order):

1. **Navigate** to the starting page for the test
2. **Execute each step** by translating natural language to agent-browser
   commands:
   - "Open <page>" → `agent-browser open <url>`
   - "Click '<label>'" → snapshot to find the element, then
     `agent-browser click @ref`
   - "Fill '<field>' with '<value>'" → snapshot to find the field, then
     `agent-browser fill @ref "<value>"`
   - "Select '<option>'" → `agent-browser select @ref "<option>"`
3. **Re-snapshot** after every interaction that changes the page
4. **Run assertions** by inspecting the snapshot:
   - "VERIFY text '<text>' visible" → check snapshot output for the text
   - "VERIFY element matching '<desc>' is visible/not visible" → check
     snapshot for matching element
   - "VERIFY current URL contains '<path>'" → `agent-browser get url`
5. **Record result**:
   - All assertions pass → PASS
   - Any assertion fails → FAIL, capture screenshot:
     `agent-browser screenshot .claude/qa-screenshots/TC-xxx.png`

**Continue on failure.** Do not stop at the first failing test. Run all
test cases and report all results.

### Step 4: Produce Results Report

Write a results report to `docs/qa/qa-<feature>-results.md`:

```markdown
# QA Execution Results: <Feature Name>

**Date:** YYYY-MM-DD
**Runbook:** <path to runbook>
**Results:** X/Y passed

| TC | Name | Priority | Result | Notes |
|----|------|----------|--------|-------|
| TC-001 | <name> | P0 | PASS | |
| TC-002 | <name> | P0 | FAIL | <one-line failure reason> |
| ... | ... | ... | ... | ... |

## Failed Test Details

### TC-002: <name>
**Step failed:** Step N — <step description>
**Expected:** <what the assertion expected>
**Actual:** <what was observed>
**Screenshot:** .claude/qa-screenshots/TC-002.png
```

### Step 5: Report Summary

After writing the results file, report:
- "QA execution complete: X/Y tests passed."
- List all failing test cases with one-line reasons
- Path to the full results report

## Key Rules

- **Priority order**: Always run P0 tests first
- **Continue on failure**: Run ALL tests, never stop early
- **Screenshots on failure only**: Do not screenshot passing tests
- **Fresh snapshots**: Always re-snapshot after interactions that change
  the page (clicks, form fills, navigations)
- **No auto-fix**: This skill only reports results. It does not attempt
  to fix failures. The orchestration layer handles fix loops.
```

**Step 2: Verify the skill structure**

```bash
ls -R skills/qa-acceptance/
```

Expected:
```
skills/qa-acceptance/:
SKILL.md
```

**Step 3: Commit**

```bash
git add skills/qa-acceptance/SKILL.md
git commit -m "feat: add QA acceptance execution skill"
```

---

### Task 9: Update Manifest and Sync Infrastructure

**Files:**
- Modify: `manifests/skills.tsv`
- Modify: `Justfile`

**Step 1: Add new skills to the manifest**

Append to `manifests/skills.tsv` (after the existing entries):

```
claude	skills/prd-interview	prd-interview
claude	skills/prd-challenge	prd-challenge
claude	skills/qa-runbook-gen	qa-runbook-gen
claude	skills/qa-acceptance	qa-acceptance
```

**Step 2: Add check targets for the new script**

Add to the `check-shell` recipe in `Justfile`:

```
	bash -n skills/prd-challenge/scripts/run_codex_prd_review.sh
```

**Step 3: Run checks**

```bash
just check
```

Expected: all checks pass (shell syntax, python compile)

**Step 4: Commit**

```bash
git add manifests/skills.tsv Justfile
git commit -m "feat: add Phase 1 skills to manifest and Justfile checks"
```

---

### Task 10: Sync Skills to Global and Verify

**Step 1: Dry-run sync**

```bash
just sync-to-global-dry
```

Expected: shows the 4 new skill directories would be copied to `~/.claude/skills/`

**Step 2: Run actual sync**

```bash
just sync-to-global
```

Expected: skills copied successfully

**Step 3: Verify skills are in place**

```bash
ls ~/.claude/skills/prd-interview/SKILL.md
ls ~/.claude/skills/prd-challenge/SKILL.md
ls ~/.claude/skills/qa-runbook-gen/SKILL.md
ls ~/.claude/skills/qa-acceptance/SKILL.md
```

Expected: all 4 files exist

**Step 4: Commit and push**

```bash
git push origin main
```

Expected: all Phase 1 skill commits pushed to remote

---

*Plan created: 2026-02-26*
*Execution method: subagent-driven (this session)*
