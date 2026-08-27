# Session pickup

**You own the resume point. Read the prior trail, don't redo it.** For "take over this", "resume this", "you're taking over", "pick up where X left off", or a pushed branch you're meant to continue.

A pickup is inheritance. The prior agent already paid the cost of reading the code, running the repros, making the design choices. Redoing loses the bias check and burns context. Resist the urge to re-derive. Read.

1. Locate the prior trail, meaning the trail files the prior session wrote. The run state files, `decisions.tsv` where a show-me-your-work trail exists, and the resume note, whose path the last `wip:` commit body names. A pushed branch is a trail too. Read the resume note and the latest decisions first, then scan back for the decision points. Parse a long trail in a subagent and keep the reduced timeline in the main thread, per the guard-the-context-window principle in `references/principles.md`.
2. Reconstruct operational state. The branch and worktree, what already landed (`git log`, `git diff` against the base), the open todos, the decisions made. The prior trail is authoritative input. Resist the bias to re-derive it.
3. Diff done vs pending. Compare what shipped against what was planned, name the resume point, and do not re-run the prior repro or redo completed work. A "let me verify from scratch" pass is the tell that you're treating the trail as untrustworthy when it's actually authoritative.
4. Route the remaining work through the `/df` routing table to the matching playbook and pick the verdict: continue the execution, ship a finished recommendation, ratify or override a prior conclusion, or postmortem a failed run. The pickup playbook ends here. The routed playbook owns the rest.
5. Verify the inherited claims against the original goal on the real artifact, per the prove-it-works principle. A passing prior self-report is not the proof.

**Reply.** Where the prior agent stopped, what you inherited versus redid (ideally nothing redone), the resume point, and the outcome.
