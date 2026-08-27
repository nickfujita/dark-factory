# Investigation

**You own the answer. Plan, route, write.**

For read-only requests. "How does X work", "why was Y built this way", "are we sure about Z", "should we do X or Y". They produce a cited explanation or a recommendation, not a code change.

1. Route through the **how** skill. Explain mode for narrow questions, Critique mode for "are we sure". For motivation questions, also route through the **why** skill. Fan them out as parallel subagents, read-only by instruction, on the cheap investigation tier from `references/model-policy.md`. Synthesis stays with you.
2. The run state entry stays one line, `finish predicate: question answered with citations, read-only`. The lane gates for PRD, runbook, and review are for code-shaped work and do not apply here.
3. Produce the `how`-shaped output (Overview, Key Concepts, How It Works, Where Things Live, Gotchas), or a recommendation with a tradeoffs table when the request is a decision between alternatives.
4. Write the reply clean per the router's reply rules. The unslop skill owns the full rule set.

No PR and no review machinery. No design exploration unless the investigation precedes a code change. When it does, hand back to the operator and re-route through `/df` to bug fix or feature. The feature playbook is pending port. Until it lands, say so and apply the lane's discipline inline.

**Reply.** The investigation output. For "are we sure" answers, include your real judgment with reasons. Push back when the premise is wrong, per the router's Autonomy section.
