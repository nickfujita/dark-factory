---
name: how
description: "Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which package owns this\", \"is this the right layer\"). Explains subsystem architecture, runtime flow, onboarding mental models. Can critique architecture. Use why for motivation."
---

# How

Explore the codebase to answer "how does X work?" questions. Produce clear architectural explanations at the level of a senior engineer onboarding onto a subsystem. Enough to build a working mental model, not annotated source code.

Two modes:

1. **Explain** (default). Explore the codebase and produce a clear explanation.
2. **Critique.** Explain first, then gather independent architectural critiques, one per model family.

This is a read-only skill. It never writes, commits, or modifies state, and every agent it spawns gets a read-only instruction.

## Explain mode

### Step 1. Understand the question and assess complexity

Parse what the user is asking about:

- "How does the rate limiter work?", a subsystem
- "How do we handle billing for on-demand usage?", a feature flow
- "How is the auth service structured?", an architectural overview
- "Walk me through what happens when a user submits a form", a runtime trace

Identify the scope. If ambiguous, state your best-guess interpretation before exploring. Don't ask. Let the user redirect if you're off.

**Assess complexity to decide the approach:**

- **Simple** (a single module, a small utility, a narrow question like "how does function X work"): no explorer agents. Explore and explain yourself in a single pass. Go to Step 2b.
- **Complex** (a subsystem spanning multiple files/services, a cross-cutting feature, a full architectural overview): spawn parallel explorer agents first, then synthesize. Go to Step 2a.

When in doubt, lean simple. You can always spawn explorers if you hit a wall.

### Step 2a. Explore (complex questions only)

Decompose the question into 2 to 4 parallel exploration angles, each a distinct slice of the subsystem so explorers don't duplicate work. Example split for "how does the rate limiter work?":

- Explorer 1: data model and state management
- Explorer 2: request path and enforcement
- Explorer 3: configuration and metrics infrastructure

The right decomposition depends on the question. Use your judgment. Narrow questions need 2 explorers. Broad subsystems earn up to 4, and 4 is the cap.

Spawn all explorers as native Codex subagents in a single wave. For each:

- run in the background
- a read-only instruction in the prompt: explore and report, never write or modify anything
- the menial investigation role resolved through the df model policy (`../df/references/model-policy.md`), never a hardcoded model slug

Each explorer gets the same base prompt from `references/explorer-prompt.md` plus a specific exploration angle naming its slice. Each explorer should:

- Start broad: glob for relevant directories, grep for key types/interfaces/class names
- Follow the thread: from an entry point, trace the call chain (callers, callees, data flow, type definitions)
- Read the actual code, don't guess from file names
- Stop when it can describe the full path from input to output (or trigger to effect) without hand-waving any step
- Note things that are surprising, non-obvious, or that a newcomer would get wrong

Each explorer returns structured findings: components found, flow traced, files read, anything non-obvious. Overlap between explorers is fine; the synthesis step reconciles.

Then proceed to Step 3.

### Step 2b. Direct explain (simple questions)

Explore and explain in-session. Search and read the code yourself and write the explanation directly. A simple question does not earn a spawn; the session does small tasks itself. Read `references/explainer-prompt.md` for the communication style and output format. Same structure, just no explorer findings as input.

Proceed to Step 4.

### Step 3. Synthesize (complex questions only)

Once all explorers return, spawn a single explainer as a native Codex subagent to synthesize their findings into one coherent explanation:

- run in the background
- a read-only instruction
- the investigation-synthesizer role from the df model policy

The explainer gets all explorers' findings and writes the human-facing explanation (output format below). Read `references/explainer-prompt.md` for the full prompt template. The explainer reconciles overlapping findings, resolves contradictions, and weaves the slices into a unified picture.

### Step 4. Present

Present the explainer's output to the user. You may lightly edit for clarity or add context from the conversation, but don't substantially rewrite. The explainer's communication is the product.

### Output format

Follow this structure, adapted to the question. Not every section is needed for every question.

**Overview.** 1-2 paragraphs. What it is, what it does, why it exists. Enough to decide whether to keep reading.

**Key concepts.** The important types, services, or abstractions. Brief definition of each. Not exhaustive, just the ones needed to understand the rest.

**How it works.** The core of the explanation. Walk through the flow: what triggers it, what happens step by step, where data goes, the decision points. Prose, not pseudocode. Reference specific files and functions so the reader can go look, but don't dump code blocks unless a snippet is genuinely necessary.

**Where things live.** A brief map of the relevant files/directories. Not every file, just the ones needed to start working in this area.

**Gotchas.** Non-obvious or surprising things that would trip someone up. Historical context that explains why something looks weird. Known sharp edges.

## Critique mode

Triggered when the user asks for architectural issues, problems, or improvements, not just understanding.

### Step 1. Explain first

Run the full explain flow above (Steps 1 to 4). You must understand the architecture before critiquing it.

### Step 2. Gather critiques, one per model family

The panel is two-family, one Codex critic plus one Claude critic. That is the panel ceiling from the df model policy, not a downgrade to work around; a same-family rerun is a correlated draw, not a second opinion.

**Codex critic.** Runs on the judgment-delegate role from the df model policy. That role defaults to inherit, so either run the critique in-session after the explanation is presented, or spawn one native Codex subagent (background, read-only instruction, model field omitted). Build the prompt from `references/critic-prompt.md`. The critic gets:

1. The explanation from Step 1, so it doesn't re-explore
2. The relevant file paths, so it can read the actual code
3. The architectural critique rubric from `references/critique-rubric.md`

**Claude critic.** The second family arrives through the cross-model transport named in the df model policy, carrying the same explanation, file paths, and rubric. When the transport is unavailable or its usage window is exhausted, record the leg as deferred and say so in the verdict rather than substituting another Codex run.

### Step 3. Lead judgment

Same framework as the review skills. You're a pragmatic lead, not an aggregator.

Categorize findings:

- **Act on.** Architectural problems worth fixing now
- **Consider.** Real concerns, but the cost/benefit is unclear
- **Noted.** Valid observations, low priority
- **Dismissed.** Wrong, missing context, or style preference

Present the explanation first (from Step 1), then the critique verdict below it, naming which family produced each act-on finding and any leg that was deferred. The explanation should stand on its own; someone who just wants to understand the system shouldn't wade through critique.
