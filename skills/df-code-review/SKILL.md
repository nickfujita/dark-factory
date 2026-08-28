---
name: df-code-review
description: "Multi-model code review for a feature branch: one whole-branch discovery pass on a frozen tree, lead adjudication, autonomous remediation, then delta verification of the fixes only. Carries the flag-flip integrated mode for the last PR in a chain. Writes a findings report and chains to df-acceptance. Runs when the df feature playbook reaches its code-review stage or when the operator invokes it explicitly — never on its own."
disable-model-invocation: true
---

# Code Review

Review a feature branch in **one whole-branch discovery pass on a frozen tree**,
then verify the remediation and stop. There is no round loop. Fixes are applied
autonomously — the user is not asked to approve findings one by one. Chains to
df-acceptance.

The shape, in five moves: freeze, discover once, adjudicate, remediate, verify
the delta. Anything that wants a sixth move is either the operator's
second-opinion pass or a signal that the lane was wrong.

## Lane modes

Read the lane from the run state. Ask the operator only if none is recorded.

| Lane | Discovery pass | Delta verification | Cross-family leg blocked |
|---|---|---|---|
| Quick | **one reviewer, one pass** over the diff, lead adjudication | none — the fixes are proven by the tests they touch | n/a, the lane has no cross-family leg |
| Standard | **one in-session reviewer plus one cross-family reviewer**, one pass | one leg per family, scoped to the remediation | **degrade with a logged note** |
| High-consequence | the full panel: 3 in-session reviewers (quality, security, spec) plus 2 cross-family reviewers, still **one pass** | one leg per raiser | **defer approval** |

Two rules cut across all three. **The per-PR review depth is what this table
says and nothing more** — a Standard PR gets the one discovery pass, and a Quick
PR gets its single reviewer. And **review findings never change the lane.**
Findings-as-authorization is how one measured run turned a bug fix into a
subsystem.

The panel is lane-priced because one Claude plus one Codex is the Standard-lane
ceiling in the model policy. The three-way split by dimension survives only in
High-consequence.

**Flag-flip integrated mode** is a fourth entry point, not a lane. See its
section below.

## The frozen-tree rule

**A review runs against a recorded commit. A moved head voids it.**

Record `REVIEW_SHA` before dispatching anything, and put it in every reviewer's
brief and in the report. Every reviewer in the pass reads that commit, and
nothing else. While the pass is running, do not commit, do not rebase, do not
amend, and do not let a delegate do any of those.

If HEAD moves before the pass completes, the pass is **void**. Its findings
describe code that no longer exists in the form that was reviewed, and merging
them with findings against the new tree produces a report nobody can act on.
Re-freeze at the new SHA and re-run — which costs dispatches, which is the
point of the rule.

Remediation commits move HEAD, and that is expected. That is exactly why the
next thing after remediation is a **delta verification of `REVIEW_SHA..HEAD`**
and not another discovery pass.

Reviewers read from a disposable snapshot of `REVIEW_SHA`, created for the
review and deleted after, never from the live tree. The bundled runner scripts
already do this when the read-only sandbox is unavailable; a degraded sandbox
must only ever be able to touch a throwaway.

## Pinned parameters

| Parameter | Value | Applies to |
|---|---|---|
| `DISPATCH_BUDGET` | the run's budget, read from the run state | every reviewer dispatch this skill makes |
| `SECOND_OPINION_DISPATCHES` | 2, operator-invoked only, once per run | the second-opinion pass |
| `VERIFY_RETRY_LIMIT` | 2 | remediate → re-verify cycles on one delta before escalating |
| `TOOLING_RETRY_LIMIT` | 1 | retries of a crashed reviewer run before the leg is declared blocked |
| `DISCOVERY_TIER` | **unpinned — inherit from the orchestrator session** (no `model`, no `subagent_type` override) | in-session discovery reviewers |
| `RECHECK_TIER` | `subagent_type: df-reviewer-recheck` (agent definition pins `model: opus`, `effort: high`) | delta-verification reviewers spawned fresh |
| `REVIEW_ROOT` | `<run-dir>/work/code-review` | all scratch output for one run |
| `REPORT_DIR` | `<run-dir>/reviews/code-review/` | the final report |

`<run-dir>` is this run's directory in the agent's own store, printed by
`bash scripts/df-state.sh path "<run-id>"`. It sits outside the repo, so a run
leaves the project's tree untouched and needs no `.gitignore` entry. Two
concurrent runs are two run ids and two directories, so they cannot clobber
each other.

