# PRD: Project-independent verification lifecycle

**Status:** Draft scope correction. Prior cross-repository approval does not approve this revised scope.
**Lane:** Standard
**Feature ID:** verification-system

## Declared inputs

| Parameter | Source | Applies to |
|-----------|--------|------------|
| `SUPPORTED_MEDIA` | Nonempty set of exact identifiers declared by the project verification system | REQ-002, REQ-003, and REQ-006 |
| `SMOKE_RECIPES_PER_MEDIUM` | At least one for each declared medium | REQ-002 |
| `READINESS_DEADLINE` | Finite deadline declared by each project skill | REQ-002 |

Run duration, dispatch budgets, provider availability, and review-family
constraints belong to external run state. They are not constants in this PRD.

**Reading conventions.** Requirements and Negative Requirements are normative.
Acceptance criteria, Edge Cases, the Glossary, and examples are satellites:
they may repeat a value, and they may never restate a rule or introduce behavior
that has no normative home.

## Purpose

Dark Factory must hand a fresh verifier the same committed recipes selected
during planning, then preserve what that verifier actually observed. The
workflow must support projects with different catalogs, interaction media,
tools, and development environments without knowing their product identities.

Recipes complement automated tests. A recipe describes an end-user procedure;
it is not evidence that a particular execution passed.

## Scope

### In scope

- Complete role resolution with working shipped defaults and explicit overrides.
- Restart-safe role plans and immutable, plural verification selections.
- Discovery of project-owned skills, recipes, optional catalog provenance, and
  migration checks through declared inputs.
- Shared planning, coverage, QA validation, developer verification, code review,
  and acceptance instructions that consume those inputs.
- Synthetic fixtures that prove these generic contracts without an application
  checkout, credential, catalog, backend, or deployment.

### Outside this repository

The consuming project owns its catalog and provenance format, concrete base
skills, feature recipes, coverage reports, migration inventory, driver choices,
readiness deadlines, and safety constraints. Requirements below describe how
Dark Factory discovers and consumes those assets. They do not authorize this
repository to implement or store a particular product's verification system.

Product migration plans and actual run status stay in their owning repositories
or external run state. This change does not merge PRs, deploy, alter credentials,
change CI configuration, delete evidence, or replace automated testing.

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
1. Dark Factory discovers exactly one project-owned base verification skill
   for each member of the project's declared `SUPPORTED_MEDIA`.
2. The project skill contract defines `Launch`, `Doctor`, `Drive`, `Evidence`, and
   `Cleanup` sections for its medium.
3. Each base skill delegates feature-specific actions and expected outcomes to
   committed feature-map entries.
4. Each base skill includes at least `SMOKE_RECIPES_PER_MEDIUM` live-drive
   recipe that proves the driver reaches the intended surface.
5. Each `Launch` readiness signal resolves within `READINESS_DEADLINE`; when it
   does not, the skill records BLOCKED with timeout evidence and follows its
   authorized cleanup procedure. Resources that cannot be cleaned up safely
   remain preserved and are reported.

Acceptance:
- The verification index resolves exactly one base skill for each supported
  medium.
- Each base skill's readiness procedure distinguishes an unavailable surface
  from a product failure.
- Each base skill produces a PASS evidence record from its committed smoke
  recipe.
- A readiness signal that exceeds `READINESS_DEADLINE` produces a BLOCKED
  evidence record and runs the skill's cleanup procedure.
- Each base skill's cleanup procedure closes its authorized verification-owned
  sessions or explicitly records why a resource remains preserved.

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
1. If the project uses a catalog, the project declares its canonical owner and
   committed reference. Dark Factory does not select a catalog service, path,
   schema, repository, feature taxonomy, or projection command.
2. Catalog and product-source revisions remain distinct. Each resolves in its
   owning repository. Ancestry checks compare only product-source revisions.
3. Dark Factory consumes the project's provenance check and blocks a current
   coverage claim when it reports missing, divergent, stale, or unreviewed data.
4. Recipes reference stable catalog identities instead of duplicating canonical
   descriptions. Redirects do not count as verified coverage.
