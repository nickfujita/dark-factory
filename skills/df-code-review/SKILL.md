---
name: df-code-review
description: "Multi-model code review for a feature branch: Claude reviewers then Codex, with autonomous remediation looped between rounds. Writes a findings report, applies fixes itself, and chains to df-qa-acceptance. Runs when the df feature playbook reaches its code-review stage or when the operator invokes it explicitly — never on its own."
disable-model-invocation: true
---

# Code Review

Review a feature branch in two sequential review-and-remediation phases.
**Phase A** runs three Claude reviewers (quality, security, spec) in a
fix-and-re-review loop until zero Critical/High findings remain. **Phase B**
runs two Codex reviewers in a capped loop for model diversity. Fixes are
**applied autonomously between every round** — the user is not asked to approve
findings one by one. Chains to df-qa-acceptance.

## Prerequisites

- Feature branch checked out with implementation complete
- Tests passing before review begins
- E2e test suite exists and passes, covering QA runbook test cases
- Codex CLI installed and authenticated (`codex --version` succeeds)
- PRD (`docs/prd-<feature>.md`, Status: Approved) and QA runbook
  (`docs/qa/qa-<feature>.md`) exist for this feature

## Step 1: Resolve Inputs

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
```
If the default branch cannot be determined, ask the user for the base ref
instead of guessing.

**Derive feature slug from branch name:**
Strip common prefixes (`feat/`, `feature/`, `fix/`, `chore/`). Use the
remainder as the slug (e.g., `feat/user-auth` → `user-auth`).

**Locate PRD and QA runbook:**
1. Scan `docs/` for `prd-<slug>.md` with `Status: Approved`
2. Scan `docs/qa/` for `qa-<slug>.md`
3. If no exact match: list candidate files and ask the user to confirm paths

**Create a run-scoped scratch directory and cache the diff** (the diff is
refreshed at the start of every round — see below). Never write review output
to a fixed shared path: concurrent review runs on the same machine will
clobber each other and destroy a completed review.
```bash
mkdir -p .dark-factory/reviews/code-review .dark-factory/tmp
repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
review_dir="${TMPDIR:-/tmp}/dark-factory-review-${repo_key}-${run_id}"
mkdir -p "$review_dir"
printf '%s\n' "$review_dir" > .dark-factory/tmp/code-review-review-dir
echo "REVIEW_ROOT=$review_dir"
git diff "$base_ref" HEAD > "$review_dir/branch-diff.txt"
```

Remember `REVIEW_ROOT` — every scratch artifact in this skill (diff cache,
Codex outputs, stderr logs) lives under it, and later Bash calls must
substitute the concrete value because shell variables do not persist between
calls.

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
```

