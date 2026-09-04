# Principles

Condensed from PSTACK's 21 principle skills. The df skills cite this file. It has no trigger of its own. When a principle drives a decision, name it in the reply along with the choice it changed. Quoted phrases are verbatim from the leaf skills.

## Core

### Laziness protocol

Applies when refactoring, sizing a diff, or tempted to add abstractions, layers, or signal threading. Aim for the most result with the least code and complexity. "Prefer deletion" and "minimize the diff". The prime directive is "If a human developer would find the code exhausting to maintain, it is a bad solution. Be lazy. Stay simple."

### Foundational thinking

Applies before writing logic, when choosing core types and data structures, sequencing scaffold-vs-feature work, or asking what concurrent actors share. "Get the data shape right before writing logic. The right shape makes downstream code obvious." "A data-structure change late is a rewrite. Early, it is often a one-line diff." Scaffold first when something helps every later phase, and subtraction comes before scaffolding.

### Redesign from first principles

Applies when integrating a new requirement into an existing design. Do not bolt it on. Redesign "as if the requirement had been there from the start", so the result looks like "what we would have built if we'd known on day one". Think about the redesign holistically, then deliver it incrementally.

### Subtract before you add

Applies when sequencing an addition, refactor, or rewrite. "Remove complexity first, then build." Deletion gives a simpler base that makes the next addition smaller and less brittle. "No speculative validators, parsers, or guards beyond what the spec demands." When a reference has no novel content, delete it rather than leaving a stub.

### Minimize reader load

Applies when reviewing or shaping code that is hard to trace. Track two axes, "layers to trace" and "state to hold". Collapse wrappers with one caller, shrink mutable scope, and "name the invariant at the boundary" so the reader learns it once. The test is whether a new reader can answer "where does X come from?" and "what can change X?" in under 30 seconds.

### Outcome-oriented execution

Applies during planned rewrites and migrations with explicit phase boundaries. "Prioritize end-state integrity over transitional stability." Intermediate breakage is acceptable when it is "planned, scoped, and reversible". Always run final verification before declaring done.

### Experience first

Applies to product, UX, or feature-scope tradeoffs. "The product is the experience." When implementation convenience conflicts with user delight, choose delight. The user is whoever consumes the work, and "the engineer who maintains the code next is a user too".

### Exhaust the design space

Applies to a novel interaction or architectural decision with no precedent in the codebase. "Build 2-3 competing prototypes or sketches. Compare them side by side. Only then commit." "A second flavor of the first shape does not count." Skip it for mechanical implementation and for changes where constraints dictate a single viable approach.

### Build the lever

Applies to any non-trivial work, not just bulk work. "Build the tool that does it instead of doing it by hand." The tool is the "artifact a reviewer can read and rerun to check the work", and "a deterministic script turns 'trust me' into 'run this'". "Applying this principle produces a file." If you cited it and no codemod, script, generator, or delegate skill is in the diff, you did not apply it.

## Architecture

### Model the domain

Applies when writing stateful logic, or when code branches a lot or repeats a shape assumption across files. "Encode the real domain in a data structure instead of scattering it across conditionals." Reach for a state machine, typed model, registry, discriminated union, or reducer. The tell you skipped it is "a new feature that grows an existing if/else chain by one more branch". Prefer boring code when the current shape is already clear, local, and unlikely to grow.

### Boundary discipline

Applies when wiring validation, error handling, or framework adapters. "Place validation, type narrowing, and error handling at system boundaries. Trust internal code unconditionally." Business logic lives in pure functions and the shell stays thin and mechanical. "Validate data once at the boundary."

### Type system discipline

Applies when designing types or a signature in any typed language. "The type checker is a proof assistant." "Make illegal states unrepresentable", brand semantic primitives, and parse external data at boundaries. "Don't lie to the type system." Exhaustive matching is the compiler's job, and strengthen a type only where partiality appears.

### Make operations idempotent

Applies when designing commands, lifecycle steps, or loops that run amid crashes, restarts, and retries. Operations "converge to the correct state regardless of how many times they run or where they start from". Every state-mutating operation answers "What happens if this runs twice? What happens if the previous run crashed halfway?" If any answer depends on leftover state, add a reconciliation step.

### Migrate callers then delete legacy APIs

Applies when introducing a new internal API while old callers exist. "Migrate callers and remove the old API in the same refactor wave instead of preserving compatibility layers." Treat temporary adapters as "exceptional and time-boxed, not default architecture". Keeping both paths creates dual-path complexity and makes the codebase feel append-only.

### Separate before serializing shared state

Applies when concurrent actors might write the same file, branch, key, or object. First ask whether they truly need the same mutable object, and if not, "eliminate the sharing" by giving each actor its own owned target and merging at the read boundary. Serialize structurally only when one shared writer is a real invariant. "Instructions and conventions are not concurrency control."

## Verification

### Prove it works

Applies after a task, before declaring done. "Verify every task output by checking the real thing directly", never a proxy, a self-report, or "it compiles". For delegated work, "trust artifacts, not self-reports", and inspect the diff or runtime behavior rather than the delegate's summary. The strongest proof is "a deterministic script that re-runs the same comparison, not a one-time eyeball".

### Fix root causes

Applies when debugging. "Trace every problem to its root cause and fix it there." Reproduce first, ask why until you reach it, and resist guards that silence crashes. "When stuck, instrument. Don't guess." For failures after a restart, suspect stale persistent state before code.

### Sequence work into verifiable units

Applies to multi-step work and to how commits and PRs form a sequence. "Order work as a sequence of small units, each ending in a state you can check, and don't advance until the current one is green." "Never batch the edits and verify once at the end." The canonical delivery shape is "the failing test first, then the fix on top", so a reviewer watches it go red, then green. Sequence does not imply dependency. Branch independent PRs from main. Use a native GitHub stack only when one PR depends on another.

## Delegation

### Guard the context window

Applies when context is filling up from large outputs, long files, repeated reads, or fan-out planning. "The context window is finite and non-renewable within a session." "Route verbose outputs, screenshots, and large documents to subagents. The main context gets summaries, not raw data." Don't read what you won't use.

### Never block on the human

Applies when tempted to ask "should I do X?" on reversible work. "Proceed, then present." "Code is cheap, attention is scarce." Reserve confirmation for irreversible actions and for genuine ambiguity where intent cannot be inferred. Product direction comes from the human, and execution does not block. Under df, the router's always-pause list is the closed set of irreversible actions.

## Meta

### Encode lessons in structure

Applies when you catch yourself writing the same instruction a second time, or notice a recurring correction. "Encode recurring fixes in mechanisms (tools, code, metadata, automation) instead of textual instructions." If the fix is structural, use only the structural fix, because "the instruction IS the symptom". Pick the strongest rung the situation allows, then close the loop by applying it now or filing a concrete todo.
