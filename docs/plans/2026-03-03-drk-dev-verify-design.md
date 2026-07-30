# Design: drk-05-dev-verify + Skill Renaming

**Date:** 2026-03-03
**Status:** Approved

## Problem

Running `drk-code-review` immediately after implementation surfaces incomplete
work — things not built, not tested, not verified. This mirrors a junior
developer submitting a PR without testing their own work first. The code review
should be a second pair of eyes on already-verified work, not the first
indication that something is broken.

## Solution

Add a developer self-verification phase (`drk-05-dev-verify`) between
implementation and code review. This mirrors the developer habit of running the
full test suite and checking the app themselves before opening a PR.

Rename all `drk-*` skills with leading-zero numbers to make pipeline order
explicit and easy to track.

## Pipeline

```
drk-01-prd-interview
drk-02-prd-challenge
drk-03-qa-runbook-gen
drk-04-qa-runbook-validation
  [implementation — superpowers skills]
drk-05-dev-verify          ← NEW
drk-06-code-review
drk-07-qa-acceptance
```

## drk-05-dev-verify Workflow

### Step 1: Resolve Inputs

- Derive feature slug from branch name (strip `feat/`, `fix/`, `chore/` prefixes)
- Locate QA runbook: scan `docs/qa/` for `qa-<slug>.md`
- Discover test runner: check `package.json` scripts (`test`, `test:unit`,
  `test:integration`, `test:e2e`), `Makefile` targets, `pytest`, etc.

### Step 2: Run All Tests

- Execute all discovered test suites (unit, integration, e2e)
- Log each failure to `.claude/tmp/dev-verify-issues.md`
- If no test runner found: warn user and skip (do not block)

### Step 3: Run QA Runbook Inline

- Execute agent-browser commands directly (no chain to drk-07-qa-acceptance)
- Sort test cases by priority: P0 first, then P1, then P2
- Log each TC failure to the same issues doc
- Always close browser session at every exit point

### Step 4: Fix Loop (if failures exist)

For each failure in the issues doc:
1. Apply fix
2. Re-run the specific test or TC to verify
3. Mark resolved in issues doc

- Max 3 attempts per individual failure — surface to user if not converging
- After all failures resolved: run full test suite + full QA runbook to confirm clean
- If the final clean run finds new failures, re-enter the fix loop

### Step 5: Chain to drk-06-code-review

When all tests and QA pass, chain to `drk-06-code-review`.

## Issues Doc Format

Path: `.claude/tmp/dev-verify-issues.md`

```markdown
# Dev Verify Issues: <feature>
**Date:** YYYY-MM-DD
**Branch:** <branch>

## Test Failures
- [ ] `describe > test name` — <failure message> — `path/to/test.ts:42`

## QA Failures
- [ ] TC-001: <name> — Step 3 failed — expected X, got Y

## Resolved
- [x] `describe > test name` — fixed: <one line description>
```

## Failure Handling

| Situation | Behavior |
|-----------|----------|
| Test runner not found | Warn user, skip test phase, continue to QA |
| No QA runbook found | Skip QA phase, run tests only (with warning) |
| App not running for QA | Prompt user to start app before proceeding |
| Fix doesn't converge after 3 attempts | Surface to user, stop fix loop for that item |
| Browser session lost | Close, attempt restart; if restart fails, mark remaining TCs NOT RUN |

## Renaming Scope

### Directory renames (`skills/`)

| Current | New |
|---------|-----|
| `drk-prd-interview/` | `drk-01-prd-interview/` |
| `drk-prd-challenge/` | `drk-02-prd-challenge/` |
| `drk-qa-runbook-gen/` | `drk-03-qa-runbook-gen/` |
| `drk-qa-runbook-validation/` | `drk-04-qa-runbook-validation/` |
| *(new)* | `drk-05-dev-verify/` |
| `drk-code-review/` | `drk-06-code-review/` |
| `drk-qa-acceptance/` | `drk-07-qa-acceptance/` |

### Cross-reference updates

- `drk-04-qa-runbook-validation` Step 8 brainstorming seed: `drk-code-review`
  → `drk-05-dev-verify`
- `drk-06-code-review` Step 7 chain: `drk-qa-acceptance` → `drk-07-qa-acceptance`
- All `name:` front-matter fields updated to match new names
- `manifests/skills.tsv` source paths and target names updated

### Not touched

- Superpowers skills — referenced by full name, no numbers needed
- `agent-browser`, `skill-creator` — not pipeline steps, no numbers needed
- Scripts directories inside each skill — paths are relative, unaffected
