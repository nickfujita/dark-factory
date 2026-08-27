# Workflow Churn Analysis — cloud-dev-2 / spellguard-internal / managed-vm-operations

> One file per analyzed session-set, same headings on every VM, so the reports
> can be concatenated into a cross-fleet assessment. Sections: Metadata, Verdict,
> Timeline, Cost, Mechanism, Hypotheses, Worker-quality evidence, Contributing
> factors, Companion Claude Code session, Recommendations.
>
> This VM contributes **two sessions on the same feature**: the original Codex
> Sol-orchestrator run (Session A, analyzed in depth) and the Claude Code
> takeover that inherited the branch (Session B, analyzed for corroboration and
> additional findings). Together they give a rare same-feature, cross-harness
> comparison.

## Metadata

| Field | Value |
| --- | --- |
| Machine | cloud-dev-2 (Spellguard:cloud-dev-2) |
| Repo / branch | `spellguard-internal` / `feat/managed-vm-operations` |
| Harness | Codex TUI 0.147.0, orchestrator model `gpt-5.6-sol`, effort `xhigh` |
| Workflow under test | Dark Factory (drk-01 … drk-07) + superpowers-style gates, Sol-orchestrator multi-agent pattern from `~/.codex/AGENTS.md` |
| Session | `01a036bd-9ac5-70a3-9615-3543a8378a1e` (`~/.codex/sessions/2026/08/25/rollout-2026-08-25T02-26-30-….jsonl`, 41 MB, 15,768 records) |
| Wall clock | 2026-08-25 02:28 UTC → 2026-08-26 13:15 UTC (~35 h, continuous — max idle gap 5 min) |
| Original ask | Pageable activity log as a tab on the agent-details page for EC2 managed agents + style the (currently unstyled) hibernate config panel |
| Outcome | Stopped by operator. 7 of 24 planned tasks done + Task 7A in flight; **UI/API never started**; handed off via `docs/handoffs/handoff-managed-vm-operations.md`, draft PR #574 |

## Verdict (one paragraph)

The session never stalled and worker-model mistakes were secondary. The dominant
failure is **unbounded scope amplification by the pipeline itself**: the drk-02
PRD challenge ran 15 adversarial rounds and grew the PRD **4,265 → 62,445 words
(14.6×)**, which mechanically produced a 24-task implementation plan, each task
gated by TDD RED→GREEN + independent `sol_high` review + remediation rounds.
This is not Sol/Luna/Terra being "incompatible" with the skills — it is the
opposite: a highly instruction-following model executes a ratchet-shaped process
with no brake. No gate anywhere in the pipeline asks "is this proportionate to
the request?"

The Claude Code takeover session (Session B, below) independently reached the
same root cause from the inside — "the workflow isn't the balloon, the PRD is,"
a 10–20× multiplier over the operator's stated intent (a 2–4 hour task) — and
added a second-order finding: **inflated scope is sticky across handoffs**. The
senior takeover agent, explicitly told not to blindly follow the plan,
re-validated the *code* against the PRD but treated the PRD itself as the
operator's settled decision, and only flagged the intent/spec mismatch when the
operator directly asked why everything was so slow.

## Timeline

| Phase | Window (UTC) | Duration | What happened |
| --- | --- | --- | --- |
| Brainstorm + PRD interview (drk-01) | 08-25 02:28–05:40 | ~3.2 h | Interactive with operator; PRD lands at 4,265 words. Healthy. |
| **PRD challenge (drk-02)** | 05:42–16:40 | **~11 h** | 15 rounds (A1–A15), ~45 PRD revisions (R-numbers to R45), 128 findings dispositioned, ~61 orchestrator→persona messages per persona. PRD ends at 62,445 words. Claude rounds waived (operator out of Claude usage). |
| QA runbook + arch docs + plan (drk-03…) | 16:43–18:40 | ~2 h | Implementation plan of **24 tasks**. |
| Implementation + review loops | 18:43 → 08-26 13:08 | **~18 h** | Tasks 1–7 + inserted 7A. Each: TDD RED→GREEN, independent review, 1–4 remediation rounds. Task 2 alone: ~4 h, 4 review rounds. |
| Handoff | 13:08–13:15 | — | Operator stopped it ("doing okay, just taking way too long"); handoff doc committed as `2147bfa13`. |

