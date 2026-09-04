# Cross-repository verification system design

## Usage first

### Resolve and freeze delegation policy

At run initialization, Dark Factory resolves every role the selected playbook
can dispatch. The result is stored with the external run, including the source
of each value.

```console
$ node scripts/df-role.mjs prepare-run \
    --run weekend-verification-2026-09-04 \
    --harness codex \
    --repo-root /home/dev/dark-factory
ROLE_PLAN=<run-dir>/work/role-plan.json
STATUS=ready
```

Before each dispatch, the caller resolves one responsibility from that frozen
plan. Resolution verifies the named local agent before the caller reserves a
dispatch.

```console
$ node scripts/df-role.mjs resolve \
    --run weekend-verification-2026-09-04 \
    --responsibility design_runners
KIND=named-agent
AGENT=terra_xhigh
SOURCE=shipped
STATUS=ready
```

Machine defaults come from
`${XDG_CONFIG_HOME:-$HOME/.config}/dark-factory/config.json`. A repository may
commit `.agents/dark-factory.json` when it needs a project override. Project
values win over machine values, which win over shipped defaults. The project
file may override role targets only; it cannot contain catalog paths, commands,
credentials, or run state.

### Seal and consume the verification selection

Coverage builds a complete draft from the approved PRD and committed recipes,
then seals it in the external run directory.

```console
$ node scripts/df-selection.mjs seal \
    --run weekend-verification-2026-09-04 \
    --draft <run-dir>/work/coverage-selection.json \
    --repo-root /home/dev/spellguard
SELECTION_REF=weekend-verification-2026-09-04:sha256:<digest>
ENTRIES=7
STATUS=sealed
```

Every downstream stage receives that reference. It never receives a copied
chat list and never discovers a replacement.

```console
$ node scripts/df-selection.mjs materialize \
    --ref weekend-verification-2026-09-04:sha256:<digest> \
    --repo-root /home/dev/spellguard \
    --format paths
```

If a PRD, skill, recipe, sub-feature, medium, or requirement mapping changes,
materialization fails with the changed field. Coverage must seal a new
selection and the affected stages rerun.

### Check Spellguard verification coverage

Spellguard keeps one index skill and one base skill per medium. A recipe file
owns one catalog feature on one medium. Missing files remain visibly unassessed;
the checker does not manufacture them.

```console
$ pnpm verification:check
catalog_revision=<spellbook sha>
product_source_revision=<spellguard sha>
covered=<n>
not_present=<n>
deferred=<n>
blocked=<n>
unassessed=<n>
```

The first runbook migration produces an inventory and mapping report. A
procedural feature-QA file is removable only when every unique scenario maps to
a committed recipe or explicit disposition.

```console
$ pnpm verification:migration-report --base origin/main
$ pnpm verification:no-new-runbooks --base origin/main
```

## Shape

### Role contract

One machine-readable shipped policy is the normative role source. Human-facing
model-policy documentation explains the rules and links to it; it does not
carry a second table that can drift.

```ts
type Harness = "claude" | "codex";
type Lane = "quick" | "standard" | "high-consequence";
type Responsibility =
  | "session_router"
  | "orchestrator"
  | "menial_scoped_investigation"
  | "implementation_delegate"
  | "judgment_delegate"
  | "investigation_synthesizer"
  | "design_runners"
  | "discovery_reviewers"
  | "recheck_leaf_reviewers"
  | "eval_graders"
  | "persona_reviewers_cli"
  | "cross_model_review";

type RoleTarget =
  | { kind: "session" }
  | { kind: "named-agent"; agent: string }
  | { kind: "cli"; model: string | null; effort: string | null }
  | { kind: "transport"; name: string };

type PolicySource = Readonly<{
  kind: "shipped" | "machine" | "project";
  path: string;
}>;

type ResolvedRole = Readonly<{
  harness: Harness;
  responsibility: Responsibility;
  lane: Lane;
  target: RoleTarget;
  provenance: readonly PolicySource[];
}>;

type FrozenRolePlan = Readonly<{
  schemaVersion: 1;
  runId: string;
  harness: Harness;
  policyDigest: string;
  resolutions: readonly ResolvedRole[];
}>;
```

