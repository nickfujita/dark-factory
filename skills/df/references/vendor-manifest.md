# Vendor manifest

Provenance record for PSTACK material vendored into the df skills, per D30. Minimal v1. It gains a row for every ported file.

## Source

| Field | Value |
|---|---|
| Repo | https://github.com/cursor/plugins, the `pstack/` plugin directory |
| Pinned commit | `bdf7aa355337897f167153e05069aca505dae17c` |
| License | MIT, copyright (c) 2026 Lauren Tan |

The drafting checkout was at HEAD `799151d91b6e12ee7dbd09f708eec108d7de9b3b`. Every base file in the table below was verified identical between that HEAD and the pinned commit on 2026-08-27.

## File mapping

| Our file | Base pstack file(s) | Local modifications |
|---|---|---|
| `skills/df/SKILL.md` | `pstack/skills/poteto-mode/SKILL.md` | Renamed to df. Explicit `/df` entry only. The three lanes added from the v2 decision plan, with the second-opinion pass and budget stops. Cursor Task became the Agent tool, `/loop` became Monitor, model slugs became roles resolved through `references/model-policy.md` with the inherit default and the throttle rule, readonly became sandbox plus instruction with the disposable-snapshot rule for reviewers. cursor-team-kit dependencies (deslop, control-ui, control-cli, create-skill) dropped, along with the Cursor-only trigger and playbook entries. The trigger table trimmed to the five router playbooks with pending-port markers. unslop core reply rules kept embedded. The project hook (`.dark-factory/project.yaml`) added. The always-pause list aligned with the operator's git workflow, which never merges and never force-pushes. |
| `skills/df/playbooks/bug-fix.md` | `pstack/skills/poteto-mode/playbooks/bug-fix.md` | Superpowers graft added as the stop rule. Three failed fix attempts means stop and question the architecture with the human. The control skill became the project verification skill named in the manifest. `/loop` became a Monitor until-loop. The bug-fix model slug became the implementation-delegate role from model-policy. The failing-repro-before-fix rule marked as holding in every lane, with the Quick-lane TDD escape hatch excluded for reproduced defects. Opening-a-PR invocation kept, with an interim plain-git-plus-gh contract while that playbook is pending port. how, why, and architect references marked pending with inline fallbacks. |
| `skills/df/references/principles.md` | the 21 `pstack/skills/principle-*/SKILL.md` files | Condensed to one reference document. One section per principle with its when-clause and its core rule in a few sentences, load-bearing phrases quoted verbatim. PSTACK's grouping kept (Core, Architecture, Verification, Delegation, Meta). No separate skill triggers, per the one-owner rule. |
| `skills/df/references/vendor-manifest.md` | none | This file. New, no base text. |
| `skills/df/references/model-policy.md` | none | New, no base text. Per-role model tables and the two routing rules, derived from the v2 decision plan §6 draft. |
| `scripts/df-session-hook.sh` | none | New, no base text. SessionStart reminder script, derived from the v2 decision plan §1 and D22. |
| `references/df-hook-install.md` | none | New, no base text. Install and uninstall doc for the SessionStart hook. |
| `scripts/test-df-invocation.sh` | none | New, no base text. D23 acceptance harness, derived from the v2 decision plan D23 row. Runs three clean headless sessions against a throwaway project-level install of the df skill and proves ordinary prompts cannot activate it while explicit `/df` invocation can. |
