# drk-05-dev-verify + Skill Renaming Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a developer self-verification skill (drk-05-dev-verify) that runs all tests and the QA runbook before code review, and rename all drk- skills with leading-zero numbers.

**Architecture:** Rename six existing skill directories with git mv, updating self-path references and cross-references within each. Create one new skill directory. Update manifests. All changes are in markdown files and a TSV — no code to compile or test in the traditional sense; verification is checking that all path strings and cross-references are correct after each change.

**Tech Stack:** Bash (git mv, grep), Markdown skill files, skills.tsv manifest

---

### Task 1: Rename drk-prd-interview → drk-01-prd-interview

**Files:**
- Rename: `skills/drk-prd-interview/` → `skills/drk-01-prd-interview/`
- Modify: `skills/drk-01-prd-interview/SKILL.md`

**Step 1: Rename the directory**

```bash
git mv skills/drk-prd-interview skills/drk-01-prd-interview
```

**Step 2: Verify the rename**

```bash
ls skills/drk-01-prd-interview/
```
Expected: `SKILL.md` and `references/` directory listed.

**Step 3: Update name field and self-path references in SKILL.md**

In `skills/drk-01-prd-interview/SKILL.md`:

- Line 2: `name: drk-prd-interview` → `name: drk-01-prd-interview`
- Lines 91-92: `drk-prd-interview/references/` → `drk-01-prd-interview/references/` (two occurrences)
- Line 169: `drk-prd-challenge` → `drk-02-prd-challenge`

**Step 4: Verify changes**

```bash
grep -n "drk-prd-interview\|drk-prd-challenge" skills/drk-01-prd-interview/SKILL.md
```
Expected: zero matches for `drk-prd-interview`, one match showing `drk-02-prd-challenge`.

**Step 5: Commit**

```bash
git add skills/drk-01-prd-interview/
git commit -m "refactor: rename drk-prd-interview to drk-01-prd-interview"
```

---

### Task 2: Rename drk-prd-challenge → drk-02-prd-challenge

**Files:**
- Rename: `skills/drk-prd-challenge/` → `skills/drk-02-prd-challenge/`
- Modify: `skills/drk-02-prd-challenge/SKILL.md`

**Step 1: Rename the directory**

```bash
git mv skills/drk-prd-challenge skills/drk-02-prd-challenge
```

**Step 2: Verify the rename**

```bash
ls skills/drk-02-prd-challenge/
```
Expected: `SKILL.md`, `references/`, `scripts/` listed.

**Step 3: Update name field and self-path references in SKILL.md**

In `skills/drk-02-prd-challenge/SKILL.md`:

- Line 2: `name: drk-prd-challenge` → `name: drk-02-prd-challenge`
- Lines 53, 55, 58: `drk-prd-challenge/scripts/` → `drk-02-prd-challenge/scripts/` (three occurrences)
- Lines 134-135: `drk-prd-challenge/references/` → `drk-02-prd-challenge/references/` (two occurrences)

**Step 4: Verify changes**

```bash
grep -n "drk-prd-challenge" skills/drk-02-prd-challenge/SKILL.md
```
Expected: all remaining matches show `drk-02-prd-challenge`, none show `drk-prd-challenge`.

**Step 5: Commit**

```bash
git add skills/drk-02-prd-challenge/
git commit -m "refactor: rename drk-prd-challenge to drk-02-prd-challenge"
```

---

### Task 3: Rename drk-qa-runbook-gen → drk-03-qa-runbook-gen

**Files:**
- Rename: `skills/drk-qa-runbook-gen/` → `skills/drk-03-qa-runbook-gen/`
- Modify: `skills/drk-03-qa-runbook-gen/SKILL.md`
- Modify: `skills/drk-03-qa-runbook-gen/references/runbook-template.md`

**Step 1: Rename the directory**

```bash
git mv skills/drk-qa-runbook-gen skills/drk-03-qa-runbook-gen
```

**Step 2: Verify the rename**

```bash
ls skills/drk-03-qa-runbook-gen/
```
Expected: `SKILL.md`, `references/`, `scripts/` listed.

**Step 3: Update SKILL.md**

In `skills/drk-03-qa-runbook-gen/SKILL.md`:

- Line 2: `name: drk-qa-runbook-gen` → `name: drk-03-qa-runbook-gen`
- Lines 51-52: `drk-qa-runbook-gen/references/` → `drk-03-qa-runbook-gen/references/` (two occurrences)
- Line 83: `drk-qa-acceptance` → `drk-07-qa-acceptance`
- Line 86: `drk-qa-acceptance` → `drk-07-qa-acceptance`
- Lines 127-128: `drk-qa-runbook-gen/references/` → `drk-03-qa-runbook-gen/references/` (two occurrences)
- Line 175: `drk-qa-runbook-validation` → `drk-04-qa-runbook-validation`
- Lines 187-188: `drk-qa-runbook-gen/references/` → `drk-03-qa-runbook-gen/references/` (two occurrences)

