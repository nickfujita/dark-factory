# Code Review & Sign-off Handoff Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add sign-off handoff to `drk-qa-runbook-validation` and build the `drk-code-review` skill with 5 parallel reviewers.

**Architecture:** Standalone skill following the established `drk-` pattern. Two Codex CLI scripts (quality + spec axes) plus three Claude persona sub-agents run in parallel. Findings written to disk before user decision step.

**Tech Stack:** Bash scripts, Markdown SKILL.md files, Codex CLI, Claude Agent tool.

---

### Task 1: Add Step 8 (sign-off handoff) to `drk-qa-runbook-validation`

**Files:**
- Modify: `skills/drk-qa-runbook-validation/SKILL.md`

**Step 1: Read the current SKILL.md**

Read `skills/drk-qa-runbook-validation/SKILL.md` to confirm current Step 7 ends at line ~164.

**Step 2: Update the frontmatter description**

Change the `description` field to:

```
"Validate a PRD + QA runbook pair using parallel Claude and Codex reviews. Auto-applies non-semantic fixes, surfaces semantic findings, presents sign-off package, and chains to superpowers:brainstorming on approval. Max 3 validation rounds."
```

**Step 3: Replace the Notes section with Step 8 + Notes**

After the current Step 7 block (ending with the summary report line), add:

```markdown
### Step 8: User Sign-off

1. Present the sign-off package:
   - PRD path and current status
   - QA runbook path
   - Validation report path (`docs/reviews/qa-validation/<file>`)
   - Count of auto-applied fixes (from Step 4)
   - List of any pending semantic proposals (from Step 5), or "None" if clean
2. Ask the user: **approve** to proceed to implementation, or **reject** with
   feedback.
3. **On approve**: chain to `superpowers:brainstorming` with this context:
   - The PRD at `<prd-path>` and QA runbook at `<qa-path>` are approved
   - Goal: plan the technical implementation of this feature
   - Pass both file paths so brainstorming can read them
4. **On reject**: classify the feedback type and confirm with the user before
   routing:
   - **QA-only** ("this scenario is wrong", "missing a flow", assertion issue)
     → update QA runbook → re-run `drk-qa-runbook-validation` → return to
     sign-off
   - **PRD tweak** ("change this requirement", "you misunderstood X") →
     update PRD → re-run `drk-qa-runbook-gen` → re-run validation → return
     to sign-off
   - **Major scope change** ("rethink the whole approach") → invoke
     `drk-prd-interview` for a focused re-interview on the changed scope
```

**Step 4: Spec review**

Re-read the updated SKILL.md. Verify:
- [ ] Frontmatter description updated
- [ ] Step 8 added after Step 7 (not replacing anything)
- [ ] Notes section still present after Step 8
- [ ] Reject routing covers all 3 cases from the design doc

**Step 5: Commit**

```bash
git add skills/drk-qa-runbook-validation/SKILL.md
git commit -m "feat: add sign-off handoff step to drk-qa-runbook-validation"
```

---

### Task 2: Scaffold `drk-code-review` directory

**Files:**
- Create: `skills/drk-code-review/scripts/` (directory)
- Create: `skills/drk-code-review/references/` (directory)

**Step 1: Create directories**

```bash
mkdir -p skills/drk-code-review/scripts
mkdir -p skills/drk-code-review/references
```

**Step 2: Verify**

```bash
ls skills/drk-code-review/
```

Expected: `references/  scripts/`

---

### Task 3: Create `run_codex_quality_review.sh`

