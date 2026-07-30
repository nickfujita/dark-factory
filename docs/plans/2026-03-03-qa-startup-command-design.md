# Design: QA Runbook startup_command Auto-Discovery

**Date:** 2026-03-03
**Status:** Approved

## Problem

When `drk-07-qa-acceptance` and `drk-05-dev-verify` check whether the app is
running and find it unreachable, they immediately ask the user to start the
app manually. This requires the user to know the startup command and intervene
mid-flow — identical to the friction of a junior developer not checking their
own work.

## Solution

When the app is unreachable, skills should attempt to start it automatically
before giving up. The startup command is resolved in priority order: explicit
runbook field, then repo auto-discovery, then ask user.

## Startup Command Resolution (priority order)

1. **`startup_command` in runbook frontmatter** — explicit, always wins
2. **Repo auto-discovery** — scan in order:
   - `package.json` scripts: `dev:all`, `dev`, `start`, `serve`, `preview`
     (first match wins)
   - `Makefile` targets: `dev`, `run`, `serve`, `start` (first match wins)
3. **Ask user** — only if nothing found above

## App-Not-Running Path (updated)

When `agent-browser open` returns an error page or times out:

1. Run `agent-browser close`
2. Resolve startup command using priority order above
3. If resolved: run command in background (`cmd &`), wait 15 seconds, retry
   `agent-browser open`
4. If app is now up: continue normally
5. If still unreachable (or no command found): log failure and ask user
   (include which command was tried, if any)

## Files Changed

| File | Change |
|------|--------|
| `skills/drk-03-qa-runbook-gen/references/runbook-template.md` | Add `startup_command` field (optional, commented) |
| `skills/drk-03-qa-runbook-gen/SKILL.md` | Note to populate `startup_command` from PRD if a dev server command is mentioned |
| `skills/drk-07-qa-acceptance/SKILL.md` | Update app-not-running path with resolution + 15s retry |
| `skills/drk-05-dev-verify/SKILL.md` | Same update |

## Sync

After all skill edits: run `bash scripts/sync-to-global.sh`.
