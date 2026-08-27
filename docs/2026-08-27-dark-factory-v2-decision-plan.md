# Dark Factory v2 decision plan

Date: 2026-08-27. Revision 4.

Revision 2 recommended keeping superpowers as the engine and treating PSTACK as a parts bin,
with a staged path to maybe replacing it later. The operator rejected the staging: these are
markdown files, a clean port is less work than cohabitation machinery, and there is no world
where superpowers keeps running inside Dark Factory as-is. Revision 3 inverted the
architecture accordingly. Revision 4 adds four operator decisions: the router sits at the top
and the feature pipeline becomes one branch under it, a hook contract separates
dark-factory from the project layer, the multi-agent delegation rules move out of the global
CLAUDE.md and AGENTS.md into dark-factory, and the model policy gains per-harness delegation
tables. Companion documents: `2026-08-27-dark-factory-course-correction.md`
(CC, the diagnosis and de-amplification work) and `2026-08-27-superpowers-assessment.md` (SA,
the per-skill evidence this revision mines).

## 1. The decision

**PSTACK's methodology, ported to Claude Code and Codex, becomes Dark Factory's execution
layer. The artifact spine stays ours. Superpowers is mined for the few practices PSTACK
lacks, then uninstalled from both harnesses.**

No pin-and-patch. No staged absorption. No dated Stage 2. Those existed to keep superpowers
alive while the decision was pending. The decision is made, so the transition state and its
whole cost disappear.

One carve-out, argued for on evidence rather than attachment: SDD's per-task review economy
survives inside the implementation port. It is the only component in this entire comparison
with a measurement behind it. On one feature it cost about 1.5x and caught five faults that
passed a 16.7k-test suite (CC §2.4). PSTACK has no equivalent: its feature playbook delegates
and verifies, but has no independent per-unit reviewer with a ledger and a hard round cap.

The one-owner rule from revision 2 stands and gets simpler: every function has exactly one
owning skill, and after the port every owner is a df skill, whether an artifact-spine
original or a port. There is no
second methodology left to clash with.

**The router is the top of the stack, and the artifact pipeline is one branch under it.** Dark
Factory today is a feature-delivery pipeline and nothing else. PSTACK's real top level is a
router that classifies the ask first: investigation, bug fix, perf issue, refactor, feature.
We adopt that shape. `df` becomes the entry point for all development work, the artifact
spine (PRD, challenge, runbook, implementation, review, acceptance) becomes the feature and
enhancement branch, and PRD creation becomes a precursor step inside that branch rather than
the front door of everything. This widens Dark Factory's scope: debugging, investigations,
perf work, and refactors get owned playbooks for the first time instead of falling into
ad-hoc sessions. A casual conversational turn does not enter the router at all, which is
PSTACK's own rule ("Casual turn or user opts out: don't") and part of the fix for
over-delegation (§6).

