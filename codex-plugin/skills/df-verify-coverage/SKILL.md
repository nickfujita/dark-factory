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

Creating a base and authoring planned recipes belong to
`create-verification-skill`, through its distinct operations. Auditing
implemented behavior belongs to `maintain-verification-skill`. This stage
routes to the owner and never restates its steps. It writes no `features/`
entry itself. A coverage verdict proves that the verification plan is complete,
not that future behavior already passed a live run.
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
because a repo gets one verification skill per medium. Read and honor the
project's declared medium ownership before classifying. Supporting HTTP probes
are not automatically another user-facing medium. Answer with the media this
feature actually reaches a user through, not every medium the repo has.

"none" is a real answer. A migration, credential plumbing, or an internal
refactor touches no user-facing medium. Record that and go straight to step 4.

### 3. Locate the verification skill for each medium

A project's verification skills live in the repo's own skill directory, usually
`.agents/skills/verify-*/` or `.claude/skills/verify-*/`, one per medium,
sometimes behind a small index skill. Resolve discovery symlinks to canonical
sources. Distinct skills claiming the same medium are an ownership collision;
stop until an owner and migration are agreed. For each medium from step 2,
read the canonical base, its retained proof, and its `features/` map.

| What you find | What to do |
|---|---|
| No verification skill, or an unproven base, for a touched medium | Invoke `create-verification-skill` in base-creation operation. Name the medium. An unexecuted base remains blocked. |
| A proved base whose map lacks the planned behavior | Invoke `create-verification-skill` in planned-recipe operation with the approved requirements. |
| An entry whose behavior this feature intentionally changes | Invoke `create-verification-skill` in planned-recipe operation. Preserve unaffected cases and label changed behavior pending live verification. |
| An entry that already covers the intended requirements | Record it and its planned or previously exercised status; neither is a new acceptance result. |
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
`create-verification-skill` in planned-recipe operation for a missing recipe, by naming the programmatic
test the plan will carry, or by writing the UNTESTABLE line with a real reason.
Leaving it silent is not an option.

For a user-facing graphical UI change, read the approved prototype record. Every material state and interaction in that record that implements a PRD requirement must appear in the matching feature-map recipe. The prototype clarifies presentation; it does not create a requirement that the PRD does not contain.

**Reverse.** Every map entry this feature adds or changes traces back to a
requirement. One that does not is scope creep. Drop it, or get the requirement
into the PRD first.

Coverage status per requirement:

| Status | Meaning |
|---|---|
| `Covered (recipe)` | a committed recipe specifies the proof; execution is pending |
| `Covered (programmatic)` | UT, IT, or ET only, no recipe |
| `Covered (both)` | a recipe and programmatic tests |
| `UNTESTABLE: <reason>` | cannot be proven, with the reason |

A backend requirement covered only by programmatic tests is
`Covered (programmatic)` and that is acceptable. It is not UNTESTABLE. Do not
manufacture a UI surface to reach `Covered (both)`.

For every user-facing requirement, map each applicable medium to a recipe.
Programmatic tests alone cannot stand in for that user path. Carry the required
automated E2E test plan for each changed user-facing entry as well, per
`../../references/engineering-standards.md`. This is planned coverage, not a
claim that an unimplemented test exists or passes.

Negative requirements are P0. A NEG-xxx without a proof plan blocks the verdict.
Record an inability to prove it, but do not silently exempt a negative requirement.

### 5. Spec guardian check

Read `references/spec-guardian-rules.md` in this skill's own directory.
Apply its medium-aware boundary to the opening description, sub-features, and
user-POV navigation prose of changed entries. The driving section can name
technical handles. Public command flags, protocol messages, and HTTP contracts
are user-visible behavior when that is the declared medium.

Route a planned recipe correction to `create-verification-skill` with the
offending line and approved requirement. Do not invoke a whole-map live audit
to correct planning prose. Internal behavior that has programmatic proof is
`Covered (programmatic)`, not UNTESTABLE merely because it has no UI wording.

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
- <medium> -> <skill-dir> (created | planned-recipes-authored | unchanged | none needed)

Entries to drive:
- <skill-dir>/features/<file>.md#<sub-feature> -> REQ-001, REQ-004
- <skill-dir>/features/<file>.md -> NEG-002

Automated coverage plan:
- <entry>#<sub-feature> -> ET, test path or planned case and meaningful assertion

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
relative so a later stage can open them without the chat context. For mixed
planned and implemented files, name the sub-feature IDs and their status in the
handoff; a file-level status must not hide the distinction.

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