Operator touchpoints after launch: one check-in at 08-25 15:47 ("you've been
running for almost 2 days it feels like") followed by an explicit grant of
unbounded autonomy at 15:49 ("take this through the full dark factory flow until
the end, I wanna wake up to a PR ready"). Next contact 08-26 13:06.

## Cost

- Orchestrator session alone: **298.9 M input tokens** (294.7 M cached), 675 k
  output tokens — **54% of the weekly Codex rate-limit window** consumed, plan
  `pro`, credits at 0.
- 12 context compactions in the orchestrator (5 of them inside the PRD-challenge
  phase, roughly one every 45–50 min).
- Subagent traffic: 31 `spawn_agent`, **251 `followup_task`** (216 of them to
  the three PRD-challenge personas + the a8 remediation worker), 735
  `wait_agent` polls, 1,120 exec calls.
- The three PRD persona subagents have their own rollouts of **87 MB / 59 MB /
  40 MB** — each re-read the ever-growing PRD dozens of times.

## Mechanism — the ratchet with no brake

1. **A completeness mandate in the ask.** The feature was modest, but one
   operator sentence ("fill any and all logging gaps … so we never miss any
   states; errors need a catch boundary that logs") gave adversarial personas an
   inexhaustible mining vein.
2. **Remediation adds mechanism; mechanism breeds findings.** Each round's
   fixes introduced new infrastructure into the PRD — Queues, DLQs, R2 budgets,
   write-ahead carriers, generation-fenced alarms, admission permits, UUIDv5
   digests, signing-key rotation, watchdog queues, a 131-entry "producer
   manifest" with a reverse census of 79 catch sites. The next round then found
   *technically real* Critical/High gaps in that newly added prose. The skill's
   `SELF_FEEDING_THRESHOLD` (50%) never tripped in practice because the findings
   were legitimate against the new text; the loop was finding real bugs in
   requirements it had itself invented.
3. **Soft caps soften.** `PHASE_A_SOFT_CAP` is 10 rounds + 2 convergence
   extensions; the run reached A15 (consistency-only passes and delta
   verifications don't count against the cap). Word growth (`GROWTH_WARN_ROUND_PCT`
   15%) is only *flagged*, never enforced.
4. **Downstream inherits the inflation.** A 62 k-word PRD ⇒ 24 tasks ⇒ per-task
   independent reviewers correctly reject work against that standard ⇒ 1–4
   remediation rounds per task ⇒ ~18 h for 7 tasks, all backend, zero UI.

## Operator's two hypotheses, evaluated

**H1: "Codex 5.6 (Sol/Luna/Terra) is incompatible with superpowers/dark-factory
skills."** Rejected as stated, but directionally onto something: the models are
*over-compatible*. These process skills were implicitly calibrated for models
that half-follow instructions and need pushing toward rigor. Sol xhigh follows
the loop's letter perfectly and never exercises the judgment the skills silently
relied on ("obviously stop, this is a dashboard tab"). A more obedient, more
thorough model turns a ratchet-shaped process into an infinite ratchet. Expect
the same pathology on Claude-driven runs of the same skills, with lower
amplitude.

**H2: "Luna/Terra subagents aren't good enough and make too many mistakes."**
Secondary at most. Real worker fabrications occurred (see below), but they
concentrated in task shapes that maximize hallucination for any model
(hand-enumerated exhaustive source censuses). The 251 followups look like
worker-correction churn, but 216 went to PRD-challenge personas — the churn was
the challenge loop, not the implementers. Also note the environment: the known
Codex bug blocks Luna spawns under a Sol parent, so implementation fell to
Terra/Sol-high anyway.

## Worker-quality evidence (for the cross-VM aggregate)

- Task 2 ("event and producer contract"): 4 review-remediation rounds over ~4 h.
  Reviewer findings included a "94-entry census with guessed/nonexistent
  boundaries", a fabricated-but-self-consistent UUID pair accepted by
  validation, and manifest entries gaining authority fields through defaults.
  Final state: 131-entry source-anchored manifest, 153 tests. The mistakes were
  real, but the assigned artifact (a model-enumerated exhaustive inventory) is
  hallucination bait by construction.
- Tasks 1, 3–6: 1–2 review rounds each; reviewers found substantive but bounded
  gaps. Task 7: 2 remediation rounds, both closing genuine lifecycle/retry-
  metadata gaps.
- Escalation rule worked as designed (round 4 of Task 2 got fresh `sol_high`
  eyes) — but "worked as designed" here means it spent more hours polishing an
  invented requirement.

## Contributing factors specific to this run

- Claude cross-model review rounds were waived (usage exhausted) — removed the
  one heterogeneous reviewer that might have flagged the scope explosion.
- Operator instruction at 15:49 explicitly authorized running the full flow to
  completion overnight; the session took it literally and reported nothing for
  ~21 h.
- No vertical-slice ordering: the plan front-loaded 24 backend "integrity"
  tasks; the user-visible tab (the actual request) was scheduled last, so 35 h
  produced zero visible product.

## Session B — Claude Code takeover of the same feature

| Field | Value |
| --- | --- |
| Session | Claude Code `f4f39420-52c6-431b-8e64-2702f9bde4cb` (same project dir) |
| Config | Fable 5 (high effort) as orchestrator + reviewer; **Opus implementers** per operator directive at 13:56 ("you are the orchestrator and reviewer and opus is implementor") |
| Started | 2026-08-26 13:24 UTC — nine minutes after the Codex handoff commit |
| Brief | "Take over … as the senior on the team … review the feature branch, the plan, compare to the code written so far … Don't blindly follow" |
| Progress | 7/24 → 11/24 tasks in ~12 h (vs. 7/24 in 35 h for Session A), everything landed to PR #574 with full gates |

### Corroborating findings (their own words, condensed)

- **Per-task agent-time**, from their task records: 7A finish ~1h26m + 35m
  gates; Task 8 ~4h24m; Task 9 ~1h48m; Task 10 ~4h14m across 7 rounds; Task 11
  ~2h35m and counting. Landing gates ~30–35 min per landing.
- **The review-remediation loop was judged worth it on this side**: overhead
  estimated at ~1.5×, having caught **five would-be production faults** that all
  passed the full 16.7k-test suite first (a sweep that silently no-ops
  production recovery; a global-fence alarm on routine EC2 retries; fresh agents
  never receiving a `power_policy_revision`; recovery cold-boots permanently
  unadmittable; a safety-disable starvation). Key nuance for the aggregate:
  per-task independent review ≠ the runaway cost; the multi-round *requirements*
  challenge is.
- **The PRD-vs-intent gap, quantified side by side**: operator intent "insert an
  event row on sleep/wake; if it fails, shrug" vs. PRD "refuse to power the VM
  unless recording is provable — HMAC-signed admission permits + alarm/taint
  state machines"; "`ORDER BY time DESC LIMIT 25`" vs. "snapshot-frozen
  pagination under REPEATABLE READ with signed opaque cursors"; "move controls
  into a tab" vs. "full ARIA semantics, a router migration, and 94 P0 browser
  test cases." Their estimate: a 10–20× multiplier over the described product.
- **Tasks weren't slow, they were bigger than the plan said**: tasks 8/10/11
  each hit real contract gaps inherited from tasks 1–7 — the inflation debt
  surfacing as "expansion" one task later. Scope inflation compounds downstream.

### Additional findings unique to Session B

1. **Scope is sticky across handoffs.** The takeover agent read the handoff's
   "operator intent and locked scope" section, took the hardened PRD as the
   operator's settled decision, and optimized for faithful delivery — despite an
   explicit "don't blindly follow" in its brief. Its own retrospective: "I
   should have flagged the mismatch in my takeover plan instead of just
   estimating 3–5 days against it." Handoff docs that freeze scope launder the
   amplification into authority.
2. **Mechanical waste independent of scope**: implementation workers ran the
   full 25-minute unsharded unit leg mid-task when focused suites sufficed, and
   the local landing gate ran the suite unsharded even though CI shards it
   4-way (~25 min → ~8 min locally). Landings were also serialized when they
   could batch. Small next to the scope multiplier, but pure waste.
3. **Mid-flight de-amplification works and is cheap.** Once the operator stated
   the 2–4 h intent, the session produced a surgical, ID-traceable **PRD/QA
   amendment** ("lite read plane", 94 → 15 browser cases, risks-accepted
   section), got it signed, recomputed the pinned hash, and re-planned to a
   ~2-day track — without discarding the landed backend (which stays dark until
   the bindings task). Amend-downward beats restart, and the pipeline should
   offer it *before* the operator has to ask.
4. **Cross-harness amplitude difference confirmed with a confound.** Claude ran
   ~2.9× faster per task with the same per-task review rigor, supporting the
   operator's "Codex is more thorough → more exacerbated" intuition — but
   Session B never ran drk-02; it inherited the inflated PRD. The harness
   difference shows mostly in loop *amplitude* (15 challenge rounds, 45
   revisions on Codex), while the vulnerability — no proportionality gate,
   sticky inherited scope — is harness-independent.

## Recommendations (candidate fixes to fold into the shared workflow)

1. **Proportionality gate at the front.** Classify the feature S/M/L before
   drk-02. Small/medium UI features get a "lite" challenge (1–2 rounds, no
   new-infrastructure remediations). Reserve the full multi-round flow for
   genuinely high-consequence surfaces (credential/BYOK boundaries, migrations).
2. **Hard growth stops, not warnings.** PRD may not exceed ~2× its hardened
   input size; a round whose Critical/High findings are majority-against-
   remediation-added-text terminates the loop as *non-converging* and escalates
   to the operator instead of extending.
3. **New infrastructure = escalation.** A remediation that introduces a new
   Queue/DO/R2/key-scheme/watchdog into the PRD requires operator sign-off; it
   is a scope decision, not a wording fix.
4. **Gate the plan size.** Operator sign-off required when the implementation
   plan exceeds N tasks (e.g. 8) or the estimated wall clock exceeds a budget.
   The 24-task plan existed by hour 16 — a checkpoint there saves 18 hours.
5. **Wall-clock checkpoints with scope deltas.** Every few hours the
   orchestrator reports "PRD now X words, plan is Y tasks, Z% budget consumed —
   continue?" instead of running silent under a blanket "until the end" grant.
6. **Vertical slice first.** Deliver the user-visible surface early (or in
   parallel), so long runs cannot end with zero visible product.
7. **Ban model-enumerated exhaustive censuses.** Inventories (producer
   manifests, catch-site censuses) must be generated by a script from source and
   then reviewed — this is where genuine worker errors concentrated.
8. **Token/cost budget as a first-class gate.** This one feature consumed >54%
   of a weekly Codex window before being stopped; phases should carry token
   budgets the way drk-02 already carries round caps.
9. **Re-anchor scope at every handoff.** (From Session B.) A takeover agent
   must re-derive the operator's intent from the *original request*, diff it
   against the inherited PRD/plan, and surface any multiplier ≥2× before
   estimating or implementing — "locked scope" sections in handoff docs are a
   claim to re-verify, not an authority. "Don't blindly follow" in a brief is
   not enough; make the intent-vs-spec diff a mandatory takeover artifact.
10. **Build the amendment path into the flow.** (From Session B.) drk skills
    should treat a signed, ID-traceable PRD/QA *downward* amendment as a normal
    mid-flight operation — proposed proactively whenever measured cost diverges
    from the operator's stated effort expectation — rather than something the
    operator must trigger by asking "why is this slow?"
11. **Keep the per-task independent review; fix its mechanics.** (From Session
    B.) At ~1.5× overhead it caught five suite-green production faults on one
    feature — it is not the runaway cost and should survive any de-scoping.
    But: workers run focused suites only (never the full unit leg mid-task),
    landing gates use the CI sharding locally (~25 min → ~8 min), and
    independent landings batch into shared gate runs.
12. **Capture the operator's effort expectation up front.** The operator's
    anchor ("if I did this myself: 2–4 hours") existed from the start but was
    never recorded in PRD or plan. Ask for it in drk-01, write it into the PRD
    header, and alarm any phase whose projected cost exceeds it by a fixed
    multiple.

## Aggregation notes

- Signature to look for on other VMs: (a) PRD/plan word-count multiple between
  drk-01 output and drk-02 output; (b) round count vs. `PHASE_A_SOFT_CAP`;
  (c) share of `followup_task` traffic going to challenge personas vs.
  implementers; (d) whether the user-visible slice ever shipped; (e) tokens
  consumed vs. plan window; (f) operator's stated effort expectation vs. actual
  spend (here: 2–4 h intent vs. ~47 h across two harnesses, still unfinished);
  (g) on handoff/takeover sessions, whether the successor re-anchored scope or
  inherited it unchallenged; (h) per-task independent-review overhead multiple
  and review-caught-fault count (here ~1.5× and 5 faults — evidence the
  per-task review is *not* the pathology).
- On this VM the sibling rollouts of the persona subagents
  (`rollout-2026-08-25T05-42-*.jsonl`, 40–87 MB each) confirm the same pattern
  from the inside; the 47 MB `09-23-37` rollout is the a8 remediation worker of
  the same flow.
