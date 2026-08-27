#!/usr/bin/env bash
# df-eval scenario stub: does the growth stop fire (v2 plan §7).
#
# The real scenario scripts a challenge round whose finding stream keeps
# growing instead of converging, then asserts from the run's store files that
# the loop stops itself rather than dispatching another wave. It needs the
# df-prd-challenge spine economics on this branch: the growth-stop rule wired
# to the df-state store, so the stop is observable as a state flip instead of
# as prose in a reply. Until that lands, this stub reports the gap.

set -u
echo "SKIP: needs the df-prd-challenge spine economics (growth stop not yet wired to the run store)"
exit 0
