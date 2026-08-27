---
name: df-prd-challenge
description: "Stress-test a hardened PRD. Standard runs a single pass, one Claude reviewer plus one Codex reviewer on the same prompt, lead adjudication, one remediation wave, one delta verification. High-consequence runs the hardened persona loop under a single dispatch budget and a hard growth stop. Runs when the df feature playbook reaches its PRD-challenge stage or when the operator invokes it explicitly — never on its own."
disable-model-invocation: true
---

# PRD Challenge Round

Stress-test a hardened PRD. This skill has two modes, and the lane picks which
one runs. The PRD is remediated **autonomously** in both — the author is not
asked to hand-fix findings.

Upstream: `df-prd-interview` produces the Hardened PRD this skill consumes.
Downstream: `df-qa-runbook-gen` consumes the PRD this skill approves.

Rationale, evidence, and the failure modes each rule exists to prevent are in
`references/rationale.md`. This file is instructions only.

## Lane modes

| Lane | Mode | Shape |
|---|---|---|
| Quick | not run | The lane has no PRD. The router's finish predicate is the acceptance. |
| Standard | **single pass** (default) | One Claude reviewer plus one Codex reviewer on the same prompt, no personas. Lead adjudication, one remediation wave, one delta verification of that wave. No rounds. `references/single-pass.md` is the contract. |
| High-consequence | **hardened loop** | The persona loop below, under one dispatch budget and a hard growth stop. |

Read the lane from the run state. Ask the operator only if no lane is
recorded. Standard is the default. **Nothing in this skill escalates its own
lane.** A single pass that wanted a second round reports that to the operator
as a lane question; it does not open one.

## Pinned parameters

**This table is the single source of truth for every tunable in this skill.**
Everywhere else in this skill and its references, parameters are referred to by
name. Do not restate a value inline — if you need the number, read it here.

| Parameter | Value | Applies to |
|---|---|---|
| `DISPATCH_BUDGET` | 12 reviewer dispatches for the whole run | High-consequence. **Everything** consumes it (see "The dispatch budget") |
| `STANDARD_PASS_DISPATCHES` | 4, fixed shape: 2 discovery, 2 delta verification | Standard single pass |
| `SECOND_OPINION_DISPATCHES` | 2, operator-invoked only, once per run | both lanes |
| `GROWTH_HARD_CAP` | **2x** the word count of the PRD as `df-prd-interview` delivered it | both lanes. A stop, never a flag |
| `ANCHOR_STOP_MULTIPLE` | 3x the PRD header's `Effort-Anchor` | both lanes. Projected run cost against the operator's own number |
| `SELF_FEEDING_THRESHOLD` | `50%` | share of a round's new Critical/High living in prose the previous remediation added, at or above which the run terminates as non-converging |
| `VERIFY_RETRY_LIMIT` | 2 | remediate → re-verify cycles allowed on one remediation delta before escalating |
| `TOOLING_RETRY_LIMIT` | 1 | retries of a crashed or timed-out reviewer run before the leg is declared tooling-blocked |
| `DISCOVERY_TIER` | **unpinned — inherit from the orchestrator session** (pass no `model`, no `subagent_type` override) | discovery reviewers, both lanes |
| `RECHECK_TIER` | `subagent_type: df-reviewer-recheck` (agent definition pins `model: opus`, `effort: high`) | High-consequence downgraded rechecks |
| `RECHECK_TIER_FLOOR` | **never below Opus-class at effort `high`** | binding floor on `RECHECK_TIER` |
| `REVIEW_ROOT` | `${TMPDIR:-/tmp}/dark-factory-prd-<repo-key>-<run-id>` | all scratch output for one run |
| `RUN_DIR_POINTER` | `.dark-factory/tmp/prd-challenge-review-dir` | file recording `REVIEW_ROOT` |
| `REPORT_DIR` | `.dark-factory/reviews/prd-challenge/` | the final report |
| `CODEX_REASONING_EFFORT` | `xhigh` in High-consequence, the operator's default in Standard | Codex reviewer |
| `CODEX_WINDOW_SECONDS` | `3600` | total detached window for one Codex leg |
| `CODEX_WAIT_SLICE_SECONDS` | `480` | one foreground poll slice (keeps each Bash call under the harness cap) |
| `CODEX_POLL_SECONDS` | `20` | poll interval inside a slice |
| `CODEX_MIN_BODY_BYTES` | `400` | minimum accepted review body when findings are claimed |

There are no round caps. Round caps were the old brake, and they counted the
wrong thing: real work escaped them by being typed as something other than a
round. `DISPATCH_BUDGET` replaces them, and nothing is exempt from it.

