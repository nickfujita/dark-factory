# QA Runbook Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the `qa-runbook-validation` skill (Stage 4) that validates a PRD+QA runbook pair using parallel Claude + Codex reviews, auto-applies non-semantic fixes, and chains from `qa-runbook-gen`.

**Architecture:** Standalone skill following the `prd-challenge` pattern — SKILL.md orchestrates 1 inline Claude review + 1 Codex CLI review (via bash script) in parallel. Up to 3 rounds. Reference files define review prompts, synthesis rules, and semantic classification.

**Tech Stack:** Bash (Codex script), Markdown (SKILL.md + reference files)

---

### Task 1: Create Skill Directory Structure

**Files:**
- Create: `skills/qa-runbook-validation/SKILL.md` (placeholder)
- Create: `skills/qa-runbook-validation/scripts/` (directory)
- Create: `skills/qa-runbook-validation/references/` (directory)

**Step 1: Create the directory tree**

Run:
```bash
mkdir -p skills/qa-runbook-validation/scripts skills/qa-runbook-validation/references
```

**Step 2: Create placeholder SKILL.md**

Create `skills/qa-runbook-validation/SKILL.md`:
```markdown
---
name: qa-runbook-validation
description: "Validate a PRD + QA runbook pair using parallel Claude and Codex reviews. Use after qa-runbook-gen completes, or when the user asks to validate a QA runbook against its PRD. Auto-applies non-semantic fixes and surfaces semantic findings for user review."
---

# QA Runbook Validation

(Implementation in progress)
```

**Step 3: Commit**

```bash
git add skills/qa-runbook-validation/
git commit -m "feat: scaffold qa-runbook-validation skill directory"
```

---

### Task 2: Write the Codex Validation Script

**Files:**
- Create: `skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh`
- Reference: `skills/prd-challenge/scripts/run_codex_prd_review.sh` (pattern to follow)

**Step 1: Write the script**

Create `skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_qa_validation.sh <prd-path> <qa-path> <output-path>
# Runs a Codex CLI review of a PRD + QA runbook pair and writes findings
# to the output path. Designed for the Stage 4 validation step —
# produces structured findings compatible with the synthesis step.

if [[ $# -lt 3 ]]; then
  echo "Usage: run_codex_qa_validation.sh <prd-path> <qa-path> <output-path>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

prd_path="$1"
qa_path="$2"
out_path="$3"

if [[ "$prd_path" != /* ]]; then
  prd_path="$repo_root/$prd_path"
fi
if [[ "$qa_path" != /* ]]; then
  qa_path="$repo_root/$qa_path"
fi

if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi
if [[ ! -f "$qa_path" ]]; then
  echo "Error: QA runbook file not found at $qa_path" >&2
  exit 1
fi

prd_rel="${prd_path#"$repo_root"/}"
if [[ "$prd_rel" == "$prd_path" ]]; then
  prd_rel="$(basename "$prd_path")"
fi

qa_rel="${qa_path#"$repo_root"/}"
if [[ "$qa_rel" == "$qa_path" ]]; then
  qa_rel="$(basename "$qa_path")"
fi

prompt="$(cat <<'PROMPT'
You are an independent reviewer examining a PRD (Product Requirements Document)
and its corresponding QA acceptance runbook as a pair. Your goal is to find
gaps, contradictions, and coverage issues between the two documents.

Review BOTH documents together and produce findings in this exact format:

## Findings — Codex

### [SEVERITY]: [One-line finding title]
**Category:** [Coverage | Consistency | Testability | Completeness]
**Requirement:** [Which REQ-xxx, NEG-xxx, or TC-xxx this relates to]
**Issue:** [2-3 sentences explaining the problem]
**Suggestion:** [Concrete fix — specify whether the PRD or QA runbook should change]

---

Severity levels:
- **Critical**: Missing coverage for a core requirement, or test verifies wrong thing
- **High**: Significant gap that will cause false passes or missed regressions
- **Medium**: Improvement that would strengthen the test suite
- **Low**: Minor wording or formatting issue

Focus on these validation axes:

**Coverage:**
- Does every REQ-xxx have at least one TC?
- Does every NEG-xxx have at least one TC?
- Does every TC trace to a valid REQ-xxx or NEG-xxx?
- Are there TCs that don't trace to any requirement (scope creep)?

**Consistency:**
- Do the test steps actually verify what the acceptance criteria say?
- Do assertions match the expected behavior described in the PRD?
- Are there contradictions between the PRD and the test cases?

**Testability:**
- Are preconditions realistic and achievable in a test environment?
- Are test steps executable as written (specific enough for automation)?
- Do assertions use concrete, observable criteria?

**Completeness:**
- Are edge cases from the PRD covered by test cases?
- Are error states and failure modes tested?
- Are negative requirements (NEG-xxx) adequately tested?

Do NOT suggest implementation approaches or architectural decisions.
Do NOT add new requirements — only identify gaps in existing coverage.
PROMPT
)"

prompt="$prompt

PRD file: $prd_rel
QA runbook file: $qa_rel

--- PRD CONTENT ---

$(cat "$prd_path")

--- QA RUNBOOK CONTENT ---

$(cat "$qa_path")"

{
  echo "# Codex QA Validation Review"
  echo
  echo "- PRD: \`$prd_rel\`"
  echo "- QA Runbook: \`$qa_rel\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (model diversity)"
  echo
} >"$out_path"

stderr_log="${out_path%.md}.stderr.log"

# Capture Codex exit code explicitly so set -e does not kill the script
# before we can report what happened
codex_exit=0
codex exec \
  --skip-git-repo-check \
  --sandbox read-only \
  --config model_reasoning_effort=high \
  -C "$repo_root" \
  "$prompt" \
  >>"$out_path" \
  2>"$stderr_log" \
  || codex_exit=$?

if [[ "$codex_exit" -ne 0 ]]; then
  echo "Error: codex exec failed with exit code $codex_exit. See $stderr_log" >&2
  # Append failure note to output so synthesis can see it
  echo "" >>"$out_path"
  echo "## Findings — Codex" >>"$out_path"
  echo "" >>"$out_path"
  echo "_Codex CLI exited with code $codex_exit. No findings produced._" >>"$out_path"
  exit 1
fi

# Validate structured output
if ! grep -q '^## Findings — Codex' "$out_path"; then
  echo "Warning: Codex output missing findings header. Check $stderr_log for errors." >&2
fi

if ! grep -Eq '^### (Critical|High|Medium|Low): ' "$out_path"; then
  echo "Warning: Codex produced no structured severity findings. Check $stderr_log for errors." >&2
fi

echo "Codex QA validation review written to: $out_path"
```

