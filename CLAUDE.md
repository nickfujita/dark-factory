# dark-factory

This repo contains workflow assets only (skills, plans, automation scripts).
It is intentionally independent from any application repo.

## Source of Truth

- Claude skill content in `skills/`
- Codex-native skill content in `codex-skills/`
- Managed mapping in `manifests/skills.tsv`
- Sync scripts in `scripts/`

## Installation Model

Use copy-based sync scripts, not symlinks.

```bash
bash scripts/sync-to-global.sh
```

Reverse sync when testing edits directly in global directories:

```bash
bash scripts/sync-from-global.sh
```

## Path Defaults

- Claude global skills: `~/.claude/skills/`
- Codex global skills: `~/.codex/skills/` (override with `CODEX_SKILLS_HOME`)

Use `--profile` with files based on `profiles/default.env.example` when paths differ on a VM.

## Git Workflow

Pushing directly to `main` is allowed in this repo. This is a
workflow/planning repo, not application code.

## Constraints

- Keep examples generic; do not copy project/org source files into this repo.
- Keep PRD and QA templates reusable across projects.
