---
name: dark-factory-codex
description: "Codex-native Dark Factory orchestration for taking a feature from PRD interview through QA acceptance. Use when the user asks to run the Dark Factory flow in Codex, start a new feature pipeline, or continue an approved PRD/QA pipeline using Codex skills and Codex Superpowers."
---

# Dark Factory Codex Orchestrator

Run the Dark Factory pipeline in Codex while keeping stage transitions under
this orchestrator's control. Do not rely on implicit skill chaining from a
stage skill. Invoke each stage explicitly and pass artifact paths forward.

## Preconditions

- Codex Superpowers plugin is installed and enabled.
- `agent-browser` is installed and available when QA execution is needed.
- The project repo is clean enough for the requested stage, or the user has
  explicitly approved working with the current dirty state.

## Pipeline

### Stage 1: PRD Interview

Invoke `drk-01-prd-interview` to create or harden the PRD.

Output artifact: `docs/prd-<feature-slug>.md`.

### Stage 2: PRD Challenge

Invoke `drk-02-prd-challenge` with the PRD path.

The stage runs Codex persona subagents first, then an interactive Claude Code
review through tmux. Do not use `claude -p` or other non-interactive Claude
invocation modes.
It edits the PRD autonomously until the Critical/High gate passes or the round
cap requires user input.

Output artifact: approved PRD plus `.dark-factory/reviews/prd-challenge/<timestamp>-<feature>-prd-challenge.md`.

### Stage 3: QA Runbook Generation

Invoke `drk-03-qa-runbook-gen` with the approved PRD path.

Output artifact: `docs/qa/qa-<feature-slug>.md`.

### Stage 4: PRD + QA Validation

Invoke `drk-04-qa-runbook-validation` with both paths.

On user approval, explicitly invoke Codex Superpowers `brainstorming` with the
approved PRD, QA runbook, and engineering standards paths. After brainstorming,
continue with Codex Superpowers `writing-plans`. Ensure the final plan task is
to invoke `drk-05-dev-verify`, not `finishing-a-development-branch`.

### Stage 5: Implementation

Use these Codex Superpowers skills in order unless the project context clearly
requires a narrower path:

1. `superpowers:brainstorming`
2. `superpowers:writing-plans`
3. `superpowers:using-git-worktrees` when branch/worktree isolation is needed
4. `superpowers:test-driven-development`
5. `superpowers:subagent-driven-development`
6. `superpowers:systematic-debugging` for failing tests, failed QA, or unclear bugs
7. `superpowers:verification-before-completion` before claiming implementation is complete

Keep Dark Factory in control of the pipeline. If a Superpowers skill suggests a
next skill that conflicts with this pipeline, record the suggestion and follow
this orchestrator instead.

### Stage 6: Developer Self-Verification

Invoke `drk-05-dev-verify` after implementation is nominally complete.

This stage runs tests, executes QA inline, fixes failures, and enforces e2e
coverage for every QA runbook `TC-xxx`.

### Stage 7: Code Review

Invoke `drk-06-code-review`.

The stage runs parallel Codex review subagents first, then interactive Claude
Code reviewers through tmux. It applies required fixes autonomously and writes a
durable report. Do not use `claude -p` or other non-interactive Claude
invocation modes.

### Stage 8: QA Acceptance

Invoke `drk-07-qa-acceptance` with the QA runbook path.

This stage runs the acceptance suite with `agent-browser` and writes immutable
QA result reports.

## Stage Control Rules

- Pass artifact paths explicitly between stages.
- Stop for user input only at documented gates, unresolved Critical/High
  findings, production-like QA URLs, missing required artifacts, or repeated
  non-convergence.
- Use Codex subagents only when a stage explicitly calls for parallel reviewer
  or implementation agents.
- Keep scratch pointers in `.dark-factory/tmp/` and run-scoped scratch files
  under `/tmp/dark-factory-*`, not `.claude/`.
- Do not move, rewrite, or normalize the Claude Dark Factory skills while
  running this Codex pipeline.