**Step 2: Make the script executable**

Run:
```bash
chmod +x skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh
```

**Step 3: Verify the script has correct syntax**

Run:
```bash
bash -n skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh
```

Expected: no output (syntax OK)

**Step 4: Commit**

```bash
git add skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh
git commit -m "feat: add Codex QA validation review script"
```

---

### Task 3: Write the Claude Review Prompt Reference

**Files:**
- Create: `skills/qa-runbook-validation/references/claude-review-prompt.md`

**Step 1: Write the reference file**

Create `skills/qa-runbook-validation/references/claude-review-prompt.md`:
```markdown
# Claude QA Validation Review Prompt

Review the PRD and QA runbook pair together. Produce findings that identify
gaps between the two documents.

## Output Format

```
## Findings — Claude

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
```

**Step 2: Commit**

```bash
git add skills/qa-runbook-validation/references/claude-review-prompt.md
git commit -m "feat: add Claude review prompt for QA validation"
```

---

### Task 4: Write the Synthesis Prompt Reference

**Files:**
- Create: `skills/qa-runbook-validation/references/synthesis-prompt.md`
- Reference: `skills/prd-challenge/references/synthesis-prompt.md` (pattern to follow)

**Step 1: Write the reference file**

Create `skills/qa-runbook-validation/references/synthesis-prompt.md`:
```markdown
# QA Validation Synthesis Prompt

After both reviewers complete, synthesize findings into a single prioritized
list with semantic classification.

## Synthesis Instructions

Read both review outputs (Claude inline review + Codex CLI). Each output has
a self-identifying header (`## Findings — Claude` or `## Findings — Codex`).
Produce a unified findings list.

**If either reviewer produced no findings or empty/malformed output**, note
this explicitly: "[Source] No findings produced — possible tool failure.
Do not treat absence of findings as endorsement." Continue synthesis with
the remaining reviewer's output.

1. **Deduplicate**: If both reviewers raised the same concern, merge into one
   finding. Note that both flagged it (higher confidence).

2. **Resolve severity disagreements**: When reviewers disagree on severity for
   the same finding, use the **highest** severity assigned by either reviewer.
   Note the disagreement.

3. **Classify each finding** as semantic or non-semantic using the rules in
   `references/semantic-classification-rules.md`. Tag each finding with
   `[AUTO-FIX]` or `[PROPOSED]`.

4. **Prioritize by severity**:
   - **Critical**: Listed first. Must be resolved before validation passes.
   - **High**: Listed second. Should be resolved.
   - **Medium**: Listed for reference. May be resolved.
   - **Low**: Listed for reference. Informational.