```ts
function prepareRunRolePlan(input: {
  runId: string;
  harness: Harness;
  repoRoot: string;
}): FrozenRolePlan {
  throw new Error("not implemented");
}

function resolveFrozenRole(input: {
  runId: string;
  responsibility: Responsibility;
  lane: Lane;
}): ResolvedRole {
  throw new Error("not implemented");
}

function validateRolePolicy(input: {
  harness: Harness;
  repoRoot: string;
  codexAgentsDir?: string;
  claudeAgentsDir?: string;
}): void {
  throw new Error("not implemented");
}
```

Each dispatching skill marks its responsibility with a stable machine-readable
role reference. The policy checker extracts those references from both skill
trees and fails on an unmapped responsibility. It also validates the three
layered config shapes and verifies every named agent definition. A pinned
native effort stays inside a named-agent definition; callers do not rebuild a
model/effort pair.

The frozen plan prevents restart-time configuration drift. Availability is
still checked immediately before reservation because an agent definition can
disappear after initialization. Missing agents stop before `df-state reserve`.

### Verification selection contract

The selection is canonical JSON stored once at
`<run-dir>/verification-selections/<sha256>.json`. Its digest is its identity.
Coverage is the only writer; every later stage is a read-only consumer.

```ts
type Medium = "dashboard" | "cli-tui" | "cli-agent" | "mcp";
type RecipeIdentity = string & { readonly recipeIdentity: unique symbol };
type SelectionDigest = string & { readonly selectionDigest: unique symbol };

type SelectionEntry = Readonly<{
  id: string;
  medium: Medium;
  skillPath: string;
  skillSha256: string;
  recipePath: string;
  subFeature: string | null;
  recipeSha256: string;
  requirementIds: readonly string[];
  negativeRequirementIds: readonly string[];
}>;

type VerificationSelection =
  | Readonly<{
      schemaVersion: 1;
      kind: "user-facing";
      runId: string;
      featureSlug: string;
      prdPath: string;
      prdSha256: string;
      catalogLinkPath: string;
      catalogLinkSha256: string;
      entries: readonly [SelectionEntry, ...SelectionEntry[]];
    }>
  | Readonly<{
      schemaVersion: 1;
      kind: "no-user-route";
      runId: string;
      featureSlug: string;
      prdPath: string;
      prdSha256: string;
      reason: string;
      entries: readonly [];
    }>;

type SelectionRef = Readonly<{
  runId: string;
  digest: SelectionDigest;
}>;
```

```ts
function sealSelection(input: {
  runId: string;
  draftPath: string;
  repoRoot: string;
}): SelectionRef {
  throw new Error("not implemented");
}

function openSelection(input: {
  ref: SelectionRef;
  repoRoot: string;
}): VerificationSelection {
  throw new Error("not implemented");
}

function materializeSelection(input: {
  ref: SelectionRef;
  repoRoot: string;
  consumer: "qa-validation" | "dev-verify" | "code-review" | "acceptance";
}): readonly SelectionEntry[] {
  throw new Error("not implemented");
}
```

Canonicalization sorts entries by medium, recipe path, and sub-feature and sorts
requirement IDs inside each entry. The sealer validates all referenced files
and hashes before an atomic rename. A reader validates the content digest and
all referenced content hashes before returning entries. It never falls back to
`latest` or current map discovery.

Acceptance expands each selected entry into entry-point legs by reading the
sealed recipe. It writes new evidence under
`<run-dir>/acceptance/<selection-digest>/`. Existing committed acceptance
records remain historical and unchanged. This separates the reusable recipe,
the frozen per-run proof set, and what one execution observed.

### Spellbook link and Spellguard project assets

The index skill owns a small generated projection, not a second product catalog.

```ts
type CatalogLink = Readonly<{
  schemaVersion: 1;
  spellbook: {
    repository: "Spellguard/spellbook";
    catalogRevision: string;
  };
  spellguard: {
    repository: "Spellguard/spellguard-internal";
    productSourceRevision: string;
  };
  snapshotSha256: string;
}>;

type FeatureMediumDisposition =
  | { kind: "covered" }
  | { kind: "not-present"; reason: string }
  | { kind: "deferred"; reason: string }
  | { kind: "blocked"; prerequisite: string };
```

