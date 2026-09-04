# Cross-repository verification system plan

> df-implement executes this plan task by task. Never hand it to any other execution skill.

This plan has 20 delivery units across Dark Factory, Spellbook, and Spellguard. PR-DF-P0 carries the planning record. PR-SG-2 is the first user-facing slice. Three linear dependency chains qualify for native stack registration.

**Goal.** Commit a restart-safe Dark Factory verification lifecycle and the first honest Spellguard catalog-to-recipe migration.
**Spec.** `/home/dev/dark-factory/docs/prd-verification-system.md`
**Design.** `/home/dev/dark-factory/docs/design-verification-system.md`
**Lane.** Standard.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. Check a box only when its evidence exists, a file, a log line, a test run, a screenshot, or a commit SHA. The body is a how-to. The appendices explain and record.

df-implement executes this plan task by task. The operator merges every PR.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Global constraints

- Supported media are exactly `dashboard`, `cli-tui`, `cli-agent`, and `mcp`.
- Every delegated dispatch reserves a run-state sequence before it starts.
- Claude calls are forbidden in this run. Fresh Codex contexts provide context diversity only.
- Dark Factory shipped role policy resolves every declared responsibility without an override.
- Project role values override machine role values. Machine role values override shipped defaults.
- The machine override path is `${XDG_CONFIG_HOME:-$HOME/.config}/dark-factory/config.json`.
- The tracked project override path is `.agents/dark-factory.json`. It may contain role targets only.
- Spellbook owns feature identity. Spellguard owns verification skills, recipes, dispositions, and catalog linkage.
- Recipe files use `.agents/skills/verify-spellguard-<medium>/features/<CATALOG-ID>.md` with an exact supported medium and catalog ID.
- A missing recipe is unassessed. It is never inferred to mean not present.
- A recipe is not acceptance evidence. A live drive writes separate PASS, FAIL, or BLOCKED evidence.
- Do not add or change CI workflow files without separate operator approval.
- Do not merge, deploy, rotate credentials, force-push, or remove unrelated local files.
- Use the approved Dark Factory PAT only through `GH_CONFIG_DIR=/home/dev/.config/gh` with inherited token variables unset.

## Publish the approved planning record (PR-DF-P0)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 1 dispatch.

**You see.**

- [x] The branch contains the approved PRD, synthesized design, and machine-checked implementation plan.

### Task 1. Record the approved requirements and design

**Files.**

- Create `docs/prd-verification-system.md`.
- Create `docs/design-verification-system.md`.
- Create `docs/implementation-plan-verification-system.md`.
- Test `skills/df-plan/scripts/check-plan.mjs` against this plan.

**Interfaces.**

- Consumes. The approved run contract at `work/run-contract.md`.
- Produces. The normative requirements in `docs/prd-verification-system.md` and the implementation interfaces in `docs/design-verification-system.md`.

**Steps.**

- [x] Verify that both documents name the four exact media and the zero-Claude limit.

```bash
rg -n 'dashboard|cli-tui|cli-agent|mcp|CLAUDE_CALL_BUDGET' \
  docs/prd-verification-system.md docs/design-verification-system.md
```

- [x] Run `git diff 464b5c2..4cc6d06 --check`. Expect PASS.
- [x] Commit the PRD with `git commit -m "docs: add verification system PRD"`.
- [x] Commit the design with `git commit -m "docs: add verification system design"`.
- [ ] Commit the checked plan with `git commit -m "docs: add verification system implementation plan"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The checked plan accepts all delivery blocks. Run `node skills/df-plan/scripts/check-plan.mjs /home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/work/implementation-plan.md`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Open both documents through GoGrip and follow every local file pointer in the design. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-P0-links.txt`. Pass when every pointer resolves in the branch and no target path is ambiguous.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR changes planning documents only.

## Resolve every delegation role (PR-DF-A1)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] `df-role.mjs prepare-run` reports one frozen resolution for every Dark Factory responsibility, including its source.

### Task 2. Add the role policy resolver and totality check

**Files.**

- Create `references/model-policy.json`.
- Create `scripts/df-role.mjs`.
- Create `scripts/check-model-policy.mjs`.
- Create `scripts/test-df-role-policy.sh`.
- Create the exact mirrors under `codex-plugin/references/` and `codex-plugin/scripts/`.
- Modify `skills/df/references/model-policy.md`, lines 1 to 30.
- Modify `codex-plugin/skills/df/references/model-policy.md`, lines 1 to 30.
- Modify `scripts/check-plugin-manifests.sh`, lines 56 to 87.
- Modify `Justfile`, lines 65 to 185.
- Test `scripts/test-df-role-policy.sh`.

**Interfaces.**

- Consumes. `prepareRunRolePlan({runId, harness, repoRoot}): FrozenRolePlan` from the approved design.
- Produces. CLI commands `prepare-run --run --harness --repo-root`, `resolve --run --responsibility --lane`, and `preflight --run --responsibility --lane`.

**Steps.**

- [ ] Write the failing role-policy test with these cases.

```text
shipped policy resolves all Claude and Codex responsibilities
missing mapping reports the exact responsibility
machine override wins over shipped
project override wins over machine
unknown field reports its source path and field
missing named-agent definition stops before df-state reserve
prepared role plan does not change after override files change
root and codex-plugin policy, script, and docs mirrors match
```

- [ ] Run `bash scripts/test-df-role-policy.sh`. Expect FAIL because `scripts/df-role.mjs` does not exist.
- [ ] Implement the schema-version 1 role contract with these complete responsibility keys.

```json
{
  "schemaVersion": 1,
  "responsibilities": [
    "session_router",
    "orchestrator",
    "menial_scoped_investigation",
    "implementation_delegate",
    "judgment_delegate",
    "investigation_synthesizer",
    "design_runners",
    "discovery_reviewers",
    "recheck_leaf_reviewers",
    "eval_graders",
    "persona_reviewers_cli",
    "cross_model_review"
  ],
  "overridePrecedence": ["shipped", "machine", "project"],
  "allowedProjectKeys": ["schemaVersion", "roles"]
}
```

- [ ] Make `prepare-run` write `work/role-plan.json` beneath the external run directory with the policy digest, provenance, harness, lane, and every resolution. Use an atomic temporary-file rename.
- [ ] Make `resolve` read only the frozen plan. Make `preflight` verify named-agent definitions before any reservation.
- [ ] Run `bash scripts/test-df-role-policy.sh`. Expect PASS.
- [ ] Run `just check-role-policy && just check-parity && just check-plugins && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "feat(df): resolve delegation roles from layered policy"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-role-policy.sh` gains all seven cases above. Run `bash scripts/test-df-role-policy.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Prepare a disposable run, resolve `design_runners`, then point an override at a missing named agent and prove preflight stops before reservation. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-A1-live.txt`. Pass when the first output names `terra_xhigh`, the second output names the bad agent, and the run's reserved count does not change.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Role resolution runs once per run and preflight reads small local files.

## Adopt resolved roles in every runner (PR-DF-A2)

**Depends on.** PR-DF-A1.

**Branch.** Dependent on PR-DF-A1.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Every dispatching skill prints its resolved role before reservation, and no runner owns a separate model or effort fallback.

### Task 3. Replace runner-local model choices

**Files.**

- Modify `skills/df-code-review/SKILL.md`, lines 94 to 194.
- Modify `skills/df-prd-challenge/SKILL.md`, lines 162 to 180.
- Modify the role prose in `skills/df-design`, `skills/df-implement`, `skills/df-plan`, `skills/how`, `skills/why`, `skills/recall`, `skills/df-eval`, `skills/arena`, `skills/swarm`, and `skills/interrogate`.
- Modify `skills/df-qa-validation/scripts/run_codex_qa_validation.sh`, lines 160 to 167.
- Modify `skills/df-code-review/scripts/run_codex_quality_review.sh`, lines 130 to 170.
- Modify `skills/df-code-review/scripts/run_codex_spec_review.sh`, lines 130 to 170.
- Modify every matching file under `codex-plugin/`.
- Modify `scripts/test_prd_review_runners.sh`.
- Create `scripts/test-df-role-callers.sh`.
- Test `scripts/test-df-role-callers.sh`.

**Interfaces.**

- Consumes. `df-role.mjs preflight --run string --responsibility Responsibility --lane Lane`.
- Produces. One preflight-before-reserve call at every background dispatch site and zero private model or effort defaults.

**Steps.**

