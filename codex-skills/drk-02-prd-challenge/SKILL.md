---
name: drk-02-prd-challenge
description: "Codex-native PRD challenge round: Codex persona subagents followed by an interactive Claude Code tmux review, with autonomous PRD remediation, consistency gates and verification rounds looped between reviews. Use after a PRD passes its quality gate, when the user wants stress-testing of requirements, or when asked to 'challenge this PRD'."
---

# PRD Challenge Round

Stress-test a hardened PRD in two sequential review-and-remediation phases.
**Phase A** runs three Codex persona subagents in a fix-and-re-review loop.
**Phase B** runs an interactive Claude Code review in tmux as the cross-model
check. The PRD is remediated **autonomously between every round** — the author
is not asked to hand-fix findings.

Upstream: `drk-01-prd-interview` produces the Hardened PRD this skill consumes.
Downstream: `drk-03-qa-runbook-gen` consumes the PRD this skill approves.

Rationale, evidence, and the failure modes each rule exists to prevent are in
`references/rationale.md`. This file is instructions only.

## Pinned parameters

**This table is the single source of truth for every tunable in this skill.**
Everywhere else in this skill and its references, parameters are referred to by
name. Do not restate a value inline — if you need the number, read it here.

| Parameter | Value | Applies to |
|---|---|---|
| `PHASE_A_SOFT_CAP` | 10 rounds | Phase A loop |
| `PHASE_B_SOFT_CAP` | 3 rounds | Phase B loop |
| `CONVERGENCE_EXTENSION` | 2 rounds, per phase | rounds permitted past a soft cap, method-change rounds only |
| `REVIEW_ROOT` | `${TMPDIR:-/tmp}/dark-factory-prd-<repo-key>-<run-id>` | all scratch output for one run |
| `RUN_DIR_POINTER` | `.dark-factory/tmp/prd-challenge-review-dir` | file recording `REVIEW_ROOT` |
| `REPORT_DIR` | `.dark-factory/reviews/prd-challenge/` | the final report |
| `CODEX_REASONING_EFFORT` | `xhigh` | Codex persona reviewers |
| `CODEX_WINDOW_SECONDS` | `3600` | total detached window for one Phase A round |
| `CODEX_WAIT_SLICE_SECONDS` | `480` | one foreground poll slice |
| `CODEX_POLL_SECONDS` | `20` | poll interval inside a slice |
| `CODEX_MIN_BODY_BYTES` | `400` | minimum accepted review body when findings are claimed |
| `CLAUDE_REVIEW_TIMEOUT_SECONDS` | `1800` | tmux Claude review window |
| `GROWTH_WARN_ROUND_PCT` | `15` | per-round PRD word-count growth that must be flagged |
| `GROWTH_WARN_TOTAL_PCT` | `50` | cumulative PRD word-count growth that must be flagged |
| `SELF_FEEDING_THRESHOLD` | `50%` | share of a round's new Critical/High living in prose the previous remediation added, above which the loop must change method |

The Codex-side timing and validation values are also the defaults compiled into
`scripts/run_codex_persona_reviews.sh`; override them there via the environment
variables the script documents, never by editing call sites.

## Prerequisites

- A PRD file that has passed the quality gate (Status: Hardened)
- Codex CLI installed and authenticated (`codex --version` succeeds)
- Claude Code installed and authenticated (`claude --help` succeeds)
- `tmux` installed (`tmux -V` succeeds)

## Step 1: Open the run

Ask the user to confirm the PRD path. If the PRD status is still "Draft",
warn that it should pass the quality gate first (but do not block — the user
may override).

Derive the feature slug from the PRD filename (e.g., `prd-user-auth.md` →
`user-auth`). Reserve the report path now; you assemble and write the full
report once, at finalize (Step 4). Across rounds keep a **running record** of
each round (see "The round record") — do not append to the report file each
round (that would duplicate the document header).

Create a **run-scoped** scratch directory. Never write review output to a fixed
shared path: concurrent challenge runs on the same machine will clobber each
other and destroy a completed review.

