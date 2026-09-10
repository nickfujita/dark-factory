#!/usr/bin/env bash
# df-eval scenario: frozen-role caller boundary.
#
# Deterministic and offline. The authoritative harness uses synthetic external
# run state and fake worker processes to prove preflight, target validation,
# reservation, and completion ordering for both installed plugin roots. It
# never starts a model CLI.

set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/../.." && pwd)
exec bash "$REPO_DIR/scripts/test-df-role-callers.sh"
