#!/usr/bin/env bash
# df-eval scenario: the D23 invocation contract, wrapped so the eval runner
# owns one entry point.
#
# Delegates to the landed scripts/test-df-invocation.sh, which runs three
# clean headless claude sessions and proves ordinary prompts cannot activate
# the df skill while explicit /df invocation can. That harness stays
# authoritative; this wrapper only gates it.
#
# Live-session scenario: it spends real model budget and minutes of wall
# clock. DF_EVAL_SKIP_LIVE=1 skips it so the deterministic suite stays cheap.

set -u

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)

if [ "${DF_EVAL_SKIP_LIVE:-0}" = "1" ]; then
  echo "SKIP: DF_EVAL_SKIP_LIVE=1 (live scenario, three headless claude sessions)"
  exit 0
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: claude CLI not on PATH (live scenario)"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH (the D23 harness needs it)"
  exit 0
fi

exec bash "$REPO_DIR/scripts/test-df-invocation.sh"
