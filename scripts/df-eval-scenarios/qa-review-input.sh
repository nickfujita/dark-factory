#!/usr/bin/env bash
# Deterministic adapter check, not a live model-quality claim.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
exec bash "$root/scripts/test-qa-review-input.sh"
