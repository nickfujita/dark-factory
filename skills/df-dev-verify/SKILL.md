---
name: df-dev-verify
description: "Verify completed implementation through project-owned tests and medium-specific recipes, then return evidence-backed code-review readiness. Runs at the feature playbook's verification stage or when explicitly invoked."
disable-model-invocation: true
---

# Developer self-verification

Verify the completed implementation before code review. Tests and committed
user-path recipes are complementary. This stage owns execution results and a
bounded product-fix loop, not recipe authoring or application lifecycle commands.

## Inputs and readiness

- Implementation is nominally complete on a feature branch.
- Read the approved PRD and the coverage handoff from `df-verify-coverage`.
  Use its slug, media, recipe paths, sub-features, and programmatic proof plan.
- If the handoff is unavailable, reconstruct it through `df-verify-coverage`
  before driving. Do not guess entries from a branch name.
- For a user-facing graphical UI change,
  `<run-dir>/work/prototype/approved-ui-prototype.md` must exist.
- Read the project verification skill and named recipes for each medium.
  Only that medium's declared tools are prerequisites. A CLI, TUI, MCP, API,
  or internal-only change does not require a browser.
- Read `../../references/engineering-standards.md` from this skill's directory.
  Resolve the approved automated test scope and its prerequisites before running.

Create `<run-dir>/work/dev-verify-issues.md` in external run state, where
`<run-dir>` is `bash scripts/df-state.sh path "<run-id>"`. Record the source
revision, coverage input, required checks, evidence paths, and outstanding items.
Each check has one status: NOT RUN, BLOCKED, FAIL, or PASS. A required check
starts NOT RUN. Neither a warning nor an empty failure list makes it PASS.

A blocked coverage verdict stops this stage. A missing required recipe,
unproven base skill, missing test runner, or unavailable prerequisite is BLOCKED.
Do not skip the obligation or announce verification complete. An empty recipe
list is valid only with `Media: none` and its recorded programmatic proof plan.
A planned recipe is executable here once implemented, but its planning status
is not evidence that it passed.

## 1. Check the automated coverage plan

This gate runs on every path, including when all existing tests already pass.

For each changed user-facing entry and sub-feature, locate its automated E2E
case. Read the setup, actions, and assertions. The case must exercise the
specified behavior through the appropriate public interface and fail when that
behavior is wrong. An ID in a name, comment, or skipped test is only a locator,
not coverage. One executable test may cover several obligations if each has a
meaningful assertion.

For internal-only requirements, inspect the planned unit, integration, or
protocol tests instead. Do not invent a browser recipe or require a UI E2E test
for a change with no user-facing medium.

Record each obligation's test path, case name, assertion, and eventual run
result. Missing coverage is unresolved even when all existing suites are green.
Add missing tests within the approved implementation scope. If that needs a new
framework, infrastructure, or authority, stop with the named gap.
Carry explicit operator-approved exemptions with their reasons. Do not invent
an exemption or treat a planning `UNTESTABLE` label as permission to ship.

## 2. Run the required automated checks

Use the project's documented review-ready commands and the approved plan.
Inspect package scripts, Makefiles, and language-specific runners if needed.
Resolve aliases and aggregate scripts so the same suite is not run twice under
different names. Read prerequisites first and verify the required services.

Run the complete required review-ready test scope once implementation is
complete, not after each small commit. Collect independent failures without
continuing destructive checks against an unhealthy or shared target. Record
commands, actual exit results, selected source revision, and skipped cases.
A missing service is an environment blocker, not a product test failure.
An unavailable runner or skipped required case leaves its obligation BLOCKED.

## 3. Drive the committed recipes

The project skill's Launch, Doctor, Drive, Evidence, and Cleanup sections own
all mechanics. Do not replace them with browser boilerplate, auto-discovered
startup commands, arbitrary sleeps, alternate flags, or internal state changes.
Honor named sessions and process ownership. Never close a default shared session.