`CODEX_WINDOW_SECONDS`, `CODEX_WAIT_SLICE_SECONDS`, `CODEX_POLL_SECONDS` and
`CODEX_MIN_BODY_BYTES` are also the defaults compiled into
`scripts/run_codex_prd_review.sh`; override them there via the environment
variables the script documents, never by editing call sites.

Two further environment variables are not tunables but **per-leg switches** on
that script, set on the invocation that starts a leg (Step 3):

| Variable | Values | Meaning |
|---|---|---|
| `CODEX_REVIEW_MODE` | `discovery` (default) / `verification` | which prompt the leg runs |
| `CODEX_REVIEW_DELTA_FILE` | path | the remediation delta; **required** when the mode is `verification` |

The mode a leg actually ran in comes back as `MODE=` in its status file. A leg
that you intended as a verification and that reports `MODE=discovery` did not
verify anything.

## Prerequisites

- A PRD file that has passed the quality gate (Status: Hardened)
- Codex CLI installed and authenticated (`codex --version` succeeds)
- An open df run in the run-state store, or the standing to open one
- High-consequence only: the `df-reviewer-recheck` agent definition installed
  (see `agents/df-reviewer-recheck.md` in the dark-factory repo, synced to
  `~/.claude/agents/`). If it is missing, run rechecks at `DISCOVERY_TIER` and
  note the substitution in the report — never silently drop below
  `RECHECK_TIER_FLOOR`.

## Step 1: Open the run

Ask the user to confirm the PRD path. If the PRD status is still "Draft", warn
that it should pass the quality gate first (but do not block — the user may
override).

Derive the feature slug from the PRD filename (e.g., `prd-user-auth.md` →
`user-auth`). Reserve the report path now; you assemble and write the full
report once, at finalize (Step 5). Across the run keep a **running record**
(see "The round record" below) — do not append to the report file each round
(that would duplicate the document header).

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

**Record the baseline word count.** It is the interview's output, and
`GROWTH_HARD_CAP` is measured against it for the rest of the run. Record the
PRD header's `Effort-Anchor` alongside it.

