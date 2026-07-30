# Code Review & Sign-off Handoff — Design Document

**Date:** 2026-03-03
**Status:** Approved

## Scope

Two related changes:

1. **`drk-qa-runbook-validation` handoff (Step 8)** — add user sign-off and
   chain to `superpowers:brainstorming` so the pipeline continues automatically
   after validation instead of requiring manual triggering.

2. **`drk-code-review` (new skill)** — post-implementation multi-model code
   review with 5 parallel reviewers, user decision step, and chain to
   `drk-qa-acceptance`.

---

## Part 1: `drk-qa-runbook-validation` — Step 8 Sign-off Handoff

### What's Missing

The current skill ends at Step 7 (Output) with a commit and summary message.
The user then had to manually invoke `superpowers:brainstorming` with the PRD
and QA runbook paths. This step adds the missing Stage 5 handoff.

### Design

Add **Step 8: User Sign-off** after the current Step 7:

1. Present the sign-off package:
   - PRD path and QA runbook path
   - Validation report path
   - Count of auto-applied fixes
   - List of any pending semantic proposals (from Step 5)
2. Ask the user to approve or reject with feedback.
3. **On approve**: chain to `superpowers:brainstorming` with:
   - PRD path as context
   - QA runbook path as context
   - Instruction: "The PRD and QA runbook are approved. Plan the technical
     implementation of this feature."
4. **On reject**: classify the feedback and route accordingly:
   - **QA-only** ("this scenario is wrong", "missing a flow") → update QA
     runbook → re-run `drk-qa-runbook-validation` → return to sign-off
   - **PRD tweak** ("change this requirement", "misunderstood X") → update
     PRD → re-run `drk-qa-runbook-gen` → re-run validation → return to
     sign-off
   - **Major scope change** ("rethink the whole approach") → back to
     `drk-prd-interview` for a focused re-interview

The rejection routing classification is suggested by the skill based on the
user's feedback, then confirmed explicitly before execution.

---

## Part 2: `drk-code-review` (New Skill)

### Pipeline Position

```
Implementation (TDD via Superpowers)
    ↓ manually triggered (until master orchestration exists)
drk-code-review   ← THIS SKILL
    ↓ auto-chains after fixes applied
drk-qa-acceptance
```

### Architecture: Standalone Skill

Same pattern as all other `drk-` skills — standalone `SKILL.md` with
reference files and Codex scripts. No shared orchestration layer (same
decision made for `drk-qa-runbook-validation`).

### 5 Parallel Reviewers

| # | Type | Axis | Input |
|---|------|------|-------|
| 1 | Claude sub-agent | Code Quality & Correctness | Branch diff + codebase |
| 2 | Claude sub-agent | Security Hardening | Branch diff + codebase |
| 3 | Claude sub-agent | Spec Compliance | Branch diff + PRD + QA runbook |
| 4 | Codex CLI | Code Quality & Correctness | Branch diff |
| 5 | Codex CLI | Spec Compliance | Branch diff + PRD + QA runbook |

Claude sub-agents run via Task tool calls. Codex reviewers run as Bash
commands. All 5 launch in a single message.

### Workflow

**Step 1: Resolve Inputs**

- Detect current feature branch (`git branch --show-current`)
- Locate PRD: scan `docs/` for `prd-<feature-slug>.md` with Status: Approved
- Locate QA runbook: scan `docs/qa/` for `qa-<feature-slug>.md`
- If multiple matches or no match, ask user to specify paths
- Compute branch diff base: `git merge-base HEAD main` for the base ref

**Step 2: Launch 5 Parallel Reviewers**

In a single message:

- **Claude Quality sub-agent**: review diff + codebase using
  `references/claude-quality-prompt.md`. Output: `## Findings — Claude Quality`
- **Claude Security sub-agent**: review diff + codebase using
  `references/claude-security-prompt.md`. Output: `## Findings — Claude Security`
- **Claude Spec sub-agent**: review diff + PRD + QA runbook using
  `references/claude-spec-compliance-prompt.md`. Output:
  `## Findings — Claude Spec`
- **Codex Quality** (Bash, 10min timeout): `run_codex_quality_review.sh
  <base-ref> <output-path>`
- **Codex Spec** (Bash, 10min timeout): `run_codex_spec_review.sh <prd-path>
  <qa-path> <base-ref> <output-path>`

