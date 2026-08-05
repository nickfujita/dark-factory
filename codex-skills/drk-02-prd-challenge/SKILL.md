---
name: drk-02-prd-challenge
description: "Codex-native PRD challenge round: Codex persona subagents followed by an interactive Claude Code tmux review, with autonomous PRD remediation, consistency gates and a delta verification after every remediation. Use after a PRD passes its quality gate, when the user wants stress-testing of requirements, or when asked to 'challenge this PRD'."
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
| `VERIFY_RETRY_LIMIT` | 2 | remediate → re-verify cycles allowed on one remediation delta before escalating |
| `TOOLING_RETRY_LIMIT` | 1 | retries of a crashed or timed-out reviewer run before the phase is declared tooling-blocked |
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

Further environment variables are not tunables but **per-round switches**, set
on the invocation that starts a round:

| Variable | Values | Applies to |
|---|---|---|
| `CODEX_REVIEW_MODE` | `discovery` (default) / `verification` | `run_codex_persona_reviews.sh` |
| `CODEX_REVIEW_DELTA_FILE` | path | same; **required** when the mode is `verification` |
| `CLAUDE_REVIEW_MODE` | `discovery` (default) / `verification` | `run_claude_prd_review_tmux.sh` |
| `CLAUDE_REVIEW_DELTA_FILE` | path | same; **required** when the mode is `verification` |

The mode a round actually ran in comes back as `MODE=` in its status file. A
round you intended as a verification that reports `MODE=discovery` verified
nothing.

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

Three pass types exist; they have different charters and are not
interchangeable. A **round** is a discovery round or a consistency-only pass,
and the running record declares which. A delta verification is not a round of
its own — it belongs to the change it checks (see below).

| Type | Scope | Reviewer mode | May the remediator change requirements? |
|---|---|---|---|
| **Discovery round** | the whole PRD | discovery (default persona prompts) | yes |
| **Delta verification** | the remediation just applied | verification (per-finding `CONFIRMED`/`NOT CONFIRMED`, plus a sweep for newly introduced problems) | yes, for `NOT CONFIRMED` items and newly surfaced problems only |
| **Consistency-only pass** | cross-reference, terminology, table and value integrity | n/a — the orchestrator performs it | **no** — charter in `references/consistency-pass.md` is binding |

**Every change to the PRD is verified against the delta it produced, before the
next review round starts.** That applies to a remediation pass, a
consistency-only pass, and any other structural or consolidation pass. Never
approve a PRD off an unverified change.

A delta verification belongs to the change it checks: it is part of that round
and **does not consume an extra round** against the soft cap. A consistency-only
pass is a round of its own, and gets its own delta verification like any other
change.

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
4. **Remediate autonomously** — do NOT hand findings to the user to fix. Every
   finding first goes through the **remediator's judgment mandate**
   (`references/prd-structure-rules.md` § 1): a reviewer's finding is evidence
   and its suggested fix is a proposal — neither is an instruction — and every
   disposition is recorded. Then **edit the PRD** for each finding you accept.
   Every round you address:
   - **All Critical findings**
   - **All High findings**
   - A **curated selection of Medium/Low findings** — the ones your judgment
     says genuinely strengthen the PRD; skip noise.

   Every declined or deferred finding gets a Decision Register row
   (`references/prd-structure-rules.md` § "Decision Register" is the normative
   rule for what the register records).

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
6. **Delta verification (mandatory)** — see below. The round is not finished
   until the remediation you just applied has been verified.

The phases are **sequential, not parallel**: Phase A must reach its exit
condition before Phase B begins.

### The delta verification

**Every remediation is immediately followed by a verification of exactly what it
changed.** If you changed nothing this round, there is no delta and no
verification.

Assemble the delta first — the verifier is judging your edits, so it needs, per
finding: the finding as originally raised (id, title, severity, class), the
disposition you chose and why, and the edit you made with the location it landed
in. Add the PRD diff since the sha256 the round reviewed. Write it to
`REVIEW_ROOT` as a file; both runners take it by path.

Who verifies:

- **Phase A** — go back to the **same persona subagent that raised the
  findings**, in its existing thread, if your harness can continue a subagent
  with its context intact. Send it the verification block from
  `references/personas.md` § "Mode: delta verification", scoped to the findings
  *it* raised. If a finding was raised by more than one persona, every raiser
  verdicts it, and one `NOT CONFIRMED` makes it `NOT CONFIRMED`. If threads
  cannot be continued — including on the CLI fallback path, which is always a
  fresh process — supply the delta file instead and record the substitution in
  the round record.
