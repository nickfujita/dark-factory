#!/bin/sh
# Claude Code SessionStart hook. Prints the df reminder to stdout.
# No side effects, no dependencies beyond POSIX sh, always exits 0.
cat <<'EOF'
df mode exists for routed development work. Entry is the operator typing /df and nothing else.
For a playbook-shaped task you may suggest /df in one line. You never enter it on your own.
One owner per function. Do not redo work a df skill owns.
Once in the mode, read the routing table in skills/df/SKILL.md.
EOF
exit 0
