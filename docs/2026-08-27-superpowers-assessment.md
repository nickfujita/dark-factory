# Superpowers Assessment — Currency, Relevance, and the Pin-and-Trim Verdict

**Date:** 2026-08-27 · Companion to `2026-08-27-dark-factory-course-correction.md` (CC).
Produced by a dedicated investigation (installed plugin vs upstream HEAD, per-skill relevance
against the forensic evidence and PSTACK equivalents); headline claims spot-verified
independently (byte-level diff, release-note quotes, SDD chain text).

Shorthands: **SP** = installed superpowers 6.3.0
(`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills`), **CD2/DEA** = the
two forensic feedback docs, **CC** = the course-correction report, **PSTACK** = the
cursor/plugins snapshot.

## 1. Currency: installed 6.3.0 IS upstream HEAD — and upstream is de-ceremonializing

- `diff -rq` between the installed skills tree and a fresh clone of
  github.com/obra/superpowers HEAD (`b36e082`, "Release v6.3.0", 2026-08-12): **zero
  differences**. There is nothing newer to adopt.
- The local cache holds `5.1.0, 6.1.1, 6.2.0, 6.3.0` — this VM walked up through four
  generations, and the 6.x line rewrote exactly the mechanisms the forensics complain about:
  - **v6.0.0:** "The old flow ran two reviewers per task… both turned out to be expensive and
    easy to game. The new flow runs one reviewer per task… One broad review at the end."
    Their evals: "roughly twice as fast and while spending almost 50% fewer tokens."
  - **v6.2.0:** SDD gained the plan-scoped on-disk ledger (compaction fix), resume-based fix
    loop, and "a five-round circuit breaker with controller adjudication."
  - **v6.3.0:** brainstorming's three-path router ("Ceremony now scales to the task… small
    tasks skip the two-document ritual"), "Controllers no longer stall on plan conflicts"
    (one donated session "had sat blocked for almost nine hours"), micro-task batching, and a
    ban on worker-spawned reviewers.
- **Upstream is converging on the course-correction's conclusions** (budget-shaped caps,
  controller adjudication, ceremony scaled to task size, eval-driven cuts). What it has NOT
  moved on: the `using-superpowers` compulsion layer (the 1%-rule), TDD's Iron Law absolutism,
  and brainstorming's approval-gate-on-every-path with a one-way heavier-path ratchet ("When
  in doubt between two paths, take the heavier one… Nothing downgrades mid-task").

### Forensic correction that falls out of this

DEA:92–95 claims "No layer of the stack sets a maximum number of review rounds, a severity
floor for blocking, or a rule that reviews only run on frozen trees." That is **false against
installed 6.3.0 SDD** (hard 5-round breaker at SP/subagent-driven-development/SKILL.md:372–373
+ 410–429; Minor findings never enter the loop; exactly one final fix wave, :458–469). Either
dev-env-a ran a pre-6.2.0 generation (plausible given the cache history — 5.x SDD had none of
this), or its loops ran *outside* SDD (DEA's own detail supports this: the runaway was four
whole-branch reviews + findings-to-scope conversion, which 6.3.0 SDD explicitly forbids).
**Action either way: extend CC's P0 attestation to record the superpowers version per VM** —
not knowing the running generation has already corrupted one forensic conclusion.

## 2. Per-skill verdicts