**Files:**
- Create: `skills/drk-code-review/scripts/run_codex_quality_review.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_quality_review.sh <base-ref> <output-path>
# Runs a Codex CLI code quality review of the branch diff and writes findings
# to the output path.

if [[ $# -lt 2 ]]; then
  echo "Usage: run_codex_quality_review.sh <base-ref> <output-path>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
base_ref="$1"
out_path="$2"

# Get the branch diff
diff_content="$(git diff "$base_ref")"

if [[ -z "$diff_content" ]]; then
  echo "Error: no diff found between HEAD and $base_ref" >&2
  exit 1
fi

prompt="$(cat <<'PROMPT'
You are an independent code quality reviewer examining a feature branch diff.

Review the diff for code quality and correctness issues. Focus on:
- **Correctness**: Logic errors, wrong conditions, off-by-one errors
- **Edge cases**: Null/undefined handling, empty inputs, boundary values
- **Error handling**: Unhandled exceptions, swallowed errors, missing propagation
- **Test coverage**: Missing tests for critical paths or edge cases
- **Performance**: N+1 queries, unnecessary re-renders (not premature optimization)
- **Clarity**: Dead code, misleading names, overly complex logic

Produce findings in this exact format:

## Findings — Codex Quality

### [SEVERITY] <One-line finding title>
**Category:** Correctness | Edge Case | Error Handling | Test Coverage | Performance | Clarity
**Location:** `path/to/file.ts:line`
**Issue:** 2-3 sentences explaining the problem.
**Recommendation:** Concrete fix. Include a short code snippet if it clarifies the fix.

---

Severity levels:
- **Critical**: Will cause incorrect behavior or crashes in production
- **High**: Likely to cause bugs under normal use
- **Medium**: Could cause issues in less common scenarios
- **Low**: Clarity or style improvement, no functional impact

Only report findings on changed code (lines in the diff). Do NOT suggest
features or refactoring beyond the diff scope. YAGNI applies.
PROMPT
)"

prompt="$prompt

--- BEGIN DIFF ---
$diff_content
--- END DIFF ---"

{
  echo "# Codex Code Quality Review"
  echo
  echo "- Base ref: \`$base_ref\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (code quality axis)"
  echo
} >"$out_path"

stderr_log="${out_path%.md}.stderr.log"

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
  echo "" >>"$out_path"
  echo "## Findings — Codex Quality" >>"$out_path"
  echo "" >>"$out_path"
  echo "_Codex CLI exited with code $codex_exit. No findings produced._" >>"$out_path"
  exit 1
fi

if ! grep -q '^## Findings — Codex Quality' "$out_path"; then
  echo "Warning: Codex output missing findings header. Check $stderr_log." >&2
fi

echo "Codex quality review written to: $out_path"
```

**Step 2: Make executable**

```bash
chmod +x skills/drk-code-review/scripts/run_codex_quality_review.sh
```

**Step 3: Syntax check**

```bash
bash -n skills/drk-code-review/scripts/run_codex_quality_review.sh
```

Expected: no output (clean syntax)

**Step 4: Commit**

```bash
git add skills/drk-code-review/scripts/run_codex_quality_review.sh
git commit -m "feat: add Codex quality review script for drk-code-review"
```

---

### Task 4: Create `run_codex_spec_review.sh`