There are no round caps in this skill, because there are no rounds. The old
10-round Claude phase and 3-round Codex phase are **deleted**. What bounds the
work now is the dispatch budget plus a shape that runs discovery exactly once.

## Dispatch reservations

Every reviewer dispatch reserves a seq through `scripts/df-state.sh` **before**
it spawns, and the reservation is spent the moment it lands:

```bash
seq=$(bash scripts/df-state.sh reserve "<run-id>" discovery_reviewers "code review discovery, claude leg")
```

Reserving covers the discovery reviewers, every delta-verification leg, any
retry after a crashed run, the second-opinion pass, the flag-flip pass, and
anything nested inside them. A refused reservation (exit 3) means the dispatch
does not happen and the run is in `stopped-budget`. Surface it; do not spawn
anyway.

Reviewer models resolve through `../df/references/model-policy.md`. Do not
hardcode a model slug at a call site.

## Prerequisites

- Feature branch checked out with implementation complete
- Tests passing before review begins
- E2e test suite exists and passes, covering QA runbook test cases
- Codex CLI installed and authenticated (`codex --version` succeeds)
- PRD (`docs/prd-<feature>.md`, Status: Approved or Approved with open items)
  and QA runbook (`docs/qa/qa-<feature>.md`) exist for this feature
- An open df run in the run-state store, or the standing to open one

## Step 1: Resolve inputs and freeze the tree

**Detect branch and base** (never hardcode `main` — detect the default branch):
```bash
feature_branch=$(git branch --show-current)
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [[ -z "$default_branch" ]]; then
  if git rev-parse --verify main >/dev/null 2>&1; then default_branch="main";
  elif git rev-parse --verify master >/dev/null 2>&1; then default_branch="master";
  else echo "ERROR: Cannot determine default branch. Ask the user for a base ref." >&2; exit 1;
  fi
fi
base_ref="$(git merge-base HEAD "$default_branch")"
review_sha="$(git rev-parse HEAD)"
echo "REVIEW_SHA=$review_sha"
```
If the default branch cannot be determined, ask the user for the base ref
instead of guessing.

**Derive feature slug from branch name:**
Strip common prefixes (`feat/`, `feature/`, `fix/`, `chore/`). Use the
remainder as the slug (e.g., `feat/user-auth` → `user-auth`).

**Locate PRD and QA runbook:**
1. Scan `docs/` for `prd-<slug>.md` with Status: Approved or Approved with open items
2. Scan `docs/qa/` for `qa-<slug>.md`
3. If no exact match: list candidate files and ask the user to confirm paths

**Resolve this run's directory and cache the frozen diff.** Everything this
skill produces lives under the run directory in the agent's own store, never in
the repo under review. The run id scopes it, so concurrent reviews cannot
clobber each other.
```bash
run_dir="$(bash scripts/df-state.sh path "<run-id>")"
review_dir="$run_dir/work/code-review"
report_dir="$run_dir/reviews/code-review"
mkdir -p "$review_dir" "$report_dir"
echo "REVIEW_ROOT=$review_dir"
echo "REPORT_DIR=$report_dir"
git diff "$base_ref" "$review_sha" > "$review_dir/branch-diff.txt"
printf '%s\n' "$review_sha" > "$review_dir/review-sha.txt"
```

The diff is cached **once**, against `REVIEW_SHA`. The old per-round refresh is
gone with the rounds; a refresh mid-pass is what the frozen-tree rule forbids.

Remember `REVIEW_ROOT` — every scratch artifact in this skill (diff cache,
Codex outputs, stderr logs, delta files) lives under it, and later Bash calls
must substitute the concrete value because shell variables do not persist
between calls.

Read `$REVIEW_ROOT/branch-diff.txt`. If empty, stop and tell the user there
are no changes to review vs the detected default branch.

Resolve the reference directory (needed for Claude sub-agent prompts):
```bash
ref_dir="$HOME/.claude/skills/df-code-review/references"
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/df-code-review/references"
fi
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/df-code-review/references"
fi
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$(ls -d "$HOME"/.claude/plugins/cache/*/dark-factory/*/skills/df-code-review/references 2>/dev/null | sort -V | tail -1)"
fi
```

