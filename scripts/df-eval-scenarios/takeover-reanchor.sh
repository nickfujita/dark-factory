#!/usr/bin/env bash
# df-eval scenario stub: does a takeover re-anchor scope (v2 plan §7).
#
# The real scenario hands a mid-flight run to a fresh session and asserts
# from the trail that the new session re-anchors on the recorded lane,
# budget, and finish predicate instead of inventing new scope. Graded from
# the takeover session's transcript and the store files: reads of the run
# state and the resume note, reservations drawn from the existing budget,
# and no scope terms absent from the recorded finish predicate. It needs the
# handoff flow as a scriptable surface: a pause-safely trail a harness can
# plant and a session-pickup entry a headless session will walk. Until that
# lands, this stub reports the gap.

set -u
echo "SKIP: needs the handoff flow as a scriptable surface (takeover re-anchoring, pending)"
exit 0