**Files:**
- Create: `skills/drk-code-review/scripts/run_codex_spec_review.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: run_codex_spec_review.sh <prd-path> <qa-path> <base-ref> <output-path>
# Runs a Codex CLI spec compliance review of the branch diff against the PRD
# and QA runbook. Writes findings to the output path.

if [[ $# -lt 4 ]]; then
  echo "Usage: run_codex_spec_review.sh <prd-path> <qa-path> <base-ref> <output-path>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI is not installed or not in PATH." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
prd_path="$1"
qa_path="$2"
base_ref="$3"
out_path="$4"

if [[ "$prd_path" != /* ]]; then prd_path="$repo_root/$prd_path"; fi
if [[ "$qa_path" != /* ]]; then qa_path="$repo_root/$qa_path"; fi

if [[ ! -f "$prd_path" ]]; then
  echo "Error: PRD file not found at $prd_path" >&2
  exit 1
fi

if [[ ! -f "$qa_path" ]]; then
  echo "Error: QA runbook not found at $qa_path" >&2
  exit 1
fi

prd_rel="${prd_path#"$repo_root"/}"
qa_rel="${qa_path#"$repo_root"/}"

diff_content="$(git diff "$base_ref")"

if [[ -z "$diff_content" ]]; then
  echo "Error: no diff found between HEAD and $base_ref" >&2
  exit 1
fi

prompt="$(cat <<'PROMPT'
You are an independent spec compliance reviewer. Verify that the implementation
satisfies the approved PRD and QA runbook.

Review the branch diff against the PRD and QA runbook for:
- **Requirement coverage**: Every REQ-xxx and NEG-xxx has corresponding implementation
- **Acceptance criteria**: Each criterion is met by the code
- **Negative requirements**: What must NOT happen is enforced in code
- **Edge cases**: PRD edge cases are handled
- **QA alignment**: Implementation would pass each TC-xxx in the runbook
- **Scope**: No scope creep (implementing things not in PRD) and no missing scope

Produce findings in this exact format:

## Findings — Codex Spec

### [SEVERITY] <One-line finding title>
**Requirement:** REQ-xxx | NEG-xxx | TC-xxx
**Location:** `path/to/file.ts:line` (or "Not implemented" if missing entirely)
**Issue:** 2-3 sentences explaining the gap between spec and implementation.
**Recommendation:** What the code should do to satisfy the requirement.

---

Severity levels:
- **Critical**: PRD requirement completely unimplemented or actively violated
- **High**: Requirement partially implemented or acceptance criterion not met
- **Medium**: Edge case or secondary flow from PRD not handled
- **Low**: Minor deviation from PRD intent, low user impact

Base your review only on the PRD and QA runbook — not on general best practices.
Do not flag missing features that are explicitly out of scope in the PRD.
PROMPT
)"

prompt="$prompt

PRD file: $prd_rel
QA runbook file: $qa_rel

--- BEGIN PRD ---
$(cat "$prd_path")
--- END PRD ---

--- BEGIN QA RUNBOOK ---
$(cat "$qa_path")
--- END QA RUNBOOK ---

--- BEGIN DIFF ---
$diff_content
--- END DIFF ---"

{
  echo "# Codex Spec Compliance Review"
  echo
  echo "- PRD: \`$prd_rel\`"
  echo "- QA Runbook: \`$qa_rel\`"
  echo "- Base ref: \`$base_ref\`"
  echo "- Generated (UTC): \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo "- Reviewer: Codex CLI (spec compliance axis)"
  echo
} >"$out_path"

stderr_log="${out_path%.md}.stderr.log"

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
  echo "" >>"$out_path"
  echo "## Findings — Codex Spec" >>"$out_path"
  echo "" >>"$out_path"
  echo "_Codex CLI exited with code $codex_exit. No findings produced._" >>"$out_path"
  exit 1
fi

if ! grep -q '^## Findings — Codex Spec' "$out_path"; then
  echo "Warning: Codex output missing findings header. Check $stderr_log." >&2
fi

echo "Codex spec review written to: $out_path"
```

**Step 2: Make executable and syntax check**

```bash
chmod +x skills/drk-code-review/scripts/run_codex_spec_review.sh
bash -n skills/drk-code-review/scripts/run_codex_spec_review.sh
```

Expected: no output

**Step 3: Commit**

```bash
git add skills/drk-code-review/scripts/run_codex_spec_review.sh
git commit -m "feat: add Codex spec compliance review script for drk-code-review"
```

---

### Task 5: Create Claude persona reference files (batch)

**Files:**
- Create: `skills/drk-code-review/references/claude-quality-prompt.md`
- Create: `skills/drk-code-review/references/claude-security-prompt.md`
- Create: `skills/drk-code-review/references/claude-spec-compliance-prompt.md`

**Step 1: Write `claude-quality-prompt.md`**

```markdown
# Code Quality & Correctness Review

You are a Code Quality & Correctness reviewer for a feature branch.

## Your Focus

Review the branch diff and changed files for:

1. **Correctness**: Logic errors, off-by-one errors, wrong conditions,
   incorrect calculations
2. **Edge cases**: Null/undefined handling, empty arrays/objects, boundary
   values, concurrent access
3. **Error handling**: Unhandled exceptions, swallowed errors, missing error
   propagation, unclear error messages
4. **Test coverage**: Missing tests for critical paths, edge cases not tested,
   test assertions that don't actually verify behavior
5. **Performance**: N+1 queries, unnecessary re-renders, missing memoization
   where clearly needed (not premature optimization)
6. **Code clarity**: Dead code, misleading names, overly complex logic

## What to Read

1. Read `.claude/tmp/branch-diff.txt` for the full diff
2. For each changed file referenced in the diff, read the full file for context

## Output Format

Produce findings with the header `## Findings — Claude Quality`.

