---
name: df-code-review
description: "Codex-native code review for a feature branch: one whole-branch discovery pass on a frozen tree, lead adjudication, autonomous remediation, then delta verification of the fixes only. Carries the flag-flip integrated mode for the last PR in a chain. Writes a findings report and returns QA-ready status. Runs when the df feature playbook reaches its code-review stage or when the operator invokes it explicitly — never on its own."
---

# Code Review

Review a feature branch in **one whole-branch discovery pass on a frozen tree**,
then verify the remediation and stop. There is no round loop. Fixes are applied
autonomously — the user is not asked to approve findings one by one. Returns
QA-ready status when the review closes clean.

The shape, in five moves: freeze, discover once, adjudicate, remediate, verify
the delta. Anything that wants a sixth move is either the operator's
second-opinion pass or a signal that the lane was wrong.

## Lane modes

Read the lane from the run state. Ask the operator only if none is recorded.

| Lane | Discovery pass | Delta verification | Cross-family leg blocked |
|---|---|---|---|
| Quick | **one reviewer, one pass** over the diff, lead adjudication | none — the fixes are proven by the tests they touch | n/a, the lane has no cross-family leg |
| Standard | **one in-session reviewer plus the cross-family leg**, one pass | one leg per family, scoped to the remediation | **degrade with a logged note** |
| High-consequence | the full panel: 3 Codex subagent reviewers (quality, security, spec) plus the 2 Claude tmux reviewers, still **one pass** | one leg per raiser | **defer approval** |

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
| `CLAUDE_REVIEW_TIMEOUT_SECONDS` | `1800` | the tmux Claude review window |
| `REVIEW_ROOT` | `${TMPDIR:-/tmp}/dark-factory-review-<repo-key>-<run-id>` | all scratch output for one run |
| `RUN_DIR_POINTER` | `.dark-factory/tmp/code-review-review-dir` | file recording `REVIEW_ROOT` |
| `REPORT_DIR` | `.dark-factory/reviews/code-review/` | the final report |

There are no round caps in this skill, because there are no rounds. The old
10-round subagent phase and 3-round Claude tmux phase are **deleted**. What
bounds the work now is the dispatch budget plus a shape that runs discovery
exactly once.

## Dispatch reservations

Every reviewer dispatch reserves a seq through `scripts/df-state.sh` **before**
it spawns, and the reservation is spent the moment it lands:

```bash
seq=$(bash scripts/df-state.sh reserve "<run-id>" discovery_reviewers "code review discovery, in-session leg")
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
- Claude Code installed and authenticated (`claude --help` succeeds)
- `tmux` installed (`tmux -V` succeeds)
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

**Create a run-scoped scratch directory and cache the frozen diff.** Never write
review output to a fixed shared path: concurrent review runs on the same machine
will clobber each other and destroy a completed review.
```bash
mkdir -p .dark-factory/reviews/code-review .dark-factory/tmp
repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
review_dir="${TMPDIR:-/tmp}/dark-factory-review-${repo_key}-${run_id}"
mkdir -p "$review_dir"
printf '%s\n' "$review_dir" > .dark-factory/tmp/code-review-review-dir
echo "REVIEW_ROOT=$review_dir"
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

Resolve the reference directory (needed for the Codex subagent prompts):
```bash
ref_dir="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/df-code-review/references"
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-plugin/skills/df-code-review/references"
fi
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/*/dark-factory/*/skills/df-code-review/references 2>/dev/null | sort -V | tail -1)"
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

Subagents do not inherit your shell variables or context: state the concrete
diff path (`<REVIEW_ROOT>/branch-diff.txt`), the concrete `REVIEW_SHA`, and for
any spec-aware reviewer the concrete PRD and QA runbook paths, in each prompt.

**Quick lane — one reviewer.** One native Codex subagent at `DISCOVERY_TIER`,
reading all three prompt files (`$ref_dir/codex-quality-subagent-prompt.md`,
`$ref_dir/codex-security-subagent-prompt.md`,
`$ref_dir/codex-spec-subagent-prompt.md`) and emitting one findings block per
dimension. It also gets the lane's recorded finish predicate, which is what
"spec compliance" means in a lane with no PRD.

**Standard lane — one in-session reviewer plus the cross-family leg.**

- **In-session:** the same combined-rubric Codex subagent as Quick, plus the
  PRD and QA runbook paths.
- **Cross-family:** the Claude Code tmux helper (Step 3). Note the transport
  constraint honestly: that helper opens a quality window and a spec window in
  one invocation, so the Standard cross-family leg costs **two** reservations
  rather than one. The one-per-family ceiling is about panel breadth, and this
  is one family reached through a two-window transport. Reserve both.

**High-consequence lane — the full panel, still one pass.**

- **Reviewer 1 — Codex Quality:** `$ref_dir/codex-quality-subagent-prompt.md`.
  Header: `## Findings — Codex Quality`.