| Skill | Verdict | Core reason |
|---|---|---|
| brainstorming | **REPLACE in-pipeline** (keep for ad-hoc work) | Duplicates drk-01's interview and drk-04's sign-off minutes after they happened; its HARD-GATE ("the ceremony scales with the task; the approval gate never does") and one-way heavier-path ratchet fight the lane design. Fork a `df-design` stage: PRD-fed, architect-style type/signature sketch (steal PSTACK architect's rationale-template + design-red-flags), approvals folded per lane. |
| writing-plans | **KEEP-TRIMMED** | It's SDD's input format and makes cheap implementers viable ("the implementation is transcription plus testing"). Trim = inject the D5 plan-size gate and vertical-slice ordering at the drk-04 handoff (already planned in CC §4.2). |
| subagent-driven-development | **KEEP-TRIMMED** — the measured-value core | The only component with a measurement in its favor (~1.5× overhead, 5 suite-green faults caught; both forensics exonerate it). Trims: (1) skip SDD's final whole-branch review when drk-06 follows; (2) don't delete the SDD workspace/ledger until drk-06 consumes it (today it's `rm -rf`'d before drk-06 runs — CC Phase 2's evidence ledger, nearly free here); (3) terminal is drk-05, stated in Dark-Factory-owned skill text, not a handoff sentence. |
| executing-plans | **DROP from the chain** | Itself prefers SDD when subagents exist; hard-wires the finishing chain; never appears in the forensics. |
| test-driven-development | **KEEP (Standard/High lanes)** | "Bounded TDD worked" (DEA). For the Quick lane adopt PSTACK tdd's escape hatch (skip-with-stated-reason + closest executable check; "Prefer no new test over a bad test") instead of SP's ask-permission model. |
| requesting-code-review | **KEEP-TRIMMED** | Template/mechanics provider for SDD's final review. Its before-merge review mandate duplicates drk-06 — review *policy* lives in the lane table. |
| receiving-code-review | **KEEP** | The one SP skill pushing against the ratchet (verify findings, push back, YAGNI check that kills findings-to-scope conversion). Extend with PSTACK's Nitpick Gravity + Act-On>5 language (CC §4.2). |
| verification-before-completion | **KEEP-TRIMMED** | Load-bearing evidence-before-claims. Trim: "Execute the FULL command" reads as full-suite-mid-task to an obedient model (plausible contributor to CD2's 25-min unsharded runs); define per-lane which command proves which claim. |
| finishing-a-development-branch | **REPLACE** with `df-open-pr` | Its merge menu is half-forbidden by the operator's global git rules; it's the terminus SDD hard-wires, overridden today by one fragile sentence. Replace with a small owned finish skill: push, open PR per PSTACK `opening-a-pr.md` format (Why/Scope/Tradeoffs/Blast Radius/Verification), keep the worktree, carry over finishing's cleanup guard verbatim. Closes the chaining hole permanently. |
| using-git-worktrees | **KEEP** | Self-limiting; enables origin/main baselines. |
| systematic-debugging | **KEEP** | A converging loop (3 failed fixes → stop and question architecture). Steal PSTACK bug-fix's "reproduce it yourself on the matching surface first." |
| dispatching-parallel-agents | **KEEP** (reference) | Prompt-crafting guidance; the DEA anti-pattern (parallel reviews on a changing tree) is the caller's fault — fix is drk-06's frozen-tree rule. |
| using-superpowers | **NEUTRALIZE for pipeline sessions** | The compulsion layer ("even a 1% chance… you ABSOLUTELY MUST") is the root busy-work generator with over-compatible models — but it contains its own escape valve: "User instructions (CLAUDE.md, AGENTS.md…) take precedence over skills." Put the override in text Dark Factory controls. |

## 3. Structural assessment: à la carte is stable in the middle, fragile at the ends

The chain is hard-wired at four joints: brainstorming → writing-plans ("Do NOT invoke any
other skill"); writing-plans → SDD **baked into every plan artifact's header** ("REQUIRED
SUB-SKILL: Use superpowers:subagent-driven-development…") so any future session re-enters the
chain from the document alone; SDD → finishing-a-development-branch; and `using-superpowers`
re-arms the graph every session via the SessionStart hook — surviving compaction better than
Dark Factory's countermeasure does (DEA measured the SDD skill re-read 52 times, once per
compaction, while the "final task must be drk-05" sentence lives in one drk-04 chat message
that compaction can drop).

Leaf skills (worktrees, TDD, debugging, VBC, receiving-code-review, dispatching) compose
freely. The spine is a conveyor belt: adopt any segment and you inherit pulls toward its
neighbors that only durable, Dark-Factory-owned text can counteract.

If superpowers were dropped entirely, Dark Factory would have to grow ~1.5–2k lines of forked
prose (worktree discipline, plan format, SDD's dispatch machinery + 3 scripts + 3 templates,
TDD guidance, verification rules, finish step, debugging) — all MIT-forkable, but the operator
would then maintain it alone and forfeit upstream's eval-driven iteration at exactly the
moment upstream is converging on his conclusions.

## 4. Bottom line

**Pin and trim, plus two surgical forks. Not keep-as-is, not drop, not a PSTACK transplant.**

The forensic evidence does not convict superpowers: both runaways were drk-02's multi-round
challenge and orchestrator-level review-to-scope conversion under Spellguard's rulebook, and
both reports exonerate the SP piece the pipeline leans on hardest (per-task SDD review).
Installed 6.3.0 is current, and upstream's last three releases cut ceremony in the same
direction as the course correction.

1. **Pin 6.3.0 and attest the version per VM** alongside the P0 drk-skill attestation.
   Marketplace auto-updates are a drift channel; review releases before adopting.
2. **Trim by ownership, not by editing upstream:** the pipeline terminal (drk-05), the
   SDD-final-review skip, ledger retention until drk-06 consumes it, VBC's focused-suite
   scoping, and TDD's Quick-lane escape hatch all become lines in `dark-factory/skills/*` and
   project CLAUDE.md — durable across compaction, leveraging using-superpowers' own
   instructions-take-precedence rule. (The Codex flow already has the override; the Claude
   flow gets it this way.)
3. **Fork two pieces where philosophy genuinely conflicts:** `df-design` (replaces in-pipeline
   brainstorming) and `df-open-pr` (replaces finishing-a-development-branch).
4. **Take PSTACK's adjudication language, not its stack:** Nitpick Gravity + Act-On>5 into the
   synthesis prompts; diversity-over-personas as the Standard-lane hypothesis; the tdd escape
   hatch. PSTACK's interrogate/orchestrate do not replace SDD — SDD has a measured fault-catch
   rate; PSTACK's docs assert rather than measure.

One-line answer: **superpowers has not become model-obsolete busy-work — its 6.x line is
de-ceremonializing faster than Dark Factory is, and its per-task review is the pipeline's only
measured win.** The busy-work generators are Dark Factory's own challenge loop (being fixed),
the compulsion layer plus entry/exit chaining (fixable with owned overrides and two small
forks), and — still unverified — which superpowers generation each VM actually ran.