**Step 4: Update runbook-template.md**

In `skills/drk-03-qa-runbook-gen/references/runbook-template.md`:

- Line 22: `drk-qa-acceptance` → `drk-07-qa-acceptance`
- Line 28: `drk-qa-runbook-gen/references/spec-guardian-rules.md` → `drk-03-qa-runbook-gen/references/spec-guardian-rules.md`

**Step 5: Verify changes**

```bash
grep -n "drk-qa-runbook-gen\|drk-qa-acceptance\|drk-qa-runbook-validation" \
  skills/drk-03-qa-runbook-gen/SKILL.md \
  skills/drk-03-qa-runbook-gen/references/runbook-template.md
```
Expected: all matches show the new numbered names, zero matches for old names.

**Step 6: Commit**

```bash
git add skills/drk-03-qa-runbook-gen/
git commit -m "refactor: rename drk-qa-runbook-gen to drk-03-qa-runbook-gen"
```

---

### Task 4: Rename drk-qa-runbook-validation → drk-04-qa-runbook-validation

**Files:**
- Rename: `skills/drk-qa-runbook-validation/` → `skills/drk-04-qa-runbook-validation/`
- Modify: `skills/drk-04-qa-runbook-validation/SKILL.md`
- Modify: `skills/drk-04-qa-runbook-validation/references/semantic-classification-rules.md`

**Step 1: Rename the directory**

```bash
git mv skills/drk-qa-runbook-validation skills/drk-04-qa-runbook-validation
```

**Step 2: Verify the rename**

```bash
ls skills/drk-04-qa-runbook-validation/
```
Expected: `SKILL.md`, `references/`, `scripts/` listed.

**Step 3: Update SKILL.md**

In `skills/drk-04-qa-runbook-validation/SKILL.md`:

Find the script path block (around line 54-67) and update all three occurrences:
- `drk-qa-runbook-validation/scripts/` → `drk-04-qa-runbook-validation/scripts/`

Find references to other skills and update:
- `name: drk-qa-runbook-validation` → `name: drk-04-qa-runbook-validation`
- Line 23: `drk-qa-runbook-gen` → `drk-03-qa-runbook-gen`
- Line 170: `drk-code-review` → `drk-05-dev-verify` (**key change — this seeds the implementation plan chain**)
- Line 172 (the note in the seed message): `drk-code-review` → `drk-05-dev-verify`
- Line 178: `drk-qa-runbook-validation` self-ref → `drk-04-qa-runbook-validation`
- Line 181: `drk-qa-runbook-gen` → `drk-03-qa-runbook-gen`
- Line 184: `drk-prd-interview` → `drk-01-prd-interview`
- References notes at bottom: `drk-qa-runbook-validation/references/` → `drk-04-qa-runbook-validation/references/`

**Step 4: Update semantic-classification-rules.md**

In `skills/drk-04-qa-runbook-validation/references/semantic-classification-rules.md`:

- Line 28: `drk-qa-runbook-gen/references/spec-guardian-rules.md` → `drk-03-qa-runbook-gen/references/spec-guardian-rules.md`

**Step 5: Verify changes**

```bash
grep -n "drk-qa-runbook-validation\|drk-qa-runbook-gen\|drk-code-review\|drk-prd-interview" \
  skills/drk-04-qa-runbook-validation/SKILL.md \
  skills/drk-04-qa-runbook-validation/references/semantic-classification-rules.md
```
Expected:
- `drk-qa-runbook-validation` only appears as `drk-04-qa-runbook-validation`
- `drk-qa-runbook-gen` only appears as `drk-03-qa-runbook-gen`
- `drk-code-review` does not appear — replaced with `drk-05-dev-verify`
- `drk-prd-interview` only appears as `drk-01-prd-interview`

**Step 6: Commit**

```bash
git add skills/drk-04-qa-runbook-validation/
git commit -m "refactor: rename drk-qa-runbook-validation to drk-04-qa-runbook-validation"
```

---

### Task 5: Create drk-05-dev-verify

**Files:**
- Create: `skills/drk-05-dev-verify/SKILL.md`

**Step 1: Create the skill directory**

```bash
mkdir -p skills/drk-05-dev-verify
```

**Step 2: Write the SKILL.md**

Create `skills/drk-05-dev-verify/SKILL.md` with this exact content:

