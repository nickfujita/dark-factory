#!/usr/bin/env bash
# Acceptance tests for the immutable verification-selection ABI.
#
# Uses only a synthetic git repository and an external XDG state root. It
# drives both shipped plugin roots as CLIs; it never invokes project checkers.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROOT_SELECTION=$ROOT/scripts/df-selection.mjs
CODEX_SELECTION=$ROOT/codex-plugin/scripts/df-selection.mjs
STATE=$ROOT/scripts/df-state.sh
TMP=$(mktemp -d "${TMPDIR:-/tmp}/df-selection-test.XXXXXX")
REPO=$TMP/consumer
OTHER_REPO=$TMP/other-consumer
export XDG_STATE_HOME=$TMP/state-home
trap 'rm -rf "$TMP"' EXIT

ASSERTS=0
FAILURES=0

pass() { ASSERTS=$((ASSERTS + 1)); printf 'PASS  %s\n' "$1"; }
fail() { ASSERTS=$((ASSERTS + 1)); FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$1"; }

assert_eq() { # description expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

assert_contains() { # description needle file
  if grep -Fq -- "$2" "$3"; then pass "$1"; else fail "$1 (missing '$2')"; fi
}

expect_failure() { # description command...
  local description=$1 output code
  shift
  output=$TMP/failure-$ASSERTS.txt
  "$@" >"$output" 2>&1
  code=$?
  if [ "$code" -ne 0 ]; then
    pass "$description"
    LAST_FAILURE=$output
  else
    fail "$description (command unexpectedly succeeded)"
    LAST_FAILURE=$output
  fi
}

selection_ref() { # command output -> selection ref
  awk -F= '/^SELECTION_REF=/{print $2}' "$1"
}

write_draft() { # destination mode [reversed]
  node - "$1" "$2" "${3:-}" <<'NODE'
const { createHash } = require("node:crypto");
const { readFileSync, writeFileSync } = require("node:fs");
const [destination, mode, reversed] = process.argv.slice(2);
const hash = (name) => createHash("sha256").update(readFileSync(`${process.env.SELECTION_FIXTURE_ROOT}/${name}`)).digest("hex");
const entry = (id, medium, recipe, subFeature, requirements, negatives) => ({
  id,
  medium,
  skillPath: "skills/verification.md",
  skillSha256: hash("skills/verification.md"),
  recipePath: recipe,
  subFeature,
  recipeSha256: hash(recipe),
  requirementIds: requirements,
  negativeRequirementIds: negatives,
});
const base = {
  schemaVersion: 1,
  kind: "user-facing",
  runId: "selection-run",
  featureSlug: "synthetic-feature",
  prdPath: "docs/prd.md",
  prdSha256: hash("docs/prd.md"),
  catalogLink: mode === "no-catalog" ? null : { path: "links/catalog.json", sha256: hash("links/catalog.json") },
  declaredMedia: ["synthetic-api", "voice-interface"],
  entries: [
    entry("api-create", "synthetic-api", "recipes/api-create.md", "create", ["REQ-002", "REQ-001"], ["NEG-002", "NEG-001"]),
    entry("voice-list", "voice-interface", "recipes/voice-list.md", null, ["REQ-003"], []),
  ],
};
if (reversed === "reversed") {
  base.declaredMedia.reverse();
  base.entries.reverse();
  for (const item of base.entries) {
    item.requirementIds.reverse();
    item.negativeRequirementIds.reverse();
  }
}
if (mode === "no-user-route") {
  delete base.catalogLink;
  delete base.declaredMedia;
  base.kind = "no-user-route";
  base.reason = "This synthetic feature has no user-facing route.";
  base.entries = [];
}
writeFileSync(destination, JSON.stringify(base, null, 2));
NODE
}

write_locale_draft() { # destination
  node - "$1" <<'NODE'
const { createHash } = require("node:crypto");
const { readFileSync, writeFileSync } = require("node:fs");
const [destination] = process.argv.slice(2);
const hash = (name) => createHash("sha256").update(readFileSync(`${process.env.SELECTION_FIXTURE_ROOT}/${name}`)).digest("hex");
const entry = (id, medium, recipe, subFeature) => ({
  id, medium, skillPath: "skills/verification.md", skillSha256: hash("skills/verification.md"),
  recipePath: recipe, recipeSha256: hash(recipe), subFeature,
  requirementIds: ["REQ-LOCALE"], negativeRequirementIds: [],
});
writeFileSync(destination, JSON.stringify({
  schemaVersion: 1, kind: "user-facing", runId: "selection-run", featureSlug: "locale-order",
  prdPath: "docs/prd.md", prdSha256: hash("docs/prd.md"), catalogLink: null,
  declaredMedia: ["z", "ä"],
  entries: [entry("z-entry", "z", "recipes/z.md", "z"), entry("umlaut-entry", "ä", "recipes/ä.md", null)],
}, null, 2));
NODE
}

write_no_route_draft() { # destination repository run-id
  node - "$1" "$2" "$3" <<'NODE'
const { createHash } = require("node:crypto");
const { readFileSync, writeFileSync } = require("node:fs");
const [destination, repository, runId] = process.argv.slice(2);
const prdPath = "prd.md";
writeFileSync(destination, JSON.stringify({
  schemaVersion: 1, kind: "no-user-route", runId, featureSlug: "association-fixture",
  prdPath, prdSha256: createHash("sha256").update(readFileSync(`${repository}/${prdPath}`)).digest("hex"),
  reason: "This synthetic fixture has no user-facing route.", entries: [],
}, null, 2));
NODE
}

mutate_draft() { # source destination mode
  node - "$1" "$2" "$3" <<'NODE'
const { createHash } = require("node:crypto");
const { readFileSync, writeFileSync } = require("node:fs");
const [source, destination, mode] = process.argv.slice(2);
const doc = JSON.parse(readFileSync(source));
const hash = (name) => createHash("sha256").update(readFileSync(`${process.env.SELECTION_FIXTURE_ROOT}/${name}`)).digest("hex");
if (mode === "empty") doc.entries = [];
if (mode === "undeclared") doc.entries[0].medium = "unlisted-surface";
if (mode === "duplicate-id") doc.entries[1].id = doc.entries[0].id;
if (mode === "duplicate-identity") {
  doc.entries[1].medium = doc.entries[0].medium;
  doc.entries[1].recipePath = doc.entries[0].recipePath;
  doc.entries[1].recipeSha256 = doc.entries[0].recipeSha256;
  doc.entries[1].subFeature = doc.entries[0].subFeature;
}
if (mode === "traversal") {
  doc.entries[0].recipePath = "../outside.md";
  doc.entries[0].recipeSha256 = "0".repeat(64);
}
if (mode === "symlink") {
  doc.entries[0].recipePath = "recipes/escape-link.md";
  doc.entries[0].recipeSha256 = hash("../outside.md");
}
if (mode === "extra") doc.unexpected = true;
if (mode === "sealed-root") doc.repoRoot = "/not-caller-authored";
if (mode === "concurrent") doc.featureSlug = "concurrent-synthetic-feature";
writeFileSync(destination, JSON.stringify(doc, null, 2));
NODE
}

echo "== setup synthetic consuming repositories =="
mkdir -p "$REPO/docs" "$REPO/skills" "$REPO/recipes" "$REPO/links" "$OTHER_REPO"
printf 'Synthetic PRD content.\n' >"$REPO/docs/prd.md"
printf 'Synthetic verification skill.\n' >"$REPO/skills/verification.md"
printf 'Drive the synthetic API create route.\n' >"$REPO/recipes/api-create.md"
printf 'Drive the synthetic voice list route.\n' >"$REPO/recipes/voice-list.md"
printf 'Drive the synthetic z route.\n' >"$REPO/recipes/z.md"
printf 'Drive the synthetic umlaut route.\n' >"$REPO/recipes/ä.md"
printf '{"catalog":"synthetic"}\n' >"$REPO/links/catalog.json"
printf 'outside the synthetic repository\n' >"$TMP/outside.md"
ln -s "$TMP/outside.md" "$REPO/recipes/escape-link.md"
git -C "$REPO" init -q
git -C "$OTHER_REPO" init -q
export SELECTION_FIXTURE_ROOT=$REPO
(cd "$REPO" && bash "$STATE" init selection-run standard 20 120 "synthetic selection checks") >/dev/null 2>&1
RUN_DIR=$(cd "$REPO" && bash "$STATE" path selection-run)
write_draft "$TMP/base.json" catalog
write_draft "$TMP/reordered.json" catalog reversed
write_draft "$TMP/no-catalog.json" no-catalog
write_draft "$TMP/no-route.json" no-user-route
write_locale_draft "$TMP/locale.json"

echo "== canonical union and installed-root coverage =="
node "$ROOT_SELECTION" seal --run selection-run --draft "$TMP/base.json" --repo-root "$REPO" >"$TMP/base.out"
BASE_REF=$(selection_ref "$TMP/base.out")
assert_contains "root CLI seals a selection" "STATUS=sealed" "$TMP/base.out"
node --input-type=module - "$ROOT_SELECTION" "$REPO" "$TMP/base.json" >"$TMP/api-contract.out" <<'NODE'
import { pathToFileURL } from "node:url";
const [helper, repoRoot, draftPath] = process.argv.slice(2);
const library = await import(pathToFileURL(helper));
const ref = library.sealSelection({ runId: "selection-run", draftPath, repoRoot });
const opened = library.openSelection({ ref, repoRoot });
const materialized = library.materializeSelection({ ref, repoRoot, consumer: "acceptance" });
let rejectsInvalidObject = false;
try {
  library.openSelection({ ref: { ...ref, unexpected: true }, repoRoot });
} catch {
  rejectsInvalidObject = true;
}
if (opened.entries.length !== 2 || materialized.length !== 2 || !rejectsInvalidObject) process.exit(1);
console.log("API_COMPOSITION=passed");
console.log("INVALID_REF_OBJECT=passed");
NODE
assert_contains "public SelectionRef objects compose seal, open, and materialize" "API_COMPOSITION=passed" "$TMP/api-contract.out"
assert_contains "public APIs reject malformed SelectionRef objects" "INVALID_REF_OBJECT=passed" "$TMP/api-contract.out"
node "$CODEX_SELECTION" seal --run selection-run --draft "$TMP/reordered.json" --repo-root "$REPO" >"$TMP/reordered.out"
REORDERED_REF=$(selection_ref "$TMP/reordered.out")
assert_eq "reordered equivalent selections share one digest" "$BASE_REF" "$REORDERED_REF"
node "$CODEX_SELECTION" materialize --ref "$BASE_REF" --repo-root "$REPO" --consumer acceptance --format json >"$TMP/materialized.json"
entry_count=$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1])).length)' "$TMP/materialized.json")
assert_eq "materialize returns both selected media" 2 "$entry_count"
node "$ROOT_SELECTION" inspect --ref "$BASE_REF" --repo-root "$REPO" >"$TMP/base.inspect.json"
SEALED_REPO_ROOT=$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1])).repoRoot)' "$TMP/base.inspect.json")
assert_eq "sealed selection records the canonical consuming repository root" "$(realpath "$REPO")" "$SEALED_REPO_ROOT"
node "$ROOT_SELECTION" materialize --ref "$BASE_REF" --repo-root "$REPO" --consumer qa-validation --format paths >"$TMP/materialized.paths"
assert_contains "paths format retains a selected sub-feature" '"create"' "$TMP/materialized.paths"
assert_contains "paths format retains the synthetic medium" '"synthetic-api"' "$TMP/materialized.paths"
env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 node "$ROOT_SELECTION" seal --run selection-run --draft "$TMP/locale.json" --repo-root "$REPO" >"$TMP/locale-en.out"
env LANG=sv_SE.UTF-8 LC_ALL=sv_SE.UTF-8 node "$CODEX_SELECTION" seal --run selection-run --draft "$TMP/locale.json" --repo-root "$REPO" >"$TMP/locale-sv.out"
LOCALE_EN_REF=$(selection_ref "$TMP/locale-en.out")
LOCALE_SV_REF=$(selection_ref "$TMP/locale-sv.out")
assert_eq "non-ASCII equivalent drafts keep one digest across locales" "$LOCALE_EN_REF" "$LOCALE_SV_REF"
env LANG=sv_SE.UTF-8 LC_ALL=sv_SE.UTF-8 node "$ROOT_SELECTION" materialize --ref "$LOCALE_EN_REF" --repo-root "$REPO" --consumer acceptance --format json >"$TMP/locale-read.json"
assert_eq "cross-locale reads retain every non-ASCII entry" 2 "$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1])).length)' "$TMP/locale-read.json")"
node "$CODEX_SELECTION" seal --run selection-run --draft "$TMP/no-catalog.json" --repo-root "$REPO" >"$TMP/no-catalog.out"
NO_CATALOG_REF=$(selection_ref "$TMP/no-catalog.out")
node "$ROOT_SELECTION" inspect --ref "$NO_CATALOG_REF" --repo-root "$REPO" >"$TMP/no-catalog.inspect.json"
catalog_value=$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1])).catalogLink === null)' "$TMP/no-catalog.inspect.json")
assert_eq "explicit null preserves an optional no-catalog configuration" true "$catalog_value"
node "$ROOT_SELECTION" seal --run selection-run --draft "$TMP/no-route.json" --repo-root "$REPO" >"$TMP/no-route.out"
NO_ROUTE_REF=$(selection_ref "$TMP/no-route.out")
node "$CODEX_SELECTION" materialize --ref "$NO_ROUTE_REF" --repo-root "$REPO" --consumer code-review --format json >"$TMP/no-route.json.out"
no_route_count=$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1])).length)' "$TMP/no-route.json.out")
assert_eq "no-user-route accepts zero entries with a reason" 0 "$no_route_count"

