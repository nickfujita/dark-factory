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

claude_run=review-selection-claude
codex_run=review-selection-codex
node - "$repo" "$scratch/selection-claude.json" "$scratch/selection-codex.json" "$scratch/no-route.json" <<'NODE'
const { createHash } = require("node:crypto");
const { readFileSync, writeFileSync } = require("node:fs");
const [repo, claudePath, codexPath, noRoutePath] = process.argv.slice(2);
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
const selection = {
  schemaVersion: 1,
  kind: "user-facing",
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
};
writeFileSync(claudePath, JSON.stringify({ ...selection, runId: "review-selection-claude" }, null, 2));
writeFileSync(codexPath, JSON.stringify({ ...selection, runId: "review-selection-codex" }, null, 2));
writeFileSync(noRoutePath, JSON.stringify({
  schemaVersion: 1,
  kind: "no-user-route",
  runId: "review-selection-claude",
  featureSlug: "synthetic-no-route",
  prdPath: "docs/prd.md",
  prdSha256: hash("docs/prd.md"),
  reason: "This synthetic change has no user-facing route.",
  entries: [],
}, null, 2));
NODE

for run in "$claude_run" "$codex_run"; do
  (cd "$repo" && bash "$root/scripts/df-state.sh" init "$run" standard 20 120 "synthetic code review") >/dev/null
done
node "$root/scripts/df-role.mjs" prepare-run --run "$claude_run" --harness claude --repo-root "$repo" >/dev/null
node "$root/codex-plugin/scripts/df-role.mjs" prepare-run --run "$codex_run" --harness codex --repo-root "$repo" >/dev/null
selection_ref_claude=$(node "$root/scripts/df-selection.mjs" seal --run "$claude_run" --draft "$scratch/selection-claude.json" --repo-root "$repo" | awk -F= '/^SELECTION_REF=/{print $2}')
selection_ref_codex=$(node "$root/scripts/df-selection.mjs" seal --run "$codex_run" --draft "$scratch/selection-codex.json" --repo-root "$repo" | awk -F= '/^SELECTION_REF=/{print $2}')
no_route_ref=$(node "$root/scripts/df-selection.mjs" seal --run "$claude_run" --draft "$scratch/no-route.json" --repo-root "$repo" | awk -F= '/^SELECTION_REF=/{print $2}')
[[ -n "$selection_ref_claude" && -n "$selection_ref_codex" && -n "$no_route_ref" ]] || fail "synthetic selections did not seal"

