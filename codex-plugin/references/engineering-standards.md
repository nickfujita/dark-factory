# Engineering Standards

Project-agnostic engineering standards that apply to every feature delivered
through the df artifact spine. These standards are read alongside the PRD and
the feature's verification recipes during design so technical delivery
expectations are planned for from the start.

## E2e Test Requirement

Every feature-map entry and sub-feature describing user-visible behavior
must have a corresponding automated end-to-end test. The mapping is 1:1. If
the map lists eight sub-features for a feature, the e2e suite covers each of
those scenarios.

**This layer is not optional and the verification skill does not replace it.**
The two prove different things. Automated tests are deterministic, run in CI
with no agent involved, and gate every PR. A verification skill is driven by an
agent against the running app and proves the real user path end to end. A
feature needs both. A feature-map entry with no automated test is an untested
feature that happens to be documented, and an automated suite with no
verification recipe is a green build nobody has driven.

**Test identification:** Each e2e test must reference its feature-map entry id
in the test name or description so coverage can be verified by scanning test
files (e.g., `test("login-flow: user can log in", ...)` or
`describe("login-flow - happy path", ...)`).

## CI-Runnable Tests

All e2e tests must be runnable in CI without any LLM or AI agent dependency.
Tests must use deterministic assertions — no flaky checks that depend on
AI-generated content or non-deterministic outputs.

Tests must:
- Run headlessly (no display required)
- Complete within reasonable timeouts (configured per project)
- Produce clear pass/fail output
- Not require manual intervention or approval steps

## Use the Project's Existing Test Framework

Do not introduce a new e2e framework. Discover and use whatever the project
already has:

1. Check `package.json` for test dependencies (Playwright, Cypress, etc.)
2. Check for existing config files (`playwright.config.ts`, `cypress.config.js`, etc.)
3. Check for an existing `e2e/`, `tests/e2e/`, or `test/` directory with e2e tests
4. Follow the project's existing patterns for test file naming, directory
   structure, and assertion style

If no e2e framework exists in the project, flag this during brainstorming so
framework selection becomes an explicit planning task.

## Tests Committed Alongside Feature Code

E2e tests are part of the feature deliverable, not a follow-up task. They
must be:

- Written during implementation (not deferred to a later PR)
- Committed on the same feature branch as the feature code
- Passing before the branch moves to code review (`df-code-review`)

The `df-dev-verify` skill enforces this as a hard gate. The branch cannot
proceed to code review without passing e2e test coverage for every
feature-map entry the change touches.
