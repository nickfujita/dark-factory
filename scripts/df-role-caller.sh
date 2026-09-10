#!/usr/bin/env bash
set -euo pipefail

# df-role-caller.sh resolves a frozen role, checks that this caller can express
# it, and records the dispatch before the caller starts its worker. It is shared
# by the shell-owned dispatchers in both plugin roots. Native harness callers
# use `preflight` before their own native reservation and spawn.

usage() {
  cat <<'USAGE'
Usage:
  df-role-caller.sh preflight --run <id> --lane <lane> --repo-root <path> \
      --responsibility <role> [--allow-kind <kind>] [--allow-transport <name>]
  df-role-caller.sh reserve --run <id> --lane <lane> --repo-root <path> \
      --responsibility <role> --purpose <text> \
      [--parent-seq <seq>] [--dispatch-count <n>] \
      [--allow-kind <kind>] [--allow-transport <name>]

`reserve` prints a JSON receipt only after frozen-role preflight and target
validation succeed. It does not prepare a run. Run entry owns prepare-run.
USAGE
}

die() {
  printf 'df-role-caller: %s\n' "$1" >&2
  exit "${2:-1}"
}

[[ $# -ge 1 ]] || { usage >&2; exit 1; }
command_name=$1
shift
case "$command_name" in
  preflight|reserve) ;;
  -h|--help) usage; exit 0 ;;
  *) die "unknown command '$command_name'" ;;
esac