````markdown
---
name: drk-05-dev-verify
description: "Developer self-verification before code review: runs all tests and QA runbook inline, logs failures, fixes them in a loop, then chains to drk-06-code-review. Use after implementation is complete and before submitting for multi-model code review."
---

# Developer Self-Verification

Run all tests and the QA acceptance runbook against your implementation before
submitting for code review. Mirrors a developer testing their own work before
opening a PR. Logs failures, fixes them inline with verification, and chains
to drk-06-code-review when everything passes.

## Prerequisites

- Feature branch checked out with implementation nominally complete
- PRD (`docs/prd-<feature>.md`) and QA runbook (`docs/qa/qa-<feature>.md`) exist
- agent-browser available (`agent-browser --version`)
- Application running and accessible at the QA runbook's `base_url`

## Workflow

### Step 1: Resolve Inputs

**Derive feature slug from branch name:**
Strip common prefixes (`feat/`, `feature/`, `fix/`, `chore/`). Use the
remainder as the slug (e.g., `feat/user-auth` → `user-auth`).

**Locate QA runbook:**
1. Scan `docs/qa/` for `qa-<slug>.md`
2. If no exact match: list candidate files and ask the user to confirm

**Discover test runner** by checking in order:
1. `package.json` scripts: `test`, `test:unit`, `test:integration`, `test:e2e`
2. `Makefile` targets: `test`, `test-unit`, `test-integration`, `test-e2e`
3. `pytest.ini`, `pyproject.toml`, or `setup.cfg` in the repo root (Python)
4. If multiple runners found, record all of them — run each one
5. If none found: warn the user and skip the test phase (do not block)

**Initialize issues doc:**

```bash
mkdir -p .claude/tmp
```

Create `.claude/tmp/dev-verify-issues.md`:

```markdown
# Dev Verify Issues: <feature>
**Date:** <YYYY-MM-DD>
**Branch:** <branch>

## Test Failures

## QA Failures

## Resolved
```

### Step 2: Run All Tests

For each discovered test runner, execute the full suite. For each failure:
- Append to `## Test Failures` in `.claude/tmp/dev-verify-issues.md`
- Format: `- [ ] \`<suite> > <test name>\` — <failure message> — \`<file:line>\``

Continue running all suites even after failures — collect everything before
moving on.

### Step 3: Run QA Runbook Inline

**Parse the QA runbook:**
Read the runbook file. Extract:
- YAML frontmatter: `base_url`, `timeout` (default 30000 if missing)
- All test cases sorted by priority: P0 first, then P1, then P2

**Verify app is running:**

```bash
agent-browser open <base_url>
agent-browser wait --load networkidle --timeout <timeout>
agent-browser snapshot -i
```

If the snapshot shows an error page or the app is unreachable:
1. Run `agent-browser close`
2. Log a warning to `.claude/tmp/dev-verify-issues.md` under `## QA Failures`:
   `- [ ] [APP NOT RUNNING] Cannot reach <base_url> — start the app and re-run drk-05-dev-verify`
3. Skip remaining QA steps and proceed to Step 4

**Execute each test case** using the same execution rules as drk-07-qa-acceptance:
- Navigate to starting page, execute each step, run assertions
- Use `agent-browser snapshot -i` for interactive elements; `agent-browser snapshot`
  (no `-i`) for non-interactive assertions
- Wait with `agent-browser wait --load networkidle --timeout <timeout>` after
  every navigation or interaction; fall back to `agent-browser wait 2000` if
  networkidle times out (log a warning)
- Re-snapshot after every interaction that changes the page
- On step failure within a TC: mark the TC FAIL, skip remaining steps in that TC,
  continue to next TC
- Single retry for interaction failures (`click`/`fill`/`select`): wait 2s,
  re-snapshot, retry once. Never retry assertion failures.

For each TC failure:
- Append to `## QA Failures` in `.claude/tmp/dev-verify-issues.md`
- Format: `- [ ] TC-<id>: <name> — Step <N> failed — expected <X>, got <Y>`

**Always close the browser when done** (success, failure, or interruption):

```bash
agent-browser close
```

### Step 4: Fix Loop

If `.claude/tmp/dev-verify-issues.md` has no unchecked items (`- [ ]`) in
`## Test Failures` or `## QA Failures`, skip directly to Step 5.

For each unchecked item, work through failures one at a time:

**a. Apply fix**
Read the failure details and locate the relevant code. Apply the minimal fix
needed. Do not fix multiple unrelated failures in a single edit.

**b. Re-run the specific failing check**
- For a test failure: run only the specific test (not the full suite)
  e.g., `npm test -- --testNamePattern "failing test name"` or
  `pytest tests/path/test.py::test_name -v`
