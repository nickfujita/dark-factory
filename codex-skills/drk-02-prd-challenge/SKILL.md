---
name: drk-02-prd-challenge
description: "Codex-native PRD challenge round: Codex persona subagents followed by an interactive Claude Code tmux review, with autonomous PRD remediation looped between rounds. Use after a PRD passes its quality gate, when the user wants stress-testing of requirements, or when asked to 'challenge this PRD'."
---

# PRD Challenge Round

Stress-test a hardened PRD in two sequential review-and-remediation phases.
**Phase A** runs three Codex persona subagents in a fix-and-re-review loop
until zero Critical/High findings remain. **Phase B** runs an interactive
Claude Code review in tmux as the cross-model check. The PRD is remediated
**autonomously between every round** — the author is not asked to hand-fix
findings.

## Prerequisites

- A PRD file that has passed the quality gate (Status: Hardened)
- Codex CLI installed and authenticated (`codex --version` succeeds)
- Claude Code installed and authenticated (`claude --help` succeeds)
- `tmux` installed (`tmux -V` succeeds)

## Step 1: Confirm the PRD

Ask the user to confirm the PRD path. If the PRD status is still "Draft",
warn that it should pass the quality gate first (but do not block — the user
may override).

Derive the feature slug from the PRD filename (e.g., `prd-user-auth.md` →
`user-auth`). Reserve the report path now; you assemble and write the full
report once, at finalize (Step 4). Across rounds keep a running record of each
round's findings and the remediation you applied — do not append to the report
file each round (that would duplicate the document header).

```bash
mkdir -p .dark-factory/reviews/prd-challenge
repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
review_dir="${TMPDIR:-/tmp}/dark-factory-prd-${repo_key}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$review_dir" .dark-factory/tmp
printf '%s\n' "$review_dir" > .dark-factory/tmp/prd-challenge-review-dir
```

Report path: `.dark-factory/reviews/prd-challenge/<timestamp>-<feature>-prd-challenge.md`
where `<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

## How the review loop works (both phases)

Each phase is a **loop**. One round of the loop is:

1. **Review** — run the phase's reviewer(s) (Phase A / Phase B below specify
   which). All reviewers in a round run in parallel in a single message.
2. **Synthesize** — consolidate this round's findings into your running record
   for the report, tagged Critical / High / Medium / Low, following
   `references/synthesis-prompt.md` (deduplicate, take the highest severity on
   disagreement, tag sources). Ignore findings you already remediated in a
   prior round (a reappearance is a regression — treat it as new); respect
   earlier deferral decisions unless the severity has risen.
3. **Gate check** — count Critical and High findings for the round:
   - **Zero Critical AND zero High** → the phase is complete. Exit the loop.
   - **Otherwise** → remediate (step 4), then start a new round at step 1.
4. **Remediate autonomously** — do NOT hand findings to the user to fix. For
   each finding you fix, research the codebase and the web to determine the
   best correction, then **edit the PRD** to resolve it. Every round you fix:
   - **All Critical findings**
   - **All High findings**
   - A **curated selection of Medium/Low findings** — apply the ones your
     judgment says genuinely strengthen the PRD; skip noise. Record in the
     report which Medium/Low you applied and which you deliberately deferred.

   Saving the PRD edits is enough for the next round to see them — the
   reviewers read the PRD file directly. Do not commit between rounds.

The phases are **sequential, not parallel**: Phase A must reach zero
Critical/High before Phase B begins.

## Step 2: Phase A — Codex persona loop (until zero Critical/High)

Read `references/personas.md` for the 3 persona system prompts.

**Each round, run 3 parallel Codex persona reviews** (one per persona).
Preferred path: explicitly spawn 3 Codex subagents or use
`superpowers:dispatching-parallel-agents`, then wait for all three before
synthesis. Each subagent receives:
- Its persona system prompt from `references/personas.md`
- The full PRD content inline (or, if the PRD exceeds ~4000 words, the file
  path with an instruction to read it)
- An instruction to explore the codebase to ground its analysis in what
  actually exists

Each subagent returns markdown findings under a self-identifying header
(e.g., `## Findings — Skeptical User Advocate`). Label each result with
`### Source: [Persona Name]` before synthesis.

**Fallback when native subagents are unavailable:** run the bundled parallel
Codex CLI script with **`timeout: 600000`**:

```bash
script_path="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-02-prd-challenge/scripts/run_codex_persona_reviews.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-skills/drk-02-prd-challenge/scripts/run_codex_persona_reviews.sh"
fi
if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_persona_reviews.sh" >&2
  echo "Checked: \${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/ and <repo>/codex-skills/" >&2
  exit 1
fi

review_dir="$(cat .dark-factory/tmp/prd-challenge-review-dir)"
out_dir="$review_dir/prd-personas"
mkdir -p "$out_dir"
bash "$script_path" "<prd-path>" "$out_dir"
echo "OUTPUT_DIR=$out_dir"
```

Read all markdown files in `$review_dir/prd-personas/` before synthesis.

Then run synthesize → gate check → remediate (above). **Loop until the gate
passes** (zero Critical and zero High) or the round cap below is reached.