run_id=''
lane=''
repo_root=''
responsibility=''
purpose=''
parent_seq=''
dispatch_count=1
declare -a allowed_kinds=()
declare -a allowed_transports=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      [[ $# -ge 2 ]] || die '--run needs a value'
      run_id=$2
      shift 2
      ;;
    --lane)
      [[ $# -ge 2 ]] || die '--lane needs a value'
      lane=$2
      shift 2
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || die '--repo-root needs a path'
      repo_root=$2
      shift 2
      ;;
    --responsibility)
      [[ $# -ge 2 ]] || die '--responsibility needs a value'
      responsibility=$2
      shift 2
      ;;
    --purpose)
      [[ $# -ge 2 ]] || die '--purpose needs a value'
      purpose=$2
      shift 2
      ;;
    --parent-seq)
      [[ $# -ge 2 ]] || die '--parent-seq needs a value'
      parent_seq=$2
      shift 2
      ;;
    --dispatch-count)
      [[ $# -ge 2 ]] || die '--dispatch-count needs a value'
      dispatch_count=$2
      shift 2
      ;;
    --allow-kind)
      [[ $# -ge 2 ]] || die '--allow-kind needs a value'
      allowed_kinds+=("$2")
      shift 2
      ;;
    --allow-transport)
      [[ $# -ge 2 ]] || die '--allow-transport needs a value'
      allowed_transports+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option '$1'" ;;
  esac
done

[[ -n "$run_id" ]] || die '--run is required; initialize and prepare the run before dispatching'
[[ -n "$lane" ]] || die '--lane is required'
[[ -n "$repo_root" ]] || die '--repo-root is required'
[[ -n "$responsibility" ]] || die '--responsibility is required'
[[ -d "$repo_root" ]] || die "repository root is not a directory: $repo_root"
[[ "$dispatch_count" =~ ^[1-9][0-9]*$ ]] || die '--dispatch-count must be a positive integer'
if [[ "$command_name" == reserve ]]; then
  [[ -n "$purpose" ]] || die '--purpose is required for reserve'
fi
if [[ -n "$parent_seq" && ! "$parent_seq" =~ ^[1-9][0-9]*$ ]]; then
  die '--parent-seq must be a positive sequence number'
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_root="$(cd "$script_dir/.." && pwd -P)"
role_helper="${DF_ROLE_CALLER_ROLE_HELPER:-$plugin_root/scripts/df-role.mjs}"
state_helper="${DF_ROLE_CALLER_STATE_HELPER:-$plugin_root/scripts/df-state.sh}"

[[ -f "$role_helper" ]] || die "role helper is not available: $role_helper"
[[ -f "$state_helper" ]] || die "state helper is not available: $state_helper"
repo_root="$(cd "$repo_root" && pwd -P)"

# A caller must not reserve a target for a different lane. The state helper's
# `path` operation is read-only and lets installed plugins key state by the
# consuming repository rather than their own cache directory.
run_dir="$(cd "$repo_root" && bash "$state_helper" path "$run_id")"
[[ -f "$run_dir/run.tsv" ]] || die "active run '$run_id' is not available for $repo_root"
run_lane="$(awk -F '\t' 'NR == 2 { print $2 }' "$run_dir/run.tsv")"
[[ "$run_lane" == "$lane" ]] || die "lane '$lane' does not match active run '$run_id' lane '$run_lane'"

preflight_json="$(node "$role_helper" preflight \
  --run "$run_id" \
  --responsibility "$responsibility" \
  --lane "$lane" \
  --repo-root "$repo_root")"

allowed_kinds_json="$(printf '%s\n' "${allowed_kinds[@]}" | node -e '
  const chunks = [];
  process.stdin.on("data", (chunk) => chunks.push(chunk));
  process.stdin.on("end", () => process.stdout.write(JSON.stringify(chunks.join("").trim().split("\\n").filter(Boolean))));
')"
allowed_transports_json="$(printf '%s\n' "${allowed_transports[@]}" | node -e '
  const chunks = [];
  process.stdin.on("data", (chunk) => chunks.push(chunk));
  process.stdin.on("end", () => process.stdout.write(JSON.stringify(chunks.join("").trim().split("\\n").filter(Boolean))));
')"

node - "$preflight_json" "$allowed_kinds_json" "$allowed_transports_json" "$dispatch_count" <<'NODE'
const [preflightText, kindsText, transportsText, countText] = process.argv.slice(2);
let preflight;
try {
  preflight = JSON.parse(preflightText);
} catch {
  process.stderr.write("df-role-caller: role helper did not return JSON\n");
  process.exit(1);
}
const allowedKinds = new Set(JSON.parse(kindsText));
const allowedTransports = new Set(JSON.parse(transportsText));
const leaves = [];
function collect(target) {
  if (target.kind === "parallel") {
    for (const child of target.targets) collect(child);
    return;
  }
  leaves.push(target);
}
collect(preflight.target);
if (leaves.length !== Number(countText)) {
  process.stderr.write(`df-role-caller: resolved target has ${leaves.length} native dispatch leaf/leaves, but caller declared ${countText}\n`);
  process.exit(1);
}
for (const target of leaves) {
  if (!allowedKinds.has(target.kind)) {
    process.stderr.write(`df-role-caller: target kind '${target.kind}' is unsupported by this caller\n`);
    process.exit(1);
  }
  if (target.kind === "transport" && !allowedTransports.has(target.name)) {
    process.stderr.write(`df-role-caller: transport '${target.name}' is unsupported by this caller\n`);
    process.exit(1);
  }
}
NODE

printf 'df-role-caller: resolved %s/%s for %s: %s\n' \
  "$responsibility" "$lane" "$run_id" "$preflight_json" >&2

if [[ "$command_name" == preflight ]]; then
  printf '%s\n' "$preflight_json"
  exit 0
fi

seqs=()
for ((index = 0; index < dispatch_count; index += 1)); do
  reserve_args=(reserve "$run_id" "$responsibility" "$purpose")
  if [[ -n "$parent_seq" ]]; then reserve_args+=("$parent_seq"); fi
  seqs+=("$(cd "$repo_root" && bash "$state_helper" "${reserve_args[@]}")")
done

node - "$preflight_json" "${seqs[@]}" <<'NODE'
const [preflightText, ...seqs] = process.argv.slice(2);
process.stdout.write(`${JSON.stringify({ preflight: JSON.parse(preflightText), seqs })}\n`);
NODE