Report path: `REPORT_DIR/<timestamp>-<feature>-prd-challenge.md` where
`<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC).

**Adopt an orphaned review (merge, do not stack).** Before the first pass, check
`REVIEW_ROOT`'s siblings and any review output the user points you at for a
completed-but-unsynthesized review of this PRD. If one exists and the PRD
sha256 recorded with it is **byte-identical** to the current PRD's sha256,
merge its findings into the first synthesis as an additional source and label
it as such — do not discard it, and do not spend a dispatch re-running what it
already produced. If the hashes differ, ignore it and say so in the report.

## The dispatch budget

**One budget, and everything consumes it.** Every reviewer dispatch reserves a
seq through `scripts/df-state.sh` **before** it spawns, and the reservation is
spent the moment it lands. There is no spawn-first-log-later path and there are
no exemptions.

Consuming a reservation:

- a discovery reviewer, any tier, any lane
- a delta verification leg, whether it continues an existing thread or spawns
  fresh
- a consistency pass that dispatches a reviewer at all
- a recheck-tier recheck
- a retry after a crashed or timed-out reviewer run
- the operator's second-opinion pass
- anything nested inside any of the above, with `parent_seq` set

Not consuming a reservation, because no reviewer runs: the orchestrator's own
synthesis, adjudication, remediation edits, and the mechanical consistency gate
in `references/consistency-pass.md`.

The old rule that a delta verification "belongs to the round it checks and does
not consume an extra round" is **deleted**. It was the exemption that let a
capped loop run indefinitely. A delta verification is a reviewer dispatch and
it costs one.

```bash
seq=$(bash scripts/df-state.sh reserve "<run-id>" discovery_reviewers "prd challenge discovery, codex leg")
```

A refused reservation (exit 3) means the dispatch does not happen. The store
records `stopped-budget` itself; you do not get to note it and continue.
Budget exhaustion mid-run is a **terminal outcome**, handled in Step 4.

**The anchor check.** Before each dispatch after the first pass, compare the
run's projected cost against the PRD's `Effort-Anchor`. When the projection
exceeds it by `ANCHOR_STOP_MULTIPLE`, stop and ask the operator before
spending more. The anchor is the operator's own number, and this skill never
revises it.

## The growth stop

`GROWTH_HARD_CAP` is a **stop**. The PRD may not exceed twice the word count
the interview delivered. Measure after every remediation, before the next
dispatch.

- At or over the cap: the run **terminates as non-converging** and escalates to
  the operator with the report. It does not get an extension, a final round, or
  a consistency pass to bring it back under. There is no convergence extension
  in this skill; the mechanism was deleted because "converging" is the state a
  self-feeding loop reports about itself.
- A round whose new Critical/High are `SELF_FEEDING_THRESHOLD` or more against
  prose the previous remediation added: same outcome. The loop is finding real
  defects in requirements it invented, and more rounds of any kind do not
  converge that.

Below both thresholds, a flat trend still argues for a **method change** rather
than another discovery round. Run the consistency-only pass, then resume.

**New infrastructure in a remediation escalates to the operator.** A fix that
introduces a queue, a durable object, a key scheme, a watchdog, a new state
machine, or any other mechanism the PRD did not already have is a **scope
decision**, not a wording fix. Stop, state the finding, state the mechanism the
fix would add, and ask. Autonomy covers wording; sign-off covers mechanism.
This is the single rule that would have stopped the 14.6x run: every round's
fixes added mechanism, and the next round found real gaps in the mechanism.

**Model-enumerated exhaustive inventories are banned from PRDs.** Never write,
and never accept a reviewer's request for, a census, manifest, or complete
enumeration produced by reading. If a finding genuinely needs one, the
remediation is a line naming the script that generates it from source. A
generated census is reviewed before use; a written one is hallucination bait,
and one measured run shipped 94 entries with guessed and nonexistent
boundaries.

## Standard lane: the single pass

Read `references/single-pass.md`. It is the contract: the six-step sequence,
the shared rubric both reviewers receive verbatim, the adjudication rules, and
the three terminal outcomes. Nothing in it loops.

Mechanics for this tree:

1. **Reserve two dispatches.** One for the in-session Claude reviewer, one for
   the Codex leg.
2. **Run both in parallel, in a single message.** The Claude reviewer is an
   Agent spawn at `DISCOVERY_TIER` carrying the shared rubric from
   `references/single-pass.md` plus the shared output contract from
   `references/personas.md`. **No persona prompt.** The Codex leg is
   `scripts/run_codex_prd_review.sh` in discovery mode, invoked exactly as
   Step 3 describes; its built-in prompt is the same non-persona rubric.
   Record the PRD sha256 both reviewed, and keep the Claude reviewer's thread
   identifier — its delta verification goes back to that thread.
3. **Synthesize and adjudicate** per `references/synthesis-prompt.md`,
   including its § "Lead adjudication".
4. **Remediate once**, under the judgment mandate
   (`references/prd-structure-rules.md` § 1), the growth stop, and the
   new-infrastructure escalation above.
5. **Run the consistency gate**, then **verify the delta**: two more
   reservations, one leg per family, per "The delta verification" below.
6. **Terminate** per `references/single-pass.md` § "Terminating" and Step 4.

D7, Standard lane: a cross-family leg that is blocked — usage limit, tooling
failure after `TOOLING_RETRY_LIMIT`, or the CLI missing — **degrades with a
logged note**. Continue on the surviving leg, record `deferred: <reason>` for
the blocked one in the run ledger, and say in the report and the chat summary
that the pass ran single-family. Degrading is a stated fact, never a silent
one.

## High-consequence lane: the hardened loop

Everything from here through Step 2 applies to High-consequence only. Step 3's
transport is shared: the Standard pass reaches its cross-family reviewer the
same way.

### Pass types

Three pass types exist; they have different charters and are not
interchangeable. The running record declares which one each pass was.

| Type | Scope | Reviewer mode | May the remediator change requirements? |
|---|---|---|---|
| **Discovery** | the whole PRD | discovery (default persona prompts) | yes |
| **Delta verification** | the remediation just applied | verification (per-finding `CONFIRMED`/`NOT CONFIRMED`, plus a sweep for newly introduced problems) | yes, for `NOT CONFIRMED` items and newly surfaced problems only |
| **Consistency-only** | cross-reference, terminology, table and value integrity | n/a — the orchestrator performs it | **no** — charter in `references/consistency-pass.md` is binding |

**Every change to the PRD is verified against the delta it produced, before the
next discovery pass starts.** That applies to a remediation, a consistency-only
pass, and any other structural or consolidation pass. Never approve a PRD off
an unverified change.

### The loop

One iteration is:

1. **Review** — reserve, then run the phase's reviewers. All reviewers in one
   iteration run in parallel in a single message. Record the PRD sha256 they
   reviewed.
2. **Synthesize** — consolidate into the running record following
   `references/synthesis-prompt.md` (deduplicate, take the highest severity on
   disagreement, tag sources). Every finding carries a severity **and a class**
   (`SUBSTANTIVE` or `CONSISTENCY`) emitted by the reviewer; if a reviewer
   omitted the class, classify it yourself using the definitions in
   `references/synthesis-prompt.md` and mark it as inferred.
   - A finding you already remediated that reappears is a **regression** —
     treat it as new, and record it as a regression.
   - A finding already recorded in the PRD's Decision Register is dismissed by
     citing that entry, unless its severity has risen or the reviewer brings
     new evidence.
3. **Adjudicate** — `references/synthesis-prompt.md` § "Lead adjudication".
   Reviewers advise; you decide. An Act-On list over five items means you are
   under-filtering.
4. **Gate check** — see "The trend-aware gate" below, then "The growth stop".
5. **Remediate autonomously** — do NOT hand findings to the user to fix. Every
   finding first goes through the **remediator's judgment mandate**
   (`references/prd-structure-rules.md` § 1): a reviewer's finding is evidence
   and its suggested fix is a proposal — neither is an instruction — and every
   disposition is recorded. Then **edit the PRD** for each finding you accept.
   Every iteration you address:
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
   than loosening the match). A fix that would add infrastructure escalates
   instead of landing.

   Saving the PRD edits is enough for the next pass to see them — the
   reviewers read the PRD file directly. Do not commit between passes.
6. **Consistency gate (mandatory, mechanical)** — run the procedure in
   `references/consistency-pass.md` § "The post-remediation consistency gate"
   over every edit you just made. This is not "check consistency"; it is a
   mechanical re-resolution of every cross-reference, threshold/parameter and
   defined term the fix touched. **The iteration is not finished until the gate
   reports zero stale hits.** Record the gate's counters in the round record.
7. **Delta verification (mandatory)** — reserve, then verify. See below. The
   iteration is not finished until the remediation you just applied has been
   verified.

The phases are **sequential, not parallel**: Phase A must reach its exit
condition before Phase B begins.

### The delta verification

**Every remediation is immediately followed by a verification of exactly what it
changed.** If you changed nothing, there is no delta and no verification.

Assemble the delta first — the verifier is judging your edits, so it needs, per
finding: the finding as originally raised (id, title, severity, class), the
disposition you chose and why, and the edit you made with the location it landed
in. Add the PRD diff since the sha256 the pass reviewed.

Who verifies:

- **Phase A** — go back to the **same reviewer sub-agent that raised the
  findings**, in its existing thread with its context intact (continue that
  agent rather than spawning a new one; a fresh Agent call starts an empty
  thread). Continuing a thread is still a dispatch and still reserves. Send it
  the verification block from `references/personas.md` § "Mode: delta
  verification", scoped to the findings *it* raised. If a finding was raised by
  more than one persona, every raiser verdicts it, and one `NOT CONFIRMED`
  makes it `NOT CONFIRMED`. If the thread cannot be resumed, spawn a fresh
  reviewer with the same block plus the original finding text verbatim, and
  record the substitution in the round record.
- **Phase B** — a fresh process, which is inherent to the Codex path and is a
  **feature** there: a reviewer with no memory of raising the finding cannot
  rubber-stamp its own fix. Because it has no memory, the delta file must carry
  everything it needs. See Step 3 for the invocation.

Reading the result:

- **All listed findings `CONFIRMED`, and nothing new surfaced** → the iteration
  is complete. Continue, or exit the phase per the gate.
- **Any `NOT CONFIRMED`, or a newly surfaced problem** → remediate those items
  under the normal rules (a `NOT CONFIRMED` verdict is a finding, not an order —
  the judgment mandate applies to it too), re-run the consistency gate, and
  **verify the new delta**. At most `VERIFY_RETRY_LIMIT` such cycles on one
  remediation; if the delta still does not come back clean, **stop and escalate
  to the user** with the outstanding verdicts. Do not approve, and do not paper
  over it with another discovery pass.
- **The verification surfaced new Critical or High findings** → the phase has
  not converged. The next pass is a discovery pass (or a method change, per the
  trend), whatever the previous counts said.

A remediation whose delta was never verified — because the reviewer was
unavailable, or the run stopped — can never support an approval outcome.

### The round record

Per pass, the running record must capture:

- pass number, phase, and **pass type**
- the dispatch seqs reserved for it, and the budget remaining after
- PRD sha256 at review time, and PRD word count, with the multiple of the
  baseline (`GROWTH_HARD_CAP` is the ceiling)
- per reviewer: name and **the tier it ran at** (`DISCOVERY_TIER` /
  `RECHECK_TIER`) and its scope (full document / changed sections)
- findings by severity **and by class**, plus how many of this pass's new
  Critical/High live in prose the previous remediation added
- regressions and Decision Register dismissals
- the **disposition of every finding** (applied as proposed / applied, modified
  / declined / deferred) with its one-line reasoning
- remediation applied, and the consistency gate counters
- the delta verification: who verified, the `CONFIRMED` / `NOT CONFIRMED` tally,
  anything it newly surfaced, and how many re-verify cycles it took

### The trend-aware gate

Count this pass's Critical and High findings, then:

- **A discovery pass with zero Critical AND zero High → the phase is done.**
  Apply any curated Medium/Low you chose to fix, run the consistency gate,
  verify that delta, and exit the phase. Do not run an extra pass to confirm:
  a clean discovery pass has already read the whole document *including* the
  last remediation, and that remediation was verified when it was made.
- **Any other pass with zero Critical/High** (a clean delta verification, a
  consistency-only pass) does **not** exit the phase — only a discovery pass
  can. Continue.
- **Otherwise** → remediate, run the consistency gate, verify the delta, and
  start a new pass — but first read the trend and the growth stop.

Maintain a severity trend line in the running record, e.g.
`R1 3C/7H → R2 3C/15H → R3 2C/10H → R4 1C/5H → R5 0C/4H`. Then:

- **Converging** (Critical+High strictly declining across the last two passes,
  and the class mix shifting toward `CONSISTENCY`) → another pass of the same
  type is justified, budget permitting.
- **Flat, below the self-feeding threshold** → **change method.** Run a
  consistency-only pass (which, like every change, is followed by its own delta
  verification), then resume discovery. More passes of the same kind do not
  converge a flat loop.
- **At or above `SELF_FEEDING_THRESHOLD`, or at `GROWTH_HARD_CAP`** →
  **terminate as non-converging** and escalate. See "The growth stop".

A pass in which any reviewer failed to produce a review is a **partial** pass.
A partial pass can never satisfy a phase's exit condition — the reviewer that
would have objected may be exactly the one that failed.

Record the trend and which branch you took. The trend is decision-grade
information — it belongs in the report, not just in your head.

## Step 2: Phase A — Claude persona loop (High-consequence)

Read `references/personas.md` for the 3 persona system prompts, the shared
output contract, and the delta-verification and recheck-scope modes.

**Each pass, reserve three dispatches, then dispatch all 3 Claude personas as
parallel sub-agents** (all 3 Agent calls in one message). Each sub-agent
receives:

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
round record, alongside its dispatch seq: the delta verification after this
pass's remediation goes back to those same threads, and a new dispatch would
arrive with no memory of the finding it is being asked to check.

### Reviewer tiering

**No persona is ever skipped.** A persona that came back clean is the only
regression net over the churn the previous remediation just created, and that
churn is where the next pass's defects come from. Downgrade it; do not drop it.

Per persona, per pass:

| Its previous pass | Tier this pass | Scope this pass |
|---|---|---|
| returned ≥1 Critical or High | `DISCOVERY_TIER` | full document |
| returned zero Critical/High | `RECHECK_TIER` | sections changed since that persona's last pass, plus its standing focus areas |
| n/a (first pass, or the first discovery pass after a structural pass) | `DISCOVERY_TIER` | full document |

A recheck is a dispatch and it reserves like any other. Downgrading the tier
saves model cost, not budget.

A delta verification runs at the tier that persona ran at when it raised the
findings — it is the same thread continuing, so tier and scope are already
fixed.

**Promotion valve:** if a `RECHECK_TIER` run surfaces any Critical or High, that
persona returns to `DISCOVERY_TIER` at full-document scope for the next pass.

Dispatch mechanics:

- `DISCOVERY_TIER` reviewers are spawned with **no `model` and no
  `subagent_type` override** so they inherit the orchestrator session's model
  and effort. The operator controls that tier from above; do not pin it here.
- `RECHECK_TIER` reviewers are spawned with
  `subagent_type: df-reviewer-recheck`. Reasoning effort **cannot** be set
  per-spawn on the Agent tool — only `model` can — so the effort is carried by
  that agent definition's frontmatter. Passing a per-invocation `model` would
  override the definition's model while effort stays locked to frontmatter;
  that is the intended behaviour, so **do not pass `model`** and let both come
  from the definition.
- `RECHECK_TIER_FLOOR` is binding. If the agent definition is unavailable or a
  future model substitution would put the recheck below the floor, run the
  recheck at `DISCOVERY_TIER` instead and note it in the report.

Report the tier and scope each persona ran at, every pass (see "The round
record").

### Phase A exit

Loop until the exit condition in "The trend-aware gate" is met, or the run hits
`DISPATCH_BUDGET`, `GROWTH_HARD_CAP`, or the self-feeding threshold. Any of the
three lands in Step 4. Reaching a stop in Phase A never approves a PRD.

## Step 3: Phase B — Codex leg

In **Standard**, this runs once, as the cross-family half of the single pass,
plus once more for the delta verification. In **High-consequence**, it runs as
the second phase of the loop, once Phase A exits cleanly.

Reserve the dispatch first. Codex runs **detached with a wide window and is
polled** — a hard foreground timeout kills healthy legs mid-exploration on a
large PRD. Start it, then poll in slices:

```bash
script_path="$HOME/.claude/skills/df-prd-challenge/scripts/run_codex_prd_review.sh"
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/skills/df-prd-challenge/scripts/run_codex_prd_review.sh"
fi
if [[ ! -f "$script_path" ]]; then
  script_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/skills/df-prd-challenge/scripts/run_codex_prd_review.sh"
