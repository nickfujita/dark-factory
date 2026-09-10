#!/usr/bin/env bash
# Exercises code-review selection consumers with fake reviewer processes. The
# selection reader is real and runs against a synthetic consumer repository.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/df-code-review-selection.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
repo="$scratch/consumer"
state="$scratch/state"
bin="$scratch/bin"
reports="$scratch/reports"
mkdir -p "$repo/docs" "$repo/skills" "$repo/recipes" "$state" "$bin" "$reports"
export DF_STATE_ROOT="$state"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }
expect_failure() {
  local description=$1 before=$2
  shift 2
  if "$@" >"$scratch/failure.out" 2>"$scratch/failure.err"; then
    fail "$description unexpectedly succeeded"
  fi
  [[ $(wc -l <"$workers") -eq "$before" ]] || fail "$description started a fake reviewer"
  pass "$description"
}

printf '# Synthetic PRD\nREQ-001: dashboard create.\nNEG-001: dashboard remove remains scoped.\nREQ-002: CLI list.\n' >"$repo/docs/prd.md"
printf 'dashboard verification skill\n' >"$repo/skills/dashboard.md"
printf 'cli verification skill\n' >"$repo/skills/cli.md"
printf '# Shared dashboard recipe\n## Create\nAssert creation.\n## Remove\nAssert scoped removal.\n' >"$repo/recipes/shared.md"
printf '# CLI recipe\n## List\nAssert listing.\n' >"$repo/recipes/cli.md"
printf 'before\n' >"$repo/app.txt"
printf '# Different document\n' >"$repo/docs/not-prd.md"
git -C "$repo" init -q
git -C "$repo" add .
git -C "$repo" -c user.name='Fixture Author' -c user.email='fixture@example.invalid' commit -qm base
printf 'after\n' >"$repo/app.txt"
git -C "$repo" add app.txt
git -C "$repo" -c user.name='Fixture Author' -c user.email='fixture@example.invalid' commit -qm feature
base_ref=$(git -C "$repo" rev-parse HEAD~1)

node - "$repo" "$scratch/selection.json" "$scratch/no-route.json" <<'NODE'
const { createHash } = require("node:crypto");
const { readFileSync, writeFileSync } = require("node:fs");
const [repo, selectionPath, noRoutePath] = process.argv.slice(2);
const hash = (path) => createHash("sha256").update(readFileSync(`${repo}/${path}`)).digest("hex");
const entry = (id, medium, skillPath, recipePath, subFeature, requirements, negatives) => ({
  id,
  medium,
  skillPath,
  skillSha256: hash(skillPath),
  recipePath,
  subFeature,
  recipeSha256: hash(recipePath),
  requirementIds: requirements,
  negativeRequirementIds: negatives,
});
writeFileSync(selectionPath, JSON.stringify({
  schemaVersion: 1,
  kind: "user-facing",
  runId: "review-selection",
  featureSlug: "synthetic-review",
  prdPath: "docs/prd.md",
  prdSha256: hash("docs/prd.md"),
  catalogLink: null,
  declaredMedia: ["dashboard", "cli-agent"],
  entries: [
    entry("dashboard-create", "dashboard", "skills/dashboard.md", "recipes/shared.md", "create", ["REQ-001"], []),
    entry("dashboard-remove", "dashboard", "skills/dashboard.md", "recipes/shared.md", "remove", [], ["NEG-001"]),
    entry("cli-list", "cli-agent", "skills/cli.md", "recipes/cli.md", null, ["REQ-002"], []),
  ],
}, null, 2));
writeFileSync(noRoutePath, JSON.stringify({
  schemaVersion: 1,
  kind: "no-user-route",
  runId: "review-selection",
  featureSlug: "synthetic-no-route",
  prdPath: "docs/prd.md",
  prdSha256: hash("docs/prd.md"),
  reason: "This synthetic change has no user-facing route.",
  entries: [],
}, null, 2));
NODE

(cd "$repo" && bash "$root/scripts/df-state.sh" init review-selection standard 20 120 "synthetic code review") >/dev/null
selection_ref=$(node "$root/scripts/df-selection.mjs" seal --run review-selection --draft "$scratch/selection.json" --repo-root "$repo" | awk -F= '/^SELECTION_REF=/{print $2}')
no_route_ref=$(node "$root/scripts/df-selection.mjs" seal --run review-selection --draft "$scratch/no-route.json" --repo-root "$repo" | awk -F= '/^SELECTION_REF=/{print $2}')
[[ -n "$selection_ref" && -n "$no_route_ref" ]] || fail "synthetic selections did not seal"

