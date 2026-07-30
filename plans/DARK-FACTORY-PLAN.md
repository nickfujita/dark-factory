# Dark Factory Implementation Plan

> Goal: Evolve from Level 3 (human-in-loop management) toward Level 4/5
> (autonomous operation / dark factory) for feature development across all
> projects. This repo (`dark-factory`) contains the cross-project workflow
> skills and orchestration tooling, with copy-based sync into global native
> skill folders on each VM.

## Table of Contents

1. [Background & Vision](#1-background--vision)
2. [The Five Levels Framework](#2-the-five-levels-framework)
3. [Current State](#3-current-state)
4. [Target Architecture](#4-target-architecture)
5. [QA Document Scope (What the Product Owner Sees)](#5-qa-document-scope)
6. [The Black Box (What the Product Owner Does Not See)](#6-the-black-box)
7. [Gap Analysis](#7-gap-analysis)
8. [Implementation Plan](#8-implementation-plan)
9. [Key Risks & Mitigations](#9-key-risks--mitigations)
10. [Research Sources](#10-research-sources)

---

## 1. Background & Vision

### The Dark Factory Concept

Borrowed from manufacturing, where robots work in unlit facilities because they
don't need to see. Applied to software: **specifications go in, tested software
comes out.** The human defines *what should exist*; machines handle everything
between the spec and the shipping artifact.

### Our Vision

The product owner interfaces with exactly **two documents**, both created
*before any code is written*:

1. **PRD (Product Requirements Document)** -- purely product-driven and
   requirements-driven, not code-driven. Created through an interactive
   interview process where the AI acts as a consultant, asking clarifying
   questions. The PRD is accepted when it passes a hard quality gate checklist:
   - All acceptance criteria are atomic, verifiable predicates (not prose)
   - Every user flow has at least one negative/edge case
   - Non-functional requirements are stated with measurable thresholds
   - A domain glossary exists for any ambiguous terms
   - Scope boundaries are explicitly defined (what is NOT included)

2. **QA Acceptance Runbook** -- machine-generated from the hardened PRD
   *before development begins*. Documents all user-level use cases that a
   browser automation agent will execute to validate that the PRD has been
   implemented correctly. Contains only UI interactions (clicking, typing,
   navigating). No curl commands, no API probing, no security testing. The
   complete QA runbook is provided to the development agent as input — the more
   information the agent has about what "done" looks like, the more accurately
   it can implement the feature. The product owner reviews the runbook at
   sign-off but does not co-author it.

### Why QA Before Development

The QA runbook is a mechanical derivation of the PRD — for each requirement,
write the user-facing test scenario. Generating it before development:
- Validates that every PRD requirement is testable (if the machine can't write
  a concrete test, the requirement is ambiguous)
- Establishes the exact acceptance criteria agent-browser will validate
- Provides the development agent with a complete picture of "done"

The two documents validate each other bidirectionally (automated check):
- **PRD claim without a matching QA scenario** → untestable requirement (fix the
  PRD or add a test)
- **QA scenario without a matching PRD requirement** → scope creep or missing
  requirement (update the PRD)

This mirrors the ATDD (Acceptance Test Driven Development) pattern: acceptance
tests define external behavior before code exists, while TDD constrains
internal structure during implementation.

### The Planning Flow

```
┌─────────────────────────────────────────────────────────┐
│ USER IN THE LOOP                                        │
│                                                         │
│ Stage 1: PRD Interview (Claude ↔ User)                  │
│   Conversational loop until quality gate passes         │
│                                                         │
│ Stage 2: PRD Challenge Round                            │
│   3 Claude personas + Codex (parallel)                  │
│   → Synthesized question list → User addresses          │
│   → Lightweight recheck (max 2 rounds)                  │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ MACHINE RUNS (no user interaction)                      │
│                                                         │
│ Stage 3: QA Runbook Generation                          │
│   AI writes runbook from hardened PRD                   │
│   Bidirectional coverage + spec guardian checks         │
│                                                         │
│ Stage 4: Multi-model Validation                         │
│   Claude + Codex formal review of PRD + QA together     │
│   AI addresses Critical findings (max 2 rounds)         │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ USER SIGN-OFF                                           │
│                                                         │
│ Stage 5: Present PRD + QA runbook + validation report   │
│   → Approve → Development begins                        │
│   → Reject  → Routed back (see rejection routing)       │
└─────────────────────────────────────────────────────────┘
```

All stages complete before any code is written.

### User Touchpoints

The product owner has exactly **two planned interaction points** during planning:

1. **PRD Authoring** (Stages 1-2): Conversational — define requirements, answer
   clarifying questions from multiple models and personas.
2. **Final Sign-off** (Stage 5): Review the complete package and approve or
   reject with feedback.

Everything between (QA generation, multi-model validation) runs autonomously.

Exception touchpoints can still occur when explicitly triggered by failure or
ambiguity policies (for example: reviewer failure after retries, unresolved
semantic contradiction, or operator checkpoint prompts).

### Rejection Routing

If the user rejects at sign-off, feedback routes based on scope:

| Feedback Type | Example | Route |
|---------------|---------|-------|
| **QA-only** | "This scenario is wrong" / "missing a flow" | Update QA runbook → re-run coverage check → lightweight re-validation → present again |
| **PRD tweak** | "Change this requirement" / "misunderstood X" | Update PRD → scoped challenge round on the delta → regenerate affected QA scenarios → re-validation → present again |
| **Major scope change** | "Rethink the whole approach" | Back to Stage 1 for focused interview → full pipeline re-run |

The AI suggests a routing classification, and the user confirms the route
explicitly (QA-only / PRD tweak / major scope change) before execution.

### What Gets Black-Boxed

Everything between these two documents and the shipping artifact is
**black-boxed**: architecture, planning, implementation, code review, security
testing, automated testing. The product owner doesn't need to understand or
manage any of it.

### Auto-Generated Transparency Artifacts

The black box produces machine-generated artifacts after each pipeline run.
These are *not* documents the product owner writes -- they are transparency
outputs the system generates automatically:

- **Feature Delivery Report**: ADR summaries, tech debt delta, performance
  impact, security scan pass/fail, test coverage metrics
- **Architecture Decision Records (ADRs)**: lightweight records of
  architectural choices (new dependencies, schema changes, API design) that
  provide context for future agent sessions

The product owner can optionally review these but is not required to.

### The Ultimate Test

A feature is ready to ship when:
1. The automated QA agent (agent-browser) passes all acceptance tests in the QA
   runbook
2. The product owner runs through a manual subset of QA tests as a sanity check
3. All automated security, linting, and type checking passes inside the black box
4. Human lead dev PR review approves (retained as accountability + safety net)

---

## 2. The Five Levels Framework

Dan Shapiro's framework (modeled after NHTSA driving automation levels):

| Level | Name | Description | Our Status |
|-------|------|-------------|------------|
| 0 | Manual | Traditional development | -- |
| 1 | Task Automation | AI writes tests, docs | -- |
| 2 | Paired Programming | Developer pairs with AI in IDE | -- |
| 3 | Human-in-Loop Mgmt | AI is senior dev, human reviews | **Current** |
| 4 | Autonomous Operation | Developer becomes PM, writes specs | **Target** |
| 5 | Dark Factory | Black box: specs in, software out | **Aspirational** |

### Where We Are Today (Level 3)

- Claude Code writes code, but we manage each step manually
- PRD creation is interactive but not formalized with hard gates
- QA runbook is created after implementation, not before
- Implementation planning requires manual context clearing and execution
- Code review with Codex is invoked manually, single-model only
- QA runbook with agent-browser works but is triggered manually
- No automated security pipeline beyond integration tests
- No multi-model consensus on PRDs or code reviews
- No cross-feature knowledge base; every feature starts from zero context

### What Level 4 Requires

- Formalized PRD interview with hard quality gate checklist
- Multi-model PRD challenge round (persona diversity + model diversity)
- Machine-generated QA runbook from hardened PRD (automated, no user loop)
- Multi-model validation (Claude + Codex) of both documents before development
- Autonomous implementation via subagent dispatch (Superpowers execution)
- Multi-model code review with synthesis before merging
- Automated security pipeline (secrets detection + SAST + AI review)
- Automated QA acceptance testing via agent-browser as a pipeline step
- Cross-feature knowledge base capturing patterns and decisions
- Product owner has two planned touchpoints (PRD authoring + sign-off), plus
  explicit exception touchpoints for failures/ambiguities

### What Level 5 Additionally Requires

- Digital Twin Universe for external service integration testing
- Self-healing: agent detects QA failures and autonomously fixes + re-tests
  (scoped to UI-layer fixes, capped at 3 attempts)
- Regression suite of deterministic Playwright scripts (converted from passing
  runbooks, no LLM cost for re-runs)
- Full CI/CD integration where PRD commit triggers the entire pipeline
- Gemini CLI as third reviewer for multi-model consensus (when stable)
- Optional holdout scenario probes (alternate formulations of approved
  requirements) once the baseline workflow is stable
- Periodic automated architectural health reviews

---

## 3. Current State

### Installed Skills (Source in this Repo)

```
skills/
  agent-browser/               # Browser automation for QA
    SKILL.md
    templates/
      capture-workflow.sh
      form-automation.sh
      authenticated-session.sh
    references/
      commands.md
      session-management.md
      authentication.md
      snapshot-refs.md
      video-recording.md
      profiling.md
      proxy-support.md

  review-branch-with-codex/    # Codex CLI branch/PR review
    SKILL.md
    scripts/
      review_branch.sh          # codex review --base <ref>
      codex_review_hook.py

  review-prd-with-codex/       # Codex CLI PRD review
    SKILL.md
    scripts/
      review_prd.sh             # codex exec --sandbox read-only

  skill-creator/               # Helper for creating new skills
    SKILL.md
    scripts/
      init_skill.py
      package_skill.py
      quick_validate.py
    references/
      workflows.md
      output-patterns.md
```

### Existing Test Infrastructure

- **Unit/component tests**: Vitest (project-specific command, e.g. `pnpm run test`)
- **Integration tests**: project-specific integration suite (e.g. `pnpm run test:integration`)
- **Security regression tests**: project-owned security test files (naming varies by repo)
- **QA documents**: acceptance runbooks authored per feature (see
  `examples/qa-runbooks/` in this repo for neutral format examples)

### Existing Codex CLI Patterns

The `review_branch.sh` script uses:
```bash
codex review --base <ref> --config model_reasoning_effort=high
```

The `review_prd.sh` script uses:
```bash
codex exec --skip-git-repo-check --sandbox read-only \
  --config model_reasoning_effort=high -C "$repo_root" "prompt"
```

> **Note (verified on Codex CLI v0.104.0)**: Both `codex review` and
> `codex exec review` exist as separate subcommands. `codex review` is the
> simpler top-level interface. `codex exec review` adds extra flags (`--json`,
> `--model`, `--full-auto`, `--skip-git-repo-check`) useful for automation.
> For orchestration scripts that need structured output, prefer
> `codex exec review --json`.

Both scripts write timestamped reports to `docs/reviews/` and save checkpoint
state to `.claude/review-state/`.

### What We Do NOT Have Yet

- Superpowers plugin (not installed)
- PRD interview skill with hard quality gates
- PRD challenge round (persona sub-agents + Codex parallel review)
- Machine-generated QA runbook from hardened PRD
- Multi-model orchestration (parallel review + synthesis)
- Automated security pipeline (gitleaks, Semgrep, Claude Code Security Review)
- QA runbook integrated into automated pipeline
- Cross-feature knowledge base
- Auto-generated Feature Delivery Reports / ADRs
- Regression suite conversion (runbook → deterministic Playwright scripts)

---

## 4. Target Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ USER TOUCHPOINT 1: PRD Authoring                                 │
│                                                                  │
│  ┌──────────────────────────────┐                               │
│  │ Stage 1: PRD Interview       │  Claude ↔ User conversational │
│  │                              │  loop until quality gate      │
│  │                              │  checklist passes             │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Stage 2: PRD Challenge Round │  3 Claude personas + Codex    │
│  │                              │  run in parallel:             │
│  │  ┌────────────────────────┐  │                               │
│  │  │ Skeptical User Advocate│  │  "What breaks for real users?"│
│  │  │ Tech Feasibility       │  │  "Does codebase support this?"│
│  │  │ Scope Challenger       │  │  "What hides complexity?"     │
│  │  │ Codex (model diversity)│  │  "What did Claude miss?"      │
│  │  └────────────────────────┘  │                               │
│  │                              │  → Synthesized question list  │
│  │                              │  → User addresses Crit/High   │
│  │                              │  → Lightweight recheck (max 2)│
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│ ════════════════╪═══════ MACHINE (no user) ════════════════════  │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Stage 3: QA Runbook Gen      │  AI writes runbook from PRD   │
│  │                              │  Bidirectional coverage check │
│  │                              │  Spec guardian check          │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Stage 4: Multi-model Valid.  │  Claude + Codex formal review │
│  │                              │  of PRD + QA together         │
│  │                              │  Non-semantic auto-fixes only │
│  │                              │  Semantic changes proposed    │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│ ════════════════╪══════════════════════════════════════════════  │
│                 │                                                │
│ USER TOUCHPOINT 2: Sign-off                                      │
│                 │                                                │
│  ┌──────────────────────────────┐                               │
│  │ Stage 5: User Approval       │  Review PRD + QA + report     │
│  │                              │  → Approve or Reject          │
│  │                              │  (reject routes back by type) │
│  └──────────────┬───────────────┘                               │
│                 │ approved                                       │
│                 │                                                │
│ ════════════════╪════════ DEVELOPMENT BLACK BOX ═══════════════  │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Architecture + Planning      │  Superpowers brainstorming    │
│  │                              │  + writing-plans              │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Implementation (TDD)         │  Superpowers subagent-        │
│  │                              │  driven-development           │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Security Scanning            │  gitleaks (secrets)           │
│  │                              │  + Semgrep SAST (diff-aware)  │
│  │                              │  + Claude Code Security (CI)  │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Multi-Model Code Review      │  Claude + Codex synthesize    │
│  │                              │  (+ Gemini when stable)       │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ agent-browser QA Execution   │  Executes QA runbook          │
│  │                              │  against running app          │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Knowledge Base + ADRs        │  Capture patterns, gotchas,   │
│  │ + Feature Delivery Report    │  architectural decisions      │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│ ════════════════╪══════════════════════════════════════════════  │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Human Sanity Check           │  Product owner runs subset    │
│  │                              │  of QA tests manually         │
│  └──────────────┬───────────────┘                               │
│                 │                                                │
│                 ▼                                                │
│  ┌──────────────────────────────┐                               │
│  │ Lead Dev PR Review           │  Human PR review (retained    │
│  │                              │  as accountability + safety)  │
│  └──────────────────────────────┘                               │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. QA Document Scope

### The QA Runbook as a Machine-Generated Artifact

The QA acceptance runbook is machine-generated from the hardened PRD *before
development begins*. The user does not co-author it — the PRD challenge round
(Stage 2) already surfaced gaps and ambiguities during PRD authoring. The QA
generation step (Stage 3) mechanically derives test scenarios from the
hardened PRD:
- Validates that every PRD requirement is testable (if the machine can't write
  a concrete test scenario, the requirement is ambiguous — flagged for review)
- Establishes the exact acceptance criteria agent-browser will validate
- Defines what "done" looks like before any code exists
- Runs bidirectional coverage check and spec guardian automatically

The product owner reviews the QA runbook at sign-off (Stage 5) and can reject
with feedback if scenarios are wrong or missing.

### Runbook Format

QA runbooks use natural language steps (not code), with optional structured
enhancements:

**YAML frontmatter** for machine-parseable configuration:
```yaml
---
id: qa-checkout-flow
app: storefront
base_url: http://localhost:3000
auth:
  user: qa.user@example.test
  password_env: QA_USER_PASSWORD
timeout: 30000
---
```

**Structured assertions** separated from actions:
```markdown
### TC-001 Add Item to Cart [P0 - Critical]

Steps:
1. Open the app home page.
2. Search for `Sample Item`.
3. Open product details.
4. Click `Add to Cart`.

Assertions:
- VERIFY text "1" visible in element matching "cart badge"
- VERIFY text "Sample Item" visible in element matching "cart drawer"
```

**Priority tags** per test case (`[P0 - Critical]`, `[P1 - High]`, etc.)
allow the agent to prioritize execution.

**data-testid hints** where available provide stable targeting:
```
4. Click `Add to Cart` (data-testid: "add-to-cart-btn")
```

### Spec Guardian Rule

The QA runbook must not contain implementation details. An automated check
during multi-model review rejects runbooks that reference class names, API
endpoints, database schemas, or internal architecture. The runbook describes
what the *user* sees and does, never how the system implements it.

### What BELONGS in the QA Acceptance Runbook

- Login and navigation flows
- CRUD operations through the UI
- Form validation from the user's perspective
- Role-based UI visibility ("member should NOT see the Invite button")
- Edge cases a user could encounter (session expiry, network errors)
- Multi-step workflows (invitation send -> email link -> acceptance)

### What Does NOT Belong (Goes Inside the Black Box)

- curl commands testing API endpoints directly
- Authorization bypass attempts
- SQL injection payloads
- Token manipulation tests
- Rate limit exploitation
- IDOR probing
- Header injection tests

### Action Item for Existing QA Docs

If any acceptance runbook currently includes API/security suites, those should be:
1. Verified as covered by the repo's automated security test suites
2. Removed from the QA acceptance document
3. Any gaps added to the automated test suite

---

## 6. The Black Box

### Security Pipeline (Automated, Invisible to Product Owner)

```
Layer 0: Pre-commit — Secrets Detection
  gitleaks (Go binary, <1 second)

Layer 1: Pre-commit — SAST
  semgrep scan --config auto --error \
    --severity ERROR --severity WARNING \
    --baseline-commit HEAD \
    --disable-version-check --quiet \
    --skip-unknown-extensions
  (diff-aware scan, 2-8 seconds)

Layer 2: CI/CD Pipeline (on every PR)
  pnpm run test          (unit tests + security-regression.test.ts)
  pnpm run test:integration
  pnpm run typecheck
  pnpm run lint
  Claude Code Security Review GitHub Action (posts PR comments)

Layer 3: Post-deploy (optional, deferred)
  OWASP ZAP DAST baseline scan against staging
```

**Pre-commit configuration:**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.0
    hooks:
      - id: gitleaks

  - repo: https://github.com/semgrep/pre-commit
    rev: v1.100.0
    hooks:
      - id: semgrep-ci
        args: ['--config', 'auto', '--error',
               '--severity', 'ERROR', '--severity', 'WARNING',
               '--baseline-commit', 'HEAD',
               '--disable-version-check', '--quiet',
               '--skip-unknown-extensions']
```

**Claude Code Security Review GitHub Action:**
```yaml
# .github/workflows/security-review.yml
name: Security Review
on: [pull_request]

permissions:
  pull-requests: write
  contents: read

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          fetch-depth: 2

      # Pin to a commit SHA for stability. Check the repo for the latest
      # release or commit: github.com/anthropics/claude-code-security-review
      # There is no stable @v1 tag as of 2026-02-25; @main is unstable.
      - uses: anthropics/claude-code-security-review@<pin-commit-sha>
        with:
          claude-api-key: ${{ secrets.CLAUDE_API_KEY }}
          comment-pr: true
```

**Severity escalation rule**: Findings below HIGH stay in the black box.
CRITICAL findings that survive the auto-fix loop get a one-line summary
surfaced to the product owner (e.g., "Feature delayed: authentication bypass
found during security review, being fixed").

### Multi-Model Review Mechanism

Three use cases for multi-model review, each at a different pipeline stage:

**Use Case 1: PRD Challenge Round (Stage 2 — user in the loop)**

Purpose: Surface gaps and clarifying questions while the user is still defining
requirements. This is the highest-leverage use of multi-model review because
changes are cheapest here.

1. Three Claude sub-agents run in parallel, each with a distinct persona:
   - **Skeptical User Advocate**: "What could confuse, frustrate, or break for
     a real person? What happens when they do something unexpected?" Covers UX
     edge cases, error states, empty states, accessibility.
   - **Technical Feasibility Reviewer**: "Given the current codebase, what's
     underspecified, unrealistic, or likely to cause integration pain?" Has
     the most codebase context — examines existing patterns, data models, API
     contracts.
   - **Scope & Complexity Challenger**: "What's hiding complexity behind simple
     language? What assumptions are unstated? What could be cut without losing
     the core value?"
2. Codex CLI reviews the same draft PRD independently (model diversity)
3. All four run in parallel; Claude synthesizes into a single prioritized
   question list, each tagged with source persona and severity
4. User addresses Critical/High questions; Medium/Low noted for reference
5. Lightweight recheck after updates (single Claude call, not full round)
6. Max 2 rounds total, then move on

**Use Case 2: PRD + QA Validation (Stage 4 — no user, machine-only)**

Purpose: Formal review of the finished PRD + QA runbook pair before presenting
to the user for sign-off. Lighter than Use Case 1 because the PRD was already
stress-tested.

1. Claude (Opus 4.6) reviews both documents for completeness, consistency,
   and bidirectional coverage
2. Codex CLI (GPT-5.3-codex) reviews both documents independently
3. Both run in parallel via bash background processes
4. Claude synthesizes: areas of agreement, areas of disagreement, by severity
5. AI auto-applies only non-semantic fixes (formatting, wording clarity,
   traceability links, deduplication)
6. Any semantic change (new requirement, requirement meaning change, scope
   change) is output as a proposed diff for user approval at Stage 5
7. Max 2 rounds total

**Use Case 3: Code Review (after implementation — no user)**

1. Same 2-model parallel pattern on the feature branch diff
2. Claude synthesizes findings, categorized by severity
3. Fix critical/high issues, re-run tests, optionally re-review

**Gemini CLI as future third reviewer**: When `gemini-3.1-pro-preview` (or
successor) is stable in the CLI for all auth methods, add Gemini as a third
parallel reviewer in all three use cases. The orchestration script uses a
pluggable reviewer interface (each reviewer is a script that takes input and
produces a markdown report), so adding Gemini is a config change, not an
architecture change.

**Synthesis pattern**: Based on ICLR 2026 research, majority voting +
synthesis captures most of the value of multi-model review. Iterative debate
adds complexity without proportional quality gains. All use cases use a single
synthesis pass with an optional second round only when critical contradictions
exist.

**Persona design principles**: Personas are gap-finders, not scope-expanders.
No "product dreamer" or "optimist" personas — at the PRD hardening stage, the
goal is to find holes, not add features. Each persona constrains attention to
a distinct concern axis to minimize overlap.

### Implementation Engine (Superpowers)

The development black box uses Superpowers for implementation and custom skills
for everything else. Superpowers provides:

1. **Brainstorming skill**: Structured 6-step design exploration with hard gates
2. **Writing-plans skill**: 2-5 minute tasks with exact file paths and commands
3. **Subagent-driven-development**: Fresh subagent per task, controller maintains
   continuity
4. **Executing-plans**: Batch execution of planned tasks with checkpoints
5. **Two-stage review per task**: Spec compliance check, then code quality check
   (`requesting-code-review` → dispatches `code-reviewer` subagent)
6. **TDD enforcement**: RED-GREEN-REFACTOR, delete code written before tests
7. **Systematic-debugging**: Four-phase root cause analysis for failures
8. **Verification-before-completion**: Per-task quality checks
9. **Finishing-a-development-branch**: PR preparation at the end (merge,
   branch deletion, and worktree cleanup are disabled in this workflow)
10. **Git worktree isolation**: Each feature in its own worktree

**Autonomous invocation**: Superpowers skills are interactive (designed for
human conversation). In the dark factory, each is invoked inside a sub-agent
with design authority context so it runs autonomously — no forking needed.
See Phase 4.4 for the full invocation pattern and fallback strategy.

**Not from Superpowers** (custom-built in this repo):
- PRD interview skill (Stage 1 — distinct from brainstorming; requirements
  gathering, not technical design)
- PRD challenge round (Stage 2)
- QA runbook generation (Stage 3)
- Multi-model review orchestration — all three use cases (Stages 2, 4, and
  post-implementation code review)
- agent-browser QA execution
- Knowledge base capture and priming
- Feature Delivery Report generation
- Master orchestration skill that drives the full pipeline

### Knowledge Base (Cross-Feature Learning)

After each feature ships, an agent captures patterns, gotchas, and
architectural decisions into a knowledge store (JSONL or markdown files in
`docs/knowledge/`). Future agent sessions are primed with contextually
relevant facts from this store. This prevents every feature from starting
with zero institutional knowledge.

Inspired by Metaswarm's self-learning pattern with selective knowledge priming.

### Auto-Generated Outputs

After each pipeline run, the black box produces:

1. **Feature Delivery Report**: ADR summaries, tech debt delta (complexity
   metrics), performance impact, security scan pass/fail, test coverage
2. **Architecture Decision Records**: Lightweight ADRs for any architectural
   choices (new dependencies, schema changes, API design, state management).
   Accumulated in `docs/decisions/` and provide context for future features.

These are transparency artifacts, not product owner deliverables. The product
owner can review them optionally but is not required to.

---

## 7. Gap Analysis

### Feature 1: PRD Interview + PRD Challenge + QA Generation

| Component | Status | Work Required |
|-----------|--------|---------------|
| PRD interview skill | Missing | Create `skills/prd-interview/SKILL.md` with checklist gates |
| PRD challenge personas | Missing | Create 3 persona prompts (Skeptical User, Tech Feasibility, Scope Challenger) |
| PRD challenge orchestration | Missing | Parallel sub-agent launch + Codex + synthesis into question list |
| PRD challenge recheck | Missing | Lightweight single-model pass after user addresses questions |
| QA runbook generation skill | Missing | Create skill to machine-generate QA runbook from hardened PRD |
| PRD ↔ QA bidirectional sync | Missing | Validation that every PRD claim has a QA scenario and vice versa |
| Spec guardian check | Missing | Automated check rejecting QA runbooks with implementation details |
| QA runbook YAML frontmatter | Missing | Standardize runbook format with machine-parseable config |

### Feature 2: Multi-Model Review (Validation + Code)

| Component | Status | Work Required |
|-----------|--------|---------------|
| Codex PRD review skill | Done | -- |
| Codex branch review skill | Done | -- |
| Claude PRD review script | Missing | Create `scripts/review_prd_claude.sh` |
| Claude branch review script | Missing | Create `scripts/review_branch_claude.sh` |
| Parallel orchestration script | Missing | Create (bash bg processes + wait) |
| Consensus synthesis prompt | Missing | Create (Claude reads all reviews, synthesizes) |
| Pluggable reviewer interface | Missing | Design so Gemini can be added later as config change |
| SKILL.md wrappers | Missing | Create for both validation and code review |

### Feature 3: Automated QA with agent-browser

| Component | Status | Work Required |
|-----------|--------|---------------|
| agent-browser skill | Done | -- |
| QA runbook documents | Done (but need cleanup) | Remove security suites, add YAML frontmatter |
| SKILL.md for QA execution | Missing | Create wrapper that triggers agent-browser with QA doc |
| Superpowers integration | Missing | Wire QA execution after implementation completes |

### Feature 4: Superpowers Integration

| Component | Status | Work Required |
|-----------|--------|---------------|
| Superpowers plugin | Not installed | `/plugin marketplace add` + `/plugin install` |
| Custom skills coexistence | Verified safe | Namespacing prevents conflicts |
| QA execution skill | Missing | Create under `skills/` and add to manifest |
| Multi-model review skill | Missing | Create under `skills/` and add to manifest |

### Feature 5: Security Pipeline

| Component | Status | Work Required |
|-----------|--------|---------------|
| Security regression tests | Done | -- |
| Authorization boundary tests | Done | -- |
| gitleaks pre-commit hook | Missing | Install + configure |
| Semgrep pre-commit hook | Missing | Install + configure (diff-aware) |
| Claude Code Security GH Action | Missing | Add to CI workflow (correct config) |
| Security-suite cleanup from QA docs | Missing | Verify coverage, then remove |
| Severity escalation rule | Missing | Surface CRITICAL findings to product owner |

### Feature 6: Knowledge Base + Delivery Reports

| Component | Status | Work Required |
|-----------|--------|---------------|
| Knowledge base structure | Missing | Create `docs/knowledge/` format and priming script |
| Post-feature capture skill | Missing | Skill that extracts patterns/decisions after shipping |
| Feature Delivery Report template | Missing | Auto-generated summary after pipeline run |
| ADR generation skill | Missing | Review diff and produce lightweight ADRs |

---

## 8. Implementation Plan

### Phase 1: Foundation (Superpowers + PRD/QA Planning Workflow)

**Goal**: Install Superpowers, create the PRD interview skill with multi-model
challenge round, and establish the automated QA generation workflow.

#### 1.1 Install Superpowers
```bash
# In Claude Code:
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Verify skills load correctly. Test brainstorming skill on a small feature.
Confirm custom skills in `~/.claude/skills/` coexist (namespacing).

#### 1.2 Create PRD Interview Skill

Create `skills/prd-interview/SKILL.md` that:
- Adopts an analyst persona for structured questioning
- Asks questions one at a time, branching based on answers
- Probes specifically for: negative requirements (what should NOT happen),
  scope boundaries, existing behavior that must not change, edge cases
- Outputs a markdown PRD in a standardized template
- Enforces a hard quality gate checklist before accepting the PRD:
  - [ ] All acceptance criteria are atomic, verifiable predicates
  - [ ] Every user flow has at least one negative/edge case
  - [ ] NFRs stated with measurable thresholds
  - [ ] Domain glossary exists for ambiguous terms
  - [ ] Scope boundaries explicitly defined
- When the checklist passes, triggers the PRD challenge round (1.3)

#### 1.3 Create PRD Challenge Round Skill

Create `skills/prd-challenge/SKILL.md` that:
- Takes a draft PRD (checklist-gated) as input
- Launches 4 parallel reviews:
  1. **Skeptical User Advocate** (Claude sub-agent): probes for UX edge
     cases, error states, empty states, accessibility gaps, confusing flows
  2. **Technical Feasibility Reviewer** (Claude sub-agent): reads the
     codebase and checks for underspecified requirements, unrealistic
     expectations, integration pain with existing patterns/data models
  3. **Scope & Complexity Challenger** (Claude sub-agent): finds hidden
     complexity, unstated assumptions, requirements that could be cut
  4. **Codex CLI review**: independent model perspective on the draft PRD
- Synthesizes all 4 outputs into a single prioritized question list:
  - Each question tagged with source persona and severity (Crit/High/Med/Low)
  - Deduplicated where multiple reviewers raised the same concern
  - Critical/High questions presented to user; Medium/Low noted for reference
- After user addresses questions and PRD is updated, runs a **lightweight
  recheck**: single Claude call asking "Given the updated PRD and the previous
  Q&A, are there any remaining Critical or High concerns?"
- Exit conditions:
  - Recheck returns clean → proceed to Stage 3 (QA generation)
  - Recheck finds new issues → user addresses, then proceed (max 2 rounds)
  - User override → proceed anytime ("good enough, move on")

#### 1.4 Create QA Runbook Generation Skill

Create `skills/qa-runbook-gen/SKILL.md` that:
- Takes a hardened PRD (post-challenge) as input
- Machine-generates a QA acceptance runbook with YAML frontmatter, structured
  assertions, and priority tags — no user interaction
- Validates bidirectional coverage: every PRD requirement has a test,
  every test traces to a requirement
- Runs spec guardian check: rejects runbooks with implementation details
- Self-corrects any coverage gaps or spec guardian violations
- If a PRD requirement is untestable (can't generate a concrete UI scenario),
  flags it in the output for user review at sign-off

#### 1.5 Clean Up Existing QA Documents
- Audit acceptance runbooks for API/security-focused suites
- Cross-reference with automated security and authorization tests
- Add any missing coverage to automated test suite
- Remove security/API suites from QA acceptance document
- Add YAML frontmatter and structured assertions to existing runbooks

#### 1.6 Create QA Execution Skill

Create `skills/qa-acceptance/SKILL.md` that:
- Takes a QA runbook path as input
- Invokes agent-browser to execute each test case
- Uses DOM/accessibility tree (`snapshot -i`) for interactions and assertions
- Captures screenshots on failure only (not during normal execution)
- Reports pass/fail with priority-ordered results
- Supports re-running failed tests after fixes

---

### Phase 2: Multi-Model Validation & Code Review

**Goal**: Build the 2-model parallel review + synthesis pipeline for document
validation (Stage 4) and code review. The PRD challenge round (Stage 2) was
built in Phase 1; this phase creates the shared orchestration infrastructure
that both the validation and code review stages use.

#### 2.1 Create Claude Review Scripts

Create `scripts/review_prd_claude.sh` and `scripts/review_branch_claude.sh`:
- Use Claude Code in headless mode (`claude -p "prompt" --output-format json`)
  or via subagent
- Same output contract as Codex scripts: timestamped report in `docs/reviews/`

#### 2.2 Create Multi-Model Orchestration

Create `skills/multi-model-review/`:
- `SKILL.md` -- "Use when a PRD/QA runbook pair or feature branch needs
  multi-model review"
- `scripts/review_multimodel.sh` -- orchestration script:
  1. Accept mode (`validation` or `branch`) and target path(s)
  2. Launch Codex and Claude reviews in parallel (`&` + `wait`)
  3. Compute workload-size tier and set timeout per attempt:
     - **Validation mode (PRD + QA docs)**:
       - Small: combined <= 3,000 words -> 10 minutes
       - Medium: 3,001-10,000 words -> 15 minutes
       - Large: > 10,000 words -> 20 minutes
     - **Branch mode (code review)**:
       - Small: <= 8 changed files AND <= 500 changed LOC -> 10 minutes
       - Medium: <= 25 files OR <= 2,000 changed LOC -> 15 minutes
       - Large: above medium -> 20 minutes
  4. Retry each reviewer up to 3 times for transient failures only
     (timeout, rate-limit, transient CLI/network errors) with exponential
     backoff: 20s, 60s, 120s
  5. **Both reviewers must complete**. If either reviewer still fails after
     retries: hard halt, notify operator (you), and emit a failure report
     artifact for debugging. Single-model degradation is not permitted silently.
  6. Output combined report for Claude synthesis
- **Pluggable reviewer interface**: Each reviewer is a script that accepts a
  prompt/target and writes a markdown report. Adding Gemini later is a config
  change (add script, update reviewer list).
- **Validation mode** (Stage 4): Reviews PRD + QA runbook pair for
  completeness, consistency, bidirectional coverage. AI can auto-apply
  non-semantic fixes and must surface semantic changes as user-approved
  proposals at sign-off.
- **Branch mode** (post-implementation): Reviews feature branch diff for
  code quality, security, spec compliance.

#### 2.3 Create Synthesis Prompt

The synthesis step (run by Claude after reviews are collected):
- Read all review reports
- Identify areas of agreement (flagged by both reviewers)
- Identify areas unique to one reviewer (lower confidence, note for reference)
- Categorize by severity (Critical / High / Medium / Low)
- Produce unified action items with specific references
- Determine if a second round is needed (unresolved critical contradictions)
- Max 2 rounds total; if contradictions persist, flag for human review

#### 2.4 Wire Stage 3-4-5 Automation

Create the automated pipeline that runs after the PRD challenge round
completes (no user interaction until sign-off):
1. Trigger QA runbook generation (Phase 1.4 skill) from hardened PRD
2. Run multi-model validation (2.2 in validation mode) on PRD + QA pair
3. AI applies only non-semantic fixes from validation; semantic findings are
   packaged as explicit user approval suggestions
4. Package results: final PRD, final QA runbook, validation report summary
5. Present to user for sign-off (Stage 5)
6. Handle rejection routing (QA-only / PRD tweak / major scope change)

---

### Phase 3: Security Pipeline

**Goal**: Automate security testing so it runs without product owner
involvement.

#### 3.1 Secrets Detection (Pre-commit)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.0
    hooks:
      - id: gitleaks
```

Fast (<1 second), free, catches hardcoded API keys and credentials that
AI-generated code commonly introduces.

#### 3.2 Semgrep SAST (Pre-commit)

```yaml
  - repo: https://github.com/semgrep/pre-commit
    rev: v1.100.0  # pin to specific version
    hooks:
      - id: semgrep-ci
        args: ['--config', 'auto', '--error',
               '--severity', 'ERROR', '--severity', 'WARNING',
               '--baseline-commit', 'HEAD',
               '--disable-version-check', '--quiet',
               '--skip-unknown-extensions']
```

Key flags:
- `--baseline-commit HEAD`: Only scan changed files (2-8s vs 90s full scan)
- `--severity WARNING`: Catches hardcoded credentials and insecure defaults
  that ERROR alone misses
- `--disable-version-check`: No network call for version check

Consider pinning rules locally for deterministic scans:
```bash
semgrep --config auto --generate-config > .semgrep-rules.yml
```

#### 3.3 Claude Code Security Review (CI)

```yaml
# .github/workflows/security-review.yml
name: Security Review
on: [pull_request]

permissions:
  pull-requests: write
  contents: read

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          fetch-depth: 2

      # Pin to a commit SHA for stability. Check the repo for the latest
      # release or commit: github.com/anthropics/claude-code-security-review
      # There is no stable @v1 tag as of 2026-02-25; @main is unstable.
      - uses: anthropics/claude-code-security-review@<pin-commit-sha>
        with:
          claude-api-key: ${{ secrets.CLAUDE_API_KEY }}
          comment-pr: true
```

Implementation gate: CI rollout is blocked until `<pin-commit-sha>` is replaced
with an actual commit SHA in the workflow file.

Cost: ~$0.10-$0.50 per PR. Catches semantic vulnerabilities that
pattern-matching SAST tools miss (business logic flaws, race conditions,
authorization bypass).

#### 3.4 Verify Security Test Coverage
- Map every security-oriented runbook scenario to an automated test
- Add missing tests to the repo's security regression suite
- Remove security suites from QA acceptance documents
- Ensure the main test command covers all required security scenarios

---

### Phase 4: End-to-End Integration

**Goal**: Wire everything together into a single orchestration skill so the
user starts one conversation and the full pipeline runs automatically, stopping
at the two planned touchpoints plus explicit exception touchpoints when needed.

#### 4.1 Orchestration Model

The user experience is a single conversation:

```
User: "I want to build a new feature"  (or /dark-factory)

    ┌── Stage 1: PRD Interview ─────────────────────────────────┐
    │ Claude asks questions, user answers                        │
    │ Quality gate checklist passes → automatic transition       │
    ├── Stage 2: PRD Challenge Round ───────────────────────────┤
    │ "Running challenge round..."                               │
    │ 4 parallel sub-agents launch automatically                 │
    │ Synthesized questions presented to user                    │
    │ User answers → lightweight recheck → automatic transition  │
    ├── Stages 3-4: Machine runs (no user) ─────────────────────┤
    │ "Generating QA runbook and running validation..."          │
    │ (user waits or does other things)                          │
    ├── Stage 5: Sign-off ──────────────────────────────────────┤
    │ "Here's your PRD and QA runbook. Validation complete.       │
    │  Please review and approve (including any semantic          │
    │  change proposals)."                                        │
    │ User reviews files, approves or rejects                    │
    ├── Development Black Box (no user) ────────────────────────┤
    │ "Starting development pipeline..."                         │
    │ (long-running, user does other things)                     │
    ├── Done ───────────────────────────────────────────────────┤
    │ "Feature complete. All QA tests pass. Ready for your       │
    │  sanity check and PR review. Here's the delivery report."  │
    └───────────────────────────────────────────────────────────┘
```

The user has exactly **two planned interaction points** (PRD authoring and
sign-off). Everything else is automatic transitions driven by the master skill,
except explicit failure/ambiguity escalations defined in section 4.7.

#### 4.2 Create Dark Factory Master Skill

Create `skills/dark-factory/SKILL.md` as the **master orchestration skill**
that acts as a state machine driving the full pipeline:

```
Use when starting a new feature. This skill orchestrates the entire dark
factory pipeline: PRD interview, multi-model challenge round, QA runbook
generation, validation, user sign-off, and autonomous development through
to shipping readiness.
```

The SKILL.md defines:
- The stage sequence and transition conditions
- When to invoke sub-agents vs inline execution
- When to pause for user input vs proceed autonomously
- How to invoke Superpowers skills during the development phase
- How to handle failures and escalation at each stage

#### 4.3 Stage-by-Stage Skill Mapping

Each pipeline stage maps to either a custom skill or a Superpowers skill:

| Stage | Skill Used | Type | User? |
|-------|-----------|------|-------|
| 1. PRD Interview | `skills/prd-interview/` | Custom | Interactive |
| 2. PRD Challenge Round | `skills/prd-challenge/` | Custom | Interactive |
| 3. QA Runbook Generation | `skills/qa-runbook-gen/` | Custom | Automatic |
| 4. Multi-model Validation | `skills/multi-model-review/` (validation mode) | Custom | Automatic |
| 5. User Sign-off | Master skill presents artifacts | Custom | Interactive |
| 6. Design Exploration | Superpowers `brainstorming` | Superpowers | Automatic |
| 7. Implementation Planning | Superpowers `writing-plans` | Superpowers | Automatic |
| 8. Build Feature (TDD) | Superpowers `subagent-driven-development` + `test-driven-development` + `executing-plans` | Superpowers | Automatic |
| 9. Run Tests | Project commands (`pnpm run test`, etc.) | Project | Automatic |
| 10. Multi-model Code Review | `skills/multi-model-review/` (branch mode) | Custom | Automatic |
| 11. Fix Critical Findings | Superpowers `systematic-debugging` + `receiving-code-review` | Superpowers | Automatic |
| 12. QA Execution | `skills/qa-acceptance/` (agent-browser) | Custom | Automatic |
| 13. Fix QA Failures | Superpowers `systematic-debugging` | Superpowers | Automatic |
| 14. Feature Delivery Report | Custom generator | Custom | Automatic |
| 15. Knowledge Capture | Custom skill | Custom | Automatic |
| 16. PR Preparation (No Merge) | Superpowers `finishing-a-development-branch` (configured for PR prep only) | Superpowers | Automatic |

**Superpowers vs Custom overlap clarification**: Superpowers has its own
per-task code review (`requesting-code-review` → dispatches a `code-reviewer`
subagent). That runs during step 8 as a per-task check inside the TDD loop.
Our multi-model code review (step 10) is a feature-level review of the
complete branch diff. They are complementary — Superpowers catches per-task
issues, multi-model review catches cross-task and architectural issues.

Merge to `main` is always human-controlled and happens only after manual sanity
check and lead-dev PR review approval.

#### 4.4 Invoking Superpowers Skills Autonomously

Superpowers skills are interactive by design — `brainstorming` has a
`<HARD-GATE>` requiring user approval before proceeding, `writing-plans`
asks which execution approach to use, and other skills expect human input at
various checkpoints. In the dark factory, the user has signed off and the
black box runs autonomously. We solve this with **sub-agent wrapping**, not
by forking the skills.

##### Sub-Agent Invocation Pattern

Each interactive Superpowers skill runs inside a **sub-agent** that has both
the skill loaded AND design authority context. The sub-agent plays both
roles — it follows the skill's process AND answers its own questions:

```
Master skill dispatches sub-agent with:
  1. Superpowers skill loaded (e.g., brainstorming)
  2. Approved PRD as context
  3. Approved QA runbook as context
  4. Codebase access
  5. Knowledge base (relevant facts from previous features)
  6. Design authority instructions (see below)

Sub-agent runs the skill's full process autonomously.
Sub-agent returns: output artifact (design doc, implementation plan, etc.)
```

##### Chain-Control Contract

Stage transitions are owned only by the master orchestration skill:
- Exactly one Superpowers skill is invoked per stage
- If a Superpowers skill suggests chaining to the next skill, that suggestion is
  ignored
- The master captures the current stage artifact, persists state, then starts
  the next stage explicitly
- No implicit chain can skip failure checks, verifier checks, or user gates

**Design authority instructions** (included in every sub-agent prompt):

> You are operating autonomously as part of the dark factory pipeline.
> The user has already approved the PRD and QA runbook attached as context.
> When the skill process asks for user input, approval, or decisions:
> - Answer product questions from the PRD
> - Answer technical questions based on codebase patterns and merit
> - At approval checkpoints, evaluate against the PRD and approve or
>   revise yourself
> - Log every decision as an ADR in `docs/decisions/`
> - If you find a genuine PRD contradiction that cannot be resolved from
>   context, stop and return the contradiction for user escalation

**Benefits of this approach:**
- No fork — Superpowers skills are used as-is, updates flow through
  automatically
- Design authority is just the sub-agent's wrapper prompt
- Output format stays the same (design docs, plans, etc.)
- Each sub-agent gets a fresh context window

##### Skill-Specific Invocation Details

**`brainstorming`** (Step 6 — Design Exploration):
- Sub-agent explores codebase, asks itself clarifying questions answered from
  the PRD, proposes 2-3 approaches and picks the best one based on codebase
  patterns, writes design doc to `docs/plans/`
- The skill's "user approves design?" gate is satisfied by the sub-agent
  evaluating each design section against PRD requirements
- The skill chains to `writing-plans` at the end — the sub-agent does NOT
  follow this chain (master skill handles the transition to the next step)
- Output: design doc

**`writing-plans`** (Step 7 — Implementation Planning):
- Sub-agent takes the design doc from step 6 as additional context
- Produces bite-sized 2-5 minute tasks with exact file paths, code, commands
- The execution handoff question ("subagent-driven or parallel session?")
  is pre-decided: always subagent-driven
- Output: implementation plan

##### Independent Verifier Pass (Required)

To avoid self-approval loops, every major artifact produced by an autonomous
sub-agent must be checked by an independent verifier pass before advancing:
- Design doc verifier: checks PRD alignment, constraint coverage, and risk flags
- Plan verifier: checks task completeness, path/command specificity, and QA
  traceability
- Verification runs with a separate prompt/model call from the generating
  sub-agent
- If verifier returns FAIL, the stage is revised and re-verified (max 2 rounds)
- If still failing after max rounds, escalate to operator

**`subagent-driven-development` + `test-driven-development`** (Step 8):
- These already use sub-agents internally (fresh subagent per task), so they
  are naturally compatible with autonomous execution
- The controller maintains continuity between tasks; individual task agents
  are stateless
- Per-task code review via `requesting-code-review` runs as a nested
  sub-agent (Superpowers' own pattern)

**`systematic-debugging`** (Steps 11, 13 — Fix Failures):
- Sub-agent receives the failure context (review findings or QA failure
  report) plus the PRD/design doc
- Follows the four-phase root cause methodology
- Output: applied fix + explanation

**`finishing-a-development-branch`** (Step 16 — PR Preparation):
- Sub-agent handles PR creation/update and PR metadata only
- It must not merge, delete branches, or clean up worktrees
- Merge and cleanup are separate human-run post-approval actions

##### Adapter Skill Fallback

If testing reveals that a Superpowers skill's `<HARD-GATE>` tags cause the
sub-agent to get stuck (e.g., waiting for approval that never comes from a
real user), the fallback is a thin **adapter skill** per affected skill:
- Same process steps and output format as the original
- Replaces interactive checkpoints with autonomous PRD-based validation
- Not a full fork — a wrapper that follows the same structure
- Only created for skills where the sub-agent approach fails in practice

##### Decision Routing

When a sub-agent encounters a question during any Superpowers skill, it
routes based on type:

| Question Type | Example | Resolution |
|---------------|---------|------------|
| **Product decision** | "Confirmation dialog or immediate delete?" | Answer from the PRD. Escalate to user if the decision changes any of: acceptance criteria, user-visible flow/copy, role/permission behavior, billing/pricing behavior, retention/deletion behavior, or external integration contract. Otherwise make a conservative reversible choice and log as inferred ADR. |
| **Technical/architectural** | "WebSocket or SSE?" / "New table or extend existing?" | Agent decides based on codebase patterns and technical merit. Log as an ADR. The user explicitly does not care about these — they are inside the black box. |
| **PRD contradiction** | Two requirements that conflict | **Escalate to user.** This is the primary semantic breakout from the black box and should be rare if stages 1-4 worked. |
| **Operational failure** | Reviewer timeout / QA checkpoint | Escalate to operator per section 4.7 failure policy. |

**ADR logging**: Every decision made autonomously is logged as a lightweight
ADR in `docs/decisions/`. This provides an audit trail for the user to
review after the pipeline completes, and gives future agent sessions context
on why choices were made.

##### PRD Interview Skill Is Custom (Not Brainstorming)

The PRD interview skill (Stage 1) is purpose-built, not a repurposed
brainstorming skill. While both ask questions one at a time, they operate
at different levels:

| | PRD Interview (Stage 1) | Brainstorming (Step 6) |
|---|---|---|
| **Purpose** | Define *what* to build (requirements) | Design *how* to build it (architecture) |
| **Language** | Product: user flows, acceptance criteria | Technical: components, data flow, patterns |
| **Output** | PRD document | Design document |
| **Exit gate** | Quality checklist (5 items) | Design approval |
| **Runs with** | The user (interactive) | Design authority sub-agent (autonomous) |

The PRD interview skill borrows brainstorming's interaction patterns (one
question at a time, multiple choice preferred, propose options) but is a
separate skill with different content, output, and gate conditions.

#### 4.5 State Management

Pipeline state is persisted to disk so it survives context compression,
session interruptions, and long-running stages:

```
.claude/dark-factory-state/
  <feature-id>.json       # Current stage, artifact paths, timestamps
  <feature-id>/
    prd-draft.md          # Artifacts at each stage
    prd-hardened.md
    challenge-questions.md
    qa-runbook.md
    validation-report.md
    delivery-report.md
```

The state file tracks:
- Current stage and substep
- Paths to all generated artifacts
- Timestamps for each transition
- Rejection history (if user rejected at sign-off, what feedback was given)
- Failure log (reviewer timeouts, QA failures, fix attempts)

If a session is interrupted, the master skill reads the state file on resume
and picks up where it left off. Artifacts are always on disk, not just in
conversation history.

#### 4.6 Context Window Management

A full pipeline run (interview through QA execution) will exceed the context
window. Mitigations:

- **Sub-agents for expensive stages**: Challenge round (4 parallel reviews),
  multi-model validation, multi-model code review, and QA execution each run
  as sub-agents with fresh context
- **Superpowers already uses fresh subagents** per task during implementation
  (step 8), so the build phase is naturally distributed
- **State file enables resumption** after context compression — the master
  skill reads current stage from disk, not from conversation history
- **Artifacts on disk** — PRD, QA runbook, review reports, delivery report
  are all files the user can review in their editor at any point, independent
  of the conversation

#### 4.7 Failure Escalation

Each stage has defined failure behavior:

| Stage | Failure | Behavior |
|-------|---------|----------|
| Stages 1-2 | N/A | User is in the loop |
| Stage 3 (QA gen) | Untestable requirements | Flag in sign-off package |
| Stage 4 (Validation) | Reviewer timeout/failure | 3 retries with backoff → halt, notify operator |
| Steps 6-8 (Superpowers) | Build/test failure | Superpowers handles internally within watchdog bounds: max 5 attempts per task OR 30 minutes per task OR configured budget cap; on exceed -> halt, notify operator with failure packet |
| Step 10 (Code review) | Reviewer timeout/failure | Same retry policy as Stage 4 |
| Step 12 (QA execution) | Test failures | Fix-and-retest loop; every 10 cycles pause and ask operator to continue or halt for manual debugging |
| Step 12 (QA execution) | agent-browser crash | Retry up to 3 times → halt, notify operator |

#### 4.8 Create Knowledge Base Infrastructure

- Create `docs/knowledge/` directory structure
- Build post-feature capture skill that extracts:
  - Patterns that worked well
  - Gotchas and anti-patterns encountered
  - Architectural decisions and their rationale
  - Dependencies added and why
- Build knowledge priming script that selects contextually relevant facts
  for future agent sessions (selective loading, not full dump)

#### 4.9 Create Feature Delivery Report Generator

Auto-generated after each pipeline run:
- ADR summaries (architectural decisions made)
- Tech debt delta (complexity metrics before/after)
- Security scan results (pass/fail summary, not details)
- Test coverage metrics
- QA runbook pass/fail results

#### 4.10 Create Regression Test Framework

- After each feature's QA runbook passes, generate a deterministic Playwright
  test script from the successful run (no LLM needed for re-runs)
- Regression suite runs Playwright scripts directly in CI
- New features must not break existing regression tests
- Only new feature QA uses LLM-driven agent-browser execution
- Tag tests by feature; re-generate only affected tests when features change
- Set flakiness budget: quarantine tests that fail non-deterministically >2%
- Separate P0 smoke suite (every PR) from full regression (merge to main)

#### 4.11 Document the Process

Update `CLAUDE.md` to reference the dark factory workflow:
- When to use it (new features, significant changes)
- When NOT to use it (bug fixes, small tweaks, config changes)
- How to invoke it (single command: `/dark-factory` or "build a new feature")
- The two planned user touchpoints (PRD authoring + final sign-off)
- Exception touchpoint policy (when and why the pipeline escalates)
- What happens inside the black box (Stages 3-4 and development pipeline)
- What auto-generated outputs to expect
- Where state and artifacts are stored
- Rejection routing: how feedback is classified and where it goes

---

### Phase 5: Toward Level 5 (Future)

These are not immediate priorities but represent the path to true Level 5:

#### 5.1 Add Gemini as Third Reviewer

When `gemini-3.1-pro-preview` (or successor) is stable in the Gemini CLI for
all authentication methods:
- Create `skills/review-prd-with-gemini/` and
  `skills/review-branch-with-gemini/`
- Add Gemini script to the pluggable reviewer list in the orchestration script
- Use `gemini -m <model> -p "$prompt" -o text --approval-mode yolo > "$out_file"`
- Test `--approval-mode yolo` thoroughly (known bugs in some versions)

#### 5.2 Self-Healing Loop (Scoped)

When QA tests fail, the agent can autonomously attempt fixes, but only for
**UI-layer issues** (CSS, routing, conditional rendering, form validation):
1. Classify the failure type (selector issue vs logic bug vs data issue)
2. If classifiable with confidence → attempt fix
3. If not classifiable → escalate to human immediately
4. Re-run the failing test
5. Max 3 attempts before escalating to human
6. All self-healing changes require code review before merge
7. Log every attempt with failure screenshot, diagnosis, and applied fix

Self-healing is NOT appropriate for: complex state management bugs, race
conditions, concurrency issues, or logic errors not visible in the UI.

#### 5.3 PRD-Triggered Pipeline
- Commit a PRD file to a specific directory
- Git hook or CI job detects the new PRD
- Full pipeline runs automatically
- Product owner is notified when QA passes (or when human input is needed)

#### 5.4 Performance Regression Testing
- Automated Lighthouse CI for web projects
- Response time benchmarks for APIs
- Bundle size tracking
- Performance regressions treated like test failures

#### 5.5 Periodic Architectural Health Reviews
- Monthly (or per-N-features) automated sweep
- Agent analyzes full codebase for: cyclomatic complexity trends, coupling
  metrics, duplication ratios, dependency freshness, dead code accumulation
- Surfaces technical debt before it becomes critical

#### 5.6 Optional Holdout Scenario Probes
- Defer until the baseline PRD -> QA -> implementation pipeline is stable
  across multiple feature cycles
- Holdouts are not hidden requirements; they are alternate test formulations
  of already approved PRD requirements
- Keep scope small initially (for example, 5-10% shadow probe coverage on P0/P1
  requirements)
- Use only as a robustness signal; do not block early pipeline adoption on this
  capability

---

## 9. Key Risks & Mitigations

### Risk 1: Shared Blind Spots
**Problem**: Same model writes code and tests, sharing the same gaps.
**Mitigation**: Multi-model review (Claude + Codex, Gemini future). Browser-
based QA via agent-browser tests the real UI, which is hard to game — unlike
unit tests, UI-level assertions can't be satisfied by `return true`. LLM-
authored, human-approved PRD and QA documents keep requirements under human
control. Human sanity check as final gate.

### Risk 2: Specification Gaming
**Problem**: Agents optimize evaluation signals rather than solving the real
problem (e.g., writing `return true` to pass tests).
**Mitigation**: QA acceptance tests are LLM-authored from the PRD and reviewed
by the product owner at sign-off. Tests execute via agent-browser against
the real UI — DOM-level assertions against a running app are harder to game
than unit test stubs. Providing the full QA runbook to the dev agent gives it
maximum context to implement correctly. Optional holdout probes can be added in
a later phase for additional robustness once the core process is stable.

### Risk 3: Silent Failures
**Problem**: Code runs but produces incorrect results.
**Mitigation**: agent-browser QA catches UI-visible incorrect behavior. Manual
sanity check catches subtle issues. Multi-model code review catches logic
errors that single-model review misses. Human sign-off on LLM-authored PRD/QA
documents ensures scenarios reflect real user expectations, not only model
assumptions.

### Risk 4: Spec Quality Degradation
**Problem**: PRDs accumulate contradictions over time.
**Mitigation**: The PRD challenge round (3 personas + Codex) stress-tests every
PRD from multiple angles before it leaves the authoring stage. The PRD
interview skill front-loads quality with a hard checklist gate. Machine-
generated QA runbooks provide automated bidirectional validation (every PRD
claim has a test, every test traces to a requirement). Each PRD is a
standalone document, not an evolving spec file.

### Risk 5: Agent Instruction Non-Compliance
**Problem**: Agents don't follow all instructions in large contexts.
**Mitigation**: Superpowers' hard gates enforce workflow compliance. Two-stage
review (spec compliance + code quality) catches deviations. QA acceptance tests
validate the actual output regardless of process compliance.

### Risk 6: Token Cost
**Problem**: Multi-model reviews and subagent execution are expensive.
**Mitigation**: Use Haiku/Flash for simple tasks, Opus/Pro for complex ones.
Superpowers' 2-5 minute task decomposition limits per-subagent token burn.
Max 2 rounds on consensus loops prevents runaway costs. QA fix loops include
operator checkpoints every 10 iterations to prevent runaway execution.
Regression suite uses deterministic Playwright scripts (no LLM cost for
re-runs).

### Risk 7: Technical Debt Accumulation
**Problem**: AI-generated code is functional but systematically lacks
architectural judgment, leading to debt accumulation across features.
**Mitigation**: Multi-model code review catches structural issues. Auto-
generated ADRs track architectural decisions. Knowledge base carries context
across features. Periodic architectural health reviews (Phase 5.5) surface
degradation before it becomes critical. Feature Delivery Reports include
complexity metrics delta.

### Risk 8: Accountability and Trust
**Problem**: When agents write code and test code, liability attribution
collapses (Stanford Law CodeX analysis).
**Mitigation**: Human lead dev PR review is retained as the final gate, even
as the review becomes lighter over time (architecture and risk focus, not
line-by-line). This provides the traceability and accountability that fully
autonomous pipelines lack. Auto-generated Feature Delivery Reports and ADRs
create an audit trail.

---

## 10. Research Sources

### Frameworks Referenced

| Framework | GitHub | Stars | Purpose |
|-----------|--------|-------|---------|
| Superpowers | [obra/superpowers](https://github.com/obra/superpowers) | 60.7k | Skills-based dev workflow for Claude Code |
| BMAD Method | [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | 37.7k | Full SDLC with agent personas |
| GitHub Spec Kit | [github/spec-kit](https://github.com/github/spec-kit) | -- | Spec-driven development toolkit |
| ATDD Plugin | [swingerman/atdd](https://github.com/swingerman/atdd) | -- | Acceptance Test Driven Development |
| Metaswarm | [dsifry/metaswarm](https://github.com/dsifry/metaswarm) | -- | 18-agent orchestration framework |
| Adversarial Review | [alecnielsen/adversarial-review](https://github.com/alecnielsen/adversarial-review) | -- | Claude + Codex debate loop |
| Claude Code Security | [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review) | 3.3k | AI-powered security scanning |
| GSD | [gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done) | -- | Minimal spec-driven development |
| agent-browser | [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) | 15.3k | Browser automation CLI for AI agents |

### Key Articles

- [Dan Shapiro - The Five Levels](https://www.danshapiro.com/blog/2026/01/the-five-levels-from-spicy-autocomplete-to-the-software-factory/)
- [Simon Willison - StrongDM Software Factory](https://simonwillison.net/2026/Feb/7/software-factory/)
- [Stanford Law - Built by Agents, Tested by Agents, Trusted by Whom?](https://law.stanford.edu/2026/02/08/built-by-agents-tested-by-agents-trusted-by-whom/)
- [Thoughtworks - Spec-Driven Development](https://www.thoughtworks.com/en-us/insights/blog/agile-engineering-practices/spec-driven-development-unpacking-2025-new-engineering-practices)
- [Martin Fowler - Understanding SDD: Tools](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)
- [Anthropic 2026 Agentic Coding Trends Report](https://resources.anthropic.com/2026-agentic-coding-trends-report)
- [Addy Osmani - How to Write a Good Spec for AI Agents](https://addyosmani.com/blog/good-spec/)
- [ProdMoh - Agentic PRD](https://prodmoh.com/blog/agentic-prd)
- [ICLR 2026 - Adversarial Multi-Agent Debate Evaluation](https://openreview.net/forum?id=06ZvHHBR0i)
- [OWASP Top 10 for Agentic Applications 2026](https://www.practical-devsecops.com/owasp-top-10-agentic-applications/)
- [OpenSSF - Security Guide for AI Code Assistants](https://best.openssf.org/Security-Focused-Guide-for-AI-Code-Assistant-Instructions)
- [IEEE Spectrum - AI Coding Silent Failures](https://spectrum.ieee.org/ai-coding-degrades)

### Case Studies

- **StrongDM**: 3-person team, two products, ~$1,000/day token cost. Rules:
  "Code must not be written by humans. Code must not be reviewed by humans."
  Key innovation: holdout scenarios for specification gaming prevention
  (deferred here as an optional later enhancement after baseline workflow
  stability is proven).
  Digital Twin Universe for external service testing.
- **Anthropic C Compiler**: 16 parallel Claude Opus 4.6 instances, ~2,000
  sessions, 2B input tokens, 100k-line Rust C compiler that builds Linux 6.9
  on x86/ARM/RISC-V. Used a custom looping harness (predated and inspired the
  formal Agent Teams feature). Key lesson: "The task verifier must be nearly
  perfect, otherwise Claude will solve the wrong problem."
- **Anthropic Claude Code Team**: Boris Cherny landed 259 PRs in 30 days
  (497 commits, 40k lines added, 38k removed). ~90% of Claude Code's own
  codebase is written by Claude Code. Workflow: 5-15 parallel sessions, Plan
  mode for design, auto-accept for execution.
- **Perplexity Model Council**: Production deployment of 3-model consensus
  (GPT 5.2, Claude Opus 4.6, Gemini 3.0) with a synthesizer model resolving
  conflicts. Validates the parallel review + synthesis pattern.

---

*Document created: 2026-02-25*
*Last updated: 2026-02-25 — Validated via multi-agent research. Key changes:
single master orchestration skill drives full pipeline (user starts one
conversation), stage-by-stage Superpowers vs custom skill mapping added,
state management and context window strategy defined, failure escalation
per stage, PRD challenge round (3 Claude personas + Codex), QA runbook
machine-generated, two planned user touchpoints (PRD authoring + sign-off) with
explicit exception touchpoints, rejection routing, reviewer retries + adaptive
timeout, Stage 4 semantic-change approval
guard, holdout scenarios deferred as optional future enhancement, Gemini
deferred to future phase, security pipeline corrected, knowledge base added,
regression suite conversion added.*

*Research methodology: 6 parallel Claude Code subagents performed web research
covering: (1) Superpowers plugin architecture and alternatives, (2) multi-model
review patterns and CLI tool readiness, (3) autonomous dev framework landscape,
(4) browser QA automation tooling, (5) security pipeline components, (6) spec-
driven development patterns. Each agent searched the web, GitHub repos, and
academic papers, producing a findings report. Results were synthesized into
corrections and additions applied to this plan. Research session transcripts
are available in the dark-factory conversation history (session 2026-02-25).*

*Status: Draft — validated by research, ready for implementation*
