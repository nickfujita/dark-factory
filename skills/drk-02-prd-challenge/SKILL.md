---
name: drk-02-prd-challenge
description: "Multi-model PRD challenge round: Claude persona reviewers then Codex, with autonomous PRD remediation, consistency gates and a delta verification after every remediation. Use after a PRD passes its quality gate, when the user wants stress-testing of requirements, or when asked to 'challenge this PRD'."
---

# PRD Challenge Round

Stress-test a hardened PRD in two sequential review-and-remediation phases.
**Phase A** runs three Claude personas in a fix-and-re-review loop. **Phase B**
runs a Codex review in a capped loop for model diversity. The PRD is remediated
**autonomously between every round** — the author is not asked to hand-fix
findings.

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
| `DISCOVERY_TIER` | **unpinned — inherit from the orchestrator session** (pass no `model`, no `subagent_type` override) | Phase A discovery reviewers |
| `RECHECK_TIER` | `subagent_type: drk-reviewer-recheck` (agent definition pins `model: opus`, `effort: high`) | Phase A downgraded rechecks |
| `RECHECK_TIER_FLOOR` | **never below Opus-class at effort `high`** | binding floor on `RECHECK_TIER` |
| `REVIEW_ROOT` | `${TMPDIR:-/tmp}/dark-factory-prd-<repo-key>-<run-id>` | all scratch output for one run |
| `RUN_DIR_POINTER` | `.dark-factory/tmp/prd-challenge-review-dir` | file recording `REVIEW_ROOT` |
| `REPORT_DIR` | `.dark-factory/reviews/prd-challenge/` | the final report |
| `CODEX_REASONING_EFFORT` | `xhigh` | Codex reviewer |
| `CODEX_WINDOW_SECONDS` | `3600` | total detached window for one Codex round |
| `CODEX_WAIT_SLICE_SECONDS` | `480` | one foreground poll slice (keeps each Bash call under the harness cap) |
| `CODEX_POLL_SECONDS` | `20` | poll interval inside a slice |
| `CODEX_MIN_BODY_BYTES` | `400` | minimum accepted review body when findings are claimed |
| `GROWTH_WARN_ROUND_PCT` | `15` | per-round PRD word-count growth that must be flagged |
| `GROWTH_WARN_TOTAL_PCT` | `50` | cumulative PRD word-count growth that must be flagged |
| `SELF_FEEDING_THRESHOLD` | `50%` | share of a round's new Critical/High living in prose the previous remediation added, above which the loop must change method |

`CODEX_WINDOW_SECONDS`, `CODEX_WAIT_SLICE_SECONDS`, `CODEX_POLL_SECONDS` and
`CODEX_MIN_BODY_BYTES` are also the defaults compiled into
`scripts/run_codex_prd_review.sh`; override them there via the environment
variables the script documents, never by editing call sites.

Two further environment variables are not tunables but **per-round switches** on
that script, set on the invocation that starts a round (Step 3):

| Variable | Values | Meaning |
|---|---|---|
| `CODEX_REVIEW_MODE` | `discovery` (default) / `verification` | which prompt the round runs |
| `CODEX_REVIEW_DELTA_FILE` | path | the remediation delta; **required** when the mode is `verification` |

The mode a round actually ran in comes back as `MODE=` in its status file. A
Phase B round that you intended as a verification and that reports
`MODE=discovery` did not verify anything.

## Prerequisites

- A PRD file that has passed the quality gate (Status: Hardened)
- Codex CLI installed and authenticated (`codex --version` succeeds)
- The `drk-reviewer-recheck` agent definition installed (see
  `agents/drk-reviewer-recheck.md` in the dark-factory repo, synced to
  `~/.claude/agents/`). If it is missing, run Phase A rechecks at
  `DISCOVERY_TIER` and note the substitution in the report — never silently
  drop below `RECHECK_TIER_FLOOR`.

## Step 1: Open the run

Ask the user to confirm the PRD path. If the PRD status is still "Draft", warn
that it should pass the quality gate first (but do not block — the user may
override).

Derive the feature slug from the PRD filename (e.g., `prd-user-auth.md` →
`user-auth`). Reserve the report path now; you assemble and write the full
report once, at finalize (Step 4). Across rounds keep a **running record** of
each round (see "The round record" below) — do not append to the report file
each round (that would duplicate the document header).

Create a **run-scoped** scratch directory. Never write review output to a fixed
shared path: concurrent challenge runs on the same machine will clobber each
other and destroy a completed review.

```bash
mkdir -p .dark-factory/reviews/prd-challenge .dark-factory/tmp
repo_key="$(git rev-parse --show-toplevel 2>/dev/null | sha1sum | cut -c1-12)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
review_dir="${TMPDIR:-/tmp}/dark-factory-prd-${repo_key}-${run_id}"
mkdir -p "$review_dir"
printf '%s\n' "$review_dir" > .dark-factory/tmp/prd-challenge-review-dir
echo "REVIEW_ROOT=$review_dir"
sha256sum "<prd-path>" | cut -d' ' -f1   # baseline PRD hash
wc -w "<prd-path>"                       # baseline word count
```

