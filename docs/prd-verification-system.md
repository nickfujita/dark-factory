# PRD: Cross-Repository Verification System

**Status:** Approved
**Lane:** Standard
**Effort-Anchor:** 72 hours
**Author:** nickfujita (Spellguard:agent-a3914910)
**Date:** 2026-09-04
**Last Updated:** 2026-09-04
**Feature ID:** verification-system

## Pinned Parameters

| Parameter | Value | Applies to |
|-----------|-------|------------|
| `SUPPORTED_MEDIA` | `{dashboard, cli-tui, cli-agent, mcp}` (4) | REQ-002, REQ-003, and REQ-006 handoff identifiers |
| `SMOKE_RECIPES_PER_MEDIUM` | 1 | REQ-002 initial proof of each base verification skill |
| `READINESS_DEADLINE` | 90 seconds per readiness signal | REQ-002 launch and doctor boundary |
| `DISPATCH_BUDGET` | 96 | REQ-009 weekend run |
| `WALL_CLOCK_BUDGET` | 4,320 minutes | REQ-009 weekend run |
| `CLAUDE_CALL_BUDGET` | 0 | REQ-009 review constraint |

**Reading conventions.** Requirements and Negative Requirements are normative.
Acceptance criteria, Edge Cases, the Glossary, and examples are satellites:
they may repeat a value, and they may never restate a rule or introduce behavior
that has no normative home.

## Purpose

Spellguard has multiple user-facing interaction media, but its manual QA
knowledge is split across legacy runbooks and an early product catalog. Dark
Factory cannot reliably hand a completed change to a fresh agent and obtain an
honest user-perspective verdict unless every relevant medium has a reusable
driver, discoverable feature recipes, and traceable coverage.

This work establishes that verification system across Dark Factory, Spellbook,
and Spellguard. It treats committed verification recipes as the agent-readable
equivalent of a human QA team's feature runbooks. The recipes complement
automated unit, integration, and end-to-end tests; they do not replace them.
Coverage begins with the existing QA knowledge and grows cumulatively with
product changes instead of claiming immediate product-wide completeness.

## Scope

### In Scope

- A complete Dark Factory role-selection contract with working defaults for
  every background-agent responsibility used by the workflow.
- A machine-local configuration override path that can change eligible defaults
  without requiring each target repository to ignore a private config file.
- A Spellguard verification entry point and one base verification skill for
  each supported user-facing medium.
- Per-medium feature maps whose entries explain how an uninformed end user
  performs a feature and observes the expected result.
- Traceability from Spellguard feature recipes to the canonical Spellbook
  catalog, including an auditable pinned catalog reference in Spellguard.
- Migration of legacy procedural QA runbooks into the feature maps, followed by
  retirement of migrated procedural duplicates.
- Dark Factory planning, coverage, developer-verification, QA-validation,
  code-review, and acceptance behavior that consumes committed recipes.
- Honest reporting of present coverage, missing media, deferred scenarios, and
  blockers.
- Locally and CI-verified pull requests, using native GitHub stacks only where
  branches have genuine dependencies.

### Out of Scope

- Merging pull requests or stacks.
- Deploying Dark Factory, Spellbook, or Spellguard changes.
- Creating, rotating, repairing, or substituting credentials.
- Replacing automated unit, integration, or end-to-end testing with agent-driven
  verification.
- Claiming complete Spellguard product coverage during the initial migration.
- Deleting historical acceptance evidence or operational runbooks that are not
  procedural feature-testing duplicates.
- Requiring a repository-private feature-catalog location in global Dark
  Factory configuration.
- Encoding implementation internals in end-user feature recipes.
- Treating independent branches as a synthetic linear stack.

## Requirements

### REQ-001: Complete Agent-Role Resolution

**Priority:** P0

Behavior:
1. Every Dark Factory responsibility that delegates background work resolves to
   a named agent role and effort level before dispatch.
2. The shipped defaults resolve every supported responsibility without a
   project-local or machine-local configuration file.
3. Every runner uses the resolved role and effort instead of a separate
   hard-coded model selection.
4. A run fails before dispatch when a selected named agent is unavailable.

Acceptance:
- The role-policy validator exits successfully against the shipped defaults.
- The role-policy validator reports the responsibility name when a required
  mapping is absent.
