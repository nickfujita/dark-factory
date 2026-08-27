#!/usr/bin/env bash
# Plugin packaging check.
#
# The repo ships two plugins from one tree: a Claude plugin rooted at the repo
# root and a Codex plugin rooted at codex-plugin/. Four manifests carry the
# version, and auto-update reads the manifest, not the git tag, so a version
# that drifts between them ships a plugin that never updates. This check holds
# them together and guards the one file the two roots have to share.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

fail=0
note() { echo "FAIL: $*" >&2; fail=1; }

read_json() {
  # read_json <file> <python-expression-on-`d`>
  python3 -c "
import json,sys
with open(sys.argv[1]) as fh:
    d = json.load(fh)
print($2)
" "$1"
}

claude_plugin=".claude-plugin/plugin.json"
claude_market=".claude-plugin/marketplace.json"
codex_plugin="codex-plugin/.codex-plugin/plugin.json"
codex_market=".agents/plugins/marketplace.json"
hooks="hooks/hooks.json"

for f in "$claude_plugin" "$claude_market" "$codex_plugin" "$codex_market" "$hooks"; do
  [[ -f "$f" ]] || { note "missing manifest $f"; continue; }
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" \
    || note "$f is not valid JSON"
done
[[ $fail -eq 0 ]] || exit 1

v_claude_plugin="$(read_json "$claude_plugin" "d['version']")"
v_claude_market="$(read_json "$claude_market" "d['plugins'][0]['version']")"
v_codex_plugin="$(read_json "$codex_plugin" "d['version']")"
v_codex_market="$(read_json "$codex_market" "d['plugins'][0]['version']")"

echo "Plugin version: $v_claude_plugin"
for pair in \
  "$claude_market:$v_claude_market" \
  "$codex_plugin:$v_codex_plugin" \
  "$codex_market:$v_codex_market"; do
  where="${pair%%:*}"; got="${pair##*:}"
  [[ "$got" == "$v_claude_plugin" ]] \
    || note "version drift: $where has '$got', $claude_plugin has '$v_claude_plugin'"
done

# Both plugin roots need the run-state accessor, and the two roots do not nest,
# so the Codex root carries a copy. Byte-identical or it is drift.
if ! cmp -s scripts/df-state.sh codex-plugin/scripts/df-state.sh; then
  note "codex-plugin/scripts/df-state.sh differs from scripts/df-state.sh"
fi

# The plugin name has to match across the Claude manifests, or `claude plugin
# install` resolves nothing.
n_plugin="$(read_json "$claude_plugin" "d['name']")"
n_market="$(read_json "$claude_market" "d['plugins'][0]['name']")"
[[ "$n_plugin" == "$n_market" ]] \
  || note "plugin name mismatch: $claude_plugin '$n_plugin' vs $claude_market '$n_market'"

# Every command the hook manifest names must exist under the plugin root.
while read -r cmd; do
  [[ -n "$cmd" ]] || continue
  rel="${cmd#*\$\{CLAUDE_PLUGIN_ROOT\}/}"
  [[ -f "$rel" ]] || note "hooks/hooks.json names a missing file: $rel"
done < <(read_json "$hooks" "'\n'.join(h['command'] for group in d['hooks'].values() for entry in group for h in entry['hooks'])")

# The Codex plugin declares its skills dir; it has to be there and be populated.
[[ -d codex-plugin/skills ]] || note "codex-plugin/skills is missing"
[[ -f codex-plugin/skills/df/SKILL.md ]] || note "codex-plugin/skills/df/SKILL.md is missing"

[[ $fail -eq 0 ]] && echo "Plugin manifests OK" || exit 1