Report path: `REPORT_DIR/<timestamp>-<feature>-prd-challenge.md` where
`<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

**Adopt an orphaned review (merge, do not stack).** Before round 1, check
`REVIEW_ROOT`'s siblings and any review output the user points you at for a
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
   parallel in a single message. Record the PRD sha256 the round reviewed.
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
3. **Gate check** — see "The trend-aware gate" below.
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
in. Add the PRD diff since the sha256 the round reviewed.

Who verifies:

- **Phase A** — go back to the **same reviewer sub-agent that raised the
  findings**, in its existing thread with its context intact (continue that
  agent rather than spawning a new one; a fresh Agent call starts an empty
  thread). Send it the verification block from `references/personas.md` § "Mode:
  delta verification", scoped to the findings *it* raised. If a finding was
  raised by more than one persona, every raiser verdicts it, and one
  `NOT CONFIRMED` makes it `NOT CONFIRMED`. If the thread cannot be resumed,
  spawn a fresh reviewer with the same block plus the original finding text
  verbatim, and record the substitution in the round record.
- **Phase B** — a fresh process, which is inherent to the Codex path and is a
  **feature** there: a reviewer with no memory of raising the finding cannot
  rubber-stamp its own fix. Because it has no memory, the delta file must carry
  everything it needs. See Step 3 for the invocation.

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
- per reviewer: name and **the tier it ran at** (`DISCOVERY_TIER` /
  `RECHECK_TIER`) and its scope (full document / changed sections)
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
  resume discovery. More rounds of the same kind do not converge a self-feeding
  loop.

A round in which any reviewer failed to produce a review is a **partial** round.
A partial round can never satisfy a phase's exit condition — the reviewer that
would have objected may be exactly the one that failed.

Record the trend and which branch you took in the round record. The trend is
decision-grade information — it belongs in the report, not just in your head.

## Step 2: Phase A — Claude persona loop

Read `references/personas.md` for the 3 persona system prompts, the shared
output contract, and the delta-verification and recheck-scope modes.

**Each round, dispatch all 3 Claude personas as parallel sub-agents** (all 3
Agent calls in one message). Each sub-agent receives:

- Its persona system prompt from `references/personas.md`
- The shared output contract from `references/personas.md` (severity **and**
  `Class:` on every finding)
- The full PRD content inline (or, if the PRD exceeds ~4000 words, the file
  path with an instruction to read it)
- An instruction to explore the codebase to ground its analysis in what
  actually exists
- For a recheck (below): the list of sections changed since that persona's last
  pass

Each sub-agent returns markdown findings under a self-identifying header
(e.g., `## Findings — Skeptical User Advocate`). Label each result with
`### Source: [Persona Name]` before synthesis.

**Keep each persona's sub-agent thread addressable for the rest of the phase.**
Record the identifier the harness gives you for each dispatched reviewer in the
round record: the delta verification after this round's remediation goes back to
those same threads, and a new dispatch would arrive with no memory of the
finding it is being asked to check.

### Reviewer tiering

**No persona is ever skipped.** A persona that came back clean is the only
regression net over the churn the previous remediation just created, and that
churn is where the next round's defects come from. Downgrade it; do not drop
it.

Per persona, per round:

| Its previous round | Tier this round | Scope this round |
|---|---|---|
| returned ≥1 Critical or High | `DISCOVERY_TIER` | full document |
| returned zero Critical/High | `RECHECK_TIER` | sections changed since that persona's last pass, plus its standing focus areas |
| n/a (round 1, or the first discovery round after a structural pass) | `DISCOVERY_TIER` | full document |

A delta verification runs at the tier that persona ran at when it raised the
findings — it is the same thread continuing, not a new dispatch, so tier and
scope are already fixed.

**Promotion valve:** if a `RECHECK_TIER` run surfaces any Critical or High, that
persona returns to `DISCOVERY_TIER` at full-document scope for the next round.

Dispatch mechanics:

- `DISCOVERY_TIER` reviewers are spawned with **no `model` and no
  `subagent_type` override** so they inherit the orchestrator session's model
  and effort. The operator controls that tier from above; do not pin it here.
- `RECHECK_TIER` reviewers are spawned with
  `subagent_type: drk-reviewer-recheck`. Reasoning effort **cannot** be set
  per-spawn on the Agent tool — only `model` can — so the effort is carried by
  that agent definition's frontmatter. Passing a per-invocation `model` would
  override the definition's model while effort stays locked to frontmatter;
  that is the intended behaviour, so **do not pass `model`** and let both come
  from the definition.