- A runner preflight reports the selected named agent before its first
  background dispatch.
- A runner with an unavailable named agent stops before reserving or starting a
  background dispatch.

---

### REQ-002: Verification Skills for Every Supported Medium

**Priority:** P0

Behavior:
1. Spellguard exposes one base verification skill for each member of
   `SUPPORTED_MEDIA`.
2. Each base skill defines `Launch`, `Doctor`, `Drive`, `Evidence`, and
   `Cleanup` sections for its medium.
3. Each base skill delegates feature-specific actions and expected outcomes to
   committed feature-map entries.
4. Each base skill includes at least `SMOKE_RECIPES_PER_MEDIUM` live-drive
   recipe that proves the driver reaches the intended surface.
5. Each `Launch` readiness signal resolves within `READINESS_DEADLINE`; when it
   does not, the skill runs `Cleanup` and records BLOCKED with the timeout
   evidence.

Acceptance:
- The verification index resolves exactly one base skill for each supported
  medium.
- Each base skill's readiness procedure distinguishes an unavailable surface
  from a product failure.
- Each base skill produces a PASS evidence record from its committed smoke
  recipe.
- A readiness signal that exceeds `READINESS_DEADLINE` produces a BLOCKED
  evidence record and runs the skill's cleanup procedure.
- Each base skill's cleanup procedure leaves no verification-owned live session.

---

### REQ-003: End-User Feature Recipes

**Priority:** P0

Behavior:
1. A feature-map entry contains `Sub-features`, `How to get to it (user POV)`,
   `Driving it with <harness>`, and `Gotchas` sections.
2. `How to get to it (user POV)` lists every supported user entry point for the
   feature.
3. `Driving it with <harness>` contains one `Preconditions:` line and labeled
   bullets that pair each user-visible action with the exact medium operation
   and observable expected result.
4. A feature-map entry may describe sub-features when they are independently
   observable parts of the same user capability.
5. A recipe identity is its repository-relative feature-map path plus an
   optional `#sub-feature` suffix.
6. A cataloged feature records an explicit disposition for every applicable
   supported medium: covered, not present, deferred, or blocked.
7. A changed user-visible behavior updates or adds its relevant feature-map
   entries during planning and commits those entries with the change.
8. Recipes remain independent from implementation internals and are executable
   by a fresh verifier with no development context.

Acceptance:
- A recipe checker rejects an entry missing any required section.
- A recipe checker rejects an entry missing its `Preconditions:` line.
- A recipe checker rejects a driving bullet missing its user action.
- A recipe checker rejects a driving bullet missing its exact medium operation.
- A recipe checker rejects a driving bullet missing its observable result.
- A coverage report distinguishes not-present, deferred, and blocked from
  covered.
- A fresh verification agent can execute a sampled recipe using only the base
  skill, feature-map entry, and declared operator-local prerequisites.

---

### REQ-004: Canonical Catalog Traceability

**Priority:** P0

Behavior:
1. Spellbook remains the canonical source of Spellguard product feature
   identity and product-level description.
2. Spellguard commits both the Spellbook catalog revision used by its
   verification maps and the Spellguard product-source revision recorded by
   that catalog revision.
3. The catalog revision resolves in the Spellbook repository and is never used
   in a Spellguard ancestry comparison.
4. The product-source revision resolves in the Spellguard repository and is an
   ancestor of or equal to the Spellguard base revision the coverage report
   claims.
5. A coverage report whose Spellguard base contains later user-facing changes
   than the product-source revision is marked stale until those changes are
   reviewed into the catalog.
6. The catalog inventory used for reconciliation is generated by a committed
   command and reviewed before use.
7. Verification entries reference stable catalog feature identities instead of
   duplicating canonical product descriptions.
8. Catalog redirects and consolidations remain distinguishable from verified
   feature coverage.

Acceptance:
- The catalog-reference check reports the Spellbook repository and catalog
  revision.
- The catalog-reference check reports the Spellguard repository and
  product-source revision.
- The ancestry check compares only the product-source revision with the
  Spellguard base revision.
- The reconciliation command fails when a referenced catalog feature identity
  does not exist at the catalog revision.
- The reconciliation command reports catalog redirects separately from
  verification coverage.
- Repeating reconciliation at the same catalog revision yields the same feature
  inventory.

