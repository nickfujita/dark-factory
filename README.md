# dark-factory

A reusable AI development workflow framework that moves feature development
toward autonomous operation. Skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
and [Codex CLI](https://github.com/openai/codex) that orchestrate the full
lifecycle — from requirements gathering through QA acceptance.

## Background: What Is a Dark Factory?

Borrowed from manufacturing, where robots work in unlit facilities because they
don't need to see. Applied to software: **specifications go in, tested software
comes out.** The human defines *what should exist*; machines handle everything
between the spec and the shipping artifact.

This framework is built around
[Dan Shapiro's Five Levels of AI-assisted development](https://www.danshapiro.com/blog/2026/01/the-five-levels-from-spicy-autocomplete-to-the-software-factory/),
modeled after NHTSA driving automation levels. See also:

- [Simon Willison — StrongDM Software Factory](https://simonwillison.net/2026/Feb/7/software-factory/)
- [Stanford Law — Built by Agents, Tested by Agents, Trusted by Whom?](https://law.stanford.edu/2026/02/08/built-by-agents-tested-by-agents-trusted-by-whom/)
- [Anthropic — 2026 Agentic Coding Trends Report](https://resources.anthropic.com/2026-agentic-coding-trends-report)

## The Five Levels

| Level | Name | Description |
|-------|------|-------------|
| 0 | Manual | Traditional development — no AI assistance |
| 1 | Task Automation | AI writes tests, docs, boilerplate |
| 2 | Paired Programming | Developer pairs with AI in IDE |
| 3 | Human-in-Loop Management | AI acts as senior dev, human manages each step |
| 4 | Autonomous Operation | Developer becomes PM — writes specs, AI handles the rest |
| 5 | Dark Factory | Black box: specs in, tested software out |

### Where this framework lands today

> **Level 3.5** — Late Level 3 / Early Level 4

The framework has the infrastructure for Level 4 but still expects the human
to be hands-on at key checkpoints. Here's what's covered and what's not:

#### Level 4 capabilities (implemented)

- [x] **Formalized PRD interview** with hard quality gate checklist (`drk-01-prd-interview`)
- [x] **PRD challenge round** — Claude flow uses 3 Claude personas + Codex; Codex flow uses Codex persona subagents + interactive Claude Code via tmux. Discovery rounds, verification rounds and consistency-only passes, with a trend-aware gate and an explicit termination rule (`drk-02-prd-challenge`)
- [x] **Machine-generated QA runbook** from hardened PRD, with bidirectional coverage checks (`drk-03-qa-runbook-gen`)
- [x] **Document validation** — Claude flow uses Claude + Codex; Codex flow uses Codex inline + Codex CLI review (`drk-04-qa-runbook-validation`)
- [x] **Autonomous implementation** via Superpowers subagent-driven development (once plan is approved)
- [x] **Developer self-verification** — tests + QA inline before review (`drk-05-dev-verify`)
- [x] **Code review** — Claude flow uses Claude personas + Codex reviewers; Codex flow uses Codex subagents + interactive Claude Code reviewers via tmux (`drk-06-code-review`)
- [x] **Automated QA acceptance** via agent-browser (`drk-07-qa-acceptance`)

#### Level 4 gaps (not yet implemented)

- [ ] **Claude master orchestration skill** — the Codex flow has `dark-factory-codex`; the Claude flow stages are still invoked manually in sequence
- [ ] **Autonomous brainstorming/architecture** — the human still participates in technical design via Superpowers brainstorming rather than delegating fully to the black box
- [ ] **Cross-feature knowledge base** — no persistent store of patterns and decisions that primes future agent sessions
- [ ] **Automated security pipeline** — gitleaks + Semgrep pre-commit hooks and CI security review are documented in the plan but not yet packaged as skills
- [ ] **Auto-generated ADRs and Feature Delivery Reports** — architectural decision records and post-pipeline transparency artifacts

#### Level 5 gaps (future)

- [ ] Self-healing loop (agent autonomously fixes QA failures and retests)
- [ ] PRD-triggered pipeline (commit a PRD file, full pipeline runs via CI)
- [ ] Regression suite conversion (passing runbooks → deterministic Playwright scripts)
- [ ] Gemini CLI as third reviewer model
- [ ] Periodic automated architectural health reviews
- [ ] Performance regression testing (Lighthouse CI, bundle size tracking)

### A note on intentional human involvement

Not every gap above is something you'd *want* to close. Keeping the human in
the loop for technical architecture decisions is a deliberate choice — the PRD
defines *what* to build, but *how* to build it benefits from human judgment,
especially for complex systems. The framework is designed so you can
progressively remove yourself from steps as trust builds, rather than going
fully autonomous from day one.

## Prerequisites

### Superpowers (required)

This framework works in tandem with the
[Superpowers](https://github.com/obra/superpowers) plugin. Superpowers provides
the implementation engine: brainstorming, plan writing, TDD enforcement,
subagent-driven development, systematic debugging, code review, and git
worktree isolation.

Install Superpowers in Claude Code:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

Install Superpowers in Codex:

```
codex plugin add superpowers@openai-curated
```

### Codex CLI (required for Codex flow and cross-context reviews)

The Codex-native flow uses [Codex CLI](https://github.com/openai/codex),
Codex skills, Codex subagents, and fresh `codex exec` review processes for
Codex-owned review work. Install it and ensure `codex` is on your PATH.

### Claude Code + tmux (required for Codex flow cross-model reviews)

When Codex is the Dark Factory driver, secondary Claude Code reviews are run as
interactive Claude Code sessions inside `tmux`. The Codex flow does not use
`claude -p`, `--print`, SDK mode, stdout piping, or other non-interactive
Claude invocation modes.

### agent-browser (required for QA acceptance)

The QA acceptance skill (`drk-07`) uses
[agent-browser](https://github.com/vercel-labs/agent-browser) for browser
automation. Install it and ensure `agent-browser` is on your PATH.

## Pipeline Overview

The diagram below shows the original Claude Code-oriented flow. The Codex fork
keeps the same artifact gates but flips reviewer ownership: Codex performs the
first looping reviewer phase, then uses interactive Claude Code sessions in
tmux for the secondary cross-model pass.

```
┌─ HUMAN IN THE LOOP ─────────────────────────────────────────┐
│                                                               │
│  Stage 1: PRD Interview (drk-01)                              │
│    Conversational loop until quality gate passes              │
│                                                               │
│  Stage 2: PRD Challenge Round (drk-02)                        │
│    3 Claude personas + Codex → synthesized questions          │
│                                                               │
├─ MACHINE RUNS (no human interaction) ────────────────────────┤
│                                                               │
│  Stage 3: QA Runbook Generation (drk-03)                      │
│    Machine-generates QA from hardened PRD                      │
│                                                               │
│  Stage 4: Multi-model Validation (drk-04)                     │
│    Claude + Codex review PRD + QA pair                        │
│                                                               │
├─ HUMAN SIGN-OFF ─────────────────────────────────────────────┤
│                                                               │
│  Stage 5: Review and approve PRD + QA + validation report     │
│                                                               │
├─ DEVELOPMENT BLACK BOX ──────────────────────────────────────┤
│                                                               │
│  Brainstorming → Plan → TDD Implementation (Superpowers)      │
│  Developer Self-Verification (drk-05)                         │
│  Multi-model Code Review (drk-06)                             │
│  QA Acceptance (drk-07)                                       │
│                                                               │
├─ HUMAN FINAL GATE ───────────────────────────────────────────┤
│                                                               │
│  Manual sanity check + lead dev PR review                     │
└───────────────────────────────────────────────────────────────┘
```

## What This Repo Contains

```
dark-factory/
  skills/                        # Claude Code skill source of truth
    drk-01-prd-interview/        # PRD authoring with quality gates
    drk-02-prd-challenge/        # Multi-model PRD stress-testing
    drk-03-qa-runbook-gen/       # Machine-generated QA from PRD
    drk-04-qa-runbook-validation/# Multi-model PRD + QA validation
    drk-05-dev-verify/           # Developer self-verification loop
    drk-06-code-review/          # Multi-model code review
    drk-07-qa-acceptance/        # Browser-based QA execution
    agent-browser/               # Browser automation primitives
    skill-creator/               # Helper for creating new skills
  codex-skills/                  # Codex-native Dark Factory skill fork
    dark-factory-codex/          # Master Codex orchestrator
    drk-01-prd-interview/        # Codex PRD authoring with quality gates
    drk-02-prd-challenge/        # Codex persona subagents + Claude tmux review
    drk-03-qa-runbook-gen/       # Codex QA runbook generation
    drk-04-qa-runbook-validation/# Codex inline + CLI validation
    drk-05-dev-verify/           # Codex developer self-verification
    drk-06-code-review/          # Codex subagents + Claude tmux code review
    drk-07-qa-acceptance/        # Browser-based QA execution
    agent-browser/               # Browser automation primitives
  agents/                        # Claude agent definitions (one .md per agent)
    drk-reviewer-recheck.md      # Downgraded-tier reviewer for scoped rechecks
  manifests/
    skills.tsv                   # Managed skill mapping (platform + source + target)
    agents.tsv                   # Managed agent-definition mapping
  scripts/
    sync-to-global.sh            # Repo → global skill dirs (install/update)
    sync-from-global.sh          # Global skill dirs → repo (reverse sync)
  profiles/
    default.env.example          # Optional path overrides per machine
  examples/
    qa-runbooks/                 # Generic QA runbook examples
  plans/
    DARK-FACTORY-PLAN.md         # Full architecture and vision document
```

No project application code lives here. Skills are designed to be
project-agnostic and work across any repo.

## Installation

Skills are copied with `rsync` (or `cp` fallback), not symlinked.

- Claude skills target: `~/.claude/skills/`
- Codex skills target: `~/.codex/skills/` by default
  (`CODEX_SKILLS_HOME` can override this for environments that load
  `~/.agents/skills/`).
- Claude agent definitions target: `~/.claude/agents/`

### Agent definitions

Some skills spawn sub-agents at a pinned model and reasoning effort. Reasoning
effort cannot be set per-spawn on the Agent tool — only `model` can — so the
effort has to live in an agent definition's frontmatter. Those definitions are
single markdown files in `agents/`, mapped by `manifests/agents.tsv`, and
installed to `~/.claude/agents/` by the same sync scripts.

Conventions:

- one file per agent, named `<agent-name>.md`
- YAML frontmatter with `name` (must equal the filename stem), `description`,
  and any pinned `model` / `effort` (`low|medium|high|xhigh|max`)
- `just check-agents` validates all of the above

A subagent spawned without an explicit `model` or `subagent_type` inherits the
orchestrating session's model and effort. Skills use that deliberately: tiers
the operator should control from above are left unpinned, and only tiers that
need a guaranteed floor get an agent definition.

The Claude and Codex flows intentionally live in parallel. The Claude flow in
`skills/` remains the stable baseline. The Codex flow in `codex-skills/` uses
Codex-native skills, subagents, and Superpowers plugin invocations.

`skills/skill-creator` remains in the repo as a Claude-oriented helper, but it
is not installed as a managed Codex skill. Codex uses its own built-in/system
`skill-creator`.

### Install / Update Global Skills

```bash
just sync-dry
just sync
```

### Reverse Sync Changes Back Into Repo

```bash
bash scripts/sync-from-global.sh --dry-run
bash scripts/sync-from-global.sh
```

### Same Commands via `just`

```bash
just sync-dry
just sync
just sync-to-global-dry
just sync-to-global
just sync-from-global-dry
just sync-from-global
```

### Checks

```bash
just check
```

`just check` validates shell scripts, the skills manifest, skill reference
directories, agent definitions, and bundled Python helper scripts.

### Multi-Machine Workflow

If you develop across multiple machines or VMs:
1. Edit/test global skills on one machine.
2. Run reverse sync into this repo.
3. Commit and push from this repo.
4. Pull on other machines and run forward sync.

### Optional Machine Profile

To override default global locations per machine:

```bash
cp profiles/default.env.example profiles/my-machine.env
bash scripts/sync-to-global.sh --profile profiles/my-machine.env
```

## Related

- [Dark Factory plan](./plans/DARK-FACTORY-PLAN.md) — full architecture, vision, and gap analysis
- [Sample QA runbook](./examples/qa-runbooks/qa-sample-checkout-flow.md)
- [Superpowers](https://github.com/obra/superpowers) — required plugin for the implementation engine
- [Dan Shapiro — The Five Levels](https://www.danshapiro.com/blog/2026/01/the-five-levels-from-spicy-autocomplete-to-the-software-factory/) — the framework this is built on