5. **Tag source**: Each finding shows which reviewer(s) raised it:
   - `[Claude]`, `[Codex]`, or `[Claude + Codex]`

6. **Format**:

```
## Validation Findings

### Critical

#### [Finding title] [Claude + Codex] [PROPOSED]
**Category:** Coverage
**Requirement:** REQ-xxx / TC-xxx
**Issue:** [Merged description from both reviewers]
**Proposed change:** [Specific edit to PRD or QA runbook]

---

### High

#### [Finding title] [Codex] [AUTO-FIX]
**Category:** Consistency
**Requirement:** REQ-xxx / TC-xxx
**Issue:** [Description]
**Fix applied:** [What was auto-fixed]

---

### Medium (for reference)
...

### Low (for reference)
...
```

7. **Summary line**: End with a count:
   "X Critical, Y High, Z Medium, W Low findings.
   A auto-fixed, B proposed for user review."
```

**Step 2: Commit**

```bash
git add skills/qa-runbook-validation/references/synthesis-prompt.md
git commit -m "feat: add synthesis prompt for QA validation"
```

---

### Task 5: Write the Semantic Classification Rules Reference

**Files:**
- Create: `skills/qa-runbook-validation/references/semantic-classification-rules.md`

**Step 1: Write the reference file**

Create `skills/qa-runbook-validation/references/semantic-classification-rules.md`:
```markdown
# Semantic Classification Rules

Every finding from the validation round must be classified as either
**non-semantic** (auto-fixable) or **semantic** (proposed as a diff for
user approval). When in doubt, classify as semantic — it is safer to
ask than to auto-apply a meaning change.

## Non-Semantic (auto-fixable) — tag as `[AUTO-FIX]`

These changes do not alter the meaning of any requirement or test case:

1. **Formatting inconsistencies**: Markdown structure, heading levels, list
   styles, whitespace, line breaks that don't affect meaning
2. **Wording clarity**: Rephrasing for readability without changing what is
   tested or required (e.g., "Click the button" → "Click the 'Submit' button")
3. **Traceability link corrections**: Fixing mismatched references
   (e.g., TC says `REQ-003` but means `REQ-3`, or a TC traces to a
   requirement that was renumbered)
4. **Deduplication**: Removing test cases that test the exact same scenario
   as another TC (same steps, same assertions, same requirement)
5. **YAML frontmatter fixes**: Correcting dates, IDs, paths, or formatting
   in the runbook's YAML frontmatter
6. **Coverage matrix corrections**: Updating the coverage matrix table to
   match the actual TCs present in the document (adding missing rows,
   removing rows for deleted TCs)
7. **Spec guardian violations**: Rewriting steps/assertions that contain
   implementation details to use user-visible language (same rules as
   `qa-runbook-gen/references/spec-guardian-rules.md`)

## Semantic (proposed for user review) — tag as `[PROPOSED]`

These changes alter the meaning of a requirement or test case:

1. **Adding a requirement**: A new REQ-xxx or NEG-xxx that doesn't exist
   in the PRD
2. **Removing a requirement**: Suggesting a requirement should be dropped
3. **Changing requirement meaning**: Altering what a requirement asks for
   or what "done" looks like
4. **Adding a test case**: A new TC-xxx that tests something not currently
   covered
5. **Removing a test case**: Suggesting a TC should be dropped (other than
   deduplication of exact copies)
6. **Changing test expectations**: Altering what a TC's assertions verify
   (different expected outcome)
7. **Scope changes**: New user flows, removed functionality, changed
   boundaries
8. **Changing preconditions**: Modifications that affect test validity or
   what is assumed true before testing
9. **Changing priority**: Moving a requirement or TC between priority levels
   (e.g., P0 → P1)

## Edge Cases

- Fixing a typo in a requirement name: **non-semantic** (if the intent
  is obviously the same word misspelled)
- Rewriting a vague assertion to be specific: **semantic** (it changes what
  the test actually verifies)
- Adding a missing traceability link to an existing TC: **non-semantic**
- Adding a traceability link to a requirement that doesn't exist:
  **semantic** (implies a new requirement)
```

**Step 2: Commit**

```bash
git add skills/qa-runbook-validation/references/semantic-classification-rules.md
git commit -m "feat: add semantic classification rules for QA validation"
```

---

### Task 6: Write the SKILL.md

**Files:**
- Modify: `skills/qa-runbook-validation/SKILL.md` (replace placeholder)
- Reference: `skills/prd-challenge/SKILL.md` (pattern to follow)
- Reference: `docs/plans/2026-03-02-qa-runbook-validation-design.md` (design spec)

**Step 1: Write the full SKILL.md**

Replace the placeholder content in `skills/qa-runbook-validation/SKILL.md` with:

```markdown
---
name: qa-runbook-validation
description: "Validate a PRD + QA runbook pair using parallel Claude and Codex reviews. Use after qa-runbook-gen completes, or when the user asks to validate a QA runbook against its PRD. Auto-applies non-semantic fixes and surfaces semantic findings for user review. Max 3 validation rounds."
---