Reserve the report path now; you assemble and write the full report once, at
finalize. Keep a running record instead, so the report stays out of the diff
the reviewers read and you avoid duplicated headers.
Report path: `REPORT_DIR/<timestamp>-<feature>-code-review.md`
where `<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

## Step 2: The discovery pass

**One pass. Every reviewer the lane calls for, in parallel, in a single
message, all reading `REVIEW_SHA`.** Reserve each dispatch first.

Sub-agents do not inherit your shell variables or context: state the concrete
diff path (`<REVIEW_ROOT>/branch-diff.txt`), the concrete `REVIEW_SHA`, and for
any spec-aware reviewer the concrete PRD and QA runbook paths, in each prompt.

**Quick lane — one reviewer.** One in-session sub-agent at `DISCOVERY_TIER`,
reading all three prompt files (`$ref_dir/claude-quality-prompt.md`,
`$ref_dir/claude-security-prompt.md`,
`$ref_dir/claude-spec-compliance-prompt.md`) and emitting one findings block
per dimension. It also gets the lane's recorded finish predicate, which is what
"spec compliance" means in a lane with no PRD.

**Standard lane — one in-session reviewer plus one cross-family reviewer.**

- **In-session:** the same combined-rubric sub-agent as Quick, plus the PRD and
  QA runbook paths.
- **Cross-family:** `run_codex_quality_review.sh` (Step 3). It carries the
  correctness and edge-case rubric, which is where cross-model disagreement is
  worth the most on code. Spec compliance is covered by the in-session reviewer,
  which has the PRD and runbook in context. That trade is deliberate and it is
  what the one-Claude-plus-one-Codex ceiling buys; High-consequence is where the
  Codex spec leg also runs.

**High-consequence lane — the full panel, still one pass.**

- **Reviewer 1 — Claude Quality:** `$ref_dir/claude-quality-prompt.md`.
  Header: `## Findings — Claude Quality`.
- **Reviewer 2 — Claude Security:** `$ref_dir/claude-security-prompt.md`.
  Header: `## Findings — Claude Security`.
- **Reviewer 3 — Claude Spec:** `$ref_dir/claude-spec-compliance-prompt.md`.
  Also reads `<prd-path>` and `<qa-path>`. Header: `## Findings — Claude Spec`.
- **Reviewers 4 and 5 — the Codex legs:** `run_codex_quality_review.sh` and
  `run_codex_spec_review.sh` (Step 3).

**Keep every in-session reviewer's thread addressable.** Record the identifier
the harness gives you alongside its dispatch seq. The delta verification goes
back to the reviewer that raised the finding, and a fresh dispatch arrives with
no memory of what it is being asked to check.

If a reviewer fails, note it and proceed with the rest — but a pass missing a
reviewer is a **partial pass**, and the reviewer that would have objected may be
exactly the one that failed. Say so in the report, and apply D7 if the missing
one was the cross-family leg.

## Step 3: The cross-family leg

Launch the Codex reviewers in the same message as the in-session ones, each with
**`timeout: 600000`**. They compute the diff internally from `base_ref`, so pin
them to the frozen tree by checking out nothing and running them before any
remediation commit exists.

**Codex Quality (Standard and High-consequence):**
```bash
quality_script="$HOME/.claude/skills/df-code-review/scripts/run_codex_quality_review.sh"
if [[ ! -f "$quality_script" ]]; then
  quality_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/df-code-review/scripts/run_codex_quality_review.sh"
fi
if [[ ! -f "$quality_script" ]]; then
  quality_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/df-code-review/scripts/run_codex_quality_review.sh"
fi
if [[ ! -f "$quality_script" ]]; then
  quality_script="$(ls -d "$HOME"/.claude/plugins/cache/*/dark-factory/*/skills/df-code-review/scripts/run_codex_quality_review.sh 2>/dev/null | sort -V | tail -1)"
fi
if [[ ! -f "$quality_script" ]]; then
  echo "ERROR: Cannot find run_codex_quality_review.sh" >&2; exit 1
fi
review_dir="<REVIEW_ROOT from Step 1>"
base_ref="<base_ref from Step 1>"
bash "$quality_script" "$base_ref" "$review_dir/codex-quality-review.md"
```

