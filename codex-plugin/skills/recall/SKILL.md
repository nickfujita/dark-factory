---
name: recall
description: "Reconstruct recent working context from the df trail (run state files, decision logs, pause notes), git and gh, and the shared record (user reports, prior fixes, incidents), then hand back a tight current-state brief. Use for 'recall my work on X', 'catch me up', 'what have I been working on', 'where did I leave off', before starting or resuming work."
---

# Recall

**Before you start or resume work, rebuild the user's recent working context and hand back a tight capsule of where things stand now and what to do next.** Use for "recall my work on X", "catch me up", "what have I been working on", or "where did I leave off".

Keep it tight and on-topic. Read only what the in-scope threads need, then stop. Heavy reading fans out to parallel subagents. The main thread keeps only their findings and the final brief.

Your context lives in two records. The df trail holds what past sessions did and decided: run state files and reports under `.dark-factory/`, decision logs (`decisions.tsv`, `.audit/*.tsv`) kept by the show-me-your-work skill, pause notes written by the pause-safely playbook, and the branches, worktrees, commits, and PRs those sessions left behind. The shared record holds everything that happened around the same code under other names: the symptoms users keep reporting, the fixes that shipped and got reverted, the errors still firing in prod. That second record is what the **why** skill searches, across source control, the issue tracker, chat channels, long-form docs, and error tracking. A feature with a long bug tail keeps most of its story there, so don't reconstruct it from the local trail alone.

This is a read-only skill. It reads the trail and reports. It never edits the trail it reads.

1. Classify, then route. One specific prior session to resume is the `session-pickup` playbook (`../df/playbooks/session-pickup.md`), not this. A human-readable summary of your work for someone else is a different task. Recall loads working context across recent work before you act. If the user already gave you a full state capsule (paths, branch, the change), use it and skip the mining.
2. Lock the scope before searching. Pin the window ("recent" is a real range, default the last 7 days), the topic if named, and the repo (default the current one; never read another project's trail without being asked). State the scope back. Never quietly turn "all" into "recent N".
3. Mine the df trail. Look in this order: pause notes and run state files under `.dark-factory/`, decision logs (`decisions.tsv`, `.audit/*.tsv`), recent branches and worktrees (`git branch --sort=-committerdate`, `git worktree list`), recent commits in the window, the operator's open and recently merged PRs (`gh pr list --author @me`), and the reports and docs those files point at. Order candidates by real modification time, never by name. Grep the topic first, then read only the matching files and only their relevant regions. For a large trail, fan the reading out to parallel subagents on the menial investigation role from the df model policy (`../df/references/model-policy.md`), each read-only by instruction and each taking a slice of the trail. Each returns the same schema, one block per thread: topic, the user's goal, decisions, open threads, struggles and corrections, and artifacts (PRs, tickets, branches), each citing a file path, commit SHA, or PR number. For a small trail, skip the fan-out and read directly. The raw files stay in the subagents. The main thread gets only their findings.
4. Sweep the shared record whenever the topic names a feature, file, subsystem, area, or bug. This is the default, not a judgment call, and "my work on X" does not exempt it. A named target carries history the local trail never sees, and that history is the point of the sweep. Hand it to the **why** skill's source investigators, but steer their question from "why was this built this way" to "what's the current state, what's been tried and didn't hold, and what are users still reporting". Reuse its per-source playbooks so you don't reinvent each query vocabulary, run the investigators in parallel with the trail mining, and inherit its posture: one investigator per source, null results are findings, skip an unavailable MCP and say so. Fold what comes back into the brief. Skip this step only for pure activity recall with no named target ("what did I do this week"), where the trail and live state are the entire answer.
5. Verify against live state. A trail file or a stale ticket is history, not current truth, so take the PRs, branches, and tickets that the mining and the sweep surfaced and check them with `git` and `gh`. Where the trail is silent about what a past session actually did, say so in the brief. A named gap beats a papered-over one.
6. Write the brief to the contract below. Group by thread. Stay on the named topic.

## Output contract

Lead with the capsule, then the thread status, then the problems, then the next move. Deeper detail goes below or gets cut.

- **Capsule.** At most 5 bullets. What this work is and where it stands overall.
- **Threads.** One line each, prefixed with exactly one status tag: `[merged #N]`, `[open PR #N]`, `[in flight <branch>]`, `[verified, uncommitted]`, `[reverted #N]`, or `[planned, not started]`. A thread with no tag is not done yet, so tag it.
- **Problems.** At most 5, the recurring ones. Include the symptoms users keep reporting and any fix that shipped and was reverted, so the next attempt starts where the last one failed.
- **Next move.** The single most useful next action, concrete.

An adjacent feature or ticket stays out unless it blocks this one. When the capsule and thread lines outgrow a screen, cut detail before you cut threads. Write the brief through the **unslop** skill, cite trail findings by file path or commit SHA and shared-record findings by their source (PR #, ticket ID, doc URL, error-tracker issue), and sanitize private context before any public output.

**Reply:** the brief, to the contract above.
