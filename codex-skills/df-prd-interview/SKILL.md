---
name: df-prd-interview
description: "Interactive PRD authoring through structured interview: guides the user through requirements gathering with probing questions, produces a structured PRD document, and enforces a hard quality gate before the PRD is accepted. Runs when the df feature playbook reaches its PRD stage or when the operator invokes it explicitly — never on its own."
---

# PRD Interview

Conduct a structured interview to produce a PRD (Product Requirements Document)
that passes a hard quality gate. The PRD captures what to build, not how.

## Lane mode

The df router classified the lane before this skill ran. Read it from the run
state and run the matching mode. Ask the operator only if no lane is recorded.
The Quick lane never reaches this skill — it records a finish predicate instead
of a PRD.

| Lane | Mode | Phase 2 coverage | Target question count |
|---|---|---|---|
| Standard | **lite** | topics 1, 2, 4, 8, and one combined pass over 3/5/6/7 | 5 to 8 |
| High-consequence | **full** | all 8 topics, each probed on its own | 8 to 15 |

Lite is a smaller interview, not a lower bar. The quality gate is identical in
both modes, and the same 8 items must pass. What lite drops is the separate
question per topic, not the topic. Write the chosen mode into the round record
and the PRD header's `Lane:` field.

A lite interview that keeps discovering material is telling you the lane was
wrong. Say so and ask the operator to re-lane before continuing. Never
self-escalate to the full interview.

## Before Starting

1. Read the project's CLAUDE.md, README, and recent git log (last 10 commits)
2. Scan `docs/` for existing PRDs to understand naming and conventions
3. Note the project's tech stack and existing patterns
4. Check if `docs/prd-<feature-slug>.md` already exists — if it does, ask
   the user: "A PRD already exists at this path. Should I update it, create
   a new one with a different name, or start fresh and overwrite?"

## Interview Process

### Phase 0: Detect Existing Input

Before starting the interview, check if the user has provided existing
material (a rough PRD, requirements doc, notes, or spec). If so:

1. Read the provided document
2. Identify which Phase 2 topics are already covered
3. Skip covered topics in Phase 2 — only probe for gaps
4. Tell the user: "I see you already have notes covering [topics]. I'll
   focus my questions on the gaps."

If no existing material is provided, proceed with Phase 1.

### Phase 1: Open Exploration

Start with a single open question:

> "What are you building, and what problem does it solve for the user?"

Listen. Do not jump to requirements yet. Understand the motivation and context.
Follow up with at most 2 clarifying questions before moving to structured
probing. After the opening and up to 2 follow-ups, transition to Phase 2
by saying: "Great, let me ask some more specific questions."