---

### REQ-005: Legacy QA Runbook Migration

**Priority:** P0

Behavior:
1. Existing procedural feature QA runbooks are treated as migration inputs, not
   as current proof artifacts.
2. A procedural QA runbook is removed only after every unique user scenario it
   contains has a corresponding committed feature recipe or an explicit
   disposition.
3. Historical acceptance evidence and operational runbooks remain intact.
4. A repository check prevents new standalone procedural feature QA runbooks
   after the migration gate is active.
5. The migration inventory is generated by a committed command and reviewed
   before use.

Acceptance:
- The migration report maps every inventoried procedural QA scenario to a
  recipe identity or explicit disposition.
- The migration check rejects removal of a runbook that still owns an unmapped
  unique scenario.
- The repository check rejects a newly added standalone procedural feature QA
  runbook.
- The repository check accepts historical evidence and operational runbooks
  outside the procedural feature-testing category.

---

### REQ-006: Dark Factory Verification Lifecycle

**Priority:** P0

Behavior:
1. Planning identifies each changed user-visible behavior and every supported
   medium on which it is present.
2. Planning and coverage use only the exact identifiers in `SUPPORTED_MEDIA`;
   the combined identifier `CLI or TUI` is invalid and is split into `cli-tui`
   and `cli-agent` according to the user route.
3. A discovered user-facing medium outside `SUPPORTED_MEDIA` blocks the handoff
   pending an explicit scope decision.
4. A user-facing requirement cannot use `UNTESTABLE` or programmatic-only
   coverage to pass the handoff; it needs a committed recipe or the handoff is
   blocked.
5. Verification coverage resolves committed recipe identities for every
   applicable changed medium before implementation proceeds.
6. QA validation checks the requirements against those same recipe identities.
7. Developer verification drives those recipes on their declared user-facing
   surfaces after automated tests pass.
8. Code review reads the same verification selection and reports disagreement
   between the code change, requirements, and recipes.
9. Acceptance drives the committed recipes and records immutable PASS, FAIL, or
   BLOCKED evidence.
10. The lifecycle supports more than one selected recipe and more than one
   medium for a single product change.

Acceptance:
- A multi-medium change produces one run-scoped verification selection containing
  every applicable recipe identity.
- Coverage rejects `CLI or TUI` as a selection medium.
- Coverage blocks when a changed user-facing route uses a medium outside
  `SUPPORTED_MEDIA`.
- Coverage blocks a user-facing requirement whose only disposition is
  `UNTESTABLE` or programmatic-only coverage.
- Coverage stops when an applicable changed medium has no committed recipe or
  explicit non-coverage disposition.
- QA validation consumes the run-scoped verification selection without
  substituting a legacy QA-runbook path.
- Developer verification records the driven surface for each selected recipe.
- Code review consumes the same recipe identities selected by coverage.
- Acceptance records one terminal verdict for every selected recipe.

---

### REQ-007: Honest and Cumulative Coverage

**Priority:** P0

Behavior:
1. Coverage reports state what is currently proven without presenting catalog
   redirects, automated-test presence, or documentation presence as manual
   verification coverage.
2. Missing coverage is visible by catalog feature and supported medium.
3. Each new or modified user-visible feature increases coverage or records why
   the applicable recipe cannot yet be added.
4. Initial migration prioritizes scenarios already present in legacy QA
   runbooks and a live smoke recipe for each base medium.

Acceptance:
- The coverage report contains separate counts for covered, not present,
  deferred, and blocked dispositions.
- The coverage report identifies uncovered applicable feature-medium pairs.
- Adding a catalog redirect without a recipe does not increase the covered
  count.
- Removing a covered recipe without a replacement or explicit disposition makes
  the coverage check fail.

---

### REQ-008: Machine-Local Configuration Overrides

**Priority:** P1

Behavior:
1. Dark Factory may read machine-local overrides for eligible workflow defaults
   from a documented location outside target repositories.
2. A project-local override takes precedence over the matching machine-local
   value, which takes precedence over the shipped default.
3. Repository-specific catalog references remain committed with the project's
   verification system rather than stored in machine-local workflow config.
4. Invalid overrides fail with the config source and field named.

Acceptance:
- With no override files, the resolver returns the shipped default.
- With only a machine-local override, the resolver returns the machine-local
  value.