echo "== strict selection validation =="
SYMLINK_FAILURE=
for mode in empty undeclared duplicate-id duplicate-identity traversal symlink extra sealed-root; do
  mutate_draft "$TMP/base.json" "$TMP/invalid-$mode.json" "$mode"
  expect_failure "rejects invalid draft: $mode" node "$ROOT_SELECTION" seal --run selection-run --draft "$TMP/invalid-$mode.json" --repo-root "$REPO"
  [ "$mode" = symlink ] && SYMLINK_FAILURE=$LAST_FAILURE
done
assert_contains "symlink escape names the rejected field" "symlink resolution escapes repository root" "$SYMLINK_FAILURE"
expect_failure "materialize requires an explicit ref" node "$ROOT_SELECTION" materialize --repo-root "$REPO" --consumer acceptance --format json
expect_failure "latest is not a valid selection ref" node "$ROOT_SELECTION" inspect --ref latest --repo-root "$REPO"
expect_failure "malformed digest cannot select a path" node "$ROOT_SELECTION" inspect --ref selection-run:sha256:not-a-digest --repo-root "$REPO"
expect_failure "a different repository cannot inspect this run" node "$ROOT_SELECTION" inspect --ref "$BASE_REF" --repo-root "$OTHER_REPO"

echo "== sealed repository association =="
COLLISION_A=$TMP/project-a
COLLISION_B=$TMP/project_a
mkdir -p "$COLLISION_A" "$COLLISION_B"
git -C "$COLLISION_A" init -q
git -C "$COLLISION_B" init -q
printf 'owned repository source\n' >"$COLLISION_A/prd.md"
printf 'other repository source\n' >"$COLLISION_B/prd.md"
(cd "$COLLISION_A" && bash "$STATE" init collision-run standard 2 20 "synthetic state-key collision") >/dev/null 2>&1
COLLISION_STORE_A=$(cd "$COLLISION_A" && bash "$STATE" path collision-run)
COLLISION_STORE_B=$(cd "$COLLISION_B" && bash "$STATE" path collision-run)
assert_eq "lossy inherited state keys collide in the fixture" "$COLLISION_STORE_A" "$COLLISION_STORE_B"
write_no_route_draft "$TMP/collision.json" "$COLLISION_A" collision-run
node "$ROOT_SELECTION" seal --run collision-run --draft "$TMP/collision.json" --repo-root "$COLLISION_A" >"$TMP/collision.out"
COLLISION_REF=$(selection_ref "$TMP/collision.out")
expect_failure "colliding inherited state cannot cross repository binding" node "$CODEX_SELECTION" inspect --ref "$COLLISION_REF" --repo-root "$COLLISION_B"
assert_contains "colliding state is rejected before source-digest reads" "selection.repoRoot" "$LAST_FAILURE"