If a Codex reviewer fails: note the failure and continue with the remaining
4 reviewers. Unlike `drk-qa-runbook-validation`, partial Codex failure is
tolerated (5 reviewers provide sufficient coverage even with one Codex
failure). If both Codex reviewers fail, halt and notify the user.

**Step 3: Synthesize**

Using `references/synthesis-prompt.md`:
- Deduplicate across all 5 sources
- Tag each finding with sources: `[Claude Quality]`, `[Claude Security]`,
  `[Claude Spec]`, `[Codex Quality]`, `[Codex Spec]`, or combinations
- Severity-rank: Critical / High / Medium / Low
- For each finding, produce a concrete recommended action (not just a
  description of the problem)

**Step 4: Write Review Report**

Write the severity-ranked findings + recommendations to:
`docs/reviews/code-review/<timestamp>-<feature>-code-review.md`

Report structure:
```
# Code Review: <Feature Name>
**Date:** YYYY-MM-DD
**Branch:** <branch-name>
**Base:** <merge-base>
**PRD:** <prd-path>
**QA Runbook:** <qa-path>
**Reviewers:** Claude Quality, Claude Security, Claude Spec, Codex Quality, Codex Spec

## Summary
X Critical, Y High, Z Medium, W Low findings.

## Findings

### [Critical] <Finding Title>
**Sources:** [Claude Quality] [Codex Quality]
**Location:** `path/to/file.ts:42`
**Issue:** <description>
**Recommendation:** <concrete proposed fix>

### [High] <Finding Title>
...

## Medium / Low (reference)
| Severity | Title | Sources | Location |
|----------|-------|---------|----------|
| Medium | ... | ... | ... |
```

Tell the user: "Review at `docs/reviews/code-review/<path>`. Reply with your
decisions on each finding (approve recommendation / adjust / skip)."

**Step 5: Apply User Decisions**

After the user responds with decisions:
- Implement all approved and adjusted fixes using
  `superpowers:receiving-code-review` discipline:
  - Verify each fix against the codebase before applying
  - Push back (with reasoning) if a fix is technically incorrect for this
    codebase
  - Apply one fix at a time, run tests after each
- Skip findings the user marked skip
- Medium/Low findings from the report are reference-only — not applied unless
  user explicitly approves them

**Step 6: Commit and Report**

```
git add <changed files>
git commit -m "fix: apply code review fixes for <feature>"
```

Report: "N fixes applied. Tests passing. Report at `<path>`."

**Step 7: Chain to QA Acceptance**

Trigger `drk-qa-acceptance` with the QA runbook path.

### Skill Structure

```
skills/drk-code-review/
  SKILL.md
  scripts/
    run_codex_quality_review.sh     # Codex: code quality axis
    run_codex_spec_review.sh        # Codex: spec compliance axis (reads PRD+QA)
  references/
    claude-quality-prompt.md        # Code Quality & Correctness persona
    claude-security-prompt.md       # Security Hardening persona
    claude-spec-compliance-prompt.md # Spec Compliance persona
    synthesis-prompt.md             # Merge 5 reviews, deduplicate, rank
```

### Key Design Decisions

**Why 5 reviewers instead of 4 (like prd-challenge)**

Two Codex reviewers cover the two primary axes independently (quality vs.
spec compliance). This gives model diversity on both axes, not just overall.
A single Codex reviewer would have to split attention across both axes.

**Findings as a file, not inline**

The review report is written to disk before the user decision step. This
matches how the validation report works in `drk-qa-runbook-validation` and
makes it easy for the user to parse findings in their editor rather than
scrolling through conversation history.

**Medium/Low are reference-only by default**

Critical/High are the actionable items. Medium/Low are included in the report
table for awareness but not surfaced as decision items — the user can promote
them explicitly if they want.

**Receiving-code-review discipline during fix application**

The `superpowers:receiving-code-review` skill enforces verification-before-
application and pushback-when-wrong. This prevents blindly applying reviewer
suggestions that don't actually fit the codebase.

**Partial Codex failure tolerance**

With 5 reviewers, losing one Codex reviewer still leaves 4 perspectives.
Both Codex failing triggers a halt because it removes all model diversity
(leaving only Claude perspectives).

---

## Manifest and Sync

Add to `manifests/skills.tsv`:
```
claude    skills/drk-code-review    drk-code-review
```

Run `bash scripts/sync-to-global.sh` after implementation.