**Scoping check:** If the user describes multiple distinct features (e.g.,
"authentication with login, signup, password reset, OAuth, and an admin
panel"), help them scope: "That sounds like N separate features. Which one
should we define first? We can do the others after."

**Effort-Anchor (mandatory, both modes).** Close Phase 1 with exactly this
question:

> "If you did this yourself, how long would it take?"

Record the answer **verbatim**, in the operator's own units, into the PRD
header as `Effort-Anchor:`. Do not convert it, round it, or replace it with an
estimate of your own. If the operator declines to answer, ask once more and
say why the number matters. If they still decline, write
`Effort-Anchor: declined` and say in your Phase 5 report that every downstream
proportionality check is now unanchored.

The anchor is the only number in the pipeline that comes from the operator
rather than from an agent. Every later stage compares its projected cost
against it and stops to ask when the projection exceeds it by the anchor stop
multiple. On the run this rule exists to prevent, the anchor lived in the
operator's head for 35 hours and was never written down anywhere.

### Phase 2: Structured Probing

Ask questions **one at a time**. Prefer multiple choice when possible.
Aim for the question count your lane mode sets (lite 5 to 8, full 8 to 15),
not counting Phase 1. Cover these topics in order:

1. **User flows** — "Walk me through the happy path. What does the user do
   step by step?" Then for each flow: "What could go wrong here?"
2. **Negative requirements** — "What should this feature explicitly NOT do?"
3. **Existing behavior** — "Is there any existing behavior that must not
   change? Any workflows that must keep working exactly as they do today?"
4. **Scope boundaries** — "What's out of scope for this feature? What are
   you deliberately not building?"
5. **Non-functional requirements** — "Any performance, accessibility, or
   security requirements? What are the thresholds?"
6. **Ambiguous terms** — "Are there any terms here that could mean different
   things to different people?"
7. **Constraints & Assumptions** — "Any technical constraints, dependencies,
   or deployment considerations? Any assumptions about the user or
   environment we should state explicitly?"
8. **Priority** — "Which of these requirements are must-haves (P0) vs
   nice-to-haves (P1, P2)?"

Skip topics the user already covered in Phase 1 or in provided material
(Phase 0). Do not re-ask what's already clear.

**In lite mode**, ask topics 1, 2, 4 and 8 as their own questions, then fold
3, 5, 6 and 7 into a single closing question: "Anything that must keep working
exactly as it does today, any performance or security threshold, any term here
that two people could read differently, or any constraint or dependency I
should write down?" A "no" to that closing question is a real answer. Record it
as such rather than probing each fold separately, and let the quality gate
catch what it misses.

**Handling user shortcuts:**
- If the user says "I don't know" — note it as a gap, move on, and flag
  it in the PRD as needing resolution.
- If the user says "skip" — move to the next topic. The quality gate will
  catch any resulting gaps.
- If the user says "just write the PRD" or wants to stop early — move
  directly to Phase 3 with what you have. The quality gate will identify
  what's missing.

### Phase 3: Draft PRD

When you have enough information:

1. Read `references/prd-template.md` for the exact output format.
   (This file is in the skill directory: `${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/df-prd-interview/references/`
   or the repo's `codex-skills/df-prd-interview/references/` directory.
   If the file cannot be found at either location, stop and report the
   error — do not invent a format.)
2. Write the PRD following the template structure
3. Derive the feature slug: take the feature name, lowercase it, replace
   spaces with hyphens, remove all characters except `a-z`, `0-9`, and `-`,
   collapse consecutive hyphens to a single hyphen, trim leading/trailing
   hyphens, truncate to 30 chars. If the result is empty, ask the user
   to provide a slug.
   Confirm with the user: "I'll save this as `docs/prd-<slug>.md` — ok?"
4. Create the `docs/` directory if it doesn't exist: `mkdir -p docs`
5. Save to `docs/prd-<feature-slug>.md`
6. Tell the user: "Draft PRD saved to `docs/prd-<slug>.md`. Please review —
   I'll highlight sections where I had to make assumptions or fill gaps."
   List any assumptions or gaps explicitly.

**Mapping edge cases to requirements:** When drafting the Edge Cases table,
map each edge case discussed during the interview to the REQ-xxx it belongs
to. If an edge case does not clearly map to a single requirement, ask the
user which requirement it should be associated with.

**Author field:** Use the git config `user.name` if available. If not, ask
the user.

**Feature ID field:** Set this to the derived feature slug.

**Lane field:** the lane the router recorded, `Standard` or
`High-consequence`. Never write a lane the operator did not confirm.

**Effort-Anchor field:** the operator's Phase 1 answer, verbatim.

**Status field:** `Draft` or `Hardened` at this stage. `Approved` and
`Approved with open items` are set by `df-prd-challenge`, never here.

**Pinned Parameters table:** fill it from every threshold, limit, timeout,
default, retry budget, size cap and enum the interview surfaced. Requirements
then refer to each parameter by name instead of restating its value. A feature
with no tunables says so in one line; an empty table is a gap, not a pass.

**Decision Register:** the interview leaves the table present and empty.
`df-prd-challenge` owns its rows. Do not delete the section because it has no
rows yet — an absent register is where the next round's re-litigation starts.

**Known open items:** the interview does not write this section. The challenge
round adds it if the PRD is approved with residue.

**Exhaustive inventories are banned.** Never write a census, manifest, or
complete enumeration of anything in the codebase from your own reading. If the
PRD needs one, name the script that generates it and record the requirement as
"inventory generated by `<command>`, reviewed before use". A model-enumerated
inventory is hallucination bait by construction; one measured run shipped a
94-entry census with guessed and nonexistent entries.

### Phase 4: Quality Gate

Evaluate the draft against all 8 gate items. **Important: read each item
as if you are a QA engineer who has never seen this feature. Would you know
exactly what to test and what the expected outcome is?** Do not rubber-stamp
your own work — actively look for items that technically conform but are
too vague to be useful.

1. **Atomic acceptance criteria** — Every criterion is a single, verifiable
   predicate (not prose). Check that no criterion is a tautology of its
   parent requirement (e.g., "the feature works" is not a valid criterion).
2. **Negative/edge cases per requirement** — Every REQ-xxx has at least one
   entry in the Edge Cases table
3. **Measurable NFRs** — NFRs have numeric thresholds and a measurement
   method. If no NFRs apply, the section must say "No non-functional
   requirements identified" with brief justification.
4. **Glossary for ambiguous terms** — Ambiguous terms are defined. If none,
   the section says "No ambiguous terms identified."
5. **Explicit scope boundaries** — Out of Scope is non-empty with specific
   exclusions
6. **At least one requirement** — The PRD has at least one REQ-xxx with
   acceptance criteria
7. **Priority assigned** — Every REQ-xxx has a priority (P0, P1, or P2)
   that was confirmed with the user
8. **Header complete** — `Status`, `Lane`, `Effort-Anchor`, `Author`, `Date`
   and `Feature ID` are all filled, and `Effort-Anchor` is the operator's own
   answer rather than one you produced

The gate is the same in lite and full mode. Lite trims the interview, not the
bar.

See `references/quality-gate-checklist.md` for full details and examples.

- If all pass: set Status to "Hardened", complete Phase 5 output, then
  proceed to Phase 6 to hand the artifact path back to the df router.
- If any fail: tell the user which items failed and what's missing. Ask the
  specific questions needed to fill the gaps. Loop back to Phase 2 for
  those topics only. **Max 3 quality gate attempts.** If the gate still
  fails after the third pass, save the PRD with Status: Draft and report
  which items remain unresolved.

### Phase 5: Output

1. Save the final PRD to `docs/prd-<feature-slug>.md`
2. Check the current git branch. If on `main` or `master`, ask the user:
   "You're on the main branch. Should I create a branch like
   `prd/<feature-slug>` first, or commit here?"
3. Ask the user: "Should I commit this PRD now?" If yes:
   - If the file is new: `git add docs/prd-<feature-slug>.md && git commit -m "docs: add PRD for <feature>"`
   - If updating an existing PRD: `git add docs/prd-<feature-slug>.md && git commit -m "docs: update PRD for <feature>"`
   If the user declines, just report the file location.
4. Report: "PRD saved to `docs/prd-<feature-slug>.md` with status Hardened.
   Ready for the PRD challenge round. (The 'Approved' status is set
   after the challenge round.)"

### Phase 6: Return Challenge-Ready Artifact

After the PRD is Hardened, report the PRD path (`docs/prd-<feature-slug>.md`)
and status. When running under the df feature playbook, stop here so the
router can explicitly invoke `df-prd-challenge` with that path. If
this skill was invoked standalone, tell the user the next stage is
`df-prd-challenge`.

## Key Rules

- **One question at a time.** Never ask multiple questions in one message.
  The lite mode's closing fold is one question, asked once.
- **The Effort-Anchor is the operator's, not yours.** Record it verbatim and
  never revise it later. A stage that finds the anchor wrong escalates to the
  operator; it does not edit the header.
- **Lane comes from the router.** Run the mode the lane names. Never
  self-escalate from lite to full.
- **Multiple choice preferred.** When there are a few obvious options, present
  them as choices rather than asking open-ended.
- **Do not suggest implementation.** The PRD is about requirements, not
  architecture or code. Never mention specific technologies, libraries,
  or design patterns in the PRD.
- **Do not invent requirements.** Only include requirements the user
  explicitly stated or confirmed. Do not add features the user did not
  mention. Ask if unsure.
- **Probe for negatives.** Users rarely volunteer what should NOT happen.
  Always ask.
- **Probe for existing behavior.** Users rarely mention what must stay the
  same. Always ask.
- **Measurable over qualitative.** "Fast" is not a requirement. "< 200ms p95"
  is a requirement.
- **Respect early exits.** If the user wants to stop probing, let them.
  The quality gate catches gaps.
- **Scope to one feature.** If the user describes multiple features, help
  them pick one to start with.
- **Handle existing material.** If the user provides notes, a rough PRD, or
  existing requirements, build on them — do not restart from scratch.
- **Non-UI features.** If the feature has no UI (API, background job, CLI
  tool), acceptance criteria should describe observable outcomes (API
  responses, CLI output, data state) rather than UI assertions. Note in
  the PRD that automated UI testing may not be applicable.
