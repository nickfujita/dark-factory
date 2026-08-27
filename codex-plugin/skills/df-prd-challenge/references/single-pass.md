# Standard lane: the single-pass challenge

The Standard lane runs one review pass with two reviewers, one from each model
family, on the **same prompt**. There are no personas and there are no rounds.
The adversarial signal comes from model diversity, not from assigned roles.

This file is harness-neutral on purpose. Both trees run the same contract; only
the transport differs. "The in-session leg" is the reviewer the driving harness
spawns itself. "The cross-family leg" is the other harness, reached through the
runner script the calling skill names.

## The sequence

Six steps, in order, once each. Nothing here loops.

| # | Step | Dispatches |
|---|---|---|
| 1 | Both reviewers run the shared rubric below, in parallel, on the same PRD sha256 | 2 |
| 2 | Lead adjudication of the merged findings | 0 |
| 3 | One autonomous remediation wave | 0 |
| 4 | The post-remediation consistency gate | 0 |
| 5 | One delta verification of that wave, one leg per family | 2 |
| 6 | Terminate: approve, approve with open items, or escalate | 0 |

Every dispatch reserves through the run-state store before it spawns. Four
reservations is the whole shape. A fifth and sixth exist only for the
operator-invoked second-opinion pass, and the operator invokes it; the skill
never reaches for it on its own.

Step 5 is a delta verification in exactly the sense
`personas.md` § "Mode: delta verification" defines. It is scoped to the
remediation, per-finding `CONFIRMED` or `NOT CONFIRMED`, plus a regression
sweep over the prose the remediation added. It is never a second discovery
pass over the whole document.

If step 5 comes back with `NOT CONFIRMED` items, the calling skill's
`VERIFY_RETRY_LIMIT` governs, exactly as in the hardened loop. Exhausting it
escalates to the operator. It does not open a round.

## The shared rubric

Both reviewers receive this prompt verbatim. Do not tailor it per leg, do not
add a persona framing, and do not tell either reviewer what the other is
looking at. Identical prompts across families is the whole design: where the
two disagree is the signal.

```
You are an independent reviewer examining a PRD (Product Requirements Document).

Read the PRD, then explore the codebase to ground your analysis in what
actually exists. Cite real files and real lines. A search that finds nothing is
a valid answer; an invented file path is not.

Report what is wrong with this document as a specification. Cover, in one pass:

- Behavior that is missing, undecided, unbounded, or not testable.
- Requirements that contradict each other, or contradict the codebase.
- Acceptance criteria that do not actually test their requirement.
- Thresholds, limits, timeouts and payload sizes left unstated.
- Edge cases and failure states with no stated outcome.
- Terms that two readers could reasonably read differently.
- Scope that exceeds the stated purpose, and requirements that duplicate
  functionality the codebase already has.

Do NOT propose new features. Do NOT propose an architecture or an
implementation approach. Do NOT propose removing a requirement that the PRD's
Decision Register records as operator-ratified; if you still think it should
go, say so as a note that cites the register entry.

Emit findings using the shared output contract you were given: one block per
finding, with severity, Class, Requirement, Issue, and Recommendation.

If you have no findings, say so explicitly. An empty result is a valid
outcome. Do not manufacture findings to fill the review, and do not return an
empty document.
```

The shared output contract, including the mandatory `SUBSTANTIVE` /
`CONSISTENCY` class and its tie-break, is defined once in `personas.md`
§ "Shared output contract". Send it with the rubric.

## Adjudication

The lead adjudicates. Reviewers advise; the lead decides. The filtering rules
are in `synthesis-prompt.md` § "Lead adjudication", and they bind here the same
way they bind in the hardened loop: Nitpick Gravity, an Act-On list over five
items means under-filtering, and every dismissal is stated with its reason
rather than hidden.

Two reviewers on one prompt gives one extra signal the hardened loop's persona
panel does not: **agreement across families is high-signal, and disagreement is
where to look.** A finding both legs raised independently gets weight. A
Critical raised by one leg that the other read the same text and did not raise
is the finding to trace to a real execution path before acting on it.

## Terminating

The Standard pass ends in exactly one of three outcomes, decided after step 5:

- **Approved.** Zero Critical and zero High outstanding, and every remediation
  in the wave came back `CONFIRMED`.
- **Approved with open items.** Only `CONSISTENCY`-class residue remains. It
  goes into the PRD's "Known open items — read first" section.
- **Escalated.** Any `SUBSTANTIVE` residue, any unverified remediation, or a
  cross-family leg that could not run in a lane where its absence blocks.

There is no fourth outcome, and specifically there is no "one more round". A
Standard pass that wanted a second round is telling you the lane was wrong.
Say that to the operator and let them re-lane. Escalating to
High-consequence is the operator's decision, never the loop's.
