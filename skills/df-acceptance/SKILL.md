---
name: df-acceptance
description: "Drive a feature's committed verification recipes on the real surface and write the evidence record. Takes the feature-map entries named by df-verify-coverage, drives each one through the project's own verification skill, and produces an immutable timestamped PASS/FAIL/BLOCKED record. Runs when the df feature playbook reaches its acceptance stage or when the operator invokes /df-acceptance. Never enter on your own."
disable-model-invocation: true
---

# Acceptance execution

Drive the feature's committed verification recipes on the real surface, then produce the evidence record.

The recipes are not in this skill and they are not in a generated document. They live in the project's own verification skill, in its `features/` map, maintained by the project. This skill drives them and records what happened. It never restates them and never invents its own way in.

## What this skill owns

One thing. A feature map says how to verify a feature. It never says that this change was verified, on this commit, with this evidence, on this date. That per-run fact is the deliverable here.

## Prerequisites

- A coverage handoff from `df-verify-coverage` in the session, with a non-blocked verdict and the entries this run must drive
- A project-local verification skill for each medium the handoff names, with a `features/` map
- The application launchable through that skill's Launch section
- `agent-browser` installed when any named medium is a browser surface
- For rerun mode, a previous immutable record and its latest pointer for the same feature slug

## Workflow

### Step 1. Read the coverage handoff

The input is the handoff block `df-verify-coverage` reports at the end of its run. That stage writes nothing to disk, so the block lives in the session. Read it. Do not build your own list.

The block names the feature and its slug, the media the feature reaches a user through, the coverage verdict, the verification skill for each medium, and the entries to drive. Each entry line looks like this.

```
<skill-dir>/features/<file>.md#<sub-feature> -> REQ-001, REQ-004
```

The path is repo relative and carries the skill directory, so the medium comes from the block's verification-skill lines. The `#<sub-feature>` suffix is present when coverage narrowed the entry to one sub-feature. The requirement ids after the arrow are what that entry proves, and they travel into the record so the evidence traces back to the PRD.

Treat the list as closed.

- Never invent an entry id or an entry path. A path with no file on disk is BLOCKED for that leg, reported with the path.
- Never widen the list. An entry that is not in the handoff is out of scope for this run, however tempting it looks.
- No handoff in the session means the coverage stage has not run. Say so and name it. Re-running that stage is the fix. Do not derive a substitute list.
- A `blocked` coverage verdict hands off to nothing, so acceptance should not have started. If it did, stop and report the coverage blocker.
- `Media: none` with an empty entry list means the change reaches no user-facing surface. There is nothing to drive. Record that and stop.

**Read the verification skill for each medium.** A repo has one verification skill per user-facing medium, sometimes behind a short index skill. A feature spanning two media drives through two skills, one leg each. For every skill in play, read its Launch, Doctor, Drive, Evidence, and Cleanup sections, and read the feature map README for baseline preconditions, driving conventions, and proof rules. Those five sections are the contract. This skill supplies discipline and the record, not the recipe.

**Read each named entry.** A feature file carries four H2 sections. `Sub-features` lists the behaviors. `How to get to it (user POV)` lists every user entry point. `Driving it with <harness>` carries a `Preconditions:` line and the labeled bullets that pair each user action with an exact command and an observable result. `Gotchas` lists the traps. Read `Gotchas` before driving, not after failing.

**Environment safety.** Only drive local, dev, or test targets (`localhost`, `127.0.0.1`, `::1`, `.local`, `.test`, `.dev`). If a verification skill's Launch section points at a production-like host, stop and ask for a non-production target.

**Feature slug.** Take it from the handoff block. It only names the output files.

**Mode.** `full` runs every entry in the handoff and is the default. `rerun-failed` runs only the legs that failed or were blocked in the most recent record.

### Step 2. Launch and doctor

Route readiness through the verification skill. Do not improvise it.