Before any mutation, verify the exact target, build, fixture ownership, and
non-production authorization through the project contract. A hostname suffix
does not prove safety. An explicitly authorized disposable remote environment
is valid when its identity and ownership can be checked. A production or
unidentified target stops the drive. Missing managed credentials do not authorize
a substitute credential.

For each named medium and entry:

1. Follow its documented launch or attachment procedure and readiness signal.
2. Run Doctor before driving, on each fresh short-lived session, and after an
   unexpected failure. Do not restart an adopted instance without owner approval.
3. Drive each in-scope sub-feature and user entry point. Use the medium's actual
   interaction contract, including its waits, retry safety, and assertions.
   Browser recipes require browser interaction; terminal recipes require the
   terminal; MCP recipes require the MCP transport. Supporting HTTP or database
   observations never substitute for the required user path.
4. Capture the action and resulting state, including required side effects,
   with the source revision and entry identifier. PASS requires every named
   observable result. A product mismatch is FAIL. Missing prerequisites or a
   lost driver are BLOCKED. Neither is a partial PASS.
5. On failure, preserve evidence and stop dependent actions. Follow the
   project's recovery policy before another independent entry. Never blindly
   retry a mutation with unknown outcome.
6. Always run the project's Cleanup for owned resources on success, failure,
   or interruption. Preserve adopted instances and prove evidence survives.
   Cleanup failure remains unresolved.

A broken Launch or inaccurate recipe is skill drift. Report it to
`maintain-verification-skill` for implemented behavior; do not patch around it
inside this stage or change expected behavior to match a product bug. Re-run
affected checks after a reviewed repair. This stage may fix product code and
tests within the approved task, but it does not own verification-skill edits.

**Compare an approved visual prototype.** For graphical UI work, read the
approved prototype record and drive every material requirement-backed state at
its recorded viewports. Retain fresh screenshots and compare hierarchy, copy,
density, responsive behavior, and interactions. Pixel equality is required only
when the approval record says so. An unexplained difference is a QA failure.
Do not redefine the approved design during verification.

## 4. Fix and recheck

Address failures within the authorized implementation scope. Prioritize safety
and user-path defects. Re-run the specific failing test or recipe after each
fix, not the full suite after every edit.

A fix is proven only by running a meaningful check that would fail if the fix
were wrong. A code citation, a plausible explanation, or an exit-zero no-op is
not proof. Keep its evidence with the item. After three unsuccessful attempts
on one item, stop that item and report it unresolved.

After the repair batch, re-run the required checks invalidated by the changes,
including affected adjacent behavior. A shared change that invalidates the full
scope requires that full scope again. Preserve evidence for genuinely unaffected
checks with its revision and an explicit applicability assessment.

At most two repair-and-recheck rounds are allowed. New failures after the second
round, a missing prerequisite, or a need for broader authority stops progression.
Do not lower an assertion, drop a recipe, or start a third round to reach green.

## 5. Final gate and handoff

Always revisit the automated coverage obligations from step 1 after fixes.
Coverage needs both inspected assertions and passing execution evidence.
Reconcile every required automated check, user-path leg, visual comparison,
and cleanup obligation against the final source revision.

Return exactly one result:

- **code-review-ready.** Every required obligation has valid PASS evidence and
  no open failures, blockers, or unrun checks remain.
- **code-review-ready with approved exemptions.** All non-exempt obligations
  pass, and each exception was explicitly approved with the exact missing
  evidence and risk stated. This is not a full verification PASS.
- **not ready.** Any required obligation is FAIL, BLOCKED, NOT RUN, missing
  evidence, or invalidated by later changes. Name the remaining work and stop.

Do not use an empty issues list, a lack of `[!]` markers, or a missing recipe
as a success condition. No silent handoff follows a not-ready result.
Approval to investigate or continue implementation is not a waiver of a gate.

Report the PRD, source revision, recipes driven, automated commands and results,
evidence location, exemptions, and remaining work. The feature playbook owns the
next invocation of `df-code-review`. Standalone, name that next stage and stop.
