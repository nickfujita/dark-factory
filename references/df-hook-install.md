# df session hook install

`scripts/df-session-hook.sh` prints the df reminder at session start. It does not activate the mode. Entry stays the operator typing `/df`, per D22. The hook only keeps the reminder and the one-owner rule in context across sessions and compaction.

## Install

Add this to `~/.claude/settings.json` (user settings). Replace `<path>` with the absolute path to this repo. Merge into an existing `hooks` key if one is already there.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash <path>/scripts/df-session-hook.sh"
          }
        ]
      }
    ]
  }
}
```

New sessions pick it up on launch. Verify by starting a fresh session and checking that the reminder lines appear.

## Codex

Codex has no SessionStart hook. The equivalent reminder line lands in dark-factory's Codex instructions when that tree ports.

## Uninstall

Remove the `SessionStart` entry from `~/.claude/settings.json`. The script has no other wiring and needs no cleanup.
