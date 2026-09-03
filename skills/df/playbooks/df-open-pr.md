# Opening a PR

Invoked at the end of every other playbook.

**Worktree.** Work from a git worktree off main; subagents inherit it. Multiple Agent spawns on the same branch each get their own worktree, or reset the worktree to the remote branch between them. Dirty branch with unrelated work: patch out, fresh worktree, apply. Snarled worktree: reset from main, redo minimally. Resets and patch-outs stay inside worktrees created for this run. Never reset the operator's primary checkout.

**Commits.** Commit liberally; rebase into small, ordered commits before the first push. Each commit is a future PR: landable, ordered to tell the story. Amend when the fix belongs in a just-made commit; new commit when separable. Once a branch is pushed it moves forward with new commits. Never force-push.

**Leakage gate.** Before the first push, run `scripts/df-check-leakage.sh` at the dark-factory root the session reminder names. It scans the branch for df's own vocabulary in the project's tree, and a hit is a stop. Fix it by naming the kind of work instead of the skill that did it, per the router's writing-into-the-project rule. Keep finding ids. A deliberate mention gets stated in the PR rather than silently kept.

**PRs.** Write every PR title, PR description, and commit body with `technical-writing`, then apply `unslop`. Apply every technical-writing layer except Diátaxis. Use one word for each action, keep articles, and avoid `-ing` when a plain verb works.

**Titles.** Use Conventional Commits in the form `type(scope): subject`. Use `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, or `perf` as the type. Use the changed area, such as `df` or the touched package, as the scope. Keep the subject short and imperative. Apply the same `technical-writing` and `unslop` pass as the body. Name a real symbol when one carries the change. For example, `fix(df): retarget the open-pr babysit trigger`. Do not add a trailing period.

**Descriptions.** Use these sections in order. Drop a section when it is empty.

- `## Why`. State the intent and why this approach fits.
- `## Scope`. State facts from the diff. Name real symbols and paths. Name both sides of a rename or retarget. State what is in and out when the boundary matters.
- `## Tradeoffs`. State real choices only. Skip this section when there are none.
- `## Blast Radius`. State who and what the change touches. Explain why the change is safe or risky. If main is red without the fix, name the continuing cost.
- `## Verification`. State how you ran each check and its rigor. Name the real path, such as the project verification skill's recipe, agent-browser, or the targeted tests. State the outcome of each check, not only the command name.

After these sections, attach videos or screenshots when they prove a claim. Do not use `## Summary` or `## Test plan` boilerplate. A commit body does not restate its subject.

**Size and dependencies.** Prefer five narrow PRs to one large PR. PRs merge as they land; verified-but-unlanded work counts as zero. Branch from the repository's default branch, normally `main`, for independent work. Never register independent PRs as a stack merely because they belong to one feature. A branch-on-branch chain exists only when an upper PR cannot work without the lower PR. Name the full bottom-to-top order in every chained PR's description, even when GitHub shows its stack map.

**Native stack registration.** Create, push, and open the plain dependent PR chain first. After at least two ready PRs exist, run `bash scripts/df-stack.sh link --repo <owner/repo> <bottom-pr> <next-pr> [...]`. Pass PR numbers only, in bottom-to-top order. Exit 0 means the helper created, extended, or confirmed a native GitHub stack. Exit 2 means the CLI or repository lacks preview support. Keep the plain chain unchanged and report the helper's exact fallback reason. Any other exit is a stop because the chain is invalid or GitHub rejected the registration. The helper preflights every PR and uses only the REST create or add endpoint. It never pushes, creates a PR, changes a base, rewrites history, or merges. Do not substitute `gh stack link`, `gh stack submit`, `gh stack sync`, `gh stack rebase`, `gh stack push`, or `gh stack merge`.

**Native stack verification.** Native stacks do not replace review or CI. GitHub applies the trunk branch's rules and CI to every layer. Treat a server-side cascading rebase, or any other new head SHA, as new remote state. Repeat the applicable review, live verification, and CI gates for that SHA before calling the PR merge-ready.

**Readiness and merge.** Open every PR ready, never as a draft. Agent PR tools that default to draft get `draft: false` on every creation call. If a PR still opens as a draft, run `gh pr ready <number>`. Run `gh pr view <number>` before you refer to PR status. Never merge a PR or a stack, in any lane, under any instruction short of the operator's own message. The operator merges every PR. Posting the URL is this playbook's finish line.

**Cleanup.** Clean up only worktrees this run created; every other workspace belongs to the host and stays in place. If `git worktree remove` refuses because the worktree contains modified or untracked files, those files exist nowhere else. Never reach for `--force` on your own initiative, on this or any git command. Run `git -C <worktree> status --porcelain -uall`, show the operator the file list, and ask whether to commit the files to the branch, move them into the main repo, or delete them. Delete only on the operator's explicit word, then remove the worktree.

**Babysit.** Opening a PR does not start a babysit. Post the URL and keep building. Finish the phase or chain first. Run a separate babysit pass only when the operator asks for one after the whole chain exists. The babysit playbook owns that pass. A babysit for each new PR stalls the build and spends checks on commits that later waves restart. Push back when feedback drifts from intent.

A subagent that opens a PR returns the URL and does not babysit. Review depth comes from the lane's review policy, never from an extra pass here. Return to the parent.