- **Phase B** — a fresh Claude Code session, which is inherent to the tmux path
  and is a **feature** there: a reviewer with no memory of raising the finding
  cannot rubber-stamp its own fix. Because it has no memory, the delta file must
  carry everything it needs.

Reading the result:

- **All listed findings `CONFIRMED`, and nothing new surfaced** → the round is
  complete. Continue to the next round (or exit the phase, per the gate).
- **Any `NOT CONFIRMED`, or a newly surfaced problem** → remediate those items
  under the normal rules (a `NOT CONFIRMED` verdict is a finding, not an order —
  the judgment mandate applies to it too), re-run the consistency gate, and
  **verify the new delta**. At most `VERIFY_RETRY_LIMIT` such cycles on one
  remediation; if the delta still does not come back clean, **stop and escalate
  to the user** with the outstanding verdicts. Do not approve, and do not paper
  over it with another discovery round.
- **The verification surfaced new Critical or High findings** → the phase has
  not converged. The next round is a discovery round (or a method change, per
  the trend), whatever the previous round's counts said.

A remediation whose delta was never verified — because the reviewer was
unavailable, or the run stopped — can never support an approval outcome.

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
- the **disposition of every finding** (applied as proposed / applied, modified
  / declined / deferred) with its one-line reasoning
- remediation applied, and the consistency gate counters
- the delta verification: who verified, the `CONFIRMED` / `NOT CONFIRMED` tally,
  anything it newly surfaced, and how many re-verify cycles it took

### The trend-aware gate

Count this round's Critical and High findings, then:

- **A discovery round with zero Critical AND zero High → the phase is done.**
  Apply any curated Medium/Low you chose to fix, run the consistency gate,
  verify that delta, and exit the phase. Do not run an extra round to confirm:
  a clean discovery round has already read the whole document *including* the
  last remediation, and that remediation was verified when it was made.
- **Any other round with zero Critical/High** (a clean delta verification, a
  consistency-only pass) does **not** exit the phase — only a discovery round
  can. Continue the loop.
- **Otherwise** → remediate, run the consistency gate, verify the delta, and
  start a new round — but first read the trend.

Maintain a severity trend line in the running record, e.g.
`R1 3C/7H → R2 3C/15H → R3 2C/10H → R4 1C/5H → R5 0C/4H`. Then:

- **Converging** (Critical+High strictly declining across the last two rounds,
  and the class mix shifting toward `CONSISTENCY`) → another round of the same
  type is justified.
- **Self-feeding** (at least `SELF_FEEDING_THRESHOLD` of this round's new
  Critical/High live in prose the previous round's remediation added, **or**
  Critical+High is flat or rising across two consecutive rounds) → **change
  method, do not run another discovery round.** Run a consistency-only pass
  (which, like every change, is followed by its own delta verification), then
  resume discovery.

A round in which any reviewer failed to produce a review is a **partial** round.
A partial round can never satisfy a phase's exit condition — the reviewer that
would have objected may be exactly the one that failed.

Record the trend and which branch you took in the round record.

## Step 2: Phase A — Codex persona loop

Read `references/personas.md` for the 3 persona system prompts, the shared
output contract, and the delta-verification mode.

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

Each subagent returns markdown findings under a self-identifying header
(e.g., `## Findings — Skeptical User Advocate`). Label each result with
`### Source: [Persona Name]` before synthesis.

**Keep each persona's subagent addressable for the rest of the phase** if your
harness can continue a subagent thread: the delta verification after this
round's remediation goes back to the same reviewer, which is the one that knows
what its finding meant. Record the identifier in the round record. On the CLI
fallback path below, every round is a fresh process and the delta file carries
the context instead.

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

review_dir="<REVIEW_ROOT from Step 1>"
out_dir="$review_dir/prd-personas-r<N>"   # <N> = Phase A round number
bash "$script_path" start "<prd-path>" "$out_dir"
echo "OUTPUT_DIR=$out_dir"
```

Then poll. Each `wait` call blocks for at most `CODEX_WAIT_SLICE_SECONDS`;
repeat until the state is terminal.

```bash
bash "$script_path" wait "$out_dir"
```

The delta verification on this path is the same script in verification mode,
with the delta supplied by file because the process is fresh:

```bash
delta_path="$review_dir/phase-a-delta-r<N>.md"     # you write this file
out_dir="$review_dir/prd-personas-verify-r<N>"
CODEX_REVIEW_MODE=verification \
CODEX_REVIEW_DELTA_FILE="$delta_path" \
  bash "$script_path" start "<prd-path>" "$out_dir"
