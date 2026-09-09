# Engineering standards

These project-independent standards govern automated evidence for changed
behavior. They complement agent-driven verification recipes.

## Automated coverage of user-facing behavior

Every changed user-facing feature-map entry and sub-feature needs automated
end-to-end coverage through the appropriate public interface. Each behavior
needs an assertion; this does not require one separate test file or test
function per sub-feature. A combined case can cover several obligations.

Automated tests run without an LLM and catch future regressions. Driving the
committed recipe establishes the current user-path result. Neither layer
substitutes for the other.

Use feature-map IDs in names or descriptions to locate tests, then inspect
their setup, actions, and assertions. A matching comment, skipped case, exit-zero
no-op, or assertion of unrelated behavior does not prove coverage. Record the
case path, what it asserts, and its actual passing execution.

## Internal-only behavior

Requirements with no user-facing medium may use unit, integration, or protocol
tests that exercise the actual contract. Do not create a fake UI recipe or
demand browser E2E coverage for internal code. A programmatic-only requirement
is not UNTESTABLE when its meaningful assertions can run.

## Plan and execute at the appropriate time

During planning, name each proof obligation and the test that will assert it.
Planned tests and recipes are not execution evidence. Commit automated tests
with the implementation, not as a later follow-up.

Use the project's existing runners. Review-ready verification runs the complete
required scope once implementation is complete. Resolve wrapper scripts and
aliases so the same suite is not needlessly repeated. During repairs, run the
failed check first, then recheck affected behavior in a bounded batch. Changes
to shared code can require the full scope again.

Read and satisfy documented service prerequisites before running. Tests must
have deterministic assertions, bounded execution, and retained pass/fail output.
A missing service is BLOCKED, not a failed product assertion.

## Readiness

`df-dev-verify` checks coverage before running and again before handoff,
including the path where existing tests pass without repairs. Required coverage
needs both inspected assertions and passing execution evidence.

A missing framework, unrun or skipped required case, failed assertion, or
unavailable environment is not ready. Do not silently weaken the requirement.
An exception needs explicit operator approval naming the missing evidence and
risk. Report readiness with approved exemptions separately from full PASS.

Do not change CI configuration or introduce a new framework without the
authority required by the project. Record framework selection during planning
when none exists.