# QA Runbook Validation

Validate a PRD + QA runbook pair using two independent reviewers (Claude +
Codex) to catch coverage gaps, consistency issues, and testability problems
that the generation step may have missed. Non-semantic fixes are auto-applied;
semantic findings are packaged for user review.

## Prerequisites

- A PRD file with Status: Approved
- A QA runbook file generated from that PRD
- Codex CLI installed and authenticated (`codex --version` succeeds)

## Workflow

### Step 1: Resolve Inputs

**If chained from qa-runbook-gen:** Use the PRD path and QA runbook path
passed from the previous step.

**If invoked standalone:** Ask the user for both paths. If not provided:
1. Scan `docs/` for files matching `prd-*.md` with Status: Approved
2. Scan `docs/qa/` for files matching `qa-*.md`
3. If exactly one PRD and one QA runbook are found, confirm with the user
4. If multiple matches, list them and ask which pair to validate

**Validate:**
- Both files exist
- PRD status is "Approved"
- QA runbook's `prd` frontmatter field points to the correct PRD

Read both documents fully into context.

### Step 2: Launch Parallel Reviews (Round 1)

Read `references/claude-review-prompt.md` for the Claude review instructions.

Launch both reviews simultaneously in a single message:

**Review 1 (Claude inline):** Using the instructions from
`references/claude-review-prompt.md`, review the PRD+QA pair. Produce
findings with the header `## Findings — Claude`. Explore the codebase
to ground the analysis in what actually exists.

**Review 2 (Codex CLI):** Launch a Bash command with **`timeout: 600000`**
(10 minutes):

```bash
script_path="$HOME/.claude/skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh"
fi
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh"
fi

if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_qa_validation.sh" >&2
  echo "Checked: \$HOME/.claude/skills/, <repo>/skills/, <repo>/.claude/skills/" >&2
  exit 1
fi

out_path=".claude/tmp/codex-qa-validation-review.md"
mkdir -p .claude/tmp
bash "$script_path" \
  "<prd-path>" \
  "<qa-path>" \
  "$out_path"
echo "OUTPUT_PATH=$out_path"
```

The output path is deterministic: `.claude/tmp/codex-qa-validation-review.md`.

**If the Codex Bash command fails** (non-zero exit, timeout, or Codex not
installed): note the failure and proceed with synthesis using only the Claude
review. Do not abort validation because of a Codex failure.

### Step 3: Synthesize Findings

After both reviews complete:

1. Collect the Claude review output (produced inline in Step 2)
2. Read the Codex output file at `.claude/tmp/codex-qa-validation-review.md`
   using the Read tool. If the file is missing or empty, note: "[Codex]
   No findings produced — possible tool failure."
3. Read `references/synthesis-prompt.md` for synthesis instructions
4. Read `references/semantic-classification-rules.md` for classification rules
5. Produce a unified findings list following the synthesis format
6. Classify each finding as `[AUTO-FIX]` or `[PROPOSED]`

### Step 4: Auto-Apply Non-Semantic Fixes

For each finding tagged `[AUTO-FIX]`:
1. Apply the fix directly to the PRD or QA runbook file as appropriate
2. Record the change in an "Auto-Applied Fixes" section for the validation
   report

Use the Edit tool for each fix. Make targeted edits — do not rewrite entire
files.

### Step 5: Package Semantic Findings

For each finding tagged `[PROPOSED]`:
- Record in a "Proposed Changes" section for the validation report
- Include: the finding, severity, source tag, the affected requirement/TC,
  and the specific proposed edit as a diff

### Step 6: Check for Additional Rounds

**Trigger condition for another round:** There are unresolved critical
contradictions between Claude and Codex — one reviewer flags something as
Critical, the other says no issue on the same item.

If the trigger condition is met AND the current round is less than 3:
1. Re-run both Claude and Codex reviews in parallel (same as Step 2) on
   the **updated** documents (including any auto-applied fixes)
2. Return to Step 3 for synthesis
3. Continue through Steps 4-5

**Max 3 rounds total.** If contradictions persist after round 3, include
the remaining contradictions in the validation report under a
"Unresolved Contradictions" section and flag for user review.

