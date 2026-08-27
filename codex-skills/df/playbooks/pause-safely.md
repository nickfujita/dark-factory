# Pause safely

**You own a clean stop. Leave a checkpoint a cold-start agent can resume from.** For "pause safely", "I need to go offline", "restarting the harness", or "board my flight", and when context is about to compact or summarize. This is explicit only. On "keep going", "going to bed, keep going", or "don't stop", do not pause. Those mean continue. Per-iteration checkpoints belong to the autonomous-run playbook.

1. Stop at a safe boundary. Finish the current atomic step or back out of it. Never stop mid-edit in a known-broken state. Start nothing new, and cancel any nested subagents.
2. Don't cross an irreversible line to pause. No PR and no push unless you already had one out.
3. Make the work durable. Commit uncommitted edits as one clear `wip:` commit on the current branch so nothing is lost. If the tree is broken, say so in the commit body in one line.
4. Write the resume note off-context. Capture intent, what you were doing, progress and what's verified, current state, next steps, key files, and gotchas. Write it to the session scratchpad directory the harness names, as `<slug>-resume.md`, never to bare `/tmp`. The in-context plan won't survive summarization. Name the note's absolute path in the `wip:` commit body so a cold-start session can find it from git alone. If a show-me-your-work trail exists, meaning `decisions.tsv` and its log, point at it instead of duplicating it.

**Reply.** Where you are in the loop, what's on disk versus still in your head (paths, no diff dumps), the commits you made and whether the tree is clean, and the first action on resume. This is a pause, not a final report. Resume is the session-pickup playbook reading this note.