1. Run the skill's Launch command exactly as written, and wait for the readiness signal it names.
2. Run its Doctor check. Doctor is the gate, and its answer is the one that counts. A process that is up but on the wrong build, the wrong data directory, or an expired session is not ready.
3. Honor whatever isolation the skill declares, such as a disposable data directory, a named harness session, or a dedicated port. Two runs sharing one instance corrupt each other.
4. Dismiss overlays that block interaction, such as cookie banners, onboarding modals, and dialogs, before the first leg.

Never auto-discover a startup command from `package.json` or a Makefile. Never guess a port. Never drive an instance the skill did not tell you to drive. If Launch does not work as written, that is drift in the verification skill and it is a finding, not an obstacle to route around.

If launch or doctor cannot be made to pass, run the skill's Cleanup, mark every leg BLOCKED with the doctor output quoted, write the record anyway, and stop. A blocked run still produces a record.

**agent-browser is a hard requirement for a browser surface.** It ships its own plugin and its skill is a discovery stub, so never restate its documentation and never work from a cached copy. Ask the CLI with `agent-browser skills get core`. When a browser surface needs driving and agent-browser is absent, stop and say so. Do not substitute a fetch tool, a screenshot you cannot interact with, or a test that asserts on markup instead of the running app.

Create the evidence directory the skill's Evidence section names. When it names none, fall back to `<run-dir>/evidence/<feature-slug>/`, where `<run-dir>` is `bash scripts/df-state.sh path "<run-id>"`. That is the run's own directory in the agent's store, outside the repo, so evidence never dirties the project's tree.

### Step 3. Drive the entries

The unit of work is one leg. A leg is one entry, or one sub-feature of it, on one medium, reached through one entry point. An entry whose `Sub-features` section splits into behaviors that need separate proof gets one leg each.

Drive every entry point the `How to get to it (user POV)` section lists. A proof that drives one convenient entry point when the map lists three is incomplete, and the two that were skipped are BLOCKED, not passed.

For each leg:

**0. Reset.** Return to the baseline state the feature map README describes. Each leg starts from a known state, never from the previous leg's ending state.

**1. Preconditions.** Check the `Preconditions:` line under `Driving it with <harness>`. A precondition the run can satisfy through the documented path gets satisfied. One it cannot satisfy makes the leg BLOCKED, with the precondition named.

**2. Execute the bullets.** Run the labeled bullets in order, literally. Each bullet pairs a user action with an exact command and an observable result. Keep quoted names and flags unchanged. The map wrote the command deliberately.

**3. Prove each bullet against its stated observable end state.** That sentence is the assertion. Do not soften it, do not swap it for an easier one, and do not accept a weaker signal in its place.

**4. Capture evidence** per the verification skill's Evidence section and the map README's proof rules. Record which entry and entry point produced each artifact.

**5. Record the leg verdict.**

**The pass is hands-off.** Every leg runs from the committed recipe with no help. If you clicked past a stuck dialog by hand, re-ran a command with a flag the recipe does not carry, edited state directly to make a step go through, or nudged the app in any way the recipe does not describe, that leg FAILED and the intervention is the bug. Record what you had to do. It is either a product defect or map drift, and both are findings. Never record the post-intervention outcome as the leg's result.

**Drive the real user path.** Never internal setters, never test-only endpoints, never a debug route that skips the flow, never a direct write to storage to reach a state a user reaches through the surface. If the only way to reach a state is a back door, the leg is BLOCKED and the map is missing a user route.

**Capture the action and the resulting state, not just the final screen.** A screenshot of an end state proves nothing about how it was reached. Verify side effects alongside what is visible, such as files written, rows inserted, and messages sent.

**Verdicts.** Every leg gets exactly one of three.

- **PASS.** The recipe ran hands-off and every observable end state it names was observed.
- **FAIL.** The recipe ran and something it names did not happen, or it happened only after intervention.
- **BLOCKED.** The leg could not be run at all. A missing precondition, an unreachable entry point, a missing harness, an entry id with no file, or a lost session.

