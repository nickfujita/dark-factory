---
name: drk-06-code-review
description: "Codex-native code review for a feature branch with autonomous remediation looped between review rounds. Use after implementation is complete and before QA acceptance. Writes a findings report, applies fixes itself, and returns QA-ready status."
---

# Code Review

Review a feature branch in two sequential review-and-remediation phases.
**Phase A** runs three parallel Codex reviewer subagents (quality, security,
spec) in a fix-and-re-review loop until zero Critical/High findings remain.
**Phase B** runs two interactive Claude Code reviewers in tmux as the
cross-model check. Fixes are
**applied autonomously between every round** — the user is not asked to approve
findings one by one. Returns QA-ready status when the review gate passes.

## Prerequisites

- Feature branch checked out with implementation complete
- Tests passing before review begins
- E2e test suite exists and passes, covering QA runbook test cases
- Codex CLI installed and authenticated (`codex --version` succeeds)
- Claude Code installed and authenticated (`claude --help` succeeds)
- `tmux` installed (`tmux -V` succeeds)
- PRD (`docs/prd-<feature>.md`, Status: Approved) and QA runbook
  (`docs/qa/qa-<feature>.md`) exist for this feature

## Step 1: Resolve Inputs

**Detect branch and base:**
```bash
feature_branch=$(git branch --show-current)
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [[ -z "$default_branch" ]]; then
  if git rev-parse --verify main >/dev/null 2>&1; then
    default_branch="main"
  elif git rev-parse --verify master >/dev/null 2>&1; then
    default_branch="master"
  else
    echo "ERROR: Cannot determine default branch. Provide a base ref." >&2
    exit 1
  fi
fi
base_ref=$(git merge-base HEAD "$default_branch")
```

**Derive feature slug from branch name:**
Strip common prefixes (`feat/`, `feature/`, `fix/`, `chore/`). Use the
remainder as the slug (e.g., `feat/user-auth` → `user-auth`).

**Locate PRD and QA runbook:**
1. Scan `docs/` for `prd-<slug>.md` with `Status: Approved`
2. Scan `docs/qa/` for `qa-<slug>.md`
3. If no exact match: list candidate files and ask the user to confirm paths

**Cache the diff** (this is refreshed at the start of every round — see below):
```bash
repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
branch_key="$(printf '%s' "$feature_branch" | tr -cs 'A-Za-z0-9._-' '-')"
review_dir="${TMPDIR:-/tmp}/dark-factory-code-${repo_key}-${branch_key}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$review_dir" .dark-factory/tmp
printf '%s\n' "$review_dir" > .dark-factory/tmp/code-review-dir
git diff "$base_ref" HEAD > "$review_dir/branch-diff.txt"
```

Read `$review_dir/branch-diff.txt`. If empty, stop and tell the user there
are no changes to review versus the detected default branch.

Resolve the reference directory (needed for Codex subagent prompts):
```bash
ref_dir="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-06-code-review/references"
if [[ ! -d "$ref_dir" ]]; then
  ref_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-skills/drk-06-code-review/references"
fi
```

Reserve the report path now; you assemble and write the full report once, at
finalize (Step 4). Keep a running record of each round's findings and fixes —
do not write the report file during the loop, so it stays out of the diff Codex
reviews and you avoid duplicated headers:
```bash
mkdir -p .dark-factory/reviews/code-review
```
Report path: `.dark-factory/reviews/code-review/<timestamp>-<feature>-code-review.md`
where `<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

## How the review loop works (both phases)

Each phase is a **loop**. One round of the loop is:

1. **Refresh the diff (Phase A only)** — Phase A's Codex subagent reviewers read the
   cached diff, so refresh it at the start of each Phase A round to show the
   latest committed state (prior rounds' fixes are committed — see step 5).
   Recompute the base ref in the same command, since shell variables do not
   persist between separate Bash calls:
   ```bash
   review_dir="$(cat .dark-factory/tmp/code-review-dir)"
   default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
   if [[ -z "$default_branch" ]]; then
     if git rev-parse --verify main >/dev/null 2>&1; then default_branch="main";
     elif git rev-parse --verify master >/dev/null 2>&1; then default_branch="master";
     else echo "ERROR: Cannot determine default branch. Provide a base ref." >&2; exit 1;
     fi
   fi
   base_ref="$(git merge-base HEAD "$default_branch")"
   mkdir -p "$review_dir"
   git diff "$base_ref" HEAD > "$review_dir/branch-diff.txt"
   ```
   Phase B's Claude helper computes its own diff from the base ref internally,
   so it does not need this refresh.
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
   one. Apply fixes using the Codex Superpowers `receiving-code-review` discipline:
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
	   round's diff and reviewer helper inputs reflect the fixes.

The phases are **sequential, not parallel**: Phase A must reach zero
Critical/High before Phase B begins.

## Step 2: Phase A — Codex reviewer loop (until zero Critical/High)

**Each round, run 3 parallel Codex review contexts** (one quality reviewer, one
security reviewer, one spec reviewer). Preferred path: explicitly spawn 3 Codex
subagents or use `superpowers:dispatching-parallel-agents`, then wait for all
three before synthesis. Each reviewer reads its prompt file, reads
`$review_dir/branch-diff.txt` for the diff, reads the changed files for context,
and returns findings under a self-identifying header.

- **Reviewer 1 — Codex Quality:** `$ref_dir/codex-quality-subagent-prompt.md`.
  Header: `## Findings — Codex Quality`.