**Round cap (safety guard):** the Codex phase loops until the gate passes, but
is capped at **10 rounds** — set high on purpose, because real Critical/High
findings from Codex should be fixed, not abandoned early. If round 10 completes
with Critical or High still open, stop and surface the remaining findings to the
user (with the report link): do not run Phase B, do not mark the PRD Approved,
and do not finalize with open Critical/High. If the user overrides ("good
enough, move on"), continue to Phase B; otherwise the user drives the next move.

## Step 3: Phase B — Claude Code tmux loop (max 3 rounds)

Once Phase A's Codex gate passes, run the Claude Code reviewer in the same loop,
**capped at 3 rounds total**.

**Each round, run the interactive Claude Code PRD review through tmux** with
**`timeout: 1800000`**:

```bash
script_path="${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-02-prd-challenge/scripts/run_claude_prd_review_tmux.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/codex-skills/drk-02-prd-challenge/scripts/run_claude_prd_review_tmux.sh"
fi
if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_claude_prd_review_tmux.sh" >&2
  echo "Checked: \${CODEX_SKILLS_HOME:-\${CODEX_HOME:-\$HOME/.codex}/skills}/ and <repo>/codex-skills/" >&2
  exit 1
fi

review_dir="$(cat .dark-factory/tmp/prd-challenge-review-dir 2>/dev/null || true)"
if [[ -z "$review_dir" ]]; then
  repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
  review_dir="${TMPDIR:-/tmp}/dark-factory-prd-${repo_key}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p .dark-factory/tmp
  printf '%s\n' "$review_dir" > .dark-factory/tmp/prd-challenge-review-dir
fi
mkdir -p "$review_dir"
out_path="$review_dir/claude-challenge-review.md"
bash "$script_path" \
  "<prd-path>" \
  "$out_path"
echo "OUTPUT_PATH=$out_path"
```

This helper starts a real interactive `claude` session in tmux and sends the
review prompt into that session. It must not use `claude -p`, `--print`, SDK
mode, or stdout piping. It returns only after Claude writes the report and then
creates a completion sentinel.

Read the Claude output at `$review_dir/claude-challenge-review.md`, then run
synthesize → gate check → remediate (above). **Stop the loop when the gate
passes OR after 3 rounds**, whichever comes first. After 3 rounds, proceed to
Step 4 even if Medium/Low (or unresolved-but-not-Critical/High) remain.

**Claude tmux failure:** if the tmux helper fails, times out, or does not write a
completion sentinel, note it in the report and proceed to Step 4. Claude is the
secondary diversity pass — Phase A already cleared Critical/High, so a Claude
failure degrades gracefully and does not halt the skill.

## Step 4: Finalize

1. **Write the full report** from your running record to the reserved path: per
   phase, the rounds run, each round's findings, the remediation applied
   (Critical/High + which Medium/Low), and the residual Medium/Low left
   intentionally. Number findings once, globally. Include the metadata header
   (Date, PRD path, Reviewers, final Summary count). It must be self-contained —
   readable without the chat context.
2. **Check for residual Critical/High.** If any Critical or High finding is
   still unresolved (Phase B hit its 3-round cap with issues left open, or Phase
   A hit its 10-round cap without an override), do NOT mark the PRD Approved.
   Surface the residual findings to the user with the report link, and stop —
   they decide whether to accept or keep going.
3. **Otherwise (zero Critical/High remain):** set the PRD's Status field to
   "Approved", save, and commit the PRD:
   `git add <prd-path> && git commit -m "docs: approve PRD after challenge round for <feature>"`
4. Present a **TTS-friendly chat summary** (do NOT paste the full report) that
   states the ACTUAL outcome — fill the placeholders from what really happened;
   do not assert convergence if Phase A hit its 10-round cap or residual
   Critical/High remain:

```
Challenge round complete. Full report:
<GoGrip link>

**Phase A (Codex):** N rounds — <converged to zero Critical/High | hit 10-round cap with X Critical, Y High remaining>.
**Phase B (Claude Code tmux):** M rounds <| failed/timed out | not run>.

Remediated A Critical, B High, and C curated Medium/Low findings in the PRD.
Deferred D Medium/Low (see report). <PRD set to Status: Approved and committed. Ready for the next stage. | Residual Critical/High remain — your call on how to proceed.>
```

## Common Mistakes

- **Running Phase A and Phase B together / in parallel.** They are sequential.
  Claude Code review only runs after the Codex persona subagents reach zero
  Critical/High.
- **Stopping after one round.** Each phase loops; re-review after every
  remediation pass until the gate passes (or the phase cap hits).
- **Handing Critical/High findings to the user to fix.** Remediation is
  autonomous — research and edit the PRD yourself.
- **Using `claude -p` for Phase B.** Do not use non-interactive Claude mode.
  Start interactive Claude Code in tmux and wait for the completion sentinel.

## Notes

- **Reference file resolution**: `references/personas.md` and
  `references/synthesis-prompt.md` are relative to the skill directory.
  Look in `${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-02-prd-challenge/references/` (global) or
  the repo's `codex-skills/drk-02-prd-challenge/references/` directory. If not found,
  stop and report the error.
- Personas are gap-finders, not scope-expanders. They should never suggest
  new features.
- The Claude Code tmux review provides a cross-model second pass. It may catch
  blind spots the in-thread Codex persona subagents share.
- The Claude phase is capped at 3 rounds; the subagent phase is capped
  at 10 rounds — set high so real Critical/High get fixed, not abandoned early.
- Scratch outputs go to a run-scoped project directory under /tmp/, with the
  path recorded in `.dark-factory/tmp/prd-challenge-review-dir`. The generated
  report lives in the gitignored `.dark-factory/reviews/` directory.
