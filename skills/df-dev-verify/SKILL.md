---
name: df-dev-verify
description: "Developer self-verification before code review: runs all tests and drives the feature's committed verification recipes inline, logs failures, fixes them in a loop, then chains to df-code-review. Runs when the df feature playbook reaches its dev-verify stage or when the operator invokes it explicitly — never on its own."
disable-model-invocation: true
---

# Developer Self-Verification

Run all tests and drive the feature's committed verification recipes against your implementation before
submitting for code review. Mirrors a developer testing their own work before
opening a PR. Logs failures, fixes them inline with verification, and chains
to df-code-review when everything passes.

## Prerequisites

- Feature branch checked out with implementation nominally complete
- PRD (`docs/prd-<feature>.md`) exists, and the coverage handoff from `df-verify-coverage` names the feature-map entries this change touches
- For a user-facing graphical UI change, `<run-dir>/work/prototype/approved-ui-prototype.md` exists
- agent-browser available (`agent-browser --version`)
- Application launchable through the project's verification skill for each medium touched

## Workflow

### Step 1: Resolve Inputs

**Derive feature slug from branch name:**
Strip common prefixes (`feat/`, `feature/`, `fix/`, `chore/`). Use the
remainder as the slug (e.g., `feat/user-auth` → `user-auth`).

**Locate the verification recipes:**
1. Take the entry list from the coverage handoff. That is the authoritative set.
2. No handoff in session: find the project's verification skill for each medium
   the change touches and read the `features/` entries covering it.
