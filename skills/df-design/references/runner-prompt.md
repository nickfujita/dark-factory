# Design runner prompt

The lead passes this file through to every candidate runner during Phase B and fills in the variable inputs around it: the task, the settled requirements, the Phase A grounding artifacts, the isolated working directory, and the path to write outputs. The working directory is a git worktree when available, otherwise a per-runner subdirectory under the sketch dir; what matters is independence between candidates.

You are producing candidate designs in df-design's parallel exploration. Read the **df-design** skill in full first; that's the workflow you're inside. Output a candidate design package: type sketch, function signatures, module map, and prose rationale shaped per [`rationale-template.md`](rationale-template.md).

Apply the following discipline. The lead compares candidates on these axes to pick a base. Principle names cite the df skill's `references/principles.md`.

- Caller's usage first. Write the README-style usage and two or three real call sites before the types, then derive the type sketch from them. The usage is the spec; the two must agree, so reconcile the sketch to the usage, not the reverse.
- Data structures first. Get the core types right and the code becomes obvious. Trace each dominant access pattern through the proposed structure; if the answer is "we'll add a map / index / cache later," the structure is wrong.
- Interface depth. Compare the capability hidden behind the public surface relative to the size of that surface. Prefer a simple interface that pulls complexity into the callee, even when the implementation becomes less simple. Do not put transport or wire types on the public surface; parse into domain types behind the interface.
- Shared state: if two actors might both write, ask "what happens?" If the answer isn't "nothing," default to per-actor state with a merge at the read boundary, per the **separate-before-serializing-shared-state** principle.
- Make boundaries visible. `not implemented` errors for bodies, `// TODO` pseudocode for tricky logic, doc comments stating intent and invariants. A reader should trace data from input to output by reading types and signatures alone.
- Encode invariants in types: hard-to-misuse types > runtime checks > prose comments, per the **encode-lessons-in-structure** principle.
- Validate at boundaries, trust types inside, per the **boundary-discipline** principle. Business logic as pure functions; the shell stays thin.
- Single source of truth per invariant. Derive instead of sync.
- Idempotent state transitions where applicable, per the **make-operations-idempotent** principle. Ask what happens if the operation runs twice or crashes halfway.
- Short call chains. If tracing the flow needs more than three files, flatten the hierarchy, per the **laziness-protocol** and **minimize-reader-load** principles.

Runner count follows the lane. When you are the only runner, produce two structurally distinct candidate packages; whole-shape alternatives, not two flavors of one shape. When you are one of two runners on different models, produce the best design your model can make; don't hedge against the other. Differences between candidates are the signal used to pick a base and graft. Converging on a safe-looking middle defeats the exploration.
