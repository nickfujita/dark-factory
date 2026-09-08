# Project-independent verification lifecycle plan

> df-implement executes this plan task by task. Never hand it to any other execution skill.

This draft contains 10 Dark Factory delivery units. It is not an execution approval. Concrete project adoption and migration batches belong outside this repository.

**Goal.** Implement restart-safe role resolution and a project-independent verification lifecycle.
**Spec.** `docs/prd-verification-system.md`
**Design.** `docs/design-verification-system.md`
**Lane.** Standard.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. Check a box only when its evidence exists, a file, a log line, a test run, a screenshot, or a commit SHA. The body is a how-to. The appendices explain and record.

df-implement executes this plan task by task. The operator merges every PR.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Global constraints

- Media are exact identifiers declared by the consuming project. Use synthetic fixtures for one medium and multiple distinct media.
- Every delegated dispatch reserves a run-state sequence before it starts.
- Review-family constraints and execution budgets are external run inputs. Never claim diversity from same-family contexts.
- Dark Factory shipped role policy resolves every declared responsibility without an override.
- Project role values override machine role values. Machine role values override shipped defaults.
- The machine override path is `${XDG_CONFIG_HOME:-$HOME/.config}/dark-factory/config.json`.
- The tracked project override path is `.agents/dark-factory.json`. It may contain role targets only.
- The consuming project owns feature identity, optional catalog linkage, skills, recipes, dispositions, and migration checks.
- Recipe paths and medium identifiers come from project declarations. Synthetic paths exercise the contract without a real application checkout.
- A missing recipe is unassessed. It is never inferred to mean not present.
- A recipe is not acceptance evidence. A live drive writes separate PASS, FAIL, or BLOCKED evidence.
- Before dependent implementation or publication, finish the lower PR's implementation, local verification, code review, and required CI at its exact head. Human review or merge may remain pending.
- Keep incomplete PRs draft. Mark locally complete PRs ready and own final CI. Record evidence-backed `NOT_CONFIGURED` where no required CI exists.
- Do not add or change CI workflow files without separate operator approval.
- Do not merge, deploy, rotate credentials, force-push, or remove unrelated local files.

## Review the reusable planning record (PR-DF-P0)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

**You see.**

- [ ] The branch contains a project-independent PRD, design, and implementation plan with no adoption inventory.

### Task 1. Record the reusable requirements and design

**Files.**

- Create `docs/prd-verification-system.md`.
- Create `docs/design-verification-system.md`.
- Create `docs/implementation-plan-verification-system.md`.
- Test `skills/df-plan/scripts/check-plan.mjs` against this plan.

**Interfaces.**

- Consumes. The reusable requirements and repository ownership rules in `AGENTS.md`.
- Produces. The normative requirements in `docs/prd-verification-system.md` and the implementation interfaces in `docs/design-verification-system.md`.

**Steps.**

- [ ] Verify that both documents require project-declared media and external run constraints.

```bash
rg -n 'project|medium|run' \
  docs/prd-verification-system.md docs/design-verification-system.md
```

- [ ] Run `git diff --check`. Expect PASS.
- [ ] Commit the PRD with `git commit -m "docs: add verification system PRD"`.
- [ ] Commit the design with `git commit -m "docs: add verification system design"`.
- [ ] Commit the checked plan with `git commit -m "docs: add verification system implementation plan"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] The checked plan accepts all delivery blocks. Run `node skills/df-plan/scripts/check-plan.mjs docs/implementation-plan-verification-system.md`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Render both documents and check current reference links. Distinguish proposed implementation paths from files that must already exist. Save `<run-dir>/evidence/PR-DF-P0-links.txt`. Pass when current reference links resolve and proposed paths are explicitly identified as future deliverables.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR changes planning documents only.

## Resolve every delegation role (PR-DF-A1)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

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

- Consumes. `prepareRunRolePlan({runId, harness, repoRoot}): FrozenRolePlan` from the proposed design.
- Produces. CLI commands `prepare-run --run --harness --repo-root`, `resolve --run --responsibility --lane`, and `preflight --run --responsibility --lane`.

**Steps.**

- [ ] Write the failing role-policy test with these cases.

```text
shipped policy resolves every responsibility and lane pair for each harness
missing mapping reports the exact responsibility and lane before reservation
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

