---
name: df-qa-validation
description: "Validate a PRD + QA runbook pair using parallel Claude and Codex reviews. Auto-applies non-semantic fixes, surfaces semantic findings, and presents a sign-off package. Standard runs one combined pass; High-consequence runs up to three contradiction rounds. Returns control to the df feature playbook on approval. Runs when the df feature playbook reaches its QA-validation stage or when the operator invokes it explicitly — never on its own."
disable-model-invocation: true
---

# QA Runbook Validation

Validate a PRD + QA runbook pair using two independent reviewers (Claude +
Codex) to catch coverage gaps, consistency issues, and testability problems
that the generation step may have missed. Non-semantic fixes are auto-applied;
semantic findings are packaged for user review.

## Lane modes

The number of validation passes is a lane property, not a judgment call. Read
the lane from the run state; ask the operator only if none is recorded.

| Lane | Passes | Contradiction loop |
|---|---|---|
| Quick | not run — the lane has no runbook | n/a |
| Standard | **one combined validation pass** | none. There is no round 2. |
| High-consequence | up to **3** | the contradiction loop in Step 6 |

**Standard runs Step 2 once.** Both reviewers, one synthesis, auto-apply,
package the semantic findings, sign-off. A contradiction that survives that
single pass is recorded under "Unresolved Contradictions" and goes to the
operator with the sign-off package. It does not open a round. A Standard
validation that wanted a second round is telling you the lane was wrong; say so
and let the operator re-lane rather than looping.

**High-consequence keeps the loop**, capped at 3 rounds, unchanged.

## Prerequisites

- A PRD file with Status: Approved (or Approved with open items)
- A QA runbook file generated from that PRD
- Codex CLI installed and authenticated (`codex --version` succeeds)

## Workflow

### Step 1: Resolve Inputs

**If chained from df-qa-runbook-gen:** Use the PRD path and QA runbook path
passed from the previous step.

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

Read `references/claude-review-prompt.md` for the Claude review instructions.

Launch both reviews simultaneously in a single message:

**Review 1 (Claude inline):** Using the instructions from
`references/claude-review-prompt.md`, review the PRD+QA pair. Produce
findings with the header `## Findings — Claude`. Explore the codebase
to ground the analysis in what actually exists.

**Review 2 (Codex CLI):** Launch a Bash command with **`timeout: 600000`**
(10 minutes):

```bash
script_path="$HOME/.claude/skills/df-qa-validation/scripts/run_codex_qa_validation.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/df-qa-validation/scripts/run_codex_qa_validation.sh"
fi
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/df-qa-validation/scripts/run_codex_qa_validation.sh"
fi
if [[ ! -f "$script_path" ]]; then
  script_path="$(ls -d "$HOME"/.claude/plugins/cache/*/dark-factory/*/skills/df-qa-validation/scripts/run_codex_qa_validation.sh 2>/dev/null | sort -V | tail -1)"
fi

if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_qa_validation.sh" >&2
  echo "Checked: \$HOME/.claude/skills/, <repo>/skills/, <repo>/.claude/skills/, and the dark-factory plugin cache" >&2
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
installed), apply D7 for the lane. This is a blocked cross-model leg, and the
two lanes treat it differently on purpose:

| Lane | A blocked Codex leg means |
|---|---|
| Standard | **degrade with a logged note.** Synthesize from the Claude review alone, record `deferred: <reason>` in the run ledger, and say in the validation report and the sign-off package that the pass ran single-family. |
| High-consequence | **defer approval.** Do not present a sign-off package. Record the blocker, surface it, and stop until the leg can run. A usage limit is a recoverable block, so waiting for the window to reset is the answer, not waiving the leg. |

Degrading is allowed in Standard. Degrading without saying so is not.

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

### Step 6: Check for Additional Rounds (High-consequence only)

**In the Standard lane, skip this step.** The combined pass is the validation.
Carry any surviving contradiction into the report's "Unresolved Contradictions"
section and go to Step 7.

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
   - Header: feature name, PRD path, QA runbook path, date, lane, pass count,
     and whether any leg was degraded under D7
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
   - Any leg that was degraded under D7, named. A sign-off package that hides
     a missing reviewer is asking for an approval the operator did not have the
     facts for.
2. Ask the user: **approve** to proceed to implementation, or **reject** with
   feedback. Treat any affirmative response ("yes", "looks good", "go ahead")
   as approve. Treat any corrective feedback as reject.
3. **On approve**: Resolve the engineering standards path using the same
   3-location fallback pattern:
   ```
   $HOME/.claude/skills/df-qa-validation/references/engineering-standards.md
   <repo>/skills/df-qa-validation/references/engineering-standards.md
   <repo>/references/engineering-standards.md
   ```
   Then **return control to the df feature playbook**
   (`df/playbooks/feature.md`). The playbook owns sequencing and picks the next
   stage; this skill does not. Invoked standalone, with no playbook driving,
   the next stage is `df-design`, and planning after it is `df-plan`. Either
   way, design and planning belong to those two skills.

   Hand back, in one block the playbook can read without the chat context:

   - the PRD path and its status
   - the QA runbook path
   - the validation report path
   - the resolved engineering-standards path, which defines the technical
     delivery expectations the plan must meet, e2e coverage included
   - the count of auto-applied fixes and any accepted semantic proposals
   - anything the pass degraded on under D7

   **`superpowers:brainstorming` is not the handoff and has not been since the
   port.** Nothing in this pipeline chains into it. One owner per function, and
   the design function belongs to `df-design`.
4. **On reject**: classify the feedback type and confirm with the user before
   routing:
   If the feedback spans multiple categories, ask the user to confirm which
   routing they intend before proceeding.
   - **QA-only** ("this scenario is wrong", "missing a flow", assertion issue)
     → update QA runbook → re-run `df-qa-validation` → return to
     sign-off
   - **PRD tweak** ("change this requirement", "you misunderstood X") →
     update PRD → re-run `df-qa-runbook-gen` → re-run validation → return
     to sign-off
   - **Major scope change** ("rethink the whole approach") → invoke
     `df-prd-interview` for a focused re-interview on the changed scope

## Notes

- **Reference file resolution**: `references/*.md` files are relative to the
  skill directory. Look in `$HOME/.claude/skills/df-qa-validation/references/`
  (global) or the repo's `skills/df-qa-validation/references/` directory.
  If not found, stop and report the error.
- Codex provides model diversity (GPT vs Claude). It may catch blind spots
  that Claude misses.
- The auto-apply step only touches non-semantic changes. When in doubt,
  classify as semantic and propose instead of auto-applying.
- Round count is a lane property: Standard runs one combined pass, and
  High-consequence runs at most 3. Neither loops indefinitely.
- This skill runs autonomously — no user interaction during validation.
  Semantic findings are packaged for user review at Step 8 (sign-off).
