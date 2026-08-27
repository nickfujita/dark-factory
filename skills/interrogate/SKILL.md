---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Reviewers from both model families challenge changes from independent angles."
disable-model-invocation: true
---

# Interrogate

Spawn one reviewer per model family, Claude and Codex, to adversarially review code changes. Each reviewer gets the same prompt and rubric. The adversarial signal comes from model diversity, not assigned personas. The families differ in blind spots, priors, and reasoning patterns. Agreement across families is high-confidence signal; lone-family findings are worth reading but lower confidence.

The deliverable is a synthesized verdict. Do NOT auto-apply changes.

The df Standard lane's second-opinion pass (D21) is the operator-invoked variant of this shape: one deliberately decorrelated re-review, the other model family or a different rubric lens, lead-adjudicated and counted against the dispatch budget, gates unchanged.

## Step 1, Determine scope

Identify what to review from context:

- If the operator points at specific files or a diff, use that
- If on a feature branch, run `git diff main...HEAD` (or the appropriate base branch) for the full changeset
- If the operator's message references recent work, gather the relevant files

Package the diff (or file contents) plus any surrounding context files the reviewers need to understand the code.

## Step 2, State the intent

Before spawning reviewers, state the intent explicitly. What is this code trying to accomplish? Derive this from:

- The operator's message
- Commit messages
- PR description if one exists
- The code itself

Write one clear paragraph. Reviewers challenge whether the work achieves the intent well, not whether the intent itself is correct. If you're unsure about the intent, ask the operator before proceeding.

## Step 3, Spawn reviewers

The panel is two-family. Launch both reviewers together.

| Reviewer | Transport | Model |
|----------|-----------|-------|
| Claude | Agent tool, background spawn | the discovery-reviewer role in `../df/references/model-policy.md` |
| Codex | codex-exec wrapper | the codex section of `../df/references/model-policy.md` |

Reviewers never touch the live tree. Create a disposable worktree snapshot for the review, point both reviewers at it, and delete it when the review ends. A degraded sandbox can then only touch a throwaway. For a document-sized artifact, put the content in the prompt instead of pointing at files.

The Codex leg runs through the D26 wrapper contract: brief and artifact digest in, structured findings and a terminal status out, with cwd, sandbox flags, an output schema, an exit mapping, and a deadline with a reaper around it.

Resolve models through the roles above, never a hardcoded slug. A role marked inherit omits the model field and runs on the session model.

Read `references/reviewer-prompt.md` and fill in the template with:

1. The stated intent
2. The diff or file contents
3. The review rubric from `references/rubric.md`
4. The code-quality lens from `references/code-quality-review.md`

The same filled template goes to both reviewers, so both families apply the code-quality lens.

Each reviewer produces structured findings as described in the prompt template.

## Step 4, Synthesize

As results come back, build a unified picture:

1. **Parse all findings** from the reviewers
2. **Identify consensus**. Findings raised by both families independently are highest signal.
3. **Identify lone-family findings**. Still worth reading, but weight accordingly.
4. **Deduplicate**. The two families may describe the same issue differently. Merge these and note which family raised it.
5. **Note disagreements**. If one family flags something and the other explicitly says the opposite, that's useful context for the verdict.

## Step 5, Lead judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator.

Read `references/lead-judgment.md` for the full framework. Reviewers only see a slice of the codebase. You have the full context (the goal, the constraints, the timeline, which tradeoffs were already considered). Use that context aggressively.

Categorize every finding using these buckets:

- **Act on**. Real issues affecting correctness, security, or maintainability given the actual goals. These would block a real PR.
- **Consider**. Legitimate points, but you're not sure they outweigh the cost of addressing them right now. Worth the operator's attention.
- **Noted**. Technically valid but not actionable. Context-dependent, premature optimization, or low-impact given the current stage.
- **Dismissed**. Wrong, nitpicky, or missing context. Brief explanation why.

For each finding, include:

- Which family raised it
- The category (act on / consider / noted / dismissed)
- A one-line rationale for the categorization

## Output format

Present the verdict in this structure:

### Intent
> [The stated intent paragraph from Step 2]

### Reviewers
- Reviewer [family]: [model name], [N findings] (one bullet per reviewer)

### Act On
[Findings that should be addressed. For each: description, which family raised it, why it matters.]

### Consider
[Findings worth thinking about. For each: description, which family raised it, tradeoff involved.]

### Noted
[Valid but low-priority. Brief list.]

### Dismissed
[Rejected findings with brief rationale. This shows the operator what was filtered out and why, so they can override your judgment if they disagree.]

### Agreement Map
[Where did the families agree, where did they diverge, and what does the pattern of agreement and disagreement tell us?]
