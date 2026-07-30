---
name: drk-02-prd-challenge
description: "Multi-model PRD challenge round: Claude persona reviewers then Codex, with autonomous PRD remediation looped between rounds. Use after a PRD passes its quality gate, when the user wants stress-testing of requirements, or when asked to 'challenge this PRD'."
---

# PRD Challenge Round

Stress-test a hardened PRD in two sequential review-and-remediation phases.
**Phase A** runs three Claude personas in a fix-and-re-review loop until zero
Critical/High findings remain. **Phase B** runs a Codex review in a capped loop
for model diversity. The PRD is remediated **autonomously between every round** —
the author is not asked to hand-fix findings.

## Prerequisites

- A PRD file that has passed the quality gate (Status: Hardened)
- Codex CLI installed and authenticated (`codex --version` succeeds)

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

## Step 2: Phase A — Claude persona loop (until zero Critical/High)

Read `references/personas.md` for the 3 persona system prompts.

**Each round, dispatch the 3 Claude personas as parallel sub-agents** (all 3
Task/Agent calls in one message). Each sub-agent receives:
- Its persona system prompt from `references/personas.md`
- The full PRD content inline (or, if the PRD exceeds ~4000 words, the file
  path with an instruction to read it)
- An instruction to explore the codebase to ground its analysis in what
  actually exists

Each sub-agent returns markdown findings under a self-identifying header
(e.g., `## Findings — Skeptical User Advocate`). Label each result with
`### Source: [Persona Name]` before synthesis.

Then run synthesize → gate check → remediate (above). **Loop until the gate
passes** (zero Critical and zero High) or the round cap below is reached.

**Round cap (safety guard):** the Claude phase loops until the gate passes, but
is capped at **10 rounds** — set high on purpose, because real Critical/High
findings from Claude should be fixed, not abandoned early. If round 10 completes
with Critical or High still open, stop and surface the remaining findings to the
user (with the report link): do not run Phase B, do not mark the PRD Approved,
and do not finalize with open Critical/High. If the user overrides ("good
enough, move on"), continue to Phase B; otherwise the user drives the next move.

## Step 3: Phase B — Codex loop (max 3 rounds)

Once Phase A's gate passes, run the Codex reviewer in the same loop, **capped
at 3 rounds total**.

**Each round, run the Codex PRD review** with **`timeout: 600000`** (10
minutes — Codex with high reasoning effort is slow):

```bash
script_path="$HOME/.claude/skills/drk-02-prd-challenge/scripts/run_codex_prd_review.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/drk-02-prd-challenge/scripts/run_codex_prd_review.sh"
fi
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/drk-02-prd-challenge/scripts/run_codex_prd_review.sh"
fi

if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_prd_review.sh" >&2
  echo "Checked: \$HOME/.claude/skills/, <repo>/skills/, <repo>/.claude/skills/" >&2
  exit 1
fi

out_path="/tmp/dark-factory-review/codex-challenge-review.md"
mkdir -p /tmp/dark-factory-review
bash "$script_path" \
  "<prd-path>" \
  "$out_path"
echo "OUTPUT_PATH=$out_path"
```

Read the Codex output at `/tmp/dark-factory-review/codex-challenge-review.md`, then run
synthesize → gate check → remediate (above). **Stop the loop when the gate
passes OR after 3 rounds**, whichever comes first. After 3 rounds, proceed to
Step 4 even if Medium/Low (or unresolved-but-not-Critical/High) remain.

**Codex usage-limit exception (the important escape hatch):** if a Codex run
fails on a usage/rate limit, stop Phase B immediately — do not run any more
Codex rounds. The script exits non-zero and writes a stderr log at
`/tmp/dark-factory-review/codex-challenge-review.stderr.log`. Read that log: a usage limit
shows up as patterns like `usage limit`, `rate limit`, `quota`, `429`,
`too many requests`, or `reached your (usage )?limit`. When you detect one:
- **Remediate any not-yet-remediated findings the limited run returned** (same
  rules as the loop's Remediate step — all Critical/High plus curated
  Medium/Low). Findings from earlier Codex rounds this phase were already
  remediated in-loop; do not re-edit them.
- If Codex returned no usable findings before the limit, just proceed.
- Either way, continue to Step 4. Note in the report that Phase B stopped
  early on a Codex usage limit.

**Codex failure that is NOT a usage limit** (script missing, generic non-zero
exit, malformed output): note it in the report and proceed to Step 4. Codex is
the secondary diversity pass — Phase A already cleared Critical/High, so a
Codex failure degrades gracefully and does not halt the skill.

## Step 4: Finalize

1. **Write the full report** from your running record to the reserved path: per
   phase, the rounds run, each round's findings, the remediation applied
   (Critical/High + which Medium/Low), and the residual Medium/Low left
   intentionally. Number findings once, globally. Include the metadata header
   (Date, PRD path, Reviewers, final Summary count). It must be self-contained —
   readable without the chat context.
2. **Check for residual Critical/High.** If any Critical or High finding is
   still unresolved (Phase B hit its 3-round cap or a usage limit with issues
   left open, or Phase A hit its 10-round cap without an override), do NOT mark
   the PRD Approved. Surface the residual findings to the user with the report
   link, and stop — they decide whether to accept or keep going.
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

**Phase A (Claude):** N rounds — <converged to zero Critical/High | hit 10-round cap with X Critical, Y High remaining>.
**Phase B (Codex):** M rounds <| stopped early on usage limit | not run>.

Remediated A Critical, B High, and C curated Medium/Low findings in the PRD.
Deferred D Medium/Low (see report). <PRD set to Status: Approved and committed. Ready for the next stage. | Residual Critical/High remain — your call on how to proceed.>
```

## Common Mistakes

- **Running Phase A and Phase B together / in parallel.** They are sequential.
  Codex only runs after Claude has reached zero Critical/High.
- **Stopping after one round.** Each phase loops; re-review after every
  remediation pass until the gate passes (or the Codex cap / limit hits).
- **Handing Critical/High findings to the user to fix.** Remediation is
  autonomous — research and edit the PRD yourself.
- **Letting a Codex usage limit abort the whole skill.** Detect it, remediate
  any partial findings, and finalize. Do not retry Codex past the limit.

## Notes

- **Reference file resolution**: `references/personas.md` and
  `references/synthesis-prompt.md` are relative to the skill directory.
  Look in `$HOME/.claude/skills/drk-02-prd-challenge/references/` (global) or
  the repo's `skills/drk-02-prd-challenge/references/` directory. If not found,
  stop and report the error.
- Personas are gap-finders, not scope-expanders. They should never suggest
  new features.
- Codex provides model diversity (GPT vs Claude). It may catch blind spots
  all Claude personas share.
- Codex is capped at 3 rounds (a usage-limit guard); the Claude phase is capped
  at 10 rounds — set high so real Critical/High get fixed, not abandoned early.
- Scratch (Codex output, stderr log) goes to a project-namespaced directory
  under /tmp/, never under .claude/, so the autonomous loop never trips a
  write-permission prompt; the generated report lives in the gitignored
  `.dark-factory/reviews/` directory.