fi

if [[ ! -f "$script_path" ]]; then
  echo "ERROR: Cannot find run_codex_prd_review.sh" >&2
  echo "Checked: \$HOME/.claude/skills/, <repo>/skills/, <repo>/.claude/skills/" >&2
  exit 1
fi

review_dir="<REVIEW_ROOT from Step 1>"
out_path="$review_dir/codex-challenge-review-<N>.md"   # <N> = pass number
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
- `complete` → read the review at `$out_path` and continue.
  Check `MODE=` matches the mode you started the leg in.
- `limit` → Codex hit a usage/rate limit. Handle per "Codex usage limit" below.
- `failed` → the run exited non-zero for some other reason, **or produced an
  empty or structurally invalid review**. Treat `failed` as *no review happened*
  — never as a clean pass (`references/rationale.md`
  § "Harness correctness"). Proceed per "Codex failure that is not a usage
  limit".
- `timeout` → the window elapsed. Same handling as `failed`.

**Never** decide a leg's outcome by grepping the review body or the raw stderr
log for phrases — the status file is the contract
(`references/rationale.md` § "Harness correctness").

Read the Codex output, then run synthesize → adjudicate → gate check →
remediate → consistency gate → delta verification. In High-consequence, stop
when the gate's exit condition is met or the budget refuses the next
reservation, whichever comes first.