For each finding:

### [SEVERITY] <One-line finding title>
**Category:** Correctness | Edge Case | Error Handling | Test Coverage | Performance | Clarity
**Location:** `path/to/file.ts:line`
**Issue:** 2-3 sentences explaining the problem clearly.
**Recommendation:** Concrete fix. Include a code snippet if it clarifies the fix.

Severity levels:
- **Critical**: Will cause incorrect behavior or crashes in production
- **High**: Likely to cause bugs under normal use or important edge cases
- **Medium**: Could cause issues in less common scenarios
- **Low**: Clarity or style improvement, no functional impact

## Constraints

- Only report findings on changed code (lines in the diff)
- Do NOT suggest adding features or refactoring beyond the diff scope
- Do NOT flag issues already clearly covered by existing tests
- YAGNI: do not suggest abstractions or utilities not needed by this diff
```

**Step 2: Write `claude-security-prompt.md`**

```markdown
# Security Hardening Review

You are a Security Hardening reviewer for a feature branch.

## Your Focus

Review the branch diff and changed files for security vulnerabilities:

1. **Injection**: SQL injection, command injection, path traversal, template
   injection — any user input reaching a dangerous sink without sanitization
2. **Authentication & Authorization**: Missing auth checks, broken access
   control, IDOR (insecure direct object reference), privilege escalation paths
3. **Input validation**: Unvalidated user input reaching sensitive operations
4. **XSS**: Unescaped output in HTML, unsafe innerHTML, CSP gaps
5. **Secrets & credentials**: Hardcoded API keys, tokens, passwords committed
   in code
6. **Insecure defaults**: Disabled security headers, overly permissive CORS,
   verbose error messages leaking internals in production
7. **Sensitive data exposure**: PII logged, sensitive data in URLs, insecure
   client-side storage

## What to Read

1. Read `.claude/tmp/branch-diff.txt` for the full diff
2. For each changed file, read the full file for context

## Output Format

Produce findings with the header `## Findings — Claude Security`.

For each finding:

### [SEVERITY] <One-line finding title>
**Category:** Injection | Auth | Input Validation | XSS | Secrets | Insecure Default | Data Exposure
**Location:** `path/to/file.ts:line`
**Issue:** 2-3 sentences explaining the vulnerability and realistic impact.
**Recommendation:** Concrete fix with code example if applicable.

Severity levels:
- **Critical**: Exploitable vulnerability with direct security impact
- **High**: Significant security risk exploitable under normal conditions
- **Medium**: Security weakness requiring specific conditions to exploit
- **Low**: Defense-in-depth improvement, no direct vulnerability

## Constraints

- Only report findings on changed code
- Do not flag theoretical vulnerabilities without a realistic attack path
- Check whether issues are already mitigated by framework-level protections
  before reporting
```

**Step 3: Write `claude-spec-compliance-prompt.md`**

```markdown
# Spec Compliance Review

You are a Spec Compliance reviewer for a feature branch.

## Your Focus

Verify that the implementation satisfies the approved PRD and QA runbook:

1. **Requirement coverage**: Every REQ-xxx and NEG-xxx in the PRD has
   corresponding implementation
2. **Acceptance criteria**: Each criterion is met by the code as written
3. **Negative requirements**: What must NOT happen is enforced in code
4. **Edge cases**: PRD edge cases are handled in the implementation
5. **QA alignment**: Implementation would pass each TC-xxx in the QA runbook
6. **Scope**: No scope creep (implementing things not in the PRD) and no
   missing scope

## What to Read

1. Read the PRD file at the path provided in your prompt
2. Read the QA runbook file at the path provided in your prompt
3. Read `.claude/tmp/branch-diff.txt` for the full diff
4. For each changed file referenced in the diff, read the full file for context

## Output Format

Produce findings with the header `## Findings — Claude Spec`.

For each finding:

### [SEVERITY] <One-line finding title>
**Requirement:** REQ-xxx | NEG-xxx | TC-xxx
**Location:** `path/to/file.ts:line` (or "Not implemented" if missing entirely)
**Issue:** 2-3 sentences explaining the gap between spec and implementation.
**Recommendation:** What the code should do to satisfy the requirement.