- [ ] Write a failing static caller test that enumerates every dispatch site and rejects direct `-c model_reasoning_effort=`, `--model`, and unqualified role names outside the resolver fixtures.
- [ ] Add a fake resolver fixture that logs `preflight`, then a fake state writer that logs `reserve`. Assert ordering for each shell runner.
- [ ] Run `bash scripts/test-df-role-callers.sh`. Expect FAIL because current runners select effort locally.
- [ ] Replace each caller with this command boundary before reservation.

```bash
node scripts/df-role.mjs preflight \
  --run "$RUN_ID" \
  --responsibility "$RESPONSIBILITY" \
  --lane "$LANE"
```

- [ ] Keep `scripts/df-codex-exec.sh` limited to the Claude-to-Codex durable transport. Do not route native Codex subagents through it.
- [ ] Run `bash scripts/test-df-role-callers.sh && just test-runners && just check-parity && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "refactor(df): route runner dispatches through role policy"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-role-callers.sh` gains dispatch-order and forbidden-fallback cases. Run `bash scripts/test-df-role-callers.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Start a disposable planning dispatch through the Codex path with a fake worker command. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-A2-live.txt`. Pass when the log orders role preflight before reservation before worker start and records no runner-local effort flag.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. The change replaces local argument selection with one local policy read.

## Seal plural verification selections (PR-DF-B1)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Coverage seals one content-addressed selection that retains every selected recipe, medium, sub-feature, requirement, and negative requirement.

### Task 4. Add the immutable selection ABI

**Files.**

- Create `references/verification-selection.schema.json`.
- Create `scripts/df-selection.mjs`.
- Create `scripts/test-df-selection.sh`.
- Create exact mirrors under `codex-plugin/references/` and `codex-plugin/scripts/`.
- Modify `references/run-state-schema.md`, lines 10 to 151.
- Modify `codex-plugin/references/run-state-schema.md`, lines 10 to 151.
- Modify `scripts/check-plugin-manifests.sh`, lines 56 to 87.
- Modify `Justfile`, lines 65 to 185.
- Test `scripts/test-df-selection.sh`.

**Interfaces.**

- Consumes. `sealSelection({runId, draftPath, repoRoot}): SelectionRef` and `materializeSelection({selectionRef, repoRoot}): VerificationSelection`.
- Produces. CLI commands `seal --run --draft --repo-root`, `inspect --ref`, and `materialize --ref --repo-root --format`.

**Steps.**

- [ ] Write the failing selection test with these cases.

```text
canonical sort gives identical digests for reordered entries
user-facing selection rejects zero entries
no-user-route selection accepts zero entries and a reason
medium accepts dashboard, cli-tui, cli-agent, and mcp only
duplicate entry IDs and duplicate recipe identities fail
recipe, skill, PRD, and catalog-link digest drift each fail
sealed content cannot be overwritten
concurrent seal calls leave one complete canonical file
materialize never searches for a latest selection
root and codex-plugin files match
```

- [ ] Run `bash scripts/test-df-selection.sh`. Expect FAIL because the selection command does not exist.
- [ ] Implement this schema-version 1 entry shape and union.

```json
{
  "schemaVersion": 1,
  "kind": "user-facing",
  "runId": "string",
  "featureSlug": "string",
  "prd": {"path": "string", "sha256": "64 lowercase hex"},
  "catalogLink": {"path": "string", "sha256": "64 lowercase hex"},
  "entries": [{
    "id": "string",
    "medium": "dashboard | cli-tui | cli-agent | mcp",
    "skill": {"path": "string", "sha256": "64 lowercase hex"},
    "recipe": {"path": "string", "subFeature": "string or null", "sha256": "64 lowercase hex"},
    "requirementIds": ["REQ-000"],
    "negativeRequirementIds": ["NEG-000"]
  }]
}
```

- [ ] Canonicalize object keys and entries before hashing. Write `verification-selections/sha256.json` beneath the external run directory through an atomic rename.
- [ ] Reject path traversal, absolute repository paths, digest mismatch, invalid media, unsealed input, and any discovery fallback.
- [ ] Run `bash scripts/test-df-selection.sh && just check-parity && just check-plugins && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "feat(df): seal plural verification selections"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-selection.sh` gains the ten cases above. Run `bash scripts/test-df-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Seal a two-medium fixture, materialize it, alter one recipe byte, and materialize it again. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-B1-live.txt`. Pass when the first read returns both entries and the second fails with the changed recipe path and expected digest.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Selection files are bounded run metadata and use local hashing.

## Validate requirements against the sealed selection (PR-DF-B2)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] QA validation receives one selection reference and reviews every resolved recipe without accepting a QA-runbook argument.

### Task 5. Convert QA validation to a selection consumer

**Files.**

- Modify `skills/df-qa-validation/SKILL.md`, lines 41 to 198.
- Modify `skills/df-qa-validation/scripts/run_codex_qa_validation.sh`, lines 4 to 210.
- Modify `skills/df-qa-validation/references/claude-review-prompt.md`.
- Modify the matching `codex-plugin/skills/df-qa-validation/` files.
- Create `scripts/test-df-qa-selection.sh`.
- Test `scripts/test-df-qa-selection.sh`.

**Interfaces.**

- Consumes. `SelectionRef` and `df-selection.mjs materialize --ref string --repo-root string --format json`.
- Produces. `run_codex_qa_validation.sh PRD_PATH SELECTION_REF REPO_ROOT OUTPUT_DIR` and a report header containing the selection digest.

**Steps.**

- [ ] Write a failing runner fixture that passes two recipes, rejects a legacy QA path, preserves both recipe identities in the prompt, and refuses digest drift.
- [ ] Run `bash scripts/test-df-qa-selection.sh`. Expect FAIL because the runner still accepts one QA-runbook path.
- [ ] Change the runner usage to this exact boundary.

```text
usage: run_codex_qa_validation.sh PRD_PATH SELECTION_REF REPO_ROOT OUTPUT_DIR
```

- [ ] Materialize before any reviewer starts. If an auto-fix changes a selected recipe, stop and return `RESEAL_REQUIRED` with that recipe path.
- [ ] Label the absent Claude leg `deferred: Claude subscription exhausted`. Never label Codex-only passes model-diverse.
- [ ] Run `bash scripts/test-df-qa-selection.sh && just check-parity && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "refactor(qa): validate the sealed recipe selection"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-qa-selection.sh` gains multi-recipe, legacy-argument, drift, and reseal cases. Run `bash scripts/test-df-qa-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run Codex QA validation against the four Spellguard smoke recipes from PR-SG-2 after that branch exists. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-B2-live.txt`. Pass when the report contains all four recipe identities, one selection digest, and the deferred Claude flag.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Prompt materialization adds bounded local file reads.

## Review code against the sealed selection (PR-DF-B3)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Whole-branch code review reports the same selection digest and recipe identities that coverage sealed.

### Task 6. Convert code review to a selection consumer

**Files.**

- Modify `skills/df-code-review/SKILL.md`, lines 106 to 485.
- Modify `skills/df-code-review/scripts/run_codex_spec_review.sh`, lines 4 to 176.
- Modify `skills/df-code-review/references/claude-spec-compliance-prompt.md`.
- Modify the matching `codex-plugin/skills/df-code-review/` files.
- Create `scripts/test-df-code-review-selection.sh`.
- Test `scripts/test-df-code-review-selection.sh`.

**Interfaces.**

- Consumes. `SelectionRef` and the read-only materialization command from PR-DF-B1.
- Produces. A code-review input bundle and report header with the immutable selection digest and all recipe identities.

**Steps.**

- [ ] Write a failing fixture that feeds two media, proves both enter the spec-review prompt, and rejects a missing or changed selection.
- [ ] Run `bash scripts/test-df-code-review-selection.sh`. Expect FAIL because the current review path takes one QA file.
- [ ] Replace the QA-path input with `SELECTION_REF` and `REPO_ROOT`. Preserve the frozen-diff, retry, synthesis, and delta-review behavior.
- [ ] Keep role-policy cleanup out of this task. PR-DF-A2 owns runner model and effort selection.
- [ ] Run `bash scripts/test-df-code-review-selection.sh && just check-parity && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "refactor(review): consume the sealed recipe selection"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-code-review-selection.sh` gains plural, missing-ref, drift, and report-header cases. Run `bash scripts/test-df-code-review-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Review a disposable two-recipe fixture through the Codex spec-review path. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-B3-live.txt`. Pass when the prompt and report retain both recipe identities and reject a substituted path.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. The review already reads bounded PRD and recipe inputs.