### The Codex delta verification

The verification after each remediation is the same script in verification
mode, and it reserves its own dispatch. Write the delta to `REVIEW_ROOT`
first, then:

```bash
delta_path="$review_dir/codex-delta-<N>.md"     # you write this file
out_path="$review_dir/codex-verification-<N>.md"
CODEX_REVIEW_MODE=verification \
CODEX_REVIEW_DELTA_FILE="$delta_path" \
  bash "$script_path" start "<prd-path>" "$out_path"
bash "$script_path" wait "$out_path"             # poll in slices as above
```

`start` refuses to run without an existing delta file in this mode. Confirm the
status file reports `MODE=verification` before reading the verdicts: a leg
that ran in discovery mode verified nothing, whatever its findings look like.

The delta file is the whole context this reviewer gets — it is a fresh process
with no memory of raising the findings. That independence is a **feature** here
(it cannot rubber-stamp a fix to its own finding), but it means the file must
carry, per item: the finding as raised, the disposition and its reasoning, the
edit made and where, plus the PRD diff.

Read the result per "The delta verification" above.

**A crashed or timed-out leg is retried once.** On `STATE=failed`/`timeout`,
reserve again and re-run at a **fresh out-path** — up to `TOOLING_RETRY_LIMIT`
retries — before concluding anything. A single transient crash is not a blocked
leg. The retry costs a dispatch. Record it in the round record.