**Codex Spec (High-consequence only):**
```bash
spec_script="$HOME/.claude/skills/df-code-review/scripts/run_codex_spec_review.sh"
if [[ ! -f "$spec_script" ]]; then
  spec_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/df-code-review/scripts/run_codex_spec_review.sh"
fi
if [[ ! -f "$spec_script" ]]; then
  spec_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/df-code-review/scripts/run_codex_spec_review.sh"
fi
if [[ ! -f "$spec_script" ]]; then
  spec_script="$(ls -d "$HOME"/.claude/plugins/cache/*/dark-factory/*/skills/df-code-review/scripts/run_codex_spec_review.sh 2>/dev/null | sort -V | tail -1)"
fi
if [[ ! -f "$spec_script" ]]; then
  echo "ERROR: Cannot find run_codex_spec_review.sh" >&2; exit 1
fi
review_dir="<REVIEW_ROOT from Step 1>"
base_ref="<base_ref from Step 1>"
bash "$spec_script" "<prd-path>" "<qa-path>" "$base_ref" "$review_dir/codex-spec-review.md"
```

Both scripts are fail-closed: an empty or structurally invalid review is a
non-zero exit and **no reviewer opinion**, never a clean result. Read the
stderr log next to the output rather than guessing.

**A crashed leg is retried once.** Reserve again and re-run at a fresh output
path, up to `TOOLING_RETRY_LIMIT`. A single transient crash is not a blocked
leg. The retry costs a dispatch.

**D7, the blocked cross-family leg.** A usage limit, a failure surviving
`TOOLING_RETRY_LIMIT`, or a missing CLI:

| Lane | It means |
|---|---|
| Standard | **degrade with a logged note.** Continue with the in-session findings, record `deferred: <reason>` in the run ledger, and say in the report and the chat summary that the pass ran single-family. |
| High-consequence | **defer approval.** Do not finalize as clean and do not hand off to QA acceptance. Record the blocker, surface it, and stop. A usage limit is recoverable, so waiting for the window is the answer; waiving the leg is not. |

Salvage first, either way: if the leg produced partial findings before it died,
read them and adjudicate them under the normal rules. Paid-for signal is not
thrown away because the process ended badly.

## Step 4: Synthesize and adjudicate

Consolidate the pass's findings into your running record following
`$ref_dir/synthesis-prompt.md`: deduplicate, tag sources, take the highest
severity on disagreement, and give every finding a concrete recommendation that
says both why the code is problematic and what the fix looks like.

Then **adjudicate**, per that file's § "Lead adjudication". You are the lead.
Reviewers advise; you decide, and you record a disposition and one line of
reasoning for every finding. Nitpick Gravity applies: a review that is all nits
is telling you the code is fine, and an Act-On list over five items means you
are under-filtering.

Agreement across model families is the strongest consensus signal available
here. A Critical raised by one family that the other read the same code and did
not raise is the finding to trace to a real execution path before acting on it.

## Step 5: Remediate

Apply the accepted fixes autonomously. Do NOT ask the user to approve findings
one by one. For each fix: research the codebase to determine the right
correction, verify the fix suits this codebase before applying it, push back in
the report with technical reasoning where a reviewer's suggestion is wrong,
apply one fix at a time, and run the project tests after each.

- **All Critical findings** that survived adjudication
- **All High findings** that survived adjudication
- A **curated selection of Medium/Low** — the ones that genuinely belong in the
  codebase. Record which you applied and which you deferred.

Verify each fix against the `blast-radius` proof ladder
(`skills/blast-radius/SKILL.md` § "How sure are you"). Below "you ran it" is
unproven, and an unproven fix is reported as unproven rather than as done.

**Commit the fixes before verifying:**
`git add <changed source files> && git commit -m "fix: code review remediation for <feature>"`.
Commit only the code you changed; the report is not written until finalize, so
it stays out of the delta. This is the point where HEAD legitimately moves past
`REVIEW_SHA`, and `REVIEW_SHA..HEAD` is now exactly the delta to verify.

## Step 6: Delta verification

Read `$ref_dir/delta-verification.md`. It is the contract: what the verifier
gets, who verifies, the verdict block, and how to read the result.

In short. Assemble the delta (each finding as raised, its disposition and
reason, the fix diff, the test evidence, plus `git diff <REVIEW_SHA>..HEAD` and
the fixed unresolved list). Reserve a dispatch per verifying leg. Send it back
to the reviewer that raised the findings, in its thread where the harness can
continue one; where it cannot — the CLI legs are fresh processes every time —
dispatch an in-session reviewer at `RECHECK_TIER` with the original finding text
verbatim, and record the substitution.

