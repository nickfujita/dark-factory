# Project-independent verification lifecycle design

This is a proposed interface design, not implemented behavior. The consuming
project supplies its own verification assets and runtime prerequisites.

## Usage first

### Resolve and freeze delegation policy

At run initialization, Dark Factory resolves every responsibility for the
selected harness across all supported lanes. The external role plan stores
one row per responsibility and lane, including the source of each value.

```console
$ node scripts/df-role.mjs prepare-run \
    --run example-run \
    --harness codex \
    --repo-root <workflow-repo>
ROLE_PLAN=<run-dir>/work/role-plan.json
STATUS=ready
```

Before each dispatch, the caller resolves one responsibility from that frozen
plan. Resolution verifies the named local agent before the caller reserves a
dispatch.

```console
$ node scripts/df-role.mjs resolve \
    --run example-run \
    --responsibility design_runners \
    --lane standard
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
    --run example-run \
    --draft <run-dir>/work/coverage-selection.json \
    --repo-root <project-root>
SELECTION_REF=example-run:sha256:<digest>
ENTRIES=7
STATUS=sealed
```

Every downstream stage receives that reference. It never receives a copied
chat list and never discovers a replacement.

```console
$ node scripts/df-selection.mjs materialize \
    --ref example-run:sha256:<digest> \
    --repo-root <project-root> \
    --consumer qa-validation \
    --format paths
```

If a PRD, skill, recipe, sub-feature, medium, or requirement mapping changes,
materialization fails with the changed field. Coverage must seal a new
selection and the affected stages rerun.

### Discover project verification inputs

The project supplies its base skills, stable recipe identities, declared media,
and optional catalog-provenance check. Dark Factory reads those declarations;
it does not assume a package manager, command name, catalog layout, product
schema, or fixed number of media.

Synthetic fixtures cover projects with one medium, multiple media, and no
catalog. A missing recipe stays unassessed. Project-owned migration checks
report whether unique legacy scenarios remain unmapped. Neither a catalog entry
nor an existing recipe proves that a live drive passed.

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

The role plan has no singular lane field. Preparation freezes the full
responsibility-by-lane matrix for its harness. Resolution and preflight require
an explicit lane and reject a missing matrix row before reservation.

The frozen plan prevents restart-time configuration drift. Availability is
still checked immediately before reservation because an agent definition can
disappear after initialization. Missing agents stop before `df-state reserve`.

### Verification selection contract

The selection is canonical JSON stored once at
`<run-dir>/verification-selections/<sha256>.json`. Its digest is its identity.
Coverage is the only writer; every later stage is a read-only consumer.