workers="$scratch/workers"
snapshots="$scratch/snapshots"
: >"$workers"
: >"$snapshots"
cat >"$bin/unshare" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat >"$bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
tree=''
prompt=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) tree=$2; shift 2 ;;
    --sandbox|--config) shift 2 ;;
    *) prompt=$1; shift ;;
  esac
done
[[ -n "$tree" && "$tree" != "$FAKE_SOURCE" ]]
[[ -f "$tree/docs/prd.md" && -f "$tree/skills/dashboard.md" && -f "$tree/skills/cli.md" ]]
[[ -f "$tree/recipes/shared.md" && -f "$tree/recipes/cli.md" ]]
[[ "$prompt" == *'Selection digest:'* ]]
if [[ "${FAKE_NO_ROUTE:-0}" != 1 ]]; then
  [[ "$prompt" == *'Entry "dashboard-create"'* ]]
  [[ "$prompt" == *'Entry "dashboard-remove"'* ]]
  [[ "$prompt" == *'Entry "cli-list"'* ]]
fi
printf '%s\n' "$tree" >>"$FAKE_SNAPSHOTS"
printf 'worker\n' >>"$FAKE_WORKERS"
if [[ "${FAKE_REVIEW_DRIFT:-0}" == 1 ]]; then
  printf 'drift\n' >>"$FAKE_SOURCE/recipes/shared.md"
fi
case "$prompt" in
  *'## Findings — Codex Quality'*) header='## Findings — Codex Quality' ;;
  *'## Findings — Codex Security'*) header='## Findings — Codex Security' ;;
  *) header='## Findings — Codex Spec' ;;
esac
printf '%s\n\nNO FINDINGS\n' "$header"
SH
cat >"$bin/claude" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == -L ]]; then shift 2; fi
case "$1" in
  new-session|new-window|send-keys|has-session|kill-session) exit 0 ;;
  load-buffer)
    name=$3
    source=$4
    cp "$source" "$FAKE_TMUX_STATE/$name"
    exit 0
    ;;
  paste-buffer)
    name=$3
    prompt=$(cat "$FAKE_TMUX_STATE/$name")
    output=$(sed -n 's#^- Write the final report to: ##p' "$FAKE_TMUX_STATE/$name")
    done_file=$(sed -n 's#^mkdir -p ".*" && printf .done\\n. > "\(.*\)"#\1#p' "$FAKE_TMUX_STATE/$name")
    digest=$(sed -n 's#^- Selection digest: ##p' "$FAKE_TMUX_STATE/$name" | head -n 1)
    [[ -n "$output" && -n "$done_file" && -n "$digest" ]]
    if [[ "${FAKE_TMUX_SWAP_DIGEST:-0}" == 1 ]]; then digest="$(printf '0%.0s' {1..64})"; fi
    if [[ "$prompt" == *'Claude Quality'* ]]; then header='## Findings — Claude Quality'; else header='## Findings — Claude Spec'; fi
    mkdir -p "$(dirname "$output")" "$(dirname "$done_file")"
    {
      echo '## Sealed verification selection'
      sed -n '/^Sealed verification selection\./,/^Produce findings/p' "$FAKE_TMUX_STATE/$name" | sed '$d' | sed "s#^- Selection digest: .*#- Selection digest: $digest#"
      echo
      echo "$header"
      echo
      echo 'NO FINDINGS'
    } >"$output"
    printf 'done\n' >"$done_file"
    printf 'worker\n' >>"$FAKE_WORKERS"
    exit 0
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "$bin/unshare" "$bin/codex" "$bin/claude" "$bin/tmux"
export PATH="$bin:$PATH"
export FAKE_SOURCE="$repo" FAKE_WORKERS="$workers" FAKE_SNAPSHOTS="$snapshots" FAKE_TMUX_STATE="$scratch/tmux"
mkdir -p "$FAKE_TMUX_STATE"

source_runner="$root/skills/df-code-review/scripts/run_codex_spec_review.sh"
codex_runner="$root/codex-plugin/skills/df-code-review/scripts/run_codex_subagent_reviews.sh"
tmux_runner="$root/codex-plugin/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh"

echo '== source runner and frozen snapshot =='
DARK_FACTORY_ROOT="$root" bash "$source_runner" docs/prd.md "$selection_ref" "$repo" "$base_ref" "$reports/source.md"
grep -Fq "Selection digest: ${selection_ref##*:sha256:}" "$reports/source.md"
grep -Fq 'Entry "dashboard-create"' "$reports/source.md"
grep -Fq 'Entry "dashboard-remove"' "$reports/source.md"
grep -Fq 'Entry "cli-list"' "$reports/source.md"
[[ -f "$reports/source.md.selection.json" ]] || fail "source runner did not write an external selection input"
while IFS= read -r snapshot; do [[ ! -e "$snapshot" ]] || fail "source review snapshot survived cleanup"; done <"$snapshots"
git -C "$repo" diff --exit-code
pass 'source runner preserves all selected identities in a frozen disposable snapshot'