**Codex usage limit (`STATE=limit`):** a usage limit is a **recoverable**
tooling block. Stop the Codex leg immediately — do not start another, and do
not retry.

- **Salvage the paid-for signal.** The assembled out-file holds only the failure
  banner; the banner points at the raw `<out-path>.body.md`, which may contain
  findings the run produced before it was cut off. Read it, and remediate any
  Critical/High under the normal rules. That delta cannot be verified by this
  leg — the reviewer that would verify it is the one that is unavailable — so
  record it in the report as an **unverified delta**.
- **Then apply D7 for the lane.** Record `deferred: usage-limit` in the run
  ledger either way.

**D7, the blocked cross-family leg.** This is the one rule that differs by
lane, and it differs on purpose:

| Lane | A blocked Codex leg means |
|---|---|
| Standard | **degrade with a logged note.** Continue single-family, record the deferral in the ledger, and state it in the report and the chat summary. |
| High-consequence | **defer approval.** Leave the PRD at its pre-approval status, record the blocker and how much of the run completed, surface it, and stop. A tooling-blocked leg defers approval; it never waives it. |

**Codex failure that is NOT a usage limit** (`STATE=failed`/`timeout` after
`TOOLING_RETRY_LIMIT` retries, script missing, malformed output) is a blocked
leg and takes the same D7 treatment. In High-consequence, model diversity is
load-bearing — if work must be cut, cut Phase A passes, never this leg.

## The second-opinion pass (operator-invoked)

The operator may ask for one more review, once per run, in either lane. This is
the formalized version of "just rerun the review", with the three couplings
that made rerunning dangerous removed.

- **Decorrelated by construction.** The other model family, or the same family
  under a deliberately different rubric lens. Never the same reviewer under the
  same prompt: a same-model rerun is a correlated draw and it mostly
  rediscovers.