Severity levels:
- **Critical**: PRD requirement completely unimplemented or actively violated
- **High**: Requirement partially implemented or acceptance criterion not met
- **Medium**: Edge case or secondary flow from PRD not handled
- **Low**: Minor deviation from PRD intent, low user impact

## Constraints

- Base your review only on the PRD and QA runbook, not on general best practices
- Do not flag missing features explicitly out of scope in the PRD
- If the PRD is ambiguous about a requirement, note the ambiguity rather than
  assuming a specific interpretation
```

**Step 4: Verify all 3 files exist**

```bash
ls skills/drk-code-review/references/
```

Expected: `claude-quality-prompt.md  claude-security-prompt.md  claude-spec-compliance-prompt.md`

**Step 5: Commit**

```bash
git add skills/drk-code-review/references/
git commit -m "feat: add Claude persona reference prompts for drk-code-review"
```

---

### Task 6: Create `synthesis-prompt.md`

**Files:**
- Create: `skills/drk-code-review/references/synthesis-prompt.md`

**Step 1: Write the file**

```markdown
# Synthesis Instructions — Code Review

Merge findings from all 5 reviewers into a single severity-ranked report.

## Step 1: Collect All Findings

- Claude Quality: `## Findings — Claude Quality` section
- Claude Security: `## Findings — Claude Security` section
- Claude Spec: `## Findings — Claude Spec` section
- Codex Quality: read `.claude/tmp/codex-quality-review.md`
- Codex Spec: read `.claude/tmp/codex-spec-review.md`

## Step 2: Deduplicate

Two findings are duplicates if they refer to the same issue at the same
location (even if described differently). When merging:
- Keep the most detailed description and recommendation
- Combine all source tags: `[Claude Quality]`, `[Claude Security]`,
  `[Claude Spec]`, `[Codex Quality]`, `[Codex Spec]`
- Use the highest severity assigned by any reviewer

## Step 3: Assign IDs and Sort

Number all Critical and High findings sequentially: CR-001, CR-002, …

Order: Critical first, then High. Within each severity, most sources first
(highest reviewer agreement).

## Step 4: Recommendations

Each finding must have a concrete, actionable recommendation:
- A specific code change, not "improve error handling"
- Include a short code snippet where it clarifies the fix
- If reviewers disagree on the fix, present both options briefly and note
  the trade-off

## Step 5: Medium / Low

Medium and Low findings go into a reference table only. They are not
surfaced as action items unless the user explicitly requests them.

Columns: ID, Severity, Title, Sources, Location

## Output Structure

Produce the full report content (the SKILL.md Step 4 writes it to disk).
Follow the report format defined there exactly.
```

**Step 2: Commit**

```bash
git add skills/drk-code-review/references/synthesis-prompt.md
git commit -m "feat: add synthesis prompt for drk-code-review"
```

---

### Task 7: Create `skills/drk-code-review/SKILL.md`

**Files:**
- Create: `skills/drk-code-review/SKILL.md`

**Step 1: Write the full SKILL.md**

```markdown
---
name: drk-code-review
description: "Multi-model code review for a feature branch: 5 parallel reviewers (3 Claude personas + 2 Codex) covering code quality, security, and spec compliance. Use after implementation is complete and before QA acceptance. Writes findings to a markdown report, gets user decisions, applies fixes, and chains to drk-qa-acceptance."
---

# Code Review

Multi-model feature branch review: 5 parallel reviewers surface code quality,
security, and spec compliance issues. User reviews the findings report and
gives decisions. Fixes are applied with codebase verification. Chains to
drk-qa-acceptance.

## Prerequisites

- Feature branch checked out with implementation complete
- Tests passing before review begins
- Codex CLI installed and authenticated (`codex --version` succeeds)
- PRD (`docs/prd-<feature>.md`, Status: Approved) and QA runbook
  (`docs/qa/qa-<feature>.md`) exist for this feature

## Workflow

### Step 1: Resolve Inputs

**Detect branch and base:**
```bash
feature_branch=$(git branch --show-current)
base_ref=$(git merge-base HEAD main)
```

**Derive feature slug from branch name:**
Strip common prefixes (`feat/`, `feature/`, `fix/`, `chore/`). Use the
remainder as the slug (e.g., `feat/user-auth` → `user-auth`).

