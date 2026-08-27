# df session hook install

`scripts/df-session-hook.sh` prints the df reminder at session start. It does not activate the mode. Entry stays the operator typing `/df`, per D22. The hook only keeps the reminder and the one-owner rule in context across sessions and compaction.

The script also names the dark-factory root it was run from. df skills refer to helper scripts and repo-level docs by root-relative paths such as `scripts/df-state.sh` and `references/run-state-schema.md`. That root is the plugin root in a plugin install and the checkout in a sync install, so the script derives it from its own location and states it rather than hardcoding either.

## Plugin install

Nothing to do. `hooks/hooks.json` ships with the plugin and registers the hook on install, with `${CLAUDE_PLUGIN_ROOT}` resolving the script path. Install the plugin and new sessions pick it up.

## Sync install

Sync mode copies skills into the global directories and leaves settings alone, so the hook is wired by hand. Add this to `~/.claude/settings.json` (user settings). Replace `<path>` with the absolute path to this repo. Merge into an existing `hooks` key if one is already there.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "sh <path>/scripts/df-session-hook.sh"
          }
        ]
      }
    ]
  }
}
```

New sessions pick it up on launch. Verify by starting a fresh session and checking that the reminder lines appear.

Do not wire the manual hook on a machine that has the plugin installed. Both would fire and the reminder would print twice.

## Codex

Codex has no SessionStart hook. The equivalent reminder line lands in dark-factory's Codex instructions when that tree ports.

## Uninstall

Plugin install: uninstall or disable the plugin. Sync install: remove the `SessionStart` entry from `~/.claude/settings.json`. The script has no other wiring and needs no cleanup.
