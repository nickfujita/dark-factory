# Dark Factory Course Correction — Diagnosis, PSTACK Adoption Plan, and the Real Path to Level 4

**Date:** 2026-08-27 · **Revision:** 2 (fact-checked against all primary sources; one factual
correction and structural revisions applied — see Appendix C)

**Inputs reviewed:**

- Forensic session analyses: `docs/cloud-dev-2-feedback.temp.md` and
  `docs/dev-env-a-feedback.temp.md`
- Codex's comparison: `docs/2026-08-27-dark-factory-vs-pstack.md`
- Lauren Tan's talk transcript: `docs/pstack-author-presentation-transcript.txt`
- PSTACK source at [`cursor/plugins@bdf7aa3`](https://github.com/cursor/plugins/tree/bdf7aa355337897f167153e05069aca505dae17c/pstack)
  (verified against current `main`: differs only by one cosmetic skill) — full read of the 23
  playbook files, the ~23 workflow skills, 21 principles, 2 agents, guide docs, and the benny
  automation pack
- Dark Factory repo at `8f95ca4` — full read of `skills/`, `codex-skills/`, `agents/`,
  scripts, plus the **installed** copies in `~/.claude/skills/` and `~/.codex/skills/`
- Spellguard `origin/main` @ `6843f38` — all AGENTS.md/CLAUDE.md files, skills, standards docs,
  CI workflows
- Superpowers 6.3.0 as installed (brainstorming, writing-plans, SDD, TDD, verification skills)

**Cast of incidents** (used throughout):

| Label | What it was |
|---|---|
| **cloud-dev-2 run** | Codex Sol-xhigh, managed-vm-operations feature: 35 h, 15-round PRD challenge (rounds A1–A15), PRD 4,265 → 62,445 words (14.6×), 24-task plan, 7 tasks done, zero UI, stopped by you |
| **Session B** | Claude Code takeover of that same branch: 11/24 tasks in ~12 h, produced the intent-vs-PRD quantification and the downward-amendment precedent |
| **dev-env-a run** | Codex Sol-xhigh, cloudflare-credentials-bootstrap PR: 2.5 days, one 41 h autonomous turn from a single "Approved", 113 subagents, never merge-ready. Never ran drk-02 — its loops were Superpowers SDD + Spellguard's repo standards |

---

## 1. TL;DR

**The models didn't get worse — they got better at following your instructions, and your
instructions describe a ratchet with no brake.** Both forensic analyses independently reach this
conclusion: Sol/Fable-class models execute the challenge/review loops *maximally faithfully*, and
the loops' exit conditions ("zero Critical/High") depend on strong reviewers running out of
findings — which strong models never do. The process was implicitly calibrated for models that
half-followed instructions.

**Three compounding failures, in order of leverage:**

1. **You are not running the machinery you think you are.** The repo's drk-02 was substantially
   hardened (pinned caps, delta verification, self-feeding detection, typed termination), but the
   **old pre-hardening version is what's installed** on this VM in both `~/.claude/skills/` and
   `~/.codex/skills/`, and `~/.claude/agents/` doesn't exist, so the `drk-reviewer-recheck` agent
   the hardened flow depends on is not installed. `just sync` was never run after the hardening
   landed.
2. **Even the hardened version brakes the wrong thing.** The cloud-dev-2 run executed a
   hardened-generation loop and still hit 15 rounds and ~11 hours: the caps count *rounds* while
   real work escapes them (delta verifications and adopted orphan reviews are exempt by design,
   and the convergence extension adds rounds past the cap), growth thresholds only *flag*, and
   `SELF_FEEDING_THRESHOLD` never trips when findings are "legitimate" against text the loop
   itself added.
3. **Nothing anywhere asks "is this proportionate to the ask?"** Not drk-01, not the challenge
   loop, not the planner, not Spellguard's rulebook, not Superpowers. A 2–4-hour intent became a
   47-hour, two-harness, 54%-of-weekly-quota program with zero user-visible output, and every
   individual step was locally correct.

**What PSTACK actually offers** is not a heavier control plane — it is a different philosophy:
*where Dark Factory bounds loops by counting rounds, PSTACK mostly removes the loop.* No PRD
artifact to inflate, single-pass multi-model review filtered by a lead who is told "if your
'Act On' list has more than 5 items, you're probably not filtering hard enough," doneness keyed
to head SHA in a ledger rather than to reviewer exhaustion, and falsifiable exit predicates
declared before any loop starts. Lauren's talk adds the deeper point: her review-agent layers
are explicitly her *weakest* enforcement tier — the real guardrails are the codebase
architecture and hard CI checks, and every constraint a human has to enforce in review is "a
code smell… how do I turn this into a lint rule? How do I turn this into a CI failure?"

**The plan, in one paragraph:** sync and attest the installed skills (this week); add a
proportionality gate and lane routing at pipeline entry; convert round-caps to work-and-budget
caps with hard growth stops; replace multi-round persona challenge with single-pass
model-diverse review + lead adjudication for small/medium work; delta-scope drk-06; persist loop
state to disk; keep the per-task independent review (best available evidence says it earns its
cost — §2.4); and redirect the saved tokens into the PSTACK-style *environment* investments that
actually raise your level: a standing verify-spellguard skill + feature map,
encode-lessons-in-structure CI checks, and skill evals. The Claude master orchestrator comes
**after** lanes and budgets exist — building it first would just automate the ratchet.

### Decisions required from you (everything else in this report is executable without input)

| # | Decision | Proposed default |
|---|---|---|
| D1 | Ratify the three lanes and their gates (§4.2), including: Quick lane skips PRD/challenge/runbook entirely | As specified in the lane table |
| D2 | Reviewer-dispatch budget for a High-consequence drk-02 run | 12 total dispatches |
| D3 | Effort-Anchor stop multiple (projected cost vs your stated effort expectation) | 3× |
| D4 | Hard PRD growth cap | 2× the hardened drk-01 output |
| D5 | Plan-size gate | > 8 tasks ⇒ sign-off before implementation |
| D6 | Checkpoint cadence for autonomous stretches | every ~2 h, or every 10 commits |
| D7 | Blocked cross-model review leg: defer approval or degrade gracefully? | Defer in High-consequence lane; degrade in Standard (log it) |
| D8 | Codex-flow drk-04 has no model diversity (Codex reviews Codex). Route its second leg to Claude tmux, or accept for Standard lane? | Accept for Standard, fix for High-consequence |
| D9 | De-minimis tier for Spellguard credential-flow review (§6.3) — accept the security trade? | Yes, with the tripwire in §4.4 |
| D10 | Single-pass challenge for Standard lane — accept removing the multi-round loop? | Yes, with the tripwire in §4.4 |

---

## 2. Diagnosis — what actually broke

### 2.1 The models didn't get worse

Both forensic reports tested and rejected the "Codex 5.6 is incompatible with the skills"
hypothesis in the same words: the models are **over-compatible**. dev-env-a: "not incompatible;
*too compatible*. Weaker models drift off process; these follow it maximally and are capable
enough to always produce one more legitimate-looking finding and diligent enough to fix them
all." cloud-dev-2: "a highly instruction-following model executes a ratchet-shaped process with
no brake." The same report predicts — and Session B confirms — the identical pathology on Claude,
at lower amplitude (~2.9× faster per task, same per-task rigor; though Session B never ran
drk-02 — it inherited the already-inflated PRD, so the harness comparison has that confound).

The worker-quality hypothesis was also rejected in both reports: workers mostly delivered green,
verified slices on the first or second attempt. The one systematic worker failure class was
model-enumerated exhaustive inventories ("a 94-entry census with guessed/nonexistent
boundaries") — hallucination bait by construction, fixable by generating inventories from source
with a script (carried forward in §4.2).

### 2.2 The runaway mechanism (the ratchet)

The chain, assembled from both sessions:

1. **A completeness mandate enters the PRD** ("fill any and all logging gaps … so we never miss
   any states") — an inexhaustible mining vein for adversarial reviewers.
2. **Remediation adds mechanism; mechanism breeds findings.** Each round's fixes added new
   infrastructure to the PRD (queues, DLQs, HMAC-signed admission permits, watchdogs, a
   131-entry producer manifest). The next round found *technically real* Critical/High gaps in
   that new prose. The loop was finding real bugs in requirements it had itself invented.
3. **Caps count rounds; work escapes them.** The hardened loop reached A15 legally. In the
   current repo skill: delta verifications and adopted orphan reviews are exempt from the cap by
   design, and the convergence extension adds up to 2 rounds past it (the cloud-dev-2 report
   additionally describes consistency-only passes and delta verifications not counting in that
   run). Growth warnings (15%/round, 50% total) are flags, never stops; the 50% self-feeding
   threshold never trips because each finding is legitimate against the current text.
4. **Downstream inherits the inflation.** 62k-word PRD ⇒ 24-task plan ⇒ per-task reviewers
   correctly reject work against that standard ⇒ 18 h for 7 backend tasks, UI (the actual
   request) scheduled last ⇒ 35 h, zero visible product.
5. **Scope is sticky across handoffs.** Session B was told "don't blindly follow," re-validated
   the *code* against the PRD, but treated the PRD itself as your settled decision. Handoff docs
   that freeze scope launder amplification into authority.
6. **Autonomy grants don't expire.** One word ("Approved") stretched across 41 hours on
   dev-env-a. Review findings labeled Important were treated as standing authorization to build
   new subsystems.

Supporting amplifiers found in this investigation:

- **Reviewer economics:** every fresh Codex reviewer in the pipeline defaults to `xhigh` (7
  scripts; env-overridable only in the hardened drk-02 runners) with no size scaling; Claude
  reviewers inherit the orchestrator session (often the most capable model); on dev-env-a the
  escalation tier (`sol_high`) became the default worker (115 of 167 assignments) because in
  Spellguard nearly everything matches "credential/auth/security boundaries."
- **State lives in context.** drk-02 and drk-06 keep their loop-control state (round number,
  severity trend, which deltas were verified) exclusively in the driving session's running
  record, written to disk only at finalize. 12–28 compactions per marathon session meant the
  loop repeatedly could not prove where it was; on dev-env-a the SDD skill file was re-read 52
  times, re-priming the same loop after each compaction.
- **Spellguard's rulebook contains unbounded work generators** that every drk stage re-inherits
  (detailed with fixes in §6).
- **Three verification layers own the same branch without shared evidence.** SDD reviews every
  task and the whole branch; drk-05 re-runs everything; drk-06 runs up to 10+3 more whole-branch
  rounds. SDD's ledgered rulings are deleted at SDD finish, before drk-06 ever runs — so the
  same class of finding is rediscovered and re-litigated at each gate.

### 2.3 The drift finding — you shipped the fix and never installed it

| Component | Repo (`8f95ca4`) | Installed on this VM |
|---|---|---|
| drk-02 (Claude) | 629-line hardened SKILL.md: pinned caps, round types, delta verification, consistency gate, trend gate, growth/self-feeding thresholds, typed termination, judgment mandate | **209-line old generation: none of the above.** Only "10 rounds — set high on purpose" + full re-review and autonomous remediation every round |
| drk-02 (Codex) | Same hardening (613 lines) + status-file contract, detached runners, partial states | **Same old generation** (235 lines); old 96-line foreground runner, no status machinery |
| drk-02 references | `consistency-pass.md`, `prd-structure-rules.md`, `rationale.md` | **Missing entirely** |
| `agents/drk-reviewer-recheck.md` (opus/high recheck tier) | Present, mapped in `manifests/agents.tsv` | **`~/.claude/agents/` does not exist** |
| drk-03/04 | "Approved with open items" carry-through | Predates it |
| drk-06 (Codex) | Matrix-bridge suppression (`8f95ca4`) | Missing |

To be precise about what this does and doesn't explain: **neither analyzed runaway ran on this
VM.** The cloud-dev-2 run executed a hardened-generation drk-02 and blew up anyway; the
dev-env-a run never invoked drk-02 at all — its loops were Superpowers SDD plus Spellguard's
repo standards. What the drift means is (a) any drk-02 run started from *this* VM today would
use the worst version, (b) you cannot currently know which generation any given VM runs, and
(c) the guards you believe are live may not be. That is a reliability and observability defect
to fix before evaluating anything else — but syncing is **necessary, not sufficient**, because
the hardened generation demonstrably still runs away. The hardening fixed loop *mechanics*
(fail-closed runners, delta verification, typed termination) but not loop *economics* (what
counts against the cap, flag-vs-stop, proportionality).

### 2.4 What is NOT broken — protect these while cutting

- **Per-task independent review.** Session B measured it on one feature: ~1.5× overhead, five
  would-be production faults caught that all passed the full 16.7k-test suite first. Both
  reports agree the runaway cost is the multi-round *requirements* challenge, not per-task
  review. This is n=1 — treat "keep it" as the working hypothesis and re-measure overhead and
  caught-fault count on the Phase 0 baseline feature (§8) before treating 1.5× as a planning
  constant. Keep it either way; fix its mechanics (focused suites, sharded gates, batched
  landings).
- **The artifact discipline.** PRD→QA traceability, coverage matrices, evidence-oriented
  reports, local/dev-only QA restriction. PSTACK has no equivalent, and for a
  credential-handling product like Spellguard, requirements traceability is worth keeping. The
  Codex doc is right: don't replace this with a generic task list.
- **The amendment precedent.** Session B's mid-flight downward PRD/QA amendment ("lite read
  plane," 94 → 15 browser cases, risks-accepted section, re-signed, hash recomputed) worked and
  was cheap. It needs to become a first-class pipeline operation instead of something you
  trigger by asking "why is this slow?"
- **drk-05's ledger pattern.** The one Dark Factory loop with a compaction-safe on-disk ledger.
  Extend the pattern; don't invent a new one.
- **The escalation rule shape** (fresh senior eyes at round 4) worked as designed — the problem
  was it was pointed at an invented requirement.

---

## 3. What PSTACK actually is

### 3.1 The philosophy inversion

Dark Factory and PSTACK agree on the goal (trustworthy autonomous delivery) and on verification
as the foundation. They disagree on where the tokens go:

| | Dark Factory today | PSTACK |
|---|---|---|
| Spend shape | **Per-feature, on process**: challenge rounds, review rounds, generated runbooks, re-runs | **One-time, on environment**: verification skills, feature maps, CI hard constraints, framework architecture; per-feature process stays light |
| Requirements | PRD artifact, adversarially hardened over rounds | No PRD at all ("i don't believe in planning. the best spec is code"); requirements live as a **falsifiable finish predicate stated in the first prompt** |
| Review | 3 personas + cross-model, looped until zero Critical/High, autonomous remediation | **Single-pass**, model-diverse (personas explicitly rejected: "the adversarial signal comes from model diversity, not assigned personas"), lead adjudicates into Act-on / Consider / Noted / Dismissed, findings are **not** auto-applied |
| Loop bounding | Round caps with exemptions | **Loop removal** + local budgets: one CI retry ("an identical second failure means it was never flake"), two agent retries then abandon, Bugbot pass-counter with third-pass lean-dismiss |
| Doneness | Gate condition (zero C/H) per stage | **Verification ledger keyed to PR + head SHA** (`patch-id` for restacks): "A new head SHA voids the row. The ledger answers 'was this verified', not memory and not the transcript" |
| Scope control | (absent) | Pervasive: "The smallest change the evidence justifies ships, nothing more"; "Most changes need none of it" (design ceremony ladder); "Nitpick Gravity — reviewers tend to fill their review"; "Never churn code to quiet a bot"; scope leaks at fan-out park in follow-ups |
| Human role | Stage gates + sign-offs | Closed **always-pause list** (irreversible writes) and closed **never-reaches-the-human list** (retries, flake triage, "should I keep going"); questions parked in durable `gates.md`; merge authority permanently segregated ("Babysit stops at merge-ready. It never merges") |
| State | Mostly in-session running records | Plain-file store with **one writer per file**: `units.tsv`, `ledger.tsv`, `frontier.json`, `preferences.md` pasted verbatim into every spawn ("directives decay across resumes") |

### 3.2 Corrections to the Codex comparison doc

The Codex analysis is directionally sound and its Phase 0 (sync + attestation + instrumentation)
is exactly right. Three factual corrections from reading the PSTACK source directly:

1. **There is no 70%-context rule in PSTACK.** The 70% figure is *wall-clock*: "by roughly 70%
   of [the declared budget], stop spawning and land what is verified, because
   finished-but-unlanded work counts as zero" (`orchestrate.md`). Context pressure is handled
   structurally (bulk payloads routed to subagents, summaries in the main thread, pause-safely
   writing an off-context resume note when compaction approaches). Adopt the wall-clock rule —
   it's better than a context rule anyway, because it forces *landing*, not just stopping.
2. **The "three-lane router" is a simplification.** The real mechanism is `poteto-mode` matching
   one of 22 routed playbooks and *copying the playbook's steps verbatim into the todo list*
   (skipping a step requires a written `skip: <reason>`). Escalation (playbook → figure-it-out →
   orchestrate) and de-escalation are both explicit, with a measured anecdote against
   over-orchestration: the orchestrate ceremony "turned a half-hour 12-unit job into 1 landed
   unit while a plain agent landed all 12." The lesson for us is lane *routing with explicit
   up/down-scaling*, not a literal three-lane state machine.
3. **PSTACK doesn't bound review loops — it doesn't have them.** Multi-model review
   (`interrogate`) runs once, produces a categorized verdict, and explicitly does "NOT
   auto-apply changes." Re-verification is per-head-SHA, not an open-ended argument. So "adopt
   P Stack's budgets for our rounds" understates the option: for most work we can adopt the
   *round-free shape*, and reserve looping for the rare high-consequence artifact.

### 3.3 What the talk adds beyond the repo

Lauren's talk supplies the strategic frame the plugin files only imply:

1. **The trust curve has no shortcuts.** Her progression — heavily in-the-loop → verification
   skills → cloud agents → automerge — took 5 months and 600+ PRs of environment investment.
   "You can't go to a hundred agents when you don't even trust the output of one." Your Level-4
   ambition (a bot teammates can talk to) sits at the top of this curve; the immediate work is
   at the middle.
2. **Enforcement hierarchy.** Codebase architecture and conventions are the strongest layer
   ("agents just love to copy existing patterns"; "the shortest path is the best path" — make
   the easy way the right way); static analysis and CI are the hard backstop; rules, skills,
   and review bots are the *soft* layer — "if you only have rules and bugbot and skills and a
   style guide, it's only a matter of time before your codebase looks like complete trash."
   Dark Factory's entire runaway lives in the soft layer. Spellguard already has the strong-layer
   pattern in miniature (the BYOK arch test that machine-enforces the encryption invariant) —
   the strategy is to grow that layer until review has less to catch.
3. **Human-enforced constraints are a code smell.** "Every time you have to do that, you should
   consider that as a code smell… instead of me commenting on the PR… how do I turn this into a
   lint rule? How do I turn this into a CI failure? Or how do I even categorically eliminate
   this problem entirely?" This is the convergence mechanism Dark Factory's review loops lack:
   each review round should *shrink the future review surface*, not grow the artifact.
4. **The feature map.** A standing file teaching agents how to reach every feature of the app
   (navigation paths, selectors, keyboard shortcuts). It converted her verification skill from
   flailing to reliable, and it powers Benny (bug-report → cloud desktop → reproduce → verdict).
   This is drk-07's missing substrate: today every generated QA runbook re-derives app
   navigation from the PRD; a feature map makes that knowledge cumulative, maintained, and
   shared across features.
5. **Skills need evals.** "An eval is… like a unit test for an agent… Every time I modify a
   skill, I will run one of these." Dark Factory's drift problem is also a testing problem —
   `just test-runners` (fake-binary runner tests) is the right instinct; extend it toward
   behavioral evals of the loop policies themselves.
6. **Token economics.** She is explicit that she has unlimited tokens and that her exact way is
   not replicable on subscriptions. Her ROI argument survives translation: spend on the
   *durable* things (framework, constraints, verification capability) that make cheap agents
   good, not on repeated per-feature process. On subscriptions this argues *against*
   4-model panels and *for* the environment investments in §5.

---

## 4. Part A — Fix the current Dark Factory

### 4.1 P0 — this week, before anything else

1. **Sync and attest.** Run `just sync` (note: `rsync --delete` will fully mirror), confirm
   `~/.claude/agents/` gets created and populated, and verify with a diff. Then make drift
   impossible to miss: every drk skill stamps the skill-package SHA into its report header at
   start, and a preflight step fails the stage if repo-vs-installed differ. Do the same on
   every VM running this stack (cloud-dev-2, dev-env-a). Until this lands, no conclusion about
   "the current flow" is valid. *(~1 h + one short skill edit for the preflight.)*
2. **Capture the operator's effort expectation in drk-01.** One question ("if you did this
   yourself, how long would it take?"), written into the PRD header as
   `Effort-Anchor: 2–4h`. Every later stage compares projected cost against it and stops to ask
   when projection exceeds the anchor by the D3 multiple. The anchor existed in your head for
   the whole cloud-dev-2 run and was never recorded anywhere. *(~1 h.)*
3. **Wall-clock checkpoints with scope deltas.** Any autonomous stretch reports at the D6
   cadence: "PRD now X words (was Y), plan is N tasks, Z% of budget consumed — continue?" A
   one-word approval authorizes the scope that existed when it was given; scope growth re-opens
   the question. *(~2 h: a shared reference file both flows' skills cite.)*
4. **Fix Appendix A items 1–4 now** (stale reviewer-prompt paths, shared scratch path,
   warn-only output validation, sandbox fallback). All are small, unambiguous script/prompt
   edits independent of any redesign decision; the rest of Appendix A rides with the P1 work.
   *(~2–3 h total.)*

### 4.2 P1 — structural changes to the drk skills

**Lanes (proportionality gate) — the single highest-leverage change.**
Add a routing decision at pipeline entry (drk-00 or a drk-01 Phase 0), PSTACK-style:

| Lane | Entry | Requirements | Challenge (drk-02) | Runbook + validation (drk-03/04) | Review (drk-06) | QA (drk-07) |
|---|---|---|---|---|---|---|
| **Quick** (bug fix, small UI change, config) | Named files/surface, one acceptance target | Finish predicate in the prompt; no PRD | None | None — acceptance is the finish predicate | 1 reviewer, single pass, lead adjudication | Verify on matching surface via verification skill |
| **Standard** (typical feature) | Small PRD (hard cap: D4 × drk-01 output) | drk-01 lite | **Single-pass**: one Claude + one Codex, same prompt (no personas), lead adjudicates, one remediation wave, one delta verification. No rounds. | drk-03 thin runbook referencing the feature map; drk-04 collapses to **one** combined validation pass (its 3-round contradiction loop is High-consequence-only) | Per-task SDD review + **one** whole-branch discovery round + delta-scoped verification | Runbook execution |
| **High-consequence** (credential/BYOK boundaries, migrations, protocol compat) | Full drk-01 + explicit written autonomy contract (objective, editable scope, budget, terminal outcomes) | Full PRD | Hardened drk-02 with the economics fixes below | Full drk-03 + drk-04 (max 3 rounds, unchanged) | Full drk-06 with delta scoping | Full runbook + drk-07 |

Classification is proposed by the agent, confirmed by you, and recorded in the PRD header. The
default is Standard; nothing escalates itself to High-consequence silently — and critically,
*review findings never change the lane* (dev-env-a's scope explosion was findings-as-
authorization).

**Fix drk-02's economics (High-consequence lane only, since other lanes stop looping):**

- Count **work, not rounds**: a single budget of total reviewer dispatches (D2) that
  everything consumes — discovery, delta verification, consistency passes, tooling retries.
- Growth becomes a **stop**, not a flag: PRD may not exceed D4; a round whose Critical/High
  findings are majority-against-remediation-added-text terminates as *non-converging* and
  escalates. (Both were feedback-doc recommendations; the repo's `GROWTH_WARN_*` flags are the
  right sensors wired to the wrong actuator.)
- **New infrastructure in a remediation = operator escalation.** A fix that introduces a queue,
  DO, key scheme, watchdog, or new state machine into the PRD is a scope decision, not a
  wording fix. Autonomy over wording; sign-off over mechanism.
- **Ban model-enumerated exhaustive inventories** in PRDs; censuses are generated by script from
  source, then reviewed.
- Adopt PSTACK's lead-adjudication language into the synthesis prompt: reviewers provide
  evidence; the orchestrator accepts/rejects/defers/dismisses each finding and is explicitly
  told about Nitpick Gravity ("if a reviewer's findings are all nits and style preferences, the
  code is probably fine — say so") and that an Act-On list over ~5 items means under-filtering.

**Delta-scope drk-06.** One full-branch discovery round; every later pass verifies only the
fixes plus a fixed unresolved list (the drk-02 hardening already built exactly this pattern —
`personas.md`'s CONFIRMED/NOT-CONFIRMED delta verification; port it). New Critical/High after
round 1 requires specific evidence. This removes the last broad-re-review self-feeder. Also
resolve the blocked-cross-model asymmetry per D7 and document it.

**Persist loop state (lightweight).** Extend drk-05's ledger pattern to drk-02/drk-06: a state
file per run (round/dispatch count, artifact SHA, finding dispositions, verified deltas, budget
consumed, next action) written *before* each dispatch, resumed from *only* the file. This is
PSTACK's `units.tsv`/`ledger.tsv` shape and it neutralizes compaction amnesia. (The
*cross-stage* evidence ledger is deliberately Phase 2 — see below.)

**Vertical slice first.** The drk-04 → brainstorming handoff message should instruct the planner
to order tasks so a user-visible slice lands early. 35 hours with zero visible product must be
structurally impossible.

**Amendment as a first-class operation.** A `drk-02b` (or drk-02 mode): signed, ID-traceable
downward PRD/QA amendment — proposed *proactively* whenever measured cost diverges from the
Effort-Anchor, not only when you ask. Session B proved the mechanics (amend, re-sign, recompute
pinned hash, re-plan) work and are cheap.

**Handoff re-anchoring.** Any takeover/handoff consumer must re-derive intent from the original
request, diff it against the inherited PRD/plan, and surface any ≥2× multiplier before
estimating. Handoff "locked scope" sections are claims to re-verify, not authority. Also adopt
dev-env-a's harder lesson: handoff notes are an unaudited instruction channel — a handoff
instruction that contradicts a global safety gate (the `GIT_CONFIG_*` unset) must be flagged,
never followed.

**Fix the Claude-flow chaining gaps** (cheap, do with the lane work): drk-02 → drk-03 has no
trigger (announce-only); drk-07 says "the orchestration layer handles fix loops" but no Claude
orchestration layer exists, so QA failures dead-end. Under lane routing, transitions become
explicit anyway — each stage ends with "propose next stage, wait unless pre-authorized by the
lane's contract."

**P1 sequencing, effort, and the cut line.** Recommended order (each item usable without the
ones after it):

| Order | Item | Rough effort | Depends on |
|---|---|---|---|
| 1 | Lane routing + Effort-Anchor enforcement + single-pass Standard challenge | 1–2 sessions | P0.1–P0.2, D1/D10 |
| 2 | drk-02 economics (dispatch budget, growth stop, new-infra escalation, lead adjudication) | 1 session | D2–D4 |
| 3 | Delta-scoped drk-06 + D7 | 1 session | — |
| 4 | Lightweight state files for drk-02/06 | 1 session | — |
| 5 | Vertical-slice ordering + plan-size gate (D5) | ~1 h (prompt edits) | — |
| 6 | Amendment operation (drk-02b) | 1 session | 1 |
| 7 | Handoff re-anchoring + chaining-gap fixes | ~half session | — |

**If you only do three: items 1, 2, 3.** They remove the amplification; everything else is
resilience and polish.

### 4.3 Reviewer and model economics

- **One leaf-reviewer profile per harness.** Every spawned reviewer gets: read-only enforced
  (fail-closed — today five scripts silently fall back to `danger-full-access`), fixed
  model/effort, no skill invocation, no delegation, a process deadline, and structured output.
  The Codex doc's `df-reviewer` recommendation stands; implement it as the pinned agent
  definitions this repo already knows how to ship (`agents/` + `manifests/agents.tsv`).
- **Stop defaulting reviewers to xhigh.** Tier by lane: Standard-lane review at
  medium/high effort; xhigh reserved for High-consequence discovery. The existing
  `drk-reviewer-recheck` (opus/high) shows the mechanism — install it and add siblings.
- **Model diversity over personas — PSTACK's claim, worth testing here.** PSTACK asserts (does
  not measure) that one prompt across model families beats same-model personas. It matches the
  cloud-dev-2 evidence (the one heterogeneous reviewer was the waived Claude round), but treat
  it as a hypothesis: the Standard lane runs diversity-only; High-consequence keeps personas
  for discovery; compare finding quality after a few features before deleting personas
  everywhere.
- **Verifier ≠ worker family** wherever cheap (PSTACK: "Run a unit's verifier on a different
  model family from its worker") — you already have both harnesses wired; make it a rule rather
  than an accident. The Codex flow's drk-04 currently has no diversity at all (Codex inline +
  Codex CLI) — decide via D8.
- **Codex global routing** (in `~/.codex/AGENTS.md`, not this repo): re-default workers to
  `terra_xhigh`/`luna_max` and narrow `sol_high` escalation criteria — "touches
  credentials/auth" cannot be the trigger in a repo where everything does; scope it to
  "changes the trust boundary or invariant," not "reads code inside one."

### 4.4 Risks and reversal tripwires

Two of these changes remove safety mechanisms. Name the failure condition now, so reverting is
a rule, not a debate:

- **Single-pass Standard challenge (D10).** What multi-round challenge was buying, when it
  worked, was requirements-level defect discovery before code exists. Tripwire: if a
  Standard-lane feature ships a requirements-level defect (wrong behavior faithfully
  implemented) that the reviewers' findings show the old loop would plausibly have caught,
  escalate *that feature class* to High-consequence — don't restore rounds globally. Log every
  Standard-lane requirements defect in a running file so the pattern is visible.
- **Credential-review de-minimis tier (D9).** Tripwire: any incident where a diff that passed
  under the de-minimis exemption turns out to have altered credential-path *behavior* revokes
  the tier immediately and the trigger list gets a regression entry. Mitigation: the exemption
  is defined by diff content (docs/comments/log strings only), machine-checkable, never by the
  agent's judgment of "riskiness."
- **Delta-scoped drk-06.** Risk: a fix introduces a defect outside the delta. Mitigation
  already in the design: the full suite still runs (drk-05), and one whole-branch discovery
  round still happens. Tripwire: a post-merge defect traced to un-re-reviewed code adjacent to
  a fix ⇒ widen delta definition (fix + blast radius per PSTACK's `blast-radius` proof ladder),
  not a return to full re-review.

---

## 5. Part B — What to adopt from PSTACK, and what to ignore

### 5.1 Adopt as-is (concepts port cleanly to Claude Code/Codex)

| Mechanism | Source | Where it lands here |
|---|---|---|
| Falsifiable exit predicate declared before any loop; "a duration is not a finish condition"; never relax the predicate to declare victory | `autonomous-run.md`, guide 07 | Every drk loop header; every overnight grant you give |
| Wall-clock land-by rule: at ~70% of budget stop spawning, land what's verified — "finished-but-unlanded work counts as zero" | `orchestrate.md` | Pipeline-level budget; the marathon-turn killer |
| Verification ledger keyed to head SHA / patch-id; new SHA voids the verdict | `orchestrate.md`, `shipping.md` | The cross-stage evidence ledger (Phase 2) |
| Lead adjudication: reviewers advise, lead decides, dismissals are legitimate and stated; Nitpick Gravity; Act-On >5 = under-filtering | `interrogate/references/lead-judgment.md` | drk-02/06 synthesis prompts |
| Retry budgets: one CI retry; two agent retries then abandon and replan around it; terminal handoff instead of infinite retry | `orchestrate.md`, `babysit.md` | All runner scripts + skill loop rules |
| Single writer per worktree/branch; briefs carry TIMEBOX ("on expiry, return partial findings and stop") | `orchestrate.md` | SDD dispatch template + review runners |
| Closed escalation lists: always-pause (irreversible only) vs never-reaches-the-human (retries, flake triage, "should I keep going"); questions parked in durable state with a default-on-no-answer | `poteto-mode`, `orchestrate.md` | The lane contracts; replaces ad-hoc gates |
| Playbook steps copied verbatim into the todo list; skips must be written | `poteto-mode/SKILL.md` | drk skill preambles (anti-drift within a session) |
| Pause-safely / session-pickup: off-context resume note before compaction; prior trail is authoritative — don't re-verify finished work | `pause-safely.md`, `session-pickup.md` | Companion to the state files in §4.2 |
| Proof ladder (5 rungs; below "you ran it" is unproven) | `blast-radius/SKILL.md` | drk-05 evidence standards; review finding verification |

### 5.2 Adopt with adaptation (the environment investments) — with price tags

Rough costs assume your current velocity with agents doing the building; they are estimates to
budget against, not commitments:

1. **create-verification-skill + feature map → `verify-spellguard`.** The biggest strategic
   adoption; directly serves your stated goal (agents able to properly verify what they ship).
   A standing, repo-owned skill that launches the dev stack, drives the dashboard
   (agent-browser/CDP — in place), drives the CLI/TUI (tmux workbench — in place), collects
   evidence, cleans up — plus a **feature map** of dashboard and CLI surfaces. Then invert
   drk-03/07's relationship to it: runbooks stop re-deriving navigation per feature and become
   thin test intents referencing map entries; a `maintain-verification-skill` audit (PSTACK:
   source wave + one live pass, outcome `clean`/`changed`/`blocked`) keeps it current.
   *Cost: ~2–4 sessions to seed the skill and initial map (Spellguard already has most of the
   driving machinery); ~10–15 min of maintenance per landed feature; payback begins with the
   first Standard-lane feature that skips runbook navigation-derivation.*
2. **encode-lessons-in-structure, systematically.** Rule: any finding class appearing in two
   separate reviews becomes a lint, arch test, or CI check within a week, and the reviewers'
   rubrics drop it. Spellguard's BYOK arch test and the CODEX_HOME isolation test (`b70a69810`)
   are the precedents. Among the plausible convergence mechanisms (this, delta-scoping,
   budgets), this is the only one that shrinks the review surface *over time* rather than
   bounding it per-run. *Cost: ~1 h per converted finding class, ongoing; the cadence matters
   more than the batch size.*
3. **Eval the skills.** Extend `just test-runners` toward PSTACK's `eval.md`: scripted scenario
   evals for the loop policies (does drk-02 stop at the dispatch budget? does the growth stop
   fire? does a takeover re-anchor scope?), run on skill changes, graded from transcripts not
   self-report; adopt the observer-effect trick (don't tell the agent under test it's being
   evaluated). *Cost: ~1–2 sessions for the first three evals; add one eval per new policy.
   This is also the durable fix for the drift class of §2.3.*
4. **Benny's shape, on your infrastructure, later.** The pieces exist: Matrix bridge (intake),
   Spellguard dev-stacks (disposable environments), agent-browser (driving), and benny's
   trusted-marker / ownership-gate / budget / fail-closed contract. Sequenced in §8 *after* the
   verification skill exists, because Benny without a feature map is the flailing agent Lauren
   described. *Cost: ~3–5 sessions once Phase 3 is done; near-zero before it (don't start).*

### 5.3 Ignore, and why

- **"No planning / no PRD" as doctrine.** Right for her context (unlimited tokens, a framework
  so constrained that code is cheap to redo, an org absorbing her output). Wrong for a solo
  operator shipping a credential-security product on subscriptions: requirements traceability is
  how you audit what an agent did to a trust boundary. We shrink the PRD's blast radius (lanes,
  size caps, finish-predicate-first) rather than delete it.
- **Automerge and review-on-main.** Top of the trust curve; she says herself there's no
  shortcut. Revisit after the environment investments have run for months.
- **Cursor-specific machinery as written.** `/loop` wake mechanics, `Task` parameters,
  `.mdc` rules files, Graphite/`gt` stack semantics, Bugbot, cursor-team-kit dependencies,
  transcript-path layouts. Port concepts, rewrite text against your harnesses.
- **4-model panels, arenas, and cloud swarms by default.** Panel-of-4 review, N parallel
  candidate implementations, and swarm verification assume someone else pays for tokens. Your
  two-family diversity (Claude + Codex) captures most of the signal at subscription cost;
  arenas are a High-consequence-lane luxury.
- **Banning code comments repo-wide, `unslop`, Comment Sicko.** Taste-level; orthogonal to the
  problem. Cherry-pick if you like the hygiene.
- **"Never block on the human" at PSTACK's aggressiveness.** Its "deferring is the measured
  failure mode" stance is tuned for her trust level. Your incidents ran the other direction —
  keep the closed always-pause list, but for now your High-consequence lane deliberately blocks
  on more than hers.

---

## 6. Spellguard-side changes (the rulebook the pipeline inherits)

Every drk stage re-inherits the full repo bar, so these compound with everything above. The
repo's mechanical gates are mostly bounded and CI-mirrored; the unbounded pressure comes from
five specific places, each fixable:

1. **Extend the baseline rule beyond integration.** "Only NEW failures beyond an `origin/main`
   baseline block your change" exists for integration tests only; unit and Playwright docs say
   the opposite ("a red unit test means a real regression, not a 'known baseline'"), which is
   how inherited red suites become feature scope — dev-env-a's final day was almost entirely
   inherited-fixture repairs. Keep the reproduce-the-baseline discipline (fresh `origin/main`
   worktree, never a remembered known-red list), but apply it to all three suites, with a
   follow-up-issue path for pre-existing reds.
2. **Write the focused-run doctrine.** AGENTS.md currently says "Locally, keep running this — it
   is the whole suite" with zero focused-run guidance. Add: mid-task iteration uses focused
   vitest runs on the touched area; the full suite runs at pre-commit; and document the local
   4-way shard invocation (the no-`--` form CI uses) for the landing gate (~25 min → ~8 min).
   Batch independent landings into shared gate runs.
3. **De-minimis tier for the credential-flow review** (decision D9, tripwire §4.4).
   Docs/comment/log-string-only diffs inside credential paths get a stated, machine-checkable
   exemption; fix the skill's over-broad bare `decrypt|unwrap` grep to match the checklist's
   actual trigger list. The full 4-sandbox `qa:cross-plugin` machinery is for changes that
   alter behavior on a credential path.
4. **Promote the proportionality precedents into normative guidance.** "Further looping had
   negative expected value" and "Approved-with-open-items" as a sanctioned terminal state exist
   only inside committed *report artifacts* — an implementing agent never loads them. Put both
   into AGENTS.md next to the Tested-E2E bar (which already carries the BLOCKED-means-stop
   rule), so the maximalist language ("ALL features — no exceptions") is read alongside
   sanctioned stopping points.
5. **Handoff conventions.** Committed handoffs may state scope and point at artifacts; they may
   not embed per-checkpoint review-loop mandates (the tui-parity handoff runs "the Dark Factory
   back-half … as an inner loop at each checkpoint") and their scope sections are claims the
   consumer must re-anchor (§4.2). Add the rule that a handoff instruction contradicting a
   global safety gate is a blocker to surface, not an instruction to follow.
6. **Grow the hard-enforcement layer** (encode-lessons-in-structure, §5.2): candidates visible
   right now — process/thread isolation for framework-launching tests (generalize `b70a69810`
   into a repo-wide arch test as dev-env-a recommended), error-boundary/logging conventions
   (the class that seeded the cloud-dev-2 PRD explosion), import-boundary checks between
   packages (Lauren's electron-main/renderer pattern).
7. **Bound the doc-update step.** "Update `README.md` and the latest `docs/spellguard-*.md`" has
   no completion criterion against a 111 KB README; scope it to "sections whose behavior your
   diff changed."

---

## 7. Harness tailoring — yes, the flows should differ (they already do)

The short answer: keep both flows, differentiate them *deliberately*, and share one policy
core. The Codex flow gets tighter budgets and mandatory checkpoints because Codex executes
process maximally faithfully (both runaways were Codex-driven; Session B showed the same skills
at lower amplitude on Claude). The Claude flow's most urgent gap is control, not economics: it
has no orchestrator and no override rule, so Superpowers' own chaining (SDD →
finishing-a-development-branch) wins whenever the one injected "final task must be drk-05"
sentence gets dropped. And the current duplication of policy text between `skills/` and
`codex-skills/` is exactly how the two drk-02 generations diverged — lane definitions, budgets,
escalation lists, and ledger schemas should live once, referenced by both.

Genuinely tabular differences:

| Dimension | Claude Code flow | Codex flow |
|---|---|---|
| Orchestration | Stage skills + explicit propose-next gates now; master orchestrator in Phase 4; add the override rule the Codex side already has | `dark-factory-codex` keeps explicit stage control; wire budgets/ledger into it |
| Cross-model reviewer | Fresh `codex exec` under the leaf profile | Interactive Claude tmux (your `claude -p` prohibition stands), with the same leaf constraints + a deadline/reaper — today a timed-out session is left running |
| Worker routing | SDD's cheapest-capable ladder already manages cost | Fix the global `sol_high` default inversion (§4.3); pipeline dispatches name agents explicitly |
| Amplitude calibration | Standard lane can afford looser checkpoints | Tighter dispatch budgets; checkpoints mandatory; usage-limit stops stay load-bearing |
| Known bugs | `~/.claude/agents/` missing (P0.1) | Luna spawn bug #36294 keeps the cheap tier unreachable — budget assuming Terra is the floor |

**Token budgets as a gate (subscription reality).** One feature consumed 54% of a weekly Codex
window before being stopped. The goal: phases carry token budgets the way drk-02 carries round
caps. Honesty about the mechanism: today the runners only *detect usage-limit exhaustion*, not
consumption rate — mid-run metering on subscription harnesses is not yet instrumented. So treat
the token-budget gate as **aspirational until Phase 0's event logging proves it measurable**;
in the meantime the wall-clock budget and dispatch budget are the enforceable proxies (they
correlate with spend and are countable today).

---

## 8. The real path to Level 4 (re-sequencing the roadmap)

The README's Level-4 gap list (master orchestrator, autonomous brainstorming, knowledge base,
security pipeline, ADRs) measures maturity by *pipeline autonomy*. The evidence of the last two
weeks says the pipeline autonomy you already have exceeds the trust and control you have. Lauren
measures maturity by *environmental trust* — and her endpoint (Benny; PMs shipping features the
architecture makes safe) is exactly your "bot others in the org can talk to."

Re-sequenced roadmap:

- **Phase 0 — Truth (this week).** §4.1 items 1–4; structured event-per-dispatch logging in the
  runners. Then run one Standard-lane-sized feature end-to-end as a baseline with the hardened
  skills actually live — this run also re-measures the per-task-review overhead (§2.4) and
  tests whether token consumption is meterable (§7).
- **Phase 1 — De-amplify (next 1–2 weeks).** The §4.2 sequence table, in order, with its cut
  line; §4.3 reviewer profiles. *Exit criterion: a Standard feature ships in roughly
  Effort-Anchor × the re-measured review multiplier, not 10–20×.*
- **Phase 2 — Durable control (following 2–3 weeks).** The cross-stage evidence ledger keyed to
  artifact SHA (deduplicating SDD / drk-05 / drk-06 verification); wall-clock budgets wired
  into both flows; token metering if Phase 0 proved it measurable; Spellguard rulebook changes
  (§6 items 1–5). *Exit criterion: kill and resume any stage mid-loop with zero duplicate
  dispatch; restart-after-compaction simulations clean.*
- **Phase 3 — Environment (ongoing, the PSTACK-shaped investment).** `verify-spellguard` +
  feature map + maintain audit; encode-lessons-in-structure cadence; skill evals (§5.2 with
  price tags). *Exit criterion: drk-07 runs off the feature map; at least the top-3 recurring
  review finding classes are CI-enforced and dropped from rubrics.*
- **Phase 4 — Scale up (only after 1–3 hold).** Claude master orchestrator *with lanes and
  budgets built in*; then the Benny-alike. Concretely, the bot's v1: a teammate sends a bug
  report to a Matrix channel; a triage skill classifies it and posts one verdict; on your
  approval marker (trusted-marker contract, benny-style), a bounded Quick-lane agent reproduces
  it on a throwaway dev-stack, fixes it, and opens a **draft PR** — merge authority stays with
  you, fail-closed at every joint. *Intermediate milestone that makes this testable: one
  teammate files one real bug through the bridge and gets a draft PR without your involvement,
  while you watch. Run supervised for weeks before widening scope; "without me intervening"
  means intake-to-draft-PR, not merge.*

The through-line: **every token the de-amplification saves gets reinvested in the environment.**
That's the trade Lauren actually made, translated to a subscription budget.

---

## 9. Measuring whether this worked

Adopt the Codex doc's scorecard, trimmed to what you'll actually track, plus the
feedback-doc signatures:

| Metric | Baseline (from the forensics) | Target direction |
|---|---|---|
| Intent-to-spec multiplier (PRD words out / drk-01 words; plan tasks vs anchor) | 14.6×; 24 tasks for a 2–4 h ask | ≤2× enforced |
| Wall-clock per feature vs Effort-Anchor | ~47 h vs 2–4 h intent | ≤3× anchor without an explicit contract |
| Challenge/review dispatches per feature | ~216 followups to challenge personas | Within dispatch budget |
| % of weekly token window per feature | 54% (one feature, one harness) | Tracked once meterable (§7); ceiling enforced |
| Time-to-first-user-visible-slice | Never (35 h) | Within first third of budget |
| Review-caught production faults per feature (keep-metric) | 5 suite-green faults (n=1) | Re-baseline in Phase 0; non-decreasing |
| Duplicate dispatch after restart/compaction | Repeated re-priming (52 skill re-reads) | Zero |
| Recurring finding classes converted to CI checks | 0 | Steady accumulation; rubrics shrink |

---

## Appendix A — Mechanical defect list (from the machinery audit)

Small, unambiguous fixes independent of any redesign decision (items 1–4 are P0.4):

1. drk-06 Claude reviewer prompts + synthesis prompt point at stale
   `.claude/tmp/branch-diff.txt` / `.claude/tmp/codex-*.md`; SKILL.md writes
   `/tmp/dark-factory-review/branch-diff.txt`.
2. drk-06 Claude flow uses a fixed shared scratch path (concurrent-run clobbering) — the exact
   bug drk-02 fixed with run-scoped `REVIEW_ROOT`; the drk-06 Codex flow already has the fix.
3. Warn-only output validation in drk-04/drk-06 codex runner scripts (empty review ⇒ silent
   pass); drk-02's fail-closed status-file contract is the template.
4. Five reviewer scripts fall back from `--sandbox read-only` to `danger-full-access` when
   `unshare --net` is unavailable; the Codex-flow drk-04 runner shows the fail-closed
   alternative ("review helpers must not silently become write-capable").
5. `agents/drk-reviewer-recheck.md` uninstalled because `~/.claude/agents/` doesn't exist;
   hardened drk-02 then falls back to discovery tier (noted in its report, but with no stop) —
   an *upgrade*, the wrong direction.
6. drk-01's PRD template predates drk-02's structure rules: no Pinned Parameters, no Decision
   Register, no "Known open items", Status enum missing "Approved with open items".
7. drk-02 → drk-03 transition is announce-only in the Claude flow; drk-07 references an
   orchestration layer that doesn't exist there.
8. drk-05's outer convergence loop and e2e-coverage gate have no iteration cap (per-item cap is
   3; the loops around it are unbounded).
9. Claude-flow drk-06 hardcodes base branch `main`; the Codex flow's default-branch detection is
   the better version.
10. Timed-out Claude tmux reviewer sessions are deliberately left running for inspection but
    have no owner/reaper — orphaned interactive sessions burning quota.

## Appendix B — Where each conclusion comes from

- Over-compatibility diagnosis, 15-round/14.6× data, Session B corroboration, the 12 candidate
  fixes: `docs/cloud-dev-2-feedback.temp.md`.
- Unbounded review loops, 41 h turn, sol_high inversion, handoff poisoning, baseline-rule
  violation, 6 recommendations: `docs/dev-env-a-feedback.temp.md`.
- Lane/budget/ledger frame, phased plan skeleton, scorecard: `docs/2026-08-27-dark-factory-vs-pstack.md`
  (with §3.2's corrections).
- PSTACK mechanisms and quotes: direct read of the `cursor/plugins` snapshot (playbooks,
  principles, interrogate/lead-judgment, orchestrate store, shipping/babysit, benny pack).
- Trust curve, enforcement hierarchy, feature map, evals, token-ROI: the talk transcript.
- Machinery map, caps inventory, drift table, defect list: direct read of
  `/home/dev/dark-factory` and installed skill copies on this VM.
- Spellguard rulebook analysis: `origin/main` @ `6843f38` worktree
  (AGENTS.md, docs/reference standards, verify-pr.yml, committed drk artifacts).

## Appendix C — Revision 2 changes (review findings applied)

An adversarial fact-check (verifying every quote, number, and mechanism claim against the
sources above) and a utility review were run on revision 1. Applied: corrected the false claim
that a runaway ran on this VM (the *installed stack* is stale; both runaways ran elsewhere, one
on the hardened generation); corrected the cap-exemption list (consistency-only passes DO count
as rounds in the current repo skill); converted a paraphrase-as-quote of the talk to the real
words; acknowledged AGENTS.md already carries BLOCKED-means-stop; added the decisions box,
P1 sequencing/cut line, risk tripwires (§4.4), environment price tags, the drk-03/04 lane
assignments, the incidents legend, token-metering honesty, n=1 calibration on the per-task
review and personas claims, and the testable Benny milestone; deduplicated P0.4 against
Appendix A.
