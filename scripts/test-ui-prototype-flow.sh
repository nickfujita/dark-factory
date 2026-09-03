#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

fail=0

require_text() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "FAIL: $file is missing: $text" >&2
    fail=1
  fi
}

require_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  local third="$4"
  local first_line second_line third_line

  first_line="$(grep -nFm1 -- "$first" "$file" | cut -d: -f1 || true)"
  second_line="$(grep -nFm1 -- "$second" "$file" | cut -d: -f1 || true)"
  third_line="$(grep -nFm1 -- "$third" "$file" | cut -d: -f1 || true)"

  if [[ -z "$first_line" || -z "$second_line" || -z "$third_line" ]]; then
    echo "FAIL: $file does not contain all ordered stages" >&2
    fail=1
    return
  fi

  if ! (( first_line < second_line && second_line < third_line )); then
    echo "FAIL: $file must route design -> visual UI checkpoint -> plan" >&2
    fail=1
  fi
}

for skill_root in skills codex-plugin/skills; do
  router="$skill_root/df/SKILL.md"
  feature="$skill_root/df/playbooks/feature.md"
  prototype="$skill_root/df/playbooks/prototype.md"
  design="$skill_root/df-design/SKILL.md"
  plan="$skill_root/df-plan/SKILL.md"
  coverage="$skill_root/df-verify-coverage/SKILL.md"
  verify="$skill_root/df-dev-verify/SKILL.md"

  require_text "$router" 'A Quick-lane change that chooses a new visual design still runs `playbooks/prototype.md`'
  require_text "$router" '| A throwaway visual or behavioral experiment that settles a design choice before production work. | `playbooks/prototype.md` | Ported |'

  require_order "$feature" '**Design.**' '**Visual UI checkpoint.**' '**Plan.**'
  require_text "$feature" 'The operator approves the driven mock before df-plan starts.'

  require_text "$design" '## Phase C: Mock user-facing UI'
  require_text "$design" 'run `../df/playbooks/prototype.md` after the technical sketch and before df-plan'
  require_text "$design" 'Do not start df-plan until that record exists.'

  require_text "$prototype" '<run-dir>/work/prototype/approved-ui-prototype.md'
  require_text "$prototype" 'stop for explicit operator approval before df-plan'

  require_text "$plan" 'For a user-facing graphical UI change, `<run-dir>/work/prototype/approved-ui-prototype.md`'
  require_text "$plan" 'the approved prototype record is missing, return to df-design'

  require_text "$coverage" 'Every material state and interaction in that record that implements a PRD requirement must appear in the matching feature-map recipe.'
  require_text "$verify" 'Compare an approved visual prototype.'
  require_text "$verify" 'An unexplained difference is a QA failure.'
done

if [[ $fail -ne 0 ]]; then
  exit 1
fi

echo "UI prototype flow OK"
