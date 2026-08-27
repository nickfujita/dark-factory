---
name: swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration. Runs when a df playbook dispatches it or the operator names it."
disable-model-invocation: true
---

# Swarm

Fan out N parallel workers. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report. No raw dumps.

Principle names in this skill cite `../df/references/principles.md`.

## Start

Open a todo list with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare the selection rule before spawning: `first pass`, `rank all`, or `best-of`.
3. Set N from the user or derive it from the shape. N is total workers. Concurrency is capped separately at 3; a larger N runs as a rolling window.
4. Resolve worker models through roles in `../df/references/model-policy.md`, never a hardcoded slug. Read-only coverage, verification, and exploration slices run the menial investigation tier. Workers that write code run the implementation-delegate role. A model race names each arm's role or family up front.
5. Give each writing worker its own writable output, per the separate-before-serializing-shared-state principle. A worktree, a branch, or its own subdirectory under the session scratchpad. Read-only workers get a read-only instruction instead.
6. For verification coverage, when `.dark-factory/project.yaml` names a feature map, slice by feature-map entry so every slice traces to a named feature and the gaps are enumerable.
7. Inside a df run, reserve every worker through `scripts/df-state.sh` before spawning; swarm workers are nested dispatches and count against the run's budget. The script lands in this same wave; until it is on disk, write the reservation lines to the run state file by hand, still before spawning.

## Phase B: Fan out

Spawn workers with the Agent tool, in the background, at most 3 concurrent. Refill the window as workers finish rather than waiting on blocking batches, which cost the slowest worker of every batch.

Every brief stands alone. Include the goal, the scope, the exact slice or race arm, how to verify, and what to report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence. Workers never spawn their own subagents.

If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read the terminal results. For coverage, every required slice needs a result; a missing slice is a gap, not a pass. For a race, apply the selection rule declared up front, never one invented after seeing the outputs. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report: the table, the issue one-liners, the gaps or dropouts, and the race rule when one was used.