- **Costs `SECOND_OPINION_DISPATCHES`** against the same budget, reserved
  before it spawns like anything else.
- **Lead-adjudicated** under the same rules. Its findings do not bypass the
  Act-On discipline.
- **Gates unchanged.** It cannot lower the bar for approval and it cannot raise
  it. It is an extra sample, not a new gate.
- **The operator invokes it.** This skill never reaches for it, never suggests
  it as a substitute for terminating, and never runs it because a pass felt
  thin.

## Step 4: Termination

The run-level outcome is decided once, at the end. In Standard that is after
the single pass's delta verification. In High-consequence it is at the end of
Phase B; Phase A ending is a *phase* ending and can never produce an approval.

The run terminates for exactly one of these reasons, and the reason is typed
in the report:

| Reason | Outcome |
|---|---|
| The gate's exit condition was met (Standard: the pass finished; High-consequence: a clean discovery pass in Phase B) | classify the residue below |
| `DISPATCH_BUDGET` refused a reservation | **Terminated — budget.** Escalate with the report and the outstanding findings. Never approve. |
| `GROWTH_HARD_CAP` reached | **Terminated — non-converging (growth).** Escalate. |
| `SELF_FEEDING_THRESHOLD` reached | **Terminated — non-converging (self-feeding).** Escalate. |
| A remediation would add infrastructure | **Escalated — scope decision.** Present the finding and the mechanism; wait. |
| `VERIFY_RETRY_LIMIT` exhausted on one delta | **Escalated — unverified remediation.** |
| A blocked cross-family leg in High-consequence | **Deferred — cross-model leg blocked.** |

Classifying the residue, when the gate exited cleanly:

- **Zero Critical/High** → **Approved**.
- **Residue is `CONSISTENCY` class only** → **Approved with open items**. List
  the residue in the PRD's "Known open items — read first" section.
- **Any `SUBSTANTIVE` residue** → **stop and escalate to the user.** Do not
  loop, do not approve, do not set the PRD to Approved.

**Preconditions on any approval outcome.** Both must hold. If either fails, the
outcome is *defer, surface and stop* — never an approval:

- A cross-family leg produced **at least one completed review** this run, or
  the lane is Standard and its absence was logged as a degrade under D7.
- **Every remediation applied in this run has a delta verification that came
  back clean.** An unverified delta cannot be approved over, and residue whose
  class was `(inferred)` rather than reviewer-emitted never justifies approving.

## Step 5: Finalize

1. **Write the full report** from your running record to the reserved path,
   following the report format in `references/synthesis-prompt.md`: the lane,
   the passes run and their types, each pass's findings by severity and class,
   the tier each reviewer ran at, the severity trend, PRD growth against
   `GROWTH_HARD_CAP`, dispatches used against `DISPATCH_BUDGET`, the
   consistency gate counters, the remediation applied, the Decision Register
   additions, the typed termination reason, and the residual items left
   intentionally. Number findings once, globally. It must be self-contained —
   readable without the chat context.
2. **If the outcome is Approved-with-open-items**, add or update the PRD's
   **"Known open items — read first"** section using the template in
   `references/prd-structure-rules.md`. It goes at the **top** of the PRD and is
   written for the zero-context implementing agent: what is unresolved, what the
   risk is, what decision is owed and by whom.
3. **If the outcome is escalate, defer, or terminate**, surface what stopped the
   run — the residual `SUBSTANTIVE` findings, the budget, the growth cap, the
   self-feeding trend, the infrastructure the fix wanted to add, the tooling
   blocker, or the delta that could not be verified — to the user with the
   report link, leave the PRD's status unchanged, and stop.
4. **If the outcome is Approved or Approved-with-open-items**, set the PRD's
   Status field (`Approved` / `Approved with open items`), save, and commit:
   `git add <prd-path> && git commit -m "docs: approve PRD after challenge round for <feature>"`
5. **Close the run's stage in the state store** so the dispatch count and the
   terminal reason are readable without the transcript.
6. Present a **TTS-friendly chat summary** (do NOT paste the full report) that
   states the ACTUAL outcome — fill the placeholders from what really happened;
   do not assert convergence if the run terminated on a stop or residue
   remains:

```
Challenge round complete. Full report:
<GoGrip link>

Lane: <Standard | High-consequence>. <Single pass, two reviewers. | N passes across two phases.>
Dispatches: <used> of <budget>. PRD growth: <x.x>x of the 2x cap.
Termination: <clean gate | budget | non-converging, growth | non-converging, self-feeding | escalated, scope | deferred, cross-model leg blocked>.

Severity trend: <R1 aC/bH → ... → Rn 0C/0H>.
Remediated A Critical, B High, and C curated Medium/Low findings in the PRD.
Deferred D Medium/Low (see report). <PRD set to Status: Approved and committed. Ready for df-qa-runbook-gen. | Approved with open items — N listed at the top of the PRD. | Residual substantive findings remain — your call on how to proceed.>
```

