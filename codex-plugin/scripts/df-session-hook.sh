#!/bin/sh
# Codex session_start hook. Prints the df reminder to stdout.
# No side effects, no dependencies beyond POSIX sh, always exits 0.
#
# Codex variant of scripts/df-session-hook.sh at the repo root: the entry
# syntax here is `$df`, and the root this script names is the Codex plugin
# root (codex-plugin/ in a checkout, the codex plugin cache dir installed).
# Deliberately NOT byte-identical to the root script; the manifest check
# validates it separately.
DF_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd) || DF_ROOT=""

cat <<'EOF'
df mode exists for routed development work. Entry is the operator invoking $df and nothing else.
For a playbook-shaped task you may suggest $df in one line. You never enter it on your own.
One owner per function. Do not redo work a df skill owns.
Once in the mode, read the routing table in the df skill's SKILL.md.
EOF

if [ -n "$DF_ROOT" ]; then
  printf 'The dark-factory root here is %s. Resolve a df skill'\''s root-relative paths, such as scripts/df-state.sh or references/run-state-schema.md, against it. A path like references/principles.md inside a skill'\''s own text is relative to that skill'\''s directory.\n' "$DF_ROOT"
fi

exit 0