Reserve the report path now (the directory was created with `REVIEW_ROOT`
above); you assemble and write the full report once, at finalize (Step 4).
Keep a running record of each round's findings and fixes — do not write the
report file during the loop, so it stays out of the diff Codex reviews and you
avoid duplicated headers.
Report path: `.dark-factory/reviews/code-review/<timestamp>-<feature>-code-review.md`
where `<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

## How the review loop works (both phases)

Each phase is a **loop**. One round of the loop is:

1. **Refresh the diff (Phase A only)** — Phase A's Claude reviewers read the
   cached diff, so refresh it at the start of each Phase A round to show the
   latest committed state (prior rounds' fixes are committed — see step 5).
   Recompute the base ref in the same command, since shell variables do not
   persist between separate Bash calls (substitute the concrete `REVIEW_ROOT`
   from Step 1):
   ```bash
   review_dir="<REVIEW_ROOT from Step 1>"
   default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
   if [[ -z "$default_branch" ]]; then
     if git rev-parse --verify main >/dev/null 2>&1; then default_branch="main";
     elif git rev-parse --verify master >/dev/null 2>&1; then default_branch="master";
     else echo "ERROR: Cannot determine default branch." >&2; exit 1;
     fi
   fi
   base_ref="$(git merge-base HEAD "$default_branch")"
   git diff "$base_ref" HEAD > "$review_dir/branch-diff.txt"
   ```
   Phase B's Codex scripts compute their own diff from the base ref internally,
   so they do not need this refresh.
2. **Review** — run the phase's reviewer(s) (Phase A / Phase B below specify
   which). All reviewers in a round run in parallel in a single message.
3. **Synthesize** — consolidate this round's findings into your running record
   for the report, following `$ref_dir/synthesis-prompt.md` (deduplicate, tag
   sources, highest severity on disagreement, concrete recommendation per
   finding). Ignore findings you already remediated in a prior round (a
   reappearance is a regression — treat it as new); respect earlier deferral
   decisions unless severity has risen. You write the report file once, at
   finalize (Step 4).
4. **Gate check** — count Critical and High findings for the round:
   - **Zero Critical AND zero High** → the phase is complete. Exit the loop.
   - **Otherwise** → remediate (step 5), then start a new round at step 1.
5. **Remediate autonomously** — do NOT ask the user to approve findings one by
   one. Apply fixes using `superpowers:receiving-code-review` discipline:
   research the codebase and the web to determine the best correction, verify
   the fix is right for this codebase before applying, push back (in the
   report) with technical reasoning if a reviewer suggestion is wrong, apply
   one fix at a time, and run project tests after each fix. Every round you fix:
   - **All Critical findings**
   - **All High findings**
   - A **curated selection of Medium/Low findings** — apply the ones your
     judgment says genuinely belong in the codebase; skip noise. Record in the
     report which Medium/Low you applied and which you deliberately deferred.

   **Commit the round's code fixes before re-reviewing:**
   `git add <changed source files> && git commit -m "fix: code review round N fixes for <feature>"`.
   Commit only the code you changed — the report is not written until finalize,
   so it stays out of the diff Codex reviews. Committing is required so the next
   round's diff (and Codex's internal diff) reflects the fixes.

The phases are **sequential, not parallel**: Phase A must reach zero
Critical/High before Phase B begins.

## Step 2: Phase A — Claude reviewer loop (until zero Critical/High)

**Each round, dispatch the 3 Claude reviewers as parallel sub-agents** (all 3
Agent calls in one message). Each sub-agent reads its prompt file, reads
`$REVIEW_ROOT/branch-diff.txt` for the diff, reads the changed files for
context, and returns findings under a self-identifying header. Sub-agents do
not inherit your shell variables or context: state the concrete diff path
(`<REVIEW_ROOT>/branch-diff.txt`) — and for the Spec reviewer the concrete PRD
and QA runbook paths — in each Agent prompt.

- **Reviewer 1 — Claude Quality:** `$ref_dir/claude-quality-prompt.md`.
  Header: `## Findings — Claude Quality`.
- **Reviewer 2 — Claude Security:** `$ref_dir/claude-security-prompt.md`.
  Header: `## Findings — Claude Security`.
- **Reviewer 3 — Claude Spec:** `$ref_dir/claude-spec-compliance-prompt.md`.
  Also reads `<prd-path>` and `<qa-path>`. Header: `## Findings — Claude Spec`.

If one Claude reviewer fails, note it and proceed with the remaining two. Then
run synthesize → gate check → remediate (above). **Loop until the gate passes**
(zero Critical and zero High) or the round cap below is reached.