- **Reviewer 2 — Codex Security:** `$ref_dir/codex-security-subagent-prompt.md`.
  Header: `## Findings — Codex Security`.
- **Reviewer 3 — Codex Spec:** `$ref_dir/codex-spec-subagent-prompt.md`.
  Also reads `<prd-path>` and `<qa-path>`. Header: `## Findings — Codex Spec`.

If one Codex reviewer fails, note it and proceed with the remaining two. Then
run synthesize → gate check → remediate (above). **Loop until the gate passes**
(zero Critical and zero High) or the round cap below is reached.

**Fallback when native subagents are unavailable:** run the bundled parallel
Codex CLI script with **`timeout: 600000`**:

```bash
script_path="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-06-code-review/scripts/run_codex_subagent_reviews.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-skills/drk-06-code-review/scripts/run_codex_subagent_reviews.sh"
fi
if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_subagent_reviews.sh" >&2
  echo "Checked: \${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/ and <repo>/codex-skills/" >&2
  exit 1
fi

review_dir="$(cat .dark-factory/tmp/code-review-dir)"
out_dir="$review_dir/code-subagents"
mkdir -p "$out_dir"
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [[ -z "$default_branch" ]]; then
  if git rev-parse --verify main >/dev/null 2>&1; then default_branch="main";
  elif git rev-parse --verify master >/dev/null 2>&1; then default_branch="master";
  else echo "ERROR: Cannot determine default branch. Provide a base ref." >&2; exit 1;
  fi
fi
base_ref="$(git merge-base HEAD "$default_branch")"
DARK_FACTORY_REVIEW_DIR="$review_dir" bash "$script_path" "<prd-path>" "<qa-path>" "$base_ref" "$out_dir"
echo "OUTPUT_DIR=$out_dir"
```

Read all markdown files in `$review_dir/code-subagents/` before synthesis.

