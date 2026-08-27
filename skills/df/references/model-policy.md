# Model policy

The per-role model table the df router resolves against. Two rules govern every lookup.

Inherit is the default. The session model is the operator's usage throttle. A role marked `inherit` omits the spawn's model field and runs on the session model, deliberate downgrades included.

A pinned role never runs above the current session model unless it is a designated floor. Floors are the only pins allowed to exceed a throttled session, because their job is to keep a review meaningful. `df-reviewer-recheck` is the only floor today, marked `# floor` below.

A value is `inherit`, a model name, or an agent-definition name. The Claude Agent tool cannot set effort per spawn, so a role that needs a pinned effort resolves to an agent definition.

```yaml
claude:
  session_router: inherit
  menial_scoped_investigation: sonnet
  implementation_delegate: opus
  judgment_delegate: inherit
  investigation_synthesizer: opus
  design_runners: [opus, inherit]  # standard lane runs one, high-consequence two
  discovery_reviewers: inherit
  recheck_leaf_reviewers: df-reviewer-recheck  # agent definition; floor
  eval_graders: sonnet
  cross_model_review: codex-cli  # the other family; resolves per the codex section

codex:
  orchestrator: inherit
  implementation_delegate: luna_max  # terra_xhigh while the Luna spawn bug stands
  discovery_context: terra_xhigh
  escalation: sol_high  # trigger is a change to a trust boundary or invariant, never reading near one
  persona_reviewers_cli: operator-default-no-effort-flag
  cross_model_review: claude-tmux
```