```text
.agents/skills/verify-spellguard/
  SKILL.md
  references/catalog-link.json
  references/catalog-snapshot.json
  references/coverage-report.md
  scripts/check.mjs
  scripts/report.mjs
  scripts/migration-report.mjs
  scripts/no-new-runbooks.mjs

.agents/skills/verify-spellguard-dashboard/
  SKILL.md
  features/README.md
  features/<CATALOG-ID>.md

.agents/skills/verify-spellguard-cli-tui/
  SKILL.md
  features/README.md
  features/<CATALOG-ID>.md

.agents/skills/verify-spellguard-cli-agent/
  SKILL.md
  features/README.md
  features/<CATALOG-ID>.md

.agents/skills/verify-spellguard-mcp/
  SKILL.md
  features/README.md
  features/<CATALOG-ID>.md
```

Each catalog-feature/medium pair has at most one file. Covered files contain the
four required recipe sections. An assessed non-covered file carries one of
`not-present`, `deferred`, or `blocked` with its reason and has no fake driving
instructions. A missing file is derived as `unassessed`, never silently
converted to another disposition.

Each medium skill owns Launch, Doctor, Drive, Evidence, and Cleanup plus a
90-second deadline per readiness signal. Dashboard uses the real browser
surface. CLI TUI uses real TTY isolation. CLI agent uses explicit structured
output and proves it never enters TUI. MCP keeps offline catalog parity and
hosted-client effects as distinct recipes.

`catalog-snapshot.json` is generated from the exact Spellbook catalog revision
and contains only stable IDs, active/retired state, and redirect targets needed
for validation. It omits product descriptions. The checker reads
`data/source-pin.json` at the catalog revision and requires it to equal the
link's product-source revision. Ancestry is checked only between Spellguard
commits. Later user-facing Spellguard source changes make the report stale.

The report cross-joins the generated snapshot with the four media, scans the
per-medium feature files, and reports covered, not-present, deferred, blocked,
and unassessed separately. Recipe authors write disjoint `<CATALOG-ID>.md`
files. One coordinator regenerates the shared snapshot, report, and indexes.

### Runbook migration

The migration generator inventories files and extracts stable scenario anchors;
it does not decide which documents are procedural feature QA. An authored
classification maps each source to `procedural-feature-qa`, `historical-evidence`,
`operational`, or `release`. Only the first class enters recipe migration.

```ts
type RunbookClass =
  | "procedural-feature-qa"
  | "historical-evidence"
  | "operational"
  | "release";

type MigratedScenario = Readonly<{
  sourcePath: string;
  anchor: string;
  classification: RunbookClass;
  recipeIdentity: RecipeIdentity | null;
  disposition: Exclude<FeatureMediumDisposition, { kind: "covered" }> | null;
}>;
```

Deletion validation fails when a removed procedural file has a scenario with
neither a recipe identity nor an explicit disposition. The no-new-runbook check
compares the branch to its base and rejects new procedural feature-QA documents.
It does not reject operational, release, or historical evidence. The local
check lands first; CI wiring requires separate operator approval.

### Lifecycle consumers

- `df-verify-coverage` validates and seals the selection, then returns its
  `SelectionRef` and compact summary.
- `df-qa-validation` accepts PRD plus `SelectionRef`; its inline and fresh Codex
  reviews receive all selected recipes.
- `df-dev-verify` refuses missing selections and drives each selected medium's
  base skill. Browser-specific logic exists only in the dashboard skill.
- `df-code-review` includes the selection digest in its report and compares the
  PRD, diff, and selected recipes. It no longer discovers a slug-named runbook.
- `df-acceptance` uses the same reference, expands entry points, and writes one
  terminal result per leg without widening the set.
- No lifecycle stage accepts the removed singular `qa-path` ABI after its
  migration PR.

### Module ownership

