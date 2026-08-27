# Synthesis Instructions — Code Review

Merge this round's findings into a single severity-ranked list. This runs once
per round in both phases (Phase A: the 3 Claude reviewers; Phase B: the 2 Codex
reviewers). Collect only the reviewers that ran this round.

## Step 1: Collect This Round's Findings

Phase A (Claude rounds):
- Claude Quality: `## Findings — Claude Quality` section
- Claude Security: `## Findings — Claude Security` section
- Claude Spec: `## Findings — Claude Spec` section

Phase B (Codex rounds):
- Codex Quality: read `<REVIEW_ROOT>/codex-quality-review.md`
- Codex Spec: read `<REVIEW_ROOT>/codex-spec-review.md`

(`REVIEW_ROOT` is the run-scoped scratch directory created in the skill's
Step 1 — substitute the concrete path.)

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

Each finding must have a concrete, actionable recommendation that includes
both the reasoning and the fix:
- Explain WHY the current code is problematic — what risk it creates, what
  invariant it violates, or what failure mode it enables
- Then describe WHAT the fix should look like — a specific code change, not
  "improve error handling"
- Include a short code snippet where it clarifies the fix
- If reviewers disagree on the fix, present both options briefly and note
  the trade-off
- The recommendation must be understandable on its own (without reading the
  full report context) so it works in a TTS-friendly chat summary

## Step 5: Medium / Low

Critical and High findings are always remediated this round. For Medium and
Low, curate: remediate the selection that genuinely belongs in the codebase,
and record the rest in a deferred table — do not ask the user to pick.

Deferred table columns: ID, Severity, Title, Sources, Location, Why deferred

## Output Structure

Produce the full report content (the SKILL.md Step 4 writes it to disk).
Follow the report format defined there exactly.
