#!/bin/sh
# Claude Code SessionStart hook. Prints the df reminder to stdout.
# No side effects, no dependencies beyond POSIX sh, always exits 0.
#
# The script also resolves its own root and names it. df skills refer to helper
# scripts and repo-level docs by root-relative paths like `scripts/df-state.sh`
# and `references/run-state-schema.md`. That root is the plugin root in a plugin
# install and the checkout in a sync install, so the script derives it from its
# own location instead of hardcoding either.
DF_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd) || DF_ROOT=""

cat <<'EOF'
df mode exists for routed development work. Entry is the operator typing /df and nothing else.
For a playbook-shaped task you may suggest /df in one line. You never enter it on your own.
One owner per function. Do not redo work a df skill owns.
Once in the mode, read the routing table in the df skill's SKILL.md.
EOF

if [ -n "$DF_ROOT" ]; then
  printf 'The dark-factory root here is %s. Resolve a df skill'\''s root-relative paths, such as scripts/df-state.sh or references/run-state-schema.md, against it.\n' "$DF_ROOT"
fi

exit 0
