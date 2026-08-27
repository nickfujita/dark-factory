# Source playbooks

The why skill spawns one investigator per available evidence category, each reading a single source-specific playbook below. The playbooks are concrete examples for the tools in use here; adapt them for a different MCP in the same category.

| Category | Playbook | Example MCP it documents |
|---|---|---|
| Source control history | [`code-archaeology.md`](./sources/code-archaeology.md) | git, `gh` |
| Long-form documents | [`notion.md`](./sources/notion.md) | Notion (adapt for Confluence, Google Docs) |

Dropped from the port until we use those tools: the Linear, Databricks, Datadog, Sentry, and Slack playbooks. Their categories (issue tracker, product analytics warehouse, infrastructure observability, error tracking, real-time chat) stay in the roster and the coverage map. When a matching MCP appears in a session, adapt the closest ported playbook plus the investigator prompt's instructions, and note the adaptation in the coverage map. The originals live in the vendored PSTACK snapshot if a full playbook is ever worth restoring.

Cross-cutting:

- [`incident-postmortem.md`](./sources/incident-postmortem.md). Add this if the target code looks defensive (null checks, retry, timeout, rate limit, feature flag, egress guard, OOM handler).
