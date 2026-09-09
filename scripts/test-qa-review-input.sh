#!/usr/bin/env bash
# Exercise both QA review adapters with a fake reviewer. No model or network.
# Proves snapshot delivery and fail-closed output handling, not review quality.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/qa-review-input.XXXXXX")
trap 'rm -r -- "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/project" "$scratch/state"
cat >"$scratch/project/prd.md" <<'DOC'
# Requirements
Status: Approved
REQ-001: Editor can export.
NEG-001: Viewer cannot export.
DOC
cat >"$scratch/state/qa-review-input.md" <<'DOC'
# Verification review input
Media: dashboard
Entry: .agents/skills/verify-sample-dashboard/features/export.md#editor
REQ-001: Status: planned; live verification pending
EDITOR-ASSERTION: CSV header is date,amount.
Entry: .agents/skills/verify-sample-dashboard/features/export.md#viewer
NEG-001: Status: planned; live verification pending
VIEWER-ASSERTION: No download for the viewer.
DOC
cat >"$scratch/bin/unshare" <<'STUB'
#!/usr/bin/env bash
[[ "${QA_NET:-0}" == 1 ]]
STUB
cat >"$scratch/bin/codex" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
tree=''
prompt=''
sandbox=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) tree=$2; shift 2 ;;
    --sandbox) sandbox=$2; shift 2 ;;
    *) prompt=$1; shift ;;
  esac
done
[[ "$tree" != "$QA_SOURCE" ]]
if [[ "$QA_NET" == 1 ]]; then
  [[ "$sandbox" == read-only ]]
else
  [[ "$sandbox" == danger-full-access ]]
fi
[[ -f "$tree/prd.md" && -f "$tree/qa-review-input.md" ]]
grep -Fq 'EDITOR-ASSERTION:' "$tree/qa-review-input.md"
grep -Fq 'VIEWER-ASSERTION:' "$tree/qa-review-input.md"
[[ "$prompt" == *'qa-review-input.md'* ]]
printf '%s\n' "$tree" >>"$QA_DELIVERIES"
[[ "${QA_MODE:-valid}" != empty ]] || exit 0
if [[ "$prompt" == *'## Findings — Codex CLI'* ]]; then
  printf '## Findings — Codex CLI\n\nNO FINDINGS\n'
else
  printf '## Findings — Codex\n\nNO FINDINGS\n'
fi
STUB
chmod +x "$scratch/bin/codex" "$scratch/bin/unshare"
export PATH="$scratch/bin:$PATH"
export QA_SOURCE="$scratch/project" QA_DELIVERIES="$scratch/state/deliveries"
cd "$scratch/project"
git init -q
git add prd.md
git -c user.name='Fixture Author' -c user.email='author@example.invalid' commit -qm 'Requirements'
for tree in skills codex-plugin/skills; do
 for network_support in 0 1; do
  export QA_NET=$network_support
  runner="$root/$tree/df-qa-validation/scripts/run_codex_qa_validation.sh"
  label=${tree//\//-}
  QA_MODE=valid bash "$runner" prd.md "$scratch/state/qa-review-input.md" "$scratch/state/$label.md"
  grep -Fq 'NO FINDINGS' "$scratch/state/$label.md"
  if QA_MODE=empty bash "$runner" prd.md "$scratch/state/qa-review-input.md" "$scratch/state/$label-empty.md" 2>"$scratch/state/empty.err"; then
    echo 'FAIL: empty reviewer output was accepted' >&2
    exit 1
  fi
  if bash "$runner" prd.md "$scratch/state/missing.md" "$scratch/state/$label-missing.md" 2>"$scratch/state/missing.err"; then
    echo 'FAIL: missing review input was accepted' >&2
    exit 1
  fi
  echo "PASS: $tree preserves both planned entries and rejects missing input/empty output"
 done
done
[[ $(wc -l <"$QA_DELIVERIES") -eq 8 ]]
while IFS= read -r snapshot; do
  [[ ! -e "$snapshot" ]]
done <"$QA_DELIVERIES"
git diff --exit-code
[[ -f "$scratch/state/qa-review-input.md" ]]
echo 'PASS: disposable snapshots cleaned, source and external input retained'
