# Model policy

[`references/model-policy.json`](../../../references/model-policy.json) is the
normative role policy. It declares every harness, responsibility, and lane.
This document explains the contract and does not repeat a default table.

`session` inherits the operator's current session model. `native-model` names
an existing native harness model such as `sonnet` or `opus`. `named-agent`
selects a locally defined agent. `cli` uses the harness CLI without model or
effort flags, and `transport` selects the other harness's approved transport.

The high-consequence Claude `design_runners` target is an ordered `parallel`
group. It runs `opus` and the inherited session target. Parallel groups cannot
be empty or contain another group.

Machine overrides live at
`${XDG_CONFIG_HOME:-$HOME/.config}/dark-factory/config.json`. A tracked
`.agents/dark-factory.json` project override wins over that file. Both files
accept only `schemaVersion` and `roles`, and they can override declared role
targets only. They cannot provide commands, credentials, catalog paths, or run
state.

The Codex implementation role names `luna_max`. When the documented Luna
spawn limitation applies, an operator may explicitly select `terra_xhigh`; the
resolver never silently substitutes another agent. Named-agent definitions are
validated during preflight, immediately before the caller reserves work.

`prepare-run` freezes every lane in the external run's role plan. `resolve`
reads that plan without reopening override files. `preflight` reads the same
plan and validates every named-agent leaf. A1 supplies these commands only;
caller migration belongs to A2.