```ts
type Medium = string; // Validated against the project-declared identifier set.
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

type SelectionDraft =
  | Readonly<{
      schemaVersion: 1;
      kind: "user-facing";
      runId: string;
      featureSlug: string;
      prdPath: string;
      prdSha256: string;
      catalogLink: Readonly<{ path: string; sha256: string }> | null;
      declaredMedia: readonly [Medium, ...Medium[]];
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

// The sealer derives this from its validated repoRoot argument. Draft JSON
// cannot supply it, so a run's evidence remains bound to one worktree.
type VerificationSelection = SelectionDraft & Readonly<{
  repoRoot: string; // Canonical absolute repository root.
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

Coverage supplies `declaredMedia` from the project's own declared input set; it
does not infer media from directory names. The draft is caller-authored, while
the sealer adds the canonical absolute `repoRoot` after validating its argument.
Canonicalization uses locale-independent raw string order for declared media,
entries by medium, recipe path, and sub-feature (with null first), and
requirement IDs inside each entry. The sealer validates all referenced files
and hashes before an atomic no-clobber publication. A reader validates the
stored repository root before source hashes and never falls back to `latest` or
current map discovery.

`verification-selection.schema.json` validates the wire shape and scalar
constraints that JSON Schema can express. It is not a selection reader: only
the shared helper validates medium membership, selected-recipe identity,
canonical ordering and bytes, source files, and real run-store containment.
Selection references additionally reject `.` and `..` run IDs even though the
generic state helper accepts a broader run identifier grammar.

Acceptance expands each selected entry into entry-point legs by reading the
sealed recipe. It writes new evidence under
`<run-dir>/acceptance/<selection-digest>/`. Existing committed acceptance
records remain historical and unchanged. This separates the reusable recipe,
the frozen per-run proof set, and what one execution observed.

The CLI maps `seal --run --draft --repo-root` to `sealSelection` and
`inspect --ref --repo-root` to `openSelection`. The command
`materialize --ref --repo-root --consumer --format` calls
`materializeSelection`. Its consumer is exactly `qa-validation`, `dev-verify`,
`code-review`, or `acceptance`. JSON format emits the returned entry array;
paths format emits one JSON tuple `[medium, recipePath, subFeature]` per line,
so it preserves distinct selected sub-features. Neither format rediscovers
recipes. The CLI parses its textual ref; the public APIs receive a
`SelectionRef` object in every `ref` argument.

### Project-owned catalog and migration checks

Dark Factory consumes project-declared inputs without owning their storage or
implementation. A catalog link is optional. When present, its project-owned
checker resolves catalog and product revisions in their respective repositories
and reports provenance. The selection hashes the committed link so later stages
cannot silently switch it. A null link explicitly means no catalog is configured.

The consuming project owns these responsibilities:

- Canonical feature identity and product descriptions.
- Catalog projection, revision resolution, freshness, and redirect checks.
- Base skill per declared medium, including launch, diagnosis, driving, evidence,
  readiness deadlines, and authorized cleanup.
- Per-feature recipes and separate coverage dispositions.
- Legacy scenario classification, migration mappings, and retirement checks.

The generic disposition contract separates a recipe eligible to be driven from
`not-present`, `deferred`, and `blocked`. Missing assessments remain unassessed.
A live PASS, FAIL, or BLOCKED result is a different record.

Dark Factory refuses a current-coverage claim when a configured project check
reports stale or divergent provenance. An unmapped legacy scenario prevents
retirement of that scenario, not unrelated recipe authoring. Historical evidence
and operational procedures remain outside procedural feature-QA retirement.

No product-specific catalog schema, check command, folder convention, deployment,
or migration inventory ships as part of this design. Test these boundaries with
synthetic repositories and caller-supplied check results.

### Lifecycle consumers

- `df-verify-coverage` validates and seals the selection, then returns its
  `SelectionRef` and compact summary.
- `df-qa-validation` accepts PRD plus `SelectionRef`; its inline and fresh Codex
  reviews receive all selected recipes.
- `df-dev-verify` refuses missing selections and drives each selected medium's
  base skill. Tool-specific logic exists only in the project-declared skill.
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
| Consuming project | Optional catalog, provenance checks, media, skills, recipes, and migration mappings |
| Dark Factory plan/open-PR stages | Real dependency graph and optional native stack registration |

## Interface depth

Callers provide one responsibility or one `SelectionRef`. They do not coordinate
config precedence, agent-definition lookup, canonical JSON, state paths, recipe
hashes, catalog checkouts, or evidence locations. `df-role.mjs` is deep because
it completes resolution and preflight. `df-selection.mjs` is deep because it
owns the full immutable-selection invariant. Project-owned checkers keep their
catalog and migration representations behind declared inputs.

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
Project recipe ownership stays separate per medium and stable feature identity. The aggregate checker alone performs the cross-medium join,
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
- We accept up to one small feature file per stable feature-identity/medium pair in
  exchange for unambiguous ownership and conflict-free recipe fan-out.
- Project-owned catalog projections may support reproducible validation without
  creating a second canonical catalog inside Dark Factory.
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
- A configured project provenance check must succeed before a current-coverage
  claim. Dark Factory does not repair the project's source history.
- CI wiring for the no-new-runbook check remains out of scope until separately
  approved.
- Native stack registration can fail its capability probe. The ordinary PR
  chain remains authoritative.
- A GitHub cascading rebase changes head SHAs and invalidates prior checks for
  affected PRs.

## Next implementation step

Add the normative role policy and its totality validator, then make one runner
consume the resolver before expanding the selection contract.