5. A project without a catalog declares that fact. It still supplies stable
   recipe identities and requirement mappings; catalog absence cannot invent
   identities or remove a changed user route from verification.

Acceptance:
- Synthetic fixtures with separate catalog and product histories never perform
  a cross-repository ancestry comparison.
- A project-provided stale or divergent result prevents a current-coverage claim.
- An unknown catalog identity is rejected when a catalog is configured.
- Redirects remain separate from coverage.
- A no-catalog project can seal recipes and requirement mappings without a
  fabricated catalog link.

---

### REQ-005: Legacy QA Runbook Migration

**Priority:** P0

Behavior:
1. Dark Factory uses project-owned procedural QA runbooks only as migration
   inputs. The consuming project owns classification, inventory, mapping,
   retirement, and any repository-specific migration check.
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
2. Planning and coverage use exact project-declared medium identifiers.
   Distinct interactive and noninteractive routes require distinct identifiers
   when their user actions or observations differ.
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
- Coverage rejects an identifier that combines distinct user routes.
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

### REQ-009: Reviewable delivery

**Priority:** P0

Behavior:
1. Each run records its operator-approved budgets, provider restrictions, and
   authorized actions outside the repository before dispatch.
2. Every dispatch is reserved before it starts. Exhausted budgets stop new work.
3. Review reports name the actual model families used and any deferred leg.
   A fresh context from the same family is not model diversity.
4. Every planned delivery unit has a PR disposition or a concrete blocker with
   preserved work and restart instructions.
5. Independent PRs branch from main. Only real source dependencies form stacks.
6. Incomplete local work remains draft. After local verification and review,
   mark the PR ready for human review and own final CI to completion.
7. Before dependent implementation or publication, complete lower PRs' agent-owned
   gates at their exact heads. Human approval and merge may remain pending.
8. A repository with no required CI records evidence-backed `NOT_CONFIGURED`,
   not PASS. The operator merges every PR.

Acceptance:
- Synthetic dispatch fixtures show reservation before worker start.
- A same-family review never claims cross-family validation.
- Incomplete predecessors block dependent dispatch and publication.
- A locally complete PR starts its CI watcher when marked ready.
- A completed lower PR permits dependent work while human review remains pending.
- Missing required checks stay unresolved; absent CI configuration is explicit.

---

### REQ-010: Catalog-Wide Expansion After Foundation

**Priority:** P1

Behavior:
1. Project recipe authoring can fan out for an accepted medium after its base
   skill, representative live recipe, provenance checks where applicable, and
   migration boundary are verified. Other media remain independently gated.
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

### REQ-011: Repository independence

**Priority:** P0

Behavior:
1. Committed Dark Factory contracts, skills, fixtures, plans, and examples contain
   no consuming-project identities, source revisions, feature inventories,
   deployment assumptions, or operator-local paths.
2. Concrete project values arrive only through explicit runtime inputs and
   project-owned verification assets. Synthetic fixtures exercise those inputs.
3. A project-specific integration requirement stays with its owning project.

Acceptance:
- Review of the branch and PR body finds only reusable workflow requirements.
- All planned Dark Factory verification can be prepared without a real consuming
  application's checkout, catalog, credentials, or services.
- Both harness instruction trees honor the same ownership boundary.

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
- One identifier must not combine routes with different user actions or observations.
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

