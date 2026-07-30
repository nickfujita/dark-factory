# QA Runbook Validation Skill — Design Document

**Date:** 2026-03-02
**Stage:** 4 (Multi-model Validation)
**Status:** Approved

## Purpose

Formal review of the finished PRD + QA runbook pair before presenting to the
user for sign-off. Lighter than the PRD challenge round (Stage 2) because the
PRD was already stress-tested by 4 reviewers. This skill validates that the
QA runbook is complete, consistent with the PRD, and testable as written.

## Context

This fills the gap between Stage 3 (qa-runbook-gen) and Stage 5 (user
sign-off) in the Dark Factory pipeline. Currently qa-runbook-gen stops after
generating the runbook with no handoff. This skill adds the missing Stage 4
validation and chains it from qa-runbook-gen.

### Pipeline Position

```
Stage 2: prd-challenge (built)
    ↓ user manually triggers
Stage 3: qa-runbook-gen (built)
    ↓ auto-chains to (NEW handoff)
Stage 4: qa-runbook-validation (THIS SKILL)
    ↓ outputs packaged results
Stage 5: User sign-off (future)
```

## Architecture Decisions

### 2 reviewers, not 4

The PRD was already stress-tested by 3 Claude personas + Codex in the
challenge round. Stage 4 validates the PRD+QA **pair**, not the PRD alone.
Two reviewers (1 Claude inline + 1 Codex CLI) provide model diversity without
redundant re-review of the PRD.

### Standalone skill, not multi-model-review

The Dark Factory plan describes a shared `multi-model-review` skill with
`validation` and `branch` modes. We build the validation use case as a
standalone `qa-runbook-validation` skill instead. Rationale: branch mode has
different inputs (diff vs documents), different review criteria, and different
output handling. We avoid premature abstraction. Shared infrastructure can be
factored out later when branch mode is actually built.

### Auto-apply non-semantic fixes

Non-semantic fixes (formatting, traceability links, wording clarity) are
applied directly to the PRD and QA runbook files. Semantic changes are
packaged as proposed diffs for user review. This follows the Dark Factory
plan's specification and keeps Stage 4 autonomous (no user interaction until
sign-off).

### Chain from qa-runbook-gen

A new handoff step is added to the end of `qa-runbook-gen/SKILL.md`, mirroring
the `prd-interview` → `prd-challenge` pattern. The user can defer the trigger
explicitly.

## Skill Structure

```
skills/qa-runbook-validation/
  SKILL.md                                    # Orchestration instructions
  scripts/
    run_codex_qa_validation.sh                # Codex CLI invocation
  references/
    claude-review-prompt.md                   # Claude's review instructions
    synthesis-prompt.md                       # How to merge 2 reviews
    semantic-classification-rules.md          # What's auto-fixable vs. proposed
```

## Input / Output

**Input:**
- PRD path (`docs/prd-<feature>.md`) — status must be "Approved"
- QA runbook path (`docs/qa/qa-<feature>.md`)

**Output:**
- Validation report at `docs/reviews/qa-validation/<timestamp>-<feature>-validation.md`
- Auto-applied non-semantic fixes directly to the PRD and QA runbook files
- Proposed semantic changes included in the validation report

## Workflow (SKILL.md Steps)

### Step 1: Resolve Inputs

- Accept PRD path and QA runbook path (passed from qa-runbook-gen handoff, or
  ask user if invoked standalone)
- Validate both files exist and PRD status is "Approved"
- Read both documents into context

### Step 2: Launch Parallel Reviews (Round 1)

In a single message, dispatch both reviewers:

**Claude review (inline):** Using `references/claude-review-prompt.md`, review
the PRD+QA pair for:
- Bidirectional coverage: every REQ/NEG has TCs, every TC traces to a REQ/NEG
- Consistency: test steps actually verify what acceptance criteria say
- Testability: preconditions realistic, steps executable as written
- Completeness: edge cases, error states, negative requirements all covered

**Codex review (Bash, 10min timeout):**
`run_codex_qa_validation.sh <prd-path> <qa-path>` writes to
`.claude/tmp/codex-qa-validation-review.md`

### Step 3: Synthesize Findings

