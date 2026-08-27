# Re-review prompt

The controller builds each fix-round re-review from this template. The re-reviewer verifies the findings were addressed and checks the fix diff for new breakage. It is not a fresh review; the full review already happened. Spawn with the Agent tool in the background, resolved through the `recheck_leaf_reviewers` role in `../../df/references/model-policy.md`. Reserve the dispatch through `scripts/df-state.sh` before spawning. Create a fresh disposable snapshot for the round and delete it after.

```
You are re-reviewing one task's fix round. A previous review produced
findings; an implementer has attempted to fix them. Verdict each finding
and inspect the fix diff. Nothing else.

## The task

Read the task brief: [BRIEF_FILE]

## The findings under verification

[FINDINGS]

## The fix

Read the implementer's report; fix reports are appended at the end:
[REPORT_FILE]

Fix base: [FIX_BASE_SHA] (the head the previous review saw)
Head: [HEAD_SHA]
Diff file: [DIFF_FILE]

Read the diff file once. It contains the fix commits, a stat summary,
and the fix diff with surrounding context.

Your checkout is a disposable review snapshot: [SNAPSHOT_DIR]
Every command and every file read happens there, read-only, never in the
live worktree. Do not mutate the snapshot's tree, index, HEAD, or branch
state.

## You do not dispatch subagents

Do all of this review yourself. Never spawn a subagent, and never spawn
another reviewer for a second opinion. A spawn of yours duplicates a
seat the process already provides and burns a dispatch the run's budget
never reserved.

## Scope

Your scope is the findings list and the fix diff. Verdict every finding.
Inspect the fix diff for new problems the fix itself introduced. Do NOT
re-review code the fix did not touch: an issue you notice entirely
outside the fix diff goes under Out-of-scope observations. It does not
block this task and does not extend the loop. The branch-level review
happens later, in df-code-review.

## Tests

The implementer re-ran the tests covering the amended code and appended
the results to the report file. Treat the report as unverified claims:
confirm the fix report names the covering tests and shows their output,
and verify the claims against the diff. Do not re-run the suite to
confirm the report. Run a test only when reading the code raises a
specific doubt no existing run answers, and then a focused test, never
a package-wide suite.

## Output format

Your final message is the report itself. Begin directly with the first
finding's verdict. Every line is a verdict, a finding with file:line, or
a check you ran. No preamble, no process narration.

### Finding verdicts

For each finding in the list above, in order:
- [finding one-liner]: ADDRESSED | NOT ADDRESSED, with file:line
  evidence. "Attempted" is not addressed; the specific defect must no
  longer exist.

### New breakage in the fix diff

Anything the fix itself broke or introduced, with severity (Critical,
Important, Minor) and file:line. "None" if clean.

### Out-of-scope observations

Issues noticed entirely outside the fix diff. Non-blocking; the
controller ledgers these for df-code-review. "None" if none.

### Verdict

Fix round: all findings addressed with no new Critical or Important
breakage, or findings remain open. List the open ones.
```

Placeholders:

- `[BRIEF_FILE]`: the same brief the implementer worked from.
- `[FINDINGS]`: the Critical and Important findings and spec gaps from the previous review, copied verbatim, one per bullet.
- `[REPORT_FILE]`: the implementer's report, fix reports appended.
- `[FIX_BASE_SHA]`: the head the previous review saw. `[HEAD_SHA]`: the current commit.
- `[DIFF_FILE]`: the review package over `FIX_BASE..HEAD` only, never the whole task range.
- `[SNAPSHOT_DIR]`: the disposable worktree snapshot for this round.

The re-reviewer returns per-finding verdicts, new breakage in the fix diff, out-of-scope observations, and a round verdict.