3. Nothing found at all: warn the user ("No verification recipes found for
   slug `<slug>`, skipping the drive phase") and skip Step 3. Say it in the
   report. A skipped drive is not a pass.

**Discover test runner** by checking in order:
1. `package.json` scripts: `test`, `test:unit`, `test:integration`, `test:e2e`
2. `Makefile` targets: `test`, `test-unit`, `test-integration`, `test-e2e`
3. `pytest.ini`, `pyproject.toml`, or `setup.cfg` in the repo root (Python)
4. If multiple runners found, record all of them — run each one
5. If none found: warn the user and skip the test phase (do not block)

**Initialize issues doc:**

```bash
run_dir="$(bash scripts/df-state.sh path "<run-id>")"
mkdir -p "$run_dir/work"
```

Create `<run-dir>/work/dev-verify-issues.md`, where `<run-dir>` is
`bash scripts/df-state.sh path "<run-id>"`. It lives in the agent's own store,
not in the repo being verified:

```markdown
# Dev Verify Issues: <feature>
**Date:** <YYYY-MM-DD>
**Branch:** <branch>

## Test Failures

## QA Failures

## Resolved
```

### Step 2: Run All Tests

For each discovered test runner, execute the full suite. For each failure:
- Append to `## Test Failures` in `<run-dir>/work/dev-verify-issues.md`
- Format: `- [ ] \`<suite> > <test name>\` — <failure message> — \`<file:line>\``

Continue running all suites even after failures — collect everything before
moving on.

### Step 3: Drive the verification recipes inline

**Read the recipes:**
For each medium the change touches, read the project's verification skill and
the `features/` entries from Step 1. The skill's Launch, Doctor, Drive,
Evidence, and Cleanup sections own the mechanics. Do not restate or improvise
around them; a Launch that does not work is drift to report, not to patch here.

**Safety guard:** Check the launch target against the allowed-host list
(`localhost`, `127.0.0.1`, `::1`, `.local`, `.test`, `.dev`). If
`base_url` looks production-like, stop immediately —
ask the user for a non-production URL before continuing.

**Verify app is running:**

```bash
agent-browser open <base_url>
agent-browser wait --load networkidle --timeout <timeout>
agent-browser snapshot -i
```

If the snapshot shows an error page or the app is unreachable:
1. Run `agent-browser close`
2. Resolve startup command — in priority order:
   a. the Launch command from the project's verification skill
   b. Auto-discover from repo:
      - Read `package.json` (if it exists): check `scripts` for keys
        `dev:all`, `dev`, `start`, `serve`, `preview` — use first match
        as `npm run <key>` (or `pnpm run <key>` / `yarn <key>` based on
        lockfile: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, else npm)
      - If no match in `package.json`, read `Makefile` (if it exists):
        check for targets `dev`, `run`, `serve`, `start` — use first match
        as `make <target>`
   c. If no command found: log warning and skip to Step 4:
      `- [ ] [APP NOT RUNNING] Cannot reach <base_url> — no startup command
      found in the verification skill or repo. Start the app and re-run df-dev-verify`
3. Run the resolved command in the background:
   ```bash
   <startup_command> &
   ```
4. Wait 15 seconds, then retry the health check:
   ```bash
   agent-browser open <base_url>
   agent-browser wait --load networkidle --timeout <timeout>
   agent-browser snapshot -i
   ```
5. If now reachable: continue with test case execution.
6. If still unreachable: log warning and skip to Step 4:
   `- [ ] [APP NOT RUNNING] Cannot reach <base_url> after running
   '<startup_command>' — investigate and re-run df-dev-verify`

**Drive each entry** using the same execution rules as df-acceptance:
- Navigate to starting page, execute each step, run assertions
- Use `agent-browser snapshot -i` for interactive elements; `agent-browser snapshot`
  (no `-i`) for non-interactive assertions
- Wait with `agent-browser wait --load networkidle --timeout <timeout>` after
  every navigation or interaction; fall back to `agent-browser wait 2000` if
  networkidle times out (log a warning)
- Re-snapshot after every interaction that changes the page
- On step failure within a TC: mark the TC FAIL, skip remaining steps in that TC,
  continue to next TC
- Single retry for interaction failures (`click`/`fill`/`select`): wait 2s,
  re-snapshot, retry once. Never retry assertion failures.

For each TC failure:
- Append to `## QA Failures` in `<run-dir>/work/dev-verify-issues.md`
- Format: `- [ ] TC-<id>: <name> — Step <N> failed — expected <X>, got <Y>`

**Browser session loss during execution:** If any `agent-browser` command
returns a hard error (e.g., the browser process is no longer reachable,
not a step assertion failure), check the session:
`agent-browser get url`. If the check fails, run `agent-browser close`
(may fail), then attempt `agent-browser open <base_url>` once to restart.
If restart fails, mark all remaining TCs as
`- [ ] TC-<id>: <name> — NOT RUN: browser session lost after TC-<prev-id>`
in `## QA Failures` and proceed to Step 4.

**Compare an approved visual prototype.** If `<run-dir>/work/prototype/approved-ui-prototype.md` exists, read it before closing the browser. Drive the implementation through every material state named in the record at each tested viewport. Capture fresh implementation screenshots beside the dev-verification evidence. Compare hierarchy, copy, density, responsive behavior, and interactions against the approved prototype. Pixel equality is required only when the approval record says so. An unexplained difference is a QA failure. Record it in `## QA Failures`; do not redefine the approved design during verification.

**Always close the browser when done** (success, failure, or interruption):

```bash
agent-browser close
```

### Step 4: Fix Loop

If `<run-dir>/work/dev-verify-issues.md` has no unchecked items (`- [ ]`) in
`## Test Failures` or `## QA Failures`, skip directly to Step 5.

For each unchecked item, work through failures one at a time:

Prioritise in this order: P0 QA failures first, then P1/P2 QA failures,
then test failures.

**The evidence standard for every fix claim.** This skill exists to produce
evidence, so a claim that a fix works is only as good as the rung it reached on
the `blast-radius` proof ladder (`skills/blast-radius/SKILL.md` § "How sure are
you"):

| Rung | What it is | Counts as proven? |
|---|---|---|
| 1 | You said so | No |
| 2 | You pointed at the line — a real `file:line`, or the library's own source | No |
| 3 | You showed the bad case cannot happen — you walked the failure step by step and it does not reach | No |
| 4 | **You ran it** — a test or script that calls the real code and fails loud if you are wrong | **Yes** |
| 5 | You reproduced it in the running app | Yes, and better |

**Below rung 4 is unproven.** Mark it `[!]` and say so; do not round it up to
resolved. Rung 4 is usually one small script or one focused test invocation
against the exact code you changed, and this skill already has the runners to
get there. Move an item to `## Resolved` only when you have run something that
would have failed had the fix been wrong, and record what you ran alongside the
one-line description.

The same standard applies to a fix's blast radius, not only to the failure it
targeted. A fix that resolves its own item and breaks something adjacent has
not been proven; the convergence check below is what catches that, and its cap
is why the check has to be honest.

**a. Apply fix**
Read the failure details and locate the relevant code. Apply the minimal fix
needed. Do not fix multiple unrelated failures in a single edit.

**b. Re-run the specific failing check**
- For a test failure: run only the specific test (not the full suite)
  e.g., `npm test -- --testNamePattern "failing test name"` or
  `pytest tests/path/test.py::test_name -v`
- For a QA TC failure: open agent-browser, navigate to the relevant page,
  re-execute only that TC's steps and assertions, then close browser

**c. Mark result**
- If passes: move item from its section to `## Resolved` with `[x]` and one-line
  description of the fix
  e.g., `- [x] \`suite > test\` — fixed: added null check in getUserById`
- If still fails after 3 attempts: mark with `[!]` in place
  e.g., `- [!] TC-003: checkout flow — 3 attempts, not converging`
  Do not loop further on that item.

**Convergence check after all items addressed (max 2 iterations):**
Run the full test suite and drive every recipe again (Steps 2 and 3). If new
failures appear (regressions introduced by fixes), add them to the issues doc
and re-enter the fix loop for those new items only.

**This loop runs at most twice.** Iteration 1 is the check after the first fix
pass; iteration 2 is the check after fixing whatever iteration 1 surfaced. If
iteration 2 still surfaces new failures, **stop and surface to the operator**
with the evidence: the failures, what each fix changed, and which rung of the
proof ladder each claim reached. Do not start a third iteration.

A third iteration is not a longer path to green; it is the signal that fixes
are producing regressions faster than they resolve failures, and that is a
question about the change, not a question about the loop. Mark the outstanding
items `[!]`, record `convergence cap reached` next to them, and go to Step 5.

**E2e test coverage gate (hard requirement, max 2 iterations):**

After the convergence check passes, verify that automated e2e tests exist for
every feature-map entry and sub-feature the change touches. This is a hard
gate; the branch cannot proceed to Step 5 without e2e coverage.

A verification skill does not satisfy this gate and never will. The two layers
prove different things: an automated e2e test is deterministic, runs in CI with
no agent, and catches the regression later. Driving a recipe proves this change
works now. The standard requires both, per `references/engineering-standards.md`.

1. **Collect entry ids** from the coverage handoff or the `features/` map
2. **Discover e2e test location** from project conventions:
   - Check for `e2e/`, `tests/e2e/`, `test/e2e/`, or `__tests__/e2e/` directories
   - Check `playwright.config.ts`, `cypress.config.js`, or similar config files
     to find the test directory
   - Check `package.json` for `test:e2e` script to infer framework and location
3. **Scan e2e test files** for TC identifiers: search test names, descriptions,
   and comments for the entry ids (e.g., `login-flow`, `login-flow: sso`)
4. **Compare**: for each entry id, confirm a matching reference
   exists in the e2e tests
5. **If any entry id is missing e2e coverage**:
   - Append to `## Test Failures` in `<run-dir>/work/dev-verify-issues.md`:
     `- [ ] [COVERAGE] TC-<id>: <name> — no automated e2e test found`
   - Re-enter the fix loop to write the missing e2e tests
   - After writing tests, re-run the e2e suite to confirm they pass — writing a
     test is rung 2, running it is rung 4, and only rung 4 closes a coverage item
   - Re-check coverage (repeat from step 1 of this gate)

**This gate runs at most twice.** Iteration 1 is the first coverage scan;
iteration 2 is the re-check after writing the missing tests. If iteration 2
still finds an uncovered TC, **stop and surface to the operator**: list every
TC still without a running e2e test, say what was written and what it did when
run, and let them decide. Do not start a third iteration, and do not delete or
weaken a TC to close the gap. An uncovered TC is a real hole in the acceptance
evidence, and the operator is the one who gets to accept it.

### Step 5: Check for Unresolved Items

Scan `<run-dir>/work/dev-verify-issues.md` for items marked `[!]`.

Items hitting either outer cap — `convergence cap reached`, or a TC still
uncovered after the coverage gate's second iteration — are `[!]` items too.
A cap is a stop that surfaces, never a silent pass.

If any `[!]` items exist:
- Present them to the user with failure details
- Ask: proceed to df-code-review anyway, or stop to investigate?
- Treat any affirmative response as proceed; any other response as stop

If no `[!]` items: proceed silently.

### Step 6: Chain to df-code-review

Trigger `df-code-review`.

## Notes

- The issues doc at `<run-dir>/work/dev-verify-issues.md` is a working scratch
  file — it is not committed
- Drive the recipes inline (not by chaining to df-acceptance) to keep the fix loop
  in a single context with all failures visible
- `agent-browser close` must run at every exit point — after Step 3 success,
  after app-not-running bail-out, and after any unexpected error
- **Evidence, not assertion.** Every fix claim is scored against the
  `blast-radius` proof ladder (`skills/blast-radius/SKILL.md`). Below "you ran
  it" is unproven, and unproven items stay `[!]` rather than moving to
  `## Resolved`.
- **Both outer loops are capped at 2.** The convergence re-run and the e2e
  coverage gate each get two iterations. Hitting a cap surfaces to the operator
  with the evidence; it never loops a third time and never lowers the bar to
  reach green.
- This skill verifies the developer's own work before review, not after. The
  multi-model code review in df-code-review is a second opinion on
  already-verified work.
- **Safety guard**: only run QA against local/dev/test hosts (`localhost`,
  `127.0.0.1`, `::1`, `.local`, `.test`, `.dev`). If `base_url` looks
  production-like, stop and ask for a non-production URL.