**This is not a second discovery pass**, and a new Critical or High after
discovery requires specific evidence: the file and line, the concrete execution
path that reaches it, and what goes wrong when it does. Without that evidence it
is a Medium at most.

`NOT CONFIRMED` items and evidenced regressions are fixed and re-verified,
inside `VERIFY_RETRY_LIMIT`. Exhausting the limit escalates to the operator with
the outstanding verdicts. It does not open a round.

## The second-opinion pass (operator-invoked)

The operator may ask for one more review, once per run, in any lane. This is the
formalized version of "just rerun the review", with the couplings that made
rerunning dangerous removed.

- **Decorrelated by construction.** The other model family, or a deliberately
  different rubric lens on the same code. Never the same reviewer under the same
  prompt: a same-model rerun is a correlated draw and it mostly rediscovers.
- **Costs `SECOND_OPINION_DISPATCHES`**, reserved before it spawns.
- **Runs on a recorded SHA** like every other pass, and its findings are
  lead-adjudicated under the same rules.
- **Gates unchanged.** It cannot lower the bar for handing off and it cannot
  raise it. It is an extra sample, not a new gate.
- **The operator invokes it.** This skill never reaches for it, never suggests
  it instead of finalizing, and never runs it because a pass felt thin.

## Flag-flip integrated mode

The last PR in a feature chain is the one that flips the flag. It gets **one
budgeted integrated pass, once per chain**, and this mode is what that pass is.
It is not a lane and it does not replace the per-PR reviews; each PR in the
chain already had its own.

Trigger it when the operator or the feature playbook says this is the flag-flip
PR. Never trigger it per-PR.

**Scope, and only this scope:**

1. **The assembled chain.** `git diff <default-branch>...<flag-flip head>` —
   the whole feature as it will land, read as one change rather than as the
   several small diffs it was reviewed in. What this catches that per-PR review
   structurally cannot: seams between PRs, an invariant each PR kept locally and
   the chain breaks jointly, and duplicated mechanism nobody saw twice.
2. **The flag-removal diff.** The commit that removes the flag, read on its own.
   The failure mode is a path that only ever ran with the flag off, now
   unreachable or now reachable for the first time in production.
3. **Dead code.** What the removed branch left behind: the old code path, its
   tests, its config keys, its feature-flag plumbing. A flag flip that leaves
   the old path compiled in has not finished.

**Shape:** freeze the tree at the flag-flip head, reserve, run one pass with the
lane's reviewer set, adjudicate, remediate, then **one bounded delta
confirmation** of that remediation, per Step 6 and inside `VERIFY_RETRY_LIMIT`.
Then stop. There is no second integrated pass, and a chain gets exactly one.

The full acceptance runbook runs alongside this pass, at the same flag-flip PR.
That pairing is the point: the integrated review reads the assembled change
while acceptance exercises it.

## Step 7: Finalize the report

Assemble the full report from your running record and write it once to the
reserved path. Number all findings globally (CR-001, CR-002, …). Do not commit
the report; `REPORT_DIR` is local working output in the run's own store
directory, outside the repo.

```
# Code Review: <Feature Name>
**Date:** YYYY-MM-DD
**Lane:** Quick | Standard | High-consequence | flag-flip integrated
**Branch:** <branch-name>
**Base:** <merge-base short SHA>
**Review SHA:** <the frozen commit the discovery pass read>
**Remediation SHA:** <HEAD after remediation>
**PRD:** <prd-path>
**QA Runbook:** <qa-path>
**Reviewers:** <the ones that actually ran, with the leg each belongs to>
**Dispatches:** <used> of <budget>

## Summary
One discovery pass at <REVIEW_SHA>. X Critical, Y High, Z Medium, W Low raised;
A acted on after adjudication, B dismissed.
Delta verification: C CONFIRMED, D NOT CONFIRMED, E re-verified clean.
<Degraded single-family under D7 — say so here, not only in Notes.>

## Adjudication
Every finding with its disposition and one line of reasoning: applied as
proposed, applied / modified, declined — not real, declined — cost, deferred.
The dismissed set is part of the report, not a private decision.

## Remediation Log
Per finding acted on: the fix applied, why the code was problematic, what
changed, what was run to prove it, and which rung of the proof ladder it
reached.

## Delta Verification
| ID | Verifier | Verdict | Evidence | Re-verify cycles |
|----|----------|---------|----------|------------------|

## Deferred (Medium / Low not applied)
| ID | Severity | Title | Sources | Location | Why deferred |
|----|----------|-------|---------|----------|--------------|

## Notes
Partial passes, blocked legs and their D7 treatment, retries, reviewer threads
that could not be continued, whether the second-opinion pass was invoked.
```

