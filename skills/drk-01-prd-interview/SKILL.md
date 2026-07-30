---
name: drk-01-prd-interview
description: "Interactive PRD authoring through structured interview. Use when starting a new feature, writing requirements, creating a PRD, or when the user says 'let's define what to build'. Guides the user through requirements gathering with probing questions, produces a structured PRD document, and enforces a hard quality gate before the PRD is accepted."
---

# PRD Interview

Conduct a structured interview to produce a PRD (Product Requirements Document)
that passes a hard quality gate. The PRD captures what to build, not how.

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

### Phase 2: Structured Probing

Ask questions **one at a time**. Prefer multiple choice when possible.
Aim for 8-15 questions in Phase 2 (not counting Phase 1). Cover these
topics in order:

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
   (This file is in the skill directory: `$HOME/.claude/skills/drk-01-prd-interview/references/`
   or the repo's `skills/drk-01-prd-interview/references/` directory.
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

### Phase 4: Quality Gate

Evaluate the draft against all 7 gate items. **Important: read each item
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

See `references/quality-gate-checklist.md` for full details and examples.

- If all pass: set Status to "Hardened", complete Phase 5 output, then
  proceed directly to Phase 6 to trigger the challenge round.
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
   Triggering the PRD challenge round now. (The 'Approved' status is set
   after the challenge round.)"

### Phase 6: Trigger Challenge Round

After the PRD is Hardened, trigger the `drk-02-prd-challenge` skill using the same
PRD path (`docs/prd-<feature-slug>.md`).

1. Start the challenge round immediately after Phase 5.
2. Pass the hardened PRD path explicitly.
3. Only skip this trigger if the user explicitly asks to defer it.

## Key Rules

- **One question at a time.** Never ask multiple questions in one message.
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