bash "$script_path" wait "$out_dir"
```

`start` refuses to run without an existing delta file in this mode.

`wait` and `status` print the run's **status file**, which is the only signal
you may use to decide what happened:

```
STATE=running|complete|partial|failed|limit|timeout
MODE=discovery|verification
PERSONAS_OK=<n>/3
LIMIT_HITS=<n>
```

Act on `STATE` only:

- `running` → call `wait` again.
- `complete` → all three reviewers produced a review. Read all markdown files in
  `$out_dir` and continue the round. Check `MODE=` matches the mode you started
  the round in.
- `partial` → some reviewers produced a review and some did not. Synthesize the
  ones that did, record the round as **partial** in the round record, and note
  the missing reviewer per `references/synthesis-prompt.md` — absence of
  findings from a reviewer that failed is **not** an endorsement. A partial
  round is bound by the rule in "The trend-aware gate".
- `limit` → a Codex usage/rate limit. This is a **recoverable tooling block**:
  it defers approval, it never waives it. Stop Phase A rounds, salvage any
  findings already on disk (per-persona `.body.md` files) and remediate the
  Critical/High under the normal rules, then **stop and surface the blocker** —
  do not start Phase B and do not approve. A delta remediated here cannot be
  verified, so record it as an **unverified delta**. A non-zero `LIMIT_HITS`
  alongside `partial` means the same: do not start another Codex round.
- `failed` / `timeout` → **no review happened this round.** Never treat it as a
  clean round (`references/rationale.md` § "Harness correctness"). Per-persona
  detail is in each persona's `.status` file. Retry the round once at a fresh
  out-dir — up to `TOOLING_RETRY_LIMIT` — before declaring the phase
  tooling-blocked; a single transient crash is not a blocked phase.

**Never** decide a run's outcome by grepping the review body or the raw stderr
log for phrases — the status file is the contract
(`references/rationale.md` § "Harness correctness").

Then run synthesize → gate check → remediate → consistency gate → delta
verification. Loop until the exit condition in "The trend-aware gate" is met, or
`PHASE_A_SOFT_CAP` is reached. At the cap, apply "Step 4: Termination" —
reaching the cap in Phase A never approves a PRD.

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

review_dir="<REVIEW_ROOT from Step 1>"
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
It writes the same `STATE=`/`MODE=` status file contract next to the report.

The reviewer session is hidden from the Matrix phone bridge. The helper spawns
it with `CCMATRIX_SUPPRESS_SESSION=1`, so it gets no Matrix room, no push
notification and no text-to-speech. Without that, one round of work would put
two live rooms on the operator's phone — one for this orchestrator and one for
the reviewer — and read the reviewer's replies aloud, even though its report is
addressed to this flow and not to a human. The assignment travels inside the
tmux command string on purpose: an exported variable does not reach a pane on
an already-running tmux server. `just test-bridge-suppression` proves both
halves.

### The Phase B delta verification

The verification after each Phase B remediation is the same helper in
verification mode. Write the delta to `REVIEW_ROOT` first, then:

```bash
delta_path="$review_dir/claude-delta-r<N>.md"     # you write this file
out_path="$review_dir/claude-verification-r<N>.md"
CLAUDE_REVIEW_MODE=verification \
CLAUDE_REVIEW_DELTA_FILE="$delta_path" \
  bash "$script_path" "<prd-path>" "$out_path"