```bash
mkdir -p .dark-factory/reviews/prd-challenge .dark-factory/tmp
repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
review_dir="${TMPDIR:-/tmp}/dark-factory-prd-${repo_key}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$review_dir"
printf '%s\n' "$review_dir" > .dark-factory/tmp/prd-challenge-review-dir
echo "REVIEW_ROOT=$review_dir"
sha256sum "<prd-path>" | cut -d' ' -f1   # baseline PRD hash
wc -w "<prd-path>"                       # baseline word count
```

Report path: `REPORT_DIR/<timestamp>-<feature>-prd-challenge.md` where
`<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

**Adopt an orphaned review (merge, do not stack).** Before round 1, check for a
completed-but-unsynthesized review of this PRD. If one exists and the PRD
sha256 recorded with it is **byte-identical** to the current PRD's sha256,
merge its findings into round 1's synthesis as an additional source and label
it as such — do not count it as a separate round, and do not discard it. If the
hashes differ, ignore it and say so in the report.

## Round types

| Type | Scope | Reviewer mode | May the remediator change requirements? |
|---|---|---|---|
| **Discovery round** | the whole PRD | discovery (default persona prompts) | yes |
| **Verification round** | the remediation delta since the reviewer's last pass | verification (per-finding `CONFIRMED`/`NOT CONFIRMED`) | yes, for `NOT CONFIRMED` items and new findings only |
| **Consistency-only pass** | cross-reference, terminology, table and value integrity | n/a — the orchestrator performs it | **no** — charter in `references/consistency-pass.md` is binding |

A **consistency-only pass** and any other structural or consolidation pass is a
change like any other and **must be followed by a verification round scoped to
that pass**. Never approve a PRD directly off a restructure.

## The round loop (both phases)

One round is:

1. **Review** — run the phase's reviewer(s). All reviewers in a round run in
   parallel. Record the PRD sha256 the round reviewed.
2. **Synthesize** — consolidate this round's findings into the running record
   following `references/synthesis-prompt.md` (deduplicate, take the highest
   severity on disagreement, tag sources). Every finding carries a severity
   **and a class** (`SUBSTANTIVE` or `CONSISTENCY`) emitted by the reviewer; if
   a reviewer omitted the class, classify it yourself using the definitions in
   `references/synthesis-prompt.md` and mark it as inferred.
   - A finding you already remediated in a prior round that reappears is a
     **regression** — treat it as new, and record it as a regression.
   - A finding already recorded in the PRD's Decision Register is dismissed by
     citing that entry, unless its severity has risen or the reviewer brings
     new evidence.
3. **Gate check** — see "The trend-aware gate".
4. **Remediate autonomously** — do NOT hand findings to the user to fix. For
   each finding you fix, research the codebase and the web to determine the
   best correction, then **edit the PRD** to resolve it. Every round you fix:
   - **All Critical findings**
   - **All High findings**
   - A **curated selection of Medium/Low findings** — the ones your judgment
     says genuinely strengthen the PRD; skip noise. Record which Medium/Low you
     applied and which you deliberately deferred, and add every *declined*
     finding to the PRD's Decision Register.

   Remediation edits obey `references/prd-structure-rules.md` — one normative
   home per rule, rationale in marked blocks, in-place edits over appended
   qualifiers, and **assertion-checked replacements** (every replacement must
   match its target exactly once; on 0 or >1 matches, stop and re-locate rather
   than loosening the match).

   Saving the PRD edits is enough for the next round to see them — the
   reviewers read the PRD file directly. Do not commit between rounds.
5. **Consistency gate (mandatory, mechanical)** — run the procedure in
   `references/consistency-pass.md` § "The post-remediation consistency gate"
   over every edit you just made. This is not "check consistency"; it is a
   mechanical re-resolution of every cross-reference, threshold/parameter and
   defined term the fix touched. **The round is not finished until the gate
   reports zero stale hits.** Record the gate's counters in the round record.

The phases are **sequential, not parallel**: Phase A must reach its exit
condition before Phase B begins.

### The round record

Per round, the running record must capture:

- round number, phase, and **round type**
- PRD sha256 at review time, and PRD word count (plus % change vs. previous
  round and vs. baseline — flag at `GROWTH_WARN_ROUND_PCT` /
  `GROWTH_WARN_TOTAL_PCT`)
- which reviewers ran and over what scope
- findings by severity **and by class**, plus how many of this round's new
  Critical/High live in prose the previous round's remediation added
- regressions and Decision Register dismissals
- remediation applied, and the consistency gate counters
- for verification rounds: the `CONFIRMED` / `NOT CONFIRMED` tally

### The trend-aware gate

Count this round's Critical and High findings, then:

- **Zero Critical AND zero High** → run one **verification round** over the
  remediation delta if the previous round was not already one. The phase exits
  when a verification round returns zero `NOT CONFIRMED` verdicts and zero new
  Critical/High.
- **Otherwise** → remediate, run the consistency gate, and start a new round —
  but first read the trend.

Maintain a severity trend line in the running record, e.g.
`R1 3C/7H → R2 3C/15H → R3 2C/10H → R4 1C/5H → R5 0C/4H`. Then:

- **Converging** (Critical+High strictly declining across the last two rounds,
  and the class mix shifting toward `CONSISTENCY`) → another round of the same
  type is justified.
- **Self-feeding** (at least `SELF_FEEDING_THRESHOLD` of this round's new
  Critical/High live in prose the previous round's remediation added, **or**
  Critical+High is flat or rising across two consecutive rounds) → **change
  method, do not run another discovery round.** Run a consistency-only pass,
  then a verification round.

Record the trend and which branch you took in the round record.

## Step 2: Phase A — Codex persona loop

Read `references/personas.md` for the 3 persona system prompts, the shared
output contract, and the verification-round mode.

**Each round, run 3 parallel Codex persona reviews** (one per persona).
Preferred path: explicitly spawn 3 Codex subagents or use
`superpowers:dispatching-parallel-agents`, then wait for all three before
synthesis. Each subagent receives:

- Its persona system prompt from `references/personas.md`
- The shared output contract from `references/personas.md` (severity **and**
  `Class:` on every finding)
- The full PRD content inline (or, if the PRD exceeds ~4000 words, the file
  path with an instruction to read it)
- An instruction to explore the codebase to ground its analysis in what
  actually exists
- For a verification round: the remediation delta and the finding list to
  verdict

Each subagent returns markdown findings under a self-identifying header
(e.g., `## Findings — Skeptical User Advocate`). Label each result with
`### Source: [Persona Name]` before synthesis.