- With both override levels, the resolver returns the project-local value.
- A malformed override reports its file path and invalid field.
- No committed target-repository ignore rule is required for machine-local
  configuration.

---

### REQ-009: Reviewable Weekend Delivery

**Priority:** P0

Behavior:
1. The run reserves every delegated dispatch against `DISPATCH_BUDGET` before
   starting it.
2. The run stops new work when `DISPATCH_BUDGET` or `WALL_CLOCK_BUDGET` is
   exhausted.
3. The run makes no Claude model call because `CLAUDE_CALL_BUDGET` is zero.
4. Required unavailable Claude review legs are recorded as deferred rather than
   represented as completed model-diverse review.
5. Every pull-request block in the checked implementation plan is a planned
   delivery unit and ends with an open locally verified pull request or a
   recorded blocker and restart procedure.
6. Work discovered after plan approval becomes a planned delivery unit through
   a checked plan amendment before implementation starts.
7. A branch is registered in a native GitHub stack only when it depends on its
   parent branch's content.
8. Pull requests remain unmerged and no deployment or credential mutation is
   performed.

Acceptance:
- Run state reports no unreserved background dispatch.
- Review records label fresh Codex contexts as context diversity rather than
  model diversity.
- Every opened pull request names its local checks and current CI status.
- Every blocked unit names the failed command, authoritative error, preserved
  work, and exact restart command.
- Every pull-request block in the checked plan has exactly one open-PR or
  blocked disposition at handoff.
- The native-stack registry contains no independent branch relationship.
- GitHub reports every created pull request as open and unmerged at handoff.

---

### REQ-010: Catalog-Wide Expansion After Foundation

**Priority:** P1

Behavior:
1. Recipe authoring can fan out by disjoint catalog feature family after the
   verification index, base skills, traceability checks, and migration rules are
   established.
2. A single coordinator owns shared generated indexes and aggregate reports
   while parallel authors own disjoint recipe files.
3. Expansion continues across pull requests until product coverage approaches
   completeness without converting an unreviewed generated inventory into a
   completeness claim.

Acceptance:
- Parallel authoring assignments have no shared recipe-file ownership.
- Shared generated indexes have one named owner per update wave.
- Every expansion pull request increases covered feature-medium pairs or closes
  a recorded disposition gap.
- The aggregate report never labels an unreviewed inventory as complete
  coverage.

## Negative Requirements

### NEG-001: Do Not Bypass Role Policy

**Related to:** REQ-001

- A runner must not select a model or effort through a private fallback that
  bypasses resolved role policy.
- Missing named agents must not silently fall back to an unapproved role.

---

### NEG-002: Do Not Collapse Media

**Related to:** REQ-002, REQ-003

- Procedures for distinct user-facing media must not be represented as one
  generic recipe when their user actions or observations differ.
- A feature absent from a medium must not be counted as covered on that medium.
- `CLI or TUI` must not appear as a verification-selection medium.
- A user-facing medium outside `SUPPORTED_MEDIA` must not be silently ignored
  or treated as covered.

---

### NEG-003: Do Not Confuse Documentation with Evidence

**Related to:** REQ-003, REQ-007

- The existence of a recipe must not be reported as a passing live verification.
- Automated-test coverage must not be reported as agent-driven acceptance.

---

### NEG-004: Do Not Fork the Product Catalog

**Related to:** REQ-004, REQ-008

- Spellguard must not become a second canonical product-feature catalog.
- Machine-local Dark Factory configuration must not own project catalog paths or
  feature identities.

---

### NEG-005: Do Not Delete Unique QA Knowledge

**Related to:** REQ-005

- Migration must not delete a procedural QA runbook while it contains a unique
  unmapped user scenario.
- Migration must not delete historical evidence or operational procedures.

---

### NEG-006: Do Not Reintroduce Legacy Selection

**Related to:** REQ-006

- A lifecycle stage must not use a legacy QA-runbook path when a run-scoped
  verification selection exists.
- A single-recipe assumption must not discard additional applicable media.

---

### NEG-007: Do Not Overstate Coverage

**Related to:** REQ-007, REQ-010

- A catalog consolidation or redirect must not count as verification coverage.
- The first migration batches must not be described as full product coverage.

---

### NEG-008: Do Not Require Private Repo Config

