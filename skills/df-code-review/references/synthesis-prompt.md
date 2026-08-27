# Synthesis Instructions — Code Review

Merge the discovery pass's findings into a single severity-ranked list, then
adjudicate them. This runs once, over every reviewer that ran the pass. It runs
again after the remediation, over the delta verification's verdicts (Step 7).
Collect only the reviewers that actually ran.

## Step 1: Collect the Pass's Findings

In-session leg:
- Claude Quality: `## Findings — Claude Quality` section
- Claude Security: `## Findings — Claude Security` section
- Claude Spec: `## Findings — Claude Spec` section

Cross-family leg:
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

Critical and High findings are always remediated. For Medium and Low, curate:
remediate the selection that genuinely belongs in the codebase, and record the
rest in a deferred table — do not ask the user to pick.

Deferred table columns: ID, Severity, Title, Sources, Location, Why deferred


## Step 6: Lead Adjudication

You are the lead. The reviewers produced findings; you decide what happens to
each one. Do not aggregate. Filter, contextualize, and decide. The reviewers
saw a diff and a slice of the codebase. You have the full context: the PRD, the
plan, what was already tried and rejected, which code is scaffolding and which
is permanent, and what the next PR in the chain will do.

Excerpted from `interrogate`'s `references/lead-judgment.md`, the normative
home for these rules:

- **Nitpick Gravity.** Reviewers, especially adversarial ones, tend to fill
  their review. If they do not find critical issues, they inflate nits to fill
  the space. If a reviewer's findings are all nits and style preferences, the
  code is probably fine. Say so.
- **Hypothetical versus actual.** "What if someone passes null here" is only a
  finding if a caller can actually pass null. Trace the call site. If the input
  is validated upstream or the type system prevents it, dismiss it. A reviewer
  working from a diff cannot always see the full call chain. You can.
- **Premature abstraction warnings.** Does this code need to change in a second
  way? If not, the extraction is premature. Simple inline code that works beats
  a clean abstraction that is overkill for the current scope.
- **"I would have done it differently."** The most common false positive in
  code review. Not a bug, not a design flaw, not actionable unless the reviewer
  shows a concrete problem with the current approach. Dismiss it and say why.
- **Missing-context signals.** Findings against code the branch did not touch,
  or against patterns consistent with the rest of the codebase, are honest
  mistakes from a reviewer with limited information. Dismiss them gracefully.
- **Verdict calibration.** **If your Act-On list has more than 5 items, you are
  probably not filtering hard enough.** Re-read it and cut.
- **Dismissals are stated, not hidden.** The dismissed list is a trust
  mechanism. It lets the operator override you where they disagree.

Two things pull the other way and win where they apply. Multiple reviewers
flagging the same issue independently is a consensus signal, and agreement
across model families is the strongest version of it. Security findings and
correctness bugs get more scrutiny before dismissal, even from a single
reviewer.

Record a disposition for every finding: `applied as proposed`,
`applied, modified`, `declined — not real`, `declined — accepted but not worth
the cost`, or `deferred`. The disposition and its one-line reason go in the
report, and the accepted ones are what the remediation step acts on.

## Step 7: Delta Verification Synthesis

After the remediation, the verifiers return verdict blocks rather than a fresh
review. Merge them the same way:

- One row per finding: `CONFIRMED` or `NOT CONFIRMED`, with the evidence the
  verifier quoted. A finding raised by more than one reviewer needs a verdict
  from each raiser, and **one `NOT CONFIRMED` makes it `NOT CONFIRMED`**.
- A finding with no verdict is **unverified**, not confirmed. Say so in the
  report; never let silence read as a pass.
- Regression-sweep findings merge into the normal severity list and go through
  adjudication like anything else — with the higher evidence bar
  `delta-verification.md` sets for a new Critical or High after discovery.

The contract for the verification itself is in `delta-verification.md`.

## Output Structure

Produce the full report content (the SKILL.md's finalize step writes it to
disk). Follow the report format defined there exactly.