**Locate PRD and QA runbook:**
1. Scan `docs/` for `prd-<slug>.md` with `Status: Approved`
2. Scan `docs/qa/` for `qa-<slug>.md`
3. If no exact match: list candidate files and ask the user to confirm paths

**Cache the diff:**
```bash
mkdir -p .claude/tmp
git diff "$base_ref" > .claude/tmp/branch-diff.txt
```

Read `.claude/tmp/branch-diff.txt`. If empty, stop and tell the user there
are no changes to review vs main.

### Step 2: Launch 5 Parallel Reviewers

Resolve script paths using 3-location fallback:

```bash
quality_script="$HOME/.claude/skills/drk-code-review/scripts/run_codex_quality_review.sh"
if [[ ! -f "$quality_script" ]]; then
  quality_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/drk-code-review/scripts/run_codex_quality_review.sh"
fi
if [[ ! -f "$quality_script" ]]; then
  quality_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/drk-code-review/scripts/run_codex_quality_review.sh"
fi

spec_script="$HOME/.claude/skills/drk-code-review/scripts/run_codex_spec_review.sh"
if [[ ! -f "$spec_script" ]]; then
  spec_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/drk-code-review/scripts/run_codex_spec_review.sh"
fi
if [[ ! -f "$spec_script" ]]; then
  spec_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/drk-code-review/scripts/run_codex_spec_review.sh"
fi

ref_dir="$HOME/.claude/skills/drk-code-review/references"
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/drk-code-review/references"
fi
```

In a **single message**, launch all 5 reviewers simultaneously:

**Reviewer 1 — Claude Quality (Agent sub-agent):**
Prompt the sub-agent to: read `$ref_dir/claude-quality-prompt.md` for
instructions, read `.claude/tmp/branch-diff.txt` for the diff, read the
changed files in the codebase for context, produce findings with header
`## Findings — Claude Quality`.

**Reviewer 2 — Claude Security (Agent sub-agent):**
Same pattern using `$ref_dir/claude-security-prompt.md`. Output header:
`## Findings — Claude Security`.

**Reviewer 3 — Claude Spec (Agent sub-agent):**
Same pattern using `$ref_dir/claude-spec-compliance-prompt.md`. Also read
`<prd-path>` and `<qa-path>`. Output header: `## Findings — Claude Spec`.

**Reviewer 4 — Codex Quality (Bash, timeout: 600000):**
```bash
mkdir -p .claude/tmp
bash "$quality_script" "$base_ref" ".claude/tmp/codex-quality-review.md"
```

**Reviewer 5 — Codex Spec (Bash, timeout: 600000):**
```bash
bash "$spec_script" "<prd-path>" "<qa-path>" "$base_ref" ".claude/tmp/codex-spec-review.md"
```

**Failure policy:**
- One Codex reviewer fails → note failure, proceed with 4 remaining
- Both Codex reviewers fail → halt, notify user, do not proceed (model
  diversity lost)
- One Claude sub-agent fails → treat same as one Codex failure (tolerated)
- Two or more reviewers fail total → halt, notify user

### Step 3: Synthesize

After all reviewers complete:

1. Collect Claude Quality, Security, and Spec findings from sub-agent outputs
2. Read `.claude/tmp/codex-quality-review.md`
3. Read `.claude/tmp/codex-spec-review.md`
4. Read `$ref_dir/synthesis-prompt.md` for synthesis instructions
5. Produce unified findings list per synthesis instructions:
   - Deduplicate, tag sources, severity-rank
   - Concrete recommendation per finding
   - Medium/Low in reference table only

### Step 4: Write Review Report

```bash
mkdir -p docs/reviews/code-review
```

Save to `docs/reviews/code-review/<timestamp>-<feature>-code-review.md`
where `<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

Report structure:

```
# Code Review: <Feature Name>
**Date:** YYYY-MM-DD
**Branch:** <branch-name>
**Base:** <merge-base short SHA>
**PRD:** <prd-path>
**QA Runbook:** <qa-path>
**Reviewers:** Claude Quality, Claude Security, Claude Spec, Codex Quality, Codex Spec