**Fallback when native subagents are unavailable:** run the bundled parallel
Codex CLI script. It runs **detached and is polled** — a hard foreground
timeout kills healthy rounds mid-exploration on a large PRD.

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
out_dir="$review_dir/prd-personas-r<N>"   # <N> = Phase A round number
bash "$script_path" start "<prd-path>" "$out_dir"
echo "OUTPUT_DIR=$out_dir"
```

Then poll. Each `wait` call blocks for at most `CODEX_WAIT_SLICE_SECONDS`;
repeat until the state is terminal.

```bash
bash "$script_path" wait "$out_dir"
```

`wait` and `status` print the run's **status file**, which is the only signal
you may use to decide what happened:

```
STATE=running|complete|partial|failed|limit|timeout
PERSONAS_OK=<n>/3
LIMIT_HITS=<n>
```

Act on `STATE` only:

- `running` → call `wait` again.
- `complete` → all three reviewers produced a review. Read all markdown files in
  `$out_dir` and continue the round.
- `partial` → some reviewers produced a review and some did not. Synthesize the
  ones that did, record the round as **partial** in the round record, and note
  the missing reviewer per `references/synthesis-prompt.md` — absence of
  findings from a reviewer that failed is **not** an endorsement.
- `limit` → a Codex usage/rate limit and no usable review. Stop Phase A rounds,
  remediate whatever earlier rounds returned, and surface the blocker. A
  non-zero `LIMIT_HITS` alongside `partial` means the same: do not start
  another Codex round.
- `failed` / `timeout` → **no review happened this round.** An empty review that
  reports success is worse than a crash: the natural next step on a "clean"
  result is to approve, which manufactures false confidence. Never treat it as
  a clean round. Per-persona detail is in each persona's `.status` file.

**Never** decide a run's outcome by grepping the review body or the raw stderr
log for phrases. Review bodies contain repo content the reviewer read, and a
substring match over them has already produced a false "usage limit" abort on a
healthy run. The status file is the contract.

Then run synthesize → gate check → remediate → consistency gate. Loop until the
gate's exit condition is met (a verification round with zero `NOT CONFIRMED` and
zero new Critical/High) or `PHASE_A_SOFT_CAP` is reached. At the cap, apply
"Step 4: Termination".

## Step 3: Phase B — Claude Code tmux loop

Once Phase A exits cleanly, run the Claude Code reviewer in the same loop,
capped at `PHASE_B_SOFT_CAP`.

**Each round, run the interactive Claude Code PRD review through tmux.** Set the
Bash timeout above `CLAUDE_REVIEW_TIMEOUT_SECONDS`.

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
out_path="$review_dir/claude-challenge-review-r<N>.md"   # <N> = Phase B round number
bash "$script_path" \
  "<prd-path>" \
  "$out_path"
echo "OUTPUT_PATH=$out_path"
```