SHARED_A=$TMP/shared-a
SHARED_B=$TMP/shared-b
SHARED_STATE=$TMP/explicit-shared-state
mkdir -p "$SHARED_A" "$SHARED_B"
git -C "$SHARED_A" init -q
git -C "$SHARED_B" init -q
printf 'explicit shared-state owner source\n' >"$SHARED_A/prd.md"
printf 'explicit shared-state other source\n' >"$SHARED_B/prd.md"
(cd "$SHARED_A" && DF_STATE_ROOT="$SHARED_STATE" bash "$STATE" init shared-run standard 2 20 "synthetic explicit shared state") >/dev/null 2>&1
write_no_route_draft "$TMP/shared.json" "$SHARED_A" shared-run
DF_STATE_ROOT="$SHARED_STATE" node "$ROOT_SELECTION" seal --run shared-run --draft "$TMP/shared.json" --repo-root "$SHARED_A" >"$TMP/shared.out"
SHARED_REF=$(selection_ref "$TMP/shared.out")
expect_failure "explicit shared DF_STATE_ROOT cannot cross repository binding" env DF_STATE_ROOT="$SHARED_STATE" node "$ROOT_SELECTION" inspect --ref "$SHARED_REF" --repo-root "$SHARED_B"
assert_contains "explicit shared state names the repository binding" "selection.repoRoot" "$LAST_FAILURE"

