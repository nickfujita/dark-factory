---
name: df
description: Dark Factory session router and lane contract. Use only when the user explicitly invokes /df. Never enter on your own. When a task looks like a playbook match, you may suggest /df in one line and continue the turn normally.
disable-model-invocation: true
---

# df

The entry point for all routed development work. `/df` classifies the ask, picks a lane, and copies the matching playbook into the todo list. A casual conversational turn never enters this mode. Work done without `/df` is ordinary conversation.

## Entry

The operator typing `/df` is the only entry. You may suggest `/df` in one line when a task looks like a playbook match. You never enter it on your own. Once entered, the copied playbook steps and the run state files carry the mode across compaction.

## Non-negotiables

Start every multi-step task with a todo list whose first item is to read `references/principles.md` in full. In your reply, name each principle that shaped a decision and the specific choice it changed. A citation with no decision behind it means you skipped the principle. It must trace to a real choice the rule drove.

## Lane decision

Classify the ask into a lane before any work. Propose the lane, get the operator's confirmation, and record it in the run state: `scripts/df-state.sh init` opens the run with its lane, budgets, and finish predicate. The default is Standard. Nothing escalates itself to High-consequence silently. Review findings never change the lane.

**Quick.** For a bug fix, small UI change, or config change with named files or a named surface and one acceptance target. Record a finish predicate up front. That predicate is the acceptance. The lane skips the PRD interview, the challenge round, and the QA runbook. Review is one reviewer, single pass, lead adjudication. Verify on the matching surface. Delivery is one PR. The TDD escape hatch ("prefer no new test over a bad test", plus the closest executable check) applies to feature work only, never to a reproduced defect.

**Standard.** For a typical feature whose requirements fit a small PRD. The lane includes:

- a lite PRD interview
- a single-pass challenge, one Claude reviewer plus one Codex reviewer on the same prompt, lead adjudication, one remediation wave, one delta verification, no rounds
- a thin QA runbook and one combined validation pass
- per-task review during implementation, one whole-branch discovery round, delta-scoped verification of fixes
- runbook execution for acceptance
- delivery as several small PRs behind a feature flag

The operator may invoke one second-opinion pass. It is a deliberately decorrelated re-review, the other model family or a different rubric lens, lead-adjudicated and counted against the dispatch budget. Gates stay unchanged.

**High-consequence.** For credential or auth boundaries, migrations, protocol compatibility, or anywhere wrongness is a security incident. Entry requires a full PRD and an explicit written autonomy contract naming the objective, the editable scope, the budget, and the terminal outcomes. The lane includes:

- the full PRD interview
- the hardened challenge loop with a dispatch budget and a growth stop
- the full runbook and validation, three rounds maximum
- full review with delta scoping
- full acceptance plus the flag-flip integrated review pass

Every lane runs under a dispatch and wall-clock budget. Budget exhaustion is a stop, not a flag.

The stage skills the lanes name are live: `df-prd-interview`, `df-prd-challenge`, `df-design`, `df-qa-runbook-gen`, `df-qa-validation`, `df-implement`, `df-dev-verify`, `df-code-review`, `df-qa-acceptance`. Where a named skill is absent on a box, say so and apply the lane's discipline inline. Never invent a file.

## Playbook triggers

Match the task to a playbook, open its file, and copy its steps into the todo list verbatim. For a pending playbook, say so and apply the lane's discipline inline. Never invent a playbook file.

| Task shape | Playbook | Status |
|---|---|---|
| Read-only question. How does X work, why was Y built this way, are we sure about Z. | `playbooks/investigation.md` | Ported |
| A reported defect to reproduce, root-cause, and fix with runtime evidence. | `playbooks/bug-fix.md` | Ported |
| A measured slowness to trace and improve against a baseline. | `playbooks/perf-issue.md` | Ported |
| A behavior-preserving change to structure or shape. Rename, extract, inline, dedupe, move. | `playbooks/refactoring.md` | Ported |
| New or changed behavior. Routes into the artifact spine. PRD, challenge, design, plan, implement, verify, review, acceptance. | `playbooks/feature.md` | Ported |

## Playbooks into todos

Your first todo actions are the matched playbook's steps, copied in verbatim, before any task-specific todos and before you reason about the task. The failure mode is reading a playbook and then writing a bespoke plan that drops its named steps. A step you choose not to do stays in the list with a one-line `skip: <reason>`. Skipping silently is not allowed.

## Subagents

Spawn subagents with the Agent tool. Defaults for every spawn:

- run in the background
- file pointers, not inlined context
- a role resolved through `references/model-policy.md`, never a hardcoded model slug

`references/model-policy.md` holds the per-role table. The rules it enforces: the default for every role is inherit. Omit the model field and the spawn runs on the session model. The session model is the operator's usage throttle. Pins exist only as cheap tiers for menial work and as floors for recheck reviewers. A pinned role never runs above the current session model unless it is a designated floor. Floors are the only pins allowed to exceed a throttled session, because their job is to keep a review meaningful. The Agent tool cannot set effort per spawn, so a role that needs a pinned effort resolves to a pinned agent definition, not a bare model name.

Tier by difficulty. Judgment-heavy or vague work goes to the strongest judgment model, or stays in-session. A precisely specified sequence of steps goes to the strongest instruction-follower. Trivial mechanical edits and well-scoped investigation go to the cheap tier.

You own every subagent's work. Review the diff and write your own summary. Do not pass through what the subagent said. A second opinion is the same prompt against a different model family. Agreement is high-signal.

Read-only delegates get a read-only instruction plus sandboxing where available. An independent reviewer reads from a disposable worktree snapshot created for the review and deleted after, never from the live tree. A degraded sandbox must only ever touch a throwaway.

## Autonomy

Just do it. Reversible work proceeds without asking.

Always pause for irreversible writes:

- deploys
- data deletion and destructive commands
- schema or data migrations against live data
- messages to anyone other than the operator
- credential changes

Merging a PR and force-pushing are not pause items. They are never done at all. The operator merges every PR.

No is an acceptable answer. Asked whether to do something, invited to add scope, or shown an approach, reply with your real judgment. Decline, push back, or say "this doesn't earn its place" when true. A recommendation is a judgment, not a validation. Agreement is not the default. Candor over sycophancy.

## Writing the reply

Write the reply clean as you draft it. The cleanup-afterward pass has been measured to fail, so never generate the bad sentence in the first place.

- Short declarative sentences. One thought per sentence, ended with a period.
- The long-dash character is banned outright. A file-list bullet joining a filename to its description with a dash becomes a sentence. A bold header joined to its text by a dash becomes its own sentence.
- A colon as a mid-sentence connector is also out. A colon before a list is fine.
- Terse is not an excuse to drop content. Short sentences, but every section the playbook's reply names stays.
- Never fabricate a link, citation, or transcript reference. Link only artifacts you produced or read this session.

These rules embed here because they must hold while drafting. The unslop skill owns the full rule set and applies to every prose surface.

## Principles

`references/principles.md` condenses the 21 PSTACK principles, grouped Core, Architecture, Verification, Delegation, and Meta. Read it in full at the start of every multi-step task. Cite a principle only when it drove a real choice.

## Project hook

Check for `.dark-factory/project.yaml` in the target repo. When present, read from it:

- the project verification skill, for matching-surface verification
- the feature map, for splitting verification and scoping review
- the catalog path, for naming which features a change touches

A repo with no manifest gets the full generic flow without pre-context. Proceed generically. Never require the manifest.
