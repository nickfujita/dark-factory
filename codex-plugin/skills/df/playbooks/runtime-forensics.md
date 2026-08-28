# Runtime forensics

**You own the diagnosis. Instrument the live process, don't theorize from source.** For "why is X leaking / spinning / slow at runtime", heap snapshots, idle-but-busy processes, intermittent glitches. The deliverable is a cited diagnosis, not a fix.

1. Capture the live signal on the matching surface: a CPU profile for a spinning process, a heap snapshot for a leak, a devtools trace for a visual glitch. Drive the surface through the repo's verification skill when it has one, otherwise the closest surface you can reach yourself, such as a local run or agent-browser for UI. A real artifact, not a guess.
2. Reduce the artifact to the smoking gun: the function on the hot path, the retainer chain from the leaked object to a GC root, the loop firing without input. Parse large artifacts in a subagent on the menial investigation role from `references/model-policy.md`, per the guard-the-context-window principle. Keep the reduced finding in the main thread.
3. Prove the mechanism before believing it. Inject instrumentation into the running process (CDP eval for a browser or Electron target), or hotfix the live code without reloading, to confirm the hypothesis cheaply. A plausible-but-unconfirmed cause can be wrong while the real one sits one layer over.
4. Map the finding back to source: file, symbol, the line that allocates or schedules.
5. The run state entry stays one line, `finish predicate: cited diagnosis, read-only`.

**Reply.** The signal captured, the reduced finding, how you proved the mechanism, the source location, and the artifact paths. No fix unless asked. Hand back to the operator and re-route through `/df` to Bug fix or Perf issue once the cause is known.
