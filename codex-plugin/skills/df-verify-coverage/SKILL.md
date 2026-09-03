---
name: df-verify-coverage
description: "Decide whether a feature can be proven and whether the recipe is committed. Reads the hardened PRD, classifies the feature by type and by user-facing medium, points each medium at the project's verification skill, and checks bidirectional coverage between requirements and committed recipes. Produces a verdict and the feature-map entries acceptance will drive, not a document. Runs when the df feature playbook reaches its verification-coverage stage or when the operator invokes $df-verify-coverage. Never enter on your own."
---

# Verification coverage

One question. Can this feature be proven, and is the recipe committed?

This stage writes no document. It reads the hardened PRD, decides which
user-facing media the feature touches, makes sure a verification skill covers
each one, and checks that every requirement traces to a proof. What it hands
the next stage is a verdict plus the list of feature-map entries acceptance
will drive.

## What this skill does not own

Creating a project verification skill belongs to `create-verification-skill`.
Keeping one honest belongs to `maintain-verification-skill`. This stage invokes
them and never restates their steps. It writes no `features/` entry itself.
Catching yourself explaining how to shape a Launch section or a feature file
means the work belongs to one of those two skills. Delete the explanation and
invoke the owner.

## Prerequisites

- A PRD with Status Hardened, Approved, or Approved with open items
- A PRD that passed its quality gate, so its acceptance criteria are testable
- For a user-facing graphical UI change, the approved prototype record from df-design

## Workflow

### 1. Read the PRD

Locate the PRD in this order.

1. An explicit path from the operator or from the previous pipeline step.
2. A path named in the conversation.
3. A scan of `docs/` for `prd-*.md`. Exactly one match with an accepted status
   wins. Several matches means list them and ask which one. That is the only
   question this stage initiates.
4. No match means stop and report "No PRD file found. Please provide the path
   to the PRD."

Read it and check the Status field. Anything other than Hardened, Approved, or
Approved with open items is a stop, reported as "PRD status is `<status>`.
Verification coverage requires a Hardened or Approved PRD."

Status "Approved with open items" means the PRD carries a "Known open items"
section listing questions the challenge round deliberately left open. Read it
first. Never invent answers for those items. Carry each one into the verdict so
the next stage sees the same caveat the implementer does.

Extract:

- every requirement (REQ-xxx) with its acceptance criteria
- every negative requirement (NEG-xxx) with its related requirements
- every row of the Edge Cases table
- preconditions from Constraints & Assumptions
- the feature name, and the priority of each requirement, defaulting to P1

Derive the feature slug from the PRD filename. Strip the directory, the `prd-`
prefix, and the `.md` suffix, then lowercase the rest. `docs/prd-User-Auth.md`
gives `user-auth`. Later stages name evidence directories from this slug, so
derive it once here and pass it on.

### 2. Classify the feature

Two questions, both answered from the PRD.

**Type.** What kind of feature is this?

| Type | Signals | What proves it |
|---|---|---|
| ui | pages, modals, forms, layouts, navigation, user-facing workflows | recipes driven against a real surface |
| backend | protocols, engines, policies, data pipelines, SDKs, APIs, cryptographic operations | programmatic tests, plus a recipe wherever the change surfaces |
| hybrid | both, with independently testable behavior on each side | both |

Default to hybrid when uncertain. It forces the wider search.

**Medium.** Which user-facing media does this feature touch? Web UI, CLI or
TUI, API, MCP, desktop, or none. A feature can touch several and most hybrid
features do. Media decide which verification skills are in scope for step 3,
because a repo gets one verification skill per medium. Answer with the media
this feature actually reaches a user through, not every medium the repo has.

"none" is a real answer. A migration, credential plumbing, or an internal
refactor touches no user-facing medium. Record that and go straight to step 4.

### 3. Locate the verification skill for each medium

A project's verification skills live in the repo's own skill directory, usually
`.agents/skills/verify-*/` or `.claude/skills/verify-*/`, one per medium,
sometimes behind a small index skill. For each medium from step 2, find the
skill whose medium matches and read its `features/` map.

| What you find | What to do |
|---|---|
| No verification skill for a medium this feature touches | Invoke `create-verification-skill`. Name the medium in the reply. |
| A skill whose `features/` map has no entry covering this feature | Invoke `maintain-verification-skill` to add the entry. |
| An entry that describes behavior this feature changes | Invoke `maintain-verification-skill` to correct it. A stale entry silently redirects the proof. |
| An entry that already covers this feature and still matches | Nothing. Record it. |
| No user-facing medium | No map entry is needed. Record "no user-facing medium" with the reason. |

Never write a map entry yourself and never invent an entry id to make coverage
look complete. An invented entry is theater and the gap it hides is the finding.

Invoking the generator here is the deliberate invocation the router means, not
a silent mid-run creation. It adds a committed skill to the project repo, so
say in the reply that you did it and for which medium.