**Related to:** REQ-008

- Machine-local preferences must not require an ignored configuration file in
  every target repository.
- Project-local reproducibility data must not be moved into uncommitted
  machine-local configuration.

---

### NEG-009: Do Not Exceed Run Authority

**Related to:** REQ-009

- The run must not merge, deploy, change credentials, force-push, or perform
  destructive cleanup.
- The run must not claim a skipped Claude leg supplied model diversity.

## Edge Cases

| Requirement | Edge Case | Expected Behavior |
|-------------|-----------|-------------------|
| REQ-001 | A named role exists in policy but its local agent definition is absent. | Preflight names the missing agent and stops before dispatch. |
| REQ-001 | No machine-local or project-local config exists. | Every responsibility resolves from shipped defaults. |
| REQ-002 | A surface cannot start because a prerequisite service is unavailable. | Readiness reports BLOCKED and does not label the product behavior FAIL. |
| REQ-002 | A readiness signal does not arrive within `READINESS_DEADLINE`. | The skill records timeout evidence, runs Cleanup, and reports BLOCKED. |
| REQ-002 | Cleanup runs after a failed recipe. | Verification-owned sessions are still closed or explicitly reported as preserved. |
| REQ-003 | A feature exists on the dashboard but not through MCP. | Dashboard may be covered and MCP is recorded as not present. |
| REQ-003 | One feature has independently observable sub-features. | The entry names each sub-feature and its observation without creating unrelated catalog identities. |
| REQ-004 | The product-source revision predates user-facing changes on the Spellguard base. | Reconciliation marks the coverage report stale until those changes are reviewed into the catalog. |
| REQ-004 | The Spellbook catalog revision and Spellguard product-source revision differ. | Each resolves in its own repository; no cross-repository ancestry comparison is attempted. |
| REQ-004 | A catalog identity redirects to another identity. | Reconciliation records the redirect without counting it as a verified recipe. |
| REQ-005 | A legacy file mixes procedural scenarios with operational recovery steps. | Only migrated procedural content is retired; operational content remains in an appropriate document. |
| REQ-005 | Two runbooks describe the same scenario. | Migration records one canonical recipe and both source mappings before duplicate removal. |
| REQ-006 | A change affects two supported media. | Selection, validation, developer verification, review, and acceptance retain both recipe identities. |
| REQ-006 | Existing coverage classifies a route as `CLI or TUI`. | The handoff blocks until the route is split into `cli-tui` or `cli-agent`. |
| REQ-006 | A user-facing API or desktop route is discovered. | The handoff blocks for an explicit decision because the medium is outside `SUPPORTED_MEDIA`. |
| REQ-006 | Automated tests pass but a live recipe fails. | The unit remains unverified and is not handed off as ready. |
| REQ-007 | A recipe file exists but has never been driven successfully. | It is not presented as passing acceptance evidence. |
| REQ-007 | A catalog feature has not been assessed on one medium. | The report shows the feature-medium pair as uncovered rather than assuming not present. |
| REQ-008 | An override file contains an unknown field. | Resolution fails and identifies the source file and field. |
| REQ-008 | A project override conflicts with a machine override. | The project value wins and provenance is reportable. |
| REQ-009 | The managed GitHub credential is unavailable. | Local non-mutating work continues; mutation-dependent units record the blocker and restart command without alternate credentials. |
| REQ-009 | A branch passes locally but CI has not completed. | Its pull request remains draft and is not reported as CI-verified. |
| REQ-010 | Two authors need to update the same aggregate index. | Recipe authoring continues on disjoint files and one coordinator serializes the index update. |
| REQ-010 | Generated inventory contains a feature that has not been reviewed. | The report marks it unreviewed and excludes it from a completeness claim. |

## Non-Functional Requirements

