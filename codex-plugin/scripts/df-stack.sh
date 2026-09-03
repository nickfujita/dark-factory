#!/usr/bin/env bash
# Register an existing dependent pull request chain as a native GitHub stack.
#
# This helper never creates pull requests, pushes branches, changes PR bases,
# rewrites local history, or merges. It uses only GitHub's REST stack endpoints.
# Exit 2 means native stacks are unavailable and the caller must keep using the
# already-created plain PR chain. Exit 1 means the requested chain is invalid or
# GitHub rejected a mutation after the capability probe succeeded.

set -uo pipefail

API_VERSION=2026-03-10
GH_BIN=${DF_GH_BIN:-gh}

usage() {
  cat <<'USAGE'
Usage:
  df-stack.sh probe --repo OWNER/REPO
  df-stack.sh link --repo OWNER/REPO PR_NUMBER PR_NUMBER [PR_NUMBER ...]

Exit codes:
  0  Native stack support is available, or the chain is linked.
  1  The chain is invalid, or GitHub rejected the stack mutation.
  2  Native stack support is unavailable. Keep the plain PR chain.
USAGE
}

report() {
  printf 'native-stack status=%s reason=%s repo=%s detail=%s\n' \
    "$1" "$2" "${repo:-unknown}" "$3"
}

api() {
  "$GH_BIN" api \
    -H 'Accept: application/vnd.github+json' \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "$@"
}