This helper starts a real interactive `claude` session in tmux and sends the
review prompt into that session. It must not use `claude -p`, `--print`, SDK
mode, or stdout piping. It returns only after Claude writes the report, creates
a completion sentinel, **and the report passes structural validation** — a
sentinel over an empty or findings-free report is a failure, not a clean round.
It writes the same `STATE=` status file contract next to the report.

Read the Claude output, then run synthesize → gate check → remediate →
consistency gate. Stop the loop when the gate's exit condition is met or
`PHASE_B_SOFT_CAP` is reached.

**Claude tmux failure** (`STATE=failed`/`timeout`, script missing, malformed
output): this is a **tooling-blocked phase**. A tooling-blocked phase **defers
approval; it never waives it**. Leave the PRD at its pre-approval status, record
the blocker in the report, surface it to the user, and stop. Model diversity is
load-bearing — the cross-model phase has repeatedly surfaced a class of finding
the in-thread persona reviewers read past for many rounds — so Phase B is never
the phase that gets dropped to save budget or to get to green. If rounds must be
cut, cut Phase A rounds.

## Step 4: Termination

Apply this rule when a phase reaches its soft cap, and at the end of Phase B.

Caps are **usage guards, not quality judgments**. A cap being reached is not
itself a finding. But "loop forever" is not acceptable either, so:

1. **Convergence extension.** If the trend says *converging* and the next round
   would be a **method change** (consistency-only pass or verification round —
   not another discovery round), you may run up to `CONVERGENCE_EXTENSION`
   further rounds in that phase. Discovery rounds are never eligible. Record
   that you used it.
2. Then, unconditionally, classify the residue:
   - **Zero Critical/High** → **Approved**.
   - **Residue is `CONSISTENCY` class only** → **Approved-with-open-items**.
     List the residue in the PRD's "Known open items — read first" section.
   - **Any `SUBSTANTIVE` residue** → **stop and escalate to the user.** Do not
     loop, do not approve, do not set the PRD to Approved.

### Finalize

1. **Write the full report** from your running record to the reserved path,
   following the report format in `references/synthesis-prompt.md`: per phase,
   the rounds run and their types, each round's findings by severity and class,
   the severity trend, PRD growth per round, the consistency gate counters, the
   remediation applied, the Decision Register additions, and the residual items
   left intentionally. Number findings once, globally. It must be
   self-contained — readable without the chat context.