| NFR | Threshold | Measurement |
|-----|-----------|-------------|
| Role-policy completeness | 100% of dispatching responsibilities resolve; 0 silent fallbacks | Run the committed role-policy validator against shipped defaults and an intentionally incomplete fixture. |
| Recipe structural integrity | 100% of committed entries contain all four required sections, a precondition, user entry points, action-operation-result bullets, catalog identity, and disposition | Run the committed recipe checker over every changed feature-map entry. |
| Catalog referential integrity | 0 unresolved feature identities at the Spellbook catalog revision | Run the committed reconciliation command against both repository-specific revisions. |
| Migration preservation | 0 unique procedural scenarios deleted without a recipe or explicit disposition | Run the committed migration report before and after each deletion batch. |
| Supported-medium readiness | 4 of 4 base skills resolve each readiness signal within `READINESS_DEADLINE` | Timestamp each readiness signal separately from recipe execution. |
| Supported-medium smoke proof | 4 of 4 base skills produce one PASS evidence record | Drive the committed smoke recipe for each member of `SUPPORTED_MEDIA`. |
| Dispatch accounting | 100% of background dispatches reserved before start | Compare dispatch records with run-state reservations at handoff. |
| Review provenance | 0 Claude calls and 0 claims of model diversity from Codex-only reviews | Inspect the run ledger and review reports at handoff. |
| Delivery safety | 0 merges, deployments, credential mutations, force-pushes, or destructive cleanups | Inspect GitHub PR state, run decisions, and local command records at handoff. |

## Glossary

| Term | Definition |
|------|------------|
| Base verification skill | The reusable driver for one user-facing medium. It owns launch, diagnosis, driving conventions, evidence, and cleanup, but not feature-specific behavior. |
| Feature catalog | The canonical Spellbook record of product capabilities and stable feature identities. |
| Feature-map entry | A committed, executable end-user recipe for one cataloged feature on one interaction medium, with an explicit coverage disposition and the four sections required by REQ-003. |
| Interaction medium | One exact member of `SUPPORTED_MEDIA`: `dashboard`, `cli-tui`, `cli-agent`, or `mcp`. |
| Honest verification | A fresh agent driving the real user-facing surface and recording observed evidence without relying on implementation knowledge. |
| Procedural QA runbook | A legacy document whose primary purpose is to tell a tester how to exercise a user-facing feature. It is a migration input, not current proof. |
| Operational runbook | A procedure for operating, diagnosing, recovering, or administering a system rather than verifying a product feature. It is not retired by this migration. |
| Verification selection | The run-scoped set of committed recipe identities and media that downstream Dark Factory stages must consume. |
| Covered | A feature-medium pair has a committed recipe that is structurally valid and eligible to be driven. It does not by itself mean the latest execution passed. |
| Not present | The feature is intentionally unavailable through that medium. |
| Deferred | The feature is present on that medium, but its recipe is intentionally scheduled for later work. |
| Blocked | The recipe cannot currently be authored or driven because a named prerequisite or external condition is unavailable. |
| Native stack | A GitHub-registered parent-child pull-request chain in which each child branch genuinely depends on its parent branch's content. |
| Planned delivery unit | One pull-request block in the checked implementation plan, including any later checked plan amendment. |
| Reachable delivery unit | A planned delivery unit with no named external blocker; an open parent pull request is a valid dependency and does not make its child unreachable. |
| Blocked delivery unit | A planned delivery unit that cannot proceed because a concrete external condition or blocked dependency is named with an exact restart procedure. |

## Constraints & Assumptions

- Dark Factory, Spellbook, and Spellguard remain separate repositories with
  separate pull requests.
- Spellbook owns canonical product feature identity; Spellguard owns executable
  verification recipes for its user-facing surfaces.
- Verification recipes and feature maps are committed project assets, not
  machine-local Dark Factory settings.
- Existing automated tests remain required and run before agent-driven
  verification where the lifecycle specifies that order.
- Live verification uses the real user-facing interaction medium and respects
  each repository's documented prerequisites and isolation rules.
- The initial feature catalog and initial recipe maps are incomplete by design;
  coverage grows with migration batches and future product changes.
- Claude model usage is unavailable for this run. Codex inline review and fresh
  Codex contexts provide context diversity only.
- Managed credentials may be used only when the existing approved credential is
  available. No privileged fallback may be retrieved or substituted.
- Repository CI configuration is not changed without separate explicit
  approval. A no-new-runbook check may land as a local repository check unless
  the operator later authorizes CI wiring.
- The work runs within `DISPATCH_BUDGET` and `WALL_CLOCK_BUDGET` and preserves
  exact restart instructions for anything still blocked at handoff.

## Decision Register

| # | Round | Finding | Severity | Decision | Reason |
|---|-------|---------|----------|----------|--------|