BLOCKED is not a soft pass. A blocked leg is unverified, and it stays unverified until something changes. A leg only earns BLOCKED by naming the concrete unmet prerequisite and the route attempted. Without those it is a FAIL.

**The feature's verdict is the weakest leg.** One FAIL makes the feature FAIL. No FAIL and any BLOCKED makes it BLOCKED. Only all-PASS makes it PASS. Never average the legs and never report the feature as mostly passing.

**Failure inside a leg.** The first failing bullet fails the leg. Skip that leg's remaining bullets, capture the failure evidence, and move to the next leg. Later bullets in a failed leg produce cascading, meaningless results.

**Retry policy.** A harness command that errors out, such as an element not found or a transport error, gets one retry after a settle and a fresh read of the current state. An observable end state that was not observed is never retried. That is a real outcome, not a flake.

**Continue between legs.** Run every leg in the handoff before reporting. Do not stop at the first failure.

**Failure capture.** Write failure artifacts where the Evidence section says, or to `<run-dir>/evidence/<feature-slug>/` when it says nothing. Capture on failure only.

### Step 3b. Error recovery

If a harness command errors or hangs:

1. Treat it as a leg failure and record the error text.
2. Before the next leg, re-run the verification skill's Doctor.
3. If doctor fails, follow the skill's Cleanup and Launch to restart once.
4. If the restart fails, halt the run. Mark every remaining leg BLOCKED with `session lost after <entry-id>`.
5. Go to Step 4 and write whatever was collected.

A partial record is the deliverable when the run cannot finish. A run that halts with no record is worse than a FAIL, because nothing downstream can see what was proven.

### Step 4. Write the evidence record

Write immutable records in `docs/qa`, creating the directory if needed.

- `full` mode writes `docs/qa/qa-<feature-slug>-results-<timestamp>.md`
- `rerun-failed` mode writes `docs/qa/qa-<feature-slug>-results-rerun-<timestamp>.md`

Maintain the latest pointers alongside them.

- `docs/qa/qa-<feature-slug>-results-latest.txt` holds one line, the path to the latest immutable record
- `docs/qa/qa-<feature-slug>-results-latest.md` is a copy of that record
- After writing the immutable record, run `printf '%s\n' "<record-path>" > docs/qa/qa-<feature-slug>-results-latest.txt` and `cp "<record-path>" docs/qa/qa-<feature-slug>-results-latest.md`

**For `full` mode**, write every leg.

**For `rerun-failed` mode**, read the previous record through `docs/qa/qa-<feature-slug>-results-latest.txt` first. Carry forward the results of legs that were not rerun, replace only the legs re-executed, and include every leg from the previous record.

```markdown
# QA acceptance results: <feature name>

**Date:** YYYY-MM-DD
**Commit:** <sha>
**Branch:** <branch>
**Mode:** full | rerun-failed
**Verdict:** PASS | FAIL | BLOCKED
**Legs:** X PASS, Y FAIL, Z BLOCKED
**Verification skills:** <path> at <revision> for <medium>, one line per medium

| Leg | Entry | Sub-feature | Medium | Entry point | Proves | Result | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | search | search-match | web UI | toolbar button | REQ-001 | PASS | artifacts/search/results.png |
| 2 | search | search-cli | CLI | `notes search` | REQ-004 | FAIL | artifacts/search/cli.txt |
| 3 | export | export-pdf | web UI | File menu | NEG-002 | BLOCKED | |

## Failures

### Leg 2: search / search-cli
**Bullet:** <the labeled bullet that failed>
**Expected:** <the observable end state the recipe names>
**Actual:** <what was observed>
**Evidence:** <path>
**Intervention:** none | <what was done by hand, which is itself the bug>

## Blocked

### Leg 3: export / export-pdf
**Unmet prerequisite:** <the concrete thing that was missing>
**Route attempted:** <the entry point and the command>

## Map drift observed

<Entries whose recipe no longer matches the app, with the bullet and what the app did instead. Reported here, fixed elsewhere.>
```