probe() {
  local output rc

  if ! command -v "$GH_BIN" >/dev/null 2>&1; then
    report fallback cli-unavailable "gh-not-found"
    return 2
  fi
  if ! "$GH_BIN" api --help >/dev/null 2>&1; then
    report fallback cli-unavailable "gh-api-not-supported"
    return 2
  fi

  output=$(api --method GET "repos/$repo/stacks?per_page=1" --silent 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    output=${output//$'\n'/ }
    if [[ "$output" == *"HTTP 404"* ]]; then
      report fallback preview-unavailable "$output"
    elif [[ "$output" == *"HTTP 401"* || "$output" == *"HTTP 403"* ]]; then
      report fallback authentication-unavailable "$output"
    else
      report fallback capability-probe-failed "${output:-stack-endpoint-unavailable}"
    fi
    return 2
  fi

  report available capability-confirmed "rest-api-$API_VERSION"
  return 0
}

pull_request_row() {
  api --method GET "repos/$repo/pulls/$1" \
    --jq '[.number, .state, .head.repo.full_name, .head.ref, .base.repo.full_name, .base.ref] | @tsv'
}

stack_number_for_pr() {
  api --method GET "repos/$repo/stacks?pull_request=$1" \
    --jq 'if length == 0 then "" else (.[0].number | tostring) end'
}

stack_pr_numbers() {
  api --method GET "repos/$repo/stacks/$1" \
    --jq '[.pull_requests[].number] | map(tostring) | join(",")'
}

join_csv() {
  local IFS=,
  printf '%s' "$*"
}

link_chain() {
  local probe_rc default_branch output rc
  local previous_head="" first_stack="" stack_number="" existing_csv requested_csv
  local -a memberships=() remaining=() request_fields=() existing_prs=() requested_prs=("$@")

  probe
  probe_rc=$?
  [[ $probe_rc -eq 0 ]] || return "$probe_rc"

  if [[ $# -lt 2 ]]; then
    report error chain-too-short "at-least-two-prs-required"
    return 1
  fi

  output=$(api --method GET "repos/$repo" --jq '.default_branch' 2>&1)
  rc=$?
  if [[ $rc -ne 0 || -z "$output" ]]; then
    output=${output//$'\n'/ }
    report error repository-read-failed "${output:-default-branch-missing}"
    return 1
  fi
  default_branch=$output

  declare -A seen=()
  local pr row number state head_repo head_ref base_repo base_ref
  for pr in "$@"; do
    if [[ ! "$pr" =~ ^[1-9][0-9]*$ ]]; then
      report error invalid-pr-number "$pr"
      return 1
    fi
    if [[ -n ${seen[$pr]:-} ]]; then
      report error duplicate-pr "$pr"
      return 1
    fi
    seen[$pr]=1

    row=$(pull_request_row "$pr" 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]]; then
      row=${row//$'\n'/ }
      report error pr-read-failed "pr-$pr:${row:-unknown-error}"
      return 1
    fi
    IFS=$'\t' read -r number state head_repo head_ref base_repo base_ref <<<"$row"
    if [[ "$number" != "$pr" || "$state" != open ]]; then
      report error pr-not-open "pr-$pr"
      return 1
    fi
    if [[ "$head_repo" != "$repo" || "$base_repo" != "$repo" ]]; then
      report error cross-repository-chain "pr-$pr"
      return 1
    fi
    if [[ -z "$previous_head" ]]; then
      if [[ "$base_ref" != "$default_branch" ]]; then
        report error wrong-trunk "pr-$pr-base-$base_ref-expected-$default_branch"
        return 1
      fi
    elif [[ "$base_ref" != "$previous_head" ]]; then
      report error chain-invalid "pr-$pr-base-$base_ref-expected-$previous_head"
      return 1
    fi
    previous_head=$head_ref
    stack_number=$(stack_number_for_pr "$pr" 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]]; then
      stack_number=${stack_number//$'\n'/ }
      report error membership-read-failed "pr-$pr:${stack_number:-unknown-error}"
      return 1
    fi
    memberships+=("$stack_number")
  done

  first_stack=${memberships[0]}
  requested_csv=$(join_csv "$@")

  if [[ -z "$first_stack" ]]; then
    for stack_number in "${memberships[@]}"; do
      if [[ -n "$stack_number" ]]; then
        report error mixed-stack-membership "chain=$requested_csv"
        return 1
      fi
    done

    request_fields=()
    for pr in "$@"; do
      request_fields+=(-F "pull_requests[]=$pr")
    done
    output=$(api --method POST "repos/$repo/stacks" "${request_fields[@]}" --jq '.number' 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]]; then
      output=${output//$'\n'/ }
      if [[ "$output" == *"HTTP 404"* ]]; then
        report fallback preview-unavailable "$output"
        return 2
      fi
      report error create-failed "${output:-unknown-error}"
      return 1
    fi
    report linked created "stack-$output-prs-$requested_csv"
    return 0
  fi

  existing_csv=$(stack_pr_numbers "$first_stack" 2>&1)
  rc=$?
  if [[ $rc -ne 0 || -z "$existing_csv" ]]; then
    existing_csv=${existing_csv//$'\n'/ }
    report error stack-read-failed "stack-$first_stack:${existing_csv:-unknown-error}"
    return 1
  fi

  IFS=, read -r -a existing_prs <<<"$existing_csv"
  local existing_start=-1 existing_index requested_index=0
  for existing_index in "${!existing_prs[@]}"; do
    if [[ ${existing_prs[$existing_index]} == "${requested_prs[0]}" ]]; then
      existing_start=$existing_index
      break
    fi
  done
  if (( existing_start < 0 )); then
    report error existing-stack-not-prefix "stack-$first_stack-prs-$existing_csv-requested-$requested_csv"
    return 1
  fi
  for ((existing_index = existing_start; existing_index < ${#existing_prs[@]}; existing_index++)); do
    if (( requested_index >= ${#requested_prs[@]} )) \
      || [[ ${requested_prs[$requested_index]} != "${existing_prs[$existing_index]}" ]]; then
      report error existing-stack-not-prefix "stack-$first_stack-prs-$existing_csv-requested-$requested_csv"
      return 1
    fi
    if [[ ${memberships[$requested_index]} != "$first_stack" ]]; then
      report error mixed-stack-membership "pr-${requested_prs[$requested_index]}"
      return 1
    fi
    requested_index=$((requested_index + 1))
  done

  if (( requested_index == ${#requested_prs[@]} )); then
    report linked already-registered "stack-$first_stack-prs-$requested_csv"
    return 0
  fi

  for ((; requested_index < ${#requested_prs[@]}; requested_index++)); do
    pr=${requested_prs[$requested_index]}
    if [[ -n ${memberships[$requested_index]} ]]; then
      if [[ ${memberships[$requested_index]} != "$first_stack" ]]; then
        report error mixed-stack-membership "pr-$pr"
        return 1
      fi
      report error existing-stack-not-prefix "pr-$pr-already-in-stack-$first_stack"
      return 1
    fi
    remaining+=("$pr")
  done

  request_fields=()
  for pr in "${remaining[@]}"; do
    request_fields+=(-F "pull_requests[]=$pr")
  done
  output=$(api --method POST "repos/$repo/stacks/$first_stack/add" \
    "${request_fields[@]}" --jq '.number' 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    output=${output//$'\n'/ }
    if [[ "$output" == *"HTTP 404"* ]]; then
      report fallback preview-unavailable "$output"
      return 2
    fi
    report error extend-failed "${output:-unknown-error}"
    return 1
  fi
  report linked extended "stack-$output-prs-$requested_csv"
}

command_name=${1:-}
[[ -n "$command_name" ]] || { usage >&2; exit 1; }
shift

repo=""
if [[ ${1:-} == --repo && -n ${2:-} ]]; then
  repo=$2
  shift 2
fi
if [[ ! "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
  usage >&2
  exit 1
fi

case "$command_name" in
  probe)
    [[ $# -eq 0 ]] || { usage >&2; exit 1; }
    probe
    ;;
  link)
    link_chain "$@"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
