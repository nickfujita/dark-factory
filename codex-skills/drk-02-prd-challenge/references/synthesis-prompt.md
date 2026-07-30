# Challenge Round Synthesis Prompt

After a review round's reviewers complete, synthesize their findings into a
single prioritized list for that round. This runs once per round in both
phases (Phase A: the 3 Codex personas; Phase B: Claude Code via tmux).

## Synthesis Instructions

Read this round's review outputs. Each output has a self-identifying header
(e.g., `## Findings — Skeptical User Advocate`). Produce a unified findings
list for the round.

**If any reviewer produced no findings or empty/malformed output**, note
this explicitly: "[Source] No findings produced — possible tool failure.
Do not treat absence of findings as endorsement." Continue synthesis with
the remaining reviewers' outputs.

1. **Deduplicate**: If multiple reviewers raised the same concern, merge into
   one finding. Note which reviewers flagged it (higher confidence).

2. **Resolve severity disagreements**: When reviewers disagree on severity
   for the same finding, use the **highest** severity assigned by any
   reviewer. Note the disagreement.

3. **Prioritize by severity**:
   - **Critical**: Listed first. Must be remediated this round before the
     phase can pass its gate.
   - **High**: Listed second. Must be remediated this round before the phase
     can pass its gate.
   - **Medium**: A curated selection is remediated this round (the ones that
     genuinely strengthen the PRD); the rest are recorded as deferred.
   - **Low**: Same as Medium — curate and remediate the worthwhile ones, defer
     the rest.

4. **Tag source**: Each finding shows which reviewer(s) raised it:
   - `[User Advocate]`, `[Tech Feasibility]`, `[Scope Challenger]`, `[Codex]`
   - Findings from multiple reviewers: `[User Advocate + Codex]`

5. **Format**:

```
# PRD Challenge Round: <Feature Name>

**Date:** YYYY-MM-DD
**PRD:** <prd-path>
**Reviewers:** Skeptical User Advocate, Technical Feasibility, Scope & Complexity, Codex

## Summary

X Critical, Y High, Z Medium, W Low findings.

## Findings

### Critical

#### [Finding title] [User Advocate + Tech Feasibility]
**Requirement:** REQ-xxx
**Issue:** [Merged description from both reviewers]
**Recommendation:** [What should change in the PRD and why — explain the reasoning behind the fix so the reader understands the risk being mitigated]
**Remediation applied:** [What you actually changed in the PRD to resolve this — or, if deferred, the reason]

---

### High

#### [Finding title] [Codex]
**Requirement:** REQ-xxx
**Issue:** [Description]
**Recommendation:** [What should change in the PRD and why]
**Remediation applied:** [What you actually changed in the PRD to resolve this]

---

### Medium (for reference)

#### [Finding title] [Scope Challenger]
...

### Low (for reference)

#### [Finding title] [User Advocate]
...
```

6. **Summary line**: The report header includes the count. The report
   file must be self-contained — it should be readable without the
   original chat context.