## Drive only the selected user routes (PR-DF-B4)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Developer verification drives each selected medium and cannot rediscover, widen, or silently skip the list.

### Task 7. Convert developer verification to a closed selection

**Files.**

- Modify `skills/df-dev-verify/SKILL.md`, lines 14 to 306.
- Modify `codex-plugin/skills/df-dev-verify/SKILL.md`, lines 13 to 312.
- Create `scripts/test-verification-selection-flow.sh`.
- Test `scripts/test-verification-selection-flow.sh`.

**Interfaces.**

- Consumes. One `SelectionRef` with one or more exact medium entries.
- Produces. One developer-verification result per entry with recipe identity, medium, driven user route, terminal status, and evidence path.

**Steps.**

- [ ] Write a failing flow test that supplies dashboard plus CLI agent entries, makes the driver return PASS and BLOCKED, and rejects a third recipe discovered from the map.
- [ ] Run `bash scripts/test-verification-selection-flow.sh`. Expect FAIL because the skill permits recipe rediscovery.
- [ ] Require the selection before automated tests start. After tests pass, materialize once and drive only those entries.
- [ ] Treat missing skills, prerequisites, or driver access as BLOCKED. Never convert them to a skip or test pass.
- [ ] Run `bash scripts/test-verification-selection-flow.sh && just check-parity && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "refactor(verify): drive the closed recipe selection"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-verification-selection-flow.sh` gains plural execution, no-widening, missing-skill, and per-entry result cases. Run `bash scripts/test-verification-selection-flow.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive the four PR-SG-2 smoke recipes from one sealed selection after that branch exists. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-B4-live.json`. Pass when exactly four terminal records exist and each names its actual medium.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. User-route latency belongs to each project recipe rather than the lifecycle iterator.

## Require project recipe migration evidence (PR-DF-B5)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Coverage owns the sealed selection and reports project migration readiness without inventing recipes or accepting a legacy QA path.

### Task 8. Connect coverage to project migration contracts

**Files.**

- Modify `skills/df-verify-coverage/SKILL.md`, lines 91 to 228.
- Modify `skills/df-verify-coverage/references/spec-guardian-rules.md`, lines 1 to 30.
- Modify `skills/create-verification-skill/SKILL.md`, lines 43 to 90.
- Modify `skills/maintain-verification-skill/SKILL.md`, lines 14 to 90.
- Modify the matching files under `codex-plugin/skills/`.
- Create `scripts/test-df-coverage-selection.sh`.
- Test `scripts/test-df-coverage-selection.sh`.

**Interfaces.**

- Consumes. Project verification index fields `catalogLink`, `media`, `recipes`, `migrationCheck`, and `noNewProceduralRunbooksCheck`.
- Produces. One validated draft for PR-DF-B1 sealing and one migration readiness value among `ready`, `pending`, and `blocked`.

**Steps.**

- [ ] Write a failing fixture for a two-medium project with one covered recipe, one deferred disposition, one unmapped legacy scenario, and one invalid `CLI or TUI` medium.
- [ ] Run `bash scripts/test-df-coverage-selection.sh`. Expect FAIL because coverage returns a conversation-only entry list.
- [ ] Make coverage validate exact media, bidirectional REQ and NEG links, catalog linkage, recipe hashes, and project migration status before it calls `df-selection.mjs seal`.
- [ ] Make missing or stale project skills route to the creator or maintainer. Neither skill may invent catalog IDs or migration dispositions.
- [ ] Treat an unmapped legacy scenario as pending migration. Block only deletion or a completeness claim, not unrelated recipe authoring.
- [ ] Run `bash scripts/test-df-coverage-selection.sh && just check-parity && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "feat(coverage): seal project recipe selections"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-coverage-selection.sh` gains exact-medium, catalog, plural recipe, legacy scenario, and no-invention cases. Run `bash scripts/test-df-coverage-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run coverage against the PR-SG-3 verification index and migration inventory. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-B5-live.txt`. Pass when four media resolve, the smoke entries seal, catalog gaps stay unassessed, and pending legacy scenarios do not become covered.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Coverage reads committed metadata once before sealing.

## Record one acceptance verdict per recipe (PR-DF-B6)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Acceptance drives the exact sealed entries and writes one immutable external verdict for each entry.

### Task 9. Convert acceptance to a selection consumer

**Files.**

- Modify `skills/df-acceptance/SKILL.md`, lines 19 to 243.
- Modify `codex-plugin/skills/df-acceptance/SKILL.md`, lines 19 to 243.
- Create `scripts/test-df-acceptance-selection.sh`.
- Test `scripts/test-df-acceptance-selection.sh`.

**Interfaces.**

- Consumes. One `SelectionRef` and the read-only selection materializer.
- Produces. Files under `acceptance/SELECTION_DIGEST/` with one terminal PASS, FAIL, or BLOCKED verdict per selection entry.

**Steps.**

- [ ] Write a failing acceptance fixture with four entries, one retry, one blocked prerequisite, and one altered recipe.
- [ ] Run `bash scripts/test-df-acceptance-selection.sh`. Expect FAIL because acceptance receives a conversational entry list.
- [ ] Materialize the selection once. Reject drift before any drive. Never add, drop, substitute, or normalize an entry.
- [ ] Store attempt records under the external run directory. Keep existing committed acceptance evidence as historical and read-only.
- [ ] Compute the feature verdict from the weakest terminal entry. FAIL outranks BLOCKED, and BLOCKED outranks PASS.
- [ ] Run `bash scripts/test-df-acceptance-selection.sh && just check-parity && just check-no-repo-scratch && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "refactor(acceptance): drive sealed recipe selections"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-acceptance-selection.sh` gains exact-entry, drift, retry, immutable-evidence, and weakest-verdict cases. Run `bash scripts/test-df-acceptance-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive the PR-SG-2 four-smoke selection and inspect the external evidence directory. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-B6-live.txt`. Pass when the directory has exactly four terminal records, every record names the same selection digest, and no target-repository evidence file appears.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Each selected recipe owns its own latency and readiness threshold.

## Retire stale lifecycle vocabulary (PR-DF-C)

**Depends on.** PR-DF-B5.

**Branch.** Dependent on PR-DF-B5.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Active Dark Factory instructions describe committed recipes, sealed selections, and external evidence without directing new work to feature QA runbooks.

### Task 10. Remove stale non-historical QA prose

**Files.**

- Modify `skills/df/SKILL.md`, lines 23 to 136.
- Modify `skills/df-plan/SKILL.md`, lines 90 to 110.
- Modify `skills/df-verify-coverage/references/spec-guardian-rules.md`, lines 1 to 30.
- Modify matching files under `codex-plugin/skills/`.
- Create `scripts/test-df-current-terminology.sh`.
- Test `scripts/test-df-current-terminology.sh`.

**Interfaces.**

- Consumes. The selection and migration terms introduced by PR-DF-B1 and PR-DF-B5.
- Produces. A narrow living-prose allowlist that preserves dated history, vendor lineage, operational runbooks, release runbooks, and existing evidence.

**Steps.**

- [ ] Write a failing dual-tree test that scans only current workflow instructions and rejects `QA runbook path`, `generated feature QA runbook`, and conversation-only `entry list` contracts.
- [ ] Run `bash scripts/test-df-current-terminology.sh`. Expect FAIL on current living instructions.
- [ ] Replace the stale terms with `project verification recipe`, `SelectionRef`, or `acceptance evidence` according to the owning stage.
- [ ] Exclude `docs/`, `references/vendor-manifest.md`, dated records, examples, operational runbooks, release runbooks, and historical evidence from the test.
- [ ] Run `bash scripts/test-df-current-terminology.sh && just check-parity && just check-no-repo-scratch && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "docs(df): retire legacy QA handoff terms"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-current-terminology.sh` gains current-prose rejection and historical allowlist cases. Run `bash scripts/test-df-current-terminology.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Follow the feature playbook from coverage through acceptance with the names only, using a disposable fixture project. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-DF-C-live.txt`. Pass when every stage hands off one `SelectionRef` and no instruction asks for a QA-runbook path.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR changes living instructions and static contract checks.

## Reconcile the divergent Spellbook source pin (PR-SB-1)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This unit expects 0 dispatches until its source-history blocker clears.

**You see.**

- [ ] Spellbook pins an immutable Spellguard revision on the current main lineage after every affected catalog page has been reviewed.

### Task 11. Advance the catalog only from a valid descendant

**Files.**

