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
for s in df-state.sh df-check-leakage.sh; do
  if ! cmp -s "scripts/$s" "codex-plugin/scripts/$s"; then
    note "codex-plugin/scripts/$s differs from scripts/$s"
  fi
  [[ -x "scripts/$s" && -x "codex-plugin/scripts/$s" ]] \
    || note "$s is not executable in both plugin roots"
done

# The resumable Codex worker is a Claude-to-Codex adapter. It ships from the
# Claude plugin root and must never become a nested Codex execution mode.
[[ -x scripts/df-codex-exec.sh ]] \
  || note "Claude-only scripts/df-codex-exec.sh is missing or not executable"
[[ -f skills/df/references/codex-background-workers.md ]] \
  || note "Claude-only Codex worker reference is missing"
[[ ! -e codex-plugin/scripts/df-codex-exec.sh ]] \
  || note "Claude-only df-codex-exec.sh leaked into the Codex plugin"
[[ ! -e codex-plugin/skills/df/references/codex-background-workers.md ]] \
  || note "Claude-only Codex worker reference leaked into the Codex plugin"
if grep -R -Fq 'scripts/df-codex-exec.sh' codex-plugin/skills 2>/dev/null; then
  note "the Codex-native skill tree references the Claude-only Codex worker transport"
fi

# Root-relative reference docs the skills name must ship in BOTH roots.
# Byte-identical copies; the repo root is canonical.
for ref in run-state-schema.md engineering-standards.md; do
  [[ -f "codex-plugin/references/$ref" ]] \
    || { note "codex-plugin/references/$ref is missing"; continue; }
  cmp -s "references/$ref" "codex-plugin/references/$ref" \
    || note "codex-plugin/references/$ref differs from references/$ref"
done

# The session hook ships in both roots too, but as a HARNESS VARIANT, not a
# copy: the Codex script says \$df where the Claude script says /df. Identity
# is checked structurally instead: both must exist, parse, and name a root.
codex_hooks="codex-plugin/hooks/hooks.json"
if [[ -f "$codex_hooks" ]]; then
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$codex_hooks" \
    || note "$codex_hooks is not valid JSON"
  while read -r cmd; do
    [[ -n "$cmd" ]] || continue
    rel="codex-plugin/${cmd#*\$\{CLAUDE_PLUGIN_ROOT\}/}"
    [[ -f "$rel" ]] || note "$codex_hooks names a missing file: $rel"
  done < <(read_json "$codex_hooks" "'\n'.join(h['command'] for group in d['hooks'].values() for entry in group for h in entry['hooks'])")
else
  note "$codex_hooks is missing"
fi
# Capture instead of piping into grep -q: under pipefail an early grep exit
# SIGPIPEs the hook script and fails the pipeline even on a match.
for hs in scripts/df-session-hook.sh codex-plugin/scripts/df-session-hook.sh; do
  bash -n "$hs" 2>/dev/null || note "$hs fails a syntax check"
  out="$(sh "$hs")"
  [[ "$out" == *"dark-factory root here is"* ]] || note "$hs does not name its root"
done
codex_out="$(sh codex-plugin/scripts/df-session-hook.sh)"
[[ "$codex_out" == *'$df'* ]] \
  || note "the codex session hook does not use the \$df entry syntax"
if [[ "$codex_out" =~ /df($|[^-a-z0-9]) ]]; then
  note "the codex session hook leaks the Claude /df entry syntax"
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