**And the router is explicit-invocation-only.** This is PSTACK's own mechanism, copied
exactly: poteto-mode's frontmatter sets `disable-model-invocation: true` and `mode: true`,
so the model can never auto-enter it, and a one-line `reminder` nudges instead ("New task?
Playbook match or rigor needed: apply /poteto-mode. Casual turn or user opts out: don't").
Ours works the same way. Entering Dark Factory mode requires the operator typing `/df`; the
model may *suggest* it in one line when a task looks like a playbook match, and never enters
on its own. The Codex side gets the equivalent through its skill description ("use only when
the user explicitly invokes df") plus the same rule in dark-factory's Codex instructions.
The SessionStart hook therefore does not activate the mode; it injects only the reminder
line and the ownership rules, and once `/df` is invoked, the copied-into-todos playbook
steps and the state files carry the mode across compaction. The D23 acceptance test proved
the hook is load-bearing for the suggestion behavior, not decorative:
`disable-model-invocation` hides the skill from the model entirely, so the model can only
suggest `/df` because the hook's reminder told it df exists. The invocation policy for
everything else: read-only helper skills (`how`, `why`, `recall`, `blast-radius`) may
trigger on their own descriptions; `unslop` stays always-on by operator mandate; playbooks
and every skill that writes or orchestrates run only when `df` dispatches them or the
operator names them. This is the structural answer to the superpowers habit of jumping into
heavyweight workflow for trivial asks: the old stack *compelled* entry ("even a 1% chance:
you MUST"), and the new stack forbids uninvited entry.

## 2. Function and owner table

The df names are new skills in this repo, written for both harness trees. "Port of X" means
the PSTACK file is the base text, rewritten for our harnesses per §5.

| Function | Owner | Base text | Superpowers graft |
|---|---|---|---|
| Session router + lanes (top of the stack) | `df` (explicit entry via `/df`, never model-invoked; the SessionStart hook injects only a reminder and the ownership rules) | poteto-mode's routing shape, our lanes (CC §4.2) | none |
| Investigation (read-only questions, "how does X work", "are we sure") | `df` → `playbooks/investigation.md`, backed by the how and why skills trimmed to subscription size | investigation playbook | none |
| Perf issue | `df` → `playbooks/perf-issue.md` | perf-issue playbook (baseline trace, hypothesis families, post-fix trace, cite the measurement) | none |
| Refactor | `df` → `playbooks/refactoring.md` | refactoring playbook (pin the behavior contract first, subtract, reader-load delta or revert) | none |
| Requirements | `df-prd-interview` (lite for Standard, full for High-consequence; Quick lane skips it, df records the finish predicate) | ours | none |
| Requirements challenge | `df-prd-challenge` (single-pass Standard, hardened loop High-consequence, CC economics) | ours | none |
| Design | `df-design` | architect (ground, sketch, lane-aware checkpoint; rationale template, design red flags) | none |
| Planning | `df-plan` | multi-phase-plan (checklist plans, machine-checked, skippable for small changes) | writing-plans' step style: verbatim code, interface blocks, no placeholders. It is what lets cheap models implement by transcription |
| Implementation | `df-implement` | feature playbook's delegation + orchestrate's brief/TIMEBOX template | SDD's review economy: per-task independent two-verdict review, on-disk ledger, five-round breaker with adjudication at the cap, model tiering, micro-task batching |
| TDD | inside `df-implement` | tdd skill's escape hatch for Quick lane ("prefer no new test over a bad test", plus the closest executable check); the escape hatch applies to feature work only, never to a reproduced defect, which keeps bug-fix's failing-repro-commit-before-fix rule in every lane | watch-it-fail discipline for Standard and High lanes |
| Debugging | `df` → `playbooks/bug-fix.md` | bug-fix playbook (reproduce yourself first, evidence per shipped line, revert refuted hypotheses) | the stop rule: three failed fixes means stop and question the architecture with the human |
| Claim verification | `df-dev-verify` | ours | prove-it-works language and the blast-radius proof ladder grafted in; evidence-before-claims from verification-before-completion |
| Per-PR code review | `df-code-review` (delta-scoped, CC) | interrogate's single-pass shape, lead-judgment filter (Nitpick Gravity, Act-On over 5 means under-filtering), frozen-tree rule | receiving-code-review's verify-findings-before-implementing posture |
| Flag-flip integrated review | `df-code-review` flag-flip mode: one budgeted pass over the assembled PR chain, the flag-removal diff, and dead code | frozen-tree rule | none |
| Finish and PR | `df-open-pr` | opening-a-pr (Why / Scope / Tradeoffs / Blast Radius / Verification description, conventional titles, small ordered commits, never merges) | finishing-a-development-branch's worktree-cleanup guard, carried verbatim |
| Worktrees | inside `df-open-pr` and `df-implement` | opening-a-pr's worktree rules | submodule guard and baseline suite run from using-git-worktrees |
| QA acceptance | `df-qa-acceptance`, driven by the feature map | ours; create/maintain-verification-skill pattern at the project layer | none |
| Session persistence | `df` → `playbooks/pause-safely.md` and `playbooks/session-pickup.md` | pause-safely and session-pickup, near-verbatim | none |
| Decision trails | decisions.tsv discipline inside `df-implement` and `df-eval` | show-me-your-work | none |
| Skill quality | `df-eval` (capped, §7) | eval playbook + reflect's accepted/rejected/backlog shape | none |
| Principles | `references/principles.md`, cited by the skills, no trigger of its own | the 21 principle skills, condensed | none |

Enforcement, kept from revision 2 because prose tables do not enforce themselves: every
SKILL.md description in both trees is rewritten against this table, the attestation preflight
flags any skill whose trigger text claims a function owned elsewhere, and the SessionStart
hook carries the df reminder and ownership rules so they survive compaction the same way
superpowers' hook text did, without compelling entry the way that hook did.

### What survives of the re-review loop

The multi-round review loops are gone, but re-review itself is not, because the operator's
original observation was correct: a review pass is a sample, and rerunning it catches real
new findings. What blew up was the coupling, not the resampling. Same-model reruns give
correlated draws, autonomous remediation between draws grows the artifact and manufactures
fresh review surface, and a zero-findings exit requires reviewer exhaustion. The bounded
forms that stay:

1. **Delta verification** in df-prd-challenge (already built in the hardened version that
   never reached the VMs) and ported into df-code-review: after a remediation, the reviewer
   re-checks only the changed sections, CONFIRMED or NOT CONFIRMED per finding, plus a
   regression sweep over the remediation prose. Never rediscovery over the whole artifact.
2. **Fresh eyes at the cap**, inside df-implement from SDD: fix rounds resume the
   implementer, the last rounds get a fresh implementer on a stronger model, and the breaker
   ends in adjudication, not another loop.
3. **One fresh verdict per new artifact version.** A changed head SHA earns exactly one new
   pass; an unchanged artifact earns none.
4. **The flag-flip integrated pass** in df-code-review, once per chain.
5. **The operator's second opinion, formalized.** In the Standard lane, "rerun the review"
   becomes an operator-invoked second-opinion pass: one more review with a deliberately
   decorrelated draw (the other model family, or a different rubric lens), lead-adjudicated,
   counted against the dispatch budget, gates unchanged. The recall benefit of the old habit
   without the three couplings. PSTACK's version of the same idea: "A second opinion is the
   same prompt against a different model. Agreement is high-signal."

### How the project layer hooks in

Dark Factory stays project-agnostic the same way PSTACK does: the generic layer looks for
project-local assets by convention and uses them when present. PSTACK's mechanism, verified
in its source: `create-verification-skill` generates a skill *inside the target repo*
(`.cursor/skills/verify-<app>/` with a `features/` map, one file per feature, sub-feature
IDs), the generic playbooks then reference "the matching control skill" and swarm splits
verification "by feature-map entry", and benny's config points at user-owned files by path
(`control.feature_map_path`, `routing.map_path`). Nothing project-specific lives in the
plugin.

Our port of that contract has three layers:

1. **Generic (dark-factory repo).** The df skills. Where they need project context
   they name a convention, never a repo: "the project's verification skill, if present",
   "the project's feature catalog, if present".
2. **Project (the target repo).** A small manifest, `.dark-factory/project.yaml`, that names
   the project's assets: the verification skill, the feature map, the catalog path, the docs
   root, the test commands. Spellguard already has the delivery mechanism for project skills
   (`.agents/skills/` symlinked into `.claude/skills/`), so `verify-spellguard` and its
   feature map land there. For Spellguard the manifest points across repos at Spellbook,
   which holds the product knowledge: the feature catalog (80 CEO IDs), streams, census,
   handbook. That is the "feature map of the entire project" from Lauren's talk, kept
   outside dark-factory on purpose.
3. **Machine (profiles).** Paths and model availability per VM, the existing
   `profiles/*.env` pattern plus `references/model-policy.md`.

The flow reads: df loads, checks for `.dark-factory/project.yaml`, and pulls the
catalog and feature map into context selection (which features does this change touch, which
verification recipes run). A repo with no manifest still gets the full generic flow, just
without pre-context. Nano projects and personal repos work day one.

## 3. What we take from superpowers, and what happens to the rest

The full mining list is in the table above. It is short: the SDD review economy, the plan
step style, watch-it-fail TDD, the debugging stop rule, the worktree details, the cleanup
guard. SA's per-skill verdicts are the provenance for each.

Everything else superpowers does, PSTACK's text already covers, and often with less ceremony.
Once the df skills exist and pass their evals, superpowers is uninstalled from both harnesses
(the Claude plugin cache and the separate Codex one). The cached copies stay on disk as MIT
reference material. Reinstalling takes minutes if we regret it, which lowers the stakes of
the whole move. Check upstream's release notes quarterly; cherry-pick by hand if something
worth having ships.

Skills lost that nothing replaces: brainstorming for ad-hoc chat design (df-design covers the
pipeline case; if ad-hoc use is missed, fork it then, it is one file), and writing-skills
(dark-factory's own skill-creator plus df-eval cover skill authoring).

## 4. What stays Dark Factory identity

PSTACK assumes an organization around the developer: PMs writing requirements in Notion,
Linear teams, Slack channels a bot can ping, reviewers on Bugbot. Dark Factory internalizes
those roles into artifacts because at two developers there is no org to lean on. The PRD is
the PM, the QA runbook is the QA team, the challenge round is the design review. So these
stay ours:

- Dual-harness operation with one policy core. PSTACK is single-harness by construction.
- df-prd-interview per lane. The interview is how the operator thinks a feature through, and the
  forensics show it was never the pathology.
- PRD-to-QA traceability, coverage matrices, evidence reports. The audit trail a credential
  product needs.
- QA acceptance as a real gate: per-PR live verification of the changed surface during
  development, full acceptance plus the df-code-review integrated pass at the flag-flip PR. Graphite's
  "run E2E later" doctrine is explicitly not adopted.
- Lanes and budgets, because no org exists to supply proportionality judgment informally.
- The Spellbook layer: the feature catalog (80 CEO-assigned IDs), streams, census, scribe.
  This is the miniature org being built deliberately. The catalog plays the role Linear teams
  play for Lauren; the scribe, or a product-persona sibling on the same Hermes setup, is the
  future intake bot.

### The delivery model, stated plainly

A Standard or High-consequence feature ships as several small PRs, typically three to seven,
merging into main behind a feature flag as each goes green. The first PRs deliver a visible
vertical slice. Each PR gets its own agent review and live verification of its changed
surface. The last PR flips the flag, and that is where the full acceptance runbook and
df-code-review's integrated pass run. PRs merge as they land rather than waiting for the
whole chain, because verified-but-unlanded work counts as zero; branch-on-branch chains are
reserved for PRs that genuinely depend on each other, managed with plain git and gh. The
Quick lane stays one PR. Merge authority is the operator's on every PR, and single-PR
delivery remains allowed where a flag would be more overhead than the feature (the
operator's call). Prerequisite, riding with Phase 1: a lightweight flag convention in
Spellguard, which can be as simple as a config boolean per dark feature.

## 5. Porting rules, Cursor to our harnesses

Mechanical substitutions applied to every ported file:

- Cursor `Task` spawns become the Agent tool (Claude) or native subagents / codex exec
  (Codex); `readonly` becomes sandbox flags plus instruction; `environment: cloud` becomes
  local subagents.
- `/loop` wake mechanics become Monitor until-loops or the loop skill.
- `/goal` becomes the lane contract plus the run state file.
- `AskQuestion` becomes AskUserQuestion (Claude) or a gates file entry.
- Graphite (`gt`) becomes plain git plus `gh`; stacks are branch chains, and no Graphite until
  more than about 4 live stacked PRs hurt.
- Model slugs become roles resolved through `references/model-policy.md` (§6).
- Cursor transcript paths become our session directories.
- Anything depending on cursor-team-kit (`/deslop`, control-ui, control-cli) is dropped or
  replaced by our own equivalents (agent-browser, the tmux workbench).

Ports are editorial, not blind copies. Each ported file gets the same treatment as any skill
change: a reviewed diff against its base text and a df-eval scenario before it ships.

Naming rules:

- Faithful ports keep their PSTACK names. `how`, `why`, `interrogate`, `swarm`,
  `blast-radius`, `unslop`, `show-me-your-work`, `figure-it-out`, and the playbooks
  (`investigation`, `bug-fix`, `perf-issue`, `refactoring`, `prototype`, `pause-safely`,
  `session-pickup`, and the rest) stay as they are. There is no collision risk, since PSTACK
  itself is Cursor-only and never installs here.
- Poteto-branded names become df names: `poteto-mode` is `df`, `poteto-agent` is
  `df-agent`.
- Composites that do not exist in PSTACK, because they merge its text with artifact-spine
  hooks or
  superpowers grafts, also get df names so the name signals ours: `df-design` (architect
  plus lanes), `df-plan` (multi-phase-plan plus writing-plans' step style), `df-implement`
  (feature delegation plus SDD's review economy), `df-open-pr` (opening-a-pr plus the
  cleanup guard and our never-merge rules), `df-eval` (eval plus reflect, capped).
- The artifact spine drops the drk prefix and its stage numbers. One namespace, df, and
  canonical names that say what each skill is. The numbers encoded pipeline order, and the
  feature playbook owns order now, so they carry nothing. The rename:

  | Old | New |
  |---|---|
  | drk-01-prd-interview | `df-prd-interview` |
  | drk-02-prd-challenge | `df-prd-challenge` |
  | drk-03-qa-runbook-gen | `df-qa-runbook-gen` |
  | drk-04-qa-runbook-validation | `df-qa-validation` |
  | drk-05-dev-verify | `df-dev-verify` |
  | drk-06-code-review | `df-code-review` |
  | drk-07-qa-acceptance | `df-qa-acceptance` |
  | drk-reviewer-recheck (agent) | `df-reviewer-recheck` |

  The rename lands on port day through the manifests and the frontmatter audit, in both
  trees. Living references update with it: the dark-factory repo, the Spellguard rulebook
  and handoff conventions, and the `.dark-factory/` report paths. Committed historical
  artifacts that mention drk stages (old runbooks, old reports, the CC and SA documents)
  stay as they are; they are records, not guidance.
- Playbooks are playbooks, matching PSTACK's structure: files under `df/playbooks/`
  that the router copies into the todo list, not separately triggered skills.

## 6. Model and cost policy

Lauren's model-role table assumes overflow billing. Ours assumes hard ceilings, so the policy
is a committed file, `references/model-policy.md`, that both flows read:

1. Per-role minimum tiers per harness. Discovery, challenge, and adjudication run on frontier
   tier. Mechanical implementation against a complete brief runs on the cheapest capable
   model (SDD's ladder, kept in df-implement; the Codex side re-defaults to Terra, with
   sol_high reserved for genuine escalation). Leaf reviewers are mid-tier, pinned through
   agent definitions. Skill quality degrades with model tier, so the file names the floor per
   role instead of hoping.
2. Exhaustion is a state, not an error. When one harness's window runs out, cross-model
   review legs record `deferred: usage-limit` in the run ledger, single-model work continues
   on the surviving harness, and High-consequence approvals wait for the window to reset
   rather than waiving the second family.
3. Budgets meter what is countable today: wall-clock and dispatch counts. Token metering
   joins when the Phase 0 logging proves it measurable.
4. Panels are lane-priced. One Claude plus one Codex is the Standard-lane ceiling. Personas
   and multi-round survive only in High-consequence. Arena-style competing implementations
   are invoked by hand or not at all.
5. Process work meters from the same windows as product work. df-eval runs and the port
   itself get line items, not a blank check.

### Delegation rules move out of the globals

Where PSTACK keeps delegation policy, verified in its source: three places, and none of them
is an always-on global instruction. The router's Subagents section carries the defaults
(background spawns, file pointers instead of inlined context, explicit model per role, and
the tier-by-difficulty rule: judgment-heavy or vague work to the strongest judgment model,
precisely specified sequences to the strongest instruction-follower, trivial mechanical
edits to the fast code model). Each playbook says what gets delegated at which step, so
delegation is a property of the task type. And a user-owned config file
(`~/.cursor/rules/pstack-models.mdc`) overrides models per role. A casual turn never enters
the mode, so a quick ask stays a quick ask.

Our globals do the opposite today. `~/.codex/AGENTS.md` carries the full Sol-orchestrator
doctrine ("The root should not perform implementation edits itself", assignment tables
before spawning), and `~/.claude/CLAUDE.md` imports the same file wholesale. Every session
on the machine becomes an orchestrator regardless of task size. That is why a request to
save an investigation to a markdown file turned into a subagent ceremony, and the dev-env-a
forensics list the global multi-agent rules as part of the runaway stack.

The fix: strip the multi-agent orchestration and agent-selection sections from both global
files. They move into dark-factory, split by harness: df's Subagents section carries
the defaults and the tier rule, each playbook names its own delegation points, and
`references/model-policy.md` holds the per-role model tables below. The globals keep what is
genuinely global: git workflow, safety rules, credential-provenance gates, file-link
conventions, and the home-server notes.

Stripping the live files is not enough, because the doctrine is provisioned. Verified in the
local checkouts: the block's true source is the home-server repo
(`config/codex/instructions/shared.md`), which syncs into box-bootstrap
(`dotfiles/codex/instructions/shared.md`); box-bootstrap's `install.sh` splices it into
`~/.codex/AGENTS.md` on every bootstrapped box, and `dotfiles/claude/CLAUDE.md.template`
imports that file wholesale into Claude Code. Worse, install.sh's doctor check actively
warns when the block is *missing* (install.sh:1006, "AGENTS.md is missing the multi-agent
workflow block"), so a hand-edited box reads as broken and the next bootstrap run restores
the doctrine. Removal therefore lands in three places, in order: the home-server repo's
shared.md (the source), box-bootstrap's copy plus the install.sh doctor check (invert it so
it warns if the block is *present*), and then the live `~/.codex/AGENTS.md` and
`~/.claude/CLAUDE.md` on each VM. The named-agent TOMLs (`luna-max`, `terra-xhigh`,
`sol-high`) stay in box-bootstrap; dark-factory's model-policy references them, it just
stops letting a global rule decide when they're used. The operator confirmed the local
home-server checkout is current with its remote, so the source location is verified.

Draft per-role tables for `references/model-policy.md`, to ratify:

Claude Code:

The inherit defaults below are deliberate. The root session model is the operator's usage
throttle: you pick it at launch, and you downgrade it near the weekly limit or mid-session
once the hard part is done. Every role marked inherit follows that downgrade automatically.
Pins exist only as floors (the recheck tier) and as cheap tiers (menial work), never as
top-tier defaults that would silently undo the throttle. And one rule closes the gap the
cross-model review caught: a pinned role never runs *above* the current session model unless
it is a designated floor. The Opus implementation pin is a cost saving under a Fable
session; under a session deliberately throttled below Opus, that pin follows the session
down. Floors (df-reviewer-recheck) are the only pins allowed to exceed a throttled session,
because their job is to keep a review meaningful.

| Role | Model / effort |
|---|---|
| Session / orchestrator | inherit: whatever the operator launched (typically Fable, deliberately downgraded near limits); the session does small tasks itself instead of delegating them |
| Development delegate (implementation against a brief) | Opus |
| Menial, well-scoped, or investigatory subagent | Sonnet |
| Judgment-heavy delegate (cross-cutting design, gnarly concurrency, vague intent) | inherit: the session model, or stay in-session |
| Reviewer, discovery tier (df-prd-challenge / df-code-review High-consequence) | inherit: the session model |
| Reviewer, recheck / leaf tier | Opus high, pinned agent definition (`df-reviewer-recheck` pattern); a floor, not a ceiling |

Codex:

| Role | Model / effort |
|---|---|
| Orchestrator | inherit: whatever the operator launched (typically Sol at xhigh, deliberately downgraded near limits) |
| Development delegate | `luna_max`, falling back to `terra_xhigh` while the Luna spawn bug stands |
| Discovery / repo-wide context work | `terra_xhigh` |
| Escalation (genuine trust-boundary changes, repeated failure) | `sol_high`, and the trigger is "changes the trust boundary or invariant", never "reads code near one" |
| Cross-model reviewer of Claude-side work | fresh `codex exec` under the leaf profile, effort per lane |

Cross-model review of PRDs and code stays, in both directions. PSTACK's interrogate is the
same idea (multi-model adversarial, one pass, lead adjudication), so the ported df-prd-challenge and
df-code-review keep their two-family reviews and take their reviewer models and efforts from these
tables rather than from hardcoded `xhigh` flags.

The file itself mirrors PSTACK's `pstack-models.mdc` format, one line per role, with two
structural differences. Cursor mixes vendors in one list; our sessions spawn only within
their own family, so the file has a Claude section and a Codex section, and the cross-model
legs name the other CLI. And the Claude Agent tool cannot set effort per spawn, so a role
that needs a pinned effort resolves to an agent definition (the `df-reviewer-recheck`
pattern) rather than a bare model name. `inherit` works exactly like their
`inherit-parent`: omit the model and the spawn runs on the session model. Draft:

```
# df model policy. One line per role. Delete a line to fall back to the skill default.
# `inherit`: the role runs on the session model (omit the spawn's model field).

## claude code
session / router:                      inherit          # you pick at launch; typically fable, downgraded near limits
menial, well-scoped, investigation explorers: sonnet
implementation delegate:               opus
judgment delegate (vague intent, cross-cutting design): inherit
investigation synthesizer / explainer: opus
df-design runners:                     opus + inherit   # standard lane runs one, high-consequence two
prd-challenge / code-review discovery reviewers: inherit
recheck and leaf reviewers:            df-reviewer-recheck   # agent def, opus @ high; a floor, not a ceiling
df-eval graders:                       sonnet
cross-model review leg:                codex CLI, per the codex section

## codex
orchestrator / router:                 inherit          # you pick at launch; typically sol @ xhigh, downgraded near limits
implementation delegate:               luna_max         # terra_xhigh while the Luna spawn bug stands
discovery / repo-wide context:         terra_xhigh
escalation (trust-boundary change, repeated failure): sol_high
df-prd-challenge persona reviewers (high-consequence CLI fallback): operator's codex default, no hardcoded effort flag; env-overridable
cross-model review leg:                claude tmux, review-only + deadline
```

## 7. df-eval, capped from birth

A recurring session that reads transcripts and proposes improvements is the same shape that
ran away in df-prd-challenge: strong models never run out of findings. So the self-improvement loop
ships with its own limits.

- Scenario evals for loop policies and ported skills: does df-prd-challenge stop at the dispatch
  budget, does the growth stop fire, does a takeover re-anchor scope, does df-open-pr refuse
  to merge. Graded from transcripts and artifacts, never from the agent's self-report, and
  the agent under test is not told it is being tested. `just test-runners` is the foundation.
- Cadence: on every skill change, plus a recurring retro producing an
  accepted/rejected/backlog list. Your approval is required before any skill edit.
- Its caps: a lane, a dispatch and wall-clock budget, at most 5 proposals per cycle, a line
  item in model-policy.md, and "the retro stayed in budget" as one of its own graded
  outcomes.
- Scope: dark-factory skills first, then verify-spellguard and the scribe skills. Three to
  five scenarios per skill. The target is the smallest harness that would have caught this
  week's two drift incidents.

This is also where the performance metrics come from. Eval runs and per-feature run ledgers
feed the CC §9 scorecard: time against the Effort-Anchor, dispatches, time to first visible
slice, review-caught faults, duplicate dispatches after a resume.

## 8. Execution plan, with honest effort accounting

Revision 2 said 25 to 35 sessions over 6 to 8 weeks. That number priced calendar spread
alongside product work, and it priced cohabitation machinery this revision deletes. The
honest breakdown separates three kinds of work.

**Writing the skills: about a day.** The df ports and grafts are markdown. Claude drafts them
in parallel with drafting agents, the operator reviews the diffs. The routing-table
frontmatter audit rides along. Superpowers' chain references in six files across both trees
get rewired in the same pass.

**The parts that are not markdown: hours to days each.**

| Item | Effort |
|---|---|
| SessionStart hook + attestation preflight (skill SHA, both superpowers channels until uninstall) | hours |
| Run state file schemas for df-prd-challenge and df-code-review | hours |
| Spellbook catalog schema and seeding, plus the Notion one-way export | operator-owned separate effort, out of this initiative's scope; the `.dark-factory/project.yaml` hook contract is built ready for it, and the extracted 80-feature seed JSON is waiting in the session scratchpad |
| Spellguard rulebook edits (CC §6: baseline rule to all suites, focused-run doctrine, credential de-minimis, handoff rules) | hours |
| Delegation-doctrine removal at the source: home-server shared.md, box-bootstrap shared.md + install.sh doctor inversion, then each VM's live globals | hours, across two repos plus the fleet |
| go-mobile trigger narrowed in the matrix plugin: dictation artifacts stop counting as a mobile hint, since the operator always dictates | minutes |
| df-eval harness and first scenarios | 1 to 2 days |
| verify-spellguard + feature map | days; it drives the real app, and it is the largest single investment |
| Baseline feature run | elapsed time of one real feature; protect it, since Phase 1's exit criterion has no numbers without it |

**Learning whether it works: weeks, by using it.** Lane thresholds, budget values, and the
single-pass challenge are hypotheses with tripwires (CC §4.4). Real features falsify or
confirm them. This is the only place "weeks" legitimately lives, and it is usage, not
construction.

Order of operations: ratify the decisions below, run `just sync` and the P0 defect fixes,
port day, then the non-markdown items in the table's order, with the baseline run started as
soon as the ports land. The Phase 4 items from CC (master orchestrator, the intake bot on
Matrix/Hermes triaging against the catalog, one teammate filing one bug and getting a draft
PR while you watch) wait until the above has weeks of history. Merge authority stays human
indefinitely.

## 9. Decisions ledger

Rejected, recorded so it stays rejected:

- Adopting PSTACK wholesale, unported. Single-harness, org-assuming, and its no-PRD doctrine
  fails where wrongness is a security incident.
- Keeping superpowers as the engine (revision 2's recommendation). Rejected by the operator:
  no version of Dark Factory keeps superpowers as-is, and cohabitation machinery costs more
  than a clean port of prose files.
- Running any PSTACK playbook as a peer of a retained skill. One owner per function.
- Graphite now. Revisit past about 4 live stacked PRs.
- Stakeholder-advocate agents per feature. The catalog plus per-feature verification recipes
  give the guarantee as verification, not opinion.
- Automerge. Top of the trust curve.

**Ratified 2026-08-27 by the operator**: D1 through D30 at the proposed defaults, with one
amendment: D9's v1 exemption covers docs and comments only, pure non-executable changes;
log-string edits keep triggering the credential-flow review until a no-new-interpolation
check exists. The catalog and Notion export are out of this initiative's scope
(operator-owned separate effort). The baseline feature is whichever real feature the
operator runs next through `/df` once the flow exists, instrumented. The ledger as ratified:

| # | Decision | Proposed default |
|---|---|---|
| D1–D10 | CC's box (lanes, budgets, growth caps, tripwires, defer/degrade) | CC defaults |
| D11 (revised) | PSTACK-ported execution layer; superpowers mined then uninstalled once the df skills pass their evals | yes |
| D12 (revised) | No pin-and-patch; cached superpowers copies kept on disk as reference only | yes |
| D13 | df-code-review flag-flip integrated review mode | add it, one budgeted pass |
| D14 | df-eval caps | 5 proposals per cycle, Standard-lane budget |
| D15 (revised) | Execute port day immediately after ratification; non-markdown items in §8 order | yes |
| D16 (extended) | Strip multi-agent orchestration rules from the live globals AND their provisioning chain: home-server `config/codex/instructions/shared.md` → box-bootstrap `dotfiles/codex/instructions/shared.md` + the install.sh doctor check that enforces the block's presence. Rules move into df, the playbooks, and model-policy.md | yes |
| D17 | Router at the top: df owns all *explicitly routed* dev work (entry is /df per D22; work done without it is ordinary conversation, and the model may suggest routing), the artifact spine is the feature branch, and investigation / bug fix / perf / refactor get df playbooks | yes |
| D18 | Project hook contract: `.dark-factory/project.yaml` in target repos; Spellguard's manifest points at Spellbook for the catalog and product map | yes |
| D19 | The full catalog dispositions (appendix): what ports, adapts, folds, defers, and gets excluded, plus the naming rules in §5 | yes |
| D20 | One namespace: every drk skill renames to df with a canonical descriptive name and no stage number (mapping table in §5); living references update on port day, historical artifacts stay | yes |
| D21 | Operator-invoked second-opinion pass in the Standard lane: one decorrelated re-review on demand, lead-adjudicated, budget-counted, gates unchanged | yes |
| D22 | `/df` and its playbooks are explicit-invocation-only (disable-model-invocation, the poteto-mode mechanism); the model may suggest `/df` in one line, never enter it; read-only helpers may self-trigger; unslop stays always-on (PSTACK's own default, "Must always apply", plus operator mandate; its core rules also embed in df's reply-writing section, since PSTACK measured cleanup-afterward as failing) | yes |

The cross-model review (Sol xhigh, findings preserved in
`2026-08-27-v2-plan-codex-review.md`) judged the decisions sound but the implementation
contracts unresolved. Adjudication: the decision doc stays a decision doc, and the review's
accepted findings become the port-day gate, captured as D23 through D30. Each executes as a
written contract before or during port day, drafted against the review's numbered findings:

| # | Decision (review findings it answers) | Proposed default |
|---|---|---|
| D23 | Codex-native explicit entry for df (`$df` or a custom prompt, not an assumed `/df`), with clean-session tests proving ordinary prompts cannot activate it (1, 2) | yes |
| D24 | The budget store is specified before any loop runs: single authoritative state file per run, atomic pre-dispatch reservation so a dispatch is counted before it spawns, nested dispatches count against the parent budget, leases and stale-owner recovery, terminal states; concurrent-dispatch and resume races get tests (18, 27) | yes |
| D25 | Cutover isolation and canary: df validates in isolated config homes (CLAUDE_CONFIG_DIR / CODEX_HOME) so superpowers cannot contaminate the evals; the exact old plugin and instruction revisions are pinned as the tested rollback; dev-env-b canaries before the fleet (7, 26) | yes |
| D26 | Reviewer transport contracts per harness: independent reviewers read from a disposable worktree snapshot created for the review and deleted after, so a degraded sandbox can only touch a throwaway (today five runners silently fall back to danger-full-access on the live tree when `unshare --net` fails, which is how reviews "work" on this VM); content-in-prompt for document-sized artifacts; the codex-exec wrapper carries brief, artifact digest, cwd, sandbox, deadline, output schema, and exit mapping; the Claude tmux adapter keeps the interactive-session flow (never `claude -p`) and gains the sentinel + structural-validation contract, a review-only instruction, a deadline with a reaper, and the Matrix bridge pane ban; port day includes one look at fixing bwrap loopback at the VM level. The wrapper contract is transport-agnostic (brief and digest in, structured findings and terminal status out, deadline and reaper around it): headless codex exec is the default transport behind it, and a tmux-Codex adapter can slot behind the same contract if exec ever becomes untenable on a box, considered and deliberately not adopted now because TUI driving adds approval-prompt automation and screen-scraping fragility for no gain (11, 12, 13) | yes |
| D27 | `.dark-factory/project.yaml` is a versioned, validated schema: allowlisted canonical paths, approved command IDs instead of raw shell strings, explicit trust for project-local skills, and a pinned catalog snapshot exported into the repo where cross-repo reads are sandbox-blocked (16, 17) | yes |
| D28 | Feature-flag lifecycle convention: default-off, tests in both states, compatibility rules for schema and credential paths, cleanup owner and date per flag, and criteria for when a chain or single atomic PR beats a flag (22) | yes |
| D29 | Port day ships one complete route first, bug-fix end to end with its acceptance tests, before extrapolating to the catalog; every ported artifact carries an acceptance check; review passes key to content digests with an explicit pass-type matrix (19, 20, 24, 25, 29) | yes |
| D30 | A vendor manifest records PSTACK provenance (repo, commit `bdf7aa3`, MIT license, per-file mapping, local modifications), and the shared-policy-core generation mechanism exists before both trees are written, with model-policy as a parseable schema and one resolver per harness (6, 9, 10, 32) | yes |

## Appendix: full PSTACK catalog and disposition

Every item in the snapshot, with its fate. "Port" means faithful, name kept. "Adapt" means
ported with the named changes. "Fold" means the content moves into a named owner and no
separate skill exists. "Later" means deliberately deferred, not rejected.

### Workflow skills (23)

| PSTACK skill | Decision | Name here | Comment |
|---|---|---|---|
| poteto-mode | Adapt | `df` | The router. Lanes added, explicit `/df` entry only, the SessionStart hook injects its reminder, Cursor mechanics replaced per §5 |
| architect | Adapt | `df-design` | Lane-aware checkpoints and artifact-spine hooks added; rationale-template and design-red-flags references come along |
| how | Adapt | `how` | Explorers capped at 2 to 4 on sonnet; the 4-model critique panel becomes two-family |
| why | Adapt | `why` | Investigator fan-out capped; sources trimmed to git, GitHub, and Notion; the Linear and Databricks playbooks dropped until we use those tools |
| interrogate | Adapt | `interrogate` | Two-family panel instead of four models; its shape and lead-judgment references also feed df-prd-challenge and df-code-review synthesis |
| swarm | Adapt | `swarm` | Cloud workers become local subagents; worker caps come from model-policy; drives feature-map verification splits |
| arena | Adapt | `arena` | Included but gated: High-consequence lane, invoked by hand, panel from model-policy. Token-expensive by design |
| figure-it-out | Port | `figure-it-out` | The bespoke-playbook designer for work no playbook fits |
| blast-radius | Port | `blast-radius` | The proof ladder is also grafted into df-dev-verify |
| show-me-your-work | Port | `show-me-your-work` | decisions.tsv discipline; `log.sh` ports with it |
| recall | Adapt | `recall` | Transcript paths differ per harness |
| create-verification-skill | Adapt | `create-verification-skill` | Targets the repo's `.agents/skills/`; harness options are agent-browser and the tmux workbench; feature maps key to catalog IDs |
| maintain-verification-skill | Adapt | `maintain-verification-skill` | Pairs with the above; clean / changed / blocked outcomes kept |
| tdd | Fold | inside `df-implement` | One owner per function. Its Quick-lane escape hatch text merges with superpowers' watch-it-fail rule |
| reflect | Fold | inside `df-eval` | One owner for skill quality; its accepted/rejected/backlog shape and approval gate survive |
| unslop | Port | `unslop` | Adopted already, operator mandate; applies to replies and docs |
| technical-writing | Port | `technical-writing` | Docs standard for spellbook and PR prose |
| typescript-best-practices | Port | `typescript-best-practices` | Reference for TS repos; Spellguard is TS |
| teach | Later | `teach` | Useful for onboarding teammates through spellbook; not needed for the pipeline |
| setup-pstack | Replace | `references/model-policy.md` + `profiles/` | Ours is a committed file, not an interactive setup; per-machine deviations live in profiles |
| no-comments | Exclude | | Comments are not banned here; taste-level, revisit if wanted |
| bro | Exclude | | Novelty; unslop's plain-speech rules cover it |
| automate-me | Exclude | | Mines Cursor transcript layouts and depends on Cursor's create-skill; niche |

### Principle skills (21)

| PSTACK item | Decision | Name here | Comment |
|---|---|---|---|
| all 21 principle-* skills | Port, condensed | `references/principles.md` | One reference document the df skills cite; no separate skill triggers, so no selector competition. Full leaf text preserved where a principle is load-bearing |

### Playbooks (23)

| PSTACK playbook | Decision | Name here | Comment |
|---|---|---|---|
| investigation | Port | `playbooks/investigation.md` | New coverage for Dark Factory |
| bug-fix | Adapt | `playbooks/bug-fix.md` | Superpowers graft: three failed fixes means stop and question the architecture |
| perf-issue | Port | `playbooks/perf-issue.md` | New coverage; gives you the perf metrics practice you never had |
| refactoring | Port | `playbooks/refactoring.md` | Reader-load delta or revert |
| prototype | Port | `playbooks/prototype.md` | Settle empirical forks by building, not by asking |
| feature | Adapt heavily | `playbooks/feature.md` | Becomes the artifact-spine entry: lane routing, PRD as precursor, df-design, df-plan, df-implement, df-dev-verify, df-code-review, df-qa-acceptance |
| multi-phase-plan | Adapt | `df-plan` | Plus writing-plans' verbatim-code step style, interface blocks, no placeholders; `check-plan.mjs` ports |
| opening-a-pr | Adapt | `df-open-pr` | gh instead of Graphite, deslop dependency dropped (unslop covers prose), finishing's cleanup guard added, never-merge and no-draft rules match the operator's git workflow |
| pause-safely | Port | `playbooks/pause-safely.md` | Off-context resume note before compaction |
| session-pickup | Port | `playbooks/session-pickup.md` | The prior trail is authoritative; no redoing finished work |
| worktree-cleanup | Port | `playbooks/worktree-cleanup.md` | `worktree-audit.sh` ports with it |
| autonomous-run | Adapt | `playbooks/autonomous-run.md` | Falsifiable predicate contract kept; wake via Monitor instead of /loop; audit ticks judge progress by side effects only (commits, pushes, check deltas), and a delegate past its expected runtime with no side effect is stuck and gets stood down and replaced |
| orchestrate | Adapt, trimmed | `playbooks/orchestrate.md` | The store schema is the base of our state files; the wall-clock 70 percent land-by rule kept; ten-agent scale and Graphite topology trimmed to subscription size |
| hillclimb | Port, gated | `playbooks/hillclimb.md` | Frozen harness, keep-or-revert; rare use, Monitor wake |
| runtime-forensics | Port | `playbooks/runtime-forensics.md` | Diagnosis-only |
| trace-forensics | Port | `playbooks/trace-forensics.md` | Diagnosis-only |
| eval | Adapt | `df-eval` | Plus the §7 caps; the observer-effect rule and transcript grading kept |
| babysit | Adapt | `playbooks/babysit.md` | Drive a PR to green via gh and CI; bugbot-triage rubric shape retargeted at our reviewer output; never merges |
| visual-parity | Later | | Dashboard pixel work via agent-browser; port when first needed |
| autopilot-stack | Later | | Fits the small-PR chain model and never merges, but belongs to Phase 4 maturity |
| autopilot-full | Exclude | | Automerge; top of the trust curve |
| shipping | Exclude | | Written against Graphite merge-when-ready; merge authority is human here. Its patch-id verdict-invalidation idea lives on in the evidence ledger |
| authoring-a-skill | Exclude | | Depends on Cursor's create-skill; dark-factory's skill-creator plus df-eval own skill authoring |

### Agents, automations, scripts

| PSTACK item | Decision | Name here | Comment |
|---|---|---|---|
| poteto-agent | Adapt | `df-agent` | Subagent definition that reads df in full before work |
| comment-sicko | Exclude | | Goes with no-comments |
| benny automation pack | Later | | The Phase 4 intake bot's reference design: trusted-marker contract, budgets, fail-closed gates, feature-map routing. Matrix and Hermes replace Slack and Cursor automations |
| scripts/orch (orch.ts, store.ts) | Adapt | state-file CLI | The units/ledger/gates schema informs our run state files; lock semantics kept |
| scripts/check-plan.mjs | Port | `check-plan.mjs` | Machine-checks df-plan output |
| scripts/watch-pr | Adapt | `watch-pr` | Mostly plain gh already; Graphite and Bugbot fields dropped |
| scripts/worktree-audit.sh | Port | `worktree-audit.sh` | Read-only classifier, never deletes |
| scripts/bootstrap.ts | Exclude | | Bun self-bootstrap for their scripts; ours ride the existing Justfile checks |
| docs/guide (10 files) | Not ported | | Operator documentation; source material for dark-factory's README rewrite |

## Appendix: revision history

Rev 1: staged absorption, no deadline. An adversarial review found the staging defaulted to
permanent cohabitation by drift, the eval gate was ceremonial, and the plan was unpriced.
Rev 2: added the dated Stage 2 decision, the pin-and-patch hardening, enforcement for the
routing table, caps for df-eval, prices, and a minimal slice. Rev 3: the operator rejected
cohabitation entirely; architecture inverted to PSTACK-as-base with superpowers mined and
uninstalled; effort accounting rewritten to separate prose (a day) from tooling (hours to
days) from validation (weeks of usage); document restyled per the unslop skill. Rev 4: router moved to
the top with the artifact spine as the feature branch and new df playbooks for investigation,
perf, and refactor; the project hook contract added (`.dark-factory/project.yaml`, Spellbook
as Spellguard's product map); delegation rules relocated from the global CLAUDE.md and
AGENTS.md into df, the playbooks, and model-policy.md, with the provisioning chain
(home-server → box-bootstrap → install.sh, doctor check inverted) added to D16; per-harness
model tables drafted in the pstack-models format; naming rules and the playbooks-not-skills
correction added to §5; the full PSTACK catalog disposition appendix and D19 added. Later
rev 4 operator corrections: the router is plain `df`; orchestrator, judgment-delegate, and
discovery-reviewer roles default to inherit on both harnesses because the root session model
is the operator's usage throttle; and the drk namespace retires entirely, every artifact
skill renamed df with a canonical name and no stage number (D20). Then: bounded re-review
forms and the second-opinion pass (D21); explicit-invocation-only routing (D22); and a
cross-model review by Codex Sol at xhigh (32 findings, preserved in
`2026-08-27-v2-plan-codex-review.md`) adjudicated into the internal-contradiction fixes in
§2 and §6 and the D23 through D30 port-day gate contracts.