## Common Mistakes

- **Spawning a reviewer without reserving first.** The reservation is the
  count. A spawn that was not reserved is a budget leak, and the budget is the
  only brake this skill has.
- **Treating a delta verification as free.** It is a dispatch. The exemption
  that used to make it free is exactly why a capped loop reached 15 rounds.
- **Extending past the growth cap because the trend "looks like it is
  converging".** There is no extension. A self-feeding loop reports itself as
  converging.
- **Applying an infrastructure fix autonomously.** A queue, a DO, a key scheme,
  a watchdog, or a new state machine in a remediation is a scope decision.
  Escalate.
- **Writing a census into the PRD.** Generate it from source or do not have it.
- **Running a second round in the Standard lane.** There is no second round.
  Report the lane question to the operator.
- **Adding personas to the Standard pass.** Both reviewers get the same rubric.
  The diversity is the model family.
- **Accepting an empty review as a clean pass.** A pass whose reviewer produced
  nothing is a *failed* pass, not a passing one. Check `STATE`, not the exit
  code.
- **Deciding anything by grepping review text.** Limits, failures and
  completion all come from the status file. Review bodies contain repo content
  and will match anything.
- **Reusing a fixed scratch path.** Every run gets its own `REVIEW_ROOT`;
  concurrent runs otherwise destroy each other's output.
- **Running Phase A and Phase B together / in parallel.** They are sequential.
- **Skipping the consistency gate after remediation.** Most of the next pass's
  Critical/High will otherwise be drift your own fix created.
- **Skipping a persona because it came back clean.** Downgrade to
  `RECHECK_TIER`; never skip.
- **Pinning the discovery tier.** `DISCOVERY_TIER` is inherited on purpose.
- **Approving off an unverified change.** Every remediation, restructure and
  consistency-only pass is verified against its own delta.
- **Letting a consistency-only pass change requirements.** Its charter is
  binding; a substantive gap it finds is *recorded*, not fixed.
- **Approving because Codex could not run in High-consequence.** A tooling-blocked
  leg defers approval there; it never waives it. A usage limit is a tooling
  block.
- **Degrading silently in Standard.** Degrading is allowed. Degrading without
  saying so in the report and the summary is not.
- **Running a Codex verification in discovery mode.** Set
  `CODEX_REVIEW_MODE=verification` and `CODEX_REVIEW_DELTA_FILE`, and check
  `MODE=` in the status file.
- **Applying a reviewer's suggested fix without checking it.** The finding is
  evidence, the fix is a proposal; verify both and record your disposition.
- **Verifying a fix in a fresh reviewer thread when the original one exists.**
  Continue the thread that raised the finding — a new one has no idea what it is
  checking.
- **Handing Critical/High findings to the user to fix.** Remediation is
  autonomous, up to the infrastructure line.

## Notes

- **Reference file resolution**: `references/*.md` are relative to the skill
  directory. Look in `$HOME/.claude/skills/df-prd-challenge/references/`
  (global) or the repo's `skills/df-prd-challenge/references/` directory.
  If not found, stop and report the error.
- **Reference files**: `single-pass.md` (the Standard-lane contract, shared
  rubric, and terminal outcomes), `personas.md` (High-consequence persona
  prompts, the shared output contract, and the delta-verification and recheck
  modes), `synthesis-prompt.md` (synthesis rules, lead adjudication, and the
  report format), `consistency-pass.md` (the post-remediation gate and the
  consistency-only pass charter), `prd-structure-rules.md` (the remediator's
  judgment mandate and the authoring rules it applies to the PRD),
  `rationale.md` (why these rules exist).
- Reviewer models resolve through `../df/references/model-policy.md`. Do not
  hardcode a model slug at a call site.
- Personas are gap-finders, not scope-expanders. They should never suggest new
  features.
- Codex provides model diversity (GPT vs Claude). It may catch blind spots all
  Claude reviewers share. That diversity, not persona assignment, is where the
  adversarial signal comes from.
- Scratch (Codex output, status file, stderr log, delta files) goes to
  `REVIEW_ROOT` under /tmp/, never under `.claude/`, so the autonomous loop
  never trips a write-permission prompt; the generated report lives in the
  gitignored `.dark-factory/reviews/` directory.
- **`REVIEW_ROOT` in your own context is authoritative.** `RUN_DIR_POINTER` is a
  convenience for a session that lost it, and a second run in the same checkout
  overwrites it. If the pointer disagrees with the `REVIEW_ROOT` you created in
  Step 1, trust your own and say so in the report.