echo "== source-drift failure is fail-closed =="
ORIGINAL_PRD=$(<"$REPO/docs/prd.md")
ORIGINAL_SKILL=$(<"$REPO/skills/verification.md")
ORIGINAL_RECIPE=$(<"$REPO/recipes/api-create.md")
ORIGINAL_CATALOG=$(<"$REPO/links/catalog.json")
for target in docs/prd.md skills/verification.md recipes/api-create.md links/catalog.json; do
  original_var=ORIGINAL_PRD
  case "$target" in
    skills/*) original_var=ORIGINAL_SKILL ;;
    recipes/*) original_var=ORIGINAL_RECIPE ;;
    links/*) original_var=ORIGINAL_CATALOG ;;
  esac
  printf '%s changed\n' "${!original_var}" >"$REPO/$target"
  expect_failure "materialize rejects changed $target" node "$CODEX_SELECTION" materialize --ref "$BASE_REF" --repo-root "$REPO" --consumer dev-verify --format json
  assert_contains "changed $target reports its expected digest" "expected" "$LAST_FAILURE"
  assert_contains "changed $target reports its path" "$target" "$LAST_FAILURE"
  printf '%s\n' "${!original_var}" >"$REPO/$target"
done
node "$ROOT_SELECTION" materialize --ref "$BASE_REF" --repo-root "$REPO" --consumer dev-verify --format json >"$TMP/recovered.json"
assert_eq "materialize succeeds again only after source restoration" 2 "$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1])).length)' "$TMP/recovered.json")"

echo "== immutable atomic publication =="
BASE_DIGEST=${BASE_REF##*:sha256:}
SEALED_FILE=$RUN_DIR/verification-selections/$BASE_DIGEST.json
ORIGINAL_SEALED=$(<"$SEALED_FILE")
printf '{}' >"$SEALED_FILE"
expect_failure "tampered sealed content is rejected" node "$ROOT_SELECTION" inspect --ref "$BASE_REF" --repo-root "$REPO"
expect_failure "sealing never overwrites differing content at an existing digest" node "$ROOT_SELECTION" seal --run selection-run --draft "$TMP/base.json" --repo-root "$REPO"
assert_eq "tampered selection remains untouched by failed seal" '{}' "$(<"$SEALED_FILE")"
printf '%s' "$ORIGINAL_SEALED" >"$SEALED_FILE"
mutate_draft "$TMP/base.json" "$TMP/concurrent.json" concurrent
for index in 1 2 3 4 5 6 7 8; do
  (
    node "$ROOT_SELECTION" seal --run selection-run --draft "$TMP/concurrent.json" --repo-root "$REPO" >"$TMP/concurrent-$index.out" 2>"$TMP/concurrent-$index.err"
    printf '%s' "$?" >"$TMP/concurrent-$index.code"
  ) &
done
wait
concurrent_ok=0
concurrent_refs=""
for index in 1 2 3 4 5 6 7 8; do
  code=$(<"$TMP/concurrent-$index.code")
  [ "$code" = 0 ] && concurrent_ok=$((concurrent_ok + 1))
  concurrent_refs="$concurrent_refs $(selection_ref "$TMP/concurrent-$index.out")"
done
CONCURRENT_REF=$(printf '%s\n' "$concurrent_refs" | awk '{for (i=1;i<=NF;i++) print $i}' | sort -u)
assert_eq "all concurrent equal-content seals succeed" 8 "$concurrent_ok"
assert_eq "concurrent seals converge on one ref" 1 "$(printf '%s\n' "$CONCURRENT_REF" | sed '/^$/d' | wc -l | tr -d ' ')"
CONCURRENT_DIGEST=${CONCURRENT_REF##*:sha256:}
assert_eq "concurrent seals leave one complete canonical file" 1 "$(find "$RUN_DIR/verification-selections" -maxdepth 1 -name "$CONCURRENT_DIGEST.json" -type f | wc -l | tr -d ' ')"

echo "== retained-run reads =="
(cd "$REPO" && bash "$STATE" stop selection-run done) >/dev/null 2>&1
node "$CODEX_SELECTION" materialize --ref "$BASE_REF" --repo-root "$REPO" --consumer acceptance --format json >"$TMP/retained.json"
assert_eq "finished runs remain readable by explicit ref" 2 "$(node -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1])).length)' "$TMP/retained.json")"
expect_failure "finished runs cannot seal a replacement" node "$ROOT_SELECTION" seal --run selection-run --draft "$TMP/base.json" --repo-root "$REPO"

echo "== exact installed mirrors =="
for pair in \
  "scripts/df-selection.mjs codex-plugin/scripts/df-selection.mjs" \
  "scripts/test-df-selection.sh codex-plugin/scripts/test-df-selection.sh" \
  "references/verification-selection.schema.json codex-plugin/references/verification-selection.schema.json"; do
  left=${pair%% *}
  right=${pair##* }
  if cmp -s "$ROOT/$left" "$ROOT/$right"; then pass "mirror matches: $left"; else fail "mirror differs: $left"; fi
done

printf '\n%d assertions, %d failures\n' "$ASSERTS" "$FAILURES"
[ "$FAILURES" -eq 0 ]