The `Proves` column carries the requirement ids the handoff attached to that entry. It is what ties the evidence back to the PRD without a second document.

The commit sha and the verification skill revision are what make the record checkable six weeks later. A record that cannot be tied to a commit and a map revision proves nothing.

This file is committed to the project, so write it in the project's vocabulary. Say QA acceptance. Never name a df skill, a lane, or a df path in it. Keep finding ids verbatim.

### Step 5. Re-run failed legs (optional)

If the operator asks to re-run failures after fixes:

1. Read `docs/qa/qa-<feature-slug>-results-latest.txt` to find the previous record.
2. If the pointer does not exist, stop and report that no prior results were found for rerun mode.
3. Collect the legs with `Result = FAIL` or `Result = BLOCKED`.
4. If none, report that there are no failed legs to rerun.
5. Re-execute only those legs, in `rerun-failed` mode, from Step 2 onward.
6. Write a new immutable rerun record, then update both pointer files.

If the verification skill or its map changed between the two runs, the rerun record says so. A rerun that passes against a rewritten recipe is a different claim from a rerun that passes against the same one.

### Step 6. Report the summary

After writing the record, report:

- the feature verdict and the leg counts, as "QA acceptance <verdict>, X of Y legs passed"
- every FAIL with a one-line reason
- every BLOCKED with its unmet prerequisite
- every intervention that happened, because each one is a finding
- the path to the immutable record and to the latest pointer
- any map drift observed, handed to the operator

Map drift is reported, never patched here. Editing the feature map mid-acceptance rewrites the standard while measuring against it. The maintenance loop owns that fix.

### Step 7. Cleanup

Run each verification skill's Cleanup section. Kill what this run started, never by process name. Cleanup removes instances and scratch state, never the evidence.

After cleanup, confirm the evidence still exists at its named location. A cleanup that eats the proof fails this step.

This runs at every exit point, including after Step 6, after a launch or doctor failure in Step 2, after a lost session in Step 3b, and after any error that stops the run. Before reporting a terminal error, clean up first. For a browser surface, closing the harness session is part of cleanup, so no browser daemon outlives the run.

## Key rules

- **Hands-off.** Any manual intervention means that leg FAILED, and the intervention is the bug.
- **Three verdicts.** PASS, FAIL, or BLOCKED, and nothing else. The feature's verdict is its weakest leg.
- **Real user path.** No internal setters, no test-only endpoints, no back door to reach a state.
- **Action and result.** Capture the action and the resulting state, not just the final screen. Verify side effects alongside what is visible.
- **The map is the recipe.** Drive what it says, in the commands it names. Do not re-derive navigation and do not improvise a shortcut.
- **Every entry point.** `How to get to it (user POV)` lists them all. One convenient path is not coverage.
- **Named entries only.** Drive the handoff. Never invent an entry id and never widen the list.
- **Doctor before driving.** And again after any failed drive.
- **One retry for harness errors.** Never for an observable end state that did not happen.
- **Fail the leg, not the run.** The first failing bullet ends that leg. Continue to the next.
- **Continue on failure.** Every leg runs before the report, except after a lost session.
- **Immutable records.** Never overwrite a prior record. Write a timestamped file and update the pointers.
- **Record the commit and the map revision.** That is what makes the record checkable later.
- **Evidence survives cleanup.** Confirm it at its named location after teardown.
- **Cleanup at every exit.** Success, failure, block, or interruption.
- **Environment safety.** Never drive a production-like target.
- **agent-browser for browser surfaces.** Get current usage from `agent-browser skills get core`. Absent means stop, not substitute.
- **No auto-fix.** This skill reports. It does not fix failures and it does not edit the feature map. The orchestration layer owns fix loops and the maintenance loop owns map drift.
- **Project vocabulary in project files.** `docs/qa/` is committed. Write QA acceptance, never a df skill name or lane vocabulary.
