# QA Startup Command Auto-Discovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When the app is unreachable during QA, auto-discover and run the startup command from the runbook frontmatter or repo before asking the user.

**Architecture:** Four targeted markdown edits across three skill files and one template. No code compilation. Verification is grep-based confirmation that old text is replaced and new text is present. The startup resolution logic is identical in both qa-acceptance and dev-verify — copy precisely.

**Tech Stack:** Bash (grep, Edit tool), Markdown skill files

---

### Task 1: Add startup_command to runbook template and generation skill

**Files:**
- Modify: `skills/drk-03-qa-runbook-gen/references/runbook-template.md`
- Modify: `skills/drk-03-qa-runbook-gen/SKILL.md`

**Step 1: Read both files to confirm current state**

```bash
grep -n "startup_command\|auth" skills/drk-03-qa-runbook-gen/references/runbook-template.md
grep -n "startup_command\|auth\|base_url" skills/drk-03-qa-runbook-gen/SKILL.md | head -20
```

**Step 2: Update runbook-template.md — add startup_command to the YAML frontmatter block**

In `skills/drk-03-qa-runbook-gen/references/runbook-template.md`, find the frontmatter block:

```yaml
---
id: qa-<feature-slug>
prd: docs/prd-<feature-slug>.md
base_url: http://localhost:3000
generated: YYYY-MM-DD
timeout: 30000
# auth:
#   method: form
#   notes: "Login at /login with test credentials"
---
```

Replace with:

```yaml
---
id: qa-<feature-slug>
prd: docs/prd-<feature-slug>.md
base_url: http://localhost:3000
generated: YYYY-MM-DD
timeout: 30000
# startup_command: pnpm dev:all
# auth:
#   method: form
#   notes: "Login at /login with test credentials"
---
```

Also add a description line for `startup_command` in the field-by-field notes below the block. Find:

```
- `auth`: (optional) authentication hint — use block mapping style
```

Replace with:

```
- `startup_command`: (optional) shell command to start the app before testing.
  If omitted, skills auto-discover from `package.json` scripts or `Makefile`.
- `auth`: (optional) authentication hint — use block mapping style
```

**Step 3: Update drk-03-qa-runbook-gen/SKILL.md — add startup_command to Step 3**

In `skills/drk-03-qa-runbook-gen/SKILL.md`, find the `auth` rule block in Step 3:

```
`auth` rule — use block mapping style (not flow mapping) to avoid YAML
escaping issues:
```

Insert before it:

```
`startup_command` rule:
- If the PRD or project docs mention a command to start the dev server
  (e.g., `pnpm dev:all`, `npm run dev`, `make run`), populate this field.
- If no startup command is mentioned, omit the field — skills will
  auto-discover it from the repo.

```

**Step 4: Verify**

```bash
grep -n "startup_command" \
  skills/drk-03-qa-runbook-gen/references/runbook-template.md \
  skills/drk-03-qa-runbook-gen/SKILL.md
```

Expected: at least 2 matches in the template file (comment + description), at least 2 in the SKILL.md (step 3 frontmatter list + startup_command rule).

**Step 5: Commit**

```bash
git add skills/drk-03-qa-runbook-gen/
git commit -m "feat: add startup_command field to QA runbook template and generation skill"
```

---

### Task 2: Update drk-07-qa-acceptance — startup auto-discovery on app-not-running

**Files:**
- Modify: `skills/drk-07-qa-acceptance/SKILL.md`

**Step 1: Read the current app-not-running block to confirm exact text**

```bash
grep -n "not reachable\|agent-browser close\|running correctly\|startup" \
  skills/drk-07-qa-acceptance/SKILL.md
```

**Step 2: Update the frontmatter parse step to extract startup_command**

In `skills/drk-07-qa-acceptance/SKILL.md`, find the Step 1 section that says:

```
Resolve `base_url`:
```

Just before it (in the Parse step), find the line that lists extracted frontmatter fields. Look for where `timeout` is mentioned as extracted from frontmatter. It will be near:

```
Resolve `timeout`:
```

After the `timeout` resolve block, add:

```
Resolve `startup_command`:
- Read the `startup_command` frontmatter field if present
- Store it for use in Step 2's app-not-running path
```

**Step 3: Replace the app-not-running block**

Find this exact block:

```
If the app is not reachable or returns an error page:
1. Run `agent-browser close` to clean up
2. Stop and report: "Cannot reach `<base-url>`. The page shows: `<brief
   description>`. Is the application running correctly?"
```

Replace with:

```
If the app is not reachable or returns an error page:
1. Run `agent-browser close` to clean up
2. Resolve startup command — in priority order:
   a. `startup_command` from runbook frontmatter (if set)
   b. Auto-discover from repo:
      - Read `package.json` (if it exists): check `scripts` for keys
        `dev:all`, `dev`, `start`, `serve`, `preview` — use first match
        as `npm run <key>` (or `pnpm run <key>` / `yarn <key>` based on
        lockfile present: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn,
        otherwise npm)
      - If no match in `package.json`, read `Makefile` (if it exists):
        check for targets `dev`, `run`, `serve`, `start` — use first match
        as `make <target>`
   c. If no command found: stop and report "Cannot reach `<base-url>`.
      No startup command found in runbook or repo. Is the application
      running correctly?"
3. Run the resolved command in the background:
   ```bash
   <startup_command> &
   ```
4. Wait 15 seconds, then retry the health check:
   ```bash
   agent-browser open <base-url>
   agent-browser wait --load networkidle --timeout <timeout>
   agent-browser snapshot -i
   ```
5. Re-verify the snapshot (same checks as above — blank page or error indicators).
6. If now reachable: continue to the overlay-handling step.
7. If still unreachable: stop and report "Cannot reach `<base-url>` after
   running `<startup_command>`. The page shows: `<brief description>`.
   Is the application running correctly?"
```

**Step 4: Verify**

```bash
grep -n "startup_command\|auto-discover\|pnpm-lock\|15 second" \
  skills/drk-07-qa-acceptance/SKILL.md
```

Expected: multiple matches confirming the new block is present.

```bash
grep -n "running correctly" skills/drk-07-qa-acceptance/SKILL.md
```

Expected: only one match — the fallback report after the 15s retry fails. The original two-line block (immediate stop) should be gone.

**Step 5: Commit**

```bash
git add skills/drk-07-qa-acceptance/SKILL.md
git commit -m "feat: auto-discover and run startup command in drk-07-qa-acceptance"
```

---

### Task 3: Update drk-05-dev-verify — same startup auto-discovery

**Files:**
- Modify: `skills/drk-05-dev-verify/SKILL.md`

**Step 1: Read the current app-not-running block**

```bash
grep -n "APP NOT RUNNING\|agent-browser close\|startup_command\|unreachable" \
  skills/drk-05-dev-verify/SKILL.md
```

**Step 2: Update the Parse step to extract startup_command**

In Step 3's "Parse the QA runbook" block, find:

```
- YAML frontmatter: `base_url`, `timeout` (default 30000 if missing)
```

Replace with:

```
- YAML frontmatter: `base_url`, `timeout` (default 30000 if missing),
  `startup_command` (optional — used if app is unreachable)
```

**Step 3: Replace the app-not-running block**

Find this exact block:

```
If the snapshot shows an error page or the app is unreachable:
1. Run `agent-browser close`
2. Log a warning to `.claude/tmp/dev-verify-issues.md` under `## QA Failures`:
   `- [ ] [APP NOT RUNNING] Cannot reach <base_url> — start the app and re-run drk-05-dev-verify`
3. Skip remaining QA steps and proceed to Step 4
```

Replace with:

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
```

**Step 4: Verify**

```bash
grep -n "startup_command\|auto-discover\|pnpm-lock\|15 second\|APP NOT RUNNING" \
  skills/drk-05-dev-verify/SKILL.md
```

Expected: `startup_command` in Parse step + new block; `APP NOT RUNNING` only in the two fallback log lines (not in the old single-step immediate-bail path).

**Step 5: Commit**

```bash
git add skills/drk-05-dev-verify/SKILL.md
git commit -m "feat: auto-discover and run startup command in drk-05-dev-verify"
```

---

### Task 4: Sync to global and verify

**Step 1: Sync**

```bash
bash scripts/sync-to-global.sh
```

Expected: output shows drk-03, drk-05, drk-07 being copied.

**Step 2: Spot-check global install**

```bash
grep -n "startup_command" \
  ~/.claude/skills/drk-07-qa-acceptance/SKILL.md \
  ~/.claude/skills/drk-05-dev-verify/SKILL.md \
  ~/.claude/skills/drk-03-qa-runbook-gen/references/runbook-template.md
```

Expected: matches in all three files.

**Step 3: Final check — old bail-out text is gone globally**

```bash
grep -n "running correctly" ~/.claude/skills/drk-07-qa-acceptance/SKILL.md
```

Expected: only one match (the new fallback after 15s retry).