- **Reviewer 2 — Codex Security:** `$ref_dir/codex-security-subagent-prompt.md`.
  Header: `## Findings — Codex Security`.
- **Reviewer 3 — Codex Spec:** `$ref_dir/codex-spec-subagent-prompt.md`.
  Also reads `<prd-path>` and `<qa-path>`. Header: `## Findings — Codex Spec`.
- **Reviewers 4 and 5 — the Claude tmux legs:** quality and spec, through the
  helper in Step 3.

**Fallback when native subagents are unavailable:** run the bundled parallel
Codex CLI script with **`timeout: 600000`**. It runs all three reviewers, so it
is the High-consequence path; in Quick and Standard prefer the single
combined-rubric subagent and do not reach for it to save a message.

```bash
script_path="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/df-code-review/scripts/run_codex_subagent_reviews.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-plugin/skills/df-code-review/scripts/run_codex_subagent_reviews.sh"
fi
if [[ ! -f "$script_path" ]]; then
  script_path="$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/*/dark-factory/*/skills/df-code-review/scripts/run_codex_subagent_reviews.sh 2>/dev/null | sort -V | tail -1)"
fi
if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_subagent_reviews.sh" >&2
  echo "Checked: \${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/, <repo>/codex-plugin/skills/, and the dark-factory plugin cache" >&2
  exit 1
fi

review_dir="<REVIEW_ROOT from Step 1>"
base_ref="<base_ref from Step 1>"
out_dir="$review_dir/code-subagents"
mkdir -p "$out_dir"
DARK_FACTORY_REVIEW_DIR="$review_dir" bash "$script_path" "<prd-path>" "<qa-path>" "$base_ref" "$out_dir"
echo "OUTPUT_DIR=$out_dir"
```

Read every markdown file in `$review_dir/code-subagents/` before synthesis.

**Keep every in-session reviewer's thread addressable.** Record the identifier
the harness gives you alongside its dispatch seq. The delta verification goes
back to the reviewer that raised the finding, and a fresh dispatch arrives with
no memory of what it is being asked to check.

If a reviewer fails, note it and proceed with the rest — but a pass missing a
reviewer is a **partial pass**, and the reviewer that would have objected may be
exactly the one that failed. Say so in the report, and apply D7 if the missing
one was the cross-family leg.

## Step 3: The cross-family leg

Launch the Claude Code reviewers through the tmux helper with
**`timeout: 1800000`**. The helper starts a real interactive `claude` session
with two tmux windows (`quality` and `spec`), sends the review prompts into
them, and waits for completion sentinels before returning. Reserve one
dispatch per window before it runs.

```bash
script_path="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/df-code-review/scripts/run_claude_code_reviews_tmux.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-plugin/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh"
fi
if [[ ! -f "$script_path" ]]; then
  script_path="$(ls -d "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/*/dark-factory/*/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh 2>/dev/null | sort -V | tail -1)"
fi
if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_claude_code_reviews_tmux.sh" >&2; exit 1
fi
review_dir="<REVIEW_ROOT from Step 1>"
base_ref="<base_ref from Step 1>"
mkdir -p "$review_dir/claude"
bash "$script_path" "<prd-path>" "<qa-path>" "$base_ref" "$review_dir/claude"
```

Do not use `claude -p`, `--print`, SDK mode, stdout piping, or any
non-interactive Claude invocation. The cross-family leg is interactive Claude
Code in tmux.

Both reviewer sessions are hidden from the Matrix phone bridge. The helper
spawns them with `CCMATRIX_SUPPRESS_SESSION=1`, so they get no Matrix room, no
push notification and no text-to-speech. Without that, one pass of work would
put three live rooms on the operator's phone — this orchestrator plus both
reviewers — and read the reviewers' replies aloud, even though their reports are
addressed to this flow and not to a human. The assignment travels inside the
tmux command string on purpose: an exported variable does not reach a pane on an
already-running tmux server. `just test-bridge-suppression` proves both halves.