echo '== installed Codex wrappers =='
DARK_FACTORY_ROOT="$root/codex-plugin" DARK_FACTORY_REVIEW_DIR="$reports/codex-work" \
  bash "$codex_runner" docs/prd.md "$selection_ref" "$repo" "$base_ref" "$reports/codex"
for report in "$reports/codex"/*-review.md; do
  grep -Fq "Selection digest: ${selection_ref##*:sha256:}" "$report"
  grep -Fq 'Entry "dashboard-remove"' "$report"
done
pass 'Codex multi-review wrapper keeps every selected identity in each report header'

echo '== tmux transport =='
CLAUDE_REVIEW_STARTUP_DELAY=0 CLAUDE_REVIEW_TIMEOUT_SECONDS=5 \
  DARK_FACTORY_ROOT="$root/codex-plugin" bash "$tmux_runner" docs/prd.md "$selection_ref" "$repo" "$base_ref" "$reports/claude"
for report in "$reports/claude"/*-review.md; do
  grep -Fq "Selection digest: ${selection_ref##*:sha256:}" "$report"
  grep -Fq 'Entry "cli-list"' "$report"
done
pass 'tmux reports reject a missing selection digest and retain the sealed identities'

if FAKE_TMUX_SWAP_DIGEST=1 CLAUDE_REVIEW_STARTUP_DELAY=0 CLAUDE_REVIEW_TIMEOUT_SECONDS=5 \
  DARK_FACTORY_ROOT="$root/codex-plugin" bash "$tmux_runner" docs/prd.md "$selection_ref" "$repo" "$base_ref" "$reports/claude-swapped" \
  >"$scratch/swapped.out" 2>"$scratch/swapped.err"; then
  fail 'tmux transport accepted a swapped selection digest'
fi
grep -Fq 'missing_selection_digest' "$scratch/swapped.err"
pass 'a reviewer report with a swapped selection digest is rejected'

echo '== copied skill location =='
copied="$scratch/copied/df-code-review"
mkdir -p "$scratch/copied"
cp -a "$root/skills/df-code-review" "$copied"
DARK_FACTORY_ROOT="$root" bash "$copied/scripts/run_codex_spec_review.sh" \
  docs/prd.md "$selection_ref" "$repo" "$base_ref" "$reports/copied.md"
grep -Fq "Selection digest: ${selection_ref##*:sha256:}" "$reports/copied.md"
pass 'copied skill wrapper resolves helpers through the session-hook root'

echo '== closed input failures =='
before=$(wc -l <"$workers")
expect_failure 'legacy four-position QA-path ABI is rejected' "$before" \
  bash "$source_runner" docs/prd.md recipes/shared.md "$base_ref" "$reports/legacy.md"
expect_failure 'missing selection ref is rejected before a reviewer starts' "$before" \
  env DARK_FACTORY_ROOT="$root" bash "$source_runner" docs/prd.md "review-selection:sha256:$(printf '0%.0s' {1..64})" "$repo" "$base_ref" "$reports/missing.md"
expect_failure 'substituted PRD path is rejected before a reviewer starts' "$before" \
  env DARK_FACTORY_ROOT="$root" bash "$source_runner" docs/not-prd.md "$selection_ref" "$repo" "$base_ref" "$reports/wrong-prd.md"

echo '== explicit no-user-route =='
FAKE_NO_ROUTE=1 DARK_FACTORY_ROOT="$root" bash "$source_runner" \
  docs/prd.md "$no_route_ref" "$repo" "$base_ref" "$reports/no-route.md"
grep -Fq 'No-user-route reason: This synthetic change has no user-facing route.' "$reports/no-route.md"
grep -Fq 'Selected entries: 0' "$reports/no-route.md"
unset FAKE_NO_ROUTE
pass 'no-user-route seal remains explicit with zero selected entries'

echo '== source drift =='
before=$(wc -l <"$workers")
if FAKE_REVIEW_DRIFT=1 DARK_FACTORY_ROOT="$root" bash "$source_runner" \
  docs/prd.md "$selection_ref" "$repo" "$base_ref" "$reports/drift.md" >"$scratch/drift.out" 2>"$scratch/drift.err"; then
  fail 'changed selected recipe was accepted'
fi
[[ $(wc -l <"$workers") -eq $((before + 1)) ]] || fail 'drift fixture did not reach exactly one fake worker'
grep -Fq 'selected source changed during review' "$scratch/drift.err"
pass 'changed selected recipe invalidates the completed reviewer result'

echo 'PASS: code-review selection consumer tests completed'