- Dark Factory must not become a canonical product-feature catalog.
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
| REQ-004 | The product-source revision predates user-facing changes on the target project base. | Reconciliation marks the coverage report stale until those changes are reviewed into the catalog. |
| REQ-004 | The catalog revision and product-source revision differ. | Each resolves in its own repository; no cross-repository ancestry comparison is attempted. |
| REQ-004 | A catalog identity redirects to another identity. | Reconciliation records the redirect without counting it as a verified recipe. |
| REQ-005 | A legacy file mixes procedural scenarios with operational recovery steps. | Only migrated procedural content is retired; operational content remains in an appropriate document. |
| REQ-005 | Two runbooks describe the same scenario. | Migration records one canonical recipe and both source mappings before duplicate removal. |
| REQ-006 | A change affects two supported media. | Selection, validation, developer verification, review, and acceptance retain both recipe identities. |
| REQ-006 | Existing coverage classifies a route as `CLI or TUI`. | The handoff blocks until distinct user routes have distinct project-declared identifiers. |
| REQ-006 | A user route uses an undeclared medium. | The handoff blocks until the project declares a matching skill and route. |
| REQ-006 | Automated tests pass but a live recipe fails. | The unit remains unverified and is not handed off as ready. |
| REQ-007 | A recipe file exists but has never been driven successfully. | It is not presented as passing acceptance evidence. |
| REQ-007 | A catalog feature has not been assessed on one medium. | The report shows the feature-medium pair as uncovered rather than assuming not present. |
| REQ-008 | An override file contains an unknown field. | Resolution fails and identifies the source file and field. |
| REQ-008 | A project override conflicts with a machine override. | The project value wins and provenance is reportable. |
| REQ-009 | The managed GitHub credential is unavailable. | Local non-mutating work continues; mutation-dependent units record the blocker and restart command without alternate credentials. |
| REQ-009 | Local work is complete but CI is pending. | Mark ready for human review, own the CI watcher, and block dependent work until agent-owned gates pass. |
| REQ-010 | Two authors need to update the same aggregate index. | Recipe authoring continues on disjoint files and one coordinator serializes the index update. |
| REQ-010 | Generated inventory contains a feature that has not been reviewed. | The report marks it unreviewed and excludes it from a completeness claim. |

## Non-Functional Requirements

| NFR | Threshold | Measurement |
|-----|-----------|-------------|
| Role-policy completeness | 100% of dispatching responsibilities resolve; 0 silent fallbacks | Run the committed role-policy validator against shipped defaults and an intentionally incomplete fixture. |
| Recipe structural integrity | 100% of committed entries contain all four required sections, a precondition, user entry points, action-operation-result bullets, stable identity, and disposition | Run the committed recipe checker over every changed feature-map entry. |
| Catalog referential integrity | 0 unresolved feature identities when a catalog is configured | Run the committed reconciliation command against both repository-specific revisions. |
| Migration preservation | 0 unique procedural scenarios deleted without a recipe or explicit disposition | Run the committed migration report before and after each deletion batch. |
| Supported-medium readiness | Every declared base skill resolves each readiness signal within `READINESS_DEADLINE` | Timestamp each readiness signal separately from recipe execution. |
| Supported-medium smoke proof | Every declared base skill produces a representative PASS evidence record | Drive the committed smoke recipe for each member of `SUPPORTED_MEDIA`. |
| Dispatch accounting | 100% of background dispatches reserved before start | Compare dispatch records with run-state reservations at handoff. |
| Review provenance | 0 claims of review diversity not supported by the actual model families | Inspect the run ledger and review reports at handoff. |
| Delivery safety | 0 merges, deployments, credential mutations, force-pushes, or destructive cleanups | Inspect GitHub PR state, run decisions, and local command records at handoff. |

## Glossary

| Term | Definition |
|------|------------|
| Base verification skill | The reusable driver for one user-facing medium. It owns launch, diagnosis, driving conventions, evidence, and cleanup, but not feature-specific behavior. |
| Feature catalog | A project-owned canonical record of product capabilities and stable feature identities. |
| Feature-map entry | A committed, executable end-user recipe for one stable feature identity on one interaction medium, with an explicit coverage disposition and the four sections required by REQ-003. |
| Interaction medium | One exact project-declared member of `SUPPORTED_MEDIA`; examples include a web dashboard, interactive terminal, structured CLI, or MCP client. |
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
| Reachable delivery unit | A planned delivery unit with no named external blocker; an open parent is usable only after its agent-owned readiness gates pass. |
| Blocked delivery unit | A planned delivery unit that cannot proceed because a concrete external condition or blocked dependency is named with an exact restart procedure. |

## Constraints and assumptions

- Project verification assets remain committed to their owning repositories.
- Run-specific settings, cross-repository plans, and evidence remain external.
- Automated tests and live user verification provide different evidence.
- Project prerequisites and cleanup permissions apply to every live drive.
- Initial catalogs and recipe maps may be incomplete; gaps stay visible.
- This revised PRD is a draft. Source review does not implement its requirements
  or approve an execution budget.
