---
name: drk-05-dev-verify
description: "Developer self-verification before code review: runs all tests and QA runbook inline, logs failures, fixes them in a loop, then chains to drk-06-code-review. Use after implementation is complete and before submitting for multi-model code review."
---

# Developer Self-Verification

Run all tests and the QA acceptance runbook against your implementation before
submitting for code review. Mirrors a developer testing their own work before
opening a PR. Logs failures, fixes them inline with verification, and chains
to drk-06-code-review when everything passes.

## Prerequisites

- Feature branch checked out with implementation nominally complete
- PRD (`docs/prd-<feature>.md`) and QA runbook (`docs/qa/qa-<feature>.md`) exist
- agent-browser available (`agent-browser --version`)
- Application running and accessible at the QA runbook's `base_url`

## Workflow

### Step 1: Resolve Inputs

**Derive feature slug from branch name:**
Strip common prefixes (`feat/`, `feature/`, `fix/`, `chore/`). Use the
remainder as the slug (e.g., `feat/user-auth` → `user-auth`).

**Locate QA runbook:**
1. Scan `docs/qa/` for `qa-<slug>.md`
2. If no exact match: list candidate files and ask the user to confirm
3. If no candidates found at all: warn the user ("No QA runbook found in
   `docs/qa/` for slug `<slug>` — skipping QA phase") and skip Step 3

**Discover test runner** by checking in order:
1. `package.json` scripts: `test`, `test:unit`, `test:integration`, `test:e2e`
2. `Makefile` targets: `test`, `test-unit`, `test-integration`, `test-e2e`
3. `pytest.ini`, `pyproject.toml`, or `setup.cfg` in the repo root (Python)
4. If multiple runners found, record all of them — run each one
5. If none found: warn the user and skip the test phase (do not block)

**Initialize issues doc:**

```bash
mkdir -p .claude/tmp
```

Create `.claude/tmp/dev-verify-issues.md`:

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
- Append to `## Test Failures` in `.claude/tmp/dev-verify-issues.md`
- Format: `- [ ] \`<suite> > <test name>\` — <failure message> — \`<file:line>\``

Continue running all suites even after failures — collect everything before
moving on.

### Step 3: Run QA Runbook Inline

**Parse the QA runbook:**
Read the runbook file. Extract:
- YAML frontmatter: `base_url`, `timeout` (default 30000 if missing),
  `startup_command` (optional — used if app is unreachable)
- All test cases sorted by priority: P0 first, then P1, then P2

**Safety guard:** Check `base_url` against the allowed-host list
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
   a. `startup_command` from runbook frontmatter (if set)
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
      found in runbook or repo. Start the app and re-run drk-05-dev-verify`
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
   '<startup_command>' — investigate and re-run drk-05-dev-verify`

**Execute each test case** using the same execution rules as drk-07-qa-acceptance:
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
- Append to `## QA Failures` in `.claude/tmp/dev-verify-issues.md`
- Format: `- [ ] TC-<id>: <name> — Step <N> failed — expected <X>, got <Y>`

**Browser session loss during execution:** If any `agent-browser` command
returns a hard error (e.g., the browser process is no longer reachable,
not a step assertion failure), check the session:
`agent-browser get url`. If the check fails, run `agent-browser close`
(may fail), then attempt `agent-browser open <base_url>` once to restart.
If restart fails, mark all remaining TCs as
`- [ ] TC-<id>: <name> — NOT RUN: browser session lost after TC-<prev-id>`
in `## QA Failures` and proceed to Step 4.

**Always close the browser when done** (success, failure, or interruption):

```bash
agent-browser close
```

### Step 4: Fix Loop

If `.claude/tmp/dev-verify-issues.md` has no unchecked items (`- [ ]`) in
`## Test Failures` or `## QA Failures`, skip directly to Step 5.

For each unchecked item, work through failures one at a time:

Prioritise in this order: P0 QA failures first, then P1/P2 QA failures,
then test failures.

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

**Convergence check after all items addressed:**
Run the full test suite and the full QA runbook (Steps 2 and 3). If new
failures appear (regressions introduced by fixes), add them to the issues doc
and re-enter the fix loop for those new items only.

**E2e test coverage gate (hard requirement):**

After the convergence check passes, verify that automated e2e tests exist
for every TC-xxx in the QA runbook. This is a hard gate — the branch cannot
proceed to Step 5 without e2e coverage.

1. **Parse TC identifiers** from the QA runbook: collect all TC-xxx IDs
2. **Discover e2e test location** from project conventions:
   - Check for `e2e/`, `tests/e2e/`, `test/e2e/`, or `__tests__/e2e/` directories
   - Check `playwright.config.ts`, `cypress.config.js`, or similar config files
     to find the test directory
   - Check `package.json` for `test:e2e` script to infer framework and location
3. **Scan e2e test files** for TC identifiers: search test names, descriptions,
   and comments for `TC-xxx` patterns (e.g., `TC-001`, `TC-002`)
4. **Compare**: for each TC-xxx in the runbook, confirm a matching reference
   exists in the e2e tests
5. **If any TC-xxx is missing e2e coverage**:
   - Append to `## Test Failures` in `.claude/tmp/dev-verify-issues.md`:
     `- [ ] [COVERAGE] TC-<id>: <name> — no automated e2e test found`
   - Re-enter the fix loop to write the missing e2e tests
   - After writing tests, re-run the e2e suite to confirm they pass
   - Re-check coverage (repeat from step 1 of this gate)

### Step 5: Check for Unresolved Items

Scan `.claude/tmp/dev-verify-issues.md` for items marked `[!]`.

If any `[!]` items exist:
- Present them to the user with failure details
- Ask: proceed to drk-06-code-review anyway, or stop to investigate?
- Treat any affirmative response as proceed; any other response as stop

If no `[!]` items: proceed silently.

### Step 6: Chain to drk-06-code-review

Trigger `drk-06-code-review`.

## Notes

- The issues doc at `.claude/tmp/dev-verify-issues.md` is a working scratch
  file — it is not committed
- Run QA inline (not by chaining to drk-07-qa-acceptance) to keep the fix loop
  in a single context with all failures visible
- `agent-browser close` must run at every exit point — after Step 3 success,
  after app-not-running bail-out, and after any unexpected error
- This skill verifies the developer's own work before review, not after. The
  multi-model code review in drk-06-code-review is a second opinion on
  already-verified work.
- **Safety guard**: only run QA against local/dev/test hosts (`localhost`,
  `127.0.0.1`, `::1`, `.local`, `.test`, `.dev`). If `base_url` looks
  production-like, stop and ask for a non-production URL.