## Summary
X Critical, Y High, Z Medium, W Low findings.

## Findings

### CR-001 [Critical] <Finding Title>
**Sources:** [Claude Quality] [Codex Quality]
**Location:** `path/to/file.ts:42`
**Issue:** Description of the problem.
**Recommendation:** Concrete proposed fix.

### CR-002 [High] ...

## Medium / Low (reference)
| ID | Severity | Title | Sources | Location |
|----|----------|-------|---------|----------|
| CR-010 | Medium | ... | [Claude Security] | `file.ts:99` |
```

Tell the user: "Review at `docs/reviews/code-review/<path>`. Reply with your
decisions on each Critical/High finding: **approve** the recommendation,
**adjust** it (describe how), or **skip** it."

### Step 5: Apply User Decisions

Wait for the user to reply with decisions on each finding.

For each finding the user **approved** or **adjusted**:
- Apply the fix using `superpowers:receiving-code-review` discipline:
  - Verify the fix is correct for this codebase before applying
  - Push back with technical reasoning if a reviewer suggestion is wrong
  - Apply one fix at a time
  - Run project tests after each fix
- If the user **adjusted** a recommendation, apply their version

For findings the user **skipped**: record as skipped in the final report.

Do not apply Medium/Low findings unless the user explicitly requests them.

### Step 6: Commit and Report

```bash
git add <changed files>
git commit -m "fix: apply code review fixes for <feature>"
```

Report: "N fixes applied. Tests passing. Skipped: X. Report at `<path>`."

### Step 7: Chain to QA Acceptance

Trigger `drk-qa-acceptance` with the QA runbook path (`<qa-path>`).

## Notes

- **Reference file resolution**: look in `$HOME/.claude/skills/drk-code-review/references/`
  first, then `<repo>/skills/drk-code-review/references/`, then
  `<repo>/.claude/skills/drk-code-review/references/`
- The diff is cached to `.claude/tmp/branch-diff.txt` once for consistency
  across all reviewers
- Both Codex reviewers failing is a hard stop — single-model is not acceptable
- Medium/Low are reference-only by default; user can promote them explicitly
- Run project tests before starting the review (not the skill's job to fix
  pre-existing failures)
```

**Step 2: Spec review**

Re-read the SKILL.md. Verify against design doc:
- [ ] 5 reviewer types listed and launched in single message
- [ ] 3-location fallback present for both scripts and ref_dir
- [ ] Failure policy: one tolerated, two halt, both Codex halt
- [ ] Findings written to `docs/reviews/code-review/` (not inline only)
- [ ] User decision step present before applying fixes
- [ ] receiving-code-review discipline mentioned
- [ ] Chains to drk-qa-acceptance at end
- [ ] Notes section present

**Step 3: Commit**

```bash
git add skills/drk-code-review/SKILL.md
git commit -m "feat: add SKILL.md for drk-code-review"
```

---

### Task 8: Update manifest, sync to global, push

**Files:**
- Modify: `manifests/skills.tsv`

**Step 1: Add to manifest**

Append to `manifests/skills.tsv`:
```
claude	skills/drk-code-review	drk-code-review
```

**Step 2: Verify manifest integrity**

```bash
while IFS=$'\t' read -r platform source_path target_name _rest; do
  [[ -z "$platform" || "$platform" == \#* ]] && continue
  [[ -d "$source_path" ]] || { echo "FAIL: missing $source_path"; }
  [[ -f "$source_path/SKILL.md" ]] || { echo "FAIL: missing SKILL.md in $source_path"; }
done < manifests/skills.tsv
echo "Manifest check complete"
```

Expected: `Manifest check complete` with no FAIL lines

**Step 3: Shell syntax check**

```bash
find . -name '*.sh' -not -path './.git/*' -exec bash -n {} +
```

Expected: no output

**Step 4: Sync to global**

```bash
bash scripts/sync-to-global.sh
```

Expected: lines showing `drk-code-review` being synced

**Step 5: Verify in global**

```bash
ls ~/.claude/skills/
```

Expected: `drk-code-review` appears in the list

**Step 6: Commit and push**

```bash
git add manifests/skills.tsv
git commit -m "feat: add drk-code-review to manifest"
git push
```