2. **If the outcome is Approved-with-open-items**, add or update the PRD's
   **"Known open items — read first"** section using the template in
   `references/prd-structure-rules.md`. It goes at the **top** of the PRD and is
   written for the zero-context implementing agent: what is unresolved, what the
   risk is, what decision is owed and by whom.
3. **If the outcome is escalate**, surface the residual `SUBSTANTIVE` findings
   to the user with the report link, leave the PRD's status unchanged, and stop.
4. **If the outcome is Approved or Approved-with-open-items**, set the PRD's
   Status field (`Approved` / `Approved with open items`), save, and commit:
   `git add <prd-path> && git commit -m "docs: approve PRD after challenge round for <feature>"`
5. Present a **TTS-friendly chat summary** (do NOT paste the full report) that
   states the ACTUAL outcome — fill the placeholders from what really happened;
   do not assert convergence if a phase hit its soft cap or residue remains:

```
Challenge round complete. Full report:
<GoGrip link>

**Phase A (Codex):** N rounds — <converged | hit the soft cap with X Critical, Y High remaining>.
**Phase B (Claude Code tmux):** M rounds <| blocked, approval deferred | not run>.

Severity trend: <R1 aC/bH → ... → Rn 0C/0H>.
Remediated A Critical, B High, and C curated Medium/Low findings in the PRD.
Deferred D Medium/Low (see report). <PRD set to Status: Approved and committed. Ready for drk-03-qa-runbook-gen. | Approved with open items — N listed at the top of the PRD. | Residual substantive findings remain — your call on how to proceed.>
```

## Common Mistakes

- **Accepting an empty review as a clean round.** A round whose reviewer
  produced nothing is a *failed* round, not a passing one. Check `STATE`, not
  the exit code.
- **Deciding anything by grepping review text.** Limits, failures and
  completion all come from the status file.
- **Reusing a fixed scratch path.** Every run gets its own `REVIEW_ROOT`, and
  every round its own subdirectory.
- **Running Phase A and Phase B together / in parallel.** They are sequential.
- **Stopping after one round.** Each phase loops; re-review after every
  remediation pass.
- **Skipping the consistency gate after remediation.** Most of the next round's
  Critical/High will otherwise be drift your own fix created.
- **Approving off a restructure.** Any structural or consistency-only pass is
  followed by a verification round.
- **Letting a consistency-only pass change requirements.** Its charter is
  binding; a substantive gap it finds is *recorded*, not fixed.
- **Approving because the cross-model phase could not run.** A tooling-blocked
  phase defers approval; it never waives it.
- **Using `claude -p` for Phase B.** Do not use non-interactive Claude mode.
  Start interactive Claude Code in tmux and wait for the completion sentinel.
- **Handing Critical/High findings to the user to fix.** Remediation is
  autonomous.

## Notes

- **Reference file resolution**: `references/*.md` are relative to the skill
  directory. Look in
  `${CODEX_SKILLS_HOME:-${CODEX_HOME:-$HOME/.codex}/skills}/drk-02-prd-challenge/references/`
  (global) or the repo's `codex-skills/drk-02-prd-challenge/references/`
  directory. If not found, stop and report the error.
- **Reference files**: `personas.md` (persona prompts, output contract,
  verification mode), `synthesis-prompt.md` (synthesis rules and report format),
  `consistency-pass.md` (the post-remediation gate and the consistency-only pass
  charter), `prd-structure-rules.md` (authoring rules the remediator applies to
  the PRD), `rationale.md` (why these rules exist).
- Personas are gap-finders, not scope-expanders. They should never suggest new
  features.
- The Claude Code tmux review provides a cross-model second pass. It may catch
  blind spots the in-thread Codex persona subagents share.
- Scratch outputs go to `REVIEW_ROOT` under /tmp/, with the path recorded in
  `RUN_DIR_POINTER`. The generated report lives in the gitignored
  `.dark-factory/reviews/` directory.