Using `references/synthesis-prompt.md`:
- Merge both reviews, deduplicate, tag sources: `[Claude]` / `[Codex]` /
  `[Claude + Codex]`
- Classify each finding as **semantic** or **non-semantic** using
  `references/semantic-classification-rules.md`
- Severity rank: Critical / High / Medium / Low
- If Codex failed: proceed with Claude-only findings (graceful degradation,
  same pattern as prd-challenge)

### Step 4: Auto-Apply Non-Semantic Fixes

- Apply formatting, wording clarity, traceability link corrections,
  deduplication directly to the PRD and QA runbook files
- Record each change in the validation report under an "Auto-Applied Fixes"
  section

### Step 5: Package Semantic Findings

- Semantic changes written as proposed diffs in the validation report
- Each proposed change includes: the finding, severity, source tag, the
  affected requirement/TC, and the specific proposed edit

### Step 6: Check for Additional Rounds

If there are unresolved critical contradictions between Claude and Codex (one
says Critical, the other says no issue on the same item):
- Re-run both Claude and Codex reviews in parallel on the updated documents
- Synthesize again, auto-apply non-semantic fixes, package semantic findings
- **Max 3 rounds total.** If contradictions persist after round 3, flag
  remaining issues for user review in the validation report and stop.

### Step 7: Output

1. Save validation report to
   `docs/reviews/qa-validation/<timestamp>-<feature>-validation.md`
2. Git commit the auto-applied fixes + validation report:
   `docs: QA runbook validation complete for <feature>`
3. Report summary:
   "Validation complete in N round(s). X non-semantic fixes auto-applied.
   Y semantic findings for user review. Report at `<path>`."

## Semantic Classification Rules

### Non-Semantic (auto-fixable)

- Formatting inconsistencies (markdown structure, heading levels, list styles)
- Wording clarity improvements that don't change meaning
- Fixing/adding traceability links (e.g., TC references REQ-003 but says REQ-3)
- Deduplication of test cases that test the same thing
- Fixing YAML frontmatter fields (dates, IDs, paths)

### Semantic (proposed as diffs)

- Adding, removing, or changing a requirement
- Changing the meaning of an acceptance criterion
- Adding or removing a test case
- Changing what a test case verifies (different expected outcome)
- Scope changes (new user flows, removed functionality)
- Changing preconditions in a way that affects test validity

## Codex Script Design

`scripts/run_codex_qa_validation.sh` follows the same pattern as
`prd-challenge/scripts/run_codex_prd_review.sh`:

- **Args:** `<prd-path> <qa-path> <output-path>`
- **Invocation:** `codex exec --skip-git-repo-check --sandbox read-only
  --config model_reasoning_effort=high -C "$repo_root"`
- **Prompt:** Review the PRD+QA pair for coverage, consistency, testability,
  completeness. Output findings in severity-ranked format with `[Codex]` tags.
- **Exit handling:** Capture exit code explicitly. On failure, write failure
  note to output file for synthesis to see. Do not abort.
- **Post-run validation:** Check for expected headers in output.
- **Script path resolution:** 3-location fallback matching prd-challenge
  pattern: `$HOME/.claude/skills/`, `<repo>/skills/`,
  `<repo>/.claude/skills/`

## qa-runbook-gen Handoff

Add to `skills/qa-runbook-gen/SKILL.md` after the current final step:

```markdown
### Step 7: Trigger Validation

After the QA runbook is generated, trigger the `qa-runbook-validation` skill
with both paths:
- PRD path: the source PRD used for generation
- QA runbook path: the just-generated runbook

Only skip this trigger if the user explicitly asks to defer it.
```

## Manifest Update

Add to `manifests/skills.tsv`:

```
claude    skills/qa-runbook-validation    qa-runbook-validation
```

## Testing Strategy

Test by running the full pipeline on a real feature PRD in a target project
repo:
1. Generate a QA runbook from an approved PRD (qa-runbook-gen)
2. Verify the handoff triggers qa-runbook-validation automatically
3. Verify both reviewers run and produce findings
4. Verify non-semantic fixes are applied directly
5. Verify semantic findings appear as proposed diffs in the report
6. Verify graceful degradation when Codex is unavailable