If the trigger condition is NOT met, proceed to Step 7.

### Step 7: Output

1. Assemble the validation report with these sections:
   - Header: feature name, PRD path, QA runbook path, date, round count
   - Validation Summary: total findings by severity, auto-fix count, proposed count
   - Auto-Applied Fixes: list of all auto-applied changes with before/after
   - Proposed Changes: list of all semantic findings with proposed diffs
   - Unresolved Contradictions: (if any remain after max rounds)
2. Create the output directory: `mkdir -p docs/reviews/qa-validation`
3. Save to `docs/reviews/qa-validation/<timestamp>-<feature>-validation.md`
   where `<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC) and `<feature>` is
   the feature slug from the QA runbook's `id` field (strip the `qa-` prefix)
4. Commit:
   ```
   git add <prd-path> <qa-path> docs/reviews/qa-validation/
   git commit -m "docs: QA runbook validation complete for <feature>"
   ```
5. Report: "Validation complete in N round(s). X non-semantic fixes
   auto-applied. Y semantic findings for user review. Report at `<path>`."

## Notes

- **Reference file resolution**: `references/*.md` files are relative to the
  skill directory. Look in `$HOME/.claude/skills/qa-runbook-validation/references/`
  (global) or the repo's `skills/qa-runbook-validation/references/` directory.
  If not found, stop and report the error.
- Codex provides model diversity (GPT vs Claude). It may catch blind spots
  that Claude misses.
- The auto-apply step only touches non-semantic changes. When in doubt,
  classify as semantic and propose instead of auto-applying.
- Max 3 rounds total. Do not loop indefinitely.
- This skill runs autonomously — no user interaction during validation.
  Semantic findings are packaged for user review at Stage 5 (sign-off).
```

**Step 2: Commit**

```bash
git add skills/qa-runbook-validation/SKILL.md
git commit -m "feat: write SKILL.md for qa-runbook-validation"
```

---

### Task 7: Add Handoff to qa-runbook-gen

**Files:**
- Modify: `skills/qa-runbook-gen/SKILL.md:162-185` (add Step 7 after Step 6, before Notes)

**Step 1: Add the handoff step**

In `skills/qa-runbook-gen/SKILL.md`, insert the following after Step 6 (Output)
and before the `## Notes` section. The new step goes after line 171 (the
report line of Step 6) and before line 173 (`## Notes`):

```markdown

### Step 7: Trigger Validation

After the QA runbook is generated, trigger the `qa-runbook-validation` skill
with both paths:
- PRD path: the source PRD used for generation
- QA runbook path: the just-generated `docs/qa/qa-<feature-slug>.md`

Start the validation immediately after Step 6. Pass both paths explicitly.
Only skip this trigger if the user explicitly asks to defer it.
```

**Step 2: Commit**

```bash
git add skills/qa-runbook-gen/SKILL.md
git commit -m "feat: chain qa-runbook-gen to qa-runbook-validation"
```

---

### Task 8: Update Manifest

**Files:**
- Modify: `manifests/skills.tsv:10` (add new line before or after qa-acceptance)

**Step 1: Add the new skill entry**

Add this line to `manifests/skills.tsv` after the `qa-runbook-gen` line:
```
claude	skills/qa-runbook-validation	qa-runbook-validation
```

**Step 2: Commit**

```bash
git add manifests/skills.tsv
git commit -m "feat: add qa-runbook-validation to skills manifest"
```

---

### Task 9: Sync to Global and Verify

**Step 1: Run the sync script**

Run:
```bash
bash scripts/sync-to-global.sh
```

Expected: output includes `Syncing claude skill: skills/qa-runbook-validation -> ~/.claude/skills/qa-runbook-validation`

**Step 2: Verify the skill directory was synced**

Run:
```bash
ls -la ~/.claude/skills/qa-runbook-validation/
ls -la ~/.claude/skills/qa-runbook-validation/scripts/
ls -la ~/.claude/skills/qa-runbook-validation/references/
```

Expected: SKILL.md, scripts/run_codex_qa_validation.sh (executable), and
all 3 reference files present.

**Step 3: Verify qa-runbook-gen was updated**

Run:
```bash
grep -n "Step 7" ~/.claude/skills/qa-runbook-gen/SKILL.md
```

Expected: shows the new "Step 7: Trigger Validation" heading.

**Step 4: Verify the Codex script syntax**

Run:
```bash
bash -n ~/.claude/skills/qa-runbook-validation/scripts/run_codex_qa_validation.sh
```

Expected: no output (syntax OK).

**Step 5: Commit (no commit needed — sync is a deployment action)**

No commit for this step. The sync copies files from the repo to the global
skill directories.
