# Project manifest schema

`.dark-factory/project.yaml` is how a target repo hands project context to the df skills. It
is a trust boundary (D27): it names files an agent will read and commands an agent will run,
and it can arrive on an untrusted branch. The schema is versioned and validated; a manifest
that fails validation is ignored with a stated warning, never partially obeyed.

## Version 1

```yaml
version: 1
project: spellguard

# Skill name, resolved from the repo's own skill directory
# (.agents/skills/ or .claude/skills/). Never a path outside the repo.
verification_skill: verify-spellguard

# Repo-relative directory of per-feature verification recipes.
feature_map: .agents/skills/verify-spellguard/features/

# Repo-local catalog only. Cross-repo catalogs enter as a pinned snapshot
# exported into this repo, never as a live pointer at a sibling checkout.
catalog: .dark-factory/catalog-snapshot.json

docs_root: docs/

# The only executable surface. df skills run commands by ID, never raw
# shell strings from the manifest. {path} is the one substitution and it
# is validated as a repo-relative path before use.
commands:
  test-focused: "pnpm exec vitest run {path}"
  test-full: "pnpm run test"
  test-integration: "pnpm run test:integration"
  typecheck: "pnpm run typecheck"
  lint: "pnpm run lint:check"
```

## Trust rules

1. Every path is repo-relative and canonical. No absolute paths, no `..`, no symlink that
   escapes the repo root. The validator canonicalizes and rejects escapes.
2. `commands` is the whole executable surface. A df skill that wants to run something the
   manifest does not name falls back to its own generic behavior and says so. `{path}` is
   the only substitution, validated before use.
3. Cross-repo product knowledge (the Spellbook catalog) enters as a snapshot file committed
   into this repo. The snapshot carries its source repo and commit, so staleness is visible.
   Live cross-repo pointers are rejected: sandbox roots differ per harness and per box, and
   a sibling-checkout path is a machine-specific assumption.
4. Project-local skills the manifest names run with the same trust as the repo's own code,
   which is what they are. A manifest edit is a code change and gets reviewed like one.
5. Unknown keys are rejected, not ignored. Schema growth bumps the version.

## Absent manifest

A repo with no manifest gets the full generic flow with no pre-context. Nothing requires
the manifest.