- Modify `data/source-pin.json` only after its current revision has a reviewed current-lineage successor.
- Regenerate `data/catalog/inventory/source-inventory.json`.
- Regenerate `data/catalog/source-line-counts.json`.
- Modify affected records under `data/catalog/features/`.
- Regenerate `docs/feature-catalog/coverage.json`.
- Regenerate `docs/feature-catalog/coverage.md`.
- Test `site/src/tests/catalog.test.ts`.
- Test `site/src/tests/catalog-integrity.test.ts`.
- Test `site/src/tests/content.test.ts`.

**Interfaces.**

- Consumes. A Spellguard source revision that descends from current Spellguard `origin/main` and a reviewed affected-file inventory.
- Produces. One immutable Spellbook catalog revision whose source pin, inventory, line counts, catalog records, and coverage outputs agree.

**Steps.**

- [ ] Run `git -C /home/dev/spellguard merge-base --is-ancestor 671e48681fa26aa7d428fc5edcb6be212ae8dd2e origin/main`. Expect FAIL with exit 1 on the current divergent history.
- [ ] Record BLOCKED with merge base `0c9472513e18dae1c1b17601cd86fe29a974e26b`, preserved branch state, and the failed command. Do not move the pin.
- [ ] After a reviewed current-lineage source revision exists, run the Spellbook `maintain-feature-catalog` workflow against that exact revision.
- [ ] Select Node 22.20.0. Run `node scripts/validate-catalog.mjs && ./node_modules/.bin/vitest run && node scripts/generate-catalog-coverage.mjs --check` from `site/`.
- [ ] Build into a disposable directory and run Pagefind. Drive changed ID redirects through local Wrangler assets.
- [ ] Commit with `git commit -m "docs(catalog): reconcile the Spellguard source pin"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Catalog, integrity, and content suites validate the reconciled revision. Run `cd site && ./node_modules/.bin/vitest run src/tests/catalog.test.ts src/tests/catalog-integrity.test.ts src/tests/content.test.ts`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Serve the built catalog with Wrangler and request both redirect forms plus the destination for each changed ID. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SB-1-live.txt`. Pass when every redirect reaches the canonical page with HTTP 200 and the reported source revision is a Spellguard-main ancestor.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Catalog generation and static serving are offline documentation operations.

## Add the Spellguard verification index (PR-SG-1)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] `pnpm verification:check` resolves the canonical Spellbook revision, reports the divergent Spellguard source history, and prints honest per-medium coverage counts.

### Task 12. Generate the catalog link and verification index

**Files.**

- Create `.agents/skills/verify-spellguard/SKILL.md`.
- Create `.agents/skills/verify-spellguard/references/catalog-link.json`.
- Create `.agents/skills/verify-spellguard/references/catalog-snapshot.json`.
- Create `.agents/skills/verify-spellguard/references/coverage-report.md`.
- Create `.agents/skills/verify-spellguard/scripts/check.mjs`.
- Create `.agents/skills/verify-spellguard/scripts/report.mjs`.
- Create `scripts/verification/generate-spellbook-catalog-snapshot.ts`.
- Create `scripts/verification/check-verification-maps.ts`.
- Create `tests/unit/verification/catalog-link.test.ts`.
- Create symlink `.claude/skills/verify-spellguard`.
- Modify `AGENTS.md`, lines 27 to 36.
- Modify `package.json`, lines 50 to 114.
- Test `tests/unit/verification/catalog-link.test.ts`.

**Interfaces.**

- Consumes. Spellbook catalog revision `dc03a0322c5f94de624ae4ba8ef2b00a565a03b0`, its product-source revision `671e48681fa26aa7d428fc5edcb6be212ae8dd2e`, and a caller-supplied Spellguard base revision.
- Produces. `pnpm verification:check`, `pnpm verification:report`, and a minimal snapshot with stable ID, record kind, status, canonical route, and redirect target.

**Steps.**

- [ ] Write a failing test that resolves the catalog revision only in Spellbook, resolves both product revisions only in Spellguard, rejects an unknown catalog ID, separates redirects from coverage, and reports the current source history as `history-divergent`.
- [ ] Run `pnpm exec vitest run tests/unit/verification/catalog-link.test.ts`. Expect FAIL because the verification index does not exist.
- [ ] Commit this catalog link shape.

```json
{
  "schemaVersion": 1,
  "spellbook": {
    "repository": "Spellguard/spellbook",
    "catalogRevision": "dc03a0322c5f94de624ae4ba8ef2b00a565a03b0"
  },
  "spellguard": {
    "repository": "Spellguard/spellguard-internal",
    "productSourceRevision": "671e48681fa26aa7d428fc5edcb6be212ae8dd2e"
  }
}
```

- [ ] Generate the snapshot from the exact Spellbook revision. Do not copy descriptions or claim that the inventory is complete manual coverage.
- [ ] Compare product-source ancestry only inside Spellguard. Report the current merge base `0c9472513e18dae1c1b17601cd86fe29a974e26b` and prevent a current-coverage claim.
- [ ] Add the index trigger, matching Claude symlink, and package commands as one atomic skill change.
- [ ] Run `pnpm exec vitest run tests/unit/verification/catalog-link.test.ts && pnpm run typecheck && pnpm run lint:check`. Expect PASS.
- [ ] Commit with `git commit -m "feat(verification): add catalog-linked verification index"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `tests/unit/verification/catalog-link.test.ts` gains repository-resolution, history-divergence, redirect, determinism, and unknown-ID cases. Run `pnpm exec vitest run tests/unit/verification/catalog-link.test.ts`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run the index against `/home/dev/spellbook` and the PR worktree's Spellguard head. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-1-live.txt`. Pass when it reports both repository-specific revisions, `history-divergent`, zero false covered rows, and deterministic snapshot output.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. The command scans one local catalog and four local feature directories.

## Add one base skill per user medium (PR-SG-2)

**Depends on.** PR-SG-1.

**Branch.** Dependent on PR-SG-1.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 9 dispatches.

**You see.**

- [ ] A fresh verifier can launch, diagnose, drive, record evidence for, and clean up each of the dashboard, CLI TUI, CLI agent, and MCP media.

### Task 13. Add the dashboard verification skill

**Files.**

- Create `.agents/skills/verify-spellguard-dashboard/SKILL.md`.
- Create `.agents/skills/verify-spellguard-dashboard/features/README.md`.
- Create `.agents/skills/verify-spellguard-dashboard/features/ORG-002.md`.
- Create symlink `.claude/skills/verify-spellguard-dashboard`.
- Modify `AGENTS.md`, lines 27 to 36.
- Create `tests/unit/verification/dashboard-skill.test.ts`.
- Test `tests/unit/verification/dashboard-skill.test.ts`.

**Interfaces.**

- Consumes. The verification index contract and the agent-browser driver.
- Produces. Launch, Doctor, Drive, Evidence, and Cleanup procedures plus the `ORG-002` login smoke recipe.

**Steps.**

- [ ] Write a failing structural test for the five base sections, catalog ID, four recipe sections, `Preconditions:` line, entry points, action-operation-result bullets, 90-second readiness rule, and cleanup-on-timeout.
- [ ] Run `pnpm exec vitest run tests/unit/verification/dashboard-skill.test.ts`. Expect FAIL because the dashboard skill does not exist.
- [ ] Author `ORG-002.md` for `/login`. Use real browser navigation, visible form and redirect observations, and screenshots. HTTP requests are not a substitute.
- [ ] Make Doctor distinguish a missing local dashboard from a product failure. Make Cleanup close only verification-owned browser sessions and local processes.
- [ ] Run `pnpm exec vitest run tests/unit/verification/dashboard-skill.test.ts`. Expect PASS.
- [ ] Commit with `git commit -m "feat(verification): add the dashboard driver"`.

### Task 14. Add the CLI TUI verification skill

**Files.**

- Create `.agents/skills/verify-spellguard-cli-tui/SKILL.md`.
- Create `.agents/skills/verify-spellguard-cli-tui/features/README.md`.
- Create `.agents/skills/verify-spellguard-cli-tui/features/CTL-008.md`.
- Create symlink `.claude/skills/verify-spellguard-cli-tui`.
- Modify `AGENTS.md`, lines 27 to 36.
- Create `tests/unit/verification/cli-tui-skill.test.ts`.
- Test `tests/unit/verification/cli-tui-skill.test.ts`.

**Interfaces.**

- Consumes. The verification index and the existing Docker CLI sandbox.
- Produces. The five base sections and a `CTL-008` smoke recipe driven through a real private TTY.