- [ ] Make `prepare-run` write `work/role-plan.json` beneath the external run directory with the policy digest, harness, and every responsibility-by-lane resolution with provenance. Freeze all supported lanes for the selected harness, with no singular lane field. Require an explicit lane on resolve and preflight. Use an atomic temporary-file rename.
- [ ] Make `resolve` read only the frozen plan. Make `preflight` verify named-agent definitions before any reservation.
- [ ] Run `bash scripts/test-df-role-policy.sh`. Expect PASS.
- [ ] Run `just check-role-policy && just check-parity && just check-plugins && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "feat(df): resolve delegation roles from layered policy"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-role-policy.sh` gains all eight cases above. Run `bash scripts/test-df-role-policy.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Prepare a disposable run, resolve `design_runners`, then point an override at a missing named agent and prove preflight stops before reservation. Save `<run-dir>/evidence/PR-DF-A1-live.txt`. Pass when the first output names `terra_xhigh`, the second output names the bad agent, and the run's reserved count does not change.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Role resolution runs once per run and preflight reads small local files.

## Adopt resolved roles in every runner (PR-DF-A2)

**Depends on.** PR-DF-A1.

**Branch.** Dependent on PR-DF-A1.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

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

- [ ] Start a disposable planning dispatch through the Codex path with a fake worker command. Save `<run-dir>/evidence/PR-DF-A2-live.txt`. Pass when the log orders role preflight before reservation before worker start and records no runner-local effort flag.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. The change replaces local argument selection with one local policy read.

## Seal plural verification selections (PR-DF-B1)

**Depends on.** None.

**Branch.** Independent from main.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

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

- Consumes. `sealSelection({runId, draftPath, repoRoot}): SelectionRef`, `openSelection({ref, repoRoot}): VerificationSelection`, and `materializeSelection({ref, repoRoot, consumer}): readonly SelectionEntry[]`. The consumer is exactly `qa-validation`, `dev-verify`, `code-review`, or `acceptance`.
- Produces. CLI commands `seal --run --draft --repo-root`, `inspect --ref --repo-root`, and `materialize --ref --repo-root --consumer --format`. JSON format emits the validated entry array. Paths format emits its recipe identities.

**Steps.**

- [ ] Write the failing selection test with these cases.

```text
canonical sort gives identical digests for reordered entries
user-facing selection rejects zero entries
no-user-route selection accepts zero entries and a reason
medium accepts every project-declared identifier and rejects undeclared identifiers
duplicate entry IDs and duplicate recipe identities fail
recipe, skill, PRD, and configured catalog-link digest drift each fail; null catalog is valid
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
  "prdPath": "string",
  "prdSha256": "64 lowercase hex",
  "catalogLink": null,
  "entries": [{
    "id": "string",
    "medium": "project-declared identifier",
    "skillPath": "string",
    "skillSha256": "64 lowercase hex",
    "recipePath": "string",
    "subFeature": null,
    "recipeSha256": "64 lowercase hex",
    "requirementIds": ["REQ-000"],
    "negativeRequirementIds": ["NEG-000"]
  }]
}
```

- [ ] For a configured catalog, replace `catalogLink: null` with an object containing `path` and `sha256`, as defined in the design. For a selected sub-feature, replace `subFeature: null` with its string identifier. The `no-user-route` union member keeps schemaVersion, runId, featureSlug, prdPath, and prdSha256, sets kind to `no-user-route`, requires reason, has an empty entries array, and has no catalogLink field.
- [ ] Canonicalize object keys and entries before hashing. Use the computed digest as the JSON filename beneath `verification-selections/` in the external run directory. Write through an atomic rename.
- [ ] Reject path traversal, absolute repository paths, digest mismatch, invalid media, unsealed input, and any discovery fallback.
- [ ] Run `bash scripts/test-df-selection.sh && just check-parity && just check-plugins && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "feat(df): seal plural verification selections"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-selection.sh` gains the ten cases above. Run `bash scripts/test-df-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Seal a two-medium fixture, materialize it, alter one recipe byte, and materialize it again. Save `<run-dir>/evidence/PR-DF-B1-live.txt`. Pass when the first read returns both entries and the second fails with the changed recipe path and expected digest.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Selection files are bounded run metadata and use local hashing.