**Round cap (safety guard):** the Claude phase loops until the gate passes, but
is capped at **10 rounds** — set high on purpose, because real Critical/High
findings from Claude should be fixed, not abandoned early. If round 10 completes
with Critical or High still open, stop and surface the remaining findings to the
user (with the report link): do not run Phase B, do not chain to QA, and do not
finalize with open Critical/High. If the user overrides ("good enough, move
on"), continue to Phase B; otherwise the user drives the next move.

## Step 3: Phase B — Codex reviewer loop (max 3 rounds)

Once Phase A's gate passes, run the 2 Codex reviewers in the same loop,
**capped at 3 rounds total**.

**Each round, launch both Codex reviewers** (both Bash commands in one message,
each with **`timeout: 600000`**). They compute the diff internally from
`base_ref`, so they pick up committed fixes automatically:

**Codex Quality:**
```bash
quality_script="$HOME/.claude/skills/df-code-review/scripts/run_codex_quality_review.sh"
if [[ ! -f "$quality_script" ]]; then
  quality_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/df-code-review/scripts/run_codex_quality_review.sh"
fi
if [[ ! -f "$quality_script" ]]; then
  quality_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/df-code-review/scripts/run_codex_quality_review.sh"
fi
if [[ ! -f "$quality_script" ]]; then
  echo "ERROR: Cannot find run_codex_quality_review.sh" >&2; exit 1
fi
review_dir="<REVIEW_ROOT from Step 1>"
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [[ -z "$default_branch" ]]; then
  if git rev-parse --verify main >/dev/null 2>&1; then default_branch="main";
  elif git rev-parse --verify master >/dev/null 2>&1; then default_branch="master";
  else echo "ERROR: Cannot determine default branch." >&2; exit 1;
  fi
fi
base_ref="$(git merge-base HEAD "$default_branch")"
bash "$quality_script" "$base_ref" "$review_dir/codex-quality-review.md"
```

**Codex Spec:**
```bash
spec_script="$HOME/.claude/skills/df-code-review/scripts/run_codex_spec_review.sh"
if [[ ! -f "$spec_script" ]]; then
  spec_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/df-code-review/scripts/run_codex_spec_review.sh"
fi
if [[ ! -f "$spec_script" ]]; then
  spec_script="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/df-code-review/scripts/run_codex_spec_review.sh"
fi
if [[ ! -f "$spec_script" ]]; then
  echo "ERROR: Cannot find run_codex_spec_review.sh" >&2; exit 1
fi
review_dir="<REVIEW_ROOT from Step 1>"
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [[ -z "$default_branch" ]]; then
  if git rev-parse --verify main >/dev/null 2>&1; then default_branch="main";
  elif git rev-parse --verify master >/dev/null 2>&1; then default_branch="master";
  else echo "ERROR: Cannot determine default branch." >&2; exit 1;
  fi
fi
base_ref="$(git merge-base HEAD "$default_branch")"
bash "$spec_script" "<prd-path>" "<qa-path>" "$base_ref" "$review_dir/codex-spec-review.md"
```

Read `$REVIEW_ROOT/codex-quality-review.md` and `$REVIEW_ROOT/codex-spec-review.md`,
then run synthesize → gate check → remediate (above). **Stop the loop when the
gate passes OR after 3 rounds**, whichever comes first. After 3 rounds, proceed
to Step 4 even if Medium/Low remain.

**Codex usage-limit exception (the important escape hatch):** if a Codex run
fails on a usage/rate limit, stop Phase B immediately — do not run any more
Codex rounds. Each script exits non-zero and writes a stderr log next to its
output (`$REVIEW_ROOT/codex-quality-review.stderr.log`,
`$REVIEW_ROOT/codex-spec-review.stderr.log`). Read the log: a usage limit shows
up as patterns like `usage limit`, `rate limit`, `quota`, `429`,
`too many requests`, or `reached your (usage )?limit`. When you detect one:
- **Remediate any not-yet-remediated findings the limited run returned** (same
  step 5 rules — all Critical/High plus curated Medium/Low — commit them).
  Findings from earlier Codex rounds this phase were already remediated
  in-loop; do not re-edit them.
- **If only one of the two Codex reviewers limited** and the other returned
  findings, remediate the successful reviewer's findings, then stop Phase B
  (do not retry the limited reviewer).
- If Codex returned no usable findings before the limit, just proceed.
- Either way, continue to Step 4. Note in the report that Phase B stopped
  early on a Codex usage limit.

**Codex failure that is NOT a usage limit** (script missing, generic non-zero
exit, malformed output): note it in the report and proceed to Step 4. Codex is
the secondary diversity pass — Phase A already cleared Critical/High, so a
Codex failure (including both Codex reviewers failing) degrades gracefully and
does not halt the skill.

## Step 4: Finalize Report

	Assemble the full report from your running record and write it once to the
	reserved path. Number all findings globally here (CR-001, CR-002, …) across all
	rounds and phases. Do not commit the report; `.dark-factory/reviews/` is local
	working output.
Structure:

```
# Code Review: <Feature Name>
**Date:** YYYY-MM-DD
**Branch:** <branch-name>
**Base:** <merge-base short SHA>
**PRD:** <prd-path>
**QA Runbook:** <qa-path>
**Reviewers:** Claude Quality, Claude Security, Claude Spec, Codex Quality, Codex Spec

## Summary
Phase A (Claude): N rounds, converged to zero Critical/High.
Phase B (Codex): M rounds [stopped early on usage limit — if applicable].
Remediated A Critical, B High, C curated Medium/Low. Deferred D Medium/Low.

## Remediation Log
Per round: findings (Critical/High first, then applied Medium/Low), and the fix
applied to each — explain WHY the code was problematic and WHAT changed.

## Deferred (Medium / Low not applied)
| ID | Severity | Title | Sources | Location | Why deferred |
|----|----------|-------|---------|----------|--------------|
```

The report must be self-contained — readable without the chat context.

## Step 5: Report and Chain

**Check for residual Critical/High first.** If any Critical or High finding is
still unresolved (Phase B hit its 3-round cap or a usage limit with issues left
open, or Phase A hit its 10-round cap without an override), do
NOT chain to QA. Surface the residual findings to the user with the report link
and stop — they decide whether to accept or keep going. Chain only when zero
Critical/High remain.

Present a **TTS-friendly chat summary** (do NOT paste the full report) that
states the ACTUAL outcome — fill the placeholders from what really happened; do
not assert convergence if Phase A hit its 10-round cap or residual Critical/High remain:

```
Review complete. Full report:
<GoGrip link>

**Phase A (Claude):** N rounds — <converged to zero Critical/High | hit 10-round cap with X Critical, Y High remaining>.
**Phase B (Codex):** M rounds <| stopped early on usage limit | not run>.

Remediated A Critical, B High, and C curated Medium/Low. Tests passing.
Deferred D Medium/Low (see report). Fixes committed. <Proceeding to QA acceptance. | Residual Critical/High remain — your call on how to proceed.>
```

When zero Critical/High remain, trigger `df-qa-acceptance` with the QA
runbook path (`<qa-path>`).

## Common Mistakes

- **Running Phase A and Phase B together / in parallel.** They are sequential.
  Codex only runs after Claude has reached zero Critical/High.
- **Stopping after one round.** Each phase loops; re-review after every
  remediation pass until the gate passes (or the Codex cap / limit hits).
- **Asking the user to approve findings one by one.** Remediation is
  autonomous — research, fix, run tests, and commit yourself.
- **Forgetting to refresh the diff / commit between rounds.** Re-reviews (and
  Codex's internal diff) only see committed fixes; an unrefreshed diff replays
  already-fixed findings.
- **Letting a Codex usage limit abort the whole skill.** Detect it, remediate
  any partial findings, and finalize. Do not retry Codex past the limit.
- **Reusing a fixed scratch path.** Every run gets its own `REVIEW_ROOT`;
  writing to a shared path lets concurrent runs clobber each other's reviews.

## Notes

- **Reference file resolution**: look in `$HOME/.claude/skills/df-code-review/references/`
  first, then `<repo>/skills/df-code-review/references/`, then
  `<repo>/.claude/skills/df-code-review/references/`
- The diff is refreshed each round via `git diff "$base_ref" HEAD` — committed
  changes only, no working-tree noise
- Codex is capped at 3 rounds (a usage-limit guard); the Claude phase is capped
  at 10 rounds — set high so real Critical/High get fixed, not abandoned early
- Scratch (diff cache, Codex outputs, stderr logs) goes to the run-scoped
  `REVIEW_ROOT` under /tmp/, never under `.claude/`, so the autonomous loop
  never trips a write-permission prompt; the generated report lives in the
  gitignored `.dark-factory/reviews/` directory
- **`REVIEW_ROOT` in your own context is authoritative.** The pointer file
  `.dark-factory/tmp/code-review-review-dir` is a convenience for a session
  that lost it, and a second run in the same checkout overwrites it. If the
  pointer disagrees with the `REVIEW_ROOT` you created in Step 1, trust your
  own and say so in the report.
- Run project tests before starting this skill (not its job to fix pre-existing
  failures)