**Steps.**

- [ ] Write a failing test that requires a private tmux label, runtime TTY proof, Docker isolation for setup and reset, readiness timeout cleanup, and rejection of workbench-only evidence.
- [ ] Run `pnpm exec vitest run tests/unit/verification/cli-tui-skill.test.ts`. Expect FAIL because the TUI skill does not exist.
- [ ] Author `CTL-008.md` for the bare `spellguard` command. Observe the actual interactive screen, navigation, and exit behavior.
- [ ] Prohibit host credential mutation. Use `docker/codex-test/spin-up.sh` and a private `tmux -L` server.
- [ ] Run `pnpm exec vitest run tests/unit/verification/cli-tui-skill.test.ts`. Expect PASS.
- [ ] Commit with `git commit -m "feat(verification): add the CLI TUI driver"`.

### Task 15. Add the CLI agent-mode verification skill

**Files.**

- Create `.agents/skills/verify-spellguard-cli-agent/SKILL.md`.
- Create `.agents/skills/verify-spellguard-cli-agent/features/README.md`.
- Create `.agents/skills/verify-spellguard-cli-agent/features/CTL-019.md`.
- Create symlink `.claude/skills/verify-spellguard-cli-agent`.
- Modify `AGENTS.md`, lines 27 to 36.
- Create `tests/unit/verification/cli-agent-skill.test.ts`.
- Test `tests/unit/verification/cli-agent-skill.test.ts`.

**Interfaces.**

- Consumes. The verification index and plain CLI stdout, stderr, JSON, and exit-code capture.
- Produces. The five base sections and a non-TUI `CTL-019` schema smoke recipe.

**Steps.**

- [ ] Write a failing test that requires machine-readable output, exact exit codes, explicit confirmation behavior, no TTY entry, readiness timeout cleanup, and secret redaction.
- [ ] Run `pnpm exec vitest run tests/unit/verification/cli-agent-skill.test.ts`. Expect FAIL because the agent-mode skill does not exist.
- [ ] Author `CTL-019.md` for `spellguard schema`. Observe JSON schema content, stable output framing, and exit status without entering the TUI.
- [ ] Route remote managed operations through the existing Spellguard managed JSON skill where it applies.
- [ ] Run `pnpm exec vitest run tests/unit/verification/cli-agent-skill.test.ts`. Expect PASS.
- [ ] Commit with `git commit -m "feat(verification): add the CLI agent driver"`.

### Task 16. Add the MCP verification skill

**Files.**

- Create `.agents/skills/verify-spellguard-mcp/SKILL.md`.
- Create `.agents/skills/verify-spellguard-mcp/features/README.md`.
- Create `.agents/skills/verify-spellguard-mcp/features/CTL-022.md`.
- Create symlink `.claude/skills/verify-spellguard-mcp`.
- Modify `AGENTS.md`, lines 27 to 36.
- Create `tests/unit/verification/mcp-skill.test.ts`.
- Test `tests/unit/verification/mcp-skill.test.ts`.

**Interfaces.**

- Consumes. The verification index, the local cloud dev stack, raw JSON-RPC capture, and named hosted-client prerequisites.
- Produces. The five base sections and a `CTL-022` compact read-tools smoke recipe with distinct offline and hosted-client proof.

**Steps.**

- [ ] Write a failing test that separates offline route parity, deployed dev-stack proof, hosted-client proof, and production advertisement. Require BLOCKED for missing entitlement.
- [ ] Run `pnpm exec vitest run tests/unit/verification/mcp-skill.test.ts`. Expect FAIL because the MCP skill does not exist.
- [ ] Author `CTL-022.md` for search, describe, and invoke-read. Require exactly three compact tools and a result that matches an independent direct query.
- [ ] Keep Cloudflare, Claude Pro web, ChatGPT Business, and Gemini host states independent. Never substitute a successful client for a blocked named host.
- [ ] Run `pnpm exec vitest run tests/unit/verification/mcp-skill.test.ts`. Expect PASS.
- [ ] Commit with `git commit -m "feat(verification): add the MCP driver"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] All four base-skill suites validate structure, recipe shape, timeout, cleanup, and driver boundaries. Run `pnpm exec vitest run tests/unit/verification/dashboard-skill.test.ts tests/unit/verification/cli-tui-skill.test.ts tests/unit/verification/cli-agent-skill.test.ts tests/unit/verification/mcp-skill.test.ts`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive `ORG-002` with agent-browser, `CTL-008` in the Docker TTY sandbox, `CTL-019` as a non-TUI CLI process, and `CTL-022` against the throwaway dev stack. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-2-smokes/`. Pass when all four recipes have separate terminal records, cleanup records, and observed media.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Seconds from Launch start to each medium's declared readiness signal.
- [ ] Probe. Run each medium readiness procedure on `origin/main` first where an equivalent route exists, then on the PR head, with the same local services.
- [ ] Baseline. Record each trunk route's readiness seconds before starting the PR-head probe.
- [ ] Rule. Fail when any PR-head readiness signal exceeds 90 seconds or cleanup does not finish after a timeout.

## Inventory and guard the legacy QA migration (PR-SG-3)

**Depends on.** PR-SG-2.

**Branch.** Dependent on PR-SG-2.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Migration commands report 45 procedural or mixed inputs, 8 retained items, 3 classification questions, and every mapped or missing scenario without deleting a source.

### Task 17. Add migration inventory, checks, and local gate

**Files.**

- Create `scripts/verification/generate-qa-migration-inventory.ts`.
- Create `scripts/verification/check-qa-migration.ts`.
- Create `scripts/verification/check-no-procedural-qa-runbooks.ts`.
- Create `docs/verification/qa-runbook-inventory.json`.
- Create `tests/unit/verification/qa-migration-contract.test.ts`.
- Modify `.agents/skills/verify-spellguard/SKILL.md`.
- Modify `package.json`, lines 50 to 114.
- Test `tests/unit/verification/qa-migration-contract.test.ts`.

**Interfaces.**

- Consumes. Files under `docs/qa/`, recipe `Legacy scenarios` identifiers, and an optional `--base` Git revision.
- Produces. `pnpm verification:migration-report --base origin/main` and `pnpm verification:no-new-runbooks --base origin/main`.

**Steps.**

- [ ] Write a failing test for procedural, mixed, historical, operational, fixture, and needs-review classifications. Add duplicate-scenario, unmapped-deletion, new-procedural-file, and accepted-operational-file cases.
- [ ] Run `pnpm exec vitest run tests/unit/verification/qa-migration-contract.test.ts`. Expect FAIL because migration commands do not exist.
- [ ] Generate stable scenario IDs as `SOURCE_BASENAME#SECTION_ANCHOR#ORDINAL`. Preserve source path, byte digest, category, and mapping state.
- [ ] Record the eight retained files named in Appendix C. Record the three classification questions named there. Classify the other 45 as procedural or mixed without deleting them.
- [ ] Read source bytes. When a NUL byte appears in `qa-audit-log-streaming.md`, report its byte offset and mark the source blocked from deletion instead of skipping it.
- [ ] Make the no-new-runbook check inspect added files relative to `--base`. Do not add it to CI in this PR.
- [ ] Run `pnpm exec vitest run tests/unit/verification/qa-migration-contract.test.ts && pnpm verification:migration-report --base origin/main && pnpm verification:no-new-runbooks --base origin/main && pnpm run typecheck && pnpm run lint:check`. Expect PASS with pending mappings and no deletion claim.
- [ ] Commit with `git commit -m "feat(verification): inventory legacy QA migration"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `tests/unit/verification/qa-migration-contract.test.ts` gains classification, scenario identity, byte-error, mapping, deletion, and diff-gate cases. Run `pnpm exec vitest run tests/unit/verification/qa-migration-contract.test.ts`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run all three verification commands against the real repository and compare the generated inventory with the reviewed 56-file census. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-3-live.txt`. Pass when counts are 45 procedural or mixed, 8 retained, 3 needs review, no source is silently skipped, and no current coverage claim appears.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. The commands scan small local Markdown and JSON files on demand.

## Migrate dashboard identity and core QA scenarios (PR-SG-4)

**Depends on.** PR-SG-3.

**Branch.** Dependent on PR-SG-3.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] The first migration batch adds executable dashboard identity, organization, control, and collaboration recipes while catalog gaps remain explicit.

### Task 18. Map nine identity and core QA sources

**Files.**