## Validate requirements against the sealed selection (PR-DF-B2)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

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

- Consumes. `SelectionRef` and `df-selection.mjs materialize --ref string --repo-root string --consumer qa-validation --format json`.
- Produces. `run_codex_qa_validation.sh PRD_PATH SELECTION_REF REPO_ROOT OUTPUT_DIR` and a report header containing the selection digest.

**Steps.**

- [ ] Write a failing runner fixture that passes two recipes, rejects a legacy QA path, preserves both recipe identities in the prompt, and refuses digest drift.
- [ ] Run `bash scripts/test-df-qa-selection.sh`. Expect FAIL because the runner still accepts one QA-runbook path.
- [ ] Change the runner usage to this exact boundary.

```text
usage: run_codex_qa_validation.sh PRD_PATH SELECTION_REF REPO_ROOT OUTPUT_DIR
```

- [ ] Materialize before any reviewer starts. If an auto-fix changes a selected recipe, stop and return `RESEAL_REQUIRED` with that recipe path.
- [ ] Record any unavailable review leg with its actual reason from external run state. Never label same-family passes model-diverse.
- [ ] Run `bash scripts/test-df-qa-selection.sh && just check-parity && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "refactor(qa): validate the sealed recipe selection"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-qa-selection.sh` gains multi-recipe, legacy-argument, drift, and reseal cases. Run `bash scripts/test-df-qa-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run QA validation against synthetic project recipes spanning multiple declared media. Save `<run-dir>/evidence/PR-DF-B2-live.txt`. Pass when the report contains every selected identity, one selection digest, and accurate review provenance.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Prompt materialization adds bounded local file reads.

## Review code against the sealed selection (PR-DF-B3)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

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

- Consumes. `SelectionRef` and `df-selection.mjs materialize --ref string --repo-root string --consumer code-review --format json` from PR-DF-B1.
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

- [ ] Review a disposable two-recipe fixture through the Codex spec-review path. Save `<run-dir>/evidence/PR-DF-B3-live.txt`. Pass when the prompt and report retain both recipe identities and reject a substituted path.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. The review already reads bounded PRD and recipe inputs.

## Drive only the selected user routes (PR-DF-B4)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

**You see.**

- [ ] Developer verification drives each selected medium and cannot rediscover, widen, or silently skip the list.

### Task 7. Convert developer verification to a closed selection

**Files.**

- Modify `skills/df-dev-verify/SKILL.md`, lines 14 to 306.
- Modify `codex-plugin/skills/df-dev-verify/SKILL.md`, lines 13 to 312.
- Create `scripts/test-verification-selection-flow.sh`.
- Test `scripts/test-verification-selection-flow.sh`.

**Interfaces.**

- Consumes. One `SelectionRef` through `df-selection.mjs materialize --ref string --repo-root string --consumer dev-verify --format json`, returning the selected entries.
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

- [ ] Drive a sealed selection against disposable synthetic user routes. Save `<run-dir>/evidence/PR-DF-B4-live.json`. Pass when one terminal record exists per selected recipe and each names its actual medium.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. User-route latency belongs to each project recipe rather than the lifecycle iterator.

## Require project recipe migration evidence (PR-DF-B5)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

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

- Consumes. Project-declared `media` and `recipes`, plus optional catalog and migration-check inputs.
- Produces. One validated draft for PR-DF-B1 sealing and one migration readiness value among `ready`, `pending`, and `blocked`.

**Steps.**

- [ ] Write a failing fixture for a two-medium project with one covered recipe, one deferred disposition, one unmapped legacy scenario, and one undeclared medium. Include a no-catalog project.
- [ ] Run `bash scripts/test-df-coverage-selection.sh`. Expect FAIL because coverage returns a conversation-only entry list.
- [ ] Make coverage validate project-declared media, bidirectional REQ and NEG links, optional catalog linkage, recipe hashes, and project migration status before it calls `df-selection.mjs seal`.
- [ ] Make missing or stale project skills route to the creator or maintainer. Neither skill may invent catalog IDs or migration dispositions.
- [ ] Treat an unmapped legacy scenario as pending migration. Block only deletion or a completeness claim, not unrelated recipe authoring.
- [ ] Run `bash scripts/test-df-coverage-selection.sh && just check-parity && just check-shell`. Expect PASS.
- [ ] Commit with `git commit -m "feat(coverage): seal project recipe selections"`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `scripts/test-df-coverage-selection.sh` gains exact-medium, catalog, plural recipe, legacy scenario, and no-invention cases. Run `bash scripts/test-df-coverage-selection.sh`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Run coverage against a synthetic project index and migration-check results. Save `<run-dir>/evidence/PR-DF-B5-live.txt`. Pass when declared media resolve, smoke entries seal, gaps stay unassessed, and pending legacy scenarios do not become covered.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Coverage reads committed metadata once before sealing.

## Record one acceptance verdict per recipe (PR-DF-B6)

**Depends on.** PR-DF-B1.

**Branch.** Dependent on PR-DF-B1.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

**You see.**

- [ ] Acceptance drives the exact sealed entries and writes one immutable external verdict for each entry.

### Task 9. Convert acceptance to a selection consumer

**Files.**

- Modify `skills/df-acceptance/SKILL.md`, lines 19 to 243.
- Modify `codex-plugin/skills/df-acceptance/SKILL.md`, lines 19 to 243.
- Create `scripts/test-df-acceptance-selection.sh`.
- Test `scripts/test-df-acceptance-selection.sh`.

**Interfaces.**

- Consumes. One `SelectionRef` through `df-selection.mjs materialize --ref string --repo-root string --consumer acceptance --format json`, returning the selected entries.
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

- [ ] Drive a synthetic multi-medium selection and inspect its external evidence directory. Save `<run-dir>/evidence/PR-DF-B6-live.txt`. Pass when every selected recipe has one terminal record with the same selection digest and no target-repository evidence file appears.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. Each selected recipe owns its own latency and readiness threshold.

## Retire stale lifecycle vocabulary (PR-DF-C)

**Depends on.** PR-DF-B5.

**Branch.** Dependent on PR-DF-B5.

**Budget.** This repository-level draft allocates no run budget. Record an operator-approved budget in external state before execution.

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

- [ ] Follow the feature playbook from coverage through acceptance with the names only, using a disposable fixture project. Save `<run-dir>/evidence/PR-DF-C-live.txt`. Pass when every stage hands off one `SelectionRef` and no instruction asks for a QA-runbook path.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Not perf-sensitive. This PR changes living instructions and static contract checks.

## Appendix A. Ownership and approval

This plan proposes Dark Factory changes only. Catalog reconciliation, concrete
base skills, application recipes, migration inventories, deployments, and
product acceptance belong to their consuming repositories or external runs.
They are not dependencies of Dark Factory's synthetic contract checks.

The existing role and selection interfaces remain proposed work. This scope
correction preserves their implementation sequence without claiming completion.
Ten tasks exceed the plan checker's eight-task threshold. Execution requires
fresh operator approval and an external budget after this revised plan is
reviewed. Documentation review alone does not authorize implementation.

## Appendix B. Requirement traceability

| Requirement | Dark Factory delivery units |
|---|---|
| REQ-001, REQ-008 | PR-DF-A1, PR-DF-A2 |
| REQ-002, REQ-003 | PR-DF-B1, PR-DF-B4, PR-DF-B5, PR-DF-B6 |
| REQ-004, REQ-005, REQ-007 | PR-DF-B1, PR-DF-B5 |
| REQ-006 | PR-DF-B1 through PR-DF-B6, PR-DF-C |
| REQ-009, REQ-011 | PR-DF-P0 and each unit's publication gate |
| REQ-010 | PR-DF-B5 contract; concrete recipe expansion stays project-owned |