- For a QA TC failure: open agent-browser, navigate to the relevant page,
  re-execute only that TC's steps and assertions, then close browser

**c. Mark result**
- If passes: move item from its section to `## Resolved` with `[x]` and one-line
  description of the fix
  e.g., `- [x] \`suite > test\` — fixed: added null check in getUserById`
- If still fails after 3 attempts: mark with `[!]` in place
  e.g., `- [!] TC-003: checkout flow — 3 attempts, not converging`
  Do not loop further on that item.

**Convergence check after all items addressed:**
Run the full test suite and the full QA runbook (Steps 2 and 3). If new
failures appear (regressions introduced by fixes), add them to the issues doc
and re-enter the fix loop for those new items only.

### Step 5: Check for Unresolved Items

Scan `.claude/tmp/dev-verify-issues.md` for items marked `[!]`.

If any `[!]` items exist:
- Present them to the user with failure details
- Ask: proceed to drk-06-code-review anyway, or stop to investigate?
- Treat any affirmative response as proceed; any other response as stop

If no `[!]` items: proceed silently.

### Step 6: Chain to drk-06-code-review

Trigger `drk-06-code-review`.

## Notes

- The issues doc at `.claude/tmp/dev-verify-issues.md` is a working scratch
  file — it is not committed
- Run QA inline (not by chaining to drk-07-qa-acceptance) to keep the fix loop
  in a single context with all failures visible
- `agent-browser close` must run at every exit point — after Step 3 success,
  after app-not-running bail-out, and after any unexpected error
- This skill verifies the developer's own work before review, not after. The
  multi-model code review in drk-06-code-review is a second opinion on
  already-verified work.
- **Safety guard**: only run QA against local/dev/test hosts (`localhost`,
  `127.0.0.1`, `::1`, `.local`, `.test`, `.dev`). If `base_url` looks
  production-like, stop and ask for a non-production URL.
````

**Step 3: Verify the file was created**

```bash
ls skills/drk-05-dev-verify/
grep "^name:" skills/drk-05-dev-verify/SKILL.md
```
Expected: `SKILL.md` listed; name shows `drk-05-dev-verify`.

**Step 4: Commit**

```bash
git add skills/drk-05-dev-verify/
git commit -m "feat: add drk-05-dev-verify developer self-verification skill"
```

---

### Task 6: Rename drk-code-review → drk-06-code-review

**Files:**
- Rename: `skills/drk-code-review/` → `skills/drk-06-code-review/`
- Modify: `skills/drk-06-code-review/SKILL.md`

**Step 1: Rename the directory**

```bash
git mv skills/drk-code-review skills/drk-06-code-review
```

**Step 2: Verify the rename**

```bash
ls skills/drk-06-code-review/
```
Expected: `SKILL.md`, `references/`, `scripts/` listed.

**Step 3: Update SKILL.md**

In `skills/drk-06-code-review/SKILL.md`:

- Line 2: `name: drk-code-review` → `name: drk-06-code-review`
- Line 3 (description): `chains to drk-qa-acceptance` → `chains to drk-07-qa-acceptance`
- Line 11: `drk-qa-acceptance` → `drk-07-qa-acceptance`
- Lines 54, 56, 59: `drk-code-review/references` → `drk-06-code-review/references` (three occurrences)
- Lines 85, 87, 90: `drk-code-review/scripts/run_codex_quality_review.sh` → `drk-06-code-review/scripts/run_codex_quality_review.sh` (three occurrences)
- Lines 102, 104, 107: `drk-code-review/scripts/run_codex_spec_review.sh` → `drk-06-code-review/scripts/run_codex_spec_review.sh` (three occurrences)
- Line 205: `Trigger \`drk-qa-acceptance\`` → `Trigger \`drk-07-qa-acceptance\``
- Lines 209-211: `drk-code-review/references/` → `drk-06-code-review/references/` (three occurrences)

**Step 4: Verify changes**

```bash
grep -n "drk-code-review\|drk-qa-acceptance" skills/drk-06-code-review/SKILL.md
```
Expected: all matches show `drk-06-code-review` or `drk-07-qa-acceptance`; zero matches for old names.

**Step 5: Commit**

```bash
git add skills/drk-06-code-review/
git commit -m "refactor: rename drk-code-review to drk-06-code-review"
```

---

### Task 7: Rename drk-qa-acceptance → drk-07-qa-acceptance

**Files:**
- Rename: `skills/drk-qa-acceptance/` → `skills/drk-07-qa-acceptance/`
- Modify: `skills/drk-07-qa-acceptance/SKILL.md`