- Create or extend dashboard feature files for `COL-001`, `COL-004`, `CTL-003`, `CTL-004`, `CTL-005`, `CTL-006`, `CRD-003`, `CRD-011`, `CRD-012`, `CRD-013`, `CRD-014`, `CRD-023`, `INF-009`, `MGT-002`, `MGT-003`, `MGT-005`, `MGT-006`, `MGT-008`, `MGT-010`, `FLT-004`, `FLT-013`, `ORG-001`, `CHN-002`, `GRD-002`, `GRD-003`, and `GRD-011` under `.agents/skills/verify-spellguard-dashboard/features/`.
- Create deferred dashboard file `.agents/skills/verify-spellguard-dashboard/features/GIT-005.md`.
- Create `.agents/skills/verify-spellguard-cli-tui/features/COL-001.md`.
- Create `.agents/skills/verify-spellguard-cli-agent/features/FRM-016.md`.
- Create `docs/verification/qa-migrations/dashboard-identity-core.json`.
- Modify `docs/verification/qa-runbook-inventory.json`.
- Test changed recipes with `.agents/skills/verify-spellguard/scripts/check.mjs`.

**Interfaces.**

- Consumes. The base skills and migration scenario IDs from PR-SG-3.
- Produces. Recipe identities and scenario mappings for nine named legacy sources while leaving unmapped gaps pending.

**Steps.**

- [ ] Run `pnpm verification:migration-report --base origin/main` and save the before-count.
- [ ] Map only user-facing scenarios from `qa-a2a-generalized-task-handling`, `qa-agent-control-plane-github-mvp`, `qa-agent-groups-discoverability`, `qa-github-mvp`, `qa-multi-org-support`, `qa-org-membership-permissions`, `qa-control-bot-identity-binding`, `qa-policy-hierarchy-redesign`, and `qa-security-cross-cutting`.
- [ ] Use this complete covered-recipe shape for each mapped feature-medium pair.

```markdown
---
schemaVersion: 1
catalogId: ORG-001
medium: dashboard
disposition: covered
legacyScenarios:
  - qa-multi-org-support#org-switcher#1
---
# Active organization context

## Sub-features

- Switch the active organization.
- Observe organization-scoped navigation and data.

## How to get to it (user POV)

- Sign in, open the organization switcher, and select an organization.

## Driving it with agent-browser

Preconditions: Two visible organizations exist for the signed-in user.

- User action: Open the organization switcher. Operation: Inspect the rendered menu with agent-browser. Observable result: Both permitted organizations appear and no unpermitted organization appears.
- User action: Select the second organization. Operation: Click its visible menu item with agent-browser. Observable result: The active organization label and organization-scoped page data both change.

## Gotchas

- An API response does not prove the dashboard route.
- A missing second organization is BLOCKED, not FAIL.
```

- [ ] Record proposed security panels, auto-provisioning policy, complete credential bootstrap, and the legacy SSO mismatch as catalog gaps. Do not create feature IDs.
- [ ] Keep CLI claims deferred where the legacy source contains no executable CLI user procedure. Keep third-party OAuth as a prerequisite, not a fifth medium.
- [ ] Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`. Expect PASS and a lower unmapped-scenario count without a completeness claim.
- [ ] Commit with `git commit -m "feat(verification): map dashboard identity recipes"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The map checker validates every changed recipe and source mapping. Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive `ORG-001` through agent-browser against the local dashboard with a two-organization fixture. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-4-ORG-001/`. Pass when the active organization and scoped content both change and the other organization's private data never appears.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR adds recipes and migration mappings without runtime code.

## Migrate dashboard activity and policy QA scenarios (PR-SG-5)

**Depends on.** PR-SG-4.

**Branch.** Dependent on PR-SG-4.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] The activity, attribution, audit, policy, push-correlation, and live-visualization scenarios resolve to executable dashboard recipes or named catalog gaps.

### Task 19. Map twelve activity, data, and policy QA sources

**Files.**

- Create or extend dashboard feature files for `ACT-001`, `ACT-002`, `ACT-003`, `ACT-004`, `ACT-005`, `ACT-006`, `GIT-002`, `GIT-003`, `GIT-004`, `GRD-001`, `GRD-002`, `GRD-003`, `MGT-003`, and `MGT-009` under `.agents/skills/verify-spellguard-dashboard/features/`.
- Create `docs/verification/qa-migrations/dashboard-activity-policy.json`.
- Modify `docs/verification/qa-runbook-inventory.json`.
- Test changed recipes with `.agents/skills/verify-spellguard/scripts/check.mjs`.

**Interfaces.**

- Consumes. Existing shared recipe files from PR-SG-4 and migration scenario IDs from PR-SG-3.
- Produces. Recipe identities and scenario mappings for twelve named legacy sources, including duplicate-source links to one canonical recipe.

**Steps.**

- [ ] Run `pnpm verification:migration-report --base origin/main` and save the before-count.
- [ ] Map only user-facing scenarios from `qa-access-rule-deviations`, `qa-activity-dashboard`, `qa-attribution-rollups`, `qa-audit-log-matching`, `qa-audit-log-streaming`, `qa-commit-data-model`, `qa-commits-poller`, `qa-github-webhooks`, `qa-plugin-commit-observation`, `qa-policy-consequences`, `qa-push-correlation`, and `qa-realtime-network-viz`.
- [ ] For every covered file, preserve the schema and four recipe sections from Task 18. Add all source scenario IDs that the recipe genuinely covers.
- [ ] Record poller observability, stream connection health, webhook delivery health, four evidence flags, proposed daemon panels, chat outcome, and Needs Review as catalog gaps. Keep proposed cases deferred.
- [ ] Record `qa-audit-log-streaming.md` as blocked from deletion at its reported NUL byte offset. Do not skip or normalize the source silently.
- [ ] Keep CLI TUI, CLI agent, and MCP unassessed because these twelve sources prove dashboard routes only.
- [ ] Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`. Expect PASS and a lower unmapped-scenario count.
- [ ] Commit with `git commit -m "feat(verification): map activity and policy recipes"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The checker validates recipe de-duplication, proposed-case dispositions, catalog gaps, and the byte-error record. Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive `ACT-002` and `ACT-004` through agent-browser with a seeded deviation. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-5-activity/`. Pass when the feed shows the event, acknowledgement changes its visible state, and filtering preserves the acknowledged record.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR adds recipes and migration mappings without runtime code.

## Migrate provisioning and credential QA scenarios (PR-SG-6)

**Depends on.** PR-SG-5.

**Branch.** Dependent on PR-SG-5.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Dashboard provisioning, credential, framework, live-test, and shadow-agent scenarios have catalog-linked recipes without treating infrastructure checks as user proof.

### Task 20. Map thirteen provisioning and credential QA sources

**Files.**

- Create or extend dashboard feature files for `FLT-001`, `FLT-002`, `FLT-016`, `FLT-017`, `PRV-001`, `PRV-002`, `PRV-003`, `PRV-004`, `PRV-005`, `PRV-006`, `PRV-007`, `PRV-008`, `PRV-014`, `PRV-015`, `PRV-016`, `PRV-017`, `PRV-018`, `PRV-019`, `CRD-001`, `CRD-002`, `CRD-003`, `CRD-004`, `CRD-005`, `CRD-006`, `CRD-011`, `CRD-012`, `CRD-013`, `CRD-014`, `CRD-015`, `CRD-016`, `CRD-017`, `CRD-018`, `CRD-019`, `CRD-020`, `CRD-021`, `CRD-023`, `CHN-001`, `CHN-005`, `FRM-006`, `FRM-009`, `FRM-010`, `FRM-011`, `FRM-012`, `FRM-016`, `FRM-018`, `FRM-020`, `FRM-027`, `FRM-028`, `FRM-029`, `FRM-030`, `FRM-032`, `ADV-004`, `ADV-011`, `ADV-012`, `ADV-013`, `ADV-014`, `CST-002`, and `PLT-005`.
- Create or extend `.agents/skills/verify-spellguard-cli-tui/features/FLT-002.md`, `CHN-005.md`, `PRV-003.md`, `PRV-006.md`, and `PRV-007.md`.
- Create `.agents/skills/verify-spellguard-cli-agent/features/CHN-005.md`.
- Create `docs/verification/qa-migrations/dashboard-provisioning-credentials.json`.
- Modify `docs/verification/qa-runbook-inventory.json`.
- Test changed recipes with `.agents/skills/verify-spellguard/scripts/check.mjs`.

**Interfaces.**

