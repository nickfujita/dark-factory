# QA Validation Synthesis Prompt

After both reviewers complete, synthesize findings into a single prioritized
list with semantic classification.

## Synthesis Instructions

Read both review outputs (Codex inline review + Codex CLI). Each output has
a self-identifying header (`## Findings — Codex Inline` or `## Findings — Codex CLI`).
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
   - `[Codex Inline]`, `[Codex CLI]`, or `[Codex Inline + Codex CLI]`

6. **Format**:

```
## Validation Findings

### Critical

#### [Finding title] [Codex Inline + Codex CLI] [PROPOSED]
**Category:** Coverage
**Requirement:** REQ-xxx / TC-xxx
**Issue:** [Merged description from both reviewers]
**Proposed change:** [Specific edit to PRD or QA runbook]

---

### High

#### [Finding title] [Codex CLI] [AUTO-FIX]
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