- `RECHECK_TIER_FLOOR` is binding. If the agent definition is unavailable or a
  future model substitution would put the recheck below the floor, run the
  recheck at `DISCOVERY_TIER` instead and note it in the report.

Report the tier and scope each persona ran at, every round (see "The round
record").

### Phase A exit

Loop until the exit condition in "The trend-aware gate" is met, or
`PHASE_A_SOFT_CAP` is reached. At the cap, apply "Step 4: Termination" —
reaching the cap in Phase A never approves a PRD.

## Step 3: Phase B — Codex loop

Once Phase A exits cleanly, run the Codex reviewer in the same loop, capped at
`PHASE_B_SOFT_CAP`.

Codex runs **detached with a wide window and is polled** — a hard foreground
timeout kills healthy rounds mid-exploration on a large PRD. Start it, then
poll in slices:

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

review_dir="<REVIEW_ROOT from Step 1>"
out_path="$review_dir/codex-challenge-review-r<N>.md"   # <N> = Phase B round number
bash "$script_path" start "<prd-path>" "$out_path"
echo "OUTPUT_PATH=$out_path"
```

Then poll. Each `wait` call blocks for at most `CODEX_WAIT_SLICE_SECONDS`, so a
single Bash call stays under the harness timeout; repeat until the state is
terminal or the run exceeds `CODEX_WINDOW_SECONDS` (the script enforces the
window and reports `timeout`).

```bash
bash "$script_path" wait "$out_path"
```

`wait` and `status` print the run's **status file**, which is the only signal
you may use to decide what happened:

```
STATE=running|complete|failed|limit|timeout
MODE=discovery|verification
EXIT=<codex exit code>
BODY_BYTES=<n>
FINDINGS=<n>
```

Act on `STATE` only:

- `running` → call `wait` again.
- `complete` → read the review at `$out_path` and continue the round loop.
  Check `MODE=` matches the mode you started the round in.
- `limit` → Codex hit a usage/rate limit. Handle per "Codex usage limit" below.
- `failed` → the run exited non-zero for some other reason, **or produced an
  empty or structurally invalid review**. Treat `failed` as *no review happened
  this round* — never as a clean round (`references/rationale.md`
  § "Harness correctness"). Proceed per "Codex failure that is not a usage
  limit".
- `timeout` → the window elapsed. Same handling as `failed`.

**Never** decide a run's outcome by grepping the review body or the raw stderr
log for phrases — the status file is the contract
(`references/rationale.md` § "Harness correctness").

Read the Codex output, then run synthesize → gate check → remediate →
consistency gate → delta verification. Stop the loop when the gate's exit
condition is met or `PHASE_B_SOFT_CAP` is reached, whichever comes first.

### The Phase B delta verification

The verification after each Phase B remediation is the same script in
verification mode. Write the delta to `REVIEW_ROOT` first, then:

```bash
delta_path="$review_dir/codex-delta-r<N>.md"     # you write this file
out_path="$review_dir/codex-verification-r<N>.md"
CODEX_REVIEW_MODE=verification \
CODEX_REVIEW_DELTA_FILE="$delta_path" \
  bash "$script_path" start "<prd-path>" "$out_path"
bash "$script_path" wait "$out_path"             # poll in slices as above
```

`start` refuses to run without an existing delta file in this mode. Confirm the
status file reports `MODE=verification` before reading the verdicts: a round
that ran in discovery mode verified nothing, whatever its findings look like.

The delta file is the whole context this reviewer gets — it is a fresh process
with no memory of raising the findings. That independence is a **feature** here
(it cannot rubber-stamp a fix to its own finding), but it means the file must
carry, per item: the finding as raised, the disposition and its reasoning, the
edit made and where, plus the PRD diff.

Read the result per "The delta verification" above.

**A crashed or timed-out round is retried once.** On `STATE=failed`/`timeout`,
re-run the round at a **fresh out-path** — up to `TOOLING_RETRY_LIMIT` retries —
before concluding anything. A single transient crash is not a blocked phase.
Record the retry in the round record.

**Codex usage limit (`STATE=limit`):** a usage limit is a **recoverable**
tooling block, and therefore defers approval exactly like any other. Stop
Phase B immediately — do not start another Codex round, and do not retry.

- **Salvage the paid-for signal.** The assembled out-file holds only the failure
  banner; the banner points at the raw `<out-path>.body.md`, which may contain
  findings the run produced before it was cut off. Read it, and remediate any
  Critical/High under the normal rules. That delta cannot be verified — the
  reviewer that would verify it is the one that is unavailable — so record it in
  the report as an **unverified delta**.
- **Then stop.** Leave the PRD at its pre-approval status, record the blocker and
  how many Phase B rounds actually completed, and surface it to the user. A
  usage limit is a budget event, and the diversity rule below applies to it.

**Codex failure that is NOT a usage limit** (`STATE=failed`/`timeout` after
`TOOLING_RETRY_LIMIT` retries, script missing, malformed output): this is a
**tooling-blocked phase**. A tooling-blocked phase **defers approval; it never
waives it**. Leave the PRD at its pre-approval status, record the blocker in the
report, surface it to the user, and stop. Model diversity is load-bearing — if
rounds must be cut, cut Phase A rounds, never this phase.

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
   phase. Discovery rounds are never eligible for the extension. Record that you
   used it.
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
   the tier each reviewer ran at, the severity trend, PRD growth per round, the
   consistency gate counters, the remediation applied, the Decision Register
   additions, and the residual items left intentionally. Number findings once,
   globally. It must be self-contained — readable without the chat context.
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

**Phase A (Claude):** N rounds — <converged | hit the soft cap with X Critical, Y High remaining>.
**Phase B (Codex):** M rounds <| stopped early on a usage limit, approval deferred | blocked, approval deferred | not run>.

Severity trend: <R1 aC/bH → ... → Rn 0C/0H>.
Remediated A Critical, B High, and C curated Medium/Low findings in the PRD.
Deferred D Medium/Low (see report). <PRD set to Status: Approved and committed. Ready for drk-03-qa-runbook-gen. | Approved with open items — N listed at the top of the PRD. | Residual substantive findings remain — your call on how to proceed.>
```

## Common Mistakes

- **Accepting an empty review as a clean round.** A round whose reviewer
  produced nothing is a *failed* round, not a passing one. Check `STATE`, not
  the exit code.
- **Deciding anything by grepping review text.** Limits, failures and
  completion all come from the status file. Review bodies contain repo content
  and will match anything.
- **Reusing a fixed scratch path.** Every run gets its own `REVIEW_ROOT`;
  concurrent runs otherwise destroy each other's output.
- **Running Phase A and Phase B together / in parallel.** They are sequential.
- **Stopping after one round.** Each phase loops; re-review after every
  remediation pass.
- **Skipping the consistency gate after remediation.** Most of the next round's
  Critical/High will otherwise be drift your own fix created.
- **Skipping a persona because it came back clean.** Downgrade to
  `RECHECK_TIER`; never skip.
- **Pinning the discovery tier.** `DISCOVERY_TIER` is inherited on purpose.
- **Approving off an unverified change.** Every remediation, restructure and
  consistency-only pass is verified against its own delta before the next round.
- **Letting a consistency-only pass change requirements.** Its charter is
  binding; a substantive gap it finds is *recorded*, not fixed.
- **Approving at a Phase A cap.** Phase A ending never approves anything; the
  run-level outcome exists only after Phase B.
- **Approving because Codex could not run.** A tooling-blocked phase defers
  approval; it never waives it. A usage limit is a tooling block.
- **Running a Phase B verification in discovery mode.** Set
  `CODEX_REVIEW_MODE=verification` and `CODEX_REVIEW_DELTA_FILE`, and check
  `MODE=` in the status file.
- **Applying a reviewer's suggested fix without checking it.** The finding is
  evidence, the fix is a proposal; verify both and record your disposition.
- **Verifying a fix in a fresh reviewer thread when the original one exists.**
  Continue the thread that raised the finding — a new one has no idea what it is
  checking.
- **Handing Critical/High findings to the user to fix.** Remediation is
  autonomous.

## Notes

- **Reference file resolution**: `references/*.md` are relative to the skill
  directory. Look in `$HOME/.claude/skills/drk-02-prd-challenge/references/`
  (global) or the repo's `skills/drk-02-prd-challenge/references/` directory.
  If not found, stop and report the error.
- **Reference files**: `personas.md` (persona prompts, output contract,
  delta-verification and recheck modes), `synthesis-prompt.md` (synthesis rules
  and report format), `consistency-pass.md` (the post-remediation gate and the
  consistency-only pass charter), `prd-structure-rules.md` (the remediator's
  judgment mandate and the authoring rules it applies to the PRD),
  `rationale.md` (why these rules exist).
- Personas are gap-finders, not scope-expanders. They should never suggest new
  features.
- Codex provides model diversity (GPT vs Claude). It may catch blind spots all
  Claude personas share.
- Scratch (Codex output, status file, stderr log, delta files) goes to
  `REVIEW_ROOT` under /tmp/, never under `.claude/`, so the autonomous loop
  never trips a write-permission prompt; the generated report lives in the
  gitignored `.dark-factory/reviews/` directory.
- **`REVIEW_ROOT` in your own context is authoritative.** `RUN_DIR_POINTER` is a
  convenience for a session that lost it, and a second run in the same checkout
  overwrites it. If the pointer disagrees with the `REVIEW_ROOT` you created in
  Step 1, trust your own and say so in the report.