```

The helper refuses to run without an existing delta file in this mode, and the
status file reports `MODE=verification`. Each round is a fresh Claude session
with no memory of raising the findings — that independence is a **feature**
here, but it means the delta file must carry, per item: the finding as raised,
the disposition and its reasoning, the edit made and where, plus the PRD diff.

Read the Claude output, then run synthesize → gate check → remediate →
consistency gate → delta verification. Stop the loop when the gate's exit
condition is met or `PHASE_B_SOFT_CAP` is reached.

**A crashed or timed-out round is retried once.** On `STATE=failed`/`timeout`,
re-run at a fresh out-path — up to `TOOLING_RETRY_LIMIT` retries — before
concluding anything, and record the retry.

**Claude tmux failure** (`STATE=failed`/`timeout` after those retries, script
missing, malformed output): this is a **tooling-blocked phase**. A
tooling-blocked phase **defers approval; it never waives it**. Leave the PRD at
its pre-approval status, record the blocker in the report, surface it to the
user, and stop. Model diversity is load-bearing — if rounds must be cut, cut
Phase A rounds, never this phase.

## Step 4: Termination

Apply this rule when a phase reaches its soft cap, and at the end of Phase B.
**The run-level outcome is decided only at the end of Phase B.** Phase A
reaching its cap ends a *phase*; it can never produce an approval and never
enters Finalize.

Caps are **usage guards, not quality judgments**. A cap being reached is not
itself a finding. But "loop forever" is not acceptable either, so:

1. **Convergence extension.** If the trend says *converging* and the next round
   would be a **method change** (a consistency-only pass — not another discovery
   round), you may run up to `CONVERGENCE_EXTENSION` further rounds in that
   phase. Discovery rounds are never eligible. Record that you used it.
2. Then classify the residue — **and which cap you are at decides what the
   classification means:**

**At `PHASE_A_SOFT_CAP`:**

- **Zero Critical/High**, or **`CONSISTENCY`-class residue only** → Phase A
  ends. Carry the residue into Phase B's running record and **start Phase B**.
  Record that Phase A ended at its cap rather than at its exit condition.
- **Any `SUBSTANTIVE` residue** → **stop and escalate to the user.** Do not
  start Phase B, do not approve.

**At the end of Phase B** (its exit condition, or `PHASE_B_SOFT_CAP`):

- **Zero Critical/High** → **Approved**.
- **Residue is `CONSISTENCY` class only** → **Approved with open items**. List
  the residue in the PRD's "Known open items — read first" section.
- **Any `SUBSTANTIVE` residue** → **stop and escalate to the user.** Do not
  loop, do not approve, do not set the PRD to Approved.

**Preconditions on any approval outcome.** Both must hold. If either fails, the
outcome is *defer, surface and stop* — never an approval:

- Phase B ran and produced **at least one completed cross-model round** this
  run. A phase that was tooling-blocked, usage-limited, or skipped defers
  approval; it never waives it.
- **Every remediation applied in this run has a delta verification that came
  back clean.** An unverified delta cannot be approved over, and residue whose
  class was `(inferred)` rather than reviewer-emitted never justifies approving.

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
3. **If the outcome is escalate or defer**, surface what stopped the run — the
   residual `SUBSTANTIVE` findings, the tooling blocker, or the delta that could
   not be verified — to the user with the report link, leave the PRD's status
   unchanged, and stop.
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
<Phase A stopped on a usage limit — approval deferred.>

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
- **Approving off an unverified change.** Every remediation, restructure and
  consistency-only pass is verified against its own delta before the next round.
- **Letting a consistency-only pass change requirements.** Its charter is
  binding; a substantive gap it finds is *recorded*, not fixed.
- **Approving at a Phase A cap.** Phase A ending never approves anything; the
  run-level outcome exists only after Phase B.
- **Approving because the cross-model phase could not run.** A tooling-blocked
  phase defers approval; it never waives it. A usage limit is a tooling block.
- **Running a verification in discovery mode.** Set `CODEX_REVIEW_MODE` /
  `CLAUDE_REVIEW_MODE` and the matching delta file, and check `MODE=` in the
  status file.
- **Applying a reviewer's suggested fix without checking it.** The finding is
  evidence, the fix is a proposal; verify both and record your disposition.
- **Verifying a fix in a fresh reviewer thread when the original one exists.**
  Continue the thread that raised the finding where the harness allows it.
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
  delta-verification mode), `synthesis-prompt.md` (synthesis rules and report
  format), `consistency-pass.md` (the post-remediation gate and the
  consistency-only pass charter), `prd-structure-rules.md` (the remediator's
  judgment mandate and the authoring rules it applies to the PRD),
  `rationale.md` (why these rules exist).
- Personas are gap-finders, not scope-expanders. They should never suggest new
  features.
- The Claude Code tmux review provides a cross-model second pass. It may catch
  blind spots the in-thread Codex persona subagents share.
- Scratch outputs (reviews, status files, stderr logs, delta files) go to
  `REVIEW_ROOT` under /tmp/. The generated report lives in the gitignored
  `.dark-factory/reviews/` directory.
- **`REVIEW_ROOT` in your own context is authoritative.** `RUN_DIR_POINTER` is a
  convenience for a session that lost it, and a second run in the same checkout
  overwrites it. If the pointer disagrees with the `REVIEW_ROOT` you created in
  Step 1, trust your own and say so in the report.