Read `$review_dir/claude/claude-quality-review.md` and
`$review_dir/claude/claude-spec-review.md`. The helper is fail-closed: a
sentinel over an empty or structurally invalid report is a failure and **no
reviewer opinion**, never a clean result.

**A crashed leg is retried once.** Reserve again and re-run at a fresh output
directory, up to `TOOLING_RETRY_LIMIT`. A single transient crash is not a
blocked leg. The retry costs a dispatch.

**D7, the blocked cross-family leg.** A timeout, a missing sentinel, a failure
surviving `TOOLING_RETRY_LIMIT`, or `claude`/`tmux` missing:

| Lane | It means |
|---|---|
| Standard | **degrade with a logged note.** Continue with the in-session findings, record `deferred: <reason>` in the run ledger, and say in the report and the chat summary that the pass ran single-family. |
| High-consequence | **defer approval.** Do not finalize as clean and do not report QA-ready. Record the blocker, surface it, and stop. A usage limit is recoverable, so waiting for the window is the answer; waiving the leg is not. |

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
dispatch a fresh in-session Codex subagent with the original finding text
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
the report; `.dark-factory/reviews/` is local working output.

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

## Step 8: Report QA-ready status

**Check for residual Critical/High first.** If any Critical or High is still
unresolved — `VERIFY_RETRY_LIMIT` exhausted, the budget refused a dispatch, or a
High-consequence cross-family leg blocked — do NOT report QA-ready. Surface the
residuals with the report link and stop; the operator decides. Report QA-ready
only when zero Critical/High remain and every remediation came back verified.

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
Deferred F Medium/Low (see report). Fixes committed. <Ready for QA acceptance. | Residual Critical/High remain — your call on how to proceed. | Ran single-family: the Claude leg was blocked, logged as a degrade.>
```

When zero Critical/High remain, report the QA runbook path (`<qa-path>`) and
QA-ready status. When running under the df feature playbook, stop here so the
router can explicitly invoke `df-qa-acceptance`. If this skill was invoked
standalone, tell the user the next stage is `df-qa-acceptance`.

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
- **Treating a blocked Claude leg the same way in both lanes.** Standard
  degrades and logs. High-consequence defers.
- **Using `claude -p` for the cross-family leg.** Do not use non-interactive
  Claude mode. Start interactive Claude Code in tmux and wait for the
  completion sentinels.
- **Degrading silently.** Degrading is allowed in Standard. Not saying so is
  not.
- **Asking the user to approve findings one by one.** Remediation is
  autonomous — research, fix, run tests, commit.
- **Claiming a fix works without running it.** Below "you ran it" on the
  blast-radius ladder is unproven, and unproven goes in the report as unproven.
- **Reusing a fixed scratch path.** Every run gets its own `REVIEW_ROOT`;
  a shared path lets concurrent runs clobber each other's reviews.

## Notes

- **Reference file resolution**: look in
  `${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/df-code-review/references/`
  first, then `<repo>/codex-plugin/skills/df-code-review/references/`
- **Reference files**: `codex-quality-subagent-prompt.md`,
  `codex-security-subagent-prompt.md` and `codex-spec-subagent-prompt.md`
  (the discovery rubrics),
  `delta-verification.md` (the CONFIRMED / NOT CONFIRMED contract),
  `synthesis-prompt.md` (synthesis, lead adjudication, and delta-verification
  synthesis)
- The diff is captured once, against `REVIEW_SHA`, from committed state only —
  no working-tree noise
- Scratch (diff cache, reviewer outputs, completion sentinels, stderr logs,
  delta files) goes to the run-scoped `REVIEW_ROOT` under /tmp/, so the
  autonomous flow never trips a write-permission prompt; the generated report
  lives in the gitignored `.dark-factory/reviews/` directory
- **`REVIEW_ROOT` in your own context is authoritative.** The pointer file
  `.dark-factory/tmp/code-review-review-dir` is a convenience for a session
  that lost it, and a second run in the same checkout overwrites it. If the
  pointer disagrees with the `REVIEW_ROOT` you created in Step 1, trust your
  own and say so in the report.
- Run project tests before starting this skill (not its job to fix pre-existing
  failures). `df-dev-verify` owns that gate.