The report must be self-contained — readable without the chat context.

## Step 8: Report and chain

**Check for residual Critical/High first.** If any Critical or High is still
unresolved — `VERIFY_RETRY_LIMIT` exhausted, the budget refused a dispatch, or a
High-consequence cross-family leg blocked — do NOT chain to QA. Surface the
residuals with the report link and stop; the operator decides. Chain only when
zero Critical/High remain and every remediation came back verified.

Present a **TTS-friendly chat summary** (do NOT paste the full report) that
states the ACTUAL outcome. Fill the placeholders from what really happened:

```
Review complete. Full report:
<GoGrip link>

Lane: <lane>. One discovery pass at <short SHA>, <N> reviewers.
Dispatches: <used> of <budget>.
Raised X Critical, Y High. Acted on A after adjudication, dismissed B.
Delta verification: C confirmed, D not confirmed <, re-verified clean | , escalated>.

Remediated A findings and E curated Medium/Low. Tests passing.
Deferred F Medium/Low (see report). Fixes committed. <Proceeding to QA acceptance. | Residual Critical/High remain — your call on how to proceed. | Ran single-family: the Codex leg was blocked, logged as a degrade.>
```

When zero Critical/High remain, trigger `df-acceptance` with the coverage
handoff from `df-verify-coverage`.

## Common Mistakes

- **Running a second discovery pass.** There is one. What follows a remediation
  is a delta verification, scoped to the fixes.
- **Reviewing a moving tree.** Freeze at `REVIEW_SHA`, put it in every brief,
  and void the pass if HEAD moves under it.
- **Refreshing the diff mid-pass.** That was the round loop's mechanic. It is
  gone with the rounds.
- **Spawning a reviewer without reserving first.** The reservation is the count,
  and the count is the brake.
- **Opening a new Critical after discovery without evidence.** File, line,
  execution path, and consequence, or it is a Medium.
- **Aggregating instead of adjudicating.** Reviewers advise. You decide, and you
  write down what you dismissed and why.
- **An Act-On list over five items.** Re-read it and cut. That length is a
  filtering failure, not a code failure.
- **Running the flag-flip pass per PR.** Once per chain, at the flag flip.
- **Treating a blocked Codex leg the same way in both lanes.** Standard
  degrades and logs. High-consequence defers.
- **Degrading silently.** Degrading is allowed in Standard. Not saying so is
  not.
- **Asking the user to approve findings one by one.** Remediation is
  autonomous — research, fix, run tests, commit.
- **Claiming a fix works without running it.** Below "you ran it" on the
  blast-radius ladder is unproven, and unproven goes in the report as unproven.
- **Reusing a fixed scratch path.** Every run gets its own `REVIEW_ROOT`;
  a shared path lets concurrent runs clobber each other's reviews.

## Notes

- **Reference file resolution**: look in `$HOME/.claude/skills/df-code-review/references/`
  first, then `<repo>/skills/df-code-review/references/`, then
  `<repo>/.claude/skills/df-code-review/references/`
- **Reference files**: `claude-quality-prompt.md`, `claude-security-prompt.md`
  and `claude-spec-compliance-prompt.md` (the discovery rubrics),
  `delta-verification.md` (the CONFIRMED / NOT CONFIRMED contract),
  `synthesis-prompt.md` (synthesis, lead adjudication, and delta-verification
  synthesis)
- The diff is captured once, against `REVIEW_SHA`, from committed state only —
  no working-tree noise
- Scratch (diff cache, Codex outputs, stderr logs, delta files) and the
  finished report both live under this run's directory in the agent's own
  store, never inside the repo, so a review leaves the project's tree untouched
  and never trips a write-permission prompt
- **`REVIEW_ROOT` is recoverable, not remembered.** A session that lost it
  rebuilds the path from the run id with `df-state.sh path`. There is no
  pointer file to go stale, and a second review in the same checkout is a
  second run id with its own directory.
- Run project tests before starting this skill (not its job to fix pre-existing
  failures). `df-dev-verify` owns that gate.
