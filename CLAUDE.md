# dark-factory

This repo contains workflow assets only (skills, plans, automation scripts).
It is intentionally independent from any application repo.

## Source of Truth

- Claude skill content in `skills/`
- Codex-native skill content in `codex-plugin/skills/`
- Claude agent definitions in `agents/` (one markdown file per agent, YAML
  frontmatter, filename stem must equal the frontmatter `name`)
- Managed mappings in `manifests/skills.tsv` and `manifests/agents.tsv`
- Sync scripts in `scripts/`
- Plugin manifests in `.claude-plugin/`, `codex-plugin/.codex-plugin/`,
  `.agents/plugins/`, and `hooks/hooks.json`. All four carry the version and
  `just check-plugins` holds them in agreement.

## Installation Model

The repo ships as a plugin to both harnesses and is also its own marketplace.
The Claude plugin is rooted at the repo root; the Codex plugin is rooted at
`codex-plugin/`, because Codex resolves a plugin's skills at
`<plugin-root>/skills` and the repo root already holds the Claude tree.

Plugin install is the path for using the skills:

```bash
claude plugin marketplace add nickfujita/dark-factory
claude plugin install dark-factory@dark-factory

codex plugin marketplace add nickfujita/dark-factory
codex plugin add dark-factory@dark-factory
```

Sync mode is the path for hacking on the skills. It uses copy-based scripts,
not symlinks.

```bash
bash scripts/sync-to-global.sh
```

Reverse sync when testing edits directly in global directories:

```bash
bash scripts/sync-from-global.sh
```

Skill prose must resolve under both modes. Refer to a sibling skill's files
relatively (`../df/references/model-policy.md`), name root-relative paths the
way the session hook reports them (`scripts/df-state.sh`), and keep
`${CLAUDE_PLUGIN_ROOT}` to hook and command definitions.

## Path Defaults

- Claude global skills: `~/.claude/skills/`
- Codex global skills: `~/.codex/skills/` (override with `CODEX_SKILLS_HOME`)
- Claude global agents: `~/.claude/agents/`

Use `--profile` with files based on `profiles/default.env.example` when paths differ on a VM.

## Git Workflow

Pushing directly to `main` is allowed in this repo. This is a
workflow/planning repo, not application code.

## Constraints

- Keep examples generic; do not copy project/org source files into this repo.
- Keep PRD and QA templates reusable across projects.