- Consumes. Existing shared credential and control recipes from PR-SG-4 and the cumulative migration record from PR-SG-5.
- Produces. Recipe identities and scenario mappings for thirteen named legacy sources plus explicit blocked, deferred, not-present, and catalog-gap records.

**Steps.**

- [ ] Map only user-facing scenarios from `qa-agent-reattach-and-assignment`, `qa-byok-customer-managed-keys`, `qa-cloudflare-managed-credentials`, `qa-ec2-devbox-hardening`, `qa-hermes-managed-agent`, `qa-live-agent-testing`, `qa-managed-agent-provisioning`, `qa-managed-box-stop-start`, `qa-managed-vm-operations`, `qa-multiframework-agent-box`, `qa-openrouter-credential-provisioning`, `qa-per-agent-slack-apps`, and `qa-shadow-agent-detection-aws`.
- [ ] For every covered file, preserve the schema and four recipe sections from Task 18. Make provider, entitlement, second-zone, real-agent, and real-VM prerequisites explicit.
- [ ] Record managed VM power, Codex device-auth card, Cloudflare credential lifecycle, per-user tag grants, and consumer-only OpenClaw behavior as catalog gaps. Do not create IDs for them.
- [ ] Mark `FRM-032` not present. Mark proposed BYOK dashboard work deferred. Mark live prerequisites BLOCKED only when the named resource is unavailable.
- [ ] Preserve provider operations, cloud teardown, KMS recovery, load thresholds, encryption checks, and historical results outside recipe steps.
- [ ] Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`. Expect PASS and no infrastructure-only scenario counted as user coverage.
- [ ] Commit with `git commit -m "feat(verification): map provisioning and credential recipes"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The checker validates all changed recipe files, known dispositions, named blockers, and catalog gaps. Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive the local dashboard path for `PRV-001` with a seeded provider connection and stop before any external provisioning mutation. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-6-PRV-001/`. Pass when the wizard exposes the documented framework and provider choices, or record BLOCKED with the missing local prerequisite and cleanup evidence.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR changes verification recipes and does not provision infrastructure during PR verification.

## Migrate CLI TUI and agent-mode QA scenarios (PR-SG-7)

**Depends on.** PR-SG-6.

**Branch.** Dependent on PR-SG-6.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] Interactive TTY routes and structured agent routes have separate recipes, operations, observations, and not-present dispositions.

### Task 21. Map seven CLI QA sources without collapsing media

**Files.**

- Create or extend CLI TUI feature files for `FLT-002`, `CHN-005`, `PRV-001`, `PRV-002`, `PRV-003`, `PRV-004`, `PRV-005`, `PRV-006`, `PRV-007`, `PRV-011`, `PRV-012`, `PRV-019`, `FRM-008`, `FRM-009`, `FRM-010`, and `FRM-018`.
- Create or extend CLI agent feature files for `CTL-007`, `CTL-009`, `CTL-010`, `CTL-011`, `CTL-012`, `CTL-013`, `CTL-014`, `CTL-015`, `CTL-016`, `CTL-017`, `CTL-018`, `CTL-019`, `CTL-020`, `CHN-005`, `FRM-016`, `PRV-001`, `PRV-002`, `PRV-003`, `PRV-004`, `PRV-005`, `PRV-006`, `PRV-011`, and `PRV-019`.
- Create or extend dashboard feature files for `CTL-002`, `ORG-001`, `ORG-003`, `PRV-001`, `PRV-002`, `PRV-003`, `PRV-004`, `PRV-005`, `PRV-006`, `PRV-007`, `PRV-008`, and `PRV-019`.
- Create MCP disposition files for `CTL-013`, `CTL-014`, `CTL-015`, `CTL-016`, `CTL-017`, `CTL-018`, `CTL-019`, `CTL-020`, `PRV-011`, and `PRV-012`.
- Create `docs/verification/qa-migrations/cli-tui-agent.json`.
- Modify `docs/verification/qa-runbook-inventory.json`.
- Test changed recipes with `.agents/skills/verify-spellguard/scripts/check.mjs`.

**Interfaces.**

- Consumes. The cumulative migration record from PR-SG-6 and distinct TUI and agent-mode base skills.
- Produces. Separate recipe identities for interactive TTY and structured-output routes plus explicit MCP and absent-route dispositions.

**Steps.**

- [ ] Map only user-facing scenarios from `qa-cli-agent-parity`, `qa-cli-connect-managed-agents`, `qa-cli-provision-managed-agents`, `qa-claude-code-ec2-provisioning`, `qa-codex-ec2-provisioning`, `qa-spellguard-cli-mvp`, and `qa-user-tag-warm-daemon`.
- [ ] Use this complete CLI agent recipe shape for `CTL-013`, then apply the same required sections to each covered agent file.

```markdown
---
schemaVersion: 1
catalogId: CTL-013
medium: cli-agent
disposition: covered
legacyScenarios:
  - qa-cli-agent-parity#confirmation-refusal#1
---
# Structured operation confirmation

## Sub-features

- Refuse an unconfirmed state-changing operation.
- Repeat the exact operation with explicit confirmation.

## How to get to it (user POV)

- Ask the CLI for its schema, construct the operation body, and run the operation in agent mode.

## Driving it with the Spellguard CLI

Preconditions: Run inside the disposable CLI Docker sandbox against its seeded server.

- User action: Submit the operation without confirmation. Operation: Capture stdout, stderr, JSON, and exit status without a TTY. Observable result: The CLI refuses the operation and reports the confirmation requirement with no side effect.
- User action: Repeat the same operation with explicit confirmation. Operation: Add the documented confirmation flag and capture the machine-readable result. Observable result: The CLI returns one terminal result and the seeded server records the operation exactly once.

## Gotchas

- Entering the TUI invalidates this recipe.
- Host credentials and host setup state must not change.
```

- [ ] Treat the managed-agent Connect feature as a catalog gap. Do not use `PRV-011` or `PRV-012` as a proxy for baseline Connect.
- [ ] Mark known MCP routes not present. Keep routes without evidence unassessed rather than guessing.
- [ ] Keep fake SSH, tsnet, cloud teardown, billing, provider, and reset mechanics in their operational or test documents.
- [ ] Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`. Expect PASS and no combined `CLI or TUI` value.
- [ ] Commit with `git commit -m "feat(verification): map CLI TUI and agent recipes"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The checker validates exact-media separation, non-TUI agent output, TTY proof, and known not-present routes. Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive `CTL-013` twice in the disposable Docker CLI sandbox, first without confirmation and then with it. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-7-CTL-013/`. Pass when the first call has no side effect, the second has one effect, both outputs are machine-readable, and neither enters a TUI.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR adds recipes and migration mappings without changing the CLI runtime.

## Migrate the remote MCP QA scenarios (PR-SG-8)

**Depends on.** PR-SG-7.

**Branch.** Dependent on PR-SG-7.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] MCP recipes distinguish offline parity, deployed dev-stack behavior, hosted-client proof, and production advertisement without borrowing a pass across them.

### Task 22. Map remote MCP scenarios and blockers

**Files.**

- Create or extend MCP feature files `CTL-021.md`, `CTL-022.md`, `CTL-023.md`, `CTL-024.md`, `CTL-025.md`, `CTL-026.md`, and `CTL-027.md`.
- Create `docs/verification/qa-migrations/mcp-remote.json`.
- Modify `docs/verification/qa-runbook-inventory.json`.
- Test changed recipes with `.agents/skills/verify-spellguard/scripts/check.mjs`.

**Interfaces.**

- Consumes. The cumulative migration record from PR-SG-7 and the MCP base skill's distinct proof axes.
- Produces. Seven catalog-linked MCP recipe identities plus blocked catalog-gap and hosted-client records.

**Steps.**

- [ ] Map user-facing scenarios from `qa-mcp-remote.md` separately for offline catalog parity, OAuth and consent, hosted compact tools, disconnect revocation, mutation confirmation, excluded operations, and production advertisement.
- [ ] Use this proof-axis shape in every covered MCP file.

```yaml
proofAxes:
  offlineParity: required
  deployedDevStack: required
  hostedClient: required-when-named
  productionAdvertisement: separate-gate
substitutionPolicy: forbidden
```