### 4. Bidirectional coverage

This is the check the stage exists for. It runs in both directions and both are
mandatory.

**Forward.** Every REQ-xxx and every NEG-xxx traces to one of these:

- a feature-map entry or sub-feature, named by its path and id
- a programmatic test (UT, IT, or ET), named by what it will assert
- `UNTESTABLE: <reason>`, written in that exact form

A requirement with none of the three is a gap. Close it by invoking
`maintain-verification-skill` for a missing recipe, by naming the programmatic
test the plan will carry, or by writing the UNTESTABLE line with a real reason.
Leaving it silent is not an option.

For a user-facing graphical UI change, read the approved prototype record. Every material state and interaction in that record that implements a PRD requirement must appear in the matching feature-map recipe. The prototype clarifies presentation; it does not create a requirement that the PRD does not contain.

**Reverse.** Every map entry this feature adds or changes traces back to a
requirement. One that does not is scope creep. Drop it, or get the requirement
into the PRD first.

Coverage status per requirement:

| Status | Meaning |
|---|---|
| `Covered (recipe)` | a committed feature-map entry proves it |
| `Covered (programmatic)` | UT, IT, or ET only, no recipe |
| `Covered (both)` | a recipe and programmatic tests |
| `UNTESTABLE: <reason>` | cannot be proven, with the reason |

A backend requirement covered only by programmatic tests is
`Covered (programmatic)` and that is acceptable. It is not UNTESTABLE. Do not
manufacture a UI surface to reach `Covered (both)`.

Negative requirements are P0. A NEG-xxx with no proof blocks the verdict.

### 5. Spec guardian check

Read `references/spec-guardian-rules.md` in this skill's own directory. Its
Scope section names the retired runbook's browser test cases. The forbidden and
allowed content lists are what carry over. The scope that applies is the one
named here.

The scope is the user-POV prose of the feature-map entries this run added or
changed, meaning each entry's "How to get to it" section. The harness recipe
section is exempt for the same reason programmatic test specs were exempt. It
necessarily names selectors, commands, and endpoints.

Scan for the forbidden content the rules list. Code identifiers, internal API
routes, database references, internal architecture, HTTP details, and
infrastructure or configuration names.

A violation is drift in the map, so the fix belongs to
`maintain-verification-skill` and not to an edit from this stage. Route it there
with the offending line quoted. A requirement that cannot be described in
user-visible language at all is `UNTESTABLE: <reason>` in step 4.

If step 3 or step 5 changed the map, re-run step 4 over the changed entries
only, once. Whatever still fails after that re-run goes into the verdict as a
named gap. There is no third pass.

### 6. Verdict and handoff

Report one block in the reply. It is this stage's whole output and nothing is
written to disk.

The verdict is exactly one of these:

- **covered.** Every requirement has a proof, every added entry traces back,
  and no gap is open.
- **covered with exemptions.** The same, except for requirements recorded as
  UNTESTABLE with reasons the operator can read.
- **blocked.** A requirement has no proof and no exemption, or a needed
  verification skill could not be created. Name what blocks it and stop.

The block:

```
Feature: <name> (slug <feature-slug>)
PRD: <path>, status <status>
Type: ui | backend | hybrid
Media: <medium>[, <medium>...] | none
Verdict: covered | covered with exemptions | blocked

Verification skills:
- <medium> -> <skill-dir> (created | maintained | unchanged | none needed)

Entries to drive:
- <skill-dir>/features/<file>.md#<sub-feature> -> REQ-001, REQ-004
- <skill-dir>/features/<file>.md -> NEG-002

Programmatic only:
- REQ-003 -> IT, what it will assert

Untestable:
- REQ-007 UNTESTABLE: <reason>

Open items carried from the PRD:
- <item>
```

"Entries to drive" is the handoff `df-acceptance` executes. One line per entry,
the entry path and the requirements that entry proves, sub-feature after a `#`
when the entry is driven at sub-feature granularity. Keep the paths repo
relative so a later stage can open them without the chat context.

An empty entry list is legal only when Media is none. Omit a section that has
no rows, except Verdict, Media, and "Entries to drive", which are always
present.

### 7. Hand off to validation

Report the PRD path and the entry list from step 6. When running under the df
feature playbook, stop here so the router can explicitly invoke
`df-qa-validation` with both. If this skill was invoked standalone, tell the
user the next stage is `df-qa-validation`.

A blocked verdict hands off to nothing. Report it and stop.

## Notes

- This stage runs without asking questions, except to disambiguate which PRD
  to use.
- A requirement that cannot be turned into a proof gets an UNTESTABLE reason,
  never a guess at intent.
- Bidirectional coverage is the quality bar. Forward-only coverage hides scope
  creep and reverse-only coverage hides gaps.