| Owner | Responsibility |
|---|---|
| `references/model-policy.json` | Normative shipped roles for both harnesses |
| `scripts/df-role.mjs` | Layered config, role-plan freezing, resolution, and agent preflight |
| `scripts/check-model-policy.mjs` | Role-call inventory and totality validation |
| `scripts/df-selection.mjs` | Selection validation, canonicalization, atomic sealing, and reading |
| `references/verification-selection.schema.json` | Versioned selection wire contract |
| `df-verify-coverage` | Sole selection writer |
| QA validation, dev verification, code review, acceptance | Read-only selection consumers |
| Spellbook | Canonical product catalog and source provenance |
| Spellguard index skill | Catalog projection, aggregate validation, and reports |
| Four Spellguard medium skills | Surface lifecycle and per-medium feature files |
| Migration classifier | Runbook category and scenario mappings |
| Dark Factory plan/open-PR stages | Real dependency graph and optional native stack registration |

## Interface depth

Callers provide one responsibility or one `SelectionRef`. They do not coordinate
config precedence, agent-definition lookup, canonical JSON, state paths, recipe
hashes, catalog checkouts, or evidence locations. `df-role.mjs` is deep because
it completes resolution and preflight. `df-selection.mjs` is deep because it
owns the full immutable-selection invariant. Spellguard's index skill is deep
because it joins catalog provenance and four independent medium maps behind one
check/report interface.

The design avoids temporal decomposition: selection load, validation, hashing,
and sealing remain one module because they protect one representation. It avoids
information leakage: downstream stages never parse raw run-store layout, and
medium drivers never perform catalog joins. It avoids pass-through wrappers:
each public command enforces policy beyond forwarding arguments.

## Synthesis decision

Candidate A's sealed selection is the base. It gives shell runners and humans
one inspectable immutable object, keeps the consumer interface small, and makes
recipe drift fail mechanically. Candidate B's row ledger was rejected because
ordinary consumers would depend on projection and sealing joins to understand
one selection.

Two Candidate B ideas were grafted into the base. First, resolved roles freeze
once per run, with an availability recheck before each reservation. This keeps
resume behavior stable without hiding a deleted agent definition. Second,
Spellguard coverage ownership stays federated as one feature file per medium
and catalog ID. The aggregate checker alone performs the cross-medium join,
which removes shared authoring files from the later fan-out.

The candidates were screened against the design red flags. The chosen modules
hide substantial validation behind small commands, no caller coordinates
temporal stages, storage and catalog representations stay private, and no
wrapper exists only to pass the same arguments onward.

## Tradeoffs accepted

- We accept canonical JSON in external run state in exchange for a restart-safe,
  inspectable closed handoff.
- We accept resealing after any recipe or PRD change in exchange for never
  changing the measured procedure mid-run.
- We accept a frozen role plan plus pre-dispatch availability checks in exchange
  for stable restarts without silent fallback.
- We accept up to one small feature file per catalog-feature/medium pair in
  exchange for unambiguous ownership and conflict-free recipe fan-out.
- We accept a generated minimal catalog snapshot in Spellguard in exchange for
  reproducible validation without making Spellguard a second catalog owner.
- We accept external evidence for new runs while preserving existing committed
  historical evidence unchanged.

## Alternatives considered

- Append-only selection rows expose joins and seal completeness to every
  consumer. They provide good audit history but a shallower consumption API.
- Conversation-only handoff loses restart safety and permits downstream
  reconstruction.
- One central coverage file creates shared write contention during catalog-wide
  expansion.
- Auto-discovering a broad project manifest repeats the removed design. The
  narrow tracked project override contains role targets only.
- Per-runner model flags repeat policy and operational exceptions at each call
  site.

## Open questions and risks

- Existing committed acceptance evidence remains historical, but the exact
  migration note that freezes its policy must land with the acceptance change.
- The Spellbook source-pin reconciliation must complete before any broad
  current-coverage claim.
- CI wiring for the no-new-runbook check remains out of scope until separately
  approved.
- Native stack registration can fail its capability probe. The ordinary PR
  chain remains authoritative.
- A GitHub cascading rebase changes head SHAs and invalidates prior checks for
  affected PRs.

## Next implementation step

Add the normative role policy and its totality validator, then make one runner
consume the resolver before expanding the selection contract.