- [ ] Record route-level role inheritance after confirmation as a catalog gap. Keep capability IDs without a declared Spellbook join unmapped instead of using semantic guesses.
- [ ] Treat missing host entitlement, changed host UI, or unavailable production advertisement as BLOCKED. Never replace the named host with another client.
- [ ] Retain the host matrix, aggregate sweep evidence, known-blocked allowlist, vendor state, and release-gate policy outside feature recipes.
- [ ] Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`. Expect PASS with independent proof states.
- [ ] Commit with `git commit -m "feat(verification): map remote MCP recipes"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The checker validates seven catalog IDs, four proof axes, no-substitution rules, and explicit blocked states. Run `pnpm verification:check && pnpm verification:migration-report --base origin/main`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive the offline `CTL-022` search, describe, and invoke-read route and compare its result with an independent direct query. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-8-CTL-022/`. Pass when exactly three compact tools appear, the result matches, and hosted-client and production axes remain independently BLOCKED or PASS.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR changes MCP recipes and migration mappings, not gateway runtime.

## Migrate collaboration scenarios and retire procedural duplicates (PR-SG-9)

**Depends on.** PR-SG-8.

**Branch.** Dependent on PR-SG-8.

**Budget.** 74 dispatches and 4,251 wall-clock minutes remained when planning began. This PR expects 3 dispatches.

**You see.**

- [ ] All 45 procedural or mixed QA inputs have mapped recipes or explicit dispositions, active procedural duplicates are gone, and retained evidence and operations remain.

### Task 23. Map cross-agent scenarios and finish retirement

**Files.**

- Create or extend CLI agent feature files `COL-001.md`, `COL-002.md`, `COL-003.md`, `GIT-003.md`, `FRM-009.md`, and `FRM-018.md`.
- Create or extend dashboard feature files `COL-004.md`, `GIT-002.md`, `GIT-004.md`, `MGT-003.md`, `ACT-002.md`, `ACT-003.md`, `ACT-004.md`, `ACT-005.md`, and `ACT-006.md`.
- Create `docs/verification/qa-migrations/a2a-cross-agent.json`.
- Modify `docs/verification/qa-runbook-inventory.json`.
- Modify or delete only the 45 procedural or mixed inputs named by the reviewed inventory.
- Preserve the eight retained files and three classified non-feature inputs named in Appendix C.
- Test changed recipes and every source retirement with `.agents/skills/verify-spellguard/scripts/check.mjs`.

**Interfaces.**

- Consumes. The cumulative recipe and migration record from PR-SG-8.
- Produces. Final scenario mappings for `qa-a2a-collaboration-plane`, `qa-multi-agent-e2e`, and `qa-multi-agent-e2e-codex`, plus zero active procedural QA duplicates.

**Steps.**

- [ ] De-duplicate the Claude and Codex multi-agent matrices. Map configured review delivery to `COL-001` and `COL-002`, repo setup to `COL-003`, activity to `COL-004`, bypass detection to `GIT-004`, push correlation to `GIT-002`, and visible results to the listed MGT and ACT files.
- [ ] Record successful review publication, App-authored non-success publication, Codex attribution identity, and distinct-token-without-reprompt behavior as blocked catalog gaps. Do not force them into adjacent IDs.
- [ ] Keep CLI TUI unassessed and MCP not present for the explicit no-public-cancel-or-retry route. A test tmux session is not a Spellguard TUI.
- [ ] Run `pnpm verification:migration-report --base origin/main`. For each of the 45 source files, remove a procedural section only after every scenario in that section maps to a recipe identity or explicit disposition.
- [ ] Delete a pure procedural duplicate with `apply_patch`. For a mixed file, retain only its programmatic, operational, release, or historical content and reclassify it. Preserve its Git history.
- [ ] Classify `qa-adversarial-testing-framework.md` as developer test tooling, `qa-cli-tui-workbench.md` as a capture fixture, and `qa-openclaw-credential-channel.md` as a programmatic test plan. Keep them outside manual recipe coverage.
- [ ] Run `pnpm verification:check && pnpm verification:migration-report --base origin/main && pnpm verification:no-new-runbooks --base origin/main`. Expect PASS with zero unmapped retired scenarios, zero active procedural duplicates, and no coverage-completeness claim.
- [ ] Commit with `git commit -m "refactor(verification): retire migrated QA runbooks"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The final checker validates all recipe mappings, retained categories, mixed-file preservation, duplicate removal, and zero new procedural runbooks. Run `pnpm verification:check && pnpm verification:migration-report --base origin/main && pnpm verification:no-new-runbooks --base origin/main`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Drive `COL-004` through agent-browser against seeded review activity and follow its links into the mapped ACT views. Save `/home/dev/.local/state/dark-factory/runs/-home-dev-dark-factory/weekend-verification-2026-09-04/evidence/PR-SG-9-COL-004/`. Pass when dispatched and terminal review activity, the review URL, attribution, and pagination are visible without using programmatic assertions as the verdict.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR changes recipes and retires duplicate documents without changing application runtime.

## Appendix A. Prototype evidence

Nothing was prototyped. The work changes agent instructions, schemas, scripts, and documentation. It makes no user-facing graphical UI change. Live verification still drives the existing Spellguard UI where a recipe requires it.

## Appendix B. Alternatives rejected

- A repository-private Dark Factory manifest duplicates discoverable project skill data and creates a leakage path.
- Conversation-only recipe handoff cannot survive restart and lets later stages change the selected proof.
- One QA-runbook path loses additional media and duplicates executable recipes.
- One large third Spellguard PR mixes migration mechanics with 45 source documents and four media.
- Independent recipe PRs cannot safely retire shared source documents before their siblings merge. The cumulative migration record makes PR-SG-4 through PR-SG-9 a real linear dependency chain.
- A copied Spellbook description catalog would make Spellguard a second catalog owner. The committed snapshot contains identity and redirect fields only.
- A same-family Codex reviewer cannot replace the unavailable Claude leg. Review records keep that leg deferred.

## Appendix C. Risks

- PR-SB-1 is blocked. The pinned Spellguard source revision `671e4868` diverges from current `origin/main` at merge base `0c947251`. Restart with `git -C /home/dev/spellguard merge-base --is-ancestor 671e48681fa26aa7d428fc5edcb6be212ae8dd2e origin/main` after source history is reconciled.
- The eight retained QA items are `agntcy-profile-cutover.md`, `mcp-host-compatibility.json`, `qa-cross-plugin.md`, `qa-hybrid-dev-workflow.md`, `qa-managed-box-stop-start-results-2026-08-10T10-15-00Z.md`, `qa-managed-box-stop-start-results-latest.md`, `qa-managed-box-stop-start-results-latest.txt`, and `qa-validation-consolidated-agent-socket.md`.
- The three reviewed non-feature inputs are `qa-adversarial-testing-framework.md`, `qa-cli-tui-workbench.md`, and `qa-openclaw-credential-channel.md`. They remain test tooling, a fixture, and a programmatic plan.
- The NUL byte in `qa-audit-log-streaming.md` blocks deletion until the migration reader reports and the implementation safely removes it.
- Recipe batches use cumulative migration state and repeated feature files. Implement them in plan order and register PR-SG-1 through PR-SG-9 as one native stack only after every ordinary PR base matches the preceding branch.
- PR-DF-A1 through PR-DF-A2 and PR-DF-B1 through PR-DF-B5 through PR-DF-C are the other native stack candidates.
- PR-DF-B2, PR-DF-B3, PR-DF-B4, and PR-DF-B6 are plain dependent siblings of PR-DF-B1. Do not register a false linear stack.
- A cascading GitHub rebase changes a head SHA. Rerun the branch's review, live verification, and CI gates for the new SHA.
- PR-SG-6 must not provision cloud infrastructure during this run. Its live proof stops at the local wizard and records a missing prerequisite as BLOCKED.
- Hosted MCP entitlement and production advertisement may stay BLOCKED. Offline parity cannot clear those axes.
- Generated inventory is not complete product coverage. Missing feature-medium pairs remain unassessed.

## Appendix D. Requirement trace

- REQ-001 and NEG-001 map to Tasks 2 and 3.
- REQ-002 maps to Tasks 13 through 16.
- REQ-003 and NEG-002 map to Tasks 13 through 16 and 18 through 23.
- REQ-004, NEG-004, and NEG-008 map to Tasks 2, 11, and 12.
- REQ-005 and NEG-005 map to Tasks 8, 17, and 18 through 23.
- REQ-006 and NEG-006 map to Tasks 4 through 9.
- REQ-007, NEG-003, and NEG-007 map to Tasks 12 through 23.
- REQ-008 maps to Task 2.
- REQ-009 and NEG-009 map to every task's Budget and verification blocks.
- REQ-010 maps to Tasks 18 through 23 and the single-owner cumulative migration record.
