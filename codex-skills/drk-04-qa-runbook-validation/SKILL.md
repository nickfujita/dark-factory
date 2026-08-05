---
name: drk-04-qa-runbook-validation
description: "Validate a PRD + QA runbook pair using a Codex inline review and a fresh Codex CLI review. Auto-applies non-semantic fixes, surfaces semantic findings, presents sign-off package, and hands off to Codex Superpowers brainstorming on approval. Max 3 validation rounds."
---

# QA Runbook Validation

Validate a PRD + QA runbook pair using two independent review contexts: the
current Codex session and a fresh Codex CLI process. Use them to catch coverage
gaps, consistency issues, and testability problems that the generation step may
have missed. Non-semantic fixes are auto-applied; semantic findings are packaged
for user review.

## Prerequisites

- A PRD file with Status: Approved (or Approved with open items)
- A QA runbook file generated from that PRD
- Codex CLI installed and authenticated (`codex --version` succeeds)

## Workflow

### Step 1: Resolve Inputs

**If invoked by the Codex orchestrator after drk-03-qa-runbook-gen:** Use the
PRD path and QA runbook path passed from the previous step.

**If invoked standalone:** Ask the user for both paths. If not provided:
1. Scan `docs/` for files matching `prd-*.md` with Status: Approved (or
   Approved with open items)
2. Scan `docs/qa/` for files matching `qa-*.md`
3. If exactly one PRD and one QA runbook are found, confirm with the user
4. If multiple matches, list them and ask which pair to validate

**Validate:**
- Both files exist
- PRD status is "Approved" or "Approved with open items" — the latter carries a
  "Known open items — read first" section whose items are known-unresolved, not
  validation findings
- QA runbook's `prd` frontmatter field points to the correct PRD

Read both documents fully into context.

### Step 2: Launch Parallel Reviews (Round 1)

Read `references/codex-inline-review-prompt.md` for the inline review
instructions.

Launch both reviews simultaneously in a single message:

**Review 1 (Codex inline):** Using the instructions from
`references/codex-inline-review-prompt.md`, review the PRD+QA pair. Produce
findings with the header `## Findings — Codex Inline`. Explore the codebase
to ground the analysis in what actually exists.

**Review 2 (Codex CLI):** Launch a Bash command with **`timeout: 600000`**
(10 minutes):

```bash
script_path="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-04-qa-runbook-validation/scripts/run_codex_qa_validation.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-skills/drk-04-qa-runbook-validation/scripts/run_codex_qa_validation.sh"
fi
if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_qa_validation.sh" >&2
  echo "Checked: \${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/ and <repo>/codex-skills/" >&2
  exit 1
fi

out_path=".dark-factory/tmp/codex-qa-validation-review.md"
mkdir -p .dark-factory/tmp
bash "$script_path" \
  "<prd-path>" \
  "<qa-path>" \
  "$out_path"
echo "OUTPUT_PATH=$out_path"
```

The output path is deterministic: `.dark-factory/tmp/codex-qa-validation-review.md`.

**If the Codex Bash command fails** (non-zero exit, timeout, or Codex not
installed): note the failure and proceed with synthesis using only the Codex
review. Do not abort validation because of a Codex failure.

### Step 3: Synthesize Findings

After both reviews complete:

1. Collect the Codex review output (produced inline in Step 2)
2. Read the Codex output file at `.dark-factory/tmp/codex-qa-validation-review.md`
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
contradictions between the inline review and CLI review — one reviewer flags
something as Critical, the other says no issue on the same item.

If the trigger condition is met AND the current round is less than 3:
1. Re-run both review contexts in parallel (same as Step 2) on
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
2. Create the output directory: `mkdir -p .dark-factory/reviews/qa-validation`
3. Save to `.dark-factory/reviews/qa-validation/<timestamp>-<feature>-validation.md`
   where `<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC) and `<feature>` is
   the feature slug from the QA runbook's `id` field (strip the `qa-` prefix)
	4. Commit:
	   ```
	   git add <prd-path> <qa-path>
	   git commit -m "docs: QA runbook validation complete for <feature>"
	   ```
5. Report: "Validation complete in N round(s). X non-semantic fixes
   auto-applied. Y semantic findings for user review. Report at `<path>`."

### Step 8: User Sign-off

1. Present the sign-off package:
   - PRD path and current status
   - QA runbook path
   - Validation report path (`.dark-factory/reviews/qa-validation/<file>`)
   - Count of auto-applied fixes (from Step 4)
   - List of any pending semantic proposals (from Step 5), or "None" if clean
2. Ask the user: **approve** to proceed to implementation, or **reject** with
   feedback. Treat any affirmative response ("yes", "looks good", "go ahead")
   as approve. Treat any corrective feedback as reject.
3. **On approve**: Resolve the engineering standards path using the same
   3-location fallback pattern:
   ```
   ${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-04-qa-runbook-validation/references/engineering-standards.md
   <repo>/codex-skills/drk-04-qa-runbook-validation/references/engineering-standards.md
   <repo>/references/engineering-standards.md
   ```
   Then explicitly invoke the Codex Superpowers `brainstorming` skill with an
   opening message that includes:
   > "The PRD at `<prd-path>` and QA runbook at `<qa-path>` have been
   > validated and approved. Please read both files as your first step.
   > Also read the engineering standards at `<standards-path>` — these
   > define technical delivery expectations (including e2e test coverage)
   > that must be met.
   > The goal is to plan the technical implementation of the feature
   > described in those documents. Use the PRD requirements and QA runbook
   > test cases as the authoritative definition of what to build.
   > Important: when the Codex Superpowers `writing-plans` skill creates the
   > implementation plan, the final task must be to invoke `drk-05-dev-verify` (not
   > `finishing-a-development-branch`) to run the Dark Factory verification
   > and review gates on the completed branch."
4. **On reject**: classify the feedback type and confirm with the user before
   routing:
   If the feedback spans multiple categories, ask the user to confirm which
   routing they intend before proceeding.
   - **QA-only** ("this scenario is wrong", "missing a flow", assertion issue)
     → update QA runbook → re-run `drk-04-qa-runbook-validation` → return to
     sign-off
   - **PRD tweak** ("change this requirement", "you misunderstood X") →
     update PRD → re-run `drk-03-qa-runbook-gen` → re-run validation → return
     to sign-off
   - **Major scope change** ("rethink the whole approach") → invoke
     `drk-01-prd-interview` for a focused re-interview on the changed scope

## Notes

- **Reference file resolution**: `references/*.md` files are relative to the
  skill directory. Look in `${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-04-qa-runbook-validation/references/`
  (global) or the repo's `codex-skills/drk-04-qa-runbook-validation/references/` directory.
  If not found, stop and report the error.
- The CLI review provides an independent context. It may catch blind spots
  the inline review misses.
- The auto-apply step only touches non-semantic changes. When in doubt,
  classify as semantic and propose instead of auto-applying.
- Max 3 rounds total. Do not loop indefinitely.
- This skill runs autonomously — no user interaction during validation.
  Semantic findings are packaged for user review at Step 8 (sign-off).