workers="$scratch/workers"
snapshots="$scratch/snapshots"
tmux_cwds="$scratch/tmux-cwds"
: >"$workers"
: >"$snapshots"
: >"$tmux_cwds"
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
  new-session|new-window)
    shift
    cwd=''
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -c) cwd=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -n "$cwd" && "$cwd" != "$FAKE_SOURCE" ]]
    [[ -f "$cwd/docs/prd.md" && -f "$cwd/skills/dashboard.md" && -f "$cwd/skills/cli.md" ]]
    [[ -f "$cwd/recipes/shared.md" && -f "$cwd/recipes/cli.md" ]]
    printf '%s\n' "$cwd" >>"$FAKE_TMUX_CWDS"
    exit 0
    ;;
  send-keys|has-session|kill-session) exit 0 ;;
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
    selection_input="$(dirname "$output")/selection-input.json"
    if [[ "${FAKE_TMUX_REWRITE_INPUT:-0}" == 1 ]]; then
      sed -i 's/"id": "cli-list"/"id": "cli-list-replaced"/' "$selection_input"
    fi
    if [[ "$prompt" == *'Claude Quality'* ]]; then header='## Findings — Claude Quality'; else header='## Findings — Claude Spec'; fi
    mkdir -p "$(dirname "$output")" "$(dirname "$done_file")"
    {
      echo '## Sealed verification selection'
      sed -n '/^Sealed verification selection\./,/^Produce findings/p' "$FAKE_TMUX_STATE/$name" | sed '$d' | sed "s#^- Selection digest: .*#- Selection digest: $digest#" | {
        if [[ "${FAKE_TMUX_SWAP_IDENTITY:-0}" == 1 || "${FAKE_TMUX_REWRITE_INPUT:-0}" == 1 ]]; then
          sed 's#Entry "cli-list"#Entry "cli-list-replaced"#'
        else
          cat
        fi
      }
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
export FAKE_SOURCE="$repo" FAKE_WORKERS="$workers" FAKE_SNAPSHOTS="$snapshots" FAKE_TMUX_STATE="$scratch/tmux" FAKE_TMUX_CWDS="$tmux_cwds"
mkdir -p "$FAKE_TMUX_STATE"

source_runner="$root/skills/df-code-review/scripts/run_codex_spec_review.sh"
quality_runner="$root/skills/df-code-review/scripts/run_codex_quality_review.sh"
codex_runner="$root/codex-plugin/skills/df-code-review/scripts/run_codex_subagent_reviews.sh"
tmux_runner="$root/codex-plugin/skills/df-code-review/scripts/run_claude_code_reviews_tmux.sh"

echo '== source quality and frozen snapshot =='
DARK_FACTORY_ROOT="$root" bash "$quality_runner" \
  docs/prd.md "$selection_ref_claude" "$repo" "$base_ref" "$reports/quality.md" \
  --df-run "$claude_run" --df-lane standard --df-repo-root "$repo"
grep -Fq "Selection digest: ${selection_ref_claude##*:sha256:}" "$reports/quality.md"
grep -Fq 'Entry "dashboard-create"' "$reports/quality.md"
grep -Fq 'Entry "dashboard-remove"' "$reports/quality.md"
grep -Fq 'Entry "cli-list"' "$reports/quality.md"
[[ -f "$reports/quality.md.selection.json" ]] || fail "quality runner did not write a sealed selection input"

echo '== source spec and frozen snapshot =='
DARK_FACTORY_ROOT="$root" bash "$source_runner" \
  docs/prd.md "$selection_ref_claude" "$repo" "$base_ref" "$reports/source.md" \
  --df-run "$claude_run" --df-lane standard --df-repo-root "$repo"
grep -Fq "Selection digest: ${selection_ref_claude##*:sha256:}" "$reports/source.md"
grep -Fq 'Entry "dashboard-create"' "$reports/source.md"
grep -Fq 'Entry "dashboard-remove"' "$reports/source.md"
grep -Fq 'Entry "cli-list"' "$reports/source.md"
[[ -f "$reports/source.md.selection.json" ]] || fail "source runner did not write an external selection input"
while IFS= read -r snapshot; do [[ ! -e "$snapshot" ]] || fail "source review snapshot survived cleanup"; done <"$snapshots"
git -C "$repo" diff --exit-code
pass 'source quality and spec runners preserve all selected identities in frozen disposable snapshots'

echo '== installed Codex wrappers =='
DARK_FACTORY_ROOT="$root/codex-plugin" DARK_FACTORY_REVIEW_DIR="$reports/codex-work" \
  bash "$codex_runner" docs/prd.md "$selection_ref_codex" "$repo" "$base_ref" "$reports/codex" \
  --df-run "$codex_run" --df-lane standard --df-repo-root "$repo"
for report in "$reports/codex"/*-review.md; do
  grep -Fq "Selection digest: ${selection_ref_codex##*:sha256:}" "$report"
  grep -Fq 'Entry "dashboard-remove"' "$report"
done
pass 'Codex multi-review wrapper keeps every selected identity in each report header'

echo '== tmux transport =='
CLAUDE_REVIEW_STARTUP_DELAY=0 CLAUDE_REVIEW_TIMEOUT_SECONDS=5 \
  DARK_FACTORY_ROOT="$root/codex-plugin" bash "$tmux_runner" \
  docs/prd.md "$selection_ref_codex" "$repo" "$base_ref" "$reports/claude" \
  --df-run "$codex_run" --df-lane standard --df-repo-root "$repo"
for report in "$reports/claude"/*-review.md; do
  grep -Fq "Selection digest: ${selection_ref_codex##*:sha256:}" "$report"
  grep -Fq 'Entry "cli-list"' "$report"
done
[[ $(wc -l <"$tmux_cwds") -eq 2 ]] || fail 'tmux did not start both reviewers in a snapshot'
while IFS= read -r cwd; do [[ ! -e "$cwd" ]] || fail "tmux review snapshot survived cleanup"; done <"$tmux_cwds"
pass 'tmux reviewers use a frozen selected-input snapshot and retain sealed identities'

if TMPDIR="$scratch" FAKE_TMUX_SWAP_DIGEST=1 CLAUDE_REVIEW_STARTUP_DELAY=0 CLAUDE_REVIEW_TIMEOUT_SECONDS=5 \
  DARK_FACTORY_ROOT="$root/codex-plugin" bash "$tmux_runner" docs/prd.md "$selection_ref_codex" "$repo" "$base_ref" "$reports/claude-swapped" \
  --df-run "$codex_run" --df-lane standard --df-repo-root "$repo" \
  >"$scratch/swapped.out" 2>"$scratch/swapped.err"; then
  fail 'tmux transport accepted a swapped selection digest'
fi
grep -Fq 'quality: selection_header' "$scratch/swapped.err"
pass 'a reviewer report with a swapped selection digest is rejected'

if TMPDIR="$scratch" FAKE_TMUX_SWAP_IDENTITY=1 CLAUDE_REVIEW_STARTUP_DELAY=0 CLAUDE_REVIEW_TIMEOUT_SECONDS=5 \
  DARK_FACTORY_ROOT="$root/codex-plugin" bash "$tmux_runner" docs/prd.md "$selection_ref_codex" "$repo" "$base_ref" "$reports/claude-identity-swapped" \
  --df-run "$codex_run" --df-lane standard --df-repo-root "$repo" \
  >"$scratch/identity-swapped.out" 2>"$scratch/identity-swapped.err"; then
  fail 'tmux transport accepted a changed selected identity with the same digest'
fi
grep -Fq 'quality: selection_header' "$scratch/identity-swapped.err"
pass 'a reviewer report with the same digest but changed selected identity is rejected'

if TMPDIR="$scratch" FAKE_TMUX_REWRITE_INPUT=1 CLAUDE_REVIEW_STARTUP_DELAY=0 CLAUDE_REVIEW_TIMEOUT_SECONDS=5 \
  DARK_FACTORY_ROOT="$root/codex-plugin" bash "$tmux_runner" docs/prd.md "$selection_ref_codex" "$repo" "$base_ref" "$reports/claude-input-rewritten" \
  --df-run "$codex_run" --df-lane standard --df-repo-root "$repo" \
  >"$scratch/input-rewritten.out" 2>"$scratch/input-rewritten.err"; then
  fail 'tmux transport accepted a matching rewrite of the prepared input and report header'
fi
grep -Fq 'quality: selection_header' "$scratch/input-rewritten.err"
node "$root/scripts/df-code-review-selection.mjs" verify \
  --prd-path docs/prd.md \
  --selection-ref "$selection_ref_codex" \
  --repo-root "$repo" >/dev/null \
  || fail 'original selection seal became invalid during prepared-input rewrite case'
pass 'a matching rewrite of the prepared input and report header is rejected against the seal'

echo '== copied skill location =='
copied="$scratch/copied/df-code-review"
mkdir -p "$scratch/copied"
cp -a "$root/skills/df-code-review" "$copied"
DARK_FACTORY_ROOT="$root" bash "$copied/scripts/run_codex_spec_review.sh" \
  docs/prd.md "$selection_ref_claude" "$repo" "$base_ref" "$reports/copied.md" \
  --df-run "$claude_run" --df-lane standard --df-repo-root "$repo"
grep -Fq "Selection digest: ${selection_ref_claude##*:sha256:}" "$reports/copied.md"
pass 'copied skill wrapper resolves helpers through the session-hook root'

echo '== closed input failures =='
before=$(wc -l <"$workers")
expect_failure 'legacy four-position QA-path ABI is rejected' "$before" \
  bash "$source_runner" docs/prd.md recipes/shared.md "$base_ref" "$reports/legacy.md"
expect_failure 'legacy two-position quality ABI is rejected' "$before" \
  bash "$quality_runner" "$base_ref" "$reports/quality-legacy.md"
expect_failure 'missing selection ref is rejected before a reviewer starts' "$before" \
  env DARK_FACTORY_ROOT="$root" bash "$source_runner" docs/prd.md "$claude_run:sha256:$(printf '0%.0s' {1..64})" "$repo" "$base_ref" "$reports/missing.md" \
  --df-run "$claude_run" --df-lane standard --df-repo-root "$repo"
expect_failure 'substituted PRD path is rejected before a reviewer starts' "$before" \
  env DARK_FACTORY_ROOT="$root" bash "$source_runner" docs/not-prd.md "$selection_ref_claude" "$repo" "$base_ref" "$reports/wrong-prd.md" \
  --df-run "$claude_run" --df-lane standard --df-repo-root "$repo"

echo '== explicit no-user-route =='
FAKE_NO_ROUTE=1 DARK_FACTORY_ROOT="$root" bash "$source_runner" \
  docs/prd.md "$no_route_ref" "$repo" "$base_ref" "$reports/no-route.md" \
  --df-run "$claude_run" --df-lane standard --df-repo-root "$repo"
grep -Fq 'No-user-route reason: This synthetic change has no user-facing route.' "$reports/no-route.md"
grep -Fq 'Selected entries: 0' "$reports/no-route.md"
unset FAKE_NO_ROUTE
pass 'no-user-route seal remains explicit with zero selected entries'

echo '== source drift =='
before=$(wc -l <"$workers")
if FAKE_REVIEW_DRIFT=1 DARK_FACTORY_ROOT="$root" bash "$source_runner" \
  docs/prd.md "$selection_ref_claude" "$repo" "$base_ref" "$reports/drift.md" \
  --df-run "$claude_run" --df-lane standard --df-repo-root "$repo" \
  >"$scratch/drift.out" 2>"$scratch/drift.err"; then
  fail 'changed selected recipe was accepted'
fi
[[ $(wc -l <"$workers") -eq $((before + 1)) ]] || fail 'drift fixture did not reach exactly one fake worker'
grep -Fq 'selected source changed during review' "$scratch/drift.err"
pass 'changed selected recipe invalidates the completed reviewer result'

echo 'PASS: code-review selection consumer tests completed'
