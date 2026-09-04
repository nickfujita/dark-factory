# Claude-to-Codex background workers

This transport belongs only to the Claude Code version of Dark Factory. A
Codex coordinator uses native Codex subagent threads and worktree chats.

Use `scripts/df-codex-exec.sh` when a Claude coordinator deliberately assigns
one unit in a parallel program to Codex and needs at least one of these
properties:

- Codex-family execution rather than another Claude subagent
- a worker whose Codex conversation survives the Claude coordinator session
- several supervised turns against the same accumulated Codex context

Do not use it for an ordinary Claude worker; use the Agent tool. Do not use it
for a one-shot independent review; use `scripts/df-codex-review.sh`, which owns
the read-only snapshot and review-result contract. Do not select it merely
because work is long-running. The orchestrate playbook's program threshold and
three-worker cap still apply.

## Start

The Dark Factory root is the path printed by the SessionStart hook. Create the
program run first, reserve the dispatch, and write the standalone brief. Then
place the Codex session state inside that run's external state directory:

```bash
df_root=<dark-factory-root>
run_id=<run-id>
worker=<worker-name>
run_dir=$(bash "$df_root/scripts/df-state.sh" path "$run_id")
export DF_CODEX_STATE_ROOT="$run_dir/codex"

bash "$df_root/scripts/df-codex-exec.sh" start "$worker" \
  --cd <exclusive-checkout-or-worktree> \
  --brief <brief-file> \
  --model <model> \
  --effort <effort>
```

Run the final command with Claude Code's background-process facility. The
default Codex sandbox is `workspace-write`. Only pass
`--dangerously-bypass-approvals-and-sandbox` when the checkout and host provide
the external isolation that flag requires. The selected security mode is fixed
for the session and reused on every resume.

Every brief and follow-up prompt carries the run's standing orders verbatim and
ends with the required `REPORT` contract. One worker owns one checkout or
worktree. The coordinator remains the only writer of the run store.

## Drain and resume

Check state without waking the worker:

```bash
bash "$df_root/scripts/df-codex-exec.sh" status "$worker"
```

When a turn has ended, read its `turn-N.exit`, `turn-N.last.md`, and any report
file required by the brief. These are claims. Verify the branch, files, tests,
and external effects before recording the dispatch disposition.

Send another bounded unit only after the prior wrapper has exited:

```bash
bash "$df_root/scripts/df-codex-exec.sh" resume "$worker" \
  --prompt <next-prompt-file>
```

The wrapper retries provider capacity, rate-limit, and transient 5xx failures
by resuming the same Codex thread. `DF_CODEX_MAX_RETRIES` and
`DF_CODEX_RETRY_SLEEP` bound that behavior. Other failures return to the Claude
coordinator for disposition.

## Coordinator restart

The durable identity is the recorded Codex thread ID, not the wrapper PID. If a
Claude session or VM restart interrupts a turn, inspect `status`, confirm no
wrapper process remains, and resume with one bounded continuation prompt. Do
not restart from the original brief and do not infer completion from the final
message alone.

Sessions created by the original private transport did not record their sandbox
mode and always used Codex's dangerous bypass. The public runner recognizes
that legacy metadata and preserves its existing mode on resume with a warning.
New sessions default to `workspace-write` and always persist their mode.