**Step 1: Rename the directory**

```bash
git mv skills/drk-qa-acceptance skills/drk-07-qa-acceptance
```

**Step 2: Verify the rename**

```bash
ls skills/drk-07-qa-acceptance/
```
Expected: `SKILL.md` listed.

**Step 3: Update SKILL.md**

In `skills/drk-07-qa-acceptance/SKILL.md`:

- Line 2: `name: drk-qa-acceptance` → `name: drk-07-qa-acceptance`
- Line 14: `drk-qa-runbook-gen` → `drk-03-qa-runbook-gen`

**Step 4: Verify changes**

```bash
grep -n "drk-qa-acceptance\|drk-qa-runbook-gen" skills/drk-07-qa-acceptance/SKILL.md
```
Expected: `drk-qa-acceptance` only appears as `drk-07-qa-acceptance`; `drk-qa-runbook-gen` only appears as `drk-03-qa-runbook-gen`.

**Step 5: Commit**

```bash
git add skills/drk-07-qa-acceptance/
git commit -m "refactor: rename drk-qa-acceptance to drk-07-qa-acceptance"
```

---

### Task 8: Update manifests/skills.tsv

**Files:**
- Modify: `manifests/skills.tsv`

**Step 1: Update all drk- entries**

In `manifests/skills.tsv`, update each drk- line to use the new directory name as both source path and target name:

| Old source_path | New source_path | Old target_name | New target_name |
|----------------|----------------|----------------|----------------|
| `skills/drk-prd-interview` | `skills/drk-01-prd-interview` | `drk-prd-interview` | `drk-01-prd-interview` |
| `skills/drk-prd-challenge` | `skills/drk-02-prd-challenge` | `drk-prd-challenge` | `drk-02-prd-challenge` |
| `skills/drk-qa-runbook-gen` | `skills/drk-03-qa-runbook-gen` | `drk-qa-runbook-gen` | `drk-03-qa-runbook-gen` |
| `skills/drk-qa-runbook-validation` | `skills/drk-04-qa-runbook-validation` | `drk-qa-runbook-validation` | `drk-04-qa-runbook-validation` |
| *(add new row)* | `skills/drk-05-dev-verify` | *(add new row)* | `drk-05-dev-verify` |
| `skills/drk-code-review` | `skills/drk-06-code-review` | `drk-code-review` | `drk-06-code-review` |
| `skills/drk-qa-acceptance` | `skills/drk-07-qa-acceptance` | `drk-qa-acceptance` | `drk-07-qa-acceptance` |

The new row for drk-05-dev-verify should be inserted between the drk-04 and drk-06 rows:
```
claude	skills/drk-05-dev-verify	drk-05-dev-verify
```

**Step 2: Verify the manifest**

```bash
grep "drk-" manifests/skills.tsv
```
Expected: 7 drk- rows, all with numbered names, in order 01 through 07. No old unnumbered names.

**Step 3: Commit**

```bash
git add manifests/skills.tsv
git commit -m "refactor: update skills manifest for numbered drk- skill names"
```

---

### Task 9: Final verification and sync

**Step 1: Check no old drk- names remain in the skills directory**

```bash
grep -rn "drk-prd-interview\|drk-prd-challenge\|drk-qa-runbook-gen\b\|drk-qa-runbook-validation\b\|drk-code-review\|drk-qa-acceptance\b" \
  skills/ --include="*.md"
```
Expected: zero matches. (The `\b` word boundary prevents matching the numbered versions.)

**Step 2: Check the key chain update landed correctly**

```bash
grep -n "drk-05-dev-verify" skills/drk-04-qa-runbook-validation/SKILL.md
```
Expected: at least one match on line ~170 in the brainstorming seed message.

**Step 3: Check drk-06-code-review chains to drk-07**

```bash
grep -n "drk-07-qa-acceptance" skills/drk-06-code-review/SKILL.md
```
Expected: matches on the description line, the narrative line, and Step 7.

**Step 4: Sync to global**

```bash
bash scripts/sync-to-global.sh
```
Expected: output shows all 7 drk- skill directories copied.

**Step 5: Verify global install has new names**

```bash
ls ~/.claude/skills/ | grep drk-
```
Expected: `drk-01-prd-interview`, `drk-02-prd-challenge`, `drk-03-qa-runbook-gen`, `drk-04-qa-runbook-validation`, `drk-05-dev-verify`, `drk-06-code-review`, `drk-07-qa-acceptance` — no old unnumbered names.

**Step 6: Commit if sync script modified any tracked files**

```bash
git status
```
If clean, no commit needed. If the sync script writes anything tracked, commit it.
