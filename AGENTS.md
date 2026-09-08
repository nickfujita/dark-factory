# Dark Factory repository rules

Dark Factory is an independent workflow plugin. Its committed content must be
usable without knowledge of any consuming application, organization, or VM.

## Project independence

- Do not commit consuming-project names, repository URLs, feature IDs, catalog
  revisions, application paths, credentials, deployment details, QA inventories,
  migration batches, or execution status in this repository.
- Keep product-specific requirements, catalogs, verification skills, and feature
  recipes in the consuming repository. Keep cross-repository execution plans,
  operator-local prerequisites, run budgets, and evidence in external run state.
- Dark Factory may discover and consume project-owned verification assets at
  runtime through declared inputs. Do not hardcode a product, its catalog
  layout, its supported media, or its tooling into shared workflow contracts.
- Use clearly synthetic fixtures and generic examples for shared contracts.
  Renaming a real application is not enough if its domain assumptions remain.
- References to Dark Factory itself, supported agent platforms, upstream
  dependencies, and verification tools are allowed when they explain actual
  integration behavior. They must not encode a consuming project's configuration.
- Before publishing a change, inspect the full diff, examples, and PR body for
  application-specific assumptions. Remove or relocate them before handoff.

## Shared instruction trees

Claude instructions live in `skills/`. Codex instructions live in
`codex-plugin/skills/`. Apply shared policy changes to both trees and run the
repository's parity checks. Preserve intentional harness-specific differences.

## Git and CI

- Use a feature branch. Never push directly to main, force-push, or merge PRs.
- Keep incomplete work draft. Mark a PR ready only after local work is complete,
  then own its final CI checks. The human reviews and merges.
- Do not change CI configuration without explicit approval.

See `CLAUDE.md` for repository layout and installation details.