**Round cap (safety guard):** the Codex phase loops until the gate passes, but
is capped at **10 rounds** — set high on purpose, because real Critical/High
findings from Codex should be fixed, not abandoned early. If round 10 completes
with Critical or High still open, stop and surface the remaining findings to the
user (with the report link): do not run Phase B, do not chain to QA, and do not
finalize with open Critical/High. If the user overrides ("good enough, move
on"), continue to Phase B; otherwise the user drives the next move.

## Step 3: Phase B — Claude Code tmux reviewer loop (max 3 rounds)

Once Phase A's Codex gate passes, run the 2 Claude Code reviewers in the same
loop, **capped at 3 rounds total**.

**Each round, launch both Claude Code reviewers** through one tmux helper with
**`timeout: 1800000`**. The helper starts a real interactive `claude` session
with two tmux windows (`quality` and `spec`), sends the review prompts into
those sessions, and waits for completion sentinels before returning.

```bash
script_path="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-06-code-review/scripts/run_claude_code_reviews_tmux.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-skills/drk-06-code-review/scripts/run_claude_code_reviews_tmux.sh"
fi
if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_claude_code_reviews_tmux.sh" >&2; exit 1
fi
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [[ -z "$default_branch" ]]; then
  if git rev-parse --verify main >/dev/null 2>&1; then default_branch="main";
  elif git rev-parse --verify master >/dev/null 2>&1; then default_branch="master";
  else echo "ERROR: Cannot determine default branch. Provide a base ref." >&2; exit 1;
  fi
fi
base_ref="$(git merge-base HEAD "$default_branch")"

review_dir="$(cat .dark-factory/tmp/code-review-dir 2>/dev/null || true)"
if [[ -z "$review_dir" ]]; then
  repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
  branch_key="$(git branch --show-current | tr -cs 'A-Za-z0-9._-' '-')"
  review_dir="${TMPDIR:-/tmp}/dark-factory-code-${repo_key}-${branch_key}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p .dark-factory/tmp
  printf '%s\n' "$review_dir" > .dark-factory/tmp/code-review-dir
fi
mkdir -p "$review_dir/claude"
bash "$script_path" "<prd-path>" "<qa-path>" "$base_ref" "$review_dir/claude"
```

Do not use `claude -p`, `--print`, SDK mode, stdout piping, or any
non-interactive Claude invocation. Phase B must use interactive Claude Code in
tmux.

Read `$review_dir/claude/claude-quality-review.md` and
`$review_dir/claude/claude-spec-review.md`, then run synthesize → gate check →
remediate (above). **Stop the loop when the gate passes OR after 3 rounds**,
whichever comes first. After 3 rounds, proceed to Step 4 even if Medium/Low
remain.

**Claude tmux failure:** if the tmux helper fails, times out, or does not write
completion sentinels, note it in the report and proceed to Step 4. Claude is the
secondary diversity pass — Phase A already cleared Critical/High, so a Claude
failure degrades gracefully and does not halt the skill.

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
**Reviewers:** Codex Quality Subagent, Codex Security Subagent, Codex Spec Subagent, Claude Quality, Claude Spec

## Summary
Phase A (subagents): N rounds, converged to zero Critical/High.
Phase B (Claude Code tmux): M rounds [failed/timed out — if applicable].
Remediated A Critical, B High, C curated Medium/Low. Deferred D Medium/Low.

## Remediation Log
Per round: findings (Critical/High first, then applied Medium/Low), and the fix
applied to each — explain WHY the code was problematic and WHAT changed.

## Deferred (Medium / Low not applied)
| ID | Severity | Title | Sources | Location | Why deferred |
|----|----------|-------|---------|----------|--------------|
```

The report must be self-contained — readable without the chat context.

## Step 5: Report QA-Ready Status

**Check for residual Critical/High first.** If any Critical or High finding is
still unresolved (Phase B hit its 3-round cap with issues left
open, or Phase A hit its 10-round cap without an override), do
NOT mark the branch QA-ready. Surface the residual findings to the user with the
report link and stop — they decide whether to accept or keep going. Report
QA-ready status only when zero Critical/High remain.

Present a **TTS-friendly chat summary** (do NOT paste the full report) that
states the ACTUAL outcome — fill the placeholders from what really happened; do
not assert convergence if Phase A hit its 10-round cap or residual Critical/High remain:

```
Review complete. Full report:
<GoGrip link>

**Phase A (subagents):** N rounds — <converged to zero Critical/High | hit 10-round cap with X Critical, Y High remaining>.
**Phase B (Claude Code tmux):** M rounds <| failed/timed out | not run>.

Remediated A Critical, B High, and C curated Medium/Low. Tests passing.
Deferred D Medium/Low (see report). Fixes committed. <Ready for QA acceptance. | Residual Critical/High remain — your call on how to proceed.>
```

When zero Critical/High remain, report the QA runbook path (`<qa-path>`) and
QA-ready status. When running under `dark-factory-codex`, stop here so the
orchestrator can explicitly invoke `drk-07-qa-acceptance`. If this skill was
invoked standalone, tell the user the next stage is `drk-07-qa-acceptance`.

## Common Mistakes

- **Running Phase A and Phase B together / in parallel.** They are sequential.
  Claude reviewers only run after the Codex subagent reviewers reach zero Critical/High.
- **Stopping after one round.** Each phase loops; re-review after every
  remediation pass until the gate passes or the phase cap hits.
- **Asking the user to approve findings one by one.** Remediation is
  autonomous — research, fix, run tests, and commit yourself.
- **Using `claude -p` for Phase B.** Do not use non-interactive Claude mode.
  Start interactive Claude Code in tmux and wait for the completion sentinels.
- **Forgetting to refresh the diff / commit between rounds.** Re-reviews only
  see committed fixes; an unrefreshed diff replays
  already-fixed findings.

## Notes

- **Reference file resolution**: look in `${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-06-code-review/references/`
  first, then `<repo>/codex-skills/drk-06-code-review/references/`
- The diff is refreshed each round via `git diff "$base_ref" HEAD` — committed
  changes only, no working-tree noise
- Claude Code tmux is capped at 3 rounds; the Codex subagent phase is capped
  at 10 rounds — set high so real Critical/High get fixed, not abandoned early
- Scratch (diff cache, Codex outputs, Claude outputs, completion sentinels, and
  stderr logs) goes to a run-scoped project directory under /tmp/, with the path
	  recorded in `.dark-factory/tmp/code-review-dir`, so concurrent runs do not
	  collide. The generated report lives in the gitignored `.dark-factory/reviews/`
	  directory.
- Run project tests before starting this skill (not its job to fix pre-existing
  failures)
