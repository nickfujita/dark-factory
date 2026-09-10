#!/usr/bin/env bash
set -euo pipefail

# Resolve a frozen role, verify that the caller can express it, and reserve the
# native dispatch only after those checks succeed. This is the Codex-plugin
# copy of the shared shell caller boundary.

die() { printf 'df-role-caller: %s\n' "$1" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage:
  df-role-caller.sh preflight --run <id> --lane <lane> --repo-root <path> \
      --responsibility <role> [--allow-kind <kind>] [--allow-transport <name>]
  df-role-caller.sh reserve --run <id> --lane <lane> --repo-root <path> \
      --responsibility <role> --purpose <text> [--parent-seq <seq>] \
      [--dispatch-count <n>] [--allow-kind <kind>] [--allow-transport <name>]
USAGE
}

[[ $# -gt 0 ]] || { usage >&2; exit 1; }
command_name=$1
shift
case "$command_name" in preflight|reserve) ;; -h|--help) usage; exit 0 ;; *) die "unknown command '$command_name'" ;; esac

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
    --run) run_id=${2:?--run needs a value}; shift 2 ;;
    --lane) lane=${2:?--lane needs a value}; shift 2 ;;
    --repo-root) repo_root=${2:?--repo-root needs a path}; shift 2 ;;
    --responsibility) responsibility=${2:?--responsibility needs a value}; shift 2 ;;
    --purpose) purpose=${2:?--purpose needs a value}; shift 2 ;;
    --parent-seq) parent_seq=${2:?--parent-seq needs a value}; shift 2 ;;
    --dispatch-count) dispatch_count=${2:?--dispatch-count needs a value}; shift 2 ;;
    --allow-kind) allowed_kinds+=("${2:?--allow-kind needs a value}"); shift 2 ;;
    --allow-transport) allowed_transports+=("${2:?--allow-transport needs a value}"); shift 2 ;;
    *) die "unknown option '$1'" ;;
  esac
done
[[ -n "$run_id$lane$repo_root$responsibility" ]] || die '--run, --lane, --repo-root, and --responsibility are required'
[[ "$dispatch_count" =~ ^[1-9][0-9]*$ ]] || die '--dispatch-count must be a positive integer'
[[ "$command_name" != reserve || -n "$purpose" ]] || die '--purpose is required for reserve'
[[ -z "$parent_seq" || "$parent_seq" =~ ^[1-9][0-9]*$ ]] || die '--parent-seq must be a positive sequence number'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
plugin_root="$(cd "$script_dir/.." && pwd -P)"
role_helper="${DF_ROLE_CALLER_ROLE_HELPER:-$plugin_root/scripts/df-role.mjs}"
state_helper="${DF_ROLE_CALLER_STATE_HELPER:-$plugin_root/scripts/df-state.sh}"
[[ -f "$role_helper" && -f "$state_helper" ]] || die 'plugin role helpers are unavailable'
repo_root="$(cd "$repo_root" && pwd -P)"

run_dir="$(cd "$repo_root" && bash "$state_helper" path "$run_id")"
[[ -f "$run_dir/run.tsv" ]] || die "active run '$run_id' is not available for $repo_root"
run_lane="$(awk -F '\t' 'NR == 2 { print $2 }' "$run_dir/run.tsv")"
[[ "$run_lane" == "$lane" ]] || die "lane '$lane' does not match active run '$run_id' lane '$run_lane'"

preflight_json="$(node "$role_helper" preflight --run "$run_id" --responsibility "$responsibility" --lane "$lane" --repo-root "$repo_root")"
kinds_json="$(printf '%s\n' "${allowed_kinds[@]}" | node -e 'let b="";process.stdin.on("data",c=>b+=c);process.stdin.on("end",()=>process.stdout.write(JSON.stringify(b.trim().split("\\n").filter(Boolean))))')"
transports_json="$(printf '%s\n' "${allowed_transports[@]}" | node -e 'let b="";process.stdin.on("data",c=>b+=c);process.stdin.on("end",()=>process.stdout.write(JSON.stringify(b.trim().split("\\n").filter(Boolean))))')"
node - "$preflight_json" "$kinds_json" "$transports_json" "$dispatch_count" <<'NODE'
const [raw, kindsRaw, transportsRaw, countRaw] = process.argv.slice(2);
let result;
try { result = JSON.parse(raw); } catch { process.stderr.write('df-role-caller: role helper did not return JSON\n'); process.exit(1); }
const kinds = new Set(JSON.parse(kindsRaw));
const transports = new Set(JSON.parse(transportsRaw));
const leaves = [];
const collect = (target) => target.kind === 'parallel' ? target.targets.forEach(collect) : leaves.push(target);
collect(result.target);
if (leaves.length !== Number(countRaw)) { process.stderr.write(`df-role-caller: resolved target has ${leaves.length} native dispatch leaf/leaves, but caller declared ${countRaw}\n`); process.exit(1); }
for (const target of leaves) {
  if (!kinds.has(target.kind)) { process.stderr.write(`df-role-caller: target kind '${target.kind}' is unsupported by this caller\n`); process.exit(1); }
  if (target.kind === 'transport' && !transports.has(target.name)) { process.stderr.write(`df-role-caller: transport '${target.name}' is unsupported by this caller\n`); process.exit(1); }
}
NODE
printf 'df-role-caller: resolved %s/%s for %s: %s\n' "$responsibility" "$lane" "$run_id" "$preflight_json" >&2
if [[ "$command_name" == preflight ]]; then printf '%s\n' "$preflight_json"; exit 0; fi

seqs=()
for ((i = 0; i < dispatch_count; i += 1)); do
  args=(reserve "$run_id" "$responsibility" "$purpose")
  [[ -z "$parent_seq" ]] || args+=("$parent_seq")
  seqs+=("$(cd "$repo_root" && bash "$state_helper" "${args[@]}")")
done
node - "$preflight_json" "${seqs[@]}" <<'NODE'
const [raw, ...seqs] = process.argv.slice(2);
process.stdout.write(`${JSON.stringify({ preflight: JSON.parse(raw), seqs })}\n`);
NODE
